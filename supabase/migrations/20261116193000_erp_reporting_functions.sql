-- Live planning, finance, supplier, and manager reporting functions.

CREATE OR REPLACE FUNCTION public.erp_get_mrp_plan(p_weeks integer DEFAULT 4)
RETURNS TABLE (
  week_start date,
  week_end date,
  component_product_id uuid,
  sku text,
  product_name text,
  parent_demand integer,
  component_requirement integer,
  on_hand integer,
  reserved integer,
  open_po_quantity integer,
  suggested_order_quantity integer,
  lead_time_days integer,
  order_by date
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.erp_require_staff();
  RETURN QUERY
  WITH demand AS (
    SELECT date_trunc('week',COALESCE(o.required_by,(o.placed_at+interval '7 days')::date))::date AS req_week,
      l.product_id AS parent_id,b.component_product_id,
      sum(l.quantity*b.quantity_per)::integer AS component_qty,
      sum(l.quantity)::integer AS parent_qty
    FROM public.erp_sales_orders o
    JOIN public.erp_sales_order_lines l ON l.order_id=o.id
    JOIN public.erp_bom b ON b.parent_product_id=l.product_id
    WHERE o.status='order_placed'
      AND COALESCE(o.required_by,(o.placed_at+interval '7 days')::date) >= current_date
      AND COALESCE(o.required_by,(o.placed_at+interval '7 days')::date) < current_date + (LEAST(GREATEST(p_weeks,1),12)*7)
    GROUP BY 1,2,3
  ), weekly AS (
    SELECT req_week,component_product_id,sum(component_qty)::integer AS component_qty,sum(parent_qty)::integer AS parent_qty
    FROM demand GROUP BY req_week,component_product_id
  ), running AS (
    SELECT w.*,
      sum(component_qty) OVER (PARTITION BY component_product_id ORDER BY req_week)::integer AS cumulative_requirement,
      sum(parent_qty) OVER (PARTITION BY component_product_id ORDER BY req_week)::integer AS cumulative_parent_demand
    FROM weekly w
  ), stock AS (
    SELECT b.product_id,sum(b.quantity_on_hand)::integer AS on_hand,sum(b.quantity_reserved)::integer AS reserved
    FROM public.inventory_balances b GROUP BY b.product_id
  ), open_po AS (
    SELECT l.product_id,sum(l.quantity_ordered-l.quantity_received)::integer AS open_qty
    FROM public.erp_purchase_order_lines l JOIN public.erp_purchase_orders o ON o.id=l.purchase_order_id
    WHERE o.status='order_sent' GROUP BY l.product_id
  ), lead AS (
    SELECT sp.product_id,COALESCE(min(sp.quoted_lead_time_days),min(p.lead_time_days),14)::integer AS days
    FROM public.products p LEFT JOIN public.erp_supplier_products sp ON sp.product_id=p.id AND sp.is_preferred
    GROUP BY sp.product_id,p.id
  ), projected AS (
    SELECT r.*,p.sku,p.name,COALESCE(s.on_hand,0) AS on_hand,COALESCE(s.reserved,0) AS reserved,
      COALESCE(po.open_qty,0) AS open_qty,COALESCE(ld.days,p.lead_time_days,14)::integer AS lead_days,
      GREATEST(r.cumulative_requirement-COALESCE(s.on_hand,0)+COALESCE(s.reserved,0)-COALESCE(po.open_qty,0),0)::integer AS cumulative_shortage
    FROM running r JOIN public.products p ON p.id=r.component_product_id
    LEFT JOIN stock s ON s.product_id=p.id LEFT JOIN open_po po ON po.product_id=p.id LEFT JOIN lead ld ON ld.product_id=p.id
  )
  SELECT x.req_week,x.req_week+6,x.component_product_id,x.sku,x.name,x.parent_qty,x.component_qty,
    x.on_hand,x.reserved,x.open_qty,
    GREATEST(x.cumulative_shortage-LAG(x.cumulative_shortage,1,0) OVER (PARTITION BY x.component_product_id ORDER BY x.req_week),0)::integer,
    x.lead_days,x.req_week-x.lead_days
  FROM projected x ORDER BY x.req_week,x.sku;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_mrp_plan(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_mrp_plan(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_reorder_recommendations()
RETURNS TABLE (
  product_id uuid, sku text, product_name text, on_hand integer, reserved integer,
  average_daily_usage numeric, lead_time_days integer, calculated_reorder_point integer,
  eoq integer, open_po_quantity integer, suggested_order_quantity integer, order_by date
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.erp_require_staff();
  RETURN QUERY
  WITH raw_usage AS (
    SELECT l.product_id,sum(l.quantity)::numeric AS direct_qty
    FROM public.pos_sale_lines l JOIN public.pos_sales s ON s.id=l.sale_id
    WHERE s.created_at >= now()-interval '180 days'
    GROUP BY l.product_id
  ), component_usage AS (
    SELECT b.component_product_id AS product_id,sum(l.quantity*b.quantity_per)::numeric AS bom_qty
    FROM public.pos_sale_lines l JOIN public.pos_sales s ON s.id=l.sale_id
    JOIN public.erp_bom b ON b.parent_product_id=l.product_id
    WHERE s.created_at >= now()-interval '180 days'
    GROUP BY b.component_product_id
  ), usage AS (
    SELECT p.id,COALESCE(r.direct_qty,0)+COALESCE(c.bom_qty,0) AS qty
    FROM public.products p LEFT JOIN raw_usage r ON r.product_id=p.id LEFT JOIN component_usage c ON c.product_id=p.id
  ), stock AS (
    SELECT product_id,sum(quantity_on_hand)::integer AS on_hand,sum(quantity_reserved)::integer AS reserved
    FROM public.inventory_balances GROUP BY product_id
  ), open_po AS (
    SELECT l.product_id,sum(l.quantity_ordered-l.quantity_received)::integer AS open_qty
    FROM public.erp_purchase_order_lines l JOIN public.erp_purchase_orders o ON o.id=l.purchase_order_id
    WHERE o.status='order_sent' GROUP BY l.product_id
  ), settings AS (
    SELECT COALESCE((SELECT (setting_value #>> '{}')::numeric FROM public.erp_system_settings WHERE setting_key='ordering_cost'),35) AS order_cost,
      COALESCE((SELECT (setting_value #>> '{}')::numeric FROM public.erp_system_settings WHERE setting_key='annual_holding_rate'),0.24) AS hold_rate
  ), data AS (
    SELECT p.id,p.sku,p.name,COALESCE(s.on_hand,0) AS on_hand,COALESCE(s.reserved,0) AS reserved,
      u.qty/180.0 AS daily,COALESCE(min(sp.quoted_lead_time_days),p.lead_time_days,14)::integer AS lead_days,
      COALESCE(po.open_qty,0) AS open_qty,COALESCE(NULLIF(p.cost,0),0.01) AS unit_cost,
      settings.order_cost,settings.hold_rate,p.reorder_point
    FROM public.products p LEFT JOIN usage u ON u.id=p.id LEFT JOIN stock s ON s.product_id=p.id
    LEFT JOIN open_po po ON po.product_id=p.id LEFT JOIN public.erp_supplier_products sp ON sp.product_id=p.id AND sp.is_preferred
    CROSS JOIN settings WHERE p.is_active
    GROUP BY p.id,p.sku,p.name,s.on_hand,s.reserved,u.qty,po.open_qty,settings.order_cost,settings.hold_rate,p.reorder_point
  ), calc AS (
    SELECT d.*,ceil(d.daily*d.lead_days*1.25)::integer AS rop,
      CASE WHEN d.daily<=0 OR d.hold_rate<=0 THEN 0
        ELSE ceil(sqrt((2*(d.daily*365)*d.order_cost)/(d.unit_cost*d.hold_rate)))::integer END AS eoq
    FROM data d
  )
  SELECT c.id,c.sku,c.name,c.on_hand,c.reserved,round(c.daily,3),c.lead_days,c.rop,c.eoq,c.open_qty,
    CASE WHEN c.on_hand-c.reserved+c.open_qty <= greatest(c.rop,c.reorder_point)
      THEN greatest(c.eoq,greatest(c.rop,c.reorder_point)-(c.on_hand-c.reserved+c.open_qty)) ELSE 0 END::integer,
    current_date+c.lead_days
  FROM calc c
  WHERE c.on_hand-c.reserved <= greatest(c.rop,c.reorder_point)
  ORDER BY (c.on_hand-c.reserved) ASC,c.sku;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_reorder_recommendations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_reorder_recommendations() TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_supplier_scorecards()
RETURNS TABLE (
  supplier_id uuid, supplier_code text, supplier_name text, quoted_lead_time_days integer,
  completed_po_count integer, on_time_delivery_rate numeric, average_actual_lead_time_days numeric,
  average_fill_rate numeric, amount_owed numeric, overdue_amount numeric, overall_rating text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.erp_require_staff();
  RETURN QUERY
  WITH po_stats AS (
    SELECT o.supplier_id,count(*) FILTER (WHERE o.actual_receipt_date IS NOT NULL)::integer AS completed,
      round(100.0*count(*) FILTER (WHERE o.actual_receipt_date<=o.expected_receipt_date)
        / NULLIF(count(*) FILTER (WHERE o.actual_receipt_date IS NOT NULL),0),1) AS on_time,
      round(avg(o.actual_receipt_date-o.order_date) FILTER (WHERE o.actual_receipt_date IS NOT NULL),1) AS actual_lead,
      round(100.0*sum(l.quantity_received) FILTER (WHERE o.actual_receipt_date IS NOT NULL)::numeric
        /NULLIF(sum(l.quantity_ordered) FILTER (WHERE o.actual_receipt_date IS NOT NULL),0),1) AS fill_rate,
      sum(GREATEST(o.total-o.amount_paid,0)) FILTER (WHERE o.status<>'cancelled') AS owed,
      sum(GREATEST(o.total-o.amount_paid,0)) FILTER (WHERE o.status<>'cancelled' AND current_date>o.order_date+o.payment_terms_days) AS overdue
    FROM public.erp_purchase_orders o LEFT JOIN public.erp_purchase_order_lines l ON l.purchase_order_id=o.id
    GROUP BY o.supplier_id
  )
  SELECT s.id,s.supplier_code,s.name,s.quoted_lead_time_days,COALESCE(x.completed,0),COALESCE(x.on_time,0),
    COALESCE(x.actual_lead,0),COALESCE(x.fill_rate,0),COALESCE(x.owed,0),COALESCE(x.overdue,0),
    CASE WHEN COALESCE(x.completed,0)=0 THEN 'NEW'
      WHEN COALESCE(x.on_time,0)>=90 AND COALESCE(x.fill_rate,0)>=95 THEN 'KEEP'
      WHEN COALESCE(x.on_time,0)>=70 AND COALESCE(x.fill_rate,0)>=85 THEN 'WATCH'
      ELSE 'REPLACE' END
  FROM public.erp_suppliers s LEFT JOIN po_stats x ON x.supplier_id=s.id
  WHERE s.is_active ORDER BY s.name;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_supplier_scorecards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_supplier_scorecards() TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_financial_report(p_from date DEFAULT current_date-30,p_to date DEFAULT current_date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_sales numeric(14,2); v_returns numeric(14,2); v_exchange_sales numeric(14,2);
  v_cogs numeric(14,2); v_exchange_cogs numeric(14,2); v_return_cogs numeric(14,2);
  v_tax numeric(14,2); v_tax_refunded numeric(14,2); v_exchange_tax numeric(14,2);
  v_inventory numeric(14,2); v_units numeric; v_turnover numeric;
BEGIN
  PERFORM private.erp_require_staff();
  IF p_from IS NULL OR p_to IS NULL OR p_from>p_to THEN RAISE EXCEPTION 'Choose a valid report date range.'; END IF;
  SELECT COALESCE(sum(subtotal-discount),0),COALESCE(sum(cogs),0),COALESCE(sum(tax),0)
    INTO v_sales,v_cogs,v_tax FROM public.pos_sales WHERE created_at::date BETWEEN p_from AND p_to;
  SELECT COALESCE(sum(r.refund_amount/(1+COALESCE(s.tax_rate,0))),0),
         COALESCE(sum(r.exchange_amount/(1+COALESCE(s.tax_rate,0))),0),
         COALESCE(sum((r.refund_amount/(1+COALESCE(s.tax_rate,0)))*COALESCE(s.tax_rate,0)),0),
         COALESCE(sum((r.exchange_amount/(1+COALESCE(s.tax_rate,0)))*COALESCE(s.tax_rate,0)),0)
    INTO v_returns,v_exchange_sales,v_tax_refunded,v_exchange_tax
    FROM public.erp_returns r JOIN public.pos_sales s ON s.id=r.original_sale_id
    WHERE r.created_at::date BETWEEN p_from AND p_to;
  SELECT COALESCE(sum(unit_cost*quantity) FILTER (WHERE disposition='restock'),0),
         COALESCE(sum(unit_cost*quantity) FILTER (WHERE disposition='exchange_out'),0)
    INTO v_return_cogs,v_exchange_cogs
    FROM public.erp_return_lines rl JOIN public.erp_returns r ON r.id=rl.return_id
    WHERE r.created_at::date BETWEEN p_from AND p_to;
  SELECT COALESCE(sum(b.quantity_on_hand*p.cost),0),COALESCE(sum(b.quantity_on_hand),0)
    INTO v_inventory,v_units
    FROM public.inventory_balances b JOIN public.products p ON p.id=b.product_id;
  v_turnover := CASE WHEN v_inventory<=0 THEN 0 ELSE round((v_cogs+v_exchange_cogs-v_return_cogs)/v_inventory,3) END;
  RETURN jsonb_build_object(
    'from',p_from,'to',p_to,
    'profit_and_loss',jsonb_build_object('gross_sales',v_sales+v_exchange_sales,'sales_returns',v_returns,'net_revenue',v_sales+v_exchange_sales-v_returns,
      'cost_of_goods_sold',greatest(v_cogs+v_exchange_cogs-v_return_cogs,0),
      'gross_profit',(v_sales+v_exchange_sales-v_returns)-greatest(v_cogs+v_exchange_cogs-v_return_cogs,0),
      'sales_tax_collected',v_tax-v_tax_refunded+v_exchange_tax),
    'inventory_valuation',jsonb_build_object('method','weighted average product cost','value',round(v_inventory,2),'units',v_units),
    'inventory_turnover',v_turnover
  );
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_financial_report(date,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_financial_report(date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_production_report(p_from date DEFAULT current_date-30,p_to date DEFAULT current_date)
RETURNS TABLE (
  production_order_id uuid, work_order_number bigint, sku text, product_name text, location_name text,
  status text, quantity_started integer, quantity_completed_good integer, quantity_scrapped integer,
  quality_reason text, yield_percent numeric, scrap_rate numeric, cycle_minutes numeric,
  component_cost numeric, started_at timestamptz, finished_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.erp_require_staff();
  RETURN QUERY
  SELECT o.id,o.work_order_number,p.sku,p.name,l.name,o.status,o.quantity_started,o.quantity_completed_good,o.quantity_scrapped,
    o.quality_reason,CASE WHEN o.quantity_started=0 THEN 0 ELSE round(100.0*o.quantity_completed_good/o.quantity_started,1) END,
    CASE WHEN o.quantity_started=0 THEN 0 ELSE round(100.0*o.quantity_scrapped/o.quantity_started,1) END,
    CASE WHEN o.started_at IS NULL OR o.finished_at IS NULL THEN NULL ELSE round(extract(epoch FROM (o.finished_at-o.started_at))/60,1) END,
    o.component_cost,o.started_at,o.finished_at
  FROM public.erp_production_orders o JOIN public.products p ON p.id=o.parent_product_id
  JOIN public.locations l ON l.id=o.location_id
  WHERE o.created_at::date BETWEEN p_from AND p_to ORDER BY o.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_production_report(date,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_production_report(date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_manager_reports(p_from date DEFAULT current_date-30,p_to date DEFAULT current_date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_sales jsonb; v_top jsonb; v_low jsonb; v_locations jsonb; v_production jsonb; v_suppliers jsonb;
BEGIN
  PERFORM private.erp_require_staff();
  IF p_from>p_to THEN RAISE EXCEPTION 'Choose a valid report date range.'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('day',d.day,'sales',d.sales,'orders',d.orders) ORDER BY d.day),'[]'::jsonb)
    INTO v_sales FROM (
      SELECT created_at::date AS day,round(sum(total),2) AS sales,count(*) AS orders
      FROM public.pos_sales WHERE created_at::date BETWEEN p_from AND p_to GROUP BY created_at::date
    ) d;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('sku',sku,'product_name',product_name,'units',units,'revenue',revenue) ORDER BY units DESC),'[]'::jsonb)
    INTO v_top FROM (
      SELECT p.sku,p.name AS product_name,sum(l.quantity)::integer AS units,round(sum(l.line_subtotal),2) AS revenue
      FROM public.pos_sale_lines l JOIN public.pos_sales s ON s.id=l.sale_id JOIN public.products p ON p.id=l.product_id
      WHERE s.created_at::date BETWEEN p_from AND p_to GROUP BY p.sku,p.name ORDER BY sum(l.quantity) DESC LIMIT 10
    ) t;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('sku',sku,'product_name',product_name,'available',on_hand-reserved,
      'suggested_order_quantity',suggested_order_quantity,'order_by',order_by) ORDER BY on_hand-reserved),'[]'::jsonb)
    INTO v_low FROM public.erp_get_reorder_recommendations();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('location',l.name,'units',COALESCE(x.units,0),'value',round(COALESCE(x.value,0),2)) ORDER BY l.name),'[]'::jsonb)
    INTO v_locations FROM public.locations l LEFT JOIN (
      SELECT b.location_id,sum(b.quantity_on_hand)::integer AS units,sum(b.quantity_on_hand*p.cost) AS value
      FROM public.inventory_balances b JOIN public.products p ON p.id=b.product_id GROUP BY b.location_id
    ) x ON x.location_id=l.id WHERE l.is_active;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('sku',sku,'product_name',product_name,'status',status,'yield_percent',yield_percent,
      'scrap_rate',scrap_rate,'cycle_minutes',cycle_minutes) ORDER BY work_order_number DESC),'[]'::jsonb)
    INTO v_production FROM public.erp_get_production_report(p_from,p_to);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('supplier',supplier_name,'rating',overall_rating,'on_time_rate',on_time_delivery_rate,
      'fill_rate',average_fill_rate,'owed',amount_owed) ORDER BY supplier_name),'[]'::jsonb)
    INTO v_suppliers FROM public.erp_get_supplier_scorecards();
  RETURN jsonb_build_object('sales_by_day',v_sales,'top_items',v_top,'low_stock',v_low,'inventory_by_location',v_locations,
    'production',v_production,'supplier_performance',v_suppliers);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_manager_reports(date,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_manager_reports(date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_dashboard()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_today numeric; v_open_orders integer; v_low integer; v_production integer; v_recent jsonb;
  v_ready integer; v_total_kits integer; v_ready_percent numeric;
BEGIN
  PERFORM private.erp_require_staff();
  SELECT COALESCE(sum(total),0) INTO v_today FROM public.pos_sales WHERE created_at::date=current_date;
  SELECT count(*) INTO v_open_orders FROM public.erp_sales_orders WHERE status='order_placed';
  SELECT count(*) INTO v_low FROM public.erp_get_reorder_recommendations();
  SELECT count(*) INTO v_production FROM public.erp_production_orders WHERE status IN ('planned','issued');
  SELECT count(*) INTO v_total_kits FROM public.products p WHERE p.is_active AND EXISTS
    (SELECT 1 FROM public.erp_bom b WHERE b.parent_product_id=p.id);
  SELECT count(*) INTO v_ready FROM public.products p WHERE p.is_active
    AND EXISTS (SELECT 1 FROM public.erp_bom b WHERE b.parent_product_id=p.id)
    AND EXISTS (SELECT 1 FROM public.locations l WHERE l.is_active AND l.location_type='retail'
      AND (
        COALESCE((SELECT sum(b.quantity_on_hand-b.quantity_reserved) FROM public.inventory_balances b
          WHERE b.product_id=p.id AND b.location_id=l.id),0)>0
        OR NOT EXISTS (SELECT 1 FROM public.erp_bom bom LEFT JOIN public.inventory_balances stock
          ON stock.product_id=bom.component_product_id AND stock.location_id=l.id
          WHERE bom.parent_product_id=p.id
          AND COALESCE(stock.quantity_on_hand-stock.quantity_reserved,0)<bom.quantity_per)
      ));
  v_ready_percent := CASE WHEN v_total_kits=0 THEN 0 ELSE round(100.0*v_ready/v_total_kits,1) END;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'receipt_number',receipt_number,'total',total,'source',source,'created_at',created_at)
      ORDER BY created_at DESC),'[]'::jsonb)
    INTO v_recent FROM (SELECT id,receipt_number,total,source,created_at FROM public.pos_sales ORDER BY created_at DESC LIMIT 8) r;
  RETURN jsonb_build_object('today_sales',v_today,'open_orders',v_open_orders,'low_stock_items',v_low,
    'active_production_orders',v_production,'recent_sales',v_recent,'ready_kits',v_ready,'total_kits',v_total_kits,
    'night_run_readiness_percent',v_ready_percent);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_get_dashboard() TO authenticated;
