import { isSparsePage } from "../domain/ocrLayout";
import { requireSupabase } from "./supabase";
import type { Chapter } from "./types";

export async function chapterHasReadableText(bookId: string, chapter: Chapter) {
  const supabase = requireSupabase();
  const { data, error } = await supabase
    .from("book_pages")
    .select("page_number, char_count")
    .eq("book_id", bookId)
    .gte("page_number", chapter.start_page)
    .lte("page_number", chapter.end_page);
  if (error) throw error;
  const expected = chapter.end_page - chapter.start_page + 1;
  if ((data ?? []).length < expected) return false;
  return (data ?? []).every((row) => !isSparsePage(row.char_count ?? 0));
}

/** Texto suficiente para resumir / preguntar mientras el OCR sigue en otras páginas. */
export async function chapterHasAssistableText(bookId: string, chapter: Chapter) {
  const supabase = requireSupabase();
  const { data, error } = await supabase
    .from("book_pages")
    .select("page_number, char_count")
    .eq("book_id", bookId)
    .gte("page_number", chapter.start_page)
    .lte("page_number", chapter.end_page)
    .order("page_number");
  if (error) throw error;
  const readable = (data ?? []).filter((row) => !isSparsePage(row.char_count ?? 0));
  const chars = readable.reduce((sum, row) => sum + (row.char_count ?? 0), 0);
  if (chars >= 2500) return true;
  if (readable.length >= 5) return true;
  const prefixEnd = Math.min(chapter.start_page + 7, chapter.end_page);
  const prefix = (data ?? []).filter((row) => row.page_number >= chapter.start_page && row.page_number <= prefixEnd);
  if (prefix.length >= prefixEnd - chapter.start_page + 1 && prefix.every((row) => !isSparsePage(row.char_count ?? 0))) {
    return true;
  }
  return false;
}
