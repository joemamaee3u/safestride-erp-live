CREATE OR REPLACE FUNCTION public.erp_get_public_catalog()
RETURNS TABLE (
  product_id uuid,sku text,product_name text,category text,barcode text,price numeric,
  location_id uuid,location_name text,quantity_available integer
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT a.product_id,a.sku,a.product_name,a.category,a.barcode,a.price,a.location_id,a.location_name,a.quantity_available
  FROM public.get_inventory_availability() a
  JOIN public.locations l ON l.id=a.location_id
  WHERE l.location_type='retail' AND COALESCE(a.category,'')<>'Components'
$$;
REVOKE ALL ON FUNCTION public.erp_get_public_catalog() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erp_get_public_catalog() TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.erp_list_store_locations()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'type',l.location_type,'address',l.address) ORDER BY l.name),'[]'::jsonb)
  FROM public.locations l WHERE l.is_active AND l.location_type='retail'
$$;
REVOKE ALL ON FUNCTION public.erp_list_store_locations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erp_list_store_locations() TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_my_customer()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid:=auth.uid(); v_data jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in to view your account.' USING ERRCODE='42501'; END IF;
  SELECT to_jsonb(c) INTO v_data FROM public.erp_customers c WHERE c.auth_user_id=v_user;
  RETURN COALESCE(v_data,'{}'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_my_customer() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.erp_get_my_customer() TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_get_my_orders()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid:=auth.uid(); v_customer uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in to view your orders.' USING ERRCODE='42501'; END IF;
  SELECT id INTO v_customer FROM public.erp_customers WHERE auth_user_id=v_user;
  IF v_customer IS NULL THEN RETURN '[]'::jsonb; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'order_number',o.order_number,'status',o.status,
    'channel',o.channel,'placed_at',o.placed_at,'required_by',o.required_by,'location_name',l.name,'total',o.total,
    'lines',COALESCE((SELECT jsonb_agg(jsonb_build_object('sku',p.sku,'name',p.name,'quantity',x.quantity,
      'quantity_backordered',x.quantity_backordered,'estimated_available_date',x.estimated_available_date,'unit_price',x.unit_price)
      ORDER BY p.sku) FROM public.erp_sales_order_lines x JOIN public.products p ON p.id=x.product_id WHERE x.order_id=o.id),'[]'::jsonb))
    ORDER BY o.placed_at DESC) FROM public.erp_sales_orders o JOIN public.locations l ON l.id=o.location_id WHERE o.customer_id=v_customer),'[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_get_my_orders() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.erp_get_my_orders() TO authenticated;
