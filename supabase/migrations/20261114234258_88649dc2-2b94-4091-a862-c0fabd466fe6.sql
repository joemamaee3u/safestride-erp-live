-- Staff roles (additive; existing tables, policies, and data are untouched)
CREATE TYPE public.app_role AS ENUM ('admin', 'manager', 'employee');

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own roles"
  ON public.user_roles FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION public.is_staff(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role IN ('admin', 'manager', 'employee')
  )
$$;

REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_staff(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_staff(uuid) TO authenticated, service_role;

-- Public, read-only availability: no cost or other financial fields
CREATE OR REPLACE FUNCTION public.get_inventory_availability()
RETURNS TABLE (
  product_id uuid,
  sku text,
  product_name text,
  category text,
  barcode text,
  price numeric,
  reorder_point integer,
  location_id uuid,
  location_name text,
  location_type text,
  quantity_on_hand integer,
  quantity_reserved integer,
  quantity_available integer
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.id, p.sku, p.name, p.category, p.barcode, p.price, p.reorder_point,
    l.id, l.name, l.location_type,
    COALESCE(b.quantity_on_hand, 0),
    COALESCE(b.quantity_reserved, 0),
    COALESCE(b.quantity_on_hand, 0) - COALESCE(b.quantity_reserved, 0)
  FROM public.products p
  CROSS JOIN public.locations l
  LEFT JOIN public.inventory_balances b
    ON b.product_id = p.id AND b.location_id = l.id
  WHERE p.is_active AND l.is_active
  ORDER BY p.sku, l.name
$$;

REVOKE EXECUTE ON FUNCTION public.get_inventory_availability() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_inventory_availability() TO anon, authenticated, service_role;

-- Staff only: product costs
CREATE OR REPLACE FUNCTION public.get_inventory_costs()
RETURNS TABLE (product_id uuid, cost numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_staff(auth.uid()) THEN
    RAISE EXCEPTION 'Staff access required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT p.id, p.cost FROM public.products p WHERE p.is_active;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_inventory_costs() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_inventory_costs() TO authenticated, service_role;

-- Staff only: movement history (read-only)
CREATE OR REPLACE FUNCTION public.get_inventory_movements(p_limit integer DEFAULT 500)
RETURNS TABLE (
  id uuid,
  created_at timestamptz,
  product_id uuid,
  sku text,
  product_name text,
  location_id uuid,
  location_name text,
  quantity_change integer,
  movement_type text,
  reason_code text,
  reference_id uuid
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_staff(auth.uid()) THEN
    RAISE EXCEPTION 'Staff access required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT m.id, m.created_at, p.id, p.sku, p.name, l.id, l.name,
           m.quantity_change, m.movement_type, m.reason_code, m.reference_id
    FROM public.inventory_movements m
    JOIN public.products p ON p.id = m.product_id
    JOIN public.locations l ON l.id = m.location_id
    ORDER BY m.created_at DESC, p.sku
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 2000);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_inventory_movements(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_inventory_movements(integer) TO authenticated, service_role;