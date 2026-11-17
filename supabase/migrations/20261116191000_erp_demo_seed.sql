-- SafeStride demo data. Inserts only missing records and never resets existing stock.
INSERT INTO public.erp_system_settings (setting_key, setting_value)
VALUES
  ('company_name', '"StrideSafe Reflective Running Gear"'::jsonb),
  ('currency', '"USD"'::jsonb),
  ('tax_rate', '0.0825'::jsonb),
  ('ordering_cost', '35'::jsonb),
  ('annual_holding_rate', '0.24'::jsonb),
  ('history_days', '180'::jsonb)
ON CONFLICT (setting_key) DO NOTHING;

INSERT INTO public.locations (name, location_type, address, is_active)
SELECT v.name, v.location_type, v.address, true
FROM (VALUES
  ('Provo Trail Lab', 'retail', 'Provo, Utah'),
  ('Salt Lake Showroom', 'retail', 'Salt Lake City, Utah'),
  ('Utah Fulfillment Hub', 'warehouse', 'Orem, Utah')
) AS v(name, location_type, address)
WHERE NOT EXISTS (SELECT 1 FROM public.locations l WHERE lower(l.name) = lower(v.name));

INSERT INTO public.erp_suppliers
  (supplier_code, name, contact_name, email, phone, quoted_lead_time_days, payment_terms_days, ordering_cost, annual_holding_rate)
VALUES
  ('SUP-REFLECT', 'Reflecta Materials', 'Maya Chen', 'orders@reflecta.example', '801-555-0142', 12, 30, 38, 0.24),
  ('SUP-TEXTILE', 'Wasatch Performance Textiles', 'Eli Turner', 'sales@wasatchtextile.example', '801-555-0188', 18, 30, 42, 0.22),
  ('SUP-LIGHT', 'NightPulse Electronics', 'Jordan Kim', 'orders@nightpulse.example', '801-555-0174', 9, 15, 55, 0.28),
  ('SUP-FIT', 'MotionFit Components', 'Avery Brooks', 'hello@motionfit.example', '801-555-0126', 14, 30, 32, 0.20),
  ('SUP-PACK', 'TrailPack Supply', 'Riley Morgan', 'supply@trailpack.example', '801-555-0191', 7, 15, 28, 0.18),
  ('SUP-PRINT', 'Utah Print & Trim', 'Casey Patel', 'orders@utahprint.example', '801-555-0163', 6, 30, 24, 0.18)
ON CONFLICT (supplier_code) DO NOTHING;

WITH seed(sku, name, category, barcode, price, cost, reorder_point, lead_time_days) AS (
  VALUES
    ('SSF-101','NightRun Reflective Vest','Vests','8100000000101',74.00,28.00,18,12),
    ('SSF-102','HaloBeam Chest Light Kit','Lighting','8100000000102',58.00,22.50,14,9),
    ('SSF-103','StormShield Reflective Jacket','Jackets','8100000000103',148.00,61.00,12,18),
    ('SSF-104','PaceBand Arm Sleeve Pair','Accessories','8100000000104',34.00,11.75,20,14),
    ('SSF-105','NightRunner Starter Kit','Bundles','8100000000105',119.00,46.00,15,12),
    ('CMP-201','Breathable Vest Shell','Components','8100000000201',19.00,7.20,60,18),
    ('CMP-202','Reflective Safety Tape Roll','Components','8100000000202',8.50,2.70,90,12),
    ('CMP-203','Low-Profile Buckle Set','Components','8100000000203',4.50,1.20,80,14),
    ('CMP-204','LED Chest Module','Components','8100000000204',18.00,7.10,45,9),
    ('CMP-205','Rechargeable 1200mAh Battery','Components','8100000000205',12.00,4.80,50,9),
    ('CMP-206','USB-C Charging Cable','Components','8100000000206',5.00,1.60,70,7),
    ('CMP-207','Silicone Chest Harness','Components','8100000000207',9.00,3.10,55,14),
    ('CMP-208','High-Visibility Jacket Shell','Components','8100000000208',44.00,18.00,30,18),
    ('CMP-209','Seam-Seal Tape Set','Components','8100000000209',6.50,2.10,55,12),
    ('CMP-210','Reflective Zipper Pull','Components','8100000000210',3.50,0.90,70,12),
    ('CMP-211','Moisture-Wicking Sleeve Pair','Components','8100000000211',7.50,2.40,60,14),
    ('CMP-212','Silicone Grip Band','Components','8100000000212',3.00,0.85,65,14),
    ('CMP-213','Reflective Arm Wrap','Components','8100000000213',5.50,1.75,60,12),
    ('CMP-214','Zip Pouch','Components','8100000000214',4.00,1.30,50,7),
    ('CMP-215','Reflective Packaging Box','Components','8100000000215',2.75,0.80,90,6),
    ('CMP-216','Elastic Webbing Meter','Components','8100000000216',1.80,0.55,100,14),
    ('CMP-217','Reflective Yarn Spool','Components','8100000000217',14.00,5.20,35,18),
    ('CMP-218','Care Label Set','Components','8100000000218',0.60,0.18,120,6),
    ('CMP-219','Adjustable Light Mount','Components','8100000000219',6.00,2.00,40,9),
    ('CMP-220','Reflective Runner Cap','Accessories','8100000000220',28.00,9.40,22,12)
)
INSERT INTO public.products (sku, name, category, barcode, price, cost, reorder_point, lead_time_days, is_active)
SELECT s.sku, s.name, s.category, s.barcode, s.price, s.cost, s.reorder_point, s.lead_time_days, true
FROM seed s
WHERE NOT EXISTS (SELECT 1 FROM public.products p WHERE p.sku = s.sku);

-- Initialize only absent balances for the named demo products and locations.
CREATE UNIQUE INDEX IF NOT EXISTS inventory_balances_product_location_uidx
  ON public.inventory_balances (product_id, location_id);

WITH seeded_stock(sku, provo_qty, slc_qty, hub_qty) AS (
  VALUES
    ('SSF-101',18,12,46),('SSF-102',14,10,38),('SSF-103',10,8,30),('SSF-104',20,14,55),('SSF-105',15,9,35),
    ('CMP-201',20,15,90),('CMP-202',30,25,120),('CMP-203',28,24,110),('CMP-204',18,14,72),('CMP-205',20,18,80),
    ('CMP-206',24,20,105),('CMP-207',22,18,95),('CMP-208',14,12,60),('CMP-209',20,16,72),('CMP-210',26,22,90),
    ('CMP-211',22,20,88),('CMP-212',24,20,90),('CMP-213',22,19,84),('CMP-214',20,18,78),('CMP-215',30,28,130),
    ('CMP-216',32,30,140),('CMP-217',15,12,52),('CMP-218',40,36,180),('CMP-219',18,16,66),('CMP-220',12,10,40)
), loc AS (
  SELECT
    (SELECT id FROM public.locations WHERE name='Provo Trail Lab' ORDER BY created_at NULLS LAST LIMIT 1) AS provo_id,
    (SELECT id FROM public.locations WHERE name='Salt Lake Showroom' ORDER BY created_at NULLS LAST LIMIT 1) AS slc_id,
    (SELECT id FROM public.locations WHERE name='Utah Fulfillment Hub' ORDER BY created_at NULLS LAST LIMIT 1) AS hub_id
)
INSERT INTO public.inventory_balances (product_id, location_id, quantity_on_hand, quantity_reserved)
SELECT p.id, x.location_id, x.qty, 0
FROM seeded_stock s
JOIN public.products p ON p.sku = s.sku
CROSS JOIN loc
CROSS JOIN LATERAL (VALUES
  (loc.provo_id, s.provo_qty), (loc.slc_id, s.slc_qty), (loc.hub_id, s.hub_qty)
) AS x(location_id, qty)
WHERE x.location_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.inventory_balances b
    WHERE b.product_id = p.id AND b.location_id = x.location_id
  );

INSERT INTO public.erp_bom (parent_product_id, component_product_id, quantity_per)
SELECT parent.id, component.id, v.quantity_per
FROM (VALUES
  ('SSF-101','CMP-201',1),('SSF-101','CMP-202',2),('SSF-101','CMP-203',1),('SSF-101','CMP-215',1),('SSF-101','CMP-218',1),
  ('SSF-102','CMP-204',1),('SSF-102','CMP-205',1),('SSF-102','CMP-206',1),('SSF-102','CMP-207',1),('SSF-102','CMP-215',1),
  ('SSF-103','CMP-208',1),('SSF-103','CMP-202',3),('SSF-103','CMP-209',1),('SSF-103','CMP-210',1),('SSF-103','CMP-218',1),
  ('SSF-104','CMP-211',1),('SSF-104','CMP-212',1),('SSF-104','CMP-213',1),('SSF-104','CMP-217',1),('SSF-104','CMP-218',1),
  ('SSF-105','CMP-201',1),('SSF-105','CMP-202',2),('SSF-105','CMP-204',1),('SSF-105','CMP-205',1),('SSF-105','CMP-206',1),('SSF-105','CMP-207',1),('SSF-105','CMP-215',1)
) AS v(parent_sku, component_sku, quantity_per)
JOIN public.products parent ON parent.sku = v.parent_sku
JOIN public.products component ON component.sku = v.component_sku
ON CONFLICT (parent_product_id, component_product_id) DO NOTHING;

INSERT INTO public.erp_supplier_products (supplier_id, product_id, quoted_cost, quoted_lead_time_days, is_preferred)
SELECT s.id, p.id, p.cost, COALESCE(p.lead_time_days, s.quoted_lead_time_days), true
FROM public.erp_suppliers s
CROSS JOIN public.products p
WHERE (s.supplier_code = 'SUP-REFLECT' AND p.sku IN ('CMP-202','CMP-208','CMP-209','CMP-210','CMP-217'))
   OR (s.supplier_code = 'SUP-TEXTILE' AND p.sku IN ('CMP-201','CMP-211','CMP-216'))
   OR (s.supplier_code = 'SUP-LIGHT' AND p.sku IN ('CMP-204','CMP-205','CMP-206','CMP-219'))
   OR (s.supplier_code = 'SUP-FIT' AND p.sku IN ('CMP-203','CMP-207','CMP-212','CMP-213'))
   OR (s.supplier_code = 'SUP-PACK' AND p.sku IN ('CMP-214','CMP-215'))
   OR (s.supplier_code = 'SUP-PRINT' AND p.sku IN ('CMP-218','CMP-220'))
ON CONFLICT (supplier_id, product_id) DO NOTHING;

INSERT INTO public.erp_customers (name, email, phone)
VALUES
  ('Mason Carter','mason.carter@example.test','801-555-1001'),
  ('Liam Bennett','liam.bennett@example.test','801-555-1002'),
  ('Noah Ramirez','noah.ramirez@example.test','801-555-1003'),
  ('Ethan Foster','ethan.foster@example.test','801-555-1004'),
  ('Logan Brooks','logan.brooks@example.test','801-555-1005'),
  ('Lucas Hayes','lucas.hayes@example.test','801-555-1006'),
  ('Owen Price','owen.price@example.test','801-555-1007'),
  ('Caleb Morgan','caleb.morgan@example.test','801-555-1008'),
  ('Jack Sullivan','jack.sullivan@example.test','801-555-1009'),
  ('Levi Peterson','levi.peterson@example.test','801-555-1010')
ON CONFLICT DO NOTHING;

-- Six supplier receipts create a meaningful scorecard baseline without changing on-hand stock.
DO $$
DECLARE v record; v_po uuid; v_order_date date; v_expected date; v_actual date; v_total numeric(14,2);
  v_supplier_id uuid; v_terms integer; v_lead integer; v_cost numeric(14,2); v_product_id uuid;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      ('SUP-REFLECT','CMP-202',100,96,-2,1.00::numeric),
      ('SUP-TEXTILE','CMP-201',120,118,0,0.85::numeric),
      ('SUP-LIGHT','CMP-204',80,80,5,1.00::numeric),
      ('SUP-FIT','CMP-213',90,82,3,0.50::numeric),
      ('SUP-PACK','CMP-215',200,200,-1,1.00::numeric),
      ('SUP-PRINT','CMP-218',250,244,7,0.80::numeric)
    ) AS x(supplier_code,sku,ordered_qty,received_qty,actual_offset,payment_fraction)
  LOOP
    IF EXISTS (SELECT 1 FROM public.erp_purchase_orders o JOIN public.erp_suppliers s ON s.id=o.supplier_id
      WHERE o.is_demo_history AND s.supplier_code=v.supplier_code) THEN CONTINUE; END IF;
    SELECT s.id,s.payment_terms_days,s.quoted_lead_time_days,sp.quoted_cost,sp.product_id
      INTO v_supplier_id,v_terms,v_lead,v_cost,v_product_id
    FROM public.erp_suppliers s JOIN public.erp_supplier_products sp ON sp.supplier_id=s.id
    JOIN public.products p ON p.id=sp.product_id
    WHERE s.supplier_code=v.supplier_code AND p.sku=v.sku LIMIT 1;
    v_order_date := current_date-130;
    v_expected := v_order_date+v_lead;
    v_actual := v_expected+v.actual_offset;
    v_total := v.ordered_qty*v_cost;
    INSERT INTO public.erp_purchase_orders(supplier_id,location_id,status,order_date,expected_receipt_date,actual_receipt_date,
      payment_terms_days,amount_paid,total,is_demo_history)
    SELECT v_supplier_id,l.id,'closed',v_order_date,v_expected,v_actual,v_terms,round(v_total*v.payment_fraction,2),v_total,true
    FROM public.locations l WHERE l.name='Utah Fulfillment Hub' ORDER BY l.created_at NULLS LAST LIMIT 1
    RETURNING id INTO v_po;
    INSERT INTO public.erp_purchase_order_lines(purchase_order_id,product_id,quantity_ordered,quantity_received,unit_cost)
      VALUES(v_po,v_product_id,v.ordered_qty,v.received_qty,v_cost);
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM public.erp_purchase_orders WHERE is_demo_history AND status='order_sent') THEN
    INSERT INTO public.erp_purchase_orders(supplier_id,location_id,status,order_date,expected_receipt_date,payment_terms_days,total,is_demo_history)
    SELECT s.id,l.id,'order_sent',current_date-2,current_date+s.quoted_lead_time_days,s.payment_terms_days,sp.quoted_cost*50,true
    FROM public.erp_suppliers s JOIN public.erp_supplier_products sp ON sp.supplier_id=s.id
    JOIN public.products p ON p.id=sp.product_id JOIN public.locations l ON l.name='Utah Fulfillment Hub'
    WHERE s.supplier_code='SUP-LIGHT' AND p.sku='CMP-205' ORDER BY l.created_at NULLS LAST LIMIT 1
    RETURNING id INTO v_po;
    INSERT INTO public.erp_purchase_order_lines(purchase_order_id,product_id,quantity_ordered,quantity_received,unit_cost)
    SELECT v_po,p.id,50,0,sp.quoted_cost FROM public.products p
    JOIN public.erp_supplier_products sp ON sp.product_id=p.id JOIN public.erp_suppliers s ON s.id=sp.supplier_id
    WHERE s.supplier_code='SUP-LIGHT' AND p.sku='CMP-205';
  END IF;
END $$;

-- A few upcoming confirmed orders make the four-week material plan immediately demonstrable.
DO $$
DECLARE v record; v_order uuid; v_customer uuid; v_product uuid; v_location uuid; v_reserved integer;
  v_available integer; v_price numeric(14,2); v_cost numeric(14,2); v_lead integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.erp_sales_orders WHERE is_demo_history) THEN RETURN; END IF;
  SELECT id INTO v_location FROM public.locations WHERE name='Provo Trail Lab' ORDER BY created_at NULLS LAST LIMIT 1;
  FOR v IN SELECT * FROM (VALUES
    ('mason.carter@example.test','SSF-101',5,7),
    ('noah.ramirez@example.test','SSF-103',3,14),
    ('lucas.hayes@example.test','SSF-105',4,21)
  ) AS x(email,sku,quantity,days_out)
  LOOP
    SELECT id INTO v_customer FROM public.erp_customers WHERE email=v.email LIMIT 1;
    SELECT id,price,cost,lead_time_days INTO v_product,v_price,v_cost,v_lead FROM public.products WHERE sku=v.sku;
    SELECT COALESCE(quantity_on_hand,0)-COALESCE(quantity_reserved,0) INTO v_available FROM public.inventory_balances
      WHERE product_id=v_product AND location_id=v_location;
    v_available:=GREATEST(COALESCE(v_available,0),0);
    v_reserved:=LEAST(v.quantity,v_available);
    INSERT INTO public.erp_sales_orders(customer_id,location_id,channel,status,required_by,is_demo_history,subtotal,total)
      VALUES(v_customer,v_location,'pickup','order_placed',current_date+v.days_out,true,v_price*v.quantity,v_price*v.quantity)
      RETURNING id INTO v_order;
    INSERT INTO public.erp_sales_order_lines(order_id,product_id,quantity,quantity_fulfilled,quantity_backordered,
      estimated_available_date,unit_price,unit_cost)
      VALUES(v_order,v_product,v.quantity,0,v.quantity-v_reserved,
        CASE WHEN v.quantity>v_reserved THEN current_date+COALESCE(v_lead,14) ELSE NULL END,v_price,v_cost);
    IF v_reserved>0 THEN UPDATE public.inventory_balances SET quantity_reserved=quantity_reserved+v_reserved,updated_at=now()
      WHERE product_id=v_product AND location_id=v_location; END IF;
  END LOOP;
END $$;

-- Six months of varied synthetic POS history for the classroom demo.
-- It is marked clearly, represents prior sales, and does not change current on-hand balances.
DO $$
DECLARE
  d integer;
  t integer;
  v_product_id uuid;
  v_location_id uuid;
  v_customer_id uuid;
  v_price numeric(14,2);
  v_cost numeric(14,2);
  v_qty integer;
  v_subtotal numeric(14,2);
  v_cogs numeric(14,2);
  v_tax numeric(14,2);
  v_sale_id uuid;
  v_customer_count integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.pos_sales WHERE is_demo_history) THEN
    RETURN;
  END IF;
  SELECT id INTO v_location_id FROM public.locations WHERE name = 'Provo Trail Lab' ORDER BY created_at NULLS LAST LIMIT 1;
  SELECT count(*) INTO v_customer_count FROM public.erp_customers;
  IF v_location_id IS NULL OR v_customer_count = 0 THEN
    RETURN;
  END IF;
  FOR d IN 1..180 LOOP
    FOR t IN 1..(CASE WHEN d % 7 IN (4,5,6) THEN 3 WHEN d % 3 = 0 THEN 2 ELSE 1 END) LOOP
      SELECT p.id, p.price, p.cost INTO v_product_id, v_price, v_cost
      FROM public.products p
      WHERE p.sku IN ('SSF-101','SSF-102','SSF-103','SSF-104','SSF-105')
      ORDER BY p.sku
      OFFSET ((d * 3 + t * 2 + (d / 21)) % 5) LIMIT 1;
      v_qty := 1 + ((d + t * 5) % 3);
      v_subtotal := round(v_price * v_qty, 2);
      v_cogs := round(v_cost * v_qty, 2);
      v_tax := round(v_subtotal * 0.0825, 2);
      SELECT id INTO v_customer_id FROM public.erp_customers ORDER BY email OFFSET ((d + t) % v_customer_count) LIMIT 1;
      INSERT INTO public.pos_sales
        (location_id, cashier_id, customer_id, source, subtotal, discount, tax, tax_rate, total, cogs, is_demo_history, created_at)
      VALUES
        (v_location_id, NULL, v_customer_id, 'demo_history', v_subtotal, 0, v_tax, 0.0825, v_subtotal + v_tax, v_cogs, true,
         (current_date - d)::timestamptz + make_interval(hours => t * 3))
      RETURNING id INTO v_sale_id;
      INSERT INTO public.pos_sale_lines (sale_id, product_id, quantity, unit_price, unit_cost, line_subtotal)
      VALUES (v_sale_id, v_product_id, v_qty, v_price, v_cost, v_subtotal);
      INSERT INTO public.erp_ledger_entries (source_type, source_id, location_id, account, debit, credit, created_at)
      VALUES
        ('sale', v_sale_id, v_location_id, 'Cash', v_subtotal + v_tax, 0, (current_date - d)::timestamptz + make_interval(hours => t * 3)),
        ('sale', v_sale_id, v_location_id, 'Sales revenue', 0, v_subtotal, (current_date - d)::timestamptz + make_interval(hours => t * 3)),
        ('sale', v_sale_id, v_location_id, 'Sales tax payable', 0, v_tax, (current_date - d)::timestamptz + make_interval(hours => t * 3)),
        ('sale', v_sale_id, v_location_id, 'Cost of goods sold', v_cogs, 0, (current_date - d)::timestamptz + make_interval(hours => t * 3)),
        ('sale', v_sale_id, v_location_id, 'Inventory', 0, v_cogs, (current_date - d)::timestamptz + make_interval(hours => t * 3));
    END LOOP;
  END LOOP;
END $$;
