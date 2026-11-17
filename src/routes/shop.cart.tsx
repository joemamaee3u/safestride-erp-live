import { createFileRoute, Link } from "@tanstack/react-router";
import { ShoppingBag, Store, Truck } from "lucide-react";
import { EmptyState, PendingButton } from "@/components/erp/page-parts";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { pageMeta } from "@/lib/seo";

export const Route = createFileRoute("/shop/cart")({
  head: () => ({
    meta: pageMeta("Your Cart — StrideSafe", "Review the items in your StrideSafe cart."),
  }),
  component: CartPage,
});

function CartPage() {
  return (
    <div className="mx-auto max-w-7xl px-4 py-10 md:px-8">
      <h1 className="text-3xl font-bold">Your cart</h1>
      <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_360px]">
        <EmptyState
          icon={ShoppingBag}
          title="Your cart is empty"
          description="Items you add from the shop will show up here."
          className="min-h-[320px]"
          action={
            <Button variant="lime" asChild>
              <Link to="/shop">Continue shopping</Link>
            </Button>
          }
        />
        <Card className="shadow-card lg:self-start">
          <CardContent className="space-y-4 p-6">
            <h2 className="font-display text-lg font-bold">Order summary</h2>
            <div className="space-y-2 text-sm">
              {["Subtotal", "Estimated tax"].map((r) => (
                <div key={r} className="flex justify-between text-muted-foreground">
                  <span>{r}</span>
                  <span>—</span>
                </div>
              ))}
              <Separator />
              <div className="flex justify-between font-display text-lg font-bold">
                <span>Total</span>
                <span className="text-foreground/30">—</span>
              </div>
            </div>
            <div className="space-y-2">
              <p className="text-sm font-medium">How would you like to get it?</p>
              <div className="grid grid-cols-2 gap-2">
                <Link
                  to="/shop/pickup"
                  className="flex flex-col items-center gap-1 rounded-lg border p-3 text-sm font-medium hover:border-lime hover:bg-lime-soft"
                >
                  <Store className="size-5" /> Store pickup
                </Link>
                <div className="flex flex-col items-center gap-1 rounded-lg border p-3 text-sm font-medium text-muted-foreground">
                  <Truck className="size-5" /> Shipping
                </div>
              </div>
            </div>
            <PendingButton variant="lime" size="xl" className="w-full">
              Checkout
            </PendingButton>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
