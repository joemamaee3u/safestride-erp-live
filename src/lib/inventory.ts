/** Pure inventory helpers: shaping database rows, stock status rules, and USD formatting. */

export interface AvailabilityRow {
  product_id: string;
  sku: string;
  product_name: string;
  category: string | null;
  barcode: string;
  price: number;
  reorder_point: number;
  location_id: string;
  location_name: string;
  location_type: string;
  quantity_on_hand: number;
  quantity_reserved: number;
}

export type StockStatus = "ok" | "low" | "out";

export interface LocationStock {
  onHand: number;
  reserved: number;
  available: number;
  status: StockStatus;
}

export interface InventoryLocation {
  id: string;
  name: string;
  type: "retail" | "warehouse";
}

export interface InventoryProduct {
  id: string;
  sku: string;
  name: string;
  category: string;
  barcode: string;
  price: number;
  reorderPoint: number;
  stock: Record<string, LocationStock>;
}

export const UNCATEGORIZED = "Uncategorized";

/** Available = on hand − reserved. */
export function availableQuantity(onHand: number, reserved: number): number {
  return onHand - reserved;
}

/** Out when nothing is available; low when available is at or below the reorder point. */
export function stockStatus(available: number, reorderPoint: number): StockStatus {
  if (available <= 0) return "out";
  if (available <= reorderPoint) return "low";
  return "ok";
}

const STATUS_RANK: Record<StockStatus, number> = { ok: 0, low: 1, out: 2 };

/** Worst status across the given locations (out > low > ok). */
export function productStatus(product: InventoryProduct, locationIds: string[]): StockStatus {
  let worst: StockStatus = "ok";
  for (const id of locationIds) {
    const s = product.stock[id]?.status ?? stockStatus(0, product.reorderPoint);
    if (STATUS_RANK[s] > STATUS_RANK[worst]) worst = s;
  }
  return worst;
}

export function totals(product: InventoryProduct, locationIds: string[]) {
  return locationIds.reduce(
    (acc, id) => {
      const s = product.stock[id];
      if (s) {
        acc.onHand += s.onHand;
        acc.reserved += s.reserved;
        acc.available += s.available;
      }
      return acc;
    },
    { onHand: 0, reserved: 0, available: 0 },
  );
}

export function buildInventory(rows: AvailabilityRow[]) {
  const products = new Map<string, InventoryProduct>();
  const locations = new Map<string, InventoryLocation>();

  for (const r of rows) {
    if (!locations.has(r.location_id)) {
      locations.set(r.location_id, {
        id: r.location_id,
        name: r.location_name,
        type: r.location_type.toLowerCase() === "warehouse" ? "warehouse" : "retail",
      });
    }
    let p = products.get(r.product_id);
    if (!p) {
      p = {
        id: r.product_id,
        sku: r.sku,
        name: r.product_name,
        category: r.category?.trim() || UNCATEGORIZED,
        barcode: r.barcode,
        price: Number(r.price),
        reorderPoint: r.reorder_point,
        stock: {},
      };
      products.set(r.product_id, p);
    }
    const available = availableQuantity(r.quantity_on_hand, r.quantity_reserved);
    p.stock[r.location_id] = {
      onHand: r.quantity_on_hand,
      reserved: r.quantity_reserved,
      available,
      status: stockStatus(available, p.reorderPoint),
    };
  }

  const sortedLocations = [...locations.values()].sort(
    (a, b) =>
      (a.type === "retail" ? 0 : 1) - (b.type === "retail" ? 0 : 1) || a.name.localeCompare(b.name),
  );
  const sortedProducts = [...products.values()].sort((a, b) => a.sku.localeCompare(b.sku));
  const categories = [...new Set(sortedProducts.map((p) => p.category))].sort();

  return { products: sortedProducts, locations: sortedLocations, categories };
}

export interface InventoryFilters {
  q: string;
  category: string;
  locationIds: string[];
  lowOnly: boolean;
}

export function filterProducts(products: InventoryProduct[], f: InventoryFilters) {
  const q = f.q.trim().toLowerCase();
  return products.filter((p) => {
    if (f.category !== "all" && p.category !== f.category) return false;
    if (f.lowOnly && productStatus(p, f.locationIds) === "ok") return false;
    if (!q) return true;
    return (
      p.sku.toLowerCase().includes(q) ||
      p.name.toLowerCase().includes(q) ||
      p.barcode.toLowerCase().includes(q)
    );
  });
}

const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });

/** Formats an amount in US dollars. */
export function formatUSD(amount: number): string {
  return usd.format(amount);
}
