import { useEffect, useState } from "react";

export interface StoreCartLine {
  product_id: string;
  quantity: number;
}

const CART_KEY = "ier-store-cart";
const CART_EVENT = "ier-store-cart-change";

function readCart(): StoreCartLine[] {
  if (typeof window === "undefined") return [];
  try {
    const value: unknown = JSON.parse(window.localStorage.getItem(CART_KEY) ?? "[]");
    if (!Array.isArray(value)) return [];
    return value.filter(
      (line): line is StoreCartLine =>
        typeof line?.product_id === "string" &&
        Number.isInteger(line?.quantity) &&
        line.quantity > 0,
    );
  } catch {
    return [];
  }
}

export function saveStoreCart(lines: StoreCartLine[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(CART_KEY, JSON.stringify(lines));
  window.dispatchEvent(new Event(CART_EVENT));
}

export function useStoreCart() {
  const [lines, setLinesState] = useState<StoreCartLine[]>([]);

  useEffect(() => {
    const sync = () => setLinesState(readCart());
    sync();
    window.addEventListener(CART_EVENT, sync);
    window.addEventListener("storage", sync);
    return () => {
      window.removeEventListener(CART_EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const setLines = (next: StoreCartLine[] | ((current: StoreCartLine[]) => StoreCartLine[])) => {
    saveStoreCart(typeof next === "function" ? next(readCart()) : next);
  };

  return { lines, setLines };
}
