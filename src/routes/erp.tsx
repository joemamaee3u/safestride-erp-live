import { createFileRoute, Outlet } from "@tanstack/react-router";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { AppSidebar } from "@/components/erp/app-sidebar";
import { TopBar } from "@/components/erp/top-bar";
import { LocationProvider } from "@/components/erp/location-context";
import { StaffGate } from "@/components/erp/staff-gate";
import { useErpRealtime } from "@/lib/erp-api";

export const Route = createFileRoute("/erp")({
  component: ErpLayout,
});

function ErpLayout() {
  useErpRealtime();
  return (
    <StaffGate>
      <LocationProvider>
        <SidebarProvider>
          <AppSidebar />
          <SidebarInset className="min-w-0 bg-background">
            <TopBar />
            <main className="flex-1 px-4 py-6 md:px-8 md:py-8">
              <div className="mx-auto w-full max-w-7xl space-y-6">
                <Outlet />
              </div>
            </main>
          </SidebarInset>
        </SidebarProvider>
      </LocationProvider>
    </StaffGate>
  );
}
