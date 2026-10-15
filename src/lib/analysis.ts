import { invokeFunction } from "./api";
import { analyzeChapterWithPlan } from "./chatgpt/analyzeChapterPlan";
import { planAiReady } from "./chatgpt/status";
import { listChapters, updateBook } from "./books";
import { chapterHasAssistableText } from "./chapterText";
import { requireSupabase } from "./supabase";
import type { Book, Chapter } from "./types";

async function analyzeChapter(book: Book, chapter: Chapter) {
  if (await planAiReady()) {
    await analyzeChapterWithPlan(book, chapter.id);
    return;
  }
  const result = await invokeFunction<{ skipped?: boolean; reason?: string }>("analyze-chapter", {
    bookId: book.id,
    chapterId: chapter.id,
  });
  if (result.skipped && result.reason === "already_running") {
    await waitForChapter(chapter.id);
  }
}

export type AnalysisEvent = {
  bookId: string;
  message: string;
  done: number;
  total: number;
  error?: string;
};

const listeners = new Set<(event: AnalysisEvent) => void>();
const running = new Map<string, Promise<void>>();

export function subscribeAnalysis(listener: (event: AnalysisEvent) => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function emit(event: AnalysisEvent) {
  listeners.forEach((listener) => listener(event));
}

export function ensureAnalysis(book: Book) {
  if (book.status === "needs_ocr") return Promise.resolve();
  if (book.status === "extracting") return analyzeReadyChapters(book);
  const current = running.get(book.id);
  if (current) return current;
  const job = run(book).finally(() => running.delete(book.id));
  running.set(book.id, job);
  return job;
}

const analyzingReady = new Map<string, Promise<void>>();

/** Analiza capítulos cuyo texto ya está leído (útil mientras el OCR sigue en otras páginas). */
export function analyzeReadyChapters(book: Book) {
  const current = analyzingReady.get(book.id);
  if (current) return current;
  const job = runReadyChapters(book).finally(() => analyzingReady.delete(book.id));
  analyzingReady.set(book.id, job);
  return job;
}

export function analysisIsRunning(bookId: string) {
  return running.has(bookId);
}

async function run(book: Book) {
  const chapters = await listChapters(book.id);
  const pending = await pendingChapters(book, chapters);
  if (!pending.length) {
    emit({ bookId: book.id, message: "El análisis de esta intensidad ya está guardado.", done: chapters.length, total: chapters.length });
    return;
  }
  await updateBook(book.id, { status: "analyzing", analysis_progress: (chapters.length - pending.length) / chapters.length });
  void embedAll(book.id);
  let done = chapters.length - pending.length;
  for (const chapter of pending) {
    emit({
      bookId: book.id,
      message: `Analizando «${chapter.title}»`,
      done,
      total: chapters.length,
    });
    try {
      await analyzeChapter(book, chapter);
    } catch (error) {
      const message = error instanceof Error ? error.message : "No se pudo analizar el capítulo.";
      await requireSupabase().from("chapters").update({ analysis_status: "failed", analysis_error: message }).eq("id", chapter.id);
      emit({ bookId: book.id, message, done, total: chapters.length, error: message });
      if (/OPENAI_API_KEY|OPENAI_MODEL|secreto|ChatGPT Plus|Continuar con ChatGPT/i.test(message)) {
        await updateBook(book.id, { status: "error", status_detail: message });
        return;
      }
    }
    done += 1;
    emit({ bookId: book.id, message: `Capítulo listo: ${chapter.title}`, done, total: chapters.length });
  }
}

async function pendingChapters(book: Book, chapters: Chapter[]) {
  const supabase = requireSupabase();
  const { data, error } = await supabase
    .from("analysis_jobs")
    .select("chapter_id, status")
    .eq("book_id", book.id)
    .eq("intensity", book.highlight_intensity);
  if (error) throw error;
  const done = new Set((data ?? []).filter((job) => job.status === "done").map((job) => job.chapter_id));
  return chapters.filter((chapter) => !done.has(chapter.id));
}

async function waitForChapter(chapterId: string) {
  const supabase = requireSupabase();
  for (let attempt = 0; attempt < 40; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    const { data } = await supabase.from("chapters").select("analysis_status").eq("id", chapterId).maybeSingle();
    if (data?.analysis_status === "done" || data?.analysis_status === "failed") return;
  }
}

async function runReadyChapters(book: Book) {
  const chapters = await listChapters(book.id);
  const pending = await pendingChapters(book, chapters);
  const ready: Chapter[] = [];
  for (const chapter of pending) {
    if (await chapterHasAssistableText(book.id, chapter)) ready.push(chapter);
  }
  if (!ready.length) return;

  await updateBook(book.id, {
    status: book.status === "extracting" ? "extracting" : "analyzing",
  });
  void embedAll(book.id);

  let done = chapters.length - pending.length;
  for (const chapter of ready) {
    emit({
      bookId: book.id,
      message: `Analizando «${chapter.title}»`,
      done,
      total: chapters.length,
    });
    try {
      await analyzeChapter(book, chapter);
    } catch (error) {
      const message = error instanceof Error ? error.message : "No se pudo analizar el capítulo.";
      if (/texto extraíble|OCR|422|ChatGPT/i.test(message)) continue;
      await requireSupabase().from("chapters").update({ analysis_status: "failed", analysis_error: message }).eq("id", chapter.id);
      emit({ bookId: book.id, message, done, total: chapters.length, error: message });
      if (/OPENAI_API_KEY|OPENAI_MODEL|secreto|ChatGPT Plus|Continuar con ChatGPT/i.test(message)) {
        await updateBook(book.id, { status: "error", status_detail: message });
        return;
      }
    }
    done += 1;
    emit({ bookId: book.id, message: `Capítulo listo: ${chapter.title}`, done, total: chapters.length });
  }
}

async function embedAll(bookId: string) {
  if (await planAiReady()) return;
  try {
    for (let attempt = 0; attempt < 80; attempt += 1) {
      const result = await invokeFunction<{ remaining: number }>("embed-book", { bookId });
      if (!result.remaining) return;
    }
  } catch {
    // El índice semántico queda pendiente; la lectura y la búsqueda textual siguen disponibles.
  }
}
