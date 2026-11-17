-- A small, permission-checked read API keeps the static app from querying protected tables directly.
CREATE OR REPLACE FUNCTION public.erp_get_module_data(p_module text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_data jsonb;
BEGIN
  PERFORM private.erp_require_staff();
  CASE p_module
    WHEN 'inventory' THEN
      SELECT jsonb_build_object(
        'locations',COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.name) FROM public.locations l WHERE l.is_active),'[]'::jsonb),
        'products',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.sku,a.location_name) FROM public.get_inventory_availability() a),'[]'::jsonb),
        'costs',COALESCE((SELECT jsonb_agg(to_jsonb(c)) FROM public.get_inventory_costs() c),'[]'::jsonb),
        'movements',COALESCE((SELECT jsonb_agg(to_jsonb(m)) FROM public.get_inventory_movements(200) m),'[]'::jsonb)
      ) INTO v_data;
    WHEN 'pos' THEN
      SELECT jsonb_build_object(
        'products',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'sku',p.sku,'name',p.name,'category',p.category,
          'barcode',p.barcode,'price',p.price,'cost',p.cost,'reorder_point',p.reorder_point) ORDER BY p.name) FROM public.products p WHERE p.is_active),'[]'::jsonb),
        'tax_rate',COALESCE((SELECT setting_value FROM public.erp_system_settings WHERE setting_key='tax_rate'),'0.0825'::jsonb),
        'inventory',COALESCE((SELECT jsonb_agg(to_jsonb(a)) FROM public.get_inventory_availability() a),'[]'::jsonb),
        'customers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'email',c.email) ORDER BY c.name) FROM public.erp_customers c),'[]'::jsonb),
        'bom',COALESCE((SELECT jsonb_agg(jsonb_build_object('parent_product_id',b.parent_product_id,'component_product_id',b.component_product_id,'quantity_per',b.quantity_per)) FROM public.erp_bom b),'[]'::jsonb),
        'receipts',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'receipt_number',s.receipt_number,'customer_id',s.customer_id,
          'location_id',s.location_id,'subtotal',s.subtotal,'discount',s.discount,'tax',s.tax,'total',s.total,'cogs',s.cogs,
          'source',s.source,'created_at',s.created_at,'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('sku',p.sku,'name',p.name,
          'quantity',sl.quantity,'unit_price',sl.unit_price,'unit_cost',sl.unit_cost) ORDER BY p.sku)
          FROM public.pos_sale_lines sl JOIN public.products p ON p.id=sl.product_id WHERE sl.sale_id=s.id),'[]'::jsonb))
          ORDER BY s.created_at DESC) FROM (SELECT * FROM public.pos_sales ORDER BY created_at DESC LIMIT 100) s),'[]'::jsonb)
      ) INTO v_data;
    WHEN 'sales_orders' THEN
      SELECT jsonb_build_object(
        'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'order_number',o.order_number,'status',o.status,'channel',o.channel,
          'customer_id',o.customer_id,'customer_name',c.name,'location_id',o.location_id,'location_name',l.name,'placed_at',o.placed_at,
          'required_by',o.required_by,'subtotal',o.subtotal,'total',o.total,'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id',x.id,'product_id',x.product_id,'sku',p.sku,'product_name',p.name,'quantity',x.quantity,'quantity_fulfilled',x.quantity_fulfilled,
          'quantity_backordered',x.quantity_backordered,'estimated_available_date',x.estimated_available_date,'unit_price',x.unit_price)
          ORDER BY p.sku) FROM public.erp_sales_order_lines x JOIN public.products p ON p.id=x.product_id WHERE x.order_id=o.id),'[]'::jsonb))
          ORDER BY o.placed_at DESC) FROM public.erp_sales_orders o LEFT JOIN public.erp_customers c ON c.id=o.customer_id
          JOIN public.locations l ON l.id=o.location_id),'[]'::jsonb),
        'customers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'email',email) ORDER BY name) FROM public.erp_customers),'[]'::jsonb),
        'products',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'sku',sku,'name',name,'price',price,'barcode',barcode) ORDER BY name)
          FROM public.products WHERE is_active),'[]'::jsonb),
        'locations',COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.name) FROM public.locations l WHERE l.is_active),'[]'::jsonb)
      ) INTO v_data;
    WHEN 'returns' THEN
      SELECT jsonb_build_object(
        'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'receipt_number',s.receipt_number,'customer_id',s.customer_id,
          'customer_name',c.name,'location_id',s.location_id,'location_name',l.name,'created_at',s.created_at,'total',s.total,
          'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_id',sl.product_id,'sku',p.sku,'name',p.name,'quantity',sl.quantity,
          'unit_price',sl.unit_price,'unit_cost',sl.unit_cost,'returned',COALESCE((SELECT sum(rl.quantity) FROM public.erp_return_lines rl
          JOIN public.erp_returns r ON r.id=rl.return_id WHERE r.original_sale_id=s.id AND rl.product_id=sl.product_id
          AND rl.disposition<>'exchange_out'),0)) ORDER BY p.sku) FROM public.pos_sale_lines sl JOIN public.products p ON p.id=sl.product_id
          WHERE sl.sale_id=s.id),'[]'::jsonb)) ORDER BY s.created_at DESC)
          FROM (SELECT * FROM public.pos_sales ORDER BY created_at DESC LIMIT 150) s
          LEFT JOIN public.erp_customers c ON c.id=s.customer_id JOIN public.locations l ON l.id=s.location_id),'[]'::jsonb),
        'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'return_number',r.return_number,'original_sale_id',r.original_sale_id,
          'kind',r.kind,'reason_code',r.reason_code,'refund_amount',r.refund_amount,'exchange_amount',r.exchange_amount,'created_at',r.created_at,
          'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('sku',p.sku,'name',p.name,'quantity',x.quantity,'disposition',x.disposition)
          ORDER BY x.disposition) FROM public.erp_return_lines x JOIN public.products p ON p.id=x.product_id WHERE x.return_id=r.id),'[]'::jsonb))
          ORDER BY r.created_at DESC) FROM public.erp_returns r),'[]'::jsonb),
        'products',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'sku',sku,'name',name,'price',price) ORDER BY name)
          FROM public.products WHERE is_active),'[]'::jsonb)
      ) INTO v_data;
    WHEN 'production' THEN
      SELECT jsonb_build_object(
        'orders',COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM public.erp_production_orders r),'[]'::jsonb),
        'report',COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM public.erp_get_production_report(current_date-180,current_date) r),'[]'::jsonb),
        'products',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'sku',p.sku,'name',p.name,'cost',p.cost) ORDER BY p.name)
          FROM public.products p WHERE p.is_active AND EXISTS(SELECT 1 FROM public.erp_bom b WHERE b.parent_product_id=p.id)),'[]'::jsonb),
        'bom',COALESCE((SELECT jsonb_agg(jsonb_build_object('parent_id',b.parent_product_id,'parent_sku',pp.sku,'parent_name',pp.name,
          'component_id',b.component_product_id,'component_sku',cp.sku,'component_name',cp.name,'quantity_per',b.quantity_per) ORDER BY pp.sku,cp.sku)
          FROM public.erp_bom b JOIN public.products pp ON pp.id=b.parent_product_id JOIN public.products cp ON cp.id=b.component_product_id),'[]'::jsonb),
        'locations',COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.name) FROM public.locations l WHERE l.is_active),'[]'::jsonb)
      ) INTO v_data;
    WHEN 'purchasing' THEN
      SELECT jsonb_build_object(
        'suppliers',COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.name) FROM public.erp_suppliers s WHERE s.is_active),'[]'::jsonb),
        'scorecards',COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM public.erp_get_supplier_scorecards() s),'[]'::jsonb),
        'purchase_orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'po_number',o.po_number,'supplier_id',o.supplier_id,
          'supplier_name',s.name,'location_id',o.location_id,'location_name',l.name,'status',o.status,'order_date',o.order_date,
          'expected_receipt_date',o.expected_receipt_date,'actual_receipt_date',o.actual_receipt_date,'payment_terms_days',o.payment_terms_days,
          'due_date',o.order_date+o.payment_terms_days,'amount_paid',o.amount_paid,'total',o.total,'amount_owed',o.total-o.amount_paid,
          'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x.id,'product_id',x.product_id,'sku',p.sku,'product_name',p.name,
          'quantity_ordered',x.quantity_ordered,'quantity_received',x.quantity_received,'unit_cost',x.unit_cost) ORDER BY p.sku)
          FROM public.erp_purchase_order_lines x JOIN public.products p ON p.id=x.product_id WHERE x.purchase_order_id=o.id),'[]'::jsonb))
          ORDER BY o.order_date DESC) FROM public.erp_purchase_orders o JOIN public.erp_suppliers s ON s.id=o.supplier_id
          JOIN public.locations l ON l.id=o.location_id),'[]'::jsonb),
        'products',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'sku',p.sku,'name',p.name,'cost',p.cost) ORDER BY p.sku)
          FROM public.products p WHERE p.is_active),'[]'::jsonb),
        'supplier_products',COALESCE((SELECT jsonb_agg(jsonb_build_object('supplier_id',sp.supplier_id,'product_id',sp.product_id,'quoted_cost',sp.quoted_cost,'lead_time_days',sp.quoted_lead_time_days,'is_preferred',sp.is_preferred)) FROM public.erp_supplier_products sp),'[]'::jsonb),
        'locations',COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.name) FROM public.locations l WHERE l.is_active),'[]'::jsonb),
        'reorder',COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM public.erp_get_reorder_recommendations() r),'[]'::jsonb)
      ) INTO v_data;
    WHEN 'mrp' THEN
      SELECT jsonb_build_object('plan',COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.week_start,r.sku) FROM public.erp_get_mrp_plan(4) r),'[]'::jsonb),
        'reorder',COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.on_hand) FROM public.erp_get_reorder_recommendations() r),'[]'::jsonb)) INTO v_data;
    WHEN 'customers' THEN
      SELECT jsonb_build_object('customers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'email',c.email,'phone',c.phone,
        'created_at',c.created_at,'order_count',(SELECT count(*) FROM public.erp_sales_orders o WHERE o.customer_id=c.id),
        'lifetime_value',(SELECT COALESCE(sum(o.total),0) FROM public.erp_sales_orders o WHERE o.customer_id=c.id AND o.status IN ('fulfilled','closed')))
        ORDER BY c.name) FROM public.erp_customers c),'[]'::jsonb)) INTO v_data;
    WHEN 'reports' THEN
      SELECT jsonb_build_object('dashboard',public.erp_get_dashboard(),
        'financials',public.erp_get_financial_report(current_date-180,current_date),
        'manager',public.erp_get_manager_reports(current_date-30,current_date)) INTO v_data;
    WHEN 'settings' THEN
      SELECT jsonb_build_object('settings',COALESCE((SELECT jsonb_object_agg(setting_key,setting_value) FROM public.erp_system_settings),'{}'::jsonb),
        'staff',CASE WHEN private.has_role(auth.uid(),'admin') THEN COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM public.erp_list_staff() s),'[]'::jsonb) ELSE '[]'::jsonb END,
        'locations',COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.name) FROM public.locations l),'[]'::jsonb)) INTO v_data;
    ELSE
      RAISE EXCEPTION 'Unknown ERP module.';
  END CASE;
  RETURN COALESCE(v_data,'{}'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_module_data(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_module_data(text) TO authenticated;
