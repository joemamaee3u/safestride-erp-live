# SafeStride ERP setup

This version keeps the existing SafeStride app and adds the operations needed for the class demo. The new database changes are additive and preserve current inventory balances. The seed adds SafeStride demo items, suppliers, customers, opening stock only where a balance is missing, six months of clearly marked synthetic sales history, supplier history, and a few open customer orders for the MRP screen.

## 1. Apply the ERP database changes

Open the Supabase project already used by this app, then open **SQL Editor**. Run the six new migration files in this order, one at a time:

1. `supabase/migrations/20261116190000_erp_operational_schema.sql`
2. `supabase/migrations/20261116191000_erp_demo_seed.sql`
3. `supabase/migrations/20261116192000_erp_transaction_functions.sql`
4. `supabase/migrations/20261116193000_erp_reporting_functions.sql`
5. `supabase/migrations/20261116194000_erp_module_data.sql`
6. `supabase/migrations/20261116195000_customer_storefront.sql`

Run each whole file. Wait for Supabase to show success before running the next. Keep existing `products`, `locations`, `inventory_balances`, `inventory_movements`, and `user_roles` data. The setup expects those base tables and the existing role helper functions to already be present in the current project.

## 2. Create staff and customer accounts

In **Authentication → Users**, make sure email/password sign-in is enabled. Create or sign up with the account that should own the demo. The first signed-in account with no staff assigned can claim the first administrator role from the staff sign-in flow. For a classroom demonstration, turn off email confirmation temporarily if you want new accounts to sign in immediately.

Sign in at `/auth` for the staff ERP. Create additional team accounts there or from **Settings → Staff roles**, then set their role. Customer accounts use **My account** on the storefront; these do not receive staff access.

## 3. Run the website

From this project folder, install the packages and start the local site:

```powershell
npm install
npm run dev
```

Open the local address printed by the development server. Staff pages are under `/erp`; the customer shop is at `/shop`.

## 4. Fast demo navigation

- **Point of Sale**: scan a barcode or search for a product, add multiple lines, apply a discount, and complete the sale to update inventory and financials.
- **Inventory**: switch among the three Utah locations, transfer or adjust stock, post cycle counts, and view backorders and supplier lead-time dates.
- **Returns & Exchanges**: choose a receipt and item, select a quality reason and disposition, then refund or exchange.
- **Production Orders**: create a run for a BOM parent, issue components, record good and scrapped units, and review yield, scrap, and cycle-time history.
- **Purchasing**: create a PO, receive quantities, record supplier payments, and review calculated supplier scorecards.
- **MRP**: show four weeks of confirmed-order component needs plus lead-time and EOQ reorder suggestions.
- **Financial Reporting / Manager Reports**: show live profit and loss, weighted-average inventory valuation, turnover, sales trends, low stock, and supplier performance.
- **Barcode Operations**: print Code 39 labels for the numeric seeded barcodes, then scan a physical printout into a cycle count or the POS scanner.
- **Shop / My Account / Store Pickup**: view live availability at each retail location, create a customer account, then reserve a pickup order.

## Notes

- The local website code is ready, but the new screens need the six SQL files above applied to your Supabase project before live ERP data and actions will work.
- Demo sales history is labeled `demo_history` and does not change current on-hand inventory.
- If Supabase has email confirmation enabled, a newly created account may need confirmation before it can sign in.
- The product barcodes are numeric and the label page prints them as Code 39. Use a barcode reader that supports Code 39.
