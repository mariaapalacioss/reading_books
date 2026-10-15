import { buildChunks } from "../domain/chunks";
import { extractPdf } from "./pdf";
import { requireSupabase } from "./supabase";
import type { BookLanguage, Intensity } from "./types";

export type IngestDraft = {
  file: File;
  title: string;
  author: string;
  language: BookLanguage;
  intensity: Intensity;
  pageCount: number;
  needsOcr: boolean;
  extracted: Awaited<ReturnType<typeof extractPdf>>;
};

export async function preparePdf(file: File, onProgress: (message: string) => void): Promise<IngestDraft> {
  if (file.type && file.type !== "application/pdf") {
    throw new Error("El archivo tiene que ser un PDF.");
  }
  onProgress("Abriendo el PDF…");
  const buffer = await file.arrayBuffer();
  const extracted = await extractPdf(buffer, (page, total) => {
    onProgress(`Extrayendo texto, página ${page} de ${total}`);
  });
  return {
    file,
    title: extracted.title,
    author: extracted.author,
    language: extracted.language,
    intensity: "balanced",
    pageCount: extracted.pageCount,
    needsOcr: extracted.needsOcr,
    extracted,
  };
}

export async function saveBook(draft: IngestDraft, onProgress: (message: string) => void) {
  const supabase = requireSupabase();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) throw new Error("Inicia sesión para guardar el libro.");
  const user = userData.user;
  const bookId = crypto.randomUUID();
  const storagePath = `${user.id}/${bookId}.pdf`;
  onProgress("Guardando el PDF original…");
  const { error: uploadError } = await supabase.storage.from("books").upload(storagePath, draft.file, {
    contentType: "application/pdf",
    upsert: false,
  });
  if (uploadError) throw uploadError;

  const status = draft.needsOcr ? "needs_ocr" : "extracting";
  const { error: bookError } = await supabase.from("books").insert({
    id: bookId,
    user_id: user.id,
    title: draft.title.trim() || "Libro sin título",
    author: draft.author.trim() || null,
    language: draft.language,
    storage_path: storagePath,
    page_count: draft.pageCount,
    status,
    highlight_intensity: draft.intensity,
    status_detail: draft.needsOcr
      ? "El PDF parece escaneado. Falta un OCR para extraer el texto."
      : null,
  });
  if (bookError) throw bookError;

  onProgress("Guardando páginas y referencias…");
  const pages = draft.extracted.pages;
  for (let index = 0; index < pages.length; index += 12) {
    const slice = pages.slice(index, index + 12).map((page) => ({
      book_id: bookId,
      user_id: user.id,
      page_number: page.page,
      printed_label: page.printedLabel,
      text: page.text,
      items: page.items,
      char_count: page.charCount,
    }));
    const { error } = await supabase.from("book_pages").insert(slice);
    if (error) throw error;
  }

  const { error: chapterError } = await supabase.from("chapters").insert(
    draft.extracted.chapters.map((chapter, index) => ({
      book_id: bookId,
      user_id: user.id,
      position: index + 1,
      title: chapter.title,
      start_page: chapter.startPage,
      end_page: chapter.endPage,
      source: chapter.source,
      analysis_status: "pending",
    })),
  );
  if (chapterError) throw chapterError;

  const chunks = buildChunks(pages.map((page) => ({ page: page.page, text: page.text })));
  for (let index = 0; index < chunks.length; index += 40) {
    const slice = chunks.slice(index, index + 40).map((chunk) => ({
      book_id: bookId,
      user_id: user.id,
      page_start: chunk.pageStart,
      page_end: chunk.pageEnd,
      content: chunk.content,
    }));
    if (!slice.length) continue;
    const { error } = await supabase.from("search_chunks").insert(slice);
    if (error) throw error;
  }

  await supabase.from("books").update({
    status: draft.needsOcr ? "needs_ocr" : "ready",
  }).eq("id", bookId);

  return bookId;
}
