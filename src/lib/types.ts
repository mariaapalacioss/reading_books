export type BookLanguage = "es" | "en" | "unknown";
export type BookStatus = "extracting" | "needs_ocr" | "ready" | "analyzing" | "partial" | "analyzed" | "error";
export type Intensity = "essential" | "balanced" | "detailed";
export type ExplanationLanguage = "es" | "en";

export type Book = {
  id: string;
  user_id: string;
  title: string;
  author: string | null;
  language: BookLanguage;
  storage_path: string;
  page_count: number;
  status: BookStatus;
  status_detail: string | null;
  highlight_intensity: Intensity;
  analysis_progress: number;
  current_page: number;
  zoom: number;
  show_ai_highlights: boolean;
  explanation_language: ExplanationLanguage;
  last_read_at: string | null;
  created_at: string;
  updated_at: string;
};

export type Chapter = {
  id: string;
  book_id: string;
  position: number;
  title: string;
  start_page: number;
  end_page: number;
  source: "detected" | "user";
  analysis_status: "pending" | "queued" | "processing" | "done" | "failed";
  analysis_error: string | null;
  summary_es: string | null;
  summary_en: string | null;
};

export type Highlight = {
  id: string;
  book_id: string;
  chapter_id: string | null;
  page_number: number;
  quote: string;
  category: "idea" | "definicion" | "dato" | "conclusion" | "contexto" | "manual";
  explanation_es: string | null;
  explanation_en: string | null;
  origin: "ai" | "user";
  intensity: Intensity | null;
  reviewed: boolean;
  review_again: boolean;
  dismissed: boolean;
  note: string | null;
  rects: { x: number; y: number; w: number; h: number }[] | null;
};

export type ChapterPoint = {
  id: string;
  book_id: string;
  chapter_id: string;
  position: number;
  text_es: string;
  text_en: string;
  quote: string | null;
  page_number: number | null;
  printed_label: string | null;
  reviewed: boolean;
  review_again: boolean;
};

export type Bookmark = {
  id: string;
  book_id: string;
  page_number: number;
  label: string | null;
};

export type PageRow = {
  page_number: number;
  printed_label: string | null;
  text: string;
  items: { s: string; start: number; x: number; y: number; w: number; h: number }[];
};

export type StudyCard = {
  id: string;
  book_id: string;
  user_id: string;
  chapter_id: string | null;
  page_number: number | null;
  kind: "note" | "qa" | "summary" | "review" | "explain" | "capture";
  source: "chat" | "assist" | "capture";
  title: string;
  body: string;
  back: string | null;
  quote: string | null;
  preview_url: string | null;
  context_question: string | null;
  assist_mode: string | null;
  reviewed: boolean;
  review_again: boolean;
  created_at: string;
};

export type QuestionRow = {
  id: string;
  question: string;
  answer: string;
  sufficient: boolean;
  citations: { pdfPage: number; printedLabel: string | null; quote: string }[];
  language: ExplanationLanguage;
  created_at: string;
};

export const STATUS_LABEL: Record<BookStatus, string> = {
  extracting: "Extrayendo texto",
  needs_ocr: "Requiere OCR",
  ready: "Listo para analizar",
  analyzing: "Analizando",
  partial: "Análisis parcial",
  analyzed: "Analizado",
  error: "Error de análisis",
};

export const LANGUAGE_LABEL: Record<BookLanguage, string> = {
  es: "Español",
  en: "Inglés",
  unknown: "Idioma sin detectar",
};

export function pageLabel(pdfPage: number, printed?: string | null) {
  if (printed && printed !== String(pdfPage)) return `PDF ${pdfPage} · impresa ${printed}`;
  return `PDF ${pdfPage}`;
}
