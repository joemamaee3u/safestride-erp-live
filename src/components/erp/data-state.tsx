import type { ReactNode } from "react";
import { AlertCircle, LoaderCircle } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

export function LoadingState({ label = "Loading live ERP data…" }: { label?: string }) {
  return (
    <div className="flex items-center gap-2 rounded-xl border bg-card px-4 py-5 text-sm text-muted-foreground">
      <LoaderCircle className="size-4 animate-spin" /> {label}
    </div>
  );
}

export function ErrorState({ error }: { error: unknown }) {
  const message = error instanceof Error ? error.message : "Could not load data from Supabase.";
  return (
    <Alert variant="destructive">
      <AlertCircle className="size-4" />
      <AlertTitle>Database request failed</AlertTitle>
      <AlertDescription>{message}</AlertDescription>
    </Alert>
  );
}

export function EmptyRows({ children = "No records yet." }: { children?: ReactNode }) {
  return <div className="rounded-xl border border-dashed bg-muted/30 px-5 py-8 text-center text-sm text-muted-foreground">{children}</div>;
}

export function DataTable({
  columns,
  children,
  empty = false,
}: {
  columns: string[];
  children: ReactNode;
  empty?: boolean;
}) {
  if (empty) return <EmptyRows>No records match this view yet.</EmptyRows>;
  return (
    <div className="overflow-hidden rounded-xl border bg-card shadow-card">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[680px] text-sm">
          <thead className="bg-muted/60">
            <tr>
              {columns.map((column) => (
                <th key={column} className="whitespace-nowrap px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {column}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y">{children}</tbody>
        </table>
      </div>
    </div>
  );
}

export function DataRow({ values }: { values: ReactNode[] }) {
  return (
    <tr className="hover:bg-muted/20">
      {values.map((value, index) => (
        <td key={index} className="whitespace-nowrap px-4 py-3 align-middle">{value}</td>
      ))}
    </tr>
  );
}

export function money(value: unknown) {
  const number = Number(value ?? 0);
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(Number.isFinite(number) ? number : 0);
}

export function shortDate(value: unknown) {
  if (!value) return "—";
  const date = new Date(String(value));
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}
