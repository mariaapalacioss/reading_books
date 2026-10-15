import type { HighlightIntensity } from "./intensity.ts";
import { INTENSITY_LIMITS } from "./intensity.ts";
import { locateQuote } from "./quotes.ts";

export type PageRecord = {
  page: number;
  text: string;
  printedLabel: string | null;
};

export type RawHighlight = {
  quote?: string;
  category?: string;
  explanation_es?: string;
  explanation_en?: string;
};

export type KeptHighlight = {
  quote: string;
  pageNumber: number;
  printedLabel: string | null;
  category: "idea" | "definicion" | "dato" | "conclusion" | "contexto";
  explanationEs: string;
  explanationEn: string;
};

const CATEGORY_SET = new Set(["idea", "definicion", "dato", "conclusion", "contexto"]);

export function validateHighlights(
  pages: PageRecord[],
  raw: RawHighlight[],
  intensity: HighlightIntensity,
): { kept: KeptHighlight[]; dropped: number } {
  const limit = INTENSITY_LIMITS[intensity].perChapter;
  const kept: KeptHighlight[] = [];
  const seen = new Set<string>();
  let dropped = 0;

  for (const item of raw) {
    if (kept.length >= limit) break;
    const quote = item.quote?.replace(/\s*\[p\.\d+\]\s*/g, " ").trim();
    const category = item.category ?? "";
    if (!quote || quote.length > 500 || !CATEGORY_SET.has(category)) {
      dropped += 1;
      continue;
    }

    const found = pages
      .map((page) => ({ page, hit: locateQuote(page.text, quote) }))
      .find((entry) => entry.hit);
    if (!found?.hit) {
      dropped += 1;
      continue;
    }

    const literal = found.page.text.slice(found.hit.start, found.hit.end);
    const key = `${found.page.page}:${literal}`;
    if (seen.has(key)) {
      dropped += 1;
      continue;
    }
    seen.add(key);
    kept.push({
      quote: literal,
      pageNumber: found.page.page,
      printedLabel: found.page.printedLabel,
      category: category as KeptHighlight["category"],
      explanationEs: (item.explanation_es || "").trim().slice(0, 500),
      explanationEn: (item.explanation_en || "").trim().slice(0, 500),
    });
  }

  return { kept, dropped };
}

export function locateSupportQuote(pages: PageRecord[], quote: string, hintedPage?: number) {
  const ordered = [...pages].sort((a, b) => {
    if (hintedPage && a.page === hintedPage) return -1;
    if (hintedPage && b.page === hintedPage) return 1;
    return a.page - b.page;
  });
  for (const page of ordered) {
    const hit = locateQuote(page.text, quote);
    if (hit) {
      return {
        pageNumber: page.page,
        printedLabel: page.printedLabel,
        quote: page.text.slice(hit.start, hit.end),
      };
    }
  }
  return null;
}
