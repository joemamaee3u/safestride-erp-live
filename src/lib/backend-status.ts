/**
 * Whether the external database has been configured for this app.
 * Pages show empty states until real data queries are wired up.
 */
export const isDatabaseConfigured = Boolean(
  import.meta.env["VITE_SUPABASE_URL"] && import.meta.env["VITE_SUPABASE_PUBLISHABLE_KEY"],
);

export const NOT_CONNECTED_HINT = "Available once the StrideSafe database is connected";
