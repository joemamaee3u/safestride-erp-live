import { describe, expect, it } from "vitest";
import {
  availableQuantity,
  buildInventory,
  filterProducts,
  formatMXN,
  stockStatus,
  type AvailabilityRow,
} from "@/lib/inventory";

const row = (over: Partial<AvailabilityRow>): AvailabilityRow => ({
  product_id: "p1",
  sku: "RUN001",
  product_name: "Reflective Running Jacket",
  category: "Apparel",
  barcode: "2000000000015",
  price: 1299,
  reorder_point: 15,
  location_id: "l1",
  location_name: "Mexico City Retail Store",
  location_type: "Retail",
  quantity_on_hand: 40,
  quantity_reserved: 0,
  ...over,
});

describe("inventory rules", () => {
  it("available is on hand minus reserved", () => {
    expect(availableQuantity(40, 5)).toBe(35);
  });

  it("flags low stock at or below the reorder point", () => {
    expect(stockStatus(15, 15)).toBe("low");
    expect(stockStatus(16, 15)).toBe("ok");
  });

  it("flags out of stock when nothing is available", () => {
    expect(stockStatus(0, 15)).toBe("out");
    expect(stockStatus(-3, 15)).toBe("out");
  });

  it("uses reserved quantities when computing a location's status", () => {
    const { products } = buildInventory([row({ quantity_on_hand: 20, quantity_reserved: 6 })]);
    expect(products[0]!.stock["l1"]).toMatchObject({ available: 14, status: "low" });
  });

  it("low-stock filter keeps only products low at a shown location", () => {
    const { products } = buildInventory([
      row({}),
      row({ location_id: "l2", location_name: "Guadalajara Retail Store", quantity_on_hand: 10 }),
    ]);
    const base = { q: "", category: "all", lowOnly: true };
    expect(filterProducts(products, { ...base, locationIds: ["l1"] })).toHaveLength(0);
    expect(filterProducts(products, { ...base, locationIds: ["l1", "l2"] })).toHaveLength(1);
  });

  it("formats money in Mexican pesos", () => {
    expect(formatMXN(1299)).toBe("MX$1,299.00");
  });
});
