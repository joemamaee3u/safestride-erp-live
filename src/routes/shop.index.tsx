import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, Search, Shirt } from "lucide-react";
import heroImg from "@/assets/storefront-hero.jpg";
import productSheet from "@/assets/ier-product-contact-sheet.png";
import { LoadingState, ErrorState } from "@/components/erp/data-state";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useStorefrontCatalog, type ErpProduct } from "@/lib/erp-api";
import { pageMeta } from "@/lib/seo";
import { PRODUCT_CATEGORIES } from "@/lib/catalog";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/shop/")({
  head: () => ({
    meta: pageMeta("IER Outdoor Gear & Apparel", "Shop trail, camping, hiking, and outdoor essentials from IER."),
  }),
  component: CatalogPage,
});

const PRODUCT_PHOTO_INDEX: Record<string, number> = {
  "SSF-101": 0,
  "SSF-102": 1,
  "SSF-103": 2,
  "SSF-104": 3,
  "IER-301": 4,
  "IER-302": 5,
  "IER-303": 6,
  "IER-304": 7,
  "IER-305": 8,
  "IER-306": 9,
  "IER-307": 10,
  "CMP-220": 11,
  "SSF-105": 12,
  "IER-308": 13,
};

function ProductPhoto({ product, className }: { product: ErpProduct; className?: string }) {
  const index = PRODUCT_PHOTO_INDEX[product.sku] ?? 12;
  const column = index % 4;
  const row = Math.floor(index / 4);

  return (
    <div
      role="img"
      aria-label={product.name}
      className={cn("bg-no-repeat", className)}
      style={{
        backgroundImage: `url(${productSheet})`,
        backgroundSize: "400% 400%",
        backgroundPosition: `${(column / 3) * 100}% ${(row / 3) * 100}%`,
      }}
    />
  );
}

function CatalogPage() {
  const [category, setCategory] = useState("All");
  const [search, setSearch] = useState("");
  const [selectedProduct, setSelectedProduct] = useState<ErpProduct | null>(null);
  const q = useStorefrontCatalog();
  const products = q.data ?? [];

  const visible = useMemo(() => {
    const byId = new Map<string, ErpProduct[]>();
    for (const product of products) {
      const rows = byId.get(product.id) ?? [];
      rows.push(product);
      byId.set(product.id, rows);
    }
    return [...byId.values()]
      .map((rows) => rows[0]!)
      .filter(
        (product) =>
          (category === "All" || product.category === category) &&
          `${product.name} ${product.sku}`.toLowerCase().includes(search.toLowerCase()),
      );
  }, [products, category, search]);

  const selectedAvailability = selectedProduct
    ? products
        .filter((product) => product.id === selectedProduct.id)
        .reduce((sum, product) => sum + Number(product.quantity_available), 0)
    : 0;

  return (
    <>
      <section className="relative overflow-hidden bg-navy text-navy-foreground">
        <img
          src={heroImg}
          alt="Outdoor adventurer heading into the mountains at dusk"
          className="absolute inset-0 h-full w-full object-cover object-right opacity-90"
        />
        <div className="absolute inset-0 bg-gradient-to-r from-navy via-navy/80 to-transparent" />
        <div className="relative mx-auto max-w-7xl px-4 py-20 md:px-8 md:py-32">
          <p className="text-sm font-semibold uppercase tracking-[.2em] text-lime">
            Find your next trail.
          </p>
          <h1 className="mt-4 max-w-xl text-4xl font-black leading-tight md:text-6xl">
            Gear for the miles beyond.
          </h1>
          <p className="mt-5 max-w-md text-navy-foreground/80">
            Camping, hiking, footwear, apparel, and outdoor essentials for your next adventure.
          </p>
          <Button className="mt-8" variant="lime" size="xl" asChild>
            <a href="#catalog">
              Explore outdoor gear <ArrowRight />
            </a>
          </Button>
        </div>
      </section>

      <section id="catalog" className="mx-auto max-w-7xl px-4 py-12 md:px-8">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h2 className="text-3xl font-bold">Shop all</h2>
            <p className="mt-1 text-muted-foreground">
              Thoughtful gear for the trail, campsite, and everywhere between.
            </p>
          </div>
          <div className="flex gap-3">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                className="pl-9"
                placeholder="Search gear"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
              />
            </div>
            <Button variant="outline" asChild>
              <Link to="/shop/account">My account</Link>
            </Button>
          </div>
        </div>

        <div className="mt-6 flex flex-wrap gap-2">
          {["All", ...PRODUCT_CATEGORIES].map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => setCategory(item)}
              aria-pressed={category === item}
              className={cn(
                "rounded-full border px-4 py-2 text-sm font-medium transition-colors",
                category === item
                  ? "border-navy bg-navy text-navy-foreground"
                  : "bg-card hover:border-lime hover:bg-lime-soft",
              )}
            >
              {item}
            </button>
          ))}
        </div>

        {q.isPending ? (
          <div className="mt-8">
            <LoadingState label="Loading outdoor gear…" />
          </div>
        ) : q.error ? (
          <div className="mt-8">
            <ErrorState error={q.error} />
          </div>
        ) : visible.length === 0 ? (
          <div className="mt-8 rounded-xl border border-dashed p-10 text-center">
            <Shirt className="mx-auto mb-3 size-8 text-muted-foreground" />
            <div className="font-semibold">No matching products</div>
            <p className="mt-1 text-sm text-muted-foreground">
              Try another search or category.
            </p>
          </div>
        ) : (
          <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {visible.map((product) => {
              const available = products
                .filter((row) => row.id === product.id)
                .reduce((sum, row) => sum + Number(row.quantity_available), 0);

              return (
                <article
                  key={product.id}
                  className="group overflow-hidden rounded-2xl border bg-card shadow-sm transition-shadow hover:shadow-card"
                >
                  <div className="relative overflow-hidden bg-[#f3efe8]">
                    <ProductPhoto
                      product={product}
                      className="aspect-[4/3] w-full transition-transform duration-500 group-hover:scale-105"
                    />
                    {available > 0 && (
                      <span className="absolute left-3 top-3 rounded-full bg-white/90 px-3 py-1 text-xs font-semibold text-foreground shadow-sm">
                        In stock
                      </span>
                    )}
                  </div>
                  <div className="p-4">
                    <p className="text-xs font-semibold uppercase tracking-[0.14em] text-lime-foreground">
                      {product.category}
                    </p>
                    <h3 className="mt-2 min-h-12 font-display text-lg font-bold leading-snug">
                      {product.name}
                    </h3>
                    <div className="mt-3 flex items-center justify-between border-t pt-3">
                      <span className="text-xl font-bold">${Number(product.price).toFixed(2)}</span>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setSelectedProduct(product)}
                      >
                        View item <ArrowRight />
                      </Button>
                    </div>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      <Dialog
        open={!!selectedProduct}
        onOpenChange={(open) => {
          if (!open) setSelectedProduct(null);
        }}
      >
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          {selectedProduct && (
            <>
              <DialogHeader>
                <DialogTitle>{selectedProduct.name}</DialogTitle>
                <DialogDescription>
                  {selectedProduct.category} · {selectedProduct.sku}
                </DialogDescription>
              </DialogHeader>
              <div className="grid gap-5 sm:grid-cols-2 sm:items-center">
                <ProductPhoto
                  product={selectedProduct}
                  className="aspect-square w-full rounded-xl bg-[#f3efe8]"
                />
                <div>
                  <p className="text-2xl font-bold">
                    ${Number(selectedProduct.price).toFixed(2)}
                  </p>
                  <p className="mt-3 text-sm text-muted-foreground">
                    {selectedAvailability > 0
                      ? "Available at our Utah stores. Choose a location during pickup ordering."
                      : "Not currently in stock. Check pickup options for the latest availability."}
                  </p>
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setSelectedProduct(null)}>
                  Keep browsing
                </Button>
                <Button variant="lime" asChild>
                  <Link to="/shop/pickup">
                    Check pickup options <ArrowRight />
                  </Link>
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
