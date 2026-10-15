import { quoteHash } from "../domain/quotes";
import { buildChunks } from "../domain/chunks";
import type { ChapterDraft } from "../domain/chapters";
import { extractPdf, inspectPdf, type ExtractedPdf } from "./pdf";
import {
  isLocalPdfPath,
  isStorageSizeError,
  localPdfKeyFromPath,
  localPdfObjectUrl,
  maxCloudPdfBytes,
  putLocalPdf,
  deleteLocalPdf,
  LOCAL_PDF_PREFIX,
} from "./pdfLocal";
import { requireSupabase } from "./supabase";
import type { Book, Bookmark, Chapter, ChapterPoint, ExplanationLanguage, Highlight, Intensity, PageRow, QuestionRow } from "./types";

export async function listBooks() {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("books").select("*").order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Book[];
}

export async function getBook(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("books").select("*").eq("id", bookId).maybeSingle();
  if (error) throw error;
  return data as Book | null;
}

export async function signedPdfUrl(path: string) {
  if (isLocalPdfPath(path)) return localPdfObjectUrl(path);
  const supabase = requireSupabase();
  const { data, error } = await supabase.storage.from("books").createSignedUrl(path, 60 * 60);
  if (error || !data?.signedUrl) throw error ?? new Error("No se pudo abrir el PDF.");
  return data.signedUrl;
}

async function persistPdfFile(input: { userId: string; bookId: string; file: File; onProgress: (message: string) => void }) {
  const cloudKey = `${input.userId}/${input.bookId}.pdf`;
  const localKey = cloudKey;
  const localPath = `${LOCAL_PDF_PREFIX}${localKey}`;

  const storeLocally = async (message: string) => {
    input.onProgress(message);
    await putLocalPdf(localKey, input.file);
    return localPath;
  };

  if (input.file.size > maxCloudPdfBytes()) {
    return storeLocally("Guardando el PDF en este navegador (supera el límite de subida a la nube)…");
  }

  input.onProgress("Subiendo el PDF original…");
  const supabase = requireSupabase();
  const upload = await supabase.storage.from("books").upload(cloudKey, input.file, {
    contentType: "application/pdf",
    upsert: false,
  });
  if (!upload.error) return cloudKey;

  if (isStorageSizeError(upload.error)) {
    return storeLocally("La nube rechazó el tamaño; guardando el PDF en este navegador…");
  }
  throw upload.error;
}

export async function preparePdf(file: File, onProgress: (page: number, total: number) => void) {
  if (file.type && file.type !== "application/pdf") {
    throw new Error("Smart Books solo acepta archivos PDF.");
  }
  const data = await file.arrayBuffer();
  const inspected = await inspectPdf(data, onProgress);
  if (inspected) return inspected;
  return extractPdf(data, onProgress);
}

export async function saveBook(input: {
  file: File;
  userId: string;
  extracted: ExtractedPdf;
  title: string;
  author: string;
  language: Book["language"];
  intensity: Intensity;
  explanationLanguage: ExplanationLanguage;
  onProgress: (message: string) => void;
}) {
  const supabase = requireSupabase();
  const bookId = crypto.randomUUID();
  const storagePath = await persistPdfFile({
    userId: input.userId,
    bookId,
    file: input.file,
    onProgress: input.onProgress,
  });
  const storedLocally = isLocalPdfPath(storagePath);

  const status = input.extracted.needsOcr ? "extracting" : "ready";
  const { error: bookError } = await supabase.from("books").insert({
    id: bookId,
    user_id: input.userId,
    title: input.title.trim() || input.extracted.title,
    author: input.author.trim() || null,
    language: input.language,
    storage_path: storagePath,
    page_count: input.extracted.pageCount,
    status,
    status_detail: input.extracted.needsOcr
      ? storedLocally
        ? "Preparando lectura en segundo plano… PDF solo en este navegador."
        : "Preparando lectura en segundo plano…"
      : storedLocally
        ? "PDF guardado solo en este navegador (no en la nube)."
        : null,
    highlight_intensity: input.intensity,
    explanation_language: input.explanationLanguage,
  });
  if (bookError) throw bookError;

  input.onProgress("Guardando páginas y referencias…");
  for (let index = 0; index < input.extracted.pages.length; index += 15) {
    const slice = input.extracted.pages.slice(index, index + 15).map((page) => ({
      book_id: bookId,
      user_id: input.userId,
      page_number: page.page,
      printed_label: page.printedLabel,
      text: page.text,
      items: page.items,
      char_count: page.charCount,
    }));
    const { error } = await supabase.from("book_pages").insert(slice);
    if (error) throw error;
  }

  const chapters = input.extracted.chapters.length
    ? input.extracted.chapters
    : [{ title: "Documento completo", startPage: 1, endPage: input.extracted.pageCount, source: "detected" as const }];
  const { error: chapterError } = await supabase.from("chapters").insert(chapters.map((chapter, position) => ({
    book_id: bookId,
    user_id: input.userId,
    position: position + 1,
    title: chapter.title,
    start_page: chapter.startPage,
    end_page: chapter.endPage,
    source: chapter.source,
    analysis_status: "pending",
  })));
  if (chapterError) throw chapterError;

  const { data: savedChapters, error: loadError } = await supabase
    .from("chapters")
    .select("id, start_page, end_page")
    .eq("book_id", bookId)
    .order("position");
  if (loadError) throw loadError;

  if (!input.extracted.needsOcr) {
    const chunks = buildChunks(input.extracted.pages.map((page) => ({ page: page.page, text: page.text }))).map((chunk) => {
      const chapter = (savedChapters ?? []).find((item) => chunk.pageStart >= item.start_page && chunk.pageStart <= item.end_page);
      return {
        book_id: bookId,
        chapter_id: chapter?.id ?? null,
        user_id: input.userId,
        page_start: chunk.pageStart,
        page_end: chunk.pageEnd,
        content: chunk.content,
      };
    });
    for (let index = 0; index < chunks.length; index += 40) {
      const { error } = await supabase.from("search_chunks").insert(chunks.slice(index, index + 40));
      if (error) throw error;
    }
  }

  return bookId;
}

export async function upsertBookPages(book: Book, pages: ExtractedPdf["pages"]) {
  const supabase = requireSupabase();
  for (let index = 0; index < pages.length; index += 8) {
    const slice = pages.slice(index, index + 8);
    await Promise.all(slice.map(async (page) => {
      const { error } = await supabase.from("book_pages").upsert({
        book_id: book.id,
        user_id: book.user_id,
        page_number: page.page,
        printed_label: page.printedLabel,
        text: page.text,
        items: page.items,
        char_count: page.charCount,
      }, { onConflict: "book_id,page_number" });
      if (error) throw error;
    }));
  }
}

export async function rebuildSearchIndex(book: Book) {
  const supabase = requireSupabase();
  const { data: rows, error: pageError } = await supabase
    .from("book_pages")
    .select("page_number, text")
    .eq("book_id", book.id)
    .order("page_number");
  if (pageError) throw pageError;
  const { error: deleteError } = await supabase.from("search_chunks").delete().eq("book_id", book.id);
  if (deleteError) throw deleteError;
  const { data: chapters, error: chapterError } = await supabase
    .from("chapters")
    .select("id, start_page, end_page")
    .eq("book_id", book.id)
    .order("position");
  if (chapterError) throw chapterError;
  const chunks = buildChunks((rows ?? []).map((row) => ({ page: row.page_number, text: row.text ?? "" }))).map((chunk) => {
    const chapter = (chapters ?? []).find((item) => chunk.pageStart >= item.start_page && chunk.pageStart <= item.end_page);
    return {
      book_id: book.id,
      chapter_id: chapter?.id ?? null,
      user_id: book.user_id,
      page_start: chunk.pageStart,
      page_end: chunk.pageEnd,
      content: chunk.content,
    };
  });
  for (let index = 0; index < chunks.length; index += 40) {
    const slice = chunks.slice(index, index + 40);
    if (!slice.length) continue;
    const { error } = await supabase.from("search_chunks").insert(slice);
    if (error) throw error;
  }
}

export async function appendSearchChunksForPages(book: Book, pageNumbers: number[]) {
  if (!pageNumbers.length) return;
  const supabase = requireSupabase();
  const minPage = Math.min(...pageNumbers);
  const maxPage = Math.max(...pageNumbers);
  const { data: rows, error: pageError } = await supabase
    .from("book_pages")
    .select("page_number, text")
    .eq("book_id", book.id)
    .gte("page_number", Math.max(1, minPage - 2))
    .lte("page_number", maxPage + 2)
    .order("page_number");
  if (pageError) throw pageError;
  const { error: deleteError } = await supabase
    .from("search_chunks")
    .delete()
    .eq("book_id", book.id)
    .gte("page_start", minPage)
    .lte("page_end", maxPage);
  if (deleteError) throw deleteError;
  const { data: chapters, error: chapterError } = await supabase
    .from("chapters")
    .select("id, start_page, end_page")
    .eq("book_id", book.id)
    .order("position");
  if (chapterError) throw chapterError;
  const chunks = buildChunks((rows ?? []).map((row) => ({ page: row.page_number, text: row.text ?? "" })))
    .filter((chunk) => chunk.pageEnd >= minPage && chunk.pageStart <= maxPage)
    .map((chunk) => {
      const chapter = (chapters ?? []).find((item) => chunk.pageStart >= item.start_page && chunk.pageStart <= item.end_page);
      return {
        book_id: book.id,
        chapter_id: chapter?.id ?? null,
        user_id: book.user_id,
        page_start: chunk.pageStart,
        page_end: chunk.pageEnd,
        content: chunk.content,
      };
    });
  if (!chunks.length) return;
  const { error } = await supabase.from("search_chunks").insert(chunks);
  if (error) throw error;
}

export async function replaceExtractedText(book: Book, extracted: ExtractedPdf) {
  const supabase = requireSupabase();
  for (let index = 0; index < extracted.pages.length; index += 8) {
    const slice = extracted.pages.slice(index, index + 8);
    await Promise.all(slice.map(async (page) => {
      const { error } = await supabase.from("book_pages").upsert({
        book_id: book.id,
        user_id: book.user_id,
        page_number: page.page,
        printed_label: page.printedLabel,
        text: page.text,
        items: page.items,
        char_count: page.charCount,
      }, { onConflict: "book_id,page_number" });
      if (error) throw error;
    }));
  }

  const { error: deleteError } = await supabase.from("search_chunks").delete().eq("book_id", book.id);
  if (deleteError) throw deleteError;

  const { data: savedChapters, error: chapterError } = await supabase
    .from("chapters")
    .select("id, title, start_page, end_page")
    .eq("book_id", book.id)
    .order("position");
  if (chapterError) throw chapterError;

  let chapters = savedChapters ?? [];
  const fallbackOnly = chapters.length <= 1 && (chapters[0]?.title === "Documento completo" || chapters.length === 0);
  if (fallbackOnly && extracted.chapters.length > 1) {
    const { error: clearError } = await supabase.from("chapters").delete().eq("book_id", book.id);
    if (clearError) throw clearError;
    const { error: insertError } = await supabase.from("chapters").insert(extracted.chapters.map((chapter, position) => ({
      book_id: book.id,
      user_id: book.user_id,
      position: position + 1,
      title: chapter.title,
      start_page: chapter.startPage,
      end_page: chapter.endPage,
      source: chapter.source,
      analysis_status: "pending",
    })));
    if (insertError) throw insertError;
    const reloaded = await supabase.from("chapters").select("id, title, start_page, end_page").eq("book_id", book.id).order("position");
    if (reloaded.error) throw reloaded.error;
    chapters = reloaded.data ?? [];
  }

  const chunks = buildChunks(extracted.pages.map((page) => ({ page: page.page, text: page.text }))).map((chunk) => {
    const chapter = chapters.find((item) => chunk.pageStart >= item.start_page && chunk.pageStart <= item.end_page);
    return {
      book_id: book.id,
      chapter_id: chapter?.id ?? null,
      user_id: book.user_id,
      page_start: chunk.pageStart,
      page_end: chunk.pageEnd,
      content: chunk.content,
    };
  });
  for (let index = 0; index < chunks.length; index += 40) {
    const slice = chunks.slice(index, index + 40);
    if (!slice.length) continue;
    const { error } = await supabase.from("search_chunks").insert(slice);
    if (error) throw error;
  }

  await updateBook(book.id, {
    status: extracted.needsOcr ? "needs_ocr" : "ready",
    status_detail: extracted.needsOcr ? "El reconocimiento no pudo leer suficiente texto en este PDF." : null,
    language: book.language === "unknown" && extracted.language !== "unknown" ? extracted.language : book.language,
    analysis_progress: 0,
  });
}

export async function replaceChapters(bookId: string, userId: string, drafts: ChapterDraft[]) {
  const supabase = requireSupabase();
  const { error: deleteError } = await supabase.from("chapters").delete().eq("book_id", bookId);
  if (deleteError) throw deleteError;
  const { error } = await supabase.from("chapters").insert(drafts.map((chapter, position) => ({
    book_id: bookId,
    user_id: userId,
    position: position + 1,
    title: chapter.title,
    start_page: chapter.startPage,
    end_page: chapter.endPage,
    source: "user",
    analysis_status: "pending",
  })));
  if (error) throw error;
  await supabase.from("highlights").delete().eq("book_id", bookId).eq("origin", "ai");
  await supabase.from("chapter_points").delete().eq("book_id", bookId);
  await supabase.from("books").update({ status: "ready", analysis_progress: 0, status_detail: null }).eq("id", bookId);
}

export async function updateBook(bookId: string, patch: Partial<Book>) {
  const supabase = requireSupabase();
  const { error } = await supabase.from("books").update(patch).eq("id", bookId);
  if (error) throw error;
}

export async function deleteBook(book: Book) {
  const supabase = requireSupabase();
  if (isLocalPdfPath(book.storage_path)) {
    await deleteLocalPdf(localPdfKeyFromPath(book.storage_path));
  } else {
    await supabase.storage.from("books").remove([book.storage_path]);
  }
  const { error } = await supabase.from("books").delete().eq("id", book.id);
  if (error) throw error;
}

export async function listChapters(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("chapters").select("*").eq("book_id", bookId).order("position");
  if (error) throw error;
  return (data ?? []) as Chapter[];
}

export async function listHighlights(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("highlights").select("*").eq("book_id", bookId).order("page_number");
  if (error) throw error;
  return (data ?? []) as Highlight[];
}

export async function listPoints(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("chapter_points").select("*").eq("book_id", bookId).order("position");
  if (error) throw error;
  return (data ?? []) as ChapterPoint[];
}

export async function listBookmarks(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("bookmarks").select("*").eq("book_id", bookId).order("page_number");
  if (error) throw error;
  return (data ?? []) as Bookmark[];
}

export async function listQuestions(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("questions").select("*").eq("book_id", bookId).order("created_at", { ascending: false }).limit(8);
  if (error) throw error;
  return (data ?? []) as QuestionRow[];
}

export async function getPage(bookId: string, pageNumber: number) {
  const supabase = requireSupabase();
  const { data, error } = await supabase
    .from("book_pages")
    .select("page_number, printed_label, text, items")
    .eq("book_id", bookId)
    .eq("page_number", pageNumber)
    .maybeSingle();
  if (error) throw error;
  return data as PageRow | null;
}

export async function createManualHighlight(input: {
  bookId: string;
  userId: string;
  chapterId: string | null;
  pageNumber: number;
  quote: string;
  rects: Highlight["rects"];
}) {
  const supabase = requireSupabase();
  const { data, error } = await supabase.from("highlights").insert({
    book_id: input.bookId,
    user_id: input.userId,
    chapter_id: input.chapterId,
    page_number: input.pageNumber,
    quote: input.quote,
    quote_hash: await quoteHash(input.quote + crypto.randomUUID()),
    category: "manual",
    origin: "user",
    rects: input.rects,
  }).select("*").single();
  if (error) throw error;
  return data as Highlight;
}

export async function patchHighlight(id: string, patch: Partial<Highlight>) {
  const supabase = requireSupabase();
  const { error } = await supabase.from("highlights").update(patch).eq("id", id);
  if (error) throw error;
}

export async function patchPoint(id: string, patch: Partial<ChapterPoint>) {
  const supabase = requireSupabase();
  const { error } = await supabase.from("chapter_points").update(patch).eq("id", id);
  if (error) throw error;
}

export async function toggleBookmark(bookId: string, userId: string, pageNumber: number, exists: boolean) {
  const supabase = requireSupabase();
  if (exists) {
    const { error } = await supabase.from("bookmarks").delete().eq("book_id", bookId).eq("page_number", pageNumber);
    if (error) throw error;
    return;
  }
  const { error } = await supabase.from("bookmarks").insert({
    book_id: bookId,
    user_id: userId,
    page_number: pageNumber,
    label: `Página ${pageNumber}`,
  });
  if (error) throw error;
}
