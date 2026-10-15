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

    const body = await req.json().catch(() => null) as {
      query?: string;
      bookId?: string | null;
      scope?: "book" | "library" | "highlights";
    } | null;
    const query = body?.query?.trim() ?? "";
    if (query.length < 2) return json({ error: "Escribe un concepto para buscar." }, 400);

    const config = openAiConfig();
    if ("error" in config) return json({ error: config.error }, 503);
    if (!config.embeddingModel) {
      return json({ error: "Falta OPENAI_EMBEDDING_MODEL. La búsqueda semántica no se simuló." }, 503);
    }

    const client = openAiClient(config.apiKey);
    if (body.scope === "highlights") {
      return json({ results: await searchHighlights(supabase, client, config.embeddingModel, query, body.bookId ?? null) });
    }
    const embedded = await client.embeddings.create({ model: config.embeddingModel, input: query });
    const vector = embedded.data[0]?.embedding;
    if (!vector) return json({ error: "OpenAI no devolvió un vector de búsqueda." }, 502);

    const { data, error } = await supabase.rpc("match_chunks", {
      query_embedding: `[${vector.join(",")}]`,
      target_book: body?.bookId ?? null,
      match_count: 12,
    });
    if (error) throw error;

    const rows = data ?? [];
    const bookIds = [...new Set(rows.map((row: { book_id: string }) => row.book_id))];
    const { data: books } = bookIds.length
      ? await supabase.from("books").select("id, title, author").in("id", bookIds)
      : { data: [] };
    const titles = new Map((books ?? []).map((book) => [book.id, book]));

    return json({
      results: rows.map((row: {
        chunk_id: string;
        book_id: string;
        chapter_id: string | null;
        page_start: number;
        page_end: number;
        content: string;
        similarity: number;
      }) => ({
        chunkId: row.chunk_id,
        bookId: row.book_id,
        chapterId: row.chapter_id,
        title: titles.get(row.book_id)?.title ?? "Libro",
        author: titles.get(row.book_id)?.author ?? "",
        pdfPage: row.page_start,
        pageEnd: row.page_end,
        snippet: String(row.content).replace(/\[p\.\d+\]/g, "").replace(/\s+/g, " ").trim().slice(0, 320),
        similarity: row.similarity,
      })),
    });
  } catch (error) {
    return json({ error: await readError(error) }, 500);
  }
});

async function searchHighlights(
  supabase: NonNullable<ReturnType<typeof userClient>>,
  client: ReturnType<typeof openAiClient>,
  model: string,
  query: string,
  bookId: string | null,
) {
  let request = supabase
    .from("highlights")
    .select("id, book_id, page_number, quote, note, explanation_es")
    .eq("dismissed", false)
    .limit(60);
  if (bookId) request = request.eq("book_id", bookId);
  const { data, error } = await request;
  if (error) throw error;
  const rows = data ?? [];
  if (!rows.length) return [];

  const embedded = await client.embeddings.create({
    model,
    input: [query, ...rows.map((row) => `${row.quote}\n${row.note ?? ""}\n${row.explanation_es ?? ""}`.slice(0, 1200))],
  });
  const queryVector = embedded.data[0]?.embedding ?? [];
  const ranked = rows
    .map((row, index) => ({
      row,
      similarity: cosine(queryVector, embedded.data[index + 1]?.embedding ?? []),
    }))
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, 12);
  const ids = [...new Set(ranked.map((item) => item.row.book_id))];
  const { data: books } = await supabase.from("books").select("id, title, author").in("id", ids);
  const titles = new Map((books ?? []).map((book) => [book.id, book]));
  return ranked.map((item) => ({
    chunkId: item.row.id,
    bookId: item.row.book_id,
    chapterId: null,
    title: titles.get(item.row.book_id)?.title ?? "Libro",
    author: titles.get(item.row.book_id)?.author ?? "",
    pdfPage: item.row.page_number,
    pageEnd: item.row.page_number,
    snippet: item.row.quote,
    similarity: item.similarity,
  }));
}

function cosine(left: number[], right: number[]) {
  let dot = 0;
  let leftNorm = 0;
  let rightNorm = 0;
  const length = Math.min(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    dot += left[index] * right[index];
    leftNorm += left[index] * left[index];
    rightNorm += right[index] * right[index];
  }
  if (!leftNorm || !rightNorm) return 0;
  return dot / Math.sqrt(leftNorm * rightNorm);
}
