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

export type HighlightIntensity = "essential" | "balanced" | "detailed";

export const INTENSITY_LIMITS: Record<HighlightIntensity, { perWindow: number; perChapter: number; label: string; hint: string }> = {
  essential: {
    perWindow: 4,
    perChapter: 6,
    label: "Esencial",
    hint: "Solo las ideas sin las cuales el capítulo no se entiende.",
  },
  balanced: {
    perWindow: 7,
    perChapter: 12,
    label: "Equilibrado",
    hint: "Ideas, definiciones y conclusiones, sin marcar párrafos de más.",
  },
  detailed: {
    perWindow: 10,
    perChapter: 20,
    label: "Detallado",
    hint: "Incluye datos, fórmulas y matices necesarios, todavía con criterio.",
  },
};

export const CATEGORIES = ["idea", "definicion", "dato", "conclusion", "contexto", "manual"] as const;
export type HighlightCategory = (typeof CATEGORIES)[number];

export const CATEGORY_LABELS: Record<HighlightCategory, string> = {
  idea: "Idea central",
  definicion: "Definición",
  dato: "Dato o fórmula",
  conclusion: "Conclusión",
  contexto: "Contexto necesario",
  manual: "Resaltado propio",
};

export type QuoteHit = {
  start: number;
  end: number;
};

/**
 * Localiza un fragmento literal dentro del texto extraído.
 * Acepta diferencias de espacios y guiones de fin de línea.
 * Si no hay una correspondencia precisa, devuelve null: no se debe dibujar un resaltado aproximado.
 */
export function locateQuote(haystack: string, quote: string): QuoteHit | null {
  const needle = quote.replace(/\u00ad/g, "").trim();
  if (needle.length < 12) return null;

  const exact = haystack.indexOf(needle);
  if (exact >= 0) return { start: exact, end: exact + needle.length };

  const source = collapseWithMap(haystack);
  const target = collapseWithMap(needle).text;
  if (target.length < 12) return null;
  const at = source.text.indexOf(target);
  if (at < 0) return null;

  const start = source.map[at];
  const last = source.map[at + target.length - 1];
  if (start === undefined || last === undefined) return null;
  return { start, end: last + 1 };
}

export function collapseWithMap(input: string): { text: string; map: number[] } {
  let text = "";
  const map: number[] = [];
  let pendingSpace = false;

  const pushSpace = (origin: number) => {
    if (!text || text.endsWith(" ")) return;
    text += " ";
    map.push(origin);
  };

  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (ch === "\u00ad") continue;

    if (ch === "-" && (input[i + 1] === "\n" || input[i + 1] === "\r")) {
      if (input[i + 1] === "\r" && input[i + 2] === "\n") i += 2;
      else i += 1;
      pendingSpace = false;
      continue;
    }

    if (/\s/.test(ch)) {
      pendingSpace = true;
      continue;
    }

    if (pendingSpace) {
      pushSpace(i);
      pendingSpace = false;
    }
    text += ch;
    map.push(i);
  }

  return { text, map };
}

export async function quoteHash(quote: string): Promise<string> {
  const normalized = quote.replace(/\s+/g, " ").trim();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalized));
  return [...new Uint8Array(digest)].slice(0, 16).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function snippetAround(text: string, start: number, end: number, radius = 80): string {
  const from = Math.max(0, start - radius);
  const to = Math.min(text.length, end + radius);
  const prefix = from > 0 ? "…" : "";
  const suffix = to < text.length ? "…" : "";
  return `${prefix}${text.slice(from, to).replace(/\s+/g, " ").trim()}${suffix}`;
}

export type PageSlice = {
  page: number;
  text: string;
};

export type ChunkDraft = {
  pageStart: number;
  pageEnd: number;
  content: string;
};

const TARGET = 1800;

export function buildChunks(pages: PageSlice[]): ChunkDraft[] {
  const usable = pages.filter((page) => page.text.trim().length > 0);
  const chunks: ChunkDraft[] = [];
  let current: PageSlice[] = [];
  let size = 0;

  const flush = () => {
    if (!current.length) return;
    chunks.push({
      pageStart: current[0].page,
      pageEnd: current[current.length - 1].page,
      content: current.map((page) => `[p.${page.page}]\n${page.text.trim()}`).join("\n\n"),
    });
    current = [];
    size = 0;
  };

  for (const page of usable) {
    const block = page.text.trim();
    if (size > 0 && size + block.length > TARGET) flush();
    current.push(page);
    size += block.length;
    if (size >= TARGET) flush();
  }
  flush();
  return chunks;
}

export function windowsForAnalysis(pages: PageSlice[], maxChars = 12000): ChunkDraft[] {
  return buildChunks(pages).reduce<ChunkDraft[]>((groups, chunk) => {
    const last = groups[groups.length - 1];
    if (!last || last.content.length + chunk.content.length > maxChars) groups.push({ ...chunk });
    else {
      last.pageEnd = chunk.pageEnd;
      last.content = `${last.content}\n\n${chunk.content}`;
    }
    return groups;
  }, []);
}


export const analysisSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary_es: { type: "string" },
    summary_en: { type: "string" },
    highlights: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          quote: { type: "string" },
          category: { type: "string", enum: ["idea", "definicion", "dato", "conclusion", "contexto"] },
          explanation_es: { type: "string" },
          explanation_en: { type: "string" },
        },
        required: ["quote", "category", "explanation_es", "explanation_en"],
      },
    },
    key_points: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          text_es: { type: "string" },
          text_en: { type: "string" },
          quote: { type: "string" },
        },
        required: ["text_es", "text_en", "quote"],
      },
    },
  },
  required: ["summary_es", "summary_en", "highlights", "key_points"],
} as const;

export const summarySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary_es: { type: "string" },
    summary_en: { type: "string" },
  },
  required: ["summary_es", "summary_en"],
} as const;

export const explainSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    explanation_es: { type: "string" },
    explanation_en: { type: "string" },
    sufficient: { type: "boolean" },
  },
  required: ["explanation_es", "explanation_en", "sufficient"],
} as const;

export const answerSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    sufficient: { type: "boolean" },
    answer: { type: "string" },
    citations: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          pdfPage: { type: "integer" },
          quote: { type: "string" },
        },
        required: ["pdfPage", "quote"],
      },
    },
  },
  required: ["sufficient", "answer", "citations"],
} as const;

export function analysisInstructions(intensity: HighlightIntensity): string {
  const limits = INTENSITY_LIMITS[intensity];
  return [
    "Eres el editor de Margen, una aplicación de lectura.",
    "Recibes el texto de un capítulo con marcadores [p.N], donde N es la página del PDF.",
    "El libro puede estar en español o en inglés. Conserva SIEMPRE las citas en el idioma original, copiadas de forma literal.",
    "No incluyas el marcador [p.N] dentro de la cita.",
    "Cada cita debe caber en una sola página y ser un fragmento continuo que exista tal cual en el texto.",
    "No marques párrafos enteros si basta una oración o una cláusula.",
    "Selecciona con criterio: ideas centrales, definiciones, datos o fórmulas, conclusiones y pasajes necesarios para entender el capítulo.",
    `Intensidad ${limits.label}: ${limits.hint} Devuelve como máximo ${limits.perWindow} resaltados en esta ventana.`,
    "La explicación breve dice por qué importa ese fragmento. explanation_es en español y explanation_en en inglés, cada una en menos de 280 caracteres.",
    "summary_es y summary_en resumen el capítulo en un párrafo. Si esta ventana no es el capítulo entero, resume solo lo que ves.",
    "key_points son afirmaciones de estudio, no copias largas. quote puede repetir un apoyo literal o ir vacío.",
    "No inventes citas, páginas ni datos que no estén en el texto.",
  ].join("\n");
}


export type PageRecord = {
  page: number;
  text: string;
  printedLabel: string | null;
};

export type RawHighlight = {
  quote?: string;
  category?: string;
  explanation_es?: string;
  explanation_en?: string;
};

export type KeptHighlight = {
  quote: string;
  pageNumber: number;
  printedLabel: string | null;
  category: "idea" | "definicion" | "dato" | "conclusion" | "contexto";
  explanationEs: string;
  explanationEn: string;
};

const CATEGORY_SET = new Set(["idea", "definicion", "dato", "conclusion", "contexto"]);

export function validateHighlights(
  pages: PageRecord[],
  raw: RawHighlight[],
  intensity: HighlightIntensity,
): { kept: KeptHighlight[]; dropped: number } {
  const limit = INTENSITY_LIMITS[intensity].perChapter;
  const kept: KeptHighlight[] = [];
  const seen = new Set<string>();
  let dropped = 0;

  for (const item of raw) {
    if (kept.length >= limit) break;
    const quote = item.quote?.replace(/\s*\[p\.\d+\]\s*/g, " ").trim();
    const category = item.category ?? "";
    if (!quote || quote.length > 500 || !CATEGORY_SET.has(category)) {
      dropped += 1;
      continue;
    }

    const found = pages
      .map((page) => ({ page, hit: locateQuote(page.text, quote) }))
      .find((entry) => entry.hit);
    if (!found?.hit) {
      dropped += 1;
      continue;
    }

    const literal = found.page.text.slice(found.hit.start, found.hit.end);
    const key = `${found.page.page}:${literal}`;
    if (seen.has(key)) {
      dropped += 1;
      continue;
    }
    seen.add(key);
    kept.push({
      quote: literal,
      pageNumber: found.page.page,
      printedLabel: found.page.printedLabel,
      category: category as KeptHighlight["category"],
      explanationEs: (item.explanation_es || "").trim().slice(0, 500),
      explanationEn: (item.explanation_en || "").trim().slice(0, 500),
    });
  }

  return { kept, dropped };
}

export function locateSupportQuote(pages: PageRecord[], quote: string, hintedPage?: number) {
  const ordered = [...pages].sort((a, b) => {
    if (hintedPage && a.page === hintedPage) return -1;
    if (hintedPage && b.page === hintedPage) return 1;
    return a.page - b.page;
  });
  for (const page of ordered) {
    const hit = locateQuote(page.text, quote);
    if (hit) {
      return {
        pageNumber: page.page,
        printedLabel: page.printedLabel,
        quote: page.text.slice(hit.start, hit.end),
      };
    }
  }
  return null;
}


type AnalysisPayload = {
  summary_es: string;
  summary_en: string;
  highlights: { quote: string; category: string; explanation_es: string; explanation_en: string }[];
  key_points: { text_es: string; text_en: string; quote: string }[];
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return options();
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  let failure: { supabase: NonNullable<ReturnType<typeof userClient>>; bookId: string; chapterId: string; intensity: string } | null = null;
  try {
    const supabase = userClient(req);
    if (!supabase) return json({ error: "Supabase no está configurado en la función." }, 500);
    const user = await requireUser(supabase);
    if (!user) return json({ error: "Sesión no válida." }, 401);

    const body = await req.json().catch(() => null) as { bookId?: string; chapterId?: string } | null;
    if (!body?.bookId || !body.chapterId) return json({ error: "Faltan bookId y chapterId." }, 400);

    const { data: book, error: bookError } = await supabase
      .from("books")
      .select("id, highlight_intensity, language")
      .eq("id", body.bookId)
      .maybeSingle();
    if (bookError || !book) return json({ error: "No se encontró el libro." }, 404);

    const { data: chapter, error: chapterError } = await supabase
      .from("chapters")
      .select("id, title, start_page, end_page, book_id")
      .eq("id", body.chapterId)
      .eq("book_id", body.bookId)
      .maybeSingle();
    if (chapterError || !chapter) return json({ error: "No se encontró el capítulo." }, 404);

    const intensity = book.highlight_intensity as HighlightIntensity;
    const { data: existing } = await supabase
      .from("analysis_jobs")
      .select("status, started_at, attempt")
      .eq("chapter_id", chapter.id)
      .eq("intensity", intensity)
      .maybeSingle();

    if (existing?.status === "done") {
      return json({ skipped: true, reason: "done" });
    }
    if (existing?.status === "processing" && existing.started_at) {
      const age = Date.now() - new Date(existing.started_at).getTime();
      if (age < 12 * 60 * 1000) return json({ skipped: true, reason: "already_running" });
    }

    const config = openAiConfig();
    if ("error" in config) return json({ error: config.error }, 503);

    failure = { supabase, bookId: book.id, chapterId: chapter.id, intensity };
    await supabase.from("analysis_jobs").upsert({
      book_id: book.id,
      chapter_id: chapter.id,
      user_id: user.id,
      intensity,
      status: "processing",
      attempt: (existing?.attempt ?? 0) + 1,
      started_at: new Date().toISOString(),
      error: null,
      model: config.model,
    }, { onConflict: "chapter_id,intensity" });

    await supabase.from("chapters").update({ analysis_status: "processing", analysis_error: null }).eq("id", chapter.id);

    const { data: pageRows, error: pageError } = await supabase
      .from("book_pages")
      .select("page_number, text, printed_label")
      .eq("book_id", book.id)
      .gte("page_number", chapter.start_page)
      .lte("page_number", chapter.end_page)
      .order("page_number");
    if (pageError) throw pageError;

    const pages: PageRecord[] = (pageRows ?? []).map((row) => ({
      page: row.page_number,
      text: row.text ?? "",
      printedLabel: row.printed_label,
    }));
    const usable = pages.filter((page) => page.text.trim().length > 40);
    if (!usable.length) {
      await fail(supabase, user.id, book.id, chapter.id, intensity, "Este capítulo no tiene texto extraíble. Si el PDF está escaneado, falta OCR.");
      return json({ error: "Este capítulo no tiene texto extraíble." }, 422);
    }

    const windows = windowsForAnalysis(usable.map((page) => ({ page: page.page, text: page.text })));
    const client = openAiClient(config.apiKey);
    const merged: AnalysisPayload = { summary_es: "", summary_en: "", highlights: [], key_points: [] };

    for (const window of windows) {
      const payload = await structuredResponse<AnalysisPayload>(
        client,
        config.model,
        "chapter_analysis",
        analysisSchema as unknown as Record<string, unknown>,
        analysisInstructions(intensity),
        `Capítulo: ${chapter.title}\nIdioma detectado del libro: ${book.language}\n\n${window.content}`,
      );
      merged.highlights.push(...payload.highlights);
      merged.key_points.push(...payload.key_points);
      if (!merged.summary_es) merged.summary_es = payload.summary_es;
      if (!merged.summary_en) merged.summary_en = payload.summary_en;
    }

    if (windows.length > 1) {
      const summary = await structuredResponse<{ summary_es: string; summary_en: string }>(
        client,
        config.model,
        "chapter_summary",
        summarySchema as unknown as Record<string, unknown>,
        "Redacta un resumen fiel del capítulo a partir de estos puntos. summary_es en español y summary_en en inglés. No añadas datos que no estén en los puntos.",
        merged.key_points.map((point, index) => `${index + 1}. ${point.text_es}`).join("\n") || merged.summary_es,
      );
      merged.summary_es = summary.summary_es;
      merged.summary_en = summary.summary_en;
    }

    const validated = validateHighlights(pages, merged.highlights, intensity);
    await supabase
      .from("highlights")
      .delete()
      .eq("chapter_id", chapter.id)
      .eq("intensity", intensity)
      .eq("origin", "ai")
      .eq("dismissed", false);

    if (validated.kept.length) {
      const rows = await Promise.all(validated.kept.map(async (item) => ({
        book_id: book.id,
        chapter_id: chapter.id,
        user_id: user.id,
        page_number: item.pageNumber,
        quote: item.quote,
        quote_hash: await quoteHash(item.quote),
        category: item.category,
        explanation_es: item.explanationEs,
        explanation_en: item.explanationEn,
        origin: "ai",
        intensity,
      })));
      const { error: insertError } = await supabase.from("highlights").upsert(rows, {
        onConflict: "chapter_id,intensity,quote_hash",
        ignoreDuplicates: true,
      });
      if (insertError) throw insertError;
    }

    const points = merged.key_points.slice(0, 12).map((point, index) => {
      const located = point.quote?.trim() ? locateSupportQuote(pages, point.quote) : null;
      return {
        book_id: book.id,
        chapter_id: chapter.id,
        user_id: user.id,
        position: index + 1,
        text_es: point.text_es.trim().slice(0, 500),
        text_en: point.text_en.trim().slice(0, 500),
        quote: located?.quote ?? null,
        page_number: located?.pageNumber ?? null,
        printed_label: located?.printedLabel ?? null,
      };
    });

    await supabase.from("chapter_points").delete().eq("chapter_id", chapter.id);
    if (points.length) {
      const { error: pointError } = await supabase.from("chapter_points").insert(points);
      if (pointError) throw pointError;
    }

    await supabase.from("chapters").update({
      analysis_status: "done",
      analysis_error: null,
      summary_es: merged.summary_es,
      summary_en: merged.summary_en,
    }).eq("id", chapter.id);

    await supabase.from("analysis_jobs").update({
      status: "done",
      kept_count: validated.kept.length,
      dropped_count: validated.dropped,
      finished_at: new Date().toISOString(),
      error: null,
    }).eq("chapter_id", chapter.id).eq("intensity", intensity);

    await refreshBook(supabase, book.id);
    return json({
      kept: validated.kept.length,
      dropped: validated.dropped,
      model: config.model,
    });
  } catch (error) {
    const message = await readError(error);
    if (failure) await fail(failure.supabase, "", failure.bookId, failure.chapterId, failure.intensity, message);
    return json({ error: message }, 500);
  }
});

async function fail(
  supabase: ReturnType<typeof userClient>,
  userId: string,
  bookId: string,
  chapterId: string,
  intensity: string,
  message: string,
) {
  if (!supabase) return;
  await supabase.from("chapters").update({ analysis_status: "failed", analysis_error: message }).eq("id", chapterId);
  await supabase.from("analysis_jobs").update({
    status: "failed",
    error: message,
    finished_at: new Date().toISOString(),
  }).eq("chapter_id", chapterId).eq("intensity", intensity);
  void userId;
  void bookId;
  await refreshBook(supabase, bookId);
}

async function refreshBook(supabase: NonNullable<ReturnType<typeof userClient>>, bookId: string) {
  const { data: chapters } = await supabase.from("chapters").select("analysis_status").eq("book_id", bookId);
  const rows = chapters ?? [];
  const total = rows.length || 1;
  const done = rows.filter((row) => row.analysis_status === "done").length;
  const failed = rows.filter((row) => row.analysis_status === "failed").length;
  const finished = done + failed;
  const status = done === rows.length && rows.length > 0
    ? "analyzed"
    : done > 0 && finished === rows.length
      ? "partial"
      : finished === rows.length && done === 0
        ? "error"
        : "analyzing";
  await supabase.from("books").update({
    status,
    analysis_progress: finished / total,
    status_detail: failed ? `${failed} capítulo${failed === 1 ? "" : "s"} con error` : null,
  }).eq("id", bookId);
}
