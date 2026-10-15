import {
  cardFromChatPair,
  cardsFromAssistContent,
  type ParsedStudyCard,
} from "../domain/studyCardsParse";
import { requireSupabase } from "./supabase";
import type { StudyCard } from "./types";

const MAX_PREVIEW = 120_000;

function trimPreview(url?: string | null) {
  if (!url) return null;
  if (url.length <= MAX_PREVIEW) return url;
  return null;
}

export async function listStudyCards(bookId: string) {
  const supabase = requireSupabase();
  const { data, error } = await supabase
    .from("study_cards")
    .select("*")
    .eq("book_id", bookId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as StudyCard[];
}

export async function insertStudyCards(input: {
  bookId: string;
  userId: string;
  chapterId?: string | null;
  pageNumber?: number | null;
  source: StudyCard["source"];
  assistMode?: string | null;
  contextQuestion?: string | null;
  quote?: string | null;
  previewUrl?: string | null;
  cards: ParsedStudyCard[];
}) {
  if (!input.cards.length) throw new Error("No hay contenido para guardar.");
  const supabase = requireSupabase();
  const rows = input.cards.map((card) => ({
    book_id: input.bookId,
    user_id: input.userId,
    chapter_id: input.chapterId ?? null,
    page_number: input.pageNumber ?? null,
    kind: card.kind,
    source: input.source,
    title: card.title.slice(0, 200),
    body: card.body,
    back: card.back ?? null,
    quote: input.quote?.slice(0, 2000) ?? null,
    preview_url: trimPreview(input.previewUrl),
    context_question: input.contextQuestion?.slice(0, 2000) ?? null,
    assist_mode: input.assistMode ?? null,
  }));
  const { data, error } = await supabase.from("study_cards").insert(rows).select("*");
  if (error) throw error;
  return (data ?? []) as StudyCard[];
}

export async function saveAssistAsStudyCards(input: {
  bookId: string;
  userId: string;
  chapterId?: string | null;
  pageNumber?: number | null;
  mode: string | null;
  markdown: string;
  quote?: string | null;
  previewUrl?: string | null;
}) {
  const cards = cardsFromAssistContent({
    mode: input.mode,
    markdown: input.markdown,
    quote: input.quote,
  });
  return insertStudyCards({
    bookId: input.bookId,
    userId: input.userId,
    chapterId: input.chapterId,
    pageNumber: input.pageNumber,
    source: "assist",
    assistMode: input.mode,
    quote: input.quote,
    previewUrl: input.previewUrl,
    cards,
  });
}

export async function saveChatAsStudyCard(input: {
  bookId: string;
  userId: string;
  chapterId?: string | null;
  pageNumber?: number | null;
  question: string;
  answer: string;
}) {
  const parsed = cardFromChatPair(input.question, input.answer);
  return insertStudyCards({
    bookId: input.bookId,
    userId: input.userId,
    chapterId: input.chapterId,
    pageNumber: input.pageNumber,
    source: "chat",
    contextQuestion: input.question,
    cards: [parsed],
  });
}

export async function patchStudyCard(id: string, patch: Partial<Pick<StudyCard, "reviewed" | "review_again">>) {
  const supabase = requireSupabase();
  const { error } = await supabase.from("study_cards").update(patch).eq("id", id);
  if (error) throw error;
}

export async function deleteStudyCard(id: string) {
  const supabase = requireSupabase();
  const { error } = await supabase.from("study_cards").delete().eq("id", id);
  if (error) throw error;
}
