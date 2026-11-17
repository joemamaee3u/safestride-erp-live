import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { ArrowLeftRight, Boxes, ClipboardCheck, PackagePlus, Search, SlidersHorizontal } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { DataRow, DataTable, EmptyRows, ErrorState, LoadingState, shortDate } from "@/components/erp/data-state";
import { PageHeader, SectionCard } from "@/components/erp/page-parts";
import { useActiveLocation } from "@/components/erp/location-context";
import { useErpAction, useErpModule } from "@/lib/erp-api";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/erp/inventory")({
  head: () => ({ meta: pageMeta("Inventory — IER ERP", "Stock, transfers, adjustments, barcode counts, and backorders by location.") }),
  component: InventoryPage,
});

type Obj = Record<string, unknown>;
type InventoryData = { locations: Obj[]; products: Obj[]; costs: Obj[]; movements: Obj[] };
type OrdersData = { orders: Obj[] };

function InventoryPage() {
  const query = useErpModule<InventoryData>("inventory");
  const ordersQuery = useErpModule<OrdersData>("sales_orders");
  const { locationId, locationLabel, locations } = useActiveLocation();
  const [search,setSearch]=useState("");
  const [barcode,setBarcode]=useState("");
  const [adjustQty,setAdjustQty]=useState("");
  const [reason,setReason]=useState("cycle_count");
  const [transferProduct,setTransferProduct]=useState("");
  const [fromLocation,setFromLocation]=useState("");
  const [toLocation,setToLocation]=useState("");
  const [transferQty,setTransferQty]=useState("1");
  const [countProduct,setCountProduct]=useState("");
  const [counted,setCounted]=useState("0");
  const adjust=useErpAction("erp_adjust_stock");
  const transfer=useErpAction<{transfer_id:string}>("erp_transfer_stock");
  const cycle=useErpAction<{count_number:number;absolute_variance_units:number}>("erp_post_cycle_count");
  if(query.isPending)return <LoadingState/>;
  if(query.error)return <ErrorState error={query.error}/>;
  const data=query.data??{locations:[],products:[],costs:[],movements:[]};
  const costById=new Map(data.costs.map((r)=>[String(r["product_id"]),Number(r["cost"])]));
  const products=Array.from(new Map(data.products.map((r)=>[String(r["product_id"]),r])).values());
  const visible=data.products.filter((r)=>{
    if(locationId!=="all"&&String(r["location_id"])!==locationId)return false;
    const q=search.trim().toLowerCase();return !q||[r["sku"],r["product_name"],r["barcode"]].some((v)=>String(v??"").toLowerCase().includes(q));
  });
  const backorders=(ordersQuery.data?.orders??[]).flatMap((order)=>((order["lines"] as Obj[]|undefined)??[])
    .filter((line)=>Number(line["quantity_backordered"]??0)>0)
    .map((line)=>({order,line,customer:String(order["customer_name"]??"Pickup customer")})));
  const submitAdjustment=async()=>{
    const item=products.find((p)=>String(p["barcode"]).toLowerCase()===barcode.trim().toLowerCase()||String(p["sku"]).toLowerCase()===barcode.trim().toLowerCase());
    const target=locationId==="all"?locations[0]?.["id"]:locationId;
    if(!item||!target||!Number(adjustQty))return;
    await adjust.mutateAsync({p_product_id:item["product_id"],p_location_id:target,p_quantity_change:Number(adjustQty),p_reason_code:reason,p_barcode:String(item["barcode"]) });
    setBarcode("");setAdjustQty("");
  };
  const submitTransfer=async()=>{
    if(!transferProduct||!fromLocation||!toLocation||fromLocation===toLocation)return;
    await transfer.mutateAsync({p_product_id:transferProduct,p_from_location:fromLocation,p_to_location:toLocation,p_quantity:Number(transferQty)});
    setTransferQty("1");
  };
  const submitCount=async()=>{
    const item=products.find((p)=>String(p["product_id"])===countProduct);const target=locationId==="all"?locations[0]?.["id"]:locationId;
    if(!item||!target)return;
    await cycle.mutateAsync({p_location_id:target,p_counts:[{product_id:countProduct,counted_quantity:Number(counted)}]});
  };
  return <>
    <PageHeader icon={Boxes} title="Inventory" description={`On-hand, reserved, and available stock · ${locationLabel}`} />
    <div className="grid gap-3 sm:grid-cols-3"><InventoryMetric label="Active items" value={String(products.length)}/><InventoryMetric label="Stock records" value={String(data.products.length)}/><InventoryMetric label="Open backorder lines" value={String(backorders.length)}/></div>
    <Tabs defaultValue="stock">
      <TabsList className="h-auto flex-wrap justify-start"><TabsTrigger value="stock">Stock levels</TabsTrigger><TabsTrigger value="transfers">Transfers</TabsTrigger><TabsTrigger value="adjustments">Adjustments</TabsTrigger><TabsTrigger value="counts">Cycle counts</TabsTrigger><TabsTrigger value="backorders">Backorders</TabsTrigger></TabsList>
      <TabsContent value="stock" className="space-y-4">
        <div className="relative max-w-md"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"/><Input className="pl-9" placeholder="Search SKU, product, or scan barcode" value={search} onChange={(e)=>setSearch(e.target.value)}/></div>
        {visible.length===0?<EmptyRows>No stock records match this view.</EmptyRows>:<DataTable columns={["SKU","Product","Location","On hand","Reserved","Available","Cost","Price","Reorder at","Barcode"]}>
          {visible.map((r,index)=>{const available=Number(r["quantity_available"]??0);const reorder=Number(r["reorder_point"]??0);return <DataRow key={`${r["product_id"]}-${r["location_id"]}-${index}`} values={[String(r["sku"]),String(r["product_name"]),String(r["location_name"]),String(r["quantity_on_hand"]),String(r["quantity_reserved"]),<Badge variant={available<=0?"destructive":available<=reorder?"secondary":"lime"}>{available}</Badge>,money(costById.get(String(r["product_id"]))),money(r["price"]),String(reorder),String(r["barcode"])]}/>})}
        </DataTable>}
        <SectionCard title="Recent inventory movements" description="Every change leaves an auditable reason and reference">
          {data.movements.length===0?<EmptyRows>No stock changes yet.</EmptyRows>:<DataTable columns={["When","SKU","Product","Location","Change","Type","Reason"]}>
            {data.movements.slice(0,12).map((m)=><DataRow key={String(m["id"])} values={[shortDate(m["created_at"]),String(m["sku"]),String(m["product_name"]),String(m["location_name"]),`${Number(m["quantity_change"])>0?"+":""}${m["quantity_change"]}`,String(m["movement_type"]),String(m["reason_code"]??"—")]}/>)}</DataTable>}
        </SectionCard>
      </TabsContent>
      <TabsContent value="transfers"><Card><CardHeader><CardTitle className="flex items-center gap-2"><ArrowLeftRight className="size-5"/>Move stock between locations</CardTitle></CardHeader><CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <FieldSelect label="Product" value={transferProduct} onChange={setTransferProduct} placeholder="Choose item" options={products.map((p)=>({value:String(p["product_id"]),label:`${p["sku"]} · ${p["product_name"]}`}))}/>
        <FieldSelect label="From" value={fromLocation} onChange={setFromLocation} placeholder="Source" options={locations.map((l)=>({value:String(l["id"]),label:String(l["name"])}))}/>
        <FieldSelect label="To" value={toLocation} onChange={setToLocation} placeholder="Destination" options={locations.map((l)=>({value:String(l["id"]),label:String(l["name"])}))}/>
        <div className="space-y-2"><Label>Quantity</Label><Input type="number" min="1" value={transferQty} onChange={(e)=>setTransferQty(e.target.value)}/></div>
        <div className="flex items-end"><Button className="w-full" variant="lime" disabled={transfer.isPending} onClick={()=>void submitTransfer()}><ArrowLeftRight/>Transfer</Button></div>
      </CardContent>{transfer.error&&<p className="px-6 pb-4 text-sm text-destructive">{transfer.error.message}</p>}</Card></TabsContent>
      <TabsContent value="adjustments"><Card><CardHeader><CardTitle className="flex items-center gap-2"><SlidersHorizontal className="size-5"/>Scan and adjust stock</CardTitle></CardHeader><CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="space-y-2"><Label htmlFor="adjust-scan">Barcode or SKU</Label><Input id="adjust-scan" autoFocus placeholder="Scan with USB reader" value={barcode} onChange={(e)=>setBarcode(e.target.value)} onKeyDown={(e)=>{if(e.key==="Enter"){e.preventDefault();document.getElementById("adjust-qty")?.focus();}}}/></div>
        <div className="space-y-2"><Label htmlFor="adjust-qty">Change in units</Label><Input id="adjust-qty" type="number" placeholder="e.g. -2 or 4" value={adjustQty} onChange={(e)=>setAdjustQty(e.target.value)}/></div>
        <FieldSelect label="Reason" value={reason} onChange={setReason} placeholder="Reason" options={[{value:"cycle_count",label:"Cycle count"},{value:"damaged",label:"Damaged"},{value:"shrink",label:"Shrink / loss"},{value:"correction",label:"Correction"},{value:"found_stock",label:"Found stock"}]}/>
        <div className="flex items-end"><Button className="w-full" variant="lime" disabled={adjust.isPending||locationId==="all"} onClick={()=>void submitAdjustment()}><PackagePlus/>Post adjustment</Button></div>
      </CardContent>{locationId==="all"&&<p className="px-6 pb-4 text-sm text-muted-foreground">Select one location in the header before posting an adjustment.</p>}{adjust.error&&<p className="px-6 pb-4 text-sm text-destructive">{adjust.error.message}</p>}</Card></TabsContent>
      <TabsContent value="counts"><Card><CardHeader><CardTitle className="flex items-center gap-2"><ClipboardCheck className="size-5"/>Post a cycle count variance</CardTitle></CardHeader><CardContent className="grid gap-4 sm:grid-cols-3">
        <FieldSelect label="Product" value={countProduct} onChange={setCountProduct} placeholder="Choose counted item" options={products.map((p)=>({value:String(p["product_id"]),label:`${p["sku"]} · ${p["product_name"]}`}))}/>
        <div className="space-y-2"><Label>Counted on shelf</Label><Input type="number" min="0" value={counted} onChange={(e)=>setCounted(e.target.value)}/></div>
        <div className="flex items-end"><Button className="w-full" variant="lime" disabled={cycle.isPending||locationId==="all"} onClick={()=>void submitCount()}><ClipboardCheck/>Post count</Button></div>
      </CardContent>{cycle.data&&<p className="px-6 pb-4 text-sm">Cycle count #{(cycle.data as {count_number:number}).count_number} posted · {(cycle.data as {absolute_variance_units:number}).absolute_variance_units} variance units.</p>}{cycle.error&&<p className="px-6 pb-4 text-sm text-destructive">{cycle.error.message}</p>}</Card></TabsContent>
      <TabsContent value="backorders">{ordersQuery.isPending?<LoadingState label="Loading customer backorders…"/>:ordersQuery.error?<ErrorState error={ordersQuery.error}/>:backorders.length===0?<EmptyRows>No backordered items.</EmptyRows>:<DataTable columns={["Order","Customer","SKU","Item","Backordered","Estimated available"]}>
        {backorders.map(({order,line,customer})=><DataRow key={`${order["id"]}-${line["product_id"]}`} values={[`#${order["order_number"]}`,customer,String(line["sku"]),String(line["product_name"]),String(line["quantity_backordered"]),shortDate(line["estimated_available_date"])]}/>)}</DataTable>}</TabsContent>
    </Tabs>
  </>;
}

function InventoryMetric({label,value}:{label:string;value:string}){return <Card><CardContent className="p-4"><p className="text-xs font-medium uppercase text-muted-foreground">{label}</p><p className="mt-1 font-display text-2xl font-bold">{value}</p></CardContent></Card>}
function FieldSelect({label,value,onChange,placeholder,options}:{label:string;value:string;onChange:(value:string)=>void;placeholder:string;options:{value:string;label:string}[]}){return <div className="space-y-2"><Label>{label}</Label><Select value={value} onValueChange={onChange}><SelectTrigger><SelectValue placeholder={placeholder}/></SelectTrigger><SelectContent>{options.map((option)=><SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent></Select></div>}
function money(value:unknown){return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(value??0));}
