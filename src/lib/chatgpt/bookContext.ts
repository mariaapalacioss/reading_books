import { normalizeStudyText } from "../../domain/studyText";
import { requireSupabase } from "../supabase";

export type BookPassage = {
  pdfPage: number;
  printedLabel: string | null;
  text: string;
};

export async function retrieveBookPassages(bookId: string, question: string, limit = 8) {
  const supabase = requireSupabase();
  const passages: BookPassage[] = [];
  const seen = new Set<string>();

  const push = (passage: BookPassage) => {
    const key = `${passage.pdfPage}:${passage.text.slice(0, 80)}`;
    if (seen.has(key)) return;
    seen.add(key);
    passages.push(passage);
  };

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
      const normalized = normalizeStudyText(page.text ?? "");
      const at = normalized.toLowerCase().indexOf(safe);
      const start = Math.max(0, at - 280);
      push({
        pdfPage: page.page_number,
        printedLabel: page.printed_label,
        text: normalized.slice(start, start + 900),
      });
    }
  }

  if (!passages.length) {
    const { data } = await supabase
      .from("book_pages")
      .select("page_number, printed_label, text, char_count")
      .eq("book_id", bookId)
      .gt("char_count", 40)
      .order("page_number")
      .limit(6);
    for (const page of data ?? []) {
      push({
        pdfPage: page.page_number,
        printedLabel: page.printed_label,
        text: normalizeStudyText(page.text ?? "").slice(0, 900),
      });
    }
  }

  return passages.slice(0, limit);
}

export type PackedChapter = {
  packed: string;
  partial: boolean;
  readableCount: number;
  expected: number;
  qualityNote: string;
};

export async function packChapterText(bookId: string, startPage: number, endPage: number): Promise<PackedChapter> {
  const supabase = requireSupabase();
  const { data: pages } = await supabase
    .from("book_pages")
    .select("page_number, text")
    .eq("book_id", bookId)
    .gte("page_number", startPage)
    .lte("page_number", endPage)
    .order("page_number");
  const readable = (pages ?? [])
    .map((page) => ({
      page_number: page.page_number,
      text: normalizeStudyText(page.text ?? ""),
    }))
    .filter((page) => page.text.length > 40);
  const expected = endPage - startPage + 1;
  const partial = readable.length < expected;
  const packed = readable
    .map((page) => `[p.${page.page_number}]\n${page.text}`)
    .join("\n\n")
    .slice(0, 18000);
  const qualityNote = partial
    ? `Solo ${readable.length}/${expected} páginas del capítulo tienen texto legible. No presentes el capítulo como completo.`
    : "";
  return { packed, partial, readableCount: readable.length, expected, qualityNote };
}

export async function packPageText(bookId: string, pageNumber: number) {
  const supabase = requireSupabase();
  const { data: page } = await supabase
    .from("book_pages")
    .select("text, printed_label, char_count")
    .eq("book_id", bookId)
    .eq("page_number", pageNumber)
    .maybeSingle();
  const text = normalizeStudyText(page?.text ?? "");
  return {
    text,
    printedLabel: page?.printed_label ?? null,
    charCount: page?.char_count ?? text.length,
  };
}
