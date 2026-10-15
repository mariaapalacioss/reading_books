export type HighlightIntensity = "essential" | "balanced" | "detailed";

export const INTENSITY_LIMITS: Record<HighlightIntensity, { perWindow: number; perChapter: number; label: string; hint: string }> = {
  essential: {
    perWindow: 4,
    perChapter: 6,
    label: "Esencial",
    hint: "Solo las ideas sin las cuales el capítulo no se entiende.",
  },
  balanced: {
    perWindow: 7,
    perChapter: 12,
    label: "Equilibrado",
    hint: "Ideas, definiciones y conclusiones, sin marcar párrafos de más.",
  },
  detailed: {
    perWindow: 10,
    perChapter: 20,
    label: "Detallado",
    hint: "Incluye datos, fórmulas y matices necesarios, todavía con criterio.",
  },
};

export const CATEGORIES = ["idea", "definicion", "dato", "conclusion", "contexto", "manual"] as const;
export type HighlightCategory = (typeof CATEGORIES)[number];

export const CATEGORY_LABELS: Record<HighlightCategory, string> = {
  idea: "Idea central",
  definicion: "Definición",
  dato: "Dato o fórmula",
  conclusion: "Conclusión",
  contexto: "Contexto necesario",
  manual: "Resaltado propio",
};
