import { isSparsePage } from "../domain/ocrLayout";
import type { ExtractedPage } from "./pdf";
import { createOcrSession } from "./ocr";
import { loadPdfBytes } from "./pdfLoad";
import { upsertBookPages } from "./books";
import type { Book, PageRow } from "./types";
import { requireSupabase } from "./supabase";

const inflight = new Map<string, Promise<PageRow | null>>();

export async function ensurePageText(book: Book, pageNumber: number): Promise<PageRow | null> {
  const supabase = requireSupabase();
  const { data: row } = await supabase
    .from("book_pages")
    .select("page_number, printed_label, text, items, char_count")
    .eq("book_id", book.id)
    .eq("page_number", pageNumber)
    .maybeSingle();
  if (row && !isSparsePage(row.char_count ?? 0)) return row as PageRow;

  const key = `${book.id}:${pageNumber}`;
  const running = inflight.get(key);
  if (running) return running;

  const job = recognizePages(book, [pageNumber]).finally(() => inflight.delete(key));
  inflight.set(key, job);
  return job;
}

async function recognizePages(book: Book, pageNumbers: number[]): Promise<PageRow | null> {
  const data = await loadPdfBytes(book.storage_path);
  const session = await createOcrSession(data);
  try {
    const pages: ExtractedPage[] = await session.recognize(pageNumbers);
    await upsertBookPages(book, pages);
  } finally {
    await session.close();
  }
  const supabase = requireSupabase();
  const target = pageNumbers[pageNumbers.length - 1];
  const { data: row } = await supabase
    .from("book_pages")
    .select("page_number, printed_label, text, items, char_count")
    .eq("book_id", book.id)
    .eq("page_number", target)
    .maybeSingle();
  return row as PageRow | null;
}

export async function ensurePagesText(book: Book, pageNumbers: number[]) {
  const unique = [...new Set(pageNumbers.filter((page) => page >= 1 && page <= book.page_count))];
  const supabase = requireSupabase();
  const { data } = await supabase
    .from("book_pages")
    .select("page_number, char_count")
    .eq("book_id", book.id)
    .in("page_number", unique);
  const sparse = unique.filter((page) => {
    const row = (data ?? []).find((item) => item.page_number === page);
    return !row || isSparsePage(row.char_count ?? 0);
  });
  if (!sparse.length) return;
  const key = `${book.id}:${sparse.join(",")}`;
  if (inflight.has(key)) {
    await inflight.get(key);
    return;
  }
  const job = recognizePages(book, sparse).finally(() => inflight.delete(key));
  inflight.set(key, job);
  await job;
}
