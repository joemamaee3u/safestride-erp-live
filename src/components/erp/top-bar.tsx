import { useRouterState } from "@tanstack/react-router";
import { MapPin } from "lucide-react";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Separator } from "@/components/ui/separator";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ALL_LOCATIONS_ID } from "@/lib/locations";
import { ALL_NAV_ITEMS } from "@/lib/erp-nav";
import { useActiveLocation } from "./location-context";
import { ConnectionPill } from "./connection-pill";

export function TopBar() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const current =
    ALL_NAV_ITEMS.filter((i) => (i.to === "/erp" ? pathname.replace(/\/$/, "") === "/erp" : pathname.startsWith(i.to)))[0];
  const { locationId, setLocationId, locations } = useActiveLocation();

  return (
    <header className="sticky top-0 z-20 flex h-16 items-center gap-3 border-b bg-background/95 px-4 backdrop-blur md:px-6">
      <SidebarTrigger className="-ml-1" aria-label="Toggle navigation" />
      <Separator orientation="vertical" className="h-6" />
      <div className="min-w-0 flex-1">
        <p className="truncate font-display text-sm font-semibold text-foreground">
          {current?.title ?? "StrideSafe ERP"}
        </p>
        <p className="hidden truncate text-xs text-muted-foreground sm:block">
          {current?.description}
        </p>
      </div>
      <ConnectionPill className="hidden md:inline-flex" />
      <Select value={locationId} onValueChange={setLocationId}>
        <SelectTrigger className="h-10 w-[200px] font-medium sm:w-[270px]" aria-label="Active location">
          <MapPin className="mr-2 size-4 shrink-0 text-muted-foreground" />
          <span className="flex-1 truncate text-left">
            <SelectValue />
          </span>
        </SelectTrigger>
        <SelectContent align="end">
          <SelectItem value={ALL_LOCATIONS_ID}>All locations</SelectItem>
          <SelectGroup>
            <SelectLabel>Retail stores</SelectLabel>
            {locations.filter((l) => l.location_type === "retail").map((l) => (
              <SelectItem key={l.id} value={l.id}>
                {l.name}
              </SelectItem>
            ))}
          </SelectGroup>
          <SelectGroup>
            <SelectLabel>Distribution</SelectLabel>
            {locations.filter((l) => l.location_type === "warehouse").map((l) => (
              <SelectItem key={l.id} value={l.id}>
                {l.name}
              </SelectItem>
            ))}
          </SelectGroup>
        </SelectContent>
      </Select>
    </header>
  );
}
