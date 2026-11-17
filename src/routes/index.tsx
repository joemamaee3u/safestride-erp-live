import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, LayoutDashboard, Store, Warehouse, Zap } from "lucide-react";
import { ConnectionPill } from "@/components/erp/connection-pill";
import { LOCATIONS } from "@/lib/locations";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: pageMeta(
      "StrideSafe — ERP & Online Store",
      "Choose the StrideSafe staff ERP or the customer-facing online storefront.",
    ),
  }),
  component: Launcher,
});

const WORKSPACES = [
  {
    to: "/erp",
    icon: LayoutDashboard,
    title: "StrideSafe ERP",
    body: "Point of sale, orders, inventory, production, purchasing, and financials for staff.",
    cta: "Open ERP",
  },
  {
    to: "/shop",
    icon: Store,
    title: "Online storefront",
    body: "The customer site: product catalog, cart, accounts, and store pickup ordering.",
    cta: "Open storefront",
  },
] as const;

function Launcher() {
  return (
    <div className="relative flex min-h-screen flex-col bg-night text-navy-foreground">
      <header className="mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-6">
        <div className="flex items-center gap-2">
          <span className="flex size-9 items-center justify-center rounded-lg bg-lime text-lime-foreground">
            <Zap className="size-5" />
          </span>
          <span className="font-display text-xl font-bold">StrideSafe</span>
        </div>
        <ConnectionPill />
      </header>

      <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col justify-center px-6 pb-16">
        <p className="text-sm font-semibold uppercase tracking-[0.2em] text-lime">
          Men's reflective running gear
        </p>
        <h1 className="mt-3 max-w-2xl text-4xl font-black leading-tight md:text-6xl">
          Where do you want to start?
        </h1>

        <div className="mt-10 grid gap-5 md:grid-cols-2">
          {WORKSPACES.map((w) => (
            <Link
              key={w.to}
              to={w.to}
              className="group flex flex-col gap-6 rounded-2xl border border-navy-foreground/15 bg-navy-foreground/5 p-8 transition-all hover:-translate-y-1 hover:border-lime hover:shadow-glow"
            >
              <span className="flex size-14 items-center justify-center rounded-xl bg-lime text-lime-foreground">
                <w.icon className="size-7" />
              </span>
              <div>
                <h2 className="text-2xl font-bold">{w.title}</h2>
                <p className="mt-2 text-navy-foreground/70">{w.body}</p>
              </div>
              <span className="mt-auto inline-flex items-center gap-2 font-semibold text-lime">
                {w.cta}
                <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" />
              </span>
            </Link>
          ))}
        </div>

        <div className="mt-12 flex flex-wrap gap-3">
          {LOCATIONS.map((l) => {
            const Icon = l.type === "retail" ? Store : Warehouse;
            return (
              <span
                key={l.id}
                className="inline-flex items-center gap-2 rounded-full border border-navy-foreground/15 px-4 py-2 text-sm text-navy-foreground/80"
              >
                <Icon className="size-4 text-lime" /> {l.name}
              </span>
            );
          })}
        </div>
      </main>
    </div>
  );
}
