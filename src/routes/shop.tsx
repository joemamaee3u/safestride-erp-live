import { createFileRoute, Outlet } from "@tanstack/react-router";
import { ShopFooter, ShopHeader } from "@/components/shop/shop-header";

export const Route = createFileRoute("/shop")({
  component: ShopLayout,
});

function ShopLayout() {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <ShopHeader />
      <main className="flex-1">
        <Outlet />
      </main>
      <ShopFooter />
    </div>
  );
}
