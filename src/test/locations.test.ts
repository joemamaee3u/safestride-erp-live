import { describe, expect, it } from "vitest";
import { LOCATIONS, RETAIL_LOCATIONS } from "@/lib/locations";

describe("company locations", () => {
  it("has exactly the three StrideSafe locations", () => {
    expect(LOCATIONS.map((l) => l.name)).toEqual([
      "Mexico City Retail Store",
      "Guadalajara Retail Store",
      "Monterrey Distribution Warehouse",
    ]);
  });

  it("offers store pickup only at the two retail stores", () => {
    expect(RETAIL_LOCATIONS.map((l) => l.id)).toEqual(["mexico-city", "guadalajara"]);
  });
});
