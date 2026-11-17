import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { ALL_LOCATIONS_ID } from "@/lib/locations";
import { useErpModule, type ErpLocation } from "@/lib/erp-api";

interface LocationContextValue {
  locationId: string;
  setLocationId: (id: string) => void;
  locationLabel: string;
  locations: ErpLocation[];
}

const LocationContext = createContext<LocationContextValue | null>(null);

export function LocationProvider({ children }: { children: ReactNode }) {
  const { data } = useErpModule<{ locations: ErpLocation[] }>("inventory");
  const locations = useMemo(() => data?.locations ?? [], [data?.locations]);
  const [locationId, setLocationIdState] = useState<string>(ALL_LOCATIONS_ID);
  useEffect(() => {
    const saved = window.localStorage.getItem("stridesafe-active-location");
    if (saved && (saved === ALL_LOCATIONS_ID || locations.some((loc) => loc.id === saved))) setLocationIdState(saved);
  }, [locations]);
  const setLocationId = (id: string) => {
    setLocationIdState(id);
    window.localStorage.setItem("stridesafe-active-location", id);
  };
  const locationLabel =
    locations.find((l) => l.id === locationId)?.name ?? "All locations";
  return (
    <LocationContext.Provider value={{ locationId, setLocationId, locationLabel, locations }}>
      {children}
    </LocationContext.Provider>
  );
}

export function useActiveLocation() {
  const ctx = useContext(LocationContext);
  if (!ctx) throw new Error("useActiveLocation must be used inside LocationProvider");
  return ctx;
}
