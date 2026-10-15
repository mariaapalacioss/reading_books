import { sortByReadingOrder } from "./readingOrder";
import type { NormRect, TextItem } from "./rects";

export function normRectFromPoints(
  x0: number,
  y0: number,
  x1: number,
  y1: number,
): NormRect {
  const x = Math.min(x0, x1);
  const y = Math.min(y0, y1);
  return {
    x,
    y,
    w: Math.max(Math.abs(x1 - x0), 0.002),
    h: Math.max(Math.abs(y1 - y0), 0.002),
  };
}

export function rectsOverlap(a: NormRect, b: NormRect) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

/** Centro del ítem dentro de la región (con margen). */
function itemInRegion(item: TextItem, region: NormRect) {
  const cx = item.x + item.w / 2;
  const cy = item.y + item.h / 2;
  const pad = 0.008;
  return cx >= region.x - pad && cx <= region.x + region.w + pad
    && cy >= region.y - pad && cy <= region.y + region.h + pad;
}

export function textFromRegion(items: TextItem[], region: NormRect, pageText = "") {
  const hits = sortByReadingOrder(items.filter((item) => item.s?.trim() && itemInRegion(item, region)));
  if (!hits.length) {
    return { quote: "", rects: [] as NormRect[], start: -1, end: -1 };
  }

  const start = Math.min(...hits.map((item) => item.start));
  const end = Math.max(...hits.map((item) => item.start + item.s.length));

  let quote = "";
  if (pageText && start >= 0 && end > start) {
    quote = pageText.slice(start, end).replace(/\s+/g, " ").trim();
  }
  if (quote.length < 8) {
    quote = hits.map((item) => item.s).join(" ").replace(/\s+/g, " ").trim();
  }

  const rects = mergeItemRects(hits);
  return { quote, rects, start, end };
}

function mergeItemRects(items: TextItem[]): NormRect[] {
  const lines: TextItem[][] = [];
  for (const item of items) {
    const line = lines.find((group) => Math.abs(group[0].y - item.y) < Math.max(item.h, group[0].h) * 0.65);
    if (line) line.push(item);
    else lines.push([item]);
  }
  return lines.map((line) => {
    const x = Math.min(...line.map((item) => item.x));
    const y = Math.min(...line.map((item) => item.y));
    const right = Math.max(...line.map((item) => item.x + item.w));
    const bottom = Math.max(...line.map((item) => item.y + item.h));
    return { x, y, w: right - x, h: bottom - y };
  });
}

export function cropCanvasToDataUrl(canvas: HTMLCanvasElement, region: NormRect) {
  const w = canvas.width;
  const h = canvas.height;
  const sx = Math.max(0, Math.floor(region.x * w));
  const sy = Math.max(0, Math.floor(region.y * h));
  const sw = Math.min(w - sx, Math.ceil(region.w * w));
  const sh = Math.min(h - sy, Math.ceil(region.h * h));
  if (sw < 8 || sh < 8) return null;
  const patch = document.createElement("canvas");
  patch.width = sw;
  patch.height = sh;
  const ctx = patch.getContext("2d");
  if (!ctx) return null;
  ctx.drawImage(canvas, sx, sy, sw, sh, 0, 0, sw, sh);
  return patch.toDataURL("image/png");
}
