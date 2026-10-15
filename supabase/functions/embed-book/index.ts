import { requireUser, userClient } from "../_shared/auth.ts";
import { json, options, readError } from "../_shared/http.ts";
import { openAiClient, openAiConfig } from "../_shared/openai.ts";

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
