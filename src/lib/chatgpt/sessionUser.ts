import { requireSupabase } from "../supabase";

export async function requireSmartBooksUserId() {
  const supabase = requireSupabase();
  const { data, error } = await supabase.auth.getUser();
  if (error) throw error;
  if (!data.user) throw new Error("Inicia sesión en Smart Books para continuar.");
  return data.user.id;
}
