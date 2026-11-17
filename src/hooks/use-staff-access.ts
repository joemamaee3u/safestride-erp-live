import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface SignedInUser {
  id: string;
  email: string | null;
}

/** Who is signed in, and whether the database recognises them as staff. */
export function useStaffAccess() {
  const userQuery = useQuery({
    queryKey: ["auth", "user"],
    queryFn: async (): Promise<SignedInUser | null> => {
      const { data } = await supabase.auth.getSession();
      if (!data.session) return null;
      const { data: userData, error } = await supabase.auth.getUser();
      if (error || !userData.user) return null;
      return { id: userData.user.id, email: userData.user.email ?? null };
    },
    staleTime: 60_000,
  });

  const user = userQuery.data ?? null;

  const staffQuery = useQuery({
    queryKey: ["auth", "is-staff", user?.id],
    enabled: Boolean(user),
    queryFn: async () => {
      const { data, error } = await supabase.rpc("current_user_is_staff");
      if (error) throw new Error(error.message);
      return Boolean(data);
    },
    staleTime: 60_000,
  });

  return {
    user,
    isStaff: Boolean(user) && staffQuery.data === true,
    isChecking: userQuery.isPending || (Boolean(user) && staffQuery.isPending),
    error: staffQuery.error,
  };
}
