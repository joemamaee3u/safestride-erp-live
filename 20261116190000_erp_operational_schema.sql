-- Additive operational schema for the SafeStride class demo.
-- Existing product, location, balance, movement, role, and auth data is preserved.

CREATE TABLE IF NOT EXISTS public.erp_suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_code text NOT NULL UNIQUE,
  name text NOT NULL,
  contact_name text,
  email text,
  phone text,
  quoted_lead_time_days integer NOT NULL DEFAULT 14 CHECK (quoted_lead_time_days >= 0),
  payment_terms_days integer NOT NULL DEFAULT 30 CHECK (payment_terms_days >= 0),
  ordering_cost numeric(12,2) NOT NULL DEFAULT 35 CHECK (ordering_cost >= 0),
  annual_holding_rate numeric(6,4) NOT NULL DEFAULT 0.24 CHECK (annual_holding_rate >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.erp_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  email text,
  phone text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS erp_customers_email_lower_idx
  ON public.erp_customers (lower(email)) WHERE email IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.erp_supplier_products (
  supplier_id uuid NOT NULL REFERENCES public.erp_suppliers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  quoted_cost numeric(12,2) NOT NULL CHECK (quoted_cost >= 0),
  quoted_lead_time_days integer NOT NULL CHECK (quoted_lead_time_days >= 0),
  is_preferred boolean NOT NULL DEFAULT false,
  PRIMARY KEY (supplier_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.erp_bom (
  parent_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  component_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_per integer NOT NULL CHECK (quantity_per > 0),
  PRIMARY KEY (parent_product_id, component_product_id),
  CHECK (parent_product_id <> component_product_id)
);

CREATE TABLE IF NOT EXISTS public.pos_sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  location_id uuid NOT NULL REFERENCES public.locations(id),
  cashier_id uuid REFERENCES auth.users(id),
  customer_id uuid REFERENCES public.erp_customers(id),
  sales_order_id uuid,
  source text NOT NULL DEFAULT 'pos' CHECK (source IN ('pos', 'pickup', 'online', 'demo_history')),
  subtotal numeric(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  discount numeric(14,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  tax numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax >= 0),
  tax_rate numeric(7,4) NOT NULL DEFAULT 0 CHECK (tax_rate >= 0),
  total numeric(14,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  cogs numeric(14,2) NOT NULL DEFAULT 0 CHECK (cogs >= 0),
  is_demo_history boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pos_sales ADD COLUMN IF NOT EXISTS customer_id uuid REFERENCES public.erp_customers(id);
ALTER TABLE public.pos_sales ADD COLUMN IF NOT EXISTS sales_order_id uuid;
ALTER TABLE public.pos_sales ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'pos';
ALTER TABLE public.pos_sales ADD COLUMN IF NOT EXISTS tax_rate numeric(7,4) NOT NULL DEFAULT 0;
ALTER TABLE public.pos_sales ADD COLUMN IF NOT EXISTS is_demo_history boolean NOT NULL DEFAULT false;
-- Demo history and online orders can have no cashier; completed staff POS sales always set one.
ALTER TABLE public.pos_sales ALTER COLUMN cashier_id DROP NOT NULL;

CREATE TABLE IF NOT EXISTS public.pos_sale_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  quantity integer NOT NULL CHECK (quantity > 0),
  unit_price numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  unit_cost numeric(14,2) NOT NULL CHECK (unit_cost >= 0),
  line_subtotal numeric(14,2) NOT NULL CHECK (line_subtotal >= 0)
);

CREATE TABLE IF NOT EXISTS public.erp_sales_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  customer_id uuid REFERENCES public.erp_customers(id),
  location_id uuid NOT NULL REFERENCES public.locations(id),
  created_by uuid REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'order_placed' CHECK (status IN ('order_placed', 'fulfilled', 'closed', 'cancelled')),
  channel text NOT NULL DEFAULT 'staff' CHECK (channel IN ('staff', 'pickup', 'online')),
  is_demo_history boolean NOT NULL DEFAULT false,
  required_by date,
  subtotal numeric(14,2) NOT NULL DEFAULT 0,
  discount numeric(14,2) NOT NULL DEFAULT 0,
  tax numeric(14,2) NOT NULL DEFAULT 0,
  total numeric(14,2) NOT NULL DEFAULT 0,
  cogs numeric(14,2) NOT NULL DEFAULT 0,
  placed_at timestamptz NOT NULL DEFAULT now(),
  fulfilled_at timestamptz,
  closed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.erp_sales_order_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.erp_sales_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  quantity integer NOT NULL CHECK (quantity > 0),
  quantity_fulfilled integer NOT NULL DEFAULT 0 CHECK (quantity_fulfilled >= 0),
  quantity_backordered integer NOT NULL DEFAULT 0 CHECK (quantity_backordered >= 0),
  estimated_available_date date,
  unit_price numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  unit_cost numeric(14,2) NOT NULL CHECK (unit_cost >= 0)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pos_sales_sales_order_id_fkey' AND conrelid='public.pos_sales'::regclass) THEN
    ALTER TABLE public.pos_sales ADD CONSTRAINT pos_sales_sales_order_id_fkey
      FOREIGN KEY (sales_order_id) REFERENCES public.erp_sales_orders(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.erp_purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  supplier_id uuid NOT NULL REFERENCES public.erp_suppliers(id),
  location_id uuid NOT NULL REFERENCES public.locations(id),
  created_by uuid REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'order_sent' CHECK (status IN ('order_sent', 'received', 'closed', 'cancelled')),
  order_date date NOT NULL DEFAULT current_date,
  expected_receipt_date date NOT NULL,
  actual_receipt_date date,
  payment_terms_days integer NOT NULL DEFAULT 30 CHECK (payment_terms_days >= 0),
  amount_paid numeric(14,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  total numeric(14,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  is_demo_history boolean NOT NULL DEFAULT false,
  closed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.erp_purchase_order_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id uuid NOT NULL REFERENCES public.erp_purchase_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  quantity_ordered integer NOT NULL CHECK (quantity_ordered > 0),
  quantity_received integer NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
  unit_cost numeric(14,2) NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE IF NOT EXISTS public.erp_production_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  parent_product_id uuid NOT NULL REFERENCES public.products(id),
  location_id uuid NOT NULL REFERENCES public.locations(id),
  created_by uuid REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'issued', 'completed', 'cancelled')),
  quantity_started integer NOT NULL CHECK (quantity_started > 0),
  quantity_completed_good integer NOT NULL DEFAULT 0 CHECK (quantity_completed_good >= 0),
  quantity_scrapped integer NOT NULL DEFAULT 0 CHECK (quantity_scrapped >= 0),
  quality_reason text,
  component_cost numeric(14,2) NOT NULL DEFAULT 0,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.erp_production_components (
  production_order_id uuid NOT NULL REFERENCES public.erp_production_orders(id) ON DELETE CASCADE,
  component_product_id uuid NOT NULL REFERENCES public.products(id),
  quantity_required integer NOT NULL CHECK (quantity_required > 0),
  quantity_consumed integer NOT NULL DEFAULT 0 CHECK (quantity_consumed >= 0),
  unit_cost numeric(14,2) NOT NULL CHECK (unit_cost >= 0),
  PRIMARY KEY (production_order_id, component_product_id)
);

CREATE TABLE IF NOT EXISTS public.erp_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  original_sale_id uuid NOT NULL REFERENCES public.pos_sales(id),
  location_id uuid NOT NULL REFERENCES public.locations(id),
  customer_id uuid REFERENCES public.erp_customers(id),
  created_by uuid REFERENCES auth.users(id),
  kind text NOT NULL CHECK (kind IN ('refund', 'exchange')),
  reason_code text NOT NULL,
  refund_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (refund_amount >= 0),
  exchange_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (exchange_amount >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.erp_return_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id uuid NOT NULL REFERENCES public.erp_returns(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  quantity integer NOT NULL CHECK (quantity > 0),
  disposition text NOT NULL CHECK (disposition IN ('restock', 'quarantine', 'exchange_out')),
  unit_price numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  unit_cost numeric(14,2) NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE IF NOT EXISTS public.erp_cycle_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  location_id uuid NOT NULL REFERENCES public.locations(id),
  created_by uuid REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'posted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  posted_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.erp_cycle_count_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id uuid NOT NULL REFERENCES public.erp_cycle_counts(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  expected_quantity integer NOT NULL,
  counted_quantity integer NOT NULL CHECK (counted_quantity >= 0),
  UNIQUE (count_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.erp_system_settings (
  setting_key text PRIMARY KEY,
  setting_value jsonb NOT NULL,
  updated_by uuid REFERENCES auth.users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.erp_ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  location_id uuid REFERENCES public.locations(id),
  account text NOT NULL,
  debit numeric(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (debit = 0 OR credit = 0)
);

CREATE INDEX IF NOT EXISTS erp_sales_orders_status_date_idx ON public.erp_sales_orders(status, placed_at DESC);
CREATE INDEX IF NOT EXISTS erp_purchase_orders_supplier_date_idx ON public.erp_purchase_orders(supplier_id, order_date DESC);
CREATE INDEX IF NOT EXISTS erp_production_orders_date_idx ON public.erp_production_orders(created_at DESC);
CREATE INDEX IF NOT EXISTS erp_returns_sale_idx ON public.erp_returns(original_sale_id);
CREATE INDEX IF NOT EXISTS erp_ledger_account_date_idx ON public.erp_ledger_entries(account, created_at DESC);
CREATE INDEX IF NOT EXISTS erp_supplier_product_product_idx ON public.erp_supplier_products(product_id);

ALTER TABLE public.erp_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_supplier_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_bom ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_sale_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_sales_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_sales_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_purchase_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_production_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_production_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_return_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_cycle_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_cycle_count_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erp_ledger_entries ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'erp_suppliers','erp_supplier_products','erp_bom','pos_sales','pos_sale_lines',
    'erp_sales_orders','erp_sales_order_lines','erp_purchase_orders','erp_purchase_order_lines',
    'erp_production_orders','erp_production_components','erp_returns','erp_return_lines',
    'erp_cycle_counts','erp_cycle_count_lines','erp_system_settings','erp_ledger_entries'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_staff_read', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (private.is_staff((select auth.uid())))', t || '_staff_read', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS erp_customers_owner_or_staff_read ON public.erp_customers;
CREATE POLICY erp_customers_owner_or_staff_read ON public.erp_customers
  FOR SELECT TO authenticated
  USING (auth_user_id = (select auth.uid()) OR private.is_staff((select auth.uid())));

DROP POLICY IF EXISTS erp_sales_orders_owner_or_staff_read ON public.erp_sales_orders;
CREATE POLICY erp_sales_orders_owner_or_staff_read ON public.erp_sales_orders
  FOR SELECT TO authenticated
  USING (
    private.is_staff((select auth.uid())) OR
    EXISTS (SELECT 1 FROM public.erp_customers c WHERE c.id = customer_id AND c.auth_user_id = (select auth.uid()))
  );

DROP POLICY IF EXISTS erp_sales_order_lines_owner_or_staff_read ON public.erp_sales_order_lines;
CREATE POLICY erp_sales_order_lines_owner_or_staff_read ON public.erp_sales_order_lines
  FOR SELECT TO authenticated
  USING (
    private.is_staff((select auth.uid())) OR
    EXISTS (
      SELECT 1 FROM public.erp_sales_orders o
      JOIN public.erp_customers c ON c.id = o.customer_id
      WHERE o.id = order_id AND c.auth_user_id = (select auth.uid())
    )
  );

GRANT SELECT ON public.erp_suppliers, public.erp_supplier_products, public.erp_bom,
  public.pos_sales, public.pos_sale_lines, public.erp_sales_orders, public.erp_sales_order_lines,
  public.erp_purchase_orders, public.erp_purchase_order_lines, public.erp_production_orders,
  public.erp_production_components, public.erp_returns, public.erp_return_lines,
  public.erp_cycle_counts, public.erp_cycle_count_lines, public.erp_system_settings,
  public.erp_ledger_entries TO authenticated;
GRANT SELECT ON public.erp_customers TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.erp_suppliers, public.erp_customers, public.erp_supplier_products,
  public.erp_bom, public.pos_sales, public.pos_sale_lines, public.erp_sales_orders,
  public.erp_sales_order_lines, public.erp_purchase_orders, public.erp_purchase_order_lines,
  public.erp_production_orders, public.erp_production_components, public.erp_returns,
  public.erp_return_lines, public.erp_cycle_counts, public.erp_cycle_count_lines,
  public.erp_system_settings, public.erp_ledger_entries FROM anon, authenticated;

-- Public storefront only needs the existing safe inventory availability RPC.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory_balances; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.pos_sales; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_sales_orders; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_purchase_orders; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_production_orders; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_sales_order_lines; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_purchase_order_lines; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_returns; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_return_lines; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_cycle_counts; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_suppliers; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_supplier_products; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.erp_system_settings; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
END $$;
