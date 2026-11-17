import { useEffect } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";

type RpcResponse<T> = { data: T | null; error: { message: string } | null };
type RpcClient = {
  rpc<T = unknown>(name: string, args?: Record<string, unknown>): Promise<RpcResponse<T>>;
};

const rpcClient = supabase as unknown as RpcClient;

export async function erpRpc<T = unknown>(name: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await rpcClient.rpc<T>(name, args);
  if (error) throw new Error(error.message);
  if (data === null) return null as T;
  return data;
}

export function useErpModule<T = Record<string, unknown>>(module: string, enabled = true) {
  return useQuery<T>({
    queryKey: ["erp", module],
    queryFn: () => erpRpc<T>("erp_get_module_data", { p_module: module }),
    enabled,
    staleTime: 15_000,
  });
}

export function useErpAction<T = unknown>(functionName: string) {
  const queryClient = useQueryClient();
  return useMutation<T, Error, Record<string, unknown>>({
    mutationFn: (args) => erpRpc<T>(functionName, args),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["erp"] });
      await queryClient.invalidateQueries({ queryKey: ["storefront"] });
      toast.success("Saved to SafeStride ERP");
    },
    onError: (error) => toast.error(error.message),
  });
}

export function useErpRealtime() {
  const queryClient = useQueryClient();
  useEffect(() => {
    const refresh = () => {
      void queryClient.invalidateQueries({ queryKey: ["erp"] });
      void queryClient.invalidateQueries({ queryKey: ["storefront"] });
    };
    const channel = supabase
      .channel("stridesafe-erp-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "inventory_balances" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "inventory_movements" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "pos_sales" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_sales_orders" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_sales_order_lines" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_purchase_orders" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_purchase_order_lines" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_production_orders" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_returns" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_return_lines" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_cycle_counts" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_suppliers" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_supplier_products" }, refresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "erp_system_settings" }, refresh)
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [queryClient]);
}

export interface ErpLocation {
  id: string;
  name: string;
  location_type: string;
  address?: string | null;
}

export interface ErpProduct {
  id: string;
  product_id?: string;
  sku: string;
  name?: string;
  product_name?: string;
  category?: string | null;
  barcode: string;
  price: number;
  cost?: number;
  reorder_point?: number;
  location_id?: string;
  location_name?: string;
  quantity_on_hand?: number;
  quantity_reserved?: number;
  quantity_available?: number;
}

export function useStorefrontCatalog() {
  return useQuery<ErpProduct[]>({
    queryKey: ["storefront", "catalog"],
    queryFn: async () => {
      const rows = await erpRpc<Array<Record<string, unknown>>>("erp_get_public_catalog");
      return rows.map((row) => ({
        ...row,
        id: String(row.product_id),
        product_id: String(row.product_id),
        name: String(row.product_name ?? ""),
        location_id: String(row.location_id),
        location_name: String(row.location_name ?? ""),
        quantity_available: Number(row.quantity_available ?? 0),
        price: Number(row.price ?? 0),
      })) as ErpProduct[];
    },
    staleTime: 10_000,
    refetchInterval: 15_000,
  });
}

export function useStoreLocations() {
  return useQuery<ErpLocation[]>({
    queryKey: ["storefront", "locations"],
    queryFn: async () => erpRpc<ErpLocation[]>("erp_list_store_locations"),
    staleTime: 60_000,
  });
}
