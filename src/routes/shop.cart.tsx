import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, Minus, Plus, ShoppingBag, Trash2 } from "lucide-react";
import { ErrorState, LoadingState, money } from "@/components/erp/data-state";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { useStorefrontCatalog } from "@/lib/erp-api";
import { pageMeta } from "@/lib/seo";
import { useStoreCart } from "@/lib/store-cart";

export const Route = createFileRoute("/shop/cart")({
  head: () => ({ meta: pageMeta("Your Cart — IER", "Review your IER outdoor gear before pickup.") }),
  component: CartPage,
});

function CartPage() {
  const catalog = useStorefrontCatalog();
  const { lines, setLines } = useStoreCart();
  const products = catalog.data ?? [];
  const cartLines = lines.flatMap((line) => {
    const product = products.find((item) => item.id === line.product_id);
    return product ? [{ product, quantity: line.quantity }] : [];
  });
  const subtotal = cartLines.reduce((sum, line) => sum + line.product.price * line.quantity, 0);

  const changeQuantity = (productId: string, change: number) => {
    setLines((current) =>
      current
        .map((line) =>
          line.product_id === productId
            ? { ...line, quantity: line.quantity + change }
            : line,
        )
        .filter((line) => line.quantity > 0),
    );
  };

  const remove = (productId: string) => {
    setLines((current) => current.filter((line) => line.product_id !== productId));
  };

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 md:px-8">
      <p className="text-sm font-semibold uppercase tracking-[.16em] text-lime-foreground">Your selection</p>
      <h1 className="mt-2 text-3xl font-bold">Shopping cart</h1>
      {catalog.isPending ? (
        <div className="mt-8"><LoadingState label="Loading your cart…" /></div>
      ) : catalog.error ? (
        <div className="mt-8"><ErrorState error={catalog.error} /></div>
      ) : cartLines.length === 0 ? (
        <div className="mt-8 rounded-2xl border border-dashed p-10 text-center">
          <ShoppingBag className="mx-auto mb-3 size-8 text-muted-foreground" />
          <h2 className="font-semibold">Your cart is empty</h2>
          <p className="mt-1 text-sm text-muted-foreground">Browse the IER collection and add gear to your cart.</p>
          <Button className="mt-5" variant="lime" asChild><Link to="/shop">Explore outdoor gear</Link></Button>
        </div>
      ) : (
        <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_360px]">
          <section className="space-y-3" aria-label="Cart items">
            {cartLines.map(({ product, quantity }) => {
              const stock = products
                .filter((item) => item.id === product.id)
                .reduce((sum, item) => sum + Number(item.quantity_available), 0);
              return (
                <article key={product.id} className="flex flex-wrap items-center gap-4 rounded-2xl border bg-card p-4">
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{product.category}</p>
                    <h2 className="mt-1 font-semibold">{product.name}</h2>
                    <p className="mt-1 text-sm text-muted-foreground">{stock} available across our Utah stores</p>
                  </div>
                  <span className="font-semibold">{money(product.price)}</span>
                  <div className="flex items-center gap-2" aria-label={`Quantity: ${quantity}`}>
                    <Button size="icon" variant="outline" aria-label={`Remove one ${product.name}`} onClick={() => changeQuantity(product.id, -1)}><Minus /></Button>
                    <span className="w-7 text-center font-semibold">{quantity}</span>
                    <Button size="icon" variant="outline" aria-label={`Add one ${product.name}`} onClick={() => changeQuantity(product.id, 1)}><Plus /></Button>
                    <Button size="icon" variant="ghost" aria-label={`Remove ${product.name} from cart`} onClick={() => remove(product.id)}><Trash2 /></Button>
                  </div>
                </article>
              );
            })}
            <Button variant="ghost" asChild><Link to="/shop">Continue shopping</Link></Button>
          </section>

          <Card className="h-fit shadow-card lg:sticky lg:top-24">
            <CardContent className="space-y-4 p-6">
              <h2 className="font-display text-lg font-bold">Order summary</h2>
              <div className="flex justify-between text-sm text-muted-foreground"><span>Subtotal</span><span>{money(subtotal)}</span></div>
              <p className="text-xs text-muted-foreground">Choose a store at pickup checkout. Any available quantity is reserved; backorders include an estimated availability date.</p>
              <Button variant="lime" size="xl" className="w-full" asChild>
                <Link to="/shop/pickup">Continue to store pickup <ArrowRight /></Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
