-- Authenticated, transaction-safe ERP operations. All stock-changing work runs in PostgreSQL.

CREATE OR REPLACE FUNCTION private.erp_require_staff()
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL OR NOT private.is_staff(v_user) THEN
    RAISE EXCEPTION 'Staff access required' USING ERRCODE = '42501';
  END IF;
  RETURN v_user;
END;
$$;
REVOKE ALL ON FUNCTION private.erp_require_staff() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.erp_claim_first_admin()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in before claiming the initial administrator.' USING ERRCODE = '42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('stridesafe-initial-admin'));
  IF EXISTS (SELECT 1 FROM public.user_roles) THEN
    RETURN jsonb_build_object('claimed', false, 'message', 'An administrator already exists. Ask them to grant your staff role.');
  END IF;
  INSERT INTO public.user_roles (user_id, role) VALUES (v_user, 'admin') ON CONFLICT (user_id, role) DO NOTHING;
  RETURN jsonb_build_object('claimed', true, 'message', 'Initial administrator access granted.');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_claim_first_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_claim_first_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_list_staff()
RETURNS TABLE (user_id uuid, email text, role text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
    SELECT u.id, u.email::text, r.role::text, r.created_at
    FROM public.user_roles r JOIN auth.users u ON u.id = r.user_id
    ORDER BY r.created_at, u.email;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_list_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_list_staff() TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_set_staff_role(p_user_id uuid, p_role text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501'; END IF;
  IF p_role NOT IN ('admin','manager','employee') THEN RAISE EXCEPTION 'Choose admin, manager, employee, or remove the role.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN RAISE EXCEPTION 'User not found.'; END IF;
  DELETE FROM public.user_roles WHERE user_id = p_user_id;
  INSERT INTO public.user_roles (user_id, role) VALUES (p_user_id, p_role::public.app_role);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_set_staff_role(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_set_staff_role(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_upsert_my_customer(p_name text, p_phone text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := auth.uid(); v_email text; v_customer uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in to place a pickup order.' USING ERRCODE = '42501'; END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = v_user;
  SELECT id INTO v_customer FROM public.erp_customers WHERE auth_user_id = v_user;
  IF v_customer IS NULL AND v_email IS NOT NULL THEN
    SELECT id INTO v_customer FROM public.erp_customers WHERE lower(email) = lower(v_email) AND auth_user_id IS NULL LIMIT 1;
  END IF;
  IF v_customer IS NULL THEN
    INSERT INTO public.erp_customers (auth_user_id, name, email, phone)
    VALUES (v_user, COALESCE(NULLIF(trim(p_name), ''), v_email), v_email, NULLIF(trim(p_phone), ''))
    RETURNING id INTO v_customer;
  ELSE
    UPDATE public.erp_customers
       SET auth_user_id = v_user,
           name = COALESCE(NULLIF(trim(p_name), ''), name),
           phone = COALESCE(NULLIF(trim(p_phone), ''), phone)
     WHERE id = v_customer;
  END IF;
  RETURN v_customer;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_upsert_my_customer(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_upsert_my_customer(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_complete_pos_sale(
  p_location_id uuid,
  p_lines jsonb,
  p_discount_percent numeric DEFAULT 0,
  p_tax_rate numeric DEFAULT NULL,
  p_customer_id uuid DEFAULT NULL,
  p_sales_order_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_setting jsonb;
  v_tax_rate numeric(7,4);
  v_sale_id uuid;
  v_receipt bigint;
  v_line record;
  v_product record;
  v_component record;
  v_on_hand integer;
  v_reserved integer;
  v_available integer;
  v_finished integer;
  v_assemble integer;
  v_qty integer;
  v_price numeric(14,2);
  v_line_cost numeric(14,4);
  v_component_cost numeric(14,4);
  v_subtotal numeric(14,2) := 0;
  v_discount numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_cogs numeric(14,2) := 0;
  v_units integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = p_location_id AND is_active) THEN RAISE EXCEPTION 'Choose an active location.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'Cart is empty.'; END IF;
  IF p_discount_percent IS NULL OR p_discount_percent < 0 OR p_discount_percent > 100 THEN RAISE EXCEPTION 'Discount must be from 0 to 100 percent.'; END IF;
  SELECT setting_value INTO v_setting FROM public.erp_system_settings WHERE setting_key = 'tax_rate';
  v_tax_rate := COALESCE(p_tax_rate, (v_setting #>> '{}')::numeric, 0.0825);
  IF v_tax_rate < 0 OR v_tax_rate > 0.25 THEN RAISE EXCEPTION 'Tax rate must be from 0 to 25 percent.'; END IF;
  IF p_customer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.erp_customers WHERE id = p_customer_id) THEN RAISE EXCEPTION 'Customer not found.'; END IF;

  -- Validate and lock in stable order before making any change.
  FOR v_line IN
    SELECT x.product_id, sum(x.quantity)::integer AS quantity
    FROM jsonb_to_recordset(p_lines) AS x(product_id uuid, quantity integer)
    GROUP BY x.product_id ORDER BY x.product_id
  LOOP
    IF v_line.product_id IS NULL OR v_line.quantity IS NULL OR v_line.quantity <= 0 THEN RAISE EXCEPTION 'Enter a valid item and quantity.'; END IF;
    SELECT id, sku, name, price, cost, is_active INTO v_product FROM public.products WHERE id = v_line.product_id FOR SHARE;
    IF NOT FOUND OR NOT v_product.is_active THEN RAISE EXCEPTION 'A product in the cart is inactive.'; END IF;
    SELECT quantity_on_hand, quantity_reserved INTO v_on_hand, v_reserved
      FROM public.inventory_balances WHERE product_id = v_product.id AND location_id = p_location_id FOR UPDATE;
    v_available := COALESCE(v_on_hand, 0) - COALESCE(v_reserved, 0);
    IF EXISTS (SELECT 1 FROM public.erp_bom WHERE parent_product_id = v_product.id) THEN
      v_finished := LEAST(v_line.quantity, GREATEST(v_available, 0));
      v_assemble := v_line.quantity - v_finished;
      v_component_cost := 0;
      FOR v_component IN
        SELECT b.component_product_id, b.quantity_per, p.cost
        FROM public.erp_bom b JOIN public.products p ON p.id = b.component_product_id
        WHERE b.parent_product_id = v_product.id ORDER BY b.component_product_id
      LOOP
        SELECT quantity_on_hand, quantity_reserved INTO v_on_hand, v_reserved
          FROM public.inventory_balances WHERE product_id = v_component.component_product_id AND location_id = p_location_id FOR UPDATE;
        IF COALESCE(v_on_hand,0) - COALESCE(v_reserved,0) < v_component.quantity_per * v_assemble THEN
          RAISE EXCEPTION 'Not enough component stock to assemble % at this location.', v_product.name;
        END IF;
        v_component_cost := v_component_cost + v_component.cost * v_component.quantity_per * v_assemble;
      END LOOP;
      IF v_assemble > 0 AND NOT EXISTS (SELECT 1 FROM public.erp_bom WHERE parent_product_id = v_product.id) THEN RAISE EXCEPTION 'The kit has no bill of material.'; END IF;
      v_line_cost := CASE WHEN v_line.quantity = 0 THEN 0 ELSE (v_finished * v_product.cost + v_component_cost) / v_line.quantity END;
    ELSE
      IF v_available < v_line.quantity THEN RAISE EXCEPTION 'Not enough available stock for % (available: %).', v_product.name, GREATEST(v_available, 0); END IF;
      v_finished := v_line.quantity;
      v_line_cost := v_product.cost;
    END IF;
    v_subtotal := v_subtotal + round(v_product.price * v_line.quantity, 2);
    v_cogs := v_cogs + round(v_line_cost * v_line.quantity, 2);
    v_units := v_units + v_line.quantity;
  END LOOP;

  v_discount := round(v_subtotal * p_discount_percent / 100, 2);
  v_tax := round((v_subtotal - v_discount) * v_tax_rate, 2);
  v_total := v_subtotal - v_discount + v_tax;
  INSERT INTO public.pos_sales
    (location_id, cashier_id, customer_id, sales_order_id, source, subtotal, discount, tax, tax_rate, total, cogs)
  VALUES
    (p_location_id, v_user, p_customer_id, p_sales_order_id, CASE WHEN p_sales_order_id IS NULL THEN 'pos' ELSE 'pickup' END,
     v_subtotal, v_discount, v_tax, v_tax_rate, v_total, v_cogs)
  RETURNING id, receipt_number INTO v_sale_id, v_receipt;

  FOR v_line IN
    SELECT x.product_id, sum(x.quantity)::integer AS quantity
    FROM jsonb_to_recordset(p_lines) AS x(product_id uuid, quantity integer)
    GROUP BY x.product_id ORDER BY x.product_id
  LOOP
    SELECT id, sku, name, price, cost INTO v_product FROM public.products WHERE id = v_line.product_id;
    SELECT quantity_on_hand, quantity_reserved INTO v_on_hand, v_reserved
      FROM public.inventory_balances WHERE product_id = v_product.id AND location_id = p_location_id FOR UPDATE;
    v_available := COALESCE(v_on_hand, 0) - COALESCE(v_reserved, 0);
    IF EXISTS (SELECT 1 FROM public.erp_bom WHERE parent_product_id = v_product.id) THEN
      v_finished := LEAST(v_line.quantity, GREATEST(v_available, 0));
      v_assemble := v_line.quantity - v_finished;
      v_component_cost := 0;
      FOR v_component IN
        SELECT b.component_product_id, b.quantity_per, p.cost
        FROM public.erp_bom b JOIN public.products p ON p.id = b.component_product_id
        WHERE b.parent_product_id = v_product.id ORDER BY b.component_product_id
      LOOP
        IF v_assemble > 0 THEN
          v_component_cost := v_component_cost + v_component.cost * v_component.quantity_per * v_assemble;
        END IF;
      END LOOP;
      v_line_cost := (v_finished * v_product.cost + v_component_cost) / v_line.quantity;
      IF v_finished > 0 THEN
        UPDATE public.inventory_balances SET quantity_on_hand = quantity_on_hand - v_finished, updated_at = now()
          WHERE product_id = v_product.id AND location_id = p_location_id;
        INSERT INTO public.inventory_movements(product_id, location_id, quantity_change, movement_type, reason_code, reference_id)
          VALUES (v_product.id, p_location_id, -v_finished, 'SALE', 'POS', v_sale_id);
      END IF;
      FOR v_component IN
        SELECT b.component_product_id, b.quantity_per, p.cost
        FROM public.erp_bom b JOIN public.products p ON p.id = b.component_product_id
        WHERE b.parent_product_id = v_product.id ORDER BY b.component_product_id
      LOOP
        IF v_assemble > 0 THEN
          UPDATE public.inventory_balances SET quantity_on_hand = quantity_on_hand - v_component.quantity_per * v_assemble, updated_at = now()
            WHERE product_id = v_component.component_product_id AND location_id = p_location_id;
          INSERT INTO public.inventory_movements(product_id, location_id, quantity_change, movement_type, reason_code, reference_id)
            VALUES (v_component.component_product_id, p_location_id, -v_component.quantity_per * v_assemble, 'SALE_BOM', 'POS_ASSEMBLY', v_sale_id);
        END IF;
      END LOOP;
    ELSE
      v_line_cost := v_product.cost;
      UPDATE public.inventory_balances SET quantity_on_hand = quantity_on_hand - v_line.quantity, updated_at = now()
        WHERE product_id = v_product.id AND location_id = p_location_id;
      INSERT INTO public.inventory_movements(product_id, location_id, quantity_change, movement_type, reason_code, reference_id)
        VALUES (v_product.id, p_location_id, -v_line.quantity, 'SALE', 'POS', v_sale_id);
    END IF;
    INSERT INTO public.pos_sale_lines (sale_id, product_id, quantity, unit_price, unit_cost, line_subtotal)
    VALUES (v_sale_id, v_product.id, v_line.quantity, v_product.price, v_line_cost, round(v_product.price * v_line.quantity, 2));
  END LOOP;

  INSERT INTO public.erp_ledger_entries (source_type, source_id, location_id, account, debit, credit)
  VALUES
    ('sale', v_sale_id, p_location_id, 'Cash', v_total, 0),
    ('sale', v_sale_id, p_location_id, 'Sales revenue', 0, v_subtotal - v_discount),
    ('sale', v_sale_id, p_location_id, 'Sales tax payable', 0, v_tax),
    ('sale', v_sale_id, p_location_id, 'Cost of goods sold', v_cogs, 0),
    ('sale', v_sale_id, p_location_id, 'Inventory', 0, v_cogs);

  RETURN jsonb_build_object('sale_id', v_sale_id, 'receipt_number', v_receipt, 'subtotal', v_subtotal,
    'discount', v_discount, 'tax', v_tax, 'tax_rate', v_tax_rate, 'total', v_total, 'cogs', v_cogs, 'units', v_units);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_complete_pos_sale(uuid,jsonb,numeric,numeric,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_complete_pos_sale(uuid,jsonb,numeric,numeric,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_adjust_stock(
  p_product_id uuid, p_location_id uuid, p_quantity_change integer, p_reason_code text, p_barcode text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_on_hand integer; v_reserved integer; v_sku text;
BEGIN
  IF p_quantity_change IS NULL OR p_quantity_change = 0 THEN RAISE EXCEPTION 'Enter a non-zero count adjustment.'; END IF;
  IF NULLIF(trim(p_reason_code), '') IS NULL THEN RAISE EXCEPTION 'Choose a reason for the adjustment.'; END IF;
  SELECT sku INTO v_sku FROM public.products WHERE id = p_product_id AND is_active AND (p_barcode IS NULL OR barcode = p_barcode);
  IF NOT FOUND THEN RAISE EXCEPTION 'Product or scanned barcode not found.'; END IF;
  SELECT quantity_on_hand, quantity_reserved INTO v_on_hand, v_reserved
    FROM public.inventory_balances WHERE product_id = p_product_id AND location_id = p_location_id FOR UPDATE;
  IF NOT FOUND THEN
    IF p_quantity_change < 0 THEN RAISE EXCEPTION 'Cannot remove stock from an empty balance.'; END IF;
    INSERT INTO public.inventory_balances(product_id, location_id, quantity_on_hand, quantity_reserved)
      VALUES (p_product_id, p_location_id, p_quantity_change, 0);
  ELSE
    IF COALESCE(v_on_hand,0) + p_quantity_change < COALESCE(v_reserved,0) THEN RAISE EXCEPTION 'Adjustment would reduce stock below reserved quantity.'; END IF;
    UPDATE public.inventory_balances SET quantity_on_hand = quantity_on_hand + p_quantity_change, updated_at = now()
      WHERE product_id = p_product_id AND location_id = p_location_id;
  END IF;
  INSERT INTO public.inventory_movements(product_id, location_id, quantity_change, movement_type, reason_code)
    VALUES (p_product_id, p_location_id, p_quantity_change, 'ADJUSTMENT', trim(p_reason_code));
  RETURN jsonb_build_object('sku', v_sku, 'quantity_change', p_quantity_change);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_adjust_stock(uuid,uuid,integer,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_adjust_stock(uuid,uuid,integer,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_transfer_stock(p_product_id uuid, p_from_location uuid, p_to_location uuid, p_quantity integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_on_hand integer; v_reserved integer; v_transfer uuid := gen_random_uuid();
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_from_location = p_to_location THEN RAISE EXCEPTION 'Choose two different locations and a positive quantity.'; END IF;
  SELECT quantity_on_hand, quantity_reserved INTO v_on_hand, v_reserved FROM public.inventory_balances
    WHERE product_id = p_product_id AND location_id = p_from_location FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_on_hand,0) - COALESCE(v_reserved,0) < p_quantity THEN RAISE EXCEPTION 'Not enough available stock to transfer.'; END IF;
  UPDATE public.inventory_balances SET quantity_on_hand = quantity_on_hand - p_quantity, updated_at = now()
    WHERE product_id = p_product_id AND location_id = p_from_location;
  INSERT INTO public.inventory_balances(product_id, location_id, quantity_on_hand, quantity_reserved)
    VALUES (p_product_id, p_to_location, p_quantity, 0)
    ON CONFLICT (product_id, location_id) DO UPDATE
      SET quantity_on_hand = public.inventory_balances.quantity_on_hand + EXCLUDED.quantity_on_hand,
          updated_at = now();
  INSERT INTO public.inventory_movements(product_id, location_id, quantity_change, movement_type, reason_code, reference_id)
    VALUES (p_product_id, p_from_location, -p_quantity, 'TRANSFER_OUT', 'LOCATION_TRANSFER', v_transfer),
           (p_product_id, p_to_location, p_quantity, 'TRANSFER_IN', 'LOCATION_TRANSFER', v_transfer);
  RETURN jsonb_build_object('transfer_id', v_transfer, 'quantity', p_quantity);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_transfer_stock(uuid,uuid,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_transfer_stock(uuid,uuid,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION private.erp_create_sales_order(
  p_location_id uuid, p_lines jsonb, p_customer_id uuid, p_channel text, p_required_by date, p_user uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order uuid;
  v_line record;
  v_product record;
  v_on_hand integer;
  v_reserved integer;
  v_available integer;
  v_reserved_now integer;
  v_backordered integer;
  v_lead integer;
  v_subtotal numeric(14,2) := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = p_location_id AND is_active) THEN RAISE EXCEPTION 'Choose an active pickup location.'; END IF;
  IF p_channel NOT IN ('staff','pickup','online') THEN RAISE EXCEPTION 'Invalid order channel.'; END IF;
  IF p_channel <> 'staff' AND p_customer_id IS NULL THEN RAISE EXCEPTION 'A customer profile is required.'; END IF;
  IF p_customer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.erp_customers WHERE id = p_customer_id) THEN RAISE EXCEPTION 'Customer not found.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'Add at least one item.'; END IF;

  INSERT INTO public.erp_sales_orders (customer_id, location_id, created_by, channel, required_by)
  VALUES (p_customer_id, p_location_id, p_user, p_channel, p_required_by)
  RETURNING id INTO v_order;

  FOR v_line IN
    SELECT x.product_id, sum(x.quantity)::integer AS quantity
    FROM jsonb_to_recordset(p_lines) AS x(product_id uuid, quantity integer)
    GROUP BY x.product_id ORDER BY x.product_id
  LOOP
    IF v_line.product_id IS NULL OR v_line.quantity IS NULL OR v_line.quantity <= 0 THEN RAISE EXCEPTION 'Enter valid products and quantities.'; END IF;
    SELECT id, price, cost, is_active, lead_time_days INTO v_product FROM public.products WHERE id = v_line.product_id FOR SHARE;
    IF NOT FOUND OR NOT v_product.is_active THEN RAISE EXCEPTION 'A selected product is unavailable.'; END IF;
    SELECT quantity_on_hand, quantity_reserved INTO v_on_hand, v_reserved FROM public.inventory_balances
      WHERE product_id = v_product.id AND location_id = p_location_id FOR UPDATE;
    v_available := COALESCE(v_on_hand,0) - COALESCE(v_reserved,0);
    v_reserved_now := LEAST(v_line.quantity, GREATEST(v_available,0));
    v_backordered := v_line.quantity - v_reserved_now;
    SELECT COALESCE(min(sp.quoted_lead_time_days), v_product.lead_time_days, 14) INTO v_lead
      FROM public.erp_supplier_products sp WHERE sp.product_id = v_product.id;
    IF v_reserved_now > 0 THEN
      UPDATE public.inventory_balances SET quantity_reserved = quantity_reserved + v_reserved_now, updated_at = now()
        WHERE product_id = v_product.id AND location_id = p_location_id;
    END IF;
    INSERT INTO public.erp_sales_order_lines
      (order_id, product_id, quantity, quantity_fulfilled, quantity_backordered, estimated_available_date, unit_price, unit_cost)
    VALUES
      (v_order, v_product.id, v_line.quantity, 0, v_backordered,
       CASE WHEN v_backordered > 0 THEN current_date + COALESCE(v_lead,14) ELSE NULL END,
       v_product.price, v_product.cost);
    v_subtotal := v_subtotal + round(v_product.price * v_line.quantity,2);
  END LOOP;
  UPDATE public.erp_sales_orders SET subtotal = v_subtotal, total = v_subtotal WHERE id = v_order;
  RETURN v_order;
END;
$$;
REVOKE ALL ON FUNCTION private.erp_create_sales_order(uuid,jsonb,uuid,text,date,uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.erp_place_sales_order(
  p_location_id uuid, p_lines jsonb, p_customer_id uuid DEFAULT NULL,
  p_channel text DEFAULT 'staff', p_required_by date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_order uuid; v_number bigint;
BEGIN
  v_order := private.erp_create_sales_order(p_location_id,p_lines,p_customer_id,p_channel,p_required_by,v_user);
  SELECT order_number INTO v_number FROM public.erp_sales_orders WHERE id = v_order;
  RETURN jsonb_build_object('order_id',v_order,'order_number',v_number,'status','order_placed');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_place_sales_order(uuid,jsonb,uuid,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_place_sales_order(uuid,jsonb,uuid,text,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_place_pickup_order(
  p_location_id uuid, p_lines jsonb, p_name text, p_phone text DEFAULT NULL, p_required_by date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := auth.uid(); v_customer uuid; v_order uuid; v_number bigint;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in before placing a pickup order.' USING ERRCODE = '42501'; END IF;
  v_customer := public.erp_upsert_my_customer(p_name,p_phone);
  v_order := private.erp_create_sales_order(p_location_id,p_lines,v_customer,'pickup',p_required_by,v_user);
  SELECT order_number INTO v_number FROM public.erp_sales_orders WHERE id = v_order;
  RETURN jsonb_build_object('order_id',v_order,'order_number',v_number,'status','order_placed');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_place_pickup_order(uuid,jsonb,text,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_place_pickup_order(uuid,jsonb,text,text,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_fulfill_sales_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_order public.erp_sales_orders%ROWTYPE; v_lines jsonb; v_sale jsonb;
BEGIN
  SELECT * INTO v_order FROM public.erp_sales_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status <> 'order_placed' THEN RAISE EXCEPTION 'Only open orders can be fulfilled.'; END IF;
  UPDATE public.inventory_balances b
     SET quantity_reserved = GREATEST(b.quantity_reserved - (l.quantity-l.quantity_backordered),0), updated_at = now()
    FROM public.erp_sales_order_lines l
   WHERE l.order_id = p_order_id AND b.product_id = l.product_id AND b.location_id = v_order.location_id;
  SELECT jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity) ORDER BY product_id)
    INTO v_lines FROM public.erp_sales_order_lines WHERE order_id = p_order_id;
  v_sale := public.erp_complete_pos_sale(v_order.location_id,v_lines,0,NULL,v_order.customer_id,p_order_id);
  UPDATE public.erp_sales_orders SET status = 'fulfilled', fulfilled_at = now(), cogs = (v_sale->>'cogs')::numeric,
      tax = (v_sale->>'tax')::numeric, total = (v_sale->>'total')::numeric
    WHERE id = p_order_id;
  UPDATE public.erp_sales_order_lines SET quantity_fulfilled = quantity, quantity_backordered = 0 WHERE order_id = p_order_id;
  RETURN jsonb_build_object('order_id',p_order_id,'sale',v_sale,'status','fulfilled');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_fulfill_sales_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_fulfill_sales_order(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_cancel_sales_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_order public.erp_sales_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.erp_sales_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status <> 'order_placed' THEN RAISE EXCEPTION 'Only open orders can be cancelled.'; END IF;
  UPDATE public.inventory_balances b
     SET quantity_reserved = GREATEST(b.quantity_reserved - (l.quantity-l.quantity_backordered),0), updated_at = now()
    FROM public.erp_sales_order_lines l
   WHERE l.order_id = p_order_id AND b.product_id = l.product_id AND b.location_id = v_order.location_id;
  UPDATE public.erp_sales_orders SET status = 'cancelled', closed_at = now() WHERE id = p_order_id;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_cancel_sales_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_cancel_sales_order(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_process_return(
  p_sale_id uuid, p_product_id uuid, p_quantity integer, p_disposition text, p_reason_code text,
  p_exchange_product_id uuid DEFAULT NULL, p_exchange_quantity integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_sale public.pos_sales%ROWTYPE;
  v_original record;
  v_product record;
  v_return uuid;
  v_return_no bigint;
  v_previously_returned integer;
  v_unit_net numeric(14,4);
  v_return_subtotal numeric(14,2);
  v_return_tax numeric(14,2);
  v_refund numeric(14,2);
  v_exchange numeric(14,2) := 0;
  v_exchange_tax numeric(14,2) := 0;
  v_on_hand integer;
  v_reserved integer;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Return quantity must be positive.'; END IF;
  IF p_disposition NOT IN ('restock','quarantine') THEN RAISE EXCEPTION 'Choose restock or quarantine for the returned item.'; END IF;
  IF NULLIF(trim(p_reason_code),'') IS NULL THEN RAISE EXCEPTION 'Choose a return reason.'; END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original receipt not found.'; END IF;
  SELECT l.product_id,l.quantity,l.unit_price,l.unit_cost INTO v_original
    FROM public.pos_sale_lines l WHERE l.sale_id = p_sale_id AND l.product_id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'That item is not on the original receipt.'; END IF;
  SELECT COALESCE(sum(rl.quantity),0)::integer INTO v_previously_returned
    FROM public.erp_return_lines rl JOIN public.erp_returns r ON r.id = rl.return_id
   WHERE r.original_sale_id = p_sale_id AND rl.product_id = p_product_id AND rl.disposition <> 'exchange_out';
  IF v_previously_returned + p_quantity > v_original.quantity THEN RAISE EXCEPTION 'Return quantity exceeds the original sale.'; END IF;
  v_unit_net := v_original.unit_price * (1 - CASE WHEN v_sale.subtotal = 0 THEN 0 ELSE v_sale.discount / v_sale.subtotal END);
  v_return_subtotal := round(v_unit_net * p_quantity,2);
  v_return_tax := round(v_return_subtotal * v_sale.tax_rate,2);
  v_refund := v_return_subtotal + v_return_tax;
  IF p_exchange_product_id IS NOT NULL THEN
    IF p_exchange_quantity IS NULL OR p_exchange_quantity <= 0 THEN RAISE EXCEPTION 'Enter a positive exchange quantity.'; END IF;
    SELECT id,price,cost,is_active INTO v_product FROM public.products WHERE id = p_exchange_product_id FOR SHARE;
    IF NOT FOUND OR NOT v_product.is_active THEN RAISE EXCEPTION 'Exchange product is unavailable.'; END IF;
    SELECT quantity_on_hand,quantity_reserved INTO v_on_hand,v_reserved FROM public.inventory_balances
      WHERE product_id = p_exchange_product_id AND location_id = v_sale.location_id FOR UPDATE;
    IF COALESCE(v_on_hand,0)-COALESCE(v_reserved,0) < p_exchange_quantity THEN RAISE EXCEPTION 'Not enough stock for the exchange item.'; END IF;
    v_exchange := round(v_product.price * p_exchange_quantity,2);
    v_exchange_tax := round(v_exchange * v_sale.tax_rate,2);
  END IF;
  INSERT INTO public.erp_returns(original_sale_id,location_id,customer_id,created_by,kind,reason_code,refund_amount,exchange_amount)
    VALUES (p_sale_id,v_sale.location_id,v_sale.customer_id,v_user,CASE WHEN p_exchange_product_id IS NULL THEN 'refund' ELSE 'exchange' END,
      trim(p_reason_code),v_refund,v_exchange+v_exchange_tax)
    RETURNING id,return_number INTO v_return,v_return_no;
  INSERT INTO public.erp_return_lines(return_id,product_id,quantity,disposition,unit_price,unit_cost)
    VALUES (v_return,p_product_id,p_quantity,p_disposition,v_original.unit_price,v_original.unit_cost);
  IF p_disposition = 'restock' THEN
    INSERT INTO public.inventory_balances(product_id,location_id,quantity_on_hand,quantity_reserved)
      VALUES (p_product_id,v_sale.location_id,p_quantity,0)
      ON CONFLICT (product_id,location_id) DO UPDATE
        SET quantity_on_hand = public.inventory_balances.quantity_on_hand + EXCLUDED.quantity_on_hand, updated_at = now();
    INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
      VALUES (p_product_id,v_sale.location_id,p_quantity,'RETURN_RESTOCK',trim(p_reason_code),v_return);
  ELSE
    INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
      VALUES (p_product_id,v_sale.location_id,0,'RETURN_QUARANTINE',trim(p_reason_code),v_return);
  END IF;
  INSERT INTO public.erp_ledger_entries(source_type,source_id,location_id,account,debit,credit)
    VALUES ('return',v_return,v_sale.location_id,'Sales returns',v_return_subtotal,0),
           ('return',v_return,v_sale.location_id,'Sales tax payable',v_return_tax,0),
           ('return',v_return,v_sale.location_id,'Cash',0,v_refund);
  IF p_disposition = 'restock' THEN
    INSERT INTO public.erp_ledger_entries(source_type,source_id,location_id,account,debit,credit)
      VALUES ('return',v_return,v_sale.location_id,'Inventory',round(v_original.unit_cost*p_quantity,2),0),
             ('return',v_return,v_sale.location_id,'Cost of goods sold',0,round(v_original.unit_cost*p_quantity,2));
  END IF;
  IF p_exchange_product_id IS NOT NULL THEN
    INSERT INTO public.erp_return_lines(return_id,product_id,quantity,disposition,unit_price,unit_cost)
      VALUES (v_return,p_exchange_product_id,p_exchange_quantity,'exchange_out',v_product.price,v_product.cost);
    UPDATE public.inventory_balances SET quantity_on_hand = quantity_on_hand-p_exchange_quantity,updated_at=now()
      WHERE product_id=p_exchange_product_id AND location_id=v_sale.location_id;
    INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
      VALUES (p_exchange_product_id,v_sale.location_id,-p_exchange_quantity,'EXCHANGE_OUT','CUSTOMER_EXCHANGE',v_return);
    INSERT INTO public.erp_ledger_entries(source_type,source_id,location_id,account,debit,credit)
      VALUES ('exchange',v_return,v_sale.location_id,'Cash',v_exchange+v_exchange_tax,0),
             ('exchange',v_return,v_sale.location_id,'Sales revenue',0,v_exchange),
             ('exchange',v_return,v_sale.location_id,'Sales tax payable',0,v_exchange_tax),
             ('exchange',v_return,v_sale.location_id,'Cost of goods sold',round(v_product.cost*p_exchange_quantity,2),0),
             ('exchange',v_return,v_sale.location_id,'Inventory',0,round(v_product.cost*p_exchange_quantity,2));
  END IF;
  RETURN jsonb_build_object('return_id',v_return,'return_number',v_return_no,'refund_amount',v_refund,
    'exchange_amount',v_exchange+v_exchange_tax,'net_customer_credit',v_refund-(v_exchange+v_exchange_tax),'kind',
    CASE WHEN p_exchange_product_id IS NULL THEN 'refund' ELSE 'exchange' END);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_process_return(uuid,uuid,integer,text,text,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_process_return(uuid,uuid,integer,text,text,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_create_production_order(p_parent_product_id uuid, p_location_id uuid, p_quantity integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_id uuid; v_number bigint;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Production quantity must be positive.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id=p_parent_product_id AND is_active) THEN RAISE EXCEPTION 'Finished item not found.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id=p_location_id AND is_active) THEN RAISE EXCEPTION 'Choose an active production location.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.erp_bom WHERE parent_product_id=p_parent_product_id) THEN RAISE EXCEPTION 'This item needs a bill of material before production.'; END IF;
  INSERT INTO public.erp_production_orders(parent_product_id,location_id,created_by,quantity_started)
    VALUES(p_parent_product_id,p_location_id,v_user,p_quantity) RETURNING id,work_order_number INTO v_id,v_number;
  RETURN jsonb_build_object('production_order_id',v_id,'work_order_number',v_number,'status','planned');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_create_production_order(uuid,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_create_production_order(uuid,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_start_production_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_order public.erp_production_orders%ROWTYPE;
  v_component record;
  v_on_hand integer;
  v_reserved integer;
  v_required integer;
  v_cost numeric(14,2) := 0;
BEGIN
  SELECT * INTO v_order FROM public.erp_production_orders WHERE id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status <> 'planned' THEN RAISE EXCEPTION 'Only planned production orders can be started.'; END IF;
  FOR v_component IN
    SELECT b.component_product_id,b.quantity_per,p.cost,p.sku
    FROM public.erp_bom b JOIN public.products p ON p.id=b.component_product_id
    WHERE b.parent_product_id=v_order.parent_product_id ORDER BY b.component_product_id
  LOOP
    v_required := v_component.quantity_per * v_order.quantity_started;
    SELECT quantity_on_hand,quantity_reserved INTO v_on_hand,v_reserved FROM public.inventory_balances
      WHERE product_id=v_component.component_product_id AND location_id=v_order.location_id FOR UPDATE;
    IF COALESCE(v_on_hand,0)-COALESCE(v_reserved,0) < v_required THEN
      RAISE EXCEPTION 'Not enough % to start this build (need %, available %).',v_component.sku,v_required,GREATEST(COALESCE(v_on_hand,0)-COALESCE(v_reserved,0),0);
    END IF;
    v_cost := v_cost + round(v_component.cost * v_required,2);
  END LOOP;
  FOR v_component IN
    SELECT b.component_product_id,b.quantity_per,p.cost
    FROM public.erp_bom b JOIN public.products p ON p.id=b.component_product_id
    WHERE b.parent_product_id=v_order.parent_product_id ORDER BY b.component_product_id
  LOOP
    v_required := v_component.quantity_per * v_order.quantity_started;
    UPDATE public.inventory_balances SET quantity_on_hand=quantity_on_hand-v_required,updated_at=now()
      WHERE product_id=v_component.component_product_id AND location_id=v_order.location_id;
    INSERT INTO public.erp_production_components(production_order_id,component_product_id,quantity_required,quantity_consumed,unit_cost)
      VALUES(p_order_id,v_component.component_product_id,v_required,v_required,v_component.cost);
    INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
      VALUES(v_component.component_product_id,v_order.location_id,-v_required,'PRODUCTION_ISSUE','WORK_ORDER',p_order_id);
  END LOOP;
  UPDATE public.erp_production_orders SET status='issued',started_at=now(),component_cost=v_cost WHERE id=p_order_id;
  RETURN jsonb_build_object('production_order_id',p_order_id,'status','issued','component_cost',v_cost);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_start_production_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_start_production_order(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_finish_production_order(p_order_id uuid,p_good_quantity integer,p_scrapped_quantity integer,p_quality_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_order public.erp_production_orders%ROWTYPE;
  v_existing_qty integer;
  v_new_cost numeric(14,4);
  v_avg_cost numeric(14,4);
BEGIN
  SELECT * INTO v_order FROM public.erp_production_orders WHERE id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status <> 'issued' THEN RAISE EXCEPTION 'Only issued production orders can be completed.'; END IF;
  IF p_good_quantity IS NULL OR p_scrapped_quantity IS NULL OR p_good_quantity < 0 OR p_scrapped_quantity < 0
     OR p_good_quantity + p_scrapped_quantity <> v_order.quantity_started THEN
    RAISE EXCEPTION 'Good plus scrapped quantity must equal the amount started.';
  END IF;
  IF p_scrapped_quantity > 0 AND NULLIF(trim(p_quality_reason),'') IS NULL THEN RAISE EXCEPTION 'Add a reason for scrapped units.'; END IF;
  v_new_cost := CASE WHEN p_good_quantity=0 THEN 0 ELSE v_order.component_cost/p_good_quantity END;
  IF p_good_quantity > 0 THEN
    SELECT COALESCE(sum(quantity_on_hand),0) INTO v_existing_qty FROM public.inventory_balances WHERE product_id=v_order.parent_product_id;
    SELECT p.cost INTO v_avg_cost FROM public.products p WHERE p.id=v_order.parent_product_id FOR UPDATE;
    v_avg_cost := CASE WHEN v_existing_qty + p_good_quantity = 0 THEN v_new_cost
      ELSE ((v_avg_cost * v_existing_qty) + (v_new_cost * p_good_quantity)) / (v_existing_qty+p_good_quantity) END;
    UPDATE public.products SET cost=round(v_avg_cost,2) WHERE id=v_order.parent_product_id;
    INSERT INTO public.inventory_balances(product_id,location_id,quantity_on_hand,quantity_reserved)
      VALUES(v_order.parent_product_id,v_order.location_id,p_good_quantity,0)
      ON CONFLICT(product_id,location_id) DO UPDATE
        SET quantity_on_hand=public.inventory_balances.quantity_on_hand+EXCLUDED.quantity_on_hand,updated_at=now();
    INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
      VALUES(v_order.parent_product_id,v_order.location_id,p_good_quantity,'PRODUCTION_RECEIPT','WORK_ORDER',p_order_id);
  END IF;
  UPDATE public.erp_production_orders
    SET status='completed',quantity_completed_good=p_good_quantity,quantity_scrapped=p_scrapped_quantity,
        quality_reason=NULLIF(trim(p_quality_reason),''),finished_at=now()
    WHERE id=p_order_id;
  RETURN jsonb_build_object('production_order_id',p_order_id,'status','completed','good',p_good_quantity,
    'scrapped',p_scrapped_quantity,'unit_cost',round(v_new_cost,2));
END;
$$;
REVOKE ALL ON FUNCTION public.erp_finish_production_order(uuid,integer,integer,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_finish_production_order(uuid,integer,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_create_purchase_order(p_supplier_id uuid,p_location_id uuid,p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_supplier public.erp_suppliers%ROWTYPE;
  v_id uuid;
  v_number bigint;
  v_line record;
  v_cost numeric(14,2);
  v_total numeric(14,2) := 0;
BEGIN
  SELECT * INTO v_supplier FROM public.erp_suppliers WHERE id=p_supplier_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found or inactive.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id=p_location_id AND is_active) THEN RAISE EXCEPTION 'Choose an active receiving location.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines)=0 THEN RAISE EXCEPTION 'Add at least one item to the purchase order.'; END IF;
  INSERT INTO public.erp_purchase_orders(supplier_id,location_id,created_by,status,order_date,expected_receipt_date,payment_terms_days)
    VALUES(p_supplier_id,p_location_id,v_user,'order_sent',current_date,current_date+v_supplier.quoted_lead_time_days,v_supplier.payment_terms_days)
    RETURNING id,po_number INTO v_id,v_number;
  FOR v_line IN
    SELECT x.product_id,sum(x.quantity)::integer AS quantity
    FROM jsonb_to_recordset(p_lines) AS x(product_id uuid,quantity integer)
    GROUP BY x.product_id ORDER BY x.product_id
  LOOP
    IF v_line.quantity IS NULL OR v_line.quantity<=0 THEN RAISE EXCEPTION 'Purchase quantities must be positive.'; END IF;
    SELECT sp.quoted_cost INTO v_cost FROM public.erp_supplier_products sp
      WHERE sp.supplier_id=p_supplier_id AND sp.product_id=v_line.product_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'This supplier is not approved for one of the selected components.'; END IF;
    INSERT INTO public.erp_purchase_order_lines(purchase_order_id,product_id,quantity_ordered,unit_cost)
      VALUES(v_id,v_line.product_id,v_line.quantity,v_cost);
    v_total := v_total + v_line.quantity*v_cost;
  END LOOP;
  UPDATE public.erp_purchase_orders SET total=v_total WHERE id=v_id;
  RETURN jsonb_build_object('purchase_order_id',v_id,'po_number',v_number,'expected_receipt_date',current_date+v_supplier.quoted_lead_time_days,'status','order_sent');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_create_purchase_order(uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_create_purchase_order(uuid,uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_receive_purchase_order(p_purchase_order_id uuid,p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_po public.erp_purchase_orders%ROWTYPE;
  v_line record;
  v_po_line public.erp_purchase_order_lines%ROWTYPE;
  v_old_qty integer;
  v_old_cost numeric(14,4);
  v_total_received boolean;
BEGIN
  SELECT * INTO v_po FROM public.erp_purchase_orders WHERE id=p_purchase_order_id FOR UPDATE;
  IF NOT FOUND OR v_po.status NOT IN ('order_sent','received') THEN RAISE EXCEPTION 'This purchase order cannot receive more items.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines)=0 THEN RAISE EXCEPTION 'Enter received quantities.'; END IF;
  FOR v_line IN SELECT x.line_id,x.quantity FROM jsonb_to_recordset(p_lines) AS x(line_id uuid,quantity integer) ORDER BY x.line_id LOOP
    IF v_line.quantity IS NULL OR v_line.quantity<=0 THEN RAISE EXCEPTION 'Received quantities must be positive.'; END IF;
    SELECT * INTO v_po_line FROM public.erp_purchase_order_lines WHERE id=v_line.line_id AND purchase_order_id=p_purchase_order_id FOR UPDATE;
    IF NOT FOUND OR v_po_line.quantity_received+v_line.quantity>v_po_line.quantity_ordered THEN RAISE EXCEPTION 'Received quantity exceeds the purchase order.'; END IF;
    SELECT COALESCE(sum(quantity_on_hand),0) INTO v_old_qty FROM public.inventory_balances WHERE product_id=v_po_line.product_id;
    SELECT cost INTO v_old_cost FROM public.products WHERE id=v_po_line.product_id FOR UPDATE;
    UPDATE public.products SET cost=CASE WHEN v_old_qty+v_line.quantity=0 THEN v_po_line.unit_cost
      ELSE round(((v_old_cost*v_old_qty)+(v_po_line.unit_cost*v_line.quantity))/(v_old_qty+v_line.quantity),2) END
      WHERE id=v_po_line.product_id;
    INSERT INTO public.inventory_balances(product_id,location_id,quantity_on_hand,quantity_reserved)
      VALUES(v_po_line.product_id,v_po.location_id,v_line.quantity,0)
      ON CONFLICT(product_id,location_id) DO UPDATE
        SET quantity_on_hand=public.inventory_balances.quantity_on_hand+EXCLUDED.quantity_on_hand,updated_at=now();
    UPDATE public.erp_purchase_order_lines SET quantity_received=quantity_received+v_line.quantity WHERE id=v_line.line_id;
    INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
      VALUES(v_po_line.product_id,v_po.location_id,v_line.quantity,'PO_RECEIPT','PURCHASE_ORDER',p_purchase_order_id);
  END LOOP;
  SELECT bool_and(quantity_received>=quantity_ordered) INTO v_total_received
    FROM public.erp_purchase_order_lines WHERE purchase_order_id=p_purchase_order_id;
  UPDATE public.erp_purchase_orders SET status=CASE WHEN v_total_received THEN 'received' ELSE 'order_sent' END,
      actual_receipt_date=CASE WHEN v_total_received THEN current_date ELSE actual_receipt_date END
    WHERE id=p_purchase_order_id;
  RETURN jsonb_build_object('purchase_order_id',p_purchase_order_id,'fully_received',v_total_received);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_receive_purchase_order(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_receive_purchase_order(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_close_purchase_order(p_purchase_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff();
BEGIN
  UPDATE public.erp_purchase_orders SET status='closed',closed_at=now()
   WHERE id=p_purchase_order_id AND status='received';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only fully received purchase orders can be closed.'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_close_purchase_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_close_purchase_order(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_record_supplier_payment(p_purchase_order_id uuid,p_amount numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff(); v_po public.erp_purchase_orders%ROWTYPE;
BEGIN
  IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Payment must be positive.'; END IF;
  SELECT * INTO v_po FROM public.erp_purchase_orders WHERE id=p_purchase_order_id FOR UPDATE;
  IF NOT FOUND OR v_po.amount_paid+p_amount>v_po.total THEN RAISE EXCEPTION 'Payment exceeds the amount owed.'; END IF;
  UPDATE public.erp_purchase_orders SET amount_paid=amount_paid+p_amount WHERE id=p_purchase_order_id;
  RETURN jsonb_build_object('purchase_order_id',p_purchase_order_id,'amount_paid',v_po.amount_paid+p_amount,'amount_owed',v_po.total-v_po.amount_paid-p_amount);
END;
$$;
REVOKE ALL ON FUNCTION public.erp_record_supplier_payment(uuid,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_record_supplier_payment(uuid,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_close_sales_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := private.erp_require_staff();
BEGIN
  UPDATE public.erp_sales_orders SET status='closed',closed_at=now()
   WHERE id=p_order_id AND status='fulfilled';
  IF NOT FOUND THEN RAISE EXCEPTION 'Only fulfilled orders can be closed.'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_close_sales_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_close_sales_order(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_post_cycle_count(p_location_id uuid,p_counts jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := private.erp_require_staff();
  v_count uuid;
  v_number bigint;
  v_line record;
  v_on_hand integer;
  v_reserved integer;
  v_delta integer;
  v_variance integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id=p_location_id AND is_active) THEN RAISE EXCEPTION 'Choose an active count location.'; END IF;
  IF p_counts IS NULL OR jsonb_typeof(p_counts)<>'array' OR jsonb_array_length(p_counts)=0 THEN RAISE EXCEPTION 'Enter at least one counted item.'; END IF;
  INSERT INTO public.erp_cycle_counts(location_id,created_by) VALUES(p_location_id,v_user) RETURNING id,count_number INTO v_count,v_number;
  FOR v_line IN SELECT x.product_id,x.counted_quantity FROM jsonb_to_recordset(p_counts) AS x(product_id uuid,counted_quantity integer) ORDER BY x.product_id LOOP
    IF v_line.counted_quantity IS NULL OR v_line.counted_quantity<0 THEN RAISE EXCEPTION 'Counted quantity cannot be negative.'; END IF;
    SELECT quantity_on_hand,quantity_reserved INTO v_on_hand,v_reserved FROM public.inventory_balances
      WHERE product_id=v_line.product_id AND location_id=p_location_id FOR UPDATE;
    v_on_hand := COALESCE(v_on_hand,0); v_reserved := COALESCE(v_reserved,0); v_delta := v_line.counted_quantity-v_on_hand;
    IF v_line.counted_quantity<v_reserved THEN RAISE EXCEPTION 'Count would put stock below reserved quantity.'; END IF;
    INSERT INTO public.erp_cycle_count_lines(count_id,product_id,expected_quantity,counted_quantity)
      VALUES(v_count,v_line.product_id,v_on_hand,v_line.counted_quantity);
    IF v_delta<>0 THEN
      INSERT INTO public.inventory_balances(product_id,location_id,quantity_on_hand,quantity_reserved)
        VALUES(v_line.product_id,p_location_id,v_line.counted_quantity,0)
        ON CONFLICT(product_id,location_id) DO UPDATE
          SET quantity_on_hand=EXCLUDED.quantity_on_hand,updated_at=now();
      INSERT INTO public.inventory_movements(product_id,location_id,quantity_change,movement_type,reason_code,reference_id)
        VALUES(v_line.product_id,p_location_id,v_delta,'CYCLE_COUNT','COUNT_VARIANCE',v_count);
      v_variance := v_variance + abs(v_delta);
    END IF;
  END LOOP;
  UPDATE public.erp_cycle_counts SET status='posted',posted_at=now() WHERE id=v_count;
  RETURN jsonb_build_object('count_id',v_count,'count_number',v_number,'absolute_variance_units',v_variance,'status','posted');
END;
$$;
REVOKE ALL ON FUNCTION public.erp_post_cycle_count(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_post_cycle_count(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_save_supplier(
  p_supplier_id uuid,p_supplier_code text,p_name text,p_contact_name text,p_email text,p_phone text,
  p_quoted_lead_time_days integer,p_payment_terms_days integer,p_ordering_cost numeric,p_annual_holding_rate numeric
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_id uuid; v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL OR NOT (private.has_role(v_user,'admin') OR private.has_role(v_user,'manager')) THEN
    RAISE EXCEPTION 'Manager access required to edit suppliers.' USING ERRCODE='42501';
  END IF;
  IF NULLIF(trim(p_supplier_code),'') IS NULL OR NULLIF(trim(p_name),'') IS NULL THEN RAISE EXCEPTION 'Supplier code and name are required.'; END IF;
  IF p_quoted_lead_time_days<0 OR p_payment_terms_days<0 OR p_ordering_cost<0 OR p_annual_holding_rate<0 THEN RAISE EXCEPTION 'Supplier terms cannot be negative.'; END IF;
  IF p_supplier_id IS NULL THEN
    INSERT INTO public.erp_suppliers(supplier_code,name,contact_name,email,phone,quoted_lead_time_days,payment_terms_days,ordering_cost,annual_holding_rate)
    VALUES(trim(p_supplier_code),trim(p_name),NULLIF(trim(p_contact_name),''),NULLIF(trim(p_email),''),NULLIF(trim(p_phone),''),
      p_quoted_lead_time_days,p_payment_terms_days,p_ordering_cost,p_annual_holding_rate) RETURNING id INTO v_id;
  ELSE
    UPDATE public.erp_suppliers SET supplier_code=trim(p_supplier_code),name=trim(p_name),contact_name=NULLIF(trim(p_contact_name),''),
      email=NULLIF(trim(p_email),''),phone=NULLIF(trim(p_phone),''),quoted_lead_time_days=p_quoted_lead_time_days,
      payment_terms_days=p_payment_terms_days,ordering_cost=p_ordering_cost,annual_holding_rate=p_annual_holding_rate
      WHERE id=p_supplier_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Supplier not found.'; END IF;
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_save_supplier(uuid,text,text,text,text,text,integer,integer,numeric,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_save_supplier(uuid,text,text,text,text,text,integer,integer,numeric,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_set_supplier_product(
  p_supplier_id uuid,p_product_id uuid,p_quoted_cost numeric,p_lead_time_days integer,p_is_preferred boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL OR NOT (private.has_role(v_user,'admin') OR private.has_role(v_user,'manager')) THEN
    RAISE EXCEPTION 'Manager access required to edit supplier catalogs.' USING ERRCODE='42501';
  END IF;
  IF p_quoted_cost<0 OR p_lead_time_days<0 THEN RAISE EXCEPTION 'Supplier cost and lead time cannot be negative.'; END IF;
  IF p_is_preferred THEN UPDATE public.erp_supplier_products SET is_preferred=false WHERE product_id=p_product_id; END IF;
  INSERT INTO public.erp_supplier_products(supplier_id,product_id,quoted_cost,quoted_lead_time_days,is_preferred)
  VALUES(p_supplier_id,p_product_id,p_quoted_cost,p_lead_time_days,p_is_preferred)
  ON CONFLICT(supplier_id,product_id) DO UPDATE SET quoted_cost=EXCLUDED.quoted_cost,
    quoted_lead_time_days=EXCLUDED.quoted_lead_time_days,is_preferred=EXCLUDED.is_preferred;
END;
$$;
REVOKE ALL ON FUNCTION public.erp_set_supplier_product(uuid,uuid,numeric,integer,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_set_supplier_product(uuid,uuid,numeric,integer,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.erp_set_setting(p_setting_key text,p_setting_value jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL OR NOT (private.has_role(v_user,'admin') OR private.has_role(v_user,'manager')) THEN
    RAISE EXCEPTION 'Manager access required to change settings.' USING ERRCODE='42501';
  END IF;
  IF p_setting_key NOT IN ('tax_rate','ordering_cost','annual_holding_rate') THEN RAISE EXCEPTION 'This setting cannot be edited here.'; END IF;
  IF p_setting_value IS NULL THEN RAISE EXCEPTION 'Setting value is required.'; END IF;
  INSERT INTO public.erp_system_settings(setting_key,setting_value,updated_by,updated_at)
  VALUES(p_setting_key,p_setting_value,v_user,now())
  ON CONFLICT(setting_key) DO UPDATE SET setting_value=EXCLUDED.setting_value,updated_by=v_user,updated_at=now();
END;
$$;
REVOKE ALL ON FUNCTION public.erp_set_setting(text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_set_setting(text,jsonb) TO authenticated;
