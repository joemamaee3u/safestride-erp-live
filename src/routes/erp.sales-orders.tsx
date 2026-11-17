import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { ClipboardList, PackageCheck, Plus, XCircle, CheckCircle2 } from "lucide-react";
import { PageHeader } from "@/components/erp/page-parts";
import { DataRow, DataTable, EmptyRows, ErrorState, LoadingState, money, shortDate } from "@/components/erp/data-state";
import { useActiveLocation } from "@/components/erp/location-context";
import { useErpAction, useErpModule } from "@/lib/erp-api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/erp/sales-orders")({ head: () => ({ meta: pageMeta("Sales Orders — IER ERP", "Reserve stock, manage backorders, and fulfill customer orders.") }), component: SalesOrdersPage });
type Obj = Record<string, any>;
function SalesOrdersPage() {
  const q = useErpModule<{ orders: Obj[]; customers: Obj[]; products: Obj[]; locations: Obj[] }>("sales_orders");
  const { locationId } = useActiveLocation();
  const [product, setProduct] = useState(""); const [qty, setQty] = useState("1"); const [customer, setCustomer] = useState("none"); const [lines,setLines]=useState<{product_id:string;quantity:number}[]>([]);
  const place = useErpAction("erp_place_sales_order"); const fulfill = useErpAction("erp_fulfill_sales_order"); const cancel = useErpAction("erp_cancel_sales_order"); const close = useErpAction("erp_close_sales_order");
  if (q.isPending) return <LoadingState/>; if (q.error) return <ErrorState error={q.error}/>;
  const d=q.data!; const loc=locationId==="all"?d.locations?.[0]?.id:locationId;
  const addLine=()=>{if(!product||Number(qty)<1)return;setLines(old=>{const found=old.find(x=>x.product_id===product);return found?old.map(x=>x.product_id===product?{...x,quantity:x.quantity+Number(qty)}:x):[...old,{product_id:product,quantity:Number(qty)}]});setProduct("");setQty("1");};
  const create=async()=>{if(!lines.length||!loc)return; await place.mutateAsync({p_location_id:loc,p_customer_id:customer==="none"?null:customer,p_channel:"staff",p_lines:lines});setLines([]);};
  return <><PageHeader icon={ClipboardList} title="Sales Orders" description="Reserve available items, surface backorders with estimated dates, and fulfill when stock is ready."/>
    <section className="rounded-xl border bg-card p-4"><h2 className="mb-3 font-semibold">Create a sales order</h2><div className="grid gap-3 md:grid-cols-[2fr_2fr_100px_auto_auto]">
      <Select value={product} onValueChange={setProduct}><SelectTrigger><SelectValue placeholder="Choose item"/></SelectTrigger><SelectContent>{d.products?.map(p=><SelectItem key={p.id} value={p.id}>{p.sku} · {p.name}</SelectItem>)}</SelectContent></Select>
      <Select value={customer} onValueChange={setCustomer}><SelectTrigger><SelectValue placeholder="Customer (optional)"/></SelectTrigger><SelectContent><SelectItem value="none">Walk-in / no profile</SelectItem>{d.customers?.map(c=><SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent></Select>
      <Input aria-label="Quantity" type="number" min="1" value={qty} onChange={e=>setQty(e.target.value)}/><Button variant="outline" onClick={addLine} disabled={!product}><Plus/>Add item</Button><Button variant="lime" onClick={()=>void create()} disabled={!lines.length||place.isPending}><Plus/>Place order</Button></div>{lines.length>0&&<div className="mt-3 space-y-2">{lines.map(line=>{const p=d.products.find(x=>x.id===line.product_id);return <div key={line.product_id} className="flex items-center justify-between rounded-lg bg-muted/40 px-3 py-2 text-sm"><span>{p?.sku} · {p?.name} × {line.quantity}</span><Button size="sm" variant="ghost" onClick={()=>setLines(lines.filter(x=>x.product_id!==line.product_id))}>Remove</Button></div>})}</div>}{place.error&&<p className="mt-2 text-sm text-destructive">{place.error.message}</p>}</section>
    <DataTable columns={["Order","Date","Customer","Location","Status","Total","Backordered","Actions"]} empty={!d.orders?.length}>{d.orders?.map(o=>{const backordered=(o.lines??[]).reduce((sum:number,line:Obj)=>sum+Number(line.quantity_backordered??0),0);return <DataRow key={o.id} values={[<strong>#{o.order_number}</strong>,shortDate(o.placed_at),o.customer_name??"Walk-in",o.location_name,<span className="capitalize">{o.status?.replaceAll("_"," ")}</span>,money(o.total),backordered?`${backordered} units`+(o.lines?.find((line:Obj)=>line.estimated_available_date)?.estimated_available_date?` · ETA ${shortDate(o.lines.find((line:Obj)=>line.estimated_available_date).estimated_available_date)}`:""):"—",o.status==="order_placed"?<div className="flex gap-2"><Button size="sm" variant="lime" onClick={()=>void fulfill.mutateAsync({p_order_id:o.id})}><PackageCheck/>Fulfill</Button><Button size="sm" variant="outline" onClick={()=>void cancel.mutateAsync({p_order_id:o.id})}><XCircle/>Cancel</Button></div>:o.status==="fulfilled"?<Button size="sm" variant="outline" onClick={()=>void close.mutateAsync({p_order_id:o.id})}><CheckCircle2/>Close</Button>:"—"]}/>})}</DataTable>
    {!d.orders?.length&&<EmptyRows>No sales orders yet. New orders reserve sellable stock and mark any shortfall as a backorder.</EmptyRows>}
  </>;
}
