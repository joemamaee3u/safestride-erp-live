export type LocationType = "retail" | "warehouse";

export interface CompanyLocation {
  id: string;
  name: string;
  shortName: string;
  type: LocationType;
}

/**
 * StrideSafe operates exactly these three locations (matches the `locations` table).
 * Pages wired to the database read locations from there; this list feeds pickers
 * on pages that are not connected yet.
 */
export const LOCATIONS: CompanyLocation[] = [
  { id: "provo-trail-lab", name: "Provo Trail Lab", shortName: "Provo", type: "retail" },
  { id: "salt-lake-showroom", name: "Salt Lake Showroom", shortName: "Salt Lake", type: "retail" },
  {
    id: "utah-fulfillment-hub",
    name: "Utah Fulfillment Hub",
    shortName: "Fulfillment",
    type: "warehouse",
  },
];

export const RETAIL_LOCATIONS = LOCATIONS.filter((l) => l.type === "retail");

export const ALL_LOCATIONS_ID = "all";
