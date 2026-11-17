import { createFileRoute, Link } from "@tanstack/react-router";
import { Activity, AlertTriangle, ArrowRight, Barcode, ClipboardList, DollarSign, Factory, LayoutDashboard, PackageCheck, ScanLine, ShoppingCart, Truck } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyRows, ErrorState, LoadingState, money, shortDate, DataTable, DataRow } from "@/components/erp/data-state";
import { PageHeader, SectionCard } from "@/components/erp/page-parts";
import { useErpModule } from "@/lib/erp-api";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/erp/")({
  head: () => ({ meta: pageMeta("Dashboard — StrideSafe ERP", "Live overview of SafeStride sales, stock, and production.") }),
  component: Dashboard,
});

const QUICK_ACTIONS = [
  { title: "Open register", to: "/erp/pos", icon: ScanLine },
  { title: "Sales orders", to: "/erp/sales-orders", icon: ShoppingCart },
  { title: "Scan barcodes", to: "/erp/barcodes", icon: Barcode },
  { title: "Purchase orders", to: "/erp/purchasing", icon: Truck },
  { title: "Production", to: "/erp/production", icon: Factory },
  { title: "Inventory", to: "/erp/inventory", icon: PackageCheck },
] as const;

type Obj = Record<string, unknown>;
type DashboardData = { dashboard?: Obj; manager?: Obj };

function arr(value: unknown): Obj[] { return Array.isArray(value) ? value as Obj[] : []; }

function Dashboard() {
  const query = useErpModule<DashboardData>("reports");
  if (query.isPending) return <LoadingState />;
  if (query.error) return <ErrorState error={query.error} />;
  const dashboard = query.data?.dashboard ?? {};
  const manager = query.data?.manager ?? {};
  const salesByDay = arr(manager["sales_by_day"]);
  const recentSales = arr(dashboard["recent_sales"]);
  const lowStock = arr(manager["low_stock"]).slice(0, 6);
  const topItems = arr(manager["top_items"]).slice(0, 5);
  const ready = Number(dashboard["night_run_readiness_percent"] ?? 0);
  return (
    <>
      <PageHeader icon={LayoutDashboard} title="Dashboard" description="SafeStride Reflective Running Gear · live operations" />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Metric label="Today's sales" value={money(dashboard["today_sales"])} hint="POS and pickup receipts" icon={<DollarSign />} />
        <Metric label="Open orders" value={String(dashboard["open_orders"] ?? 0)} hint="Confirmed orders awaiting fulfillment" icon={<ClipboardList />} />
        <Metric label="Low stock" value={String(dashboard["low_stock_items"] ?? 0)} hint="Items at or below reorder coverage" icon={<AlertTriangle />} />
        <Metric label="In production" value={String(dashboard["active_production_orders"] ?? 0)} hint="Planned and issued work orders" icon={<Factory />} />
      </div>
      <div className="grid gap-4 lg:grid-cols-[1.2fr_1fr]">
        <Card className="overflow-hidden bg-navy text-navy-foreground shadow-card">
          <CardContent className="flex flex-col gap-6 p-6 sm:flex-row sm:items-center sm:justify-between">
            <div className="max-w-lg">
              <Badge className="border-lime/40 bg-lime/15 text-lime">AFTER-DARK READINESS</Badge>
              <h2 className="mt-3 font-display text-2xl font-bold">Night Run Ready</h2>
              <p className="mt-2 text-sm text-navy-foreground/75">Share of reflective kit styles with sellable stock at a retail location.</p>
              <p className="mt-4 text-sm">{dashboard["ready_kits"] ?? 0} of {dashboard["total_kits"] ?? 0} kit styles available now</p>
            </div>
            <div className="flex size-36 shrink-0 items-center justify-center rounded-full" style={{ background: `conic-gradient(#d5ff3f ${ready}%, rgba(255,255,255,.14) 0)` }}>
              <div className="flex size-28 flex-col items-center justify-center rounded-full bg-navy text-center">
                <span className="font-display text-3xl font-black">{ready}%</span><span className="text-xs text-navy-foreground/65">ready</span>
              </div>
            </div>
          </CardContent>
        </Card>
        <SectionCard title="Quick actions" description="Jump to the work managers do most">
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {QUICK_ACTIONS.map((action) => <Link key={action.to} to={action.to} className="group rounded-xl border bg-background p-3 transition hover:-translate-y-0.5 hover:border-lime hover:shadow-glow">
              <action.icon className="size-5 text-lime-foreground" /><span className="mt-3 flex items-center justify-between text-xs font-semibold">{action.title}<ArrowRight className="size-3 text-muted-foreground transition group-hover:translate-x-0.5" /></span>
            </Link>)}
          </div>
        </SectionCard>
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <SectionCard title="Recent sales" description="Live receipts across all locations">
          {recentSales.length === 0 ? <EmptyRows>No sales are recorded yet.</EmptyRows> : <DataTable columns={["Receipt","Channel","Amount","Time"]}>
            {recentSales.slice(0, 7).map((sale) => <DataRow key={String(sale["id"])} values={[`#${sale["receipt_number"]}`,String(sale["source"] ?? "POS"),money(sale["total"]),shortDate(sale["created_at"])]} />)}
          </DataTable>}
        </SectionCard>
        <SectionCard title="Replenishment watch" description="Demand and supplier lead time drive these suggestions">
          {lowStock.length === 0 ? <EmptyRows>Nothing is below its reorder target.</EmptyRows> : <DataTable columns={["Item","Available","Order","Order by"]}>
            {lowStock.map((item) => <DataRow key={String(item["product_id"])} values={[<span className="font-medium">{String(item["sku"])} · {String(item["product_name"])}</span>,String(Number(item["on_hand"])-Number(item["reserved"])),String(item["suggested_order_quantity"]),shortDate(item["order_by"])]} />)}
          </DataTable>}
        </SectionCard>
      </div>
      <div className="grid gap-4 lg:grid-cols-[1.2fr_1fr]">
        <SectionCard title="Sales pulse" description="Daily revenue from live and seeded six-month history">
          {salesByDay.length === 0 ? <EmptyRows>No sales in this window.</EmptyRows> : <div className="flex h-44 items-end gap-1 rounded-xl border bg-muted/20 p-3">
            {salesByDay.slice(-21).map((day,index) => { const max=Math.max(...salesByDay.map((x)=>Number(x["sales"]??0)),1); const height=Math.max(5,Number(day["sales"]??0)/max*100); return <div key={String(day["day"])} className="group relative flex-1 rounded-t bg-lime/80 hover:bg-lime" style={{height:`${height}%`}} title={`${shortDate(day["day"])} · ${money(day["sales"])}`}><span className="absolute -top-7 left-1/2 hidden -translate-x-1/2 whitespace-nowrap rounded bg-navy px-2 py-1 text-[10px] text-white group-hover:block">{money(day["sales"])}</span></div>; })}
          </div>}
        </SectionCard>
        <SectionCard title="Top sellers" description="Best-selling items in the last 30 days">
          {topItems.length === 0 ? <EmptyRows>No sales in this window.</EmptyRows> : <div className="space-y-3">{topItems.map((item,index)=><div key={String(item["sku"])} className="flex items-center gap-3"><span className="flex size-8 items-center justify-center rounded-lg bg-muted text-xs font-bold">{index+1}</span><div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{String(item["product_name"])}</p><p className="text-xs text-muted-foreground">{item["units"]} units</p></div><span className="text-sm font-semibold">{money(item["revenue"])}</span></div>)}</div>}
        </SectionCard>
      </div>
    </>
  );
}

function Metric({label,value,hint,icon}:{label:string;value:string;hint:string;icon:React.ReactNode}) {
  return <Card className="shadow-card"><CardContent className="flex items-start justify-between gap-3 p-5"><div><p className="text-sm font-medium text-muted-foreground">{label}</p><p className="mt-2 font-display text-3xl font-bold">{value}</p><p className="mt-1 text-xs text-muted-foreground">{hint}</p></div><div className="flex size-10 items-center justify-center rounded-lg bg-lime-soft text-lime-foreground">{icon}</div></CardContent></Card>;
}
