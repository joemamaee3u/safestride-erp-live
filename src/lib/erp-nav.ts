import {
  LayoutDashboard,
  ScanLine,
  ShoppingCart,
  RotateCcw,
  Boxes,
  Barcode,
  Factory,
  Truck,
  Network,
  Users,
  Landmark,
  BarChart3,
  Settings,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  title: string;
  to: string;
  icon: LucideIcon;
  description: string;
}

export interface NavGroup {
  label: string;
  items: NavItem[];
}

export const ERP_NAV: NavGroup[] = [
  {
    label: "Overview",
    items: [
      {
        title: "Dashboard",
        to: "/erp",
        icon: LayoutDashboard,
        description: "Company-wide snapshot across all three locations",
      },
    ],
  },
  {
    label: "Sell",
    items: [
      {
        title: "Point of Sale",
        to: "/erp/pos",
        icon: ScanLine,
        description: "Ring up in-store sales at the Utah retail locations",
      },
      {
        title: "Sales Orders",
        to: "/erp/sales-orders",
        icon: ShoppingCart,
        description: "In-store, online, and pickup orders",
      },
      {
        title: "Returns & Exchanges",
        to: "/erp/returns",
        icon: RotateCcw,
        description: "Process returns, exchanges, and refunds",
      },
      {
        title: "Customers",
        to: "/erp/customers",
        icon: Users,
        description: "Customer profiles and purchase history",
      },
    ],
  },
  {
    label: "Operate",
    items: [
      {
        title: "Inventory",
        to: "/erp/inventory",
        icon: Boxes,
        description: "Stock levels, transfers, and adjustments by location",
      },
      {
        title: "Barcode Operations",
        to: "/erp/barcodes",
        icon: Barcode,
        description: "Scan to receive, transfer, count, and print labels",
      },
      {
        title: "Production Orders",
        to: "/erp/production",
        icon: Factory,
        description: "Plan and track manufacturing runs",
      },
      {
        title: "Purchasing & Suppliers",
        to: "/erp/purchasing",
        icon: Truck,
        description: "Purchase orders, suppliers, and receiving",
      },
      {
        title: "MRP",
        to: "/erp/mrp",
        icon: Network,
        description: "Material requirements planning",
      },
    ],
  },
  {
    label: "Analyze",
    items: [
      {
        title: "Financials",
        to: "/erp/financials",
        icon: Landmark,
        description: "Ledger, receivables, payables, and tax",
      },
      {
        title: "Reports",
        to: "/erp/reports",
        icon: BarChart3,
        description: "Sales, inventory, production, and financial reports",
      },
      {
        title: "Settings",
        to: "/erp/settings",
        icon: Settings,
        description: "Company, locations, users, and connections",
      },
    ],
  },
];

export const ALL_NAV_ITEMS = ERP_NAV.flatMap((g) => g.items);

