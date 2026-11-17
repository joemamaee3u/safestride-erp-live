import { Link } from "@tanstack/react-router";
import { isDatabaseConfigured } from "@/lib/backend-status";
import { cn } from "@/lib/utils";

export function ConnectionPill({ className }: { className?: string }) {
  return (
    <Link
      to="/erp/settings"
      className={cn(
        "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-medium transition-colors hover:bg-muted",
        isDatabaseConfigured
          ? "border-lime bg-lime-soft text-lime-foreground"
          : "border-warning/50 bg-warning-soft text-warning-foreground",
        className,
      )}
    >
      <span
        className={cn("size-2 rounded-full", isDatabaseConfigured ? "bg-lime" : "bg-warning")}
      />
      {isDatabaseConfigured ? "Database configured" : "Database not connected"}
    </Link>
  );
}
