import { requireSupabase } from "./supabase";

export async function invokeFunction<T>(name: string, body: unknown): Promise<T> {
  const client = requireSupabase();
  const { data, error } = await client.functions.invoke(name, { body: body as object });
  if (error) {
    let message = error.message;
    const context = (error as { context?: Response }).context;
    if (context && typeof context.json === "function") {
      try {
        const payload = await context.json() as { error?: string };
        if (payload?.error) message = payload.error;
      } catch {
        // La respuesta ya no trae JSON.
      }
    }
    throw new Error(message);
  }
  if (data && typeof data === "object" && "error" in data && data.error) {
    throw new Error(String(data.error));
  }
  return data as T;
}
