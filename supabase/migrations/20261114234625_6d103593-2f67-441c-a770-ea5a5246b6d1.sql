-- Move privileged logic out of the public API schema; keep thin SECURITY INVOKER wrappers in public.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.is_staff(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role IN ('admin', 'manager', 'employee')
  )
$$;

CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION private.inventory_availability()
RETURNS TABLE (
  product_id uuid, sku text, product_name text, category text, barcode text,
  price numeric, reorder_point integer, location_id uuid, location_name text,
  location_type text, quantity_on_hand integer, quantity_reserved integer,
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

CREATE OR REPLACE FUNCTION private.inventory_costs()
RETURNS TABLE (product_id uuid, cost numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_staff(auth.uid()) THEN
    RAISE EXCEPTION 'Staff access required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT p.id, p.cost FROM public.products p WHERE p.is_active;
END;
$$;

CREATE OR REPLACE FUNCTION private.inventory_movements(p_limit integer DEFAULT 500)
RETURNS TABLE (
  id uuid, created_at timestamptz, product_id uuid, sku text, product_name text,
  location_id uuid, location_name text, quantity_change integer,
  movement_type text, reason_code text, reference_id uuid
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_staff(auth.uid()) THEN
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

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.inventory_availability() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.inventory_costs() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.inventory_movements(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_staff(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) TO authenticated, service_role;

-- Public API wrappers run with the caller's rights
CREATE OR REPLACE FUNCTION public.get_inventory_availability()
RETURNS TABLE (
  product_id uuid, sku text, product_name text, category text, barcode text,
  price numeric, reorder_point integer, location_id uuid, location_name text,
  location_type text, quantity_on_hand integer, quantity_reserved integer,
  quantity_available integer
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $$ SELECT * FROM private.inventory_availability() $$;

CREATE OR REPLACE FUNCTION public.get_inventory_costs()
RETURNS TABLE (product_id uuid, cost numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $$ SELECT * FROM private.inventory_costs() $$;

CREATE OR REPLACE FUNCTION public.get_inventory_movements(p_limit integer DEFAULT 500)
RETURNS TABLE (
  id uuid, created_at timestamptz, product_id uuid, sku text, product_name text,
  location_id uuid, location_name text, quantity_change integer,
  movement_type text, reason_code text, reference_id uuid
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $$ SELECT * FROM private.inventory_movements(p_limit) $$;

-- Staff check the app uses to decide what to show (true/false for the caller only)
CREATE OR REPLACE FUNCTION public.current_user_is_staff()
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $$ SELECT private.is_staff(auth.uid()) $$;

REVOKE EXECUTE ON FUNCTION public.current_user_is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_is_staff() TO authenticated, service_role;

-- Remove the earlier public helpers (unused; replaced by private versions)
DROP FUNCTION IF EXISTS public.is_staff(uuid);
DROP FUNCTION IF EXISTS public.has_role(uuid, public.app_role);