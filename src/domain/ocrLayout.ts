import type { TextItem } from "./rects.ts";

export const SPARSE_PAGE_CHARS = 40;
export const SCANNED_PAGE_RATIO = 0.7;

export type OcrWord = {
  text: string;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
};

export function isSparsePage(charCount: number) {
  return charCount < SPARSE_PAGE_CHARS;
}

export function documentNeedsOcr(pages: { charCount: number }[]) {
  if (!pages.length) return false;
  const sparse = pages.filter((page) => isSparsePage(page.charCount)).length;
  return sparse / pages.length >= SCANNED_PAGE_RATIO;
}

export function layoutOcrWords(words: OcrWord[], width: number, height: number): { text: string; items: TextItem[] } {
  const usable = words
    .map((word) => ({ ...word, text: word.text.replace(/\s+/g, " ").trim() }))
    .filter((word) => word.text && width > 0 && height > 0 && word.x1 > word.x0 && word.y1 > word.y0)
    .sort((a, b) => a.y0 - b.y0 || a.x0 - b.x0);

  let text = "";
  const items: TextItem[] = [];
  let lineCenter = -1;
  let lineHeight = 0;

  for (const word of usable) {
    const heightPx = word.y1 - word.y0;
    const center = (word.y0 + word.y1) / 2;
    const sameLine = lineCenter >= 0 && Math.abs(center - lineCenter) <= Math.max(lineHeight, heightPx) * 0.6;
    if (text) text += sameLine ? " " : "\n";
    if (!sameLine) {
      lineCenter = center;
      lineHeight = heightPx;
    }
    const start = text.length;
    text += word.text;
    items.push({
      s: word.text,
      start,
      x: round(word.x0 / width),
      y: round(word.y0 / height),
      w: round((word.x1 - word.x0) / width),
      h: round(heightPx / height),
    });
  }

  return { text, items };
}

function round(value: number) {
  return Math.round(value * 10000) / 10000;
}
