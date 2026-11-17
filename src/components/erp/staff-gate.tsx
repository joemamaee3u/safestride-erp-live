import { Link, useRouterState } from "@tanstack/react-router";
import { LoaderCircle, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useStaffAccess } from "@/hooks/use-staff-access";

export function StaffGate({ children }: { children: React.ReactNode }) {
  const { user, isStaff, isChecking, error } = useStaffAccess();
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  if (isChecking) {
    return <div className="flex min-h-screen items-center justify-center gap-2 text-muted-foreground"><LoaderCircle className="size-4 animate-spin" /> Checking staff access…</div>;
  }
  if (!user || !isStaff) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
        <Card className="w-full max-w-md shadow-card">
          <CardHeader>
            <div className="flex size-11 items-center justify-center rounded-xl bg-navy text-lime"><ShieldCheck className="size-5" /></div>
            <CardTitle>{user ? "Staff access required" : "Sign in to the staff ERP"}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-muted-foreground">
              {user
                ? "This account has no staff role. Ask an administrator to add you under Settings."
                : "The register, inventory controls, and financial reports are available to staff accounts."}
            </p>
            {error && <p className="text-sm text-destructive">{error instanceof Error ? error.message : "Staff check failed."}</p>}
            {!user && <Button asChild variant="lime" className="w-full"><Link to="/auth" search={{ redirect: pathname }}>Staff sign in</Link></Button>}
            {user && <Button asChild variant="outline" className="w-full"><Link to="/shop">Return to storefront</Link></Button>}
          </CardContent>
        </Card>
      </div>
    );
  }
  return <>{children}</>;
}
