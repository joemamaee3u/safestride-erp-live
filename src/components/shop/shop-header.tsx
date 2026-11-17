import { Link } from "@tanstack/react-router";
import { MapPin, User, Zap } from "lucide-react";

const NAV = [
  { to: "/shop", label: "Shop" },
  { to: "/shop/pickup", label: "Store pickup" },
  { to: "/shop/account", label: "Account" },
] as const;

export function ShopHeader() {
  return (
    <header className="sticky top-0 z-30 border-b border-sidebar-border bg-navy text-navy-foreground reflect-stripe">
      <div className="mx-auto flex h-16 max-w-7xl items-center gap-6 px-4 md:px-8">
        <Link to="/shop" className="flex items-center gap-2">
          <span className="flex size-8 items-center justify-center rounded-lg bg-lime text-lime-foreground">
            <Zap className="size-4" />
          </span>
          <span className="font-display text-lg font-bold tracking-tight">StrideSafe</span>
        </Link>
        <nav className="hidden flex-1 items-center gap-1 md:flex">
          {NAV.map((n) => (
            <Link
              key={n.to}
              to={n.to}
              activeOptions={{ exact: true }}
              className="rounded-md px-3 py-2 text-sm font-medium text-navy-foreground/75 transition-colors hover:text-navy-foreground data-[status=active]:text-lime"
            >
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-1">
          <Link
            to="/shop/pickup"
            className="flex size-10 items-center justify-center rounded-md hover:bg-navy-soft md:hidden"
            aria-label="Store pickup"
          >
            <MapPin className="size-5" />
          </Link>
          <Link
            to="/shop/account"
            className="flex size-10 items-center justify-center rounded-md hover:bg-navy-soft"
            aria-label="Account"
          >
            <User className="size-5" />
          </Link>
        </div>
      </div>
    </header>
  );
}

export function ShopFooter() {
  return (
    <footer className="border-t bg-muted/50">
      <div className="mx-auto flex max-w-7xl flex-col gap-4 px-4 py-10 text-sm text-muted-foreground md:flex-row md:items-center md:justify-between md:px-8">
        <div>
          <p className="font-display font-bold text-foreground">StrideSafe</p>
          <p>Reflective running gear for men who run after dark.</p>
        </div>
        <div className="flex flex-wrap gap-x-6 gap-y-2">
          <span>Provo Trail Lab</span>
          <span>Salt Lake Showroom</span>
          <Link to="/erp" className="font-medium text-foreground hover:underline">
            Staff ERP →
          </Link>
        </div>
      </div>
    </footer>
  );
}
