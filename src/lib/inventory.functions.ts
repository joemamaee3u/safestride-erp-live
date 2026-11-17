import { createServerFn } from "@tanstack/react-start";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import type { AvailabilityRow } from "@/lib/inventory";

/**
 * Public, read-only stock availability (no costs). Uses the publishable key, so the
 * database's own access rules decide what is returned.
 */
export const getInventoryAvailability = createServerFn({ method: "GET" }).handler(
  async (): Promise<AvailabilityRow[]> => {
    const url = process.env["SUPABASE_URL"];
    const key = process.env["SUPABASE_PUBLISHABLE_KEY"];
    if (!url || !key) {
      throw new Error(
        "The StrideSafe database connection is missing (SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY is not set).",
      );
    }
    const client = createClient<Database>(url, key, {
      auth: { storage: undefined, persistSession: false, autoRefreshToken: false },
      global: {
        fetch: (input, init) => {
          const h = new Headers(init?.headers);
          if (key.startsWith("sb_") && h.get("Authorization") === `Bearer ${key}`) {
            h.delete("Authorization");
          }
          h.set("apikey", key);
          return fetch(input, { ...init, headers: h });
        },
      },
    });

    const { data, error } = await client.rpc("get_inventory_availability");
    if (error) {
      throw new Error(`The database refused the inventory request: ${error.message}`);
    }
    return (data ?? []).map((r) => ({
      product_id: r.product_id,
      sku: r.sku,
      product_name: r.product_name,
      category: r.category,
      barcode: r.barcode,
      price: Number(r.price),
      reorder_point: r.reorder_point,
      location_id: r.location_id,
      location_name: r.location_name,
      location_type: r.location_type,
      quantity_on_hand: r.quantity_on_hand,
      quantity_reserved: r.quantity_reserved,
    }));
  },
);
