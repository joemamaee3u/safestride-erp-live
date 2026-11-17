import { useEffect } from "react";
import { Link, useRouterState } from "@tanstack/react-router";
import { Store, Zap } from "lucide-react";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
  useSidebar,
} from "@/components/ui/sidebar";
import { ERP_NAV } from "@/lib/erp-nav";

export function AppSidebar() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { setOpenMobile } = useSidebar();
  // Close the mobile drawer after navigating so the page is visible right away.
  useEffect(() => {
    setOpenMobile(false);
  }, [pathname, setOpenMobile]);
  const isActive = (to: string) =>
    to === "/erp" ? pathname === "/erp" || pathname === "/erp/" : pathname.startsWith(to);

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="border-b border-sidebar-border">
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton size="lg" asChild tooltip="StrideSafe ERP">
              <Link to="/erp">
                <div className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-lime text-lime-foreground">
                  <Zap className="size-4" />
                </div>
                <div className="flex flex-col leading-tight">
                  <span className="font-display text-base font-bold text-navy-foreground">
                    StrideSafe
                  </span>
                  <span className="text-[11px] uppercase tracking-[0.18em] text-sidebar-foreground">
                    ERP
                  </span>
                </div>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent>
        {ERP_NAV.map((group) => (
          <SidebarGroup key={group.label}>
            <SidebarGroupLabel className="text-[11px] uppercase tracking-[0.16em] text-sidebar-foreground/60">
              {group.label}
            </SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {group.items.map((item) => (
                  <SidebarMenuItem key={item.to}>
                    <SidebarMenuButton
                      asChild
                      isActive={isActive(item.to)}
                      tooltip={item.title}
                      className="h-9"
                    >
                      <Link to={item.to}>
                        <item.icon />
                        <span>{item.title}</span>
                      </Link>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        ))}
      </SidebarContent>

      <SidebarFooter className="border-t border-sidebar-border">
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton asChild tooltip="Open online storefront">
              <Link to="/shop">
                <Store />
                <span>Open online storefront</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}
