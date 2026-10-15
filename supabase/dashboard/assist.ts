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

export async function chatResponse(
  client: OpenAI,
  model: string,
  input: { role: "system" | "user" | "assistant"; content: string }[],
): Promise<string> {
  const response = await withRetries(() =>
    client.responses.create({ model, input }),
  );
  const text = response.output_text?.trim();
  if (!text) throw new Error("OpenAI no devolvió una respuesta.");
  return text;
}

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
    partial: { type: "boolean" },
  },
  required: ["summary_es", "summary_en", "partial"],
} as const;

export const keyPointsSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    partial: { type: "boolean" },
    points_es: { type: "array", items: { type: "string" } },
    points_en: { type: "array", items: { type: "string" } },
  },
  required: ["partial", "points_es", "points_en"],
} as const;

export const pageHelpSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    partial: { type: "boolean" },
    explanation_es: { type: "string" },
    explanation_en: { type: "string" },
    sufficient: { type: "boolean" },
  },
  required: ["partial", "explanation_es", "explanation_en", "sufficient"],
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


type Passage = {
  pdfPage: number;
  printedLabel: string | null;
  text: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return options();
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const supabase = userClient(req);
    if (!supabase) return json({ error: "Supabase no está configurado en la función." }, 500);
    const user = await requireUser(supabase);
    if (!user) return json({ error: "Sesión no válida." }, 401);

    const body = await req.json().catch(() => null) as {
      mode?: "explain" | "ask" | "summary" | "key_points" | "page" | "chat" | "ping";
      bookId?: string;
      chapterId?: string;
      quote?: string;
      question?: string;
      language?: "es" | "en";
      pageNumber?: number;
      messages?: { role: "user" | "assistant"; content: string }[];
    } | null;
    if (!body?.mode) return json({ error: "Faltan datos de la consulta." }, 400);

    const config = openAiConfig();
    if (body.mode === "ping") {
      if ("error" in config) return json({ ok: false, error: config.error });
      return json({ ok: true, model: config.model, embeddingModel: config.embeddingModel || null });
    }

    if (!body.bookId) return json({ error: "Falta el libro." }, 400);
    const language = body.language === "en" ? "en" : "es";

    if ("error" in config) return json({ error: config.error }, 503);
    const client = openAiClient(config.apiKey);

    if (body.mode === "chat") {
      const history = (body.messages ?? []).filter((item) => item.content?.trim());
      const lastUser = [...history].reverse().find((item) => item.role === "user");
      if (!lastUser?.content.trim()) return json({ error: "Escribe un mensaje." }, 400);
      const passages = await retrieve(supabase, body.bookId, lastUser.content, config.embeddingModel, client);
      const { data: bookRow } = await supabase.from("books").select("title").eq("id", body.bookId).maybeSingle();
      const packed = passages.map((passage) => (
        `[PDF p.${passage.pdfPage}]\n${passage.text}`
      )).join("\n\n");
      const system = [
        `Eres el tutor de lectura de Margen, amable y claro como ChatGPT, ayudando a un estudiante con el libro «${bookRow?.title ?? "sin título"}».`,
        language === "en" ? "Responde en inglés salvo que el estudiante pida otro idioma." : "Responde en español salvo que el estudiante pida otro idioma.",
        "Prioriza el texto del libro en los pasajes. Si citas algo, indica la página del PDF entre corchetes, p. ej. [p.12].",
        "Si el pasaje no alcanza, dilo con honestidad y ayuda con lo que sí está en el material o con razonamiento general marcándolo como fuera del libro.",
        packed ? `Pasajes del libro:\n${packed}` : "Todavía no hay pasajes indexados; responde con lo que el estudiante pregunte y sugiere esperar a que termine la lectura del PDF si hace falta citas.",
        body.pageNumber ? `El estudiante está en la página PDF ${body.pageNumber}.` : "",
      ].filter(Boolean).join("\n\n");
      const input = [
        { role: "system" as const, content: system },
        ...history.slice(-14).map((item) => ({ role: item.role, content: item.content })),
      ];
      const reply = await chatResponse(client, config.model, input);
      const citations = passages.slice(0, 4).map((passage) => ({
        pdfPage: passage.pdfPage,
        printedLabel: passage.printedLabel,
        quote: passage.text.slice(0, 160),
      }));
      return json({ reply, citations });
    }

    if (body.mode === "summary" || body.mode === "key_points") {
      if (!body.chapterId) return json({ error: "Falta el capítulo." }, 400);
      const { data: chapter } = await supabase
        .from("chapters")
        .select("id, title, start_page, end_page, summary_es, summary_en")
        .eq("id", body.chapterId)
        .eq("book_id", body.bookId)
        .maybeSingle();
      if (!chapter) return json({ error: "No se encontró el capítulo." }, 404);
      const packedInfo = await packChapterText(supabase, body.bookId, chapter.start_page, chapter.end_page);
      if (packedInfo.packed.trim().length < 40) {
        return json({ error: "Todavía no hay texto leído en este capítulo. Espera unos segundos o cambia de página para priorizar la lectura." }, 422);
      }
      if (body.mode === "summary") {
        if (!packedInfo.partial && (chapter.summary_es || chapter.summary_en)) {
          return json({
            summary: language === "en" ? chapter.summary_en || chapter.summary_es : chapter.summary_es || chapter.summary_en,
            cached: true,
            partial: false,
          });
        }
        const summary = await structuredResponse<{ summary_es: string; summary_en: string; partial: boolean }>(
          client,
          config.model,
          "chapter_summary",
          summarySchema as unknown as Record<string, unknown>,
          "Resume solo el texto recibido. summary_es en español y summary_en en inglés. partial=true si el texto no cubre todo el capítulo. No agregues datos externos.",
          `${packedInfo.header}\nCapítulo: ${chapter.title}\n\n${packedInfo.packed}`,
        );
        if (!packedInfo.partial) {
          await supabase.from("chapters").update({
            summary_es: summary.summary_es,
            summary_en: summary.summary_en,
          }).eq("id", chapter.id);
        }
        const text = language === "en" ? summary.summary_en : summary.summary_es;
        return json({
          summary: packedInfo.partial ? `${text}\n\n(Basado en ${packedInfo.readableCount} páginas ya leídas; el resto sigue procesándose.)` : text,
          cached: false,
          partial: packedInfo.partial,
        });
      }
      const points = await structuredResponse<{ partial: boolean; points_es: string[]; points_en: string[] }>(
        client,
        config.model,
        "chapter_key_points",
        keyPointsSchema as unknown as Record<string, unknown>,
        "Lista 5-8 ideas clave del texto recibido. points_es en español y points_en en inglés. partial=true si el texto no cubre todo el capítulo. No inventes.",
        `${packedInfo.header}\nCapítulo: ${chapter.title}\n\n${packedInfo.packed}`,
      );
      const list = (language === "en" ? points.points_en : points.points_es).map((item, index) => `${index + 1}. ${item}`).join("\n");
      return json({
        keyPoints: packedInfo.partial ? `${list}\n\n(Basado en ${packedInfo.readableCount} páginas ya leídas.)` : list,
        partial: packedInfo.partial,
      });
    }

    if (body.mode === "page") {
      const pageNumber = body.pageNumber ?? 1;
      const { data: page } = await supabase
        .from("book_pages")
        .select("page_number, text, printed_label")
        .eq("book_id", body.bookId)
        .eq("page_number", pageNumber)
        .maybeSingle();
      const text = page?.text?.trim() ?? "";
      if (text.length < 40) {
        return json({ error: "Esta página todavía no tiene texto. Margen la está leyendo; inténtalo de nuevo en unos segundos." }, 422);
      }
      const helped = await structuredResponse<{ partial: boolean; explanation_es: string; explanation_en: string; sufficient: boolean }>(
        client,
        config.model,
        "page_help",
        pageHelpSchema as unknown as Record<string, unknown>,
        "Explica las ideas principales de la página para un estudiante. explanation_es en español y explanation_en en inglés. Solo usa el texto recibido.",
        `PDF p.${pageNumber}${page?.printed_label ? ` · impresa ${page.printed_label}` : ""}\n\n${text.slice(0, 12000)}`,
      );
      const explanation = language === "en" ? helped.explanation_en : helped.explanation_es;
      return json({
        sufficient: helped.sufficient,
        explanation: helped.sufficient ? explanation : "No hay suficiente texto en esta página todavía.",
        pdfPage: pageNumber,
      });
    }

    if (body.mode === "explain") {
      const quote = body.quote?.trim() ?? "";
      if (quote.length < 8) return json({ error: "Selecciona un fragmento del libro." }, 400);
      const pageNumber = body.pageNumber ?? 1;
      const { data: pages } = await supabase
        .from("book_pages")
        .select("page_number, text, printed_label")
        .eq("book_id", body.bookId)
        .gte("page_number", Math.max(1, pageNumber - 1))
        .lte("page_number", pageNumber + 1)
        .order("page_number");
      const found = (pages ?? []).find((page) => locateQuote(page.text ?? "", quote));
      if (!found) {
        return json({
          sufficient: false,
          explanation: "No hay evidencia suficiente: ese fragmento no aparece de forma literal en las páginas cercanas.",
        });
      }
      const hit = locateQuote(found.text, quote)!;
      const context = snippetAround(found.text, hit.start, hit.end, 700);
      const explained = await structuredResponse<{ explanation_es: string; explanation_en: string; sufficient: boolean }>(
        client,
        config.model,
        "fragment_explanation",
        explainSchema as unknown as Record<string, unknown>,
        "Explica el fragmento usando solo el contexto. explanation_es en español y explanation_en en inglés. Si el contexto no alcanza, pon sufficient en false. No cites nada que no esté en el contexto.",
        `Página del PDF ${found.page_number}${found.printed_label ? ` · numeración impresa ${found.printed_label}` : ""}\nFragmento original:\n${quote}\n\nContexto:\n${context}`,
      );
      const explanation = language === "en" ? explained.explanation_en : explained.explanation_es;
      return json({
        sufficient: explained.sufficient,
        explanation: explained.sufficient ? explanation : "No hay evidencia suficiente en el pasaje para explicarlo con fidelidad.",
        pdfPage: found.page_number,
        printedLabel: found.printed_label,
      });
    }

    const question = body.question?.trim() ?? "";
    if (question.length < 3) return json({ error: "Escribe una pregunta." }, 400);
    const passages = await retrieve(supabase, body.bookId, question, config.embeddingModel, client);
    if (!passages.length) {
      const answer = "No hay evidencia suficiente en el libro para responder esa pregunta.";
      await supabase.from("questions").insert({
        book_id: body.bookId,
        user_id: user.id,
        question,
        answer,
        sufficient: false,
        citations: [],
        language,
      });
      return json({ sufficient: false, answer, citations: [] });
    }

    const packed = passages.map((passage) => (
      `[PDF p.${passage.pdfPage}${passage.printedLabel && passage.printedLabel !== String(passage.pdfPage) ? ` | impresa ${passage.printedLabel}` : ""}]\n${passage.text}`
    )).join("\n\n");
    const answered = await structuredResponse<{
      sufficient: boolean;
      answer: string;
      citations: { pdfPage: number; quote: string }[];
    }>(
      client,
      config.model,
      "book_answer",
      answerSchema as unknown as Record<string, unknown>,
      [
        "Responde solo con los pasajes recibidos.",
        language === "en" ? "Escribe la respuesta en inglés." : "Escribe la respuesta en español.",
        "Las citas deben copiar el idioma original del libro y existir de forma literal.",
        "pdfPage es la página del archivo PDF, no la numeración impresa.",
        "Si los pasajes no alcanzan, pon sufficient en false y dilo en la respuesta.",
        "No uses conocimiento externo.",
      ].join("\n"),
      `Pregunta:\n${question}\n\nPasajes:\n${packed}`,
    );

    const citations = [];
    for (const citation of answered.citations) {
      const { data: page } = await supabase
        .from("book_pages")
        .select("page_number, text, printed_label")
        .eq("book_id", body.bookId)
        .eq("page_number", citation.pdfPage)
        .maybeSingle();
      if (!page) continue;
      const hit = locateQuote(page.text ?? "", citation.quote ?? "");
      if (!hit) continue;
      citations.push({
        pdfPage: page.page_number,
        printedLabel: page.printed_label,
        quote: page.text.slice(hit.start, hit.end),
      });
    }

    const sufficient = answered.sufficient && citations.length > 0;
    const answer = sufficient
      ? answered.answer
      : "No hay evidencia suficiente en el libro para responder con una referencia literal.";
    await supabase.from("questions").insert({
      book_id: body.bookId,
      user_id: user.id,
      question,
      answer,
      sufficient,
      citations,
      language,
    });
    return json({ sufficient, answer, citations });
  } catch (error) {
    return json({ error: await readError(error) }, 500);
  }
});

async function retrieve(
  supabase: NonNullable<ReturnType<typeof userClient>>,
  bookId: string,
  question: string,
  embeddingModel: string,
  client: ReturnType<typeof openAiClient>,
): Promise<Passage[]> {
  const passages: Passage[] = [];
  const seen = new Set<string>();
  const push = (passage: Passage) => {
    const key = `${passage.pdfPage}:${passage.text.slice(0, 80)}`;
    if (seen.has(key)) return;
    seen.add(key);
    passages.push(passage);
  };

  if (embeddingModel) {
    try {
      const embedded = await client.embeddings.create({ model: embeddingModel, input: question });
      const vector = embedded.data[0]?.embedding;
      if (vector) {
        const { data } = await supabase.rpc("match_chunks", {
          query_embedding: `[${vector.join(",")}]`,
          target_book: bookId,
          match_count: 8,
        });
        for (const row of data ?? []) {
          const page = Number(row.page_start);
          push({
            pdfPage: page,
            printedLabel: null,
            text: String(row.content).slice(0, 1800),
          });
        }
      }
    } catch {
      // La búsqueda por palabras sigue disponible si el índice todavía no existe.
    }
  }

  const terms = question
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((term) => term.length > 3)
    .slice(0, 4);
  for (const term of terms) {
    const safe = term.replace(/[%_\\]/g, "");
    if (!safe) continue;
    const { data } = await supabase
      .from("book_pages")
      .select("page_number, printed_label, text")
      .eq("book_id", bookId)
      .ilike("text", `%${safe}%`)
      .limit(3);
    for (const page of data ?? []) {
      const at = page.text.toLowerCase().indexOf(safe);
      const start = Math.max(0, at - 280);
      push({
        pdfPage: page.page_number,
        printedLabel: page.printed_label,
        text: page.text.slice(start, start + 900),
      });
    }
  }

  return passages.slice(0, 8);
}

async function packChapterText(
  supabase: NonNullable<ReturnType<typeof userClient>>,
  bookId: string,
  startPage: number,
  endPage: number,
) {
  const { data: pages } = await supabase
    .from("book_pages")
    .select("page_number, text")
    .eq("book_id", bookId)
    .gte("page_number", startPage)
    .lte("page_number", endPage)
    .order("page_number");
  const readable = (pages ?? []).filter((page) => (page.text ?? "").trim().length > 40);
  const expected = endPage - startPage + 1;
  const partial = readable.length < expected;
  const packed = readable
    .map((page) => `[p.${page.page_number}]\n${page.text}`)
    .join("\n\n")
    .slice(0, 16000);
  const header = partial
    ? `Nota: solo hay texto leído en ${readable.length} de ${expected} páginas de este capítulo. Resume o lista ideas solo con lo recibido.`
    : "Nota: el texto cubre todo el capítulo recibido.";
  return { packed, partial, readableCount: readable.length, header };
}
