import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import OpenAI from "npm:openai";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function options() {
  return new Response("ok", { headers: corsHeaders });
}

export async function readError(error: unknown) {
  if (error instanceof Error) return error.message;
  return "Error inesperado";
}


export function userClient(req: Request): SupabaseClient | null {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  if (!url || !key || !authorization) return null;
  return createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function requireUser(supabase: SupabaseClient) {
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}


export function openAiConfig(): { apiKey: string; model: string; embeddingModel: string } | { error: string } {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL");
  const embeddingModel = Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "";
  if (!apiKey || !model) {
    return {
      error: "Falta configurar OPENAI_API_KEY y OPENAI_MODEL como secretos de la función. No se inventó ningún análisis.",
    };
  }
  return { apiKey, model, embeddingModel };
}

export function openAiClient(apiKey: string) {
  return new OpenAI({ apiKey });
}

export async function withRetries<T>(work: () => Promise<T>, attempts = 3): Promise<T> {
  let last: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await work();
    } catch (error) {
      last = error;
      const status = typeof error === "object" && error && "status" in error ? Number(error.status) : 0;
      const retry = status === 429 || status >= 500 || status === 0;
      if (!retry || attempt === attempts - 1) throw error;
      await new Promise((resolve) => setTimeout(resolve, 400 * 2 ** attempt));
    }
  }
  throw last;
}

export async function structuredResponse<T>(
  client: OpenAI,
  model: string,
  name: string,
  schema: Record<string, unknown>,
  instructions: string,
  content: string,
): Promise<T> {
  const response = await withRetries(() =>
    client.responses.create({
      model,
      input: [
        { role: "system", content: instructions },
        { role: "user", content },
      ],
      text: {
        format: {
          type: "json_schema",
          name,
          strict: true,
          schema,
        },
      },
    })
  );
  const text = response.output_text;
  if (!text) throw new Error("OpenAI no devolvió una respuesta estructurada.");
  return JSON.parse(text) as T;
}


Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return options();
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const supabase = userClient(req);
    if (!supabase) return json({ error: "Supabase no está configurado en la función." }, 500);
    const user = await requireUser(supabase);
    if (!user) return json({ error: "Sesión no válida." }, 401);
    void user;

    const body = await req.json().catch(() => null) as { bookId?: string } | null;
    if (!body?.bookId) return json({ error: "Falta el libro." }, 400);

    const config = openAiConfig();
    if ("error" in config) return json({ error: config.error }, 503);
    if (!config.embeddingModel) {
      return json({ error: "Falta OPENAI_EMBEDDING_MODEL en los secretos de la función." }, 503);
    }

    const { data: chunks, error } = await supabase
      .from("search_chunks")
      .select("id, content")
      .eq("book_id", body.bookId)
      .is("embedding", null)
      .limit(12);
    if (error) throw error;
    if (!chunks?.length) return json({ embedded: 0, remaining: 0 });

    const client = openAiClient(config.apiKey);
    const embedded = await client.embeddings.create({
      model: config.embeddingModel,
      input: chunks.map((chunk) => chunk.content.slice(0, 8000)),
    });

    for (let index = 0; index < chunks.length; index++) {
      const vector = embedded.data[index]?.embedding;
      if (!vector) continue;
      const { error: updateError } = await supabase
        .from("search_chunks")
        .update({ embedding: `[${vector.join(",")}]` })
        .eq("id", chunks[index].id);
      if (updateError) throw updateError;
    }

    const { count } = await supabase
      .from("search_chunks")
      .select("id", { count: "exact", head: true })
      .eq("book_id", body.bookId)
      .is("embedding", null);

    return json({ embedded: chunks.length, remaining: count ?? 0 });
  } catch (error) {
    return json({ error: await readError(error) }, 500);
  }
});
