const SPANISH = ["el", "la", "de", "que", "y", "en", "los", "del", "se", "las", "por", "un", "una", "con", "para", "es", "al", "como", "más", "una"];
const ENGLISH = ["the", "of", "and", "to", "in", "a", "is", "that", "for", "it", "on", "with", "as", "was", "at", "by", "an", "be", "this", "are"];

export type BookLanguage = "es" | "en" | "unknown";

export function detectLanguage(text: string): BookLanguage {
  const tokens = text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .split(/[^a-z]+/)
    .filter(Boolean);
  if (tokens.length < 20) return "unknown";

  const bag = new Map<string, number>();
  for (const token of tokens) bag.set(token, (bag.get(token) ?? 0) + 1);
  const score = (words: string[]) => words.reduce((sum, word) => sum + (bag.get(word) ?? 0), 0);
  const es = score(SPANISH.map((word) => word.normalize("NFD").replace(/\p{M}/gu, "")));
  const en = score(ENGLISH);
  if (es < 8 && en < 8) return "unknown";
  if (es >= en * 1.25) return "es";
  if (en >= es * 1.25) return "en";
  return "unknown";
}
