import { sortByReadingOrder } from "./readingOrder";
import type { TextItem } from "./rects";

/** Agrupa palabras OCR en líneas para selección más continua en el visor. */
export function groupItemsIntoLineSpans(items: TextItem[]) {
  const ordered = sortByReadingOrder(items.filter((item) => item.s?.trim()));
  const lines: TextItem[][] = [];
  for (const item of ordered) {
    const line = lines.find((group) => Math.abs(group[0].y - item.y) < Math.max(item.h, group[0].h) * 0.65);
    if (line) line.push(item);
    else lines.push([item]);
  }
  return lines.map((line) => ({
    text: line.map((item) => item.s).join(" "),
    x: Math.min(...line.map((item) => item.x)),
    y: Math.min(...line.map((item) => item.y)),
    w: Math.max(...line.map((item) => item.x + item.w)) - Math.min(...line.map((item) => item.x)),
    h: Math.max(...line.map((item) => item.y + item.h)) - Math.min(...line.map((item) => item.y)),
  }));
}
