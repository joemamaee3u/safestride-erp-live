import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { BadgeCheck, PackageX, RotateCcw, ShieldAlert } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DataRow, DataTable, EmptyRows, ErrorState, LoadingState, money, shortDate } from "@/components/erp/data-state";
import { PageHeader, SectionCard } from "@/components/erp/page-parts";
import { useErpAction, useErpModule } from "@/lib/erp-api";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/erp/returns")({
  head: () => ({ meta: pageMeta("Returns & Exchanges — IER ERP", "Return an item, track quality, restock good gear, and exchange items transactionally.") }),
  component: ReturnsPage,
});

type Obj=Record<string,unknown>;
type ReturnsData={sales:Obj[];returns:Obj[];products:Obj[]};

function ReturnsPage(){
  const query=useErpModule<ReturnsData>("returns");
  const [saleId,setSaleId]=useState("");
  const [productId,setProductId]=useState("");
  const [quantity,setQuantity]=useState("1");
  const [disposition,setDisposition]=useState("quarantine");
  const [reason,setReason]=useState("quality_failure");
  const [exchangeProduct,setExchangeProduct]=useState("none");
  const [exchangeQty,setExchangeQty]=useState("1");
  const action=useErpAction<{return_number:number;refund_amount:number;exchange_amount:number;net_customer_credit:number;kind:string}>("erp_process_return");
  const sales=query.data?.sales??[];
  const selectedSale=sales.find((s)=>String(s["id"])===saleId)??sales[0];
  const saleLines=(selectedSale?.["lines"] as Obj[]|undefined)??[];
  const selectedLine=saleLines.find((l)=>String(l["product_id"])===productId)??saleLines[0];
  const returnable=selectedLine?Math.max(0,Number(selectedLine["quantity"])-Number(selectedLine["returned"]??0)):0;
  const replacement=useMemo(()=>query.data?.products?.find((p)=>String(p["id"]??p["product_id"])===exchangeProduct),[query.data?.products,exchangeProduct]);
  const submit=async()=>{
    if(!selectedSale||!selectedLine||returnable<=0)return;
    await action.mutateAsync({p_sale_id:selectedSale["id"],p_product_id:selectedLine["product_id"],p_quantity:Number(quantity),
      p_disposition:disposition,p_reason_code:reason,p_exchange_product_id:exchangeProduct==="none"?null:exchangeProduct,
      p_exchange_quantity:exchangeProduct==="none"?0:Number(exchangeQty)});
  };
  if(query.isPending)return <LoadingState/>;
  if(query.error)return <ErrorState error={query.error}/>;
  return <>
    <PageHeader icon={RotateCcw} title="Returns & Exchanges" description="Tie every return to its receipt, quality reason, stock disposition, and financial adjustment."/>
    {action.data&&<div className="rounded-xl border border-lime/50 bg-lime-soft p-4 text-sm"><strong>Return #{action.data.return_number} recorded.</strong> Refund {money(action.data.refund_amount)} · exchange {money(action.data.exchange_amount)} · net customer credit {money(action.data.net_customer_credit)}.</div>}
    <div className="grid gap-4 xl:grid-cols-[1.1fr_.9fr]">
      <Card className="shadow-card"><CardHeader><CardTitle className="flex items-center gap-2"><RotateCcw className="size-5"/>Process customer return</CardTitle></CardHeader><CardContent className="space-y-4">
        {sales.length===0?<EmptyRows>Complete a sale first; receipts will appear here.</EmptyRows>:<>
          <Field label="Original receipt"><Select value={saleId||String(selectedSale?.["id"]??"")} onValueChange={(v)=>{setSaleId(v);setProductId("");}}><SelectTrigger><SelectValue placeholder="Choose receipt"/></SelectTrigger><SelectContent>{sales.map((s)=><SelectItem key={String(s["id"])} value={String(s["id"])}>#{s["receipt_number"]} · {money(s["total"])} · {shortDate(s["created_at"])}</SelectItem>)}</SelectContent></Select></Field>
          <Field label="Item being returned"><Select value={productId||String(selectedLine?.["product_id"]??"")} onValueChange={setProductId}><SelectTrigger><SelectValue placeholder="Choose item"/></SelectTrigger><SelectContent>{saleLines.map((line)=><SelectItem key={String(line["product_id"])} value={String(line["product_id"])}>{line["sku"]} · {line["name"]} · sold {line["quantity"]}, returned {line["returned"]??0}</SelectItem>)}</SelectContent></Select></Field>
          <div className="grid gap-4 sm:grid-cols-2"><Field label={`Quantity · up to ${returnable}`}><Input type="number" min="1" max={returnable} value={quantity} onChange={(e)=>setQuantity(e.target.value)}/></Field><Field label="Return reason"><Select value={reason} onValueChange={setReason}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent><SelectItem value="quality_failure">Quality failure</SelectItem><SelectItem value="damaged">Damaged in use</SelectItem><SelectItem value="wrong_size">Wrong size</SelectItem><SelectItem value="changed_mind">Changed mind</SelectItem><SelectItem value="other">Other</SelectItem></SelectContent></Select></Field></div>
          <Field label="Returned item condition"><Select value={disposition} onValueChange={setDisposition}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent><SelectItem value="restock">Good · restock it</SelectItem><SelectItem value="quarantine">Failed quality · quarantine</SelectItem></SelectContent></Select></Field>
          <div className="rounded-xl border bg-muted/30 p-4"><p className="mb-3 flex items-center gap-2 text-sm font-semibold"><PackageX className="size-4"/>Optional exchange item</p><div className="grid gap-3 sm:grid-cols-[1fr_120px]"><Field label="Replacement"><Select value={exchangeProduct} onValueChange={setExchangeProduct}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent><SelectItem value="none">Refund only</SelectItem>{query.data?.products?.map((p)=><SelectItem key={String(p["id"]??p["product_id"])} value={String(p["id"]??p["product_id"])}>{p["sku"]} · {p["name"]}</SelectItem>)}</SelectContent></Select></Field><Field label="Qty"><Input type="number" min="1" value={exchangeQty} onChange={(e)=>setExchangeQty(e.target.value)} disabled={exchangeProduct==="none"}/></Field></div>{replacement&&<p className="mt-2 text-xs text-muted-foreground">Replacement price {money(replacement["price"])}; inventory will be checked at the original sale location.</p>}</div>
          <Button variant="lime" size="xl" className="w-full" disabled={action.isPending||returnable<=0} onClick={()=>void submit()}><BadgeCheck/>Post return / exchange</Button>
          {action.error&&<p className="text-sm text-destructive">{action.error.message}</p>}
        </>}
      </CardContent></Card>
      <SectionCard title="Recent return history" description="Quality failure, disposition, and refund stay linked to the sale">
        {(query.data?.returns??[]).length===0?<EmptyRows>No returns yet.</EmptyRows>:<div className="space-y-3">{query.data?.returns?.slice(0,10).map((r)=><div key={String(r["id"])} className="rounded-xl border p-4"><div className="flex items-center justify-between gap-2"><div className="flex items-center gap-2"><Badge variant={r["kind"]==="exchange"?"lime":"secondary"}>{String(r["kind"]).toUpperCase()}</Badge><span className="font-semibold">#{r["return_number"]}</span></div><span className="text-xs text-muted-foreground">{shortDate(r["created_at"])}</span></div><p className="mt-2 text-sm">{String(r["reason_code"])} · Refund {money(r["refund_amount"])}</p><div className="mt-2 flex flex-wrap gap-2">{((r["lines"] as Obj[]|undefined)??[]).map((line,index)=><Badge key={index} variant="outline">{line["sku"]} × {line["quantity"]} · {line["disposition"]}</Badge>)}</div></div>)}</div>}
      </SectionCard>
    </div>
    <div className="flex items-start gap-3 rounded-xl border bg-muted/30 p-4 text-sm text-muted-foreground"><ShieldAlert className="mt-0.5 size-4 shrink-0"/>Quality failures are quarantined out of sellable inventory. Refunds and exchanges update inventory, revenue, tax, and cost of goods sold in the same database transaction.</div>
  </>;
}

function Field({label,children}:{label:string;children:React.ReactNode}){return <div className="space-y-2"><Label>{label}</Label>{children}</div>}
