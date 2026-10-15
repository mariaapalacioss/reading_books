/** Normaliza texto extraído (PDF/OCR) para estudio e IA sin inventar contenido. */
export function normalizeStudyText(raw: string): string {
  let text = raw.replace(/\u00ad/g, "");
  text = text.replace(/(\p{L})-\r?\n(\p{L})/gu, "$1$2");
  text = text.replace(/[ \t]+\n/g, "\n");
  text = text.replace(/\n{3,}/g, "\n\n");
  text = text.replace(/[ \t]{2,}/g, " ");
  return text.trim();
}

export type TextQuality = {
  reliable: boolean;
  score: number;
  issues: string[];
};

/** Heurística: OCR o extracción pobre → la IA debe ser cauta. */
export function assessTextQuality(text: string): TextQuality {
  const issues: string[] = [];
  const sample = text.trim();
  if (sample.length < 40) {
    return { reliable: false, score: 0, issues: ["Muy poco texto en la página."] };
  }
  const words = sample.split(/\s+/).filter(Boolean);
  if (!words.length) return { reliable: false, score: 0, issues: ["Sin palabras legibles."] };

  const oneChar = words.filter((w) => w.length === 1 && /\p{L}/u.test(w)).length;
  if (oneChar / words.length > 0.22) issues.push("Muchas palabras de una letra (posible OCR ruidoso).");

  const broken = words.filter((w) => w.length >= 2 && !/^[\p{L}\p{N}][\p{L}\p{N}'\-.,;:()/]*$/u.test(w)).length;
  if (broken / words.length > 0.18) issues.push("Símbolos o cortes irregulares frecuentes.");

  const letters = (sample.match(/\p{L}/gu) ?? []).length;
  const ratio = letters / Math.max(sample.length, 1);
  if (ratio < 0.45) issues.push("Proporción baja de letras respecto al total.");

  const lines = sample.split("\n");
  const shortLines = lines.filter((line) => line.trim().length > 0 && line.trim().length < 4).length;
  if (shortLines / Math.max(lines.length, 1) > 0.35) issues.push("Muchas líneas muy cortas (orden o columnas dudosos).");

  let score = 1;
  score -= Math.min(0.35, oneChar / words.length);
  score -= Math.min(0.25, broken / words.length);
  score -= ratio < 0.45 ? 0.2 : 0;
  score -= shortLines / Math.max(lines.length, 1) > 0.35 ? 0.15 : 0;
  score = Math.max(0, Math.min(1, score));

  return {
    reliable: score >= 0.62 && issues.length <= 1,
    score,
    issues,
  };
}

export function qualityPreamble(quality: TextQuality, language: "es" | "en"): string {
  if (quality.reliable) return "";
  const intro = language === "en"
    ? "The source text may contain OCR or layout errors. Be explicit about uncertainty; do not present guesses as facts from the book."
    : "El texto fuente puede tener errores de OCR o de maquetación. Señala la incertidumbre; no presentes suposiciones como hechos del libro.";
  const detail = quality.issues.length
    ? (language === "en" ? `Issues: ${quality.issues.join(" ")}` : `Problemas detectados: ${quality.issues.join(" ")}`)
    : "";
  return [intro, detail].filter(Boolean).join("\n");
}
