import { analysisInstructions, analysisSchema, summarySchema } from "../../../src/domain/analysisSchema.ts";
import type { HighlightIntensity } from "../../../src/domain/intensity.ts";
import { windowsForAnalysis } from "../../../src/domain/chunks.ts";
import { quoteHash } from "../../../src/domain/quotes.ts";
import { locateSupportQuote, validateHighlights, type PageRecord } from "../../../src/domain/validate.ts";
import { requireUser, userClient } from "../_shared/auth.ts";
import { json, options, readError } from "../_shared/http.ts";
import { openAiClient, openAiConfig, structuredResponse } from "../_shared/openai.ts";

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
