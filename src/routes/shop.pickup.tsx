import { useEffect, useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, CalendarClock, Check, Plus, ShoppingBag, Store, Trash2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { erpRpc, useErpAction, useStorefrontCatalog, useStoreLocations } from "@/lib/erp-api";
import { useStoreCart } from "@/lib/store-cart";
import { money, ErrorState, LoadingState } from "@/components/erp/data-state";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/shop/pickup")({
  head: () => ({ meta: pageMeta("Store Pickup — IER", "Order IER outdoor gear for pickup at a Utah store.") }),
  component: PickupPage,
});

type Obj = Record<string, any>;

function PickupPage() {
  const catalog = useStorefrontCatalog();
  const locationsQuery = useStoreLocations();
  const cart = useStoreCart();
  const [user, setUser] = useState<any>(null);
  const [store, setStore] = useState("");
  const [product, setProduct] = useState("");
  const [qty, setQty] = useState("1");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [requiredBy, setRequiredBy] = useState("");
  const [result, setResult] = useState<any>(null);
  const place = useErpAction<any>("erp_place_pickup_order");

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setUser(data.session?.user ?? null));
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null));
    return () => subscription.unsubscribe();
  }, []);

  const stores = locationsQuery.data ?? [];
  useEffect(() => {
    if (!store && stores[0]) setStore(stores[0].id);
  }, [store, stores]);

  const available = useMemo(
    () => catalog.data?.filter((item) => item.location_id === store) ?? [],
    [catalog.data, store],
  );
  const selected = available.find((item) => item.id === product);
  const lines = useMemo(
    () => cart.lines.flatMap((line) => {
      const item = available.find((candidate) => candidate.id === line.product_id);
      return item ? [{ product: item, quantity: line.quantity }] : [];
    }),
    [available, cart.lines],
  );
  const subtotal = lines.reduce((sum, line) => sum + line.product.price * line.quantity, 0);

  const addProduct = (productId: string, quantity: number) => {
    if (!Number.isInteger(quantity) || quantity < 1) return;
    cart.setLines((current) => {
      const existing = current.find((line) => line.product_id === productId);
      return existing
        ? current.map((line) => line.product_id === productId ? { ...line, quantity: line.quantity + quantity } : line)
        : [...current, { product_id: productId, quantity }];
    });
    setProduct("");
    setQty("1");
  };

  const submit = async () => {
    if (!user || !store || !lines.length) return;
    const customer = await erpRpc<Obj>("erp_get_my_customer").catch(() => ({} as Obj));
    const customerName = name || customer.name || user.user_metadata?.full_name || user.email;
    const order = await place.mutateAsync({
      p_location_id: store,
      p_lines: lines.map((line) => ({ product_id: line.product.id, quantity: line.quantity })),
      p_name: customerName,
      p_phone: phone || customer.phone || null,
      p_required_by: requiredBy || null,
    });
    setResult(order);
    cart.setLines([]);
  };

  if (catalog.isPending || locationsQuery.isPending) return <LoadingState label="Loading store availability…" />;
  if (catalog.error) return <ErrorState error={catalog.error} />;
  if (locationsQuery.error) return <ErrorState error={locationsQuery.error} />;

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 md:px-8">
      <p className="text-sm font-semibold uppercase tracking-[.16em] text-lime-foreground">Convenient local pickup</p>
      <h1 className="mt-2 text-3xl font-bold">Store pickup</h1>
      <p className="mt-1 text-muted-foreground">Choose a Utah store, add gear from your cart, and reserve available items. Any shortfall appears as a backorder with an estimated date.</p>
      {result && <div className="mt-5 rounded-xl border border-lime/50 bg-lime-soft p-4"><strong>Order #{result.order_number} placed.</strong> See its availability and status in <Link className="underline" to="/shop/account">your account</Link>.</div>}

      <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_360px]">
        <div className="space-y-6">
          <section>
            <h2 className="font-display text-lg font-bold">1. Choose a store</h2>
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              {stores.map((location) => (
                <button key={location.id} type="button" onClick={() => { setStore(location.id); setProduct(""); }} className={`rounded-xl border p-4 text-left ${store === location.id ? "border-lime bg-lime-soft" : "bg-card"}`}>
                  <span className="flex items-center gap-2 font-semibold"><Store className="size-4" />{location.name}</span>
                  <span className="mt-1 block text-sm text-muted-foreground">{location.address ?? "Utah"}</span>
                </button>
              ))}
            </div>
          </section>

          <section>
            <h2 className="font-display text-lg font-bold">2. Add more gear</h2>
            <div className="mt-3 grid gap-3 sm:grid-cols-[2fr_1fr_110px_auto]">
              <Select value={product} onValueChange={setProduct}>
                <SelectTrigger><SelectValue placeholder="Choose gear" /></SelectTrigger>
                <SelectContent>{available.map((item) => <SelectItem key={item.id} value={item.id}>{item.name} · {item.quantity_available} available · {money(item.price)}</SelectItem>)}</SelectContent>
              </Select>
              <div className="self-center text-sm text-muted-foreground">{selected ? `${selected.quantity_available} available at this store` : "Live store stock"}</div>
              <Input aria-label="Quantity" type="number" min="1" step="1" value={qty} onChange={(event) => setQty(event.target.value)} />
              <Button variant="lime" onClick={() => selected && addProduct(selected.id, Number(qty))} disabled={!selected || !Number.isInteger(Number(qty)) || Number(qty) < 1}><Plus />Add</Button>
            </div>
          </section>

          <section>
            <h2 className="flex items-center gap-2 font-display text-lg font-bold"><CalendarClock className="size-5" />3. Your details</h2>
            {user ? (
              <div className="mt-3 grid gap-4 sm:grid-cols-2">
                <div className="space-y-2"><Label>Name</Label><Input value={name} onChange={(event) => setName(event.target.value)} placeholder={user.user_metadata?.full_name ?? user.email} /></div>
                <div className="space-y-2"><Label>Mobile phone</Label><Input type="tel" value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="Optional" /></div>
                <div className="space-y-2"><Label>Requested pickup date</Label><Input type="date" min={new Date().toISOString().slice(0, 10)} value={requiredBy} onChange={(event) => setRequiredBy(event.target.value)} /></div>
              </div>
            ) : (
              <div className="mt-3 rounded-xl border bg-card p-4 text-sm">Please <Link className="underline" to="/shop/account">sign in or create an account</Link> before placing your pickup order.</div>
            )}
          </section>
        </div>

        <Card className="h-fit shadow-card lg:sticky lg:top-24">
          <CardContent className="space-y-4 p-6">
            <h2 className="font-display text-lg font-bold">Pickup summary</h2>
            <div className="text-sm">{stores.find((location) => location.id === store)?.name ?? "Choose store"}</div>
            {lines.length ? (
              <div className="divide-y">
                {lines.map((line) => (
                  <div key={line.product.id} className="flex items-center justify-between gap-2 py-2 text-sm">
                    <span>{line.quantity} × {line.product.name}<span className="block text-muted-foreground">{money(line.product.price * line.quantity)}</span></span>
                    <Button size="icon" variant="ghost" aria-label={`Remove ${line.product.name}`} onClick={() => cart.setLines((current) => current.filter((item) => item.product_id !== line.product.id))}><Trash2 className="size-4" /></Button>
                  </div>
                ))}
              </div>
            ) : (
              <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground"><ShoppingBag className="mx-auto mb-2 size-5" />Your cart is empty. <Link to="/shop/cart" className="underline">Return to cart</Link>.</div>
            )}
            <div className="flex justify-between border-t pt-3 font-bold"><span>Estimated subtotal</span><span>{money(subtotal)}</span></div>
            <Button variant="lime" size="xl" className="w-full" disabled={!user || !lines.length || place.isPending} onClick={() => void submit()}><Check />Place pickup order <ArrowRight /></Button>
            {!user && <p className="text-xs text-muted-foreground">Sign in or create an account to reserve your pickup order.</p>}
            {place.error && <p className="text-sm text-destructive">{place.error.message}</p>}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
