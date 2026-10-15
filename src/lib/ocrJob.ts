import { detectChapters } from "../domain/chapters";
import { detectLanguage } from "../domain/language";
import { documentNeedsOcr, isSparsePage } from "../domain/ocrLayout";
import { analyzeReadyChapters } from "./analysis";
import {
  getBook,
  listChapters,
  rebuildSearchIndex,
  appendSearchChunksForPages,
  updateBook,
  upsertBookPages,
} from "./books";
import { createOcrSession, type OcrSession } from "./ocr";
import { extractPdf } from "./pdf";
import { loadPdfBytes } from "./pdfLoad";
import { requireSupabase } from "./supabase";
import type { Book } from "./types";

export type OcrEvent = {
  bookId: string;
  message: string;
  done: number;
  total: number;
  error?: string;
};

const listeners = new Set<(event: OcrEvent) => void>();
const running = new Map<string, Promise<void>>();
const cancel = new Map<string, boolean>();
const priorityPages = new Map<string, Set<number>>();

export const OCR_BATCH_SIZE = 6;

export function prioritizeOcrPages(bookId: string, pages: number[]) {
  const set = priorityPages.get(bookId) ?? new Set<number>();
  for (const page of pages) {
    if (page >= 1) set.add(page);
  }
  priorityPages.set(bookId, set);
}

function orderOcrTargets(bookId: string, targets: number[]) {
  const priority = priorityPages.get(bookId);
  return [...targets].sort((left, right) => {
    const leftP = priority?.has(left) ? 0 : 1;
    const rightP = priority?.has(right) ? 0 : 1;
    if (leftP !== rightP) return leftP - rightP;
    return left - right;
  });
}

export function subscribeOcr(listener: (event: OcrEvent) => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function emit(event: OcrEvent) {
  listeners.forEach((listener) => listener(event));
}

export function cancelOcr(bookId: string) {
  cancel.set(bookId, true);
}

export function ocrIsRunning(bookId: string) {
  return running.has(bookId);
}

export function ensureOcr(book: Book) {
  if (book.status !== "extracting" && book.status !== "needs_ocr") return Promise.resolve();
  const current = running.get(book.id);
  if (current) return current;
  cancel.set(book.id, false);
  const job = run(book).finally(() => running.delete(book.id));
  running.set(book.id, job);
  return job;
}

export function resumeBackgroundOcr(books: Book[]) {
  for (const book of books) {
    if (book.status === "extracting" || book.status === "needs_ocr") void ensureOcr(book);
  }
}

async function run(book: Book) {
  const fresh = (await getBook(book.id)) ?? book;
  if (fresh.status === "needs_ocr") {
    await updateBook(fresh.id, { status: "extracting", status_detail: "Reanudando lectura…" });
  }
  emit({ bookId: fresh.id, message: "Abriendo el PDF…", done: 0, total: fresh.page_count });

  const data = await loadPdfBytes(fresh.storage_path);

  let targets: number[] = [];
  const supabase = requireSupabase();
  const { data: existing } = await supabase
    .from("book_pages")
    .select("page_number, char_count")
    .eq("book_id", fresh.id)
    .order("page_number");
  if (existing?.length) {
    targets = existing.filter((row) => isSparsePage(row.char_count ?? 0)).map((row) => row.page_number);
  } else {
    const extracted = await extractPdf(data);
    targets = extracted.pages.filter((page) => isSparsePage(page.charCount)).map((page) => page.page);
  }
  targets = orderOcrTargets(fresh.id, targets);
  if (!targets.length) {
    await updateBook(fresh.id, { status: "ready", status_detail: null });
    void analyzeReadyChapters(fresh);
    return;
  }

  emit({
    bookId: fresh.id,
    message: "Descargando reconocimiento (español e inglés)…",
    done: 0,
    total: targets.length,
  });

  let session: OcrSession | null = null;
  let done = 0;

  try {
    session = await createOcrSession(data);
    for (let index = 0; index < targets.length; index += OCR_BATCH_SIZE) {
      if (cancel.get(fresh.id)) throw new Error("Lectura cancelada.");
      const batch = targets.slice(index, index + OCR_BATCH_SIZE);
      const pages = await session.recognize(batch);
      await upsertBookPages(fresh, pages);
      await appendSearchChunksForPages(fresh, pages.map((item) => item.page));
      done += batch.length;
      const progress = done / targets.length;
      await updateBook(fresh.id, {
        analysis_progress: progress,
        status_detail: `Leyendo texto: ${done}/${targets.length} páginas`,
      });
      emit({
        bookId: fresh.id,
        message: `Leyendo página ${batch[batch.length - 1]} de ${fresh.page_count}`,
        done,
        total: targets.length,
      });
      const updated = (await getBook(fresh.id)) ?? fresh;
      void analyzeReadyChapters(updated);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "No se pudo leer el PDF.";
    emit({ bookId: fresh.id, message, done, total: targets.length, error: message });
    if (message === "Lectura cancelada.") return;
    await updateBook(fresh.id, { status: "needs_ocr", status_detail: message });
    return;
  } finally {
    await session?.close();
  }

  const { data: allPages } = await supabase
    .from("book_pages")
    .select("page_number, char_count, text")
    .eq("book_id", fresh.id)
    .order("page_number");
  const pageRows = allPages ?? [];
  const stillSparse = pageRows.filter((row) => isSparsePage(row.char_count ?? 0)).length;
  const needsOcr = documentNeedsOcr(pageRows.map((row) => ({ charCount: row.char_count ?? 0 })));
  if (needsOcr) {
    await updateBook(fresh.id, {
      status: "needs_ocr",
      status_detail: "El reconocimiento no pudo leer suficiente texto en este PDF.",
      analysis_progress: 1 - stillSparse / Math.max(pageRows.length, 1),
    });
    emit({ bookId: fresh.id, message: "Lectura terminada con pocas páginas útiles.", done: targets.length, total: targets.length });
    return;
  }

  await maybeRefreshChapters(fresh, pageRows.map((row) => row.text ?? ""));
  await rebuildSearchIndex(fresh);
  const sample = pageRows.filter((row) => !isSparsePage(row.char_count ?? 0)).slice(0, 12).map((row) => row.text).join("\n");
  const language = detectLanguage(sample);
  await updateBook(fresh.id, {
    status: "ready",
    status_detail: null,
    analysis_progress: 0,
    language: fresh.language === "unknown" && language !== "unknown" ? language : fresh.language,
  });
  emit({ bookId: fresh.id, message: "Texto leído. Indexando y analizando capítulos listos…", done: targets.length, total: targets.length });
  const updated = (await getBook(fresh.id)) ?? fresh;
  void analyzeReadyChapters(updated);
}

async function maybeRefreshChapters(book: Book, pageTexts: string[]) {
  const chapters = await listChapters(book.id);
  const fallbackOnly = chapters.length <= 1 && (chapters[0]?.title === "Documento completo" || !chapters.length);
  if (!fallbackOnly) return;
  const detected = detectChapters({
    pageCount: book.page_count,
    outline: [],
    pageTexts,
  });
  if (detected.length <= 1) return;
  const supabase = requireSupabase();
  await supabase.from("chapters").delete().eq("book_id", book.id);
  await supabase.from("chapters").insert(detected.map((chapter, position) => ({
    book_id: book.id,
    user_id: book.user_id,
    position: position + 1,
    title: chapter.title,
    start_page: chapter.startPage,
    end_page: chapter.endPage,
    source: chapter.source,
    analysis_status: "pending",
  })));
}
