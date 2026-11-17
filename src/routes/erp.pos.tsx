import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Banknote, Barcode, CreditCard, Minus, Plus, ScanLine, Search, ShoppingBag, Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ErrorState, LoadingState, money, shortDate } from "@/components/erp/data-state";
import { PageHeader, SectionCard } from "@/components/erp/page-parts";
import { useActiveLocation } from "@/components/erp/location-context";
import { useErpAction, useErpModule } from "@/lib/erp-api";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/erp/pos")({
  head: () => ({ meta: pageMeta("Point of Sale — StrideSafe ERP", "Live in-store register with barcode scan, discounts, taxes, and receipt." ) }),
  component: PosPage,
});

type Obj = Record<string, unknown>;
type PosData = { products: Obj[]; inventory: Obj[]; customers: Obj[]; receipts: Obj[]; bom: Obj[]; tax_rate: number };
type CartLine = { product: Obj; quantity: number };

function PosPage() {
  const query = useErpModule<PosData>("pos");
  const { locationId, locationLabel, locations } = useActiveLocation();
  const [cart, setCart] = useState<Record<string,CartLine>>({});
  const [scan, setScan] = useState("");
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("All");
  const [customerId, setCustomerId] = useState("none");
  const [discount, setDiscount] = useState("0");
  const sale = useErpAction<{ sale_id: string; receipt_number: number; total: number; units: number }>("erp_complete_pos_sale");
  if (query.isPending) return <LoadingState />;
  if (query.error) return <ErrorState error={query.error} />;
  const data = query.data ?? { products:[],inventory:[],customers:[],receipts:[],bom:[],tax_rate:0.0825 };
  const productId = (p:Obj) => String(p["id"] ?? p["product_id"] ?? "");
  const stockFor = (p:Obj) => data.inventory.filter((r)=>String(r["product_id"])===productId(p));
  const available = (p:Obj) => {
    const rows=stockFor(p).filter((r)=>locationId==="all" || String(r["location_id"])===locationId);
    const finished=rows.reduce((sum,r)=>sum+Number(r["quantity_available"]??0),0);
    const bom=data.bom.filter((r)=>String(r["parent_product_id"])===productId(p));
    if(bom.length===0)return finished;
    const assemble=Math.min(...bom.map((component)=>{
      const stocks=data.inventory.filter((r)=>String(r["product_id"])===String(component["component_product_id"])&&(locationId==="all"||String(r["location_id"])===locationId));
      const onHand=stocks.reduce((sum,r)=>sum+Number(r["quantity_available"]??0),0);
      return Math.floor(onHand/Math.max(1,Number(component["quantity_per"]??1)));
    }));
    return finished+assemble;
  };
  const categories=["All",...new Set(data.products.map((p)=>String(p["category"]??"Other")))];
  const visible=data.products.filter((p)=>{
    const q=search.trim().toLowerCase();
    const matches=!q || [p["sku"],p["name"],p["barcode"]].some((x)=>String(x??"").toLowerCase().includes(q));
    return matches && (category==="All" || String(p["category"]??"Other")===category);
  }).slice(0,24);
  const lines=Object.values(cart);
  const subtotal=lines.reduce((sum,line)=>sum+Number(line.product["price"]??0)*line.quantity,0);
  const discountAmount=subtotal*Math.max(0,Math.min(100,Number(discount)||0))/100;
  const tax=(subtotal-discountAmount)*Number(data.tax_rate??0.0825);
  const total=subtotal-discountAmount+tax;
  const add=(product:Obj,delta=1)=>setCart((current)=>{
    const id=productId(product);const next={...current};const qty=(next[id]?.quantity??0)+delta;
    if(qty<=0)delete next[id];else next[id]={product,quantity:qty};return next;
  });
  const scanItem=()=>{
    const code=scan.trim().toLowerCase();if(!code)return;
    const product=data.products.find((p)=>[p["barcode"],p["sku"]].some((value)=>String(value??"").toLowerCase()===code));
    if(product){add(product);setScan("");setSearch("");}else setSearch(scan);
  };
  const complete=async()=>{
    if(locationId==="all" || lines.length===0)return;
    await sale.mutateAsync({p_location_id:locationId,p_lines:lines.map((l)=>({product_id:productId(l.product),quantity:l.quantity})),
      p_discount_percent:Number(discount)||0,p_tax_rate:null,p_customer_id:customerId==="none"?null:customerId,p_sales_order_id:null});
    setCart({});setDiscount("0");setCustomerId("none");
  };
  const lastReceipt=sale.data;
  return <>
    <PageHeader icon={ScanLine} title="Point of Sale" description={locationId==="all"?"Choose a retail location in the header to open its register.":`Register · ${locationLabel}`} />
    {lastReceipt && <div className="rounded-xl border border-lime/50 bg-lime-soft p-4 text-sm"><strong>Sale complete · Receipt #{lastReceipt.receipt_number}</strong> · {lastReceipt.units} units · {money(lastReceipt.total)} · Inventory and ledger updated.</div>}
    <div className="grid gap-5 xl:grid-cols-[1fr_390px]">
      <div className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-[1fr_1.4fr]">
          <div className="relative"><Barcode className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"/><Input className="h-12 pl-9" placeholder="Scan barcode · press Enter" aria-label="Scan product barcode" value={scan} onChange={(e)=>setScan(e.target.value)} onKeyDown={(e)=>{if(e.key==="Enter"){e.preventDefault();scanItem();}}}/></div>
          <div className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"/><Input className="h-12 pl-9" placeholder="Search products or SKU" value={search} onChange={(e)=>setSearch(e.target.value)}/></div>
        </div>
        <div className="flex flex-wrap gap-2">{categories.map((c)=><Button key={c} size="sm" variant={category===c?"default":"outline"} onClick={()=>setCategory(c)}>{c}</Button>)}</div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((p)=><button key={productId(p)} type="button" onClick={()=>add(p)} disabled={available(p)<=0 || locationId==="all"} className="rounded-xl border bg-card p-4 text-left shadow-card transition hover:border-lime hover:shadow-glow disabled:cursor-not-allowed disabled:opacity-50">
            <div className="flex items-start justify-between gap-2"><div><p className="text-xs font-semibold text-muted-foreground">{String(p["sku"])}</p><p className="mt-1 font-semibold">{String(p["name"])}</p></div><Badge variant={available(p)>0?"lime":"muted"}>{available(p)} available</Badge></div>
            <div className="mt-4 flex items-center justify-between"><span className="font-display text-lg font-bold">{money(p["price"])}</span><span className="text-xs text-muted-foreground">{String(p["category"]??"Gear")}</span></div>
          </button>)}
        </div>
      </div>
      <Card className="h-fit shadow-card xl:sticky xl:top-24">
        <CardHeader className="pb-3"><CardTitle className="flex items-center justify-between font-display text-lg"><span>Current sale</span><Badge variant="muted">{lines.reduce((n,l)=>n+l.quantity,0)} units</Badge></CardTitle></CardHeader>
        <CardContent className="space-y-4">
          {lines.length===0?<div className="rounded-xl border border-dashed py-12 text-center text-sm text-muted-foreground"><ShoppingBag className="mx-auto mb-3 size-6"/>Scan or choose a product to begin.</div>:<div className="max-h-72 space-y-3 overflow-y-auto">{lines.map((line)=><div key={productId(line.product)} className="flex items-start gap-3 border-b pb-3"><div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{String(line.product["name"])}</p><p className="text-xs text-muted-foreground">{money(line.product["price"])} each</p><div className="mt-2 flex items-center gap-2"><Button size="icon" variant="outline" className="size-7" onClick={()=>add(line.product,-1)}><Minus className="size-3"/></Button><span className="w-5 text-center text-sm">{line.quantity}</span><Button size="icon" variant="outline" className="size-7" onClick={()=>add(line.product)}><Plus className="size-3"/></Button><Button size="icon" variant="ghost" className="ml-auto size-7" onClick={()=>setCart((current)=>{const next={...current};delete next[productId(line.product)];return next;})}><Trash2 className="size-3.5"/></Button></div></div><span className="text-sm font-semibold">{money(Number(line.product["price"])*line.quantity)}</span></div>)}</div>}
          <div className="space-y-2">
            <Label htmlFor="pos-customer">Customer (optional)</Label>
            <Select value={customerId} onValueChange={setCustomerId}><SelectTrigger id="pos-customer"><SelectValue placeholder="Walk-in customer"/></SelectTrigger><SelectContent><SelectItem value="none">Walk-in customer</SelectItem>{data.customers.map((c)=><SelectItem key={String(c["id"])} value={String(c["id"])}>{String(c["name"])}</SelectItem>)}</SelectContent></Select>
            <Label htmlFor="pos-discount">Discount %</Label><Input id="pos-discount" type="number" min="0" max="100" step="1" value={discount} onChange={(e)=>setDiscount(e.target.value)}/>
          </div>
          <div className="space-y-2 border-t pt-3 text-sm"><Line label="Subtotal" value={money(subtotal)}/><Line label="Discount" value={`−${money(discountAmount)}`}/><Line label={`Tax (${(Number(data.tax_rate??0.0825)*100).toFixed(2)}%)`} value={money(tax)}/><div className="flex justify-between pt-2 font-display text-xl font-bold"><span>Total</span><span>{money(total)}</span></div></div>
          <div className="grid grid-cols-2 gap-2"><Button variant="lime" size="xl" disabled={sale.isPending||lines.length===0||locationId==="all"} onClick={()=>void complete()}><CreditCard/> Complete sale</Button><Button variant="outline" size="xl" disabled={sale.isPending||lines.length===0||locationId==="all"} onClick={()=>void complete()}><Banknote/> Cash</Button></div>
          {sale.error&&<p className="text-sm text-destructive">{sale.error.message}</p>}
        </CardContent>
      </Card>
    </div>
    <SectionCard title="Recent receipts" description="Receipt history is live and tied to inventory and financial reporting">
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">{data.receipts.slice(0,8).map((r)=><div key={String(r["id"])} className="rounded-lg border p-3"><div className="flex justify-between gap-2"><span className="font-semibold">#{r["receipt_number"]}</span><Badge variant="secondary">{String(r["source"])}</Badge></div><p className="mt-2 font-display text-lg font-bold">{money(r["total"])}</p><p className="text-xs text-muted-foreground">{shortDate(r["created_at"])}</p></div>)}</div>
    </SectionCard>
  </>;
}

function Line({label,value}:{label:string;value:string}){return <div className="flex justify-between text-muted-foreground"><span>{label}</span><span className="text-foreground">{value}</span></div>;}
