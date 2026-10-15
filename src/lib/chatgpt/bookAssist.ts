import { assessTextQuality } from "../../domain/studyText";
import type { ExplanationLanguage } from "../types";
import { assistCacheKey, readAssistCache, runAssistOnce } from "./assistCache";
import {
  fragmentInstructions,
  keyPointsInstructions,
  pageInstructions,
  reviewInstructions,
  summaryInstructions,
} from "./assistPrompts";
import { packChapterText, packPageText, retrieveBookPassages } from "./bookContext";
import { streamPlanResponse } from "./planApi";
import { requireSupabase } from "../supabase";

export type AssistMode = "summary" | "key_points" | "explain" | "fragment_summary" | "page" | "review";

export async function chatAboutBook(input: {
  bookId: string;
  bookTitle: string;
  chapterTitle?: string;
  pageNumber: number;
  language: ExplanationLanguage;
  messages: { role: "user" | "assistant"; content: string }[];
  onDelta: (text: string) => void;
}) {
  const lastUser = [...input.messages].reverse().find((item) => item.role === "user");
  const question = lastUser?.content ?? "";
  const passages = await retrieveBookPassages(input.bookId, question);
  const packed = passages.map((item) => `[p.${item.pdfPage}]\n${item.text}`).join("\n\n");
  const instructions = [
    `Eres el tutor de Smart Books, claro y profundo como ChatGPT, ayudando con «${input.bookTitle}».`,
    input.language === "en" ? "Responde en inglés." : "Responde en español.",
    input.chapterTitle ? `Capítulo actual: ${input.chapterTitle}.` : "",
    `Página PDF actual: ${input.pageNumber}.`,
    "Prioriza los pasajes del libro. Cita páginas como [p.N]. Si falta texto OCR, dilo y ayuda con lo disponible.",
    packed ? `Pasajes:\n${packed}` : "Aún hay poco texto indexado; responde con lo que puedas y sugiere esperar la lectura OCR.",
  ].filter(Boolean).join("\n\n");

  await streamPlanResponse({
    instructions,
    input: input.messages.slice(-14).map((item) => ({
      role: item.role,
      content: item.content,
    })),
    onDelta: input.onDelta,
  });
  return passages.slice(0, 4).map((item) => ({
    pdfPage: item.pdfPage,
    printedLabel: item.printedLabel,
    quote: item.text.slice(0, 160),
  }));
}

async function streamAssist(input: {
  instructions: string;
  userContent: string;
  onDelta?: (text: string) => void;
}) {
  let text = "";
  await streamPlanResponse({
    instructions: input.instructions,
    input: [{ role: "user", content: input.userContent }],
    onDelta: (delta) => {
      text += delta;
      input.onDelta?.(delta);
    },
  });
  return text.trim();
}

async function loadChapter(chapterId: string) {
  const supabase = requireSupabase();
  const { data: chapter } = await supabase
    .from("chapters")
    .select("title, start_page, end_page")
    .eq("id", chapterId)
    .maybeSingle();
  if (!chapter) throw new Error("Capítulo no encontrado.");
  return chapter;
}

function partialFooter(partial: boolean, readable: number, expected: number, language: ExplanationLanguage) {
  if (!partial) return "";
  return language === "en"
    ? `\n\n---\n*Based on ${readable}/${expected} pages with readable text. More pages are still being processed.*`
    : `\n\n---\n*Basado en ${readable}/${expected} páginas con texto legible. Otras páginas siguen procesándose.*`;
}

export async function runBookAssist(input: {
  mode: AssistMode;
  bookId: string;
  chapterId?: string;
  pageNumber?: number;
  quote?: string;
  language: ExplanationLanguage;
  onDelta?: (text: string) => void;
  skipCache?: boolean;
}) {
  const cacheKey = assistCacheKey({
    mode: input.mode,
    bookId: input.bookId,
    chapterId: input.chapterId,
    pageNumber: input.pageNumber,
    quote: input.quote?.slice(0, 120),
    language: input.language,
  });

  if (!input.skipCache) {
    const hit = readAssistCache(cacheKey);
    if (hit && hit.length > 0) {
      input.onDelta?.(hit);
      return hit;
    }
  }

  const work = async () => {
    if (input.mode === "summary" || input.mode === "key_points" || input.mode === "review") {
      if (!input.chapterId) throw new Error("No hay capítulo en esta página.");
      const chapter = await loadChapter(input.chapterId);
      const packedInfo = await packChapterText(input.bookId, chapter.start_page, chapter.end_page);
      if (packedInfo.packed.trim().length < 40) {
        throw new Error("Todavía no hay texto leído en este capítulo. Espera unos segundos o cambia de página.");
      }
      const quality = assessTextQuality(packedInfo.packed);
      const prefix = [
        packedInfo.qualityNote,
        packedInfo.partial ? `Capítulo parcial: ${packedInfo.readableCount}/${packedInfo.expected} páginas.` : "",
      ].filter(Boolean).join("\n");

      const instructions = input.mode === "summary"
        ? summaryInstructions(input.language, quality)
        : input.mode === "key_points"
          ? keyPointsInstructions(input.language, quality)
          : reviewInstructions(input.language, quality);

      const body = `${prefix ? `${prefix}\n\n` : ""}Capítulo: ${chapter.title}\n\n${packedInfo.packed}`;
      const text = await streamAssist({ instructions, userContent: body, onDelta: input.onDelta });
      return text + partialFooter(packedInfo.partial, packedInfo.readableCount, packedInfo.expected, input.language);
    }

    if (input.mode === "page") {
      const pageNumber = input.pageNumber ?? 1;
      const page = await packPageText(input.bookId, pageNumber);
      if (page.text.length < 40) {
        throw new Error("Esta página todavía no tiene texto seleccionable. Usa «Leer texto de esta página» o espera el OCR.");
      }
      const quality = assessTextQuality(page.text);
      const instructions = pageInstructions(input.language, quality);
      const body = `PDF p.${pageNumber}${page.printedLabel ? ` · ${page.printedLabel}` : ""}\n\n${page.text.slice(0, 14000)}`;
      return streamAssist({ instructions, userContent: body, onDelta: input.onDelta });
    }

    if (input.mode === "explain" || input.mode === "fragment_summary") {
      const pageNumber = input.pageNumber ?? 1;
      const quote = input.quote?.trim() ?? "";
      if (quote.length < 12) throw new Error("Selecciona al menos unas palabras en el PDF.");
      const page = await packPageText(input.bookId, pageNumber);
      const quality = assessTextQuality(page.text || quote);
      const instructions = input.mode === "fragment_summary"
        ? [
          fragmentInstructions(input.language, quality),
          input.language === "en"
            ? "Summarize ONLY the selected fragment in 2–4 sentences."
            : "Resume SOLO el fragmento seleccionado en 2–4 frases.",
        ].join("\n")
        : fragmentInstructions(input.language, quality);
      const body = `Página PDF ${pageNumber}\nFragmento seleccionado:\n«${quote}»\n\nContexto de la página:\n${page.text.slice(0, 10000)}`;
      return streamAssist({ instructions, userContent: body, onDelta: input.onDelta });
    }

    throw new Error("Modo de asistencia desconocido.");
  };

  if (input.skipCache) return work();
  return runAssistOnce(cacheKey, work);
}

/** @deprecated use runBookAssist */
export async function summarizeChapterPlan(input: {
  bookId: string;
  chapterId: string;
  language: ExplanationLanguage;
}) {
  return runBookAssist({ mode: "summary", ...input });
}

export async function keyPointsChapterPlan(input: {
  bookId: string;
  chapterId: string;
  language: ExplanationLanguage;
  onDelta?: (text: string) => void;
}) {
  return runBookAssist({ mode: "key_points", ...input });
}

export async function explainPagePlan(input: {
  bookId: string;
  pageNumber: number;
  language: ExplanationLanguage;
  onDelta?: (text: string) => void;
}) {
  return runBookAssist({ mode: "page", ...input });
}

export async function explainFragmentPlan(input: {
  bookId: string;
  pageNumber: number;
  quote: string;
  language: ExplanationLanguage;
  onDelta?: (text: string) => void;
}) {
  return runBookAssist({ mode: "explain", ...input });
}

export async function reviewChapterPlan(input: {
  bookId: string;
  chapterId: string;
  language: ExplanationLanguage;
  onDelta?: (text: string) => void;
}) {
  return runBookAssist({ mode: "review", ...input });
}
