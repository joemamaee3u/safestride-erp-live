import { useState, type FormEvent } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, Loader2, ShieldCheck } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { erpRpc } from "@/lib/erp-api";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { pageMeta } from "@/lib/seo";

function safeRedirect(value: unknown): string {
  return typeof value === "string" && value.startsWith("/") && !value.startsWith("//")
    ? value
    : "/erp/inventory";
}

export const Route = createFileRoute("/auth")({
  validateSearch: (search: Record<string, unknown>): { redirect?: string } =>
    typeof search["redirect"] === "string" ? { redirect: search["redirect"] } : {},
  head: () => ({
    meta: pageMeta(
      "Staff sign in — IER ERP",
      "Sign in to IER ERP to see product costs and inventory movement history.",
    ),
  }),
  component: AuthPage,
});

function AuthPage() {
  const { redirect } = Route.useSearch();
  const target = safeRedirect(redirect);
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function signIn(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) return setError(error.message);
    try {
      const claim = await erpRpc<{ claimed: boolean }>("erp_claim_first_admin");
      if (claim?.claimed) setNotice("This is the first staff account, so administrator access is ready.");
    } catch (claimError) {
      setError(claimError instanceof Error ? claimError.message : "Staff access could not be initialized.");
    }
    await queryClient.invalidateQueries({ queryKey: ["auth"] });
    navigate({ to: target });
  }

  async function signUp(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: `${window.location.origin}/auth` },
    });
    setBusy(false);
    if (error) return setError(error.message);
    if (data.session) {
      try {
        const claim = await erpRpc<{ claimed: boolean }>("erp_claim_first_admin");
        if (claim?.claimed) setNotice("This is the first staff account, so administrator access is ready.");
      } catch (claimError) {
        setError(claimError instanceof Error ? claimError.message : "Staff access could not be initialized.");
      }
      await queryClient.invalidateQueries({ queryKey: ["auth"] });
      navigate({ to: target });
    } else {
      setNotice("Account created. Check your email to confirm it, then sign in.");
    }
  }

  const fields = (
    <>
      <div className="space-y-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          type="password"
          autoComplete="current-password"
          required
          minLength={6}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </div>
    </>
  );

  return (
    <div className="flex min-h-screen items-center justify-center bg-navy px-4 py-10">
      <Card className="w-full max-w-md shadow-card">
        <CardHeader>
          <div className="mb-2 flex size-12 items-center justify-center rounded-xl bg-navy text-lime">
            <ShieldCheck className="size-6" />
          </div>
          <CardTitle className="font-display text-2xl">IER staff sign in</CardTitle>
          <p className="text-sm text-muted-foreground">
            Costs and movement history are visible only to accounts an administrator has given
            staff access.
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
          {notice && (
            <Alert>
              <AlertDescription>{notice}</AlertDescription>
            </Alert>
          )}
          <Tabs defaultValue="signin">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="signin">Sign in</TabsTrigger>
              <TabsTrigger value="signup">Create account</TabsTrigger>
            </TabsList>
            <TabsContent value="signin">
              <form onSubmit={signIn} className="space-y-4 pt-2">
                {fields}
                <Button type="submit" variant="lime" className="w-full" disabled={busy}>
                  {busy && <Loader2 className="animate-spin" />} Sign in
                </Button>
              </form>
            </TabsContent>
            <TabsContent value="signup">
              <form onSubmit={signUp} className="space-y-4 pt-2">
                {fields}
                <Button type="submit" variant="lime" className="w-full" disabled={busy}>
                  {busy && <Loader2 className="animate-spin" />} Create account
                </Button>
                <p className="text-xs text-muted-foreground">
                  New accounts don't have staff access until an administrator grants it.
                </p>
              </form>
            </TabsContent>
          </Tabs>
          <Link
            to="/erp/inventory"
            className="inline-flex items-center gap-1 text-sm font-medium text-muted-foreground hover:text-foreground"
          >
            <ArrowLeft className="size-4" /> Back to inventory
          </Link>
        </CardContent>
      </Card>
    </div>
  );
}
