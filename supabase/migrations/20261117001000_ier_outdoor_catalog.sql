-- IER rebrand and outdoor retail assortment. Product IDs and existing stock history remain intact.
UPDATE public.erp_system_settings
SET setting_value = '"IER Outdoor Gear"'::jsonb
WHERE setting_key = 'company_name';

UPDATE public.products AS p
SET name = v.name,
    category = v.category,
    price = v.price,
    cost = v.cost,
    reorder_point = v.reorder_point,
    lead_time_days = v.lead_time_days,
    is_active = true
FROM (VALUES
  ('SSF-101','Summit Ridge 2P Backpacking Tent','Camping',229.00,108.00,10,18),
  ('SSF-102','TrailBeam Rechargeable Headlamp','Lighting',49.00,19.00,14,9),
  ('SSF-103','Stormline Waterproof Shell Jacket','Clothing',179.00,76.00,12,18),
  ('SSF-104','RidgeRunner Trekking Pole Set','Accessories',89.00,38.00,15,14),
  ('SSF-105','Alpine Camp Starter Bundle','Bundles',299.00,142.00,8,18)
) AS v(sku,name,category,price,cost,reorder_point,lead_time_days)
WHERE p.sku = v.sku;

INSERT INTO public.products (sku,name,category,barcode,price,cost,reorder_point,lead_time_days,is_active)
VALUES
  ('IER-301','Trail 28L Daypack','Packs & Bags','8100000000301',88.00,39.00,12,14,true),
  ('IER-302','Approach Waterproof Hiking Shoes','Footwear','8100000000302',139.00,62.00,10,21,true),
  ('IER-303','Basecamp 20F Sleeping Bag','Sleeping Gear','8100000000303',189.00,84.00,8,18,true),
  ('IER-304','CampRest Insulated Sleeping Pad','Sleeping Gear','8100000000304',99.00,43.00,10,14,true),
  ('IER-305','Trailside Compact Camp Stove','Camp Kitchen','8100000000305',64.00,27.00,10,12,true),
  ('IER-306','All-Weather 32 oz Bottle','Hydration','8100000000306',32.00,12.00,18,9,true),
  ('IER-307','Merino Trail Crew Socks','Clothing','8100000000307',24.00,8.00,20,12,true),
  ('IER-308','Alpine Trekking Poles','Accessories','8100000000308',79.00,34.00,12,14,true)
ON CONFLICT (sku) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  price = EXCLUDED.price,
  cost = EXCLUDED.cost,
  reorder_point = EXCLUDED.reorder_point,
  lead_time_days = EXCLUDED.lead_time_days,
  is_active = true;

WITH stock(sku, location_name, quantity) AS (VALUES
  ('IER-301','Provo Trail Lab',12),('IER-301','Salt Lake Showroom',7),('IER-301','Utah Fulfillment Hub',28),
  ('IER-302','Provo Trail Lab',10),('IER-302','Salt Lake Showroom',6),('IER-302','Utah Fulfillment Hub',24),
  ('IER-303','Provo Trail Lab',8),('IER-303','Salt Lake Showroom',5),('IER-303','Utah Fulfillment Hub',20),
  ('IER-304','Provo Trail Lab',10),('IER-304','Salt Lake Showroom',6),('IER-304','Utah Fulfillment Hub',22),
  ('IER-305','Provo Trail Lab',10),('IER-305','Salt Lake Showroom',5),('IER-305','Utah Fulfillment Hub',18),
  ('IER-306','Provo Trail Lab',18),('IER-306','Salt Lake Showroom',12),('IER-306','Utah Fulfillment Hub',36),
  ('IER-307','Provo Trail Lab',20),('IER-307','Salt Lake Showroom',14),('IER-307','Utah Fulfillment Hub',42),
  ('IER-308','Provo Trail Lab',12),('IER-308','Salt Lake Showroom',7),('IER-308','Utah Fulfillment Hub',25)
)
INSERT INTO public.inventory_balances (product_id,location_id,quantity_on_hand,quantity_reserved)
SELECT p.id,l.id,s.quantity,0
FROM stock s
JOIN public.products p ON p.sku=s.sku
JOIN public.locations l ON l.name=s.location_name
ON CONFLICT (product_id,location_id) DO NOTHING;

INSERT INTO public.erp_suppliers
  (supplier_code,name,contact_name,email,phone,quoted_lead_time_days,payment_terms_days,ordering_cost,annual_holding_rate,is_active)
VALUES
  ('SUP-IER','Summit Outdoor Supply','Taylor Morgan','orders@summitoutdoor.example','801-555-0164',14,30,35,0.24,true)
ON CONFLICT (supplier_code) DO UPDATE SET name=EXCLUDED.name,is_active=true;

INSERT INTO public.erp_supplier_products (supplier_id,product_id,quoted_cost,quoted_lead_time_days,is_preferred)
SELECT s.id,p.id,p.cost,COALESCE(p.lead_time_days,14),true
FROM public.erp_suppliers s
CROSS JOIN public.products p
WHERE s.supplier_code='SUP-IER' AND p.sku LIKE 'IER-3%'
ON CONFLICT (supplier_id,product_id) DO UPDATE SET
  quoted_cost=EXCLUDED.quoted_cost,
  quoted_lead_time_days=EXCLUDED.quoted_lead_time_days,
  is_preferred=true;
