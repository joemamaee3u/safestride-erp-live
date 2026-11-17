-- Stop exposing product cost through the public API. Rows and existing policies are unchanged.
REVOKE SELECT ON public.products FROM anon, authenticated;
GRANT SELECT (id, sku, name, category, barcode, price, reorder_point, lead_time_days, is_active, created_at)
  ON public.products TO anon, authenticated;
GRANT ALL ON public.products TO service_role;