import type { HighlightIntensity } from "./intensity.ts";
import { INTENSITY_LIMITS } from "./intensity.ts";

export const analysisSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary_es: { type: "string" },
    summary_en: { type: "string" },
    highlights: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          quote: { type: "string" },
          category: { type: "string", enum: ["idea", "definicion", "dato", "conclusion", "contexto"] },
          explanation_es: { type: "string" },
          explanation_en: { type: "string" },
        },
        required: ["quote", "category", "explanation_es", "explanation_en"],
      },
    },
    key_points: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          text_es: { type: "string" },
          text_en: { type: "string" },
          quote: { type: "string" },
        },
        required: ["text_es", "text_en", "quote"],
      },
    },
  },
  required: ["summary_es", "summary_en", "highlights", "key_points"],
} as const;

export const summarySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary_es: { type: "string" },
    summary_en: { type: "string" },
    partial: { type: "boolean" },
  },
  required: ["summary_es", "summary_en", "partial"],
} as const;

export const keyPointsSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    partial: { type: "boolean" },
    points_es: { type: "array", items: { type: "string" } },
    points_en: { type: "array", items: { type: "string" } },
  },
  required: ["partial", "points_es", "points_en"],
} as const;

export const pageHelpSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    partial: { type: "boolean" },
    explanation_es: { type: "string" },
    explanation_en: { type: "string" },
    sufficient: { type: "boolean" },
  },
  required: ["partial", "explanation_es", "explanation_en", "sufficient"],
} as const;

export const explainSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    explanation_es: { type: "string" },
    explanation_en: { type: "string" },
    sufficient: { type: "boolean" },
  },
  required: ["explanation_es", "explanation_en", "sufficient"],
} as const;

export const answerSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    sufficient: { type: "boolean" },
    answer: { type: "string" },
    citations: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          pdfPage: { type: "integer" },
          quote: { type: "string" },
        },
        required: ["pdfPage", "quote"],
      },
    },
  },
  required: ["sufficient", "answer", "citations"],
} as const;

export function analysisInstructions(intensity: HighlightIntensity): string {
  const limits = INTENSITY_LIMITS[intensity];
  return [
    "Eres el editor de Smart Books, una aplicación de lectura.",
    "Recibes el texto de un capítulo con marcadores [p.N], donde N es la página del PDF.",
    "El libro puede estar en español o en inglés. Conserva SIEMPRE las citas en el idioma original, copiadas de forma literal.",
    "No incluyas el marcador [p.N] dentro de la cita.",
    "Cada cita debe caber en una sola página y ser un fragmento continuo que exista tal cual en el texto.",
    "No marques párrafos enteros si basta una oración o una cláusula.",
    "Selecciona con criterio: ideas centrales, definiciones, datos o fórmulas, conclusiones y pasajes necesarios para entender el capítulo.",
    `Intensidad ${limits.label}: ${limits.hint} Devuelve como máximo ${limits.perWindow} resaltados en esta ventana.`,
    "La explicación breve dice por qué importa ese fragmento. explanation_es en español y explanation_en en inglés, cada una en menos de 280 caracteres.",
    "summary_es y summary_en resumen el capítulo en un párrafo. Si esta ventana no es el capítulo entero, resume solo lo que ves.",
    "key_points son afirmaciones de estudio, no copias largas. quote puede repetir un apoyo literal o ir vacío.",
    "No inventes citas, páginas ni datos que no estén en el texto.",
  ].join("\n");
}
