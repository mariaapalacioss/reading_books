import { analysisInstructions } from "../../domain/analysisSchema";
import { windowsForAnalysis } from "../../domain/chunks";
import type { HighlightIntensity } from "../../domain/intensity";
import { quoteHash } from "../../domain/quotes";
import { locateSupportQuote, validateHighlights, type PageRecord } from "../../domain/validate";
import { listChapters, updateBook } from "../books";
import { requireSupabase } from "../supabase";
import type { Book } from "../types";
import { completePlanJson } from "./planApi";

type AnalysisPayload = {
  summary_es: string;
  summary_en: string;
  highlights: { quote: string; category: string; explanation_es: string; explanation_en: string }[];
  key_points: { text_es: string; text_en: string; quote: string }[];
};

export async function analyzeChapterWithPlan(book: Book, chapterId: string) {
  const supabase = requireSupabase();
  const { data: auth } = await supabase.auth.getUser();
  const user = auth.user;
  if (!user) throw new Error("Sesión no válida.");

  const { data: chapter } = await supabase
    .from("chapters")
    .select("*")
    .eq("id", chapterId)
    .eq("book_id", book.id)
    .maybeSingle();
  if (!chapter) throw new Error("Capítulo no encontrado.");
  const intensity = book.highlight_intensity as HighlightIntensity;

  await supabase.from("chapters").update({ analysis_status: "processing", analysis_error: null }).eq("id", chapter.id);
  await supabase.from("analysis_jobs").upsert({
    book_id: book.id,
    chapter_id: chapter.id,
    user_id: user.id,
    intensity,
    status: "processing",
    started_at: new Date().toISOString(),
  }, { onConflict: "chapter_id,intensity" });

  const { data: pageRows } = await supabase
    .from("book_pages")
    .select("page_number, text, printed_label")
    .eq("book_id", book.id)
    .gte("page_number", chapter.start_page)
    .lte("page_number", chapter.end_page)
    .order("page_number");

  const pages: PageRecord[] = (pageRows ?? []).map((row) => ({
    page: row.page_number,
    text: row.text ?? "",
    printedLabel: row.printed_label,
  }));
  const usable = pages.filter((page) => page.text.trim().length > 40);
  if (!usable.length) throw new Error("Este capítulo aún no tiene texto leído.");

  const windows = windowsForAnalysis(usable.map((page) => ({ page: page.page, text: page.text })));
  const merged: AnalysisPayload = { summary_es: "", summary_en: "", highlights: [], key_points: [] };

  for (const window of windows) {
    const payload = await completePlanJson<AnalysisPayload>({
      instructions: analysisInstructions(intensity),
      user: `Capítulo: ${chapter.title}\nIdioma: ${book.language}\n\n${window.content}`,
    });
    merged.highlights.push(...(payload.highlights ?? []));
    merged.key_points.push(...(payload.key_points ?? []));
    if (!merged.summary_es) merged.summary_es = payload.summary_es ?? "";
    if (!merged.summary_en) merged.summary_en = payload.summary_en ?? "";
  }

  const validated = validateHighlights(pages, merged.highlights, intensity);
  await supabase.from("highlights").delete().eq("chapter_id", chapter.id).eq("intensity", intensity).eq("origin", "ai");
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
    await supabase.from("highlights").upsert(rows, { onConflict: "chapter_id,intensity,quote_hash", ignoreDuplicates: true });
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
  if (points.length) await supabase.from("chapter_points").insert(points);

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
  }).eq("chapter_id", chapter.id).eq("intensity", intensity);

  const chapters = await listChapters(book.id);
  const done = chapters.filter((item) => item.analysis_status === "done").length;
  await updateBook(book.id, {
    analysis_progress: done / Math.max(chapters.length, 1),
    status: book.status === "extracting" ? "extracting" : "partial",
  });
}
