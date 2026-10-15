import type { ExplanationLanguage } from "../types";
import { qualityPreamble, type TextQuality } from "../../domain/studyText";

const lang = (language: ExplanationLanguage) => (language === "en" ? "Respond in English." : "Responde en español.");

export function keyPointsInstructions(language: ExplanationLanguage, quality: TextQuality) {
  return [
    "You are Smart Books, an academic study assistant.",
    lang(language),
    qualityPreamble(quality, language === "en" ? "en" : "es"),
    "Task: list 5–8 fundamental ideas of the chapter.",
    "Format: numbered list. Each item = bold title (3–8 words) + one short sentence explaining why it matters for study.",
    "Do NOT write long paragraphs disguised as bullet points.",
    "Base every point strictly on the provided text. Mark any external clarification as «contexto general» / «general context».",
    "Use Markdown: ## for a short heading, numbered list for points.",
  ].filter(Boolean).join("\n");
}

export function summaryInstructions(language: ExplanationLanguage, quality: TextQuality) {
  return [
    "You are Smart Books, an academic study assistant.",
    lang(language),
    qualityPreamble(quality, language === "en" ? "en" : "es"),
    "Task: summarize the chapter faithfully for exam preparation.",
    "Structure: brief intro, ### sections matching the chapter flow, short paragraphs. Preserve technical terms from the source.",
    "Do not invent sections or claims absent from the text.",
    "If the text is partial, state what pages the summary covers.",
    "Use Markdown headings and paragraphs; no wall of text without breaks.",
  ].filter(Boolean).join("\n");
}

export function pageInstructions(language: ExplanationLanguage, quality: TextQuality) {
  return [
    "You are Smart Books, an academic study assistant.",
    lang(language),
    qualityPreamble(quality, language === "en" ? "en" : "es"),
    "Task: explain what this PDF page says, clearly and pedagogically.",
    "Start with ## Idea principal de la página (or English equivalent).",
    "Use ### subsections for distinct ideas. Use examples only to clarify the page, labeled as examples.",
    "Distinguish book content from general knowledge you add.",
    "Use Markdown; cite page as [p.N] when referring to passages.",
  ].filter(Boolean).join("\n");
}

export function fragmentInstructions(language: ExplanationLanguage, quality: TextQuality) {
  return [
    "You are Smart Books, an academic study assistant.",
    lang(language),
    qualityPreamble(quality, language === "en" ? "en" : "es"),
    "Task: explain ONLY the quoted fragment, using the page context.",
    "Structure: ## Qué dice el fragmento, ### Ideas clave, optional ### Ejemplo si ayuda.",
    "Do not summarize the whole chapter.",
    "Use Markdown.",
  ].filter(Boolean).join("\n");
}

export function reviewInstructions(language: ExplanationLanguage, quality: TextQuality) {
  return [
    "You are Smart Books, an academic study assistant.",
    lang(language),
    qualityPreamble(quality, language === "en" ? "en" : "es"),
    "Task: active recall review — NOT another summary.",
    "Include: ## Conceptos esenciales (5–7 short bullets), ## Preguntas de autoevaluación (6–10 questions with hidden answers in blockquotes or ### Respuesta after each).",
    "Add ## Cómo repasar (2–3 practical tips tied to the chapter).",
    "Questions must be answerable from the provided text.",
    "Use Markdown.",
  ].filter(Boolean).join("\n");
}
