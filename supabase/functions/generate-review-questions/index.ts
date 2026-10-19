/**
 * Autocontenida para deploy en Supabase Dashboard (sin ../_shared).
 * Mantener en sync con supabase/functions/_shared cuando cambie auth/http/openai.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import OpenAI from "npm:openai";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function options() {
  return new Response("ok", { headers: corsHeaders });
}

function readError(error: unknown) {
  if (error instanceof Error) return error.message;
  return "Error inesperado";
}

function userClient(req: Request): SupabaseClient | null {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  if (!url || !key || !authorization) return null;
  return createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function requireUser(supabase: SupabaseClient) {
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}

function openAiConfig(): { apiKey: string; model: string } | { error: string } {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL");
  if (!apiKey || !model) {
    return {
      error:
        "Falta configurar OPENAI_API_KEY y OPENAI_MODEL como secretos de la función.",
    };
  }
  return { apiKey, model };
}

function openAiClient(apiKey: string) {
  return new OpenAI({ apiKey });
}

async function withRetries<T>(work: () => Promise<T>, attempts = 3): Promise<T> {
  let last: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await work();
    } catch (error) {
      last = error;
      const status = typeof error === "object" && error && "status" in error
        ? Number(error.status)
        : 0;
      const retry = status === 429 || status >= 500 || status === 0;
      if (!retry || attempt === attempts - 1) throw error;
      await new Promise((resolve) => setTimeout(resolve, 400 * 2 ** attempt));
    }
  }
  throw last;
}

async function structuredResponse<T>(
  client: OpenAI,
  model: string,
  name: string,
  schema: Record<string, unknown>,
  instructions: string,
  content: string,
): Promise<T> {
  const response = await client.responses.create({
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
  });
  const text = response.output_text;
  if (!text) throw new Error("OpenAI no devolvió una respuesta estructurada.");
  return JSON.parse(text) as T;
}

type ReviewCard = { title: string; question: string; answer: string };

type ContentLanguage = "es" | "en";

function resolveContentLanguage(
  sourceText: string,
  metadataLanguage?: string,
  localeFallback: ContentLanguage = "es",
): ContentLanguage {
  const sample = sourceText.trim();
  if (sample.length >= 24) {
    const lower = sample.toLowerCase();
    const esStop = (lower.match(/\b(el|la|de|que|y|en|los|las|un|una|por|con|del|al|es|son|para|como)\b/g) ?? []).length;
    const enStop = (lower.match(/\b(the|and|of|to|in|that|is|for|with|on|are|was|be|this|may|can)\b/g) ?? []).length;
    const spanishMarkers = (sample.match(/[áéíóúñ¿¡]/g) ?? []).length;
    const spanishScore = esStop + spanishMarkers * 2;
    const englishScore = enStop;
    if (spanishScore >= englishScore + 2) return "es";
    if (englishScore >= spanishScore + 2) return "en";
  }
  const meta = (metadataLanguage ?? "").trim().toLowerCase();
  if (meta === "en" || meta === "english") return "en";
  if (meta === "es" || meta === "spanish" || meta === "español") return "es";
  return localeFallback;
}

type ResponsePayload = {
  cards: ReviewCard[];
};

/** OpenAI strict: every property must appear in `required`. Solo pedimos `cards`; el resto lo calcula el servidor. */
const schema = {
  type: "object",
  properties: {
    cards: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          question: { type: "string" },
          answer: { type: "string" },
        },
        required: ["title", "question", "answer"],
        additionalProperties: false,
      },
    },
  },
  required: ["cards"],
  additionalProperties: false,
} as const;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return options();
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const supabase = userClient(req);
    if (!supabase) return json({ error: "Supabase no configurado." }, 500);
    const user = await requireUser(supabase);
    if (!user) return json({ error: "Sesión no válida." }, 401);

    const body = await req.json().catch(() => null) as {
      source_text?: string;
      requested_count?: number;
      source_type?: string;
      book_id?: string;
      book_title?: string;
      chapter_id?: string | null;
      chapter_title?: string | null;
      page_number?: number | null;
      scope?: string;
      language?: "es" | "en";
      book_language?: string;
    } | null;

    const sourceText = body?.source_text?.trim() ?? "";
    const requested = Math.min(Math.max(body?.requested_count ?? 5, 1), 30);

    if (sourceText.length < 40) {
      return json({ error: "El texto fuente es demasiado corto para generar preguntas." }, 400);
    }
    if (!body?.book_id) return json({ error: "Falta book_id." }, 400);

    const config = openAiConfig();
    if ("error" in config) return json({ error: config.error }, 503);
    const client = openAiClient(config.apiKey);

    const lang = resolveContentLanguage(
      sourceText,
      body.book_language,
      body?.language === "en" ? "en" : "es",
    );
    const instructions = [
      lang === "en"
        ? "You create active-recall flashcards for medical/academic study. Output ONLY valid JSON matching the schema."
        : "Generas flashcards de recuerdo activo para estudio médico/académico. Devuelve SOLO JSON válido según el esquema.",
      "Respond in the same language as the SOURCE text.",
      "Do not translate the material.",
      "All titles, questions, and answers must use the source language.",
      "Rules:",
      "- One concept per question.",
      "- Questions must be specific to the supplied source text (no generic templates like 'what factors are mentioned here').",
      "- Every answer must be fully supported by the source; do not invent facts.",
      "- Answers: 1–3 concise sentences.",
      "- Titles: short semantic labels (3–8 words), NOT the book title.",
      `- Target up to ${requested} cards, but return FEWER if the source cannot support more unique non-repetitive questions.`,
      "- No duplicate or near-duplicate questions.",
      lang === "en"
        ? "- Prefer questions starting with What/How/Why/Which…"
        : "- Prefer questions starting with ¿Qué/Cuándo/Por qué/Cuáles/Cuál es la diferencia…",
    ].join("\n");

    const userContent = [
      `book_title: ${body.book_title ?? ""}`,
      `source_type: ${body.source_type ?? "unknown"}`,
      `scope: ${body.scope ?? "unknown"}`,
      body.chapter_title ? `chapter: ${body.chapter_title}` : "",
      body.page_number != null ? `page_number: ${body.page_number}` : "",
      `requested_count (target): ${requested}`,
      "",
      "SOURCE TEXT:",
      sourceText.slice(0, 12000),
    ].filter(Boolean).join("\n");

    const parsed = await withRetries(
      () =>
        structuredResponse<ResponsePayload>(
          client,
          config.model,
          "review_questions",
          schema,
          instructions,
          userContent,
        ),
      2,
    );

    const cards = (parsed.cards ?? []).filter(
      (c) => c.question?.trim().length >= 12 && c.answer?.trim().length >= 8,
    );

    const unique: ReviewCard[] = [];
    const seen = new Set<string>();
    for (const c of cards) {
      const key = c.question.trim().toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      unique.push({
        title: c.title.trim().slice(0, 200),
        question: c.question.trim(),
        answer: c.answer.trim(),
      });
      if (unique.length >= requested) break;
    }

    const generated = unique.length;
    const message =
      generated < requested
        ? lang === "en"
          ? `Only ${generated} useful questions could be generated from this content.`
          : `Solo se pudieron generar ${generated} preguntas útiles con este contenido.`
        : undefined;

    return json({ cards: unique, generated_count: generated, message });
  } catch (error) {
    return json({ error: readError(error) }, 500);
  }
});
