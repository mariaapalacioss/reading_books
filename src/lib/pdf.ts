import { getDocument, GlobalWorkerOptions, Util, type PDFDocumentProxy } from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import { detectChapters, type OutlineEntry } from "../domain/chapters";
import { detectLanguage, type BookLanguage } from "../domain/language";
import { documentNeedsOcr, isSparsePage } from "../domain/ocrLayout";
import { sortByReadingOrder } from "../domain/readingOrder";
import { normalizeStudyText } from "../domain/studyText";
import type { TextItem } from "../domain/rects";

GlobalWorkerOptions.workerSrc = workerUrl;

export type ExtractedPage = {
  page: number;
  text: string;
  items: TextItem[];
  printedLabel: string | null;
  charCount: number;
};

export type ExtractedPdf = {
  title: string;
  author: string;
  pageCount: number;
  language: BookLanguage;
  needsOcr: boolean;
  sparsePages: number;
  pages: ExtractedPage[];
  chapters: ReturnType<typeof detectChapters>;
};

type TextItemLike = {
  str: string;
  transform: number[];
  width: number;
  height: number;
  hasEOL?: boolean;
};

function emptyPage(pageNumber: number): ExtractedPage {
  return { page: pageNumber, text: "", items: [], printedLabel: null, charCount: 0 };
}

function samplePageNumbers(pageCount: number) {
  const picks = new Set<number>([1, 2, 3, 4, 5, 6, 7, 8, Math.min(15, pageCount), Math.min(20, pageCount)]);
  if (pageCount > 40) picks.add(Math.floor(pageCount / 2));
  if (pageCount > 1) picks.add(pageCount);
  return [...picks].filter((page) => page >= 1 && page <= pageCount).sort((a, b) => a - b);
}

/** Detecta PDF escaneado sin recorrer todas las páginas. Devuelve null si hace falta extracción completa. */
export async function inspectPdf(
  data: ArrayBuffer,
  onProgress?: (page: number, total: number) => void,
): Promise<ExtractedPdf | null> {
  const pdf = await getDocument({ data: new Uint8Array(data) }).promise;
  try {
    const pageCount = pdf.numPages;
    const meta = await pdf.getMetadata().catch(() => null);
    const info = (meta?.info ?? {}) as { Title?: string; Author?: string };
    const samples = samplePageNumbers(pageCount);
    let sparse = 0;
    const pageTexts: string[] = Array.from({ length: pageCount }, () => "");
    for (const pageNumber of samples) {
      const page = await extractPage(pdf, pageNumber);
      pageTexts[pageNumber - 1] = page.text;
      if (isSparsePage(page.charCount)) sparse += 1;
      onProgress?.(pageNumber, pageCount);
    }
    if (sparse / samples.length < 0.7) return null;

    for (let pageNumber = 1; pageNumber <= Math.min(20, pageCount); pageNumber += 1) {
      if (pageTexts[pageNumber - 1]) continue;
      pageTexts[pageNumber - 1] = (await extractPage(pdf, pageNumber)).text;
    }
    const outline = await readOutline(pdf);
    return {
      title: cleanMeta(info.Title) || "Libro sin título",
      author: cleanMeta(info.Author),
      pageCount,
      language: "unknown",
      needsOcr: true,
      sparsePages: pageCount,
      pages: Array.from({ length: pageCount }, (_, index) => emptyPage(index + 1)),
      chapters: detectChapters({ pageCount, outline, pageTexts }),
    };
  } finally {
    await pdf.destroy();
  }
}

export async function extractPdf(
  data: ArrayBuffer,
  onProgress?: (page: number, total: number) => void,
): Promise<ExtractedPdf> {
  const pdf = await getDocument({ data: new Uint8Array(data) }).promise;
  try {
    const pageCount = pdf.numPages;
    const meta = await pdf.getMetadata().catch(() => null);
    const info = (meta?.info ?? {}) as { Title?: string; Author?: string };
    const pages: ExtractedPage[] = [];
    for (let pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
      pages.push(await extractPage(pdf, pageNumber));
      onProgress?.(pageNumber, pageCount);
    }
    const sample = pages.slice(0, 8).map((page) => page.text).join("\n");
    const sparsePages = pages.filter((page) => isSparsePage(page.charCount)).length;
    const outline = await readOutline(pdf);
    return {
      title: cleanMeta(info.Title) || "Libro sin título",
      author: cleanMeta(info.Author),
      pageCount,
      language: detectLanguage(sample),
      needsOcr: documentNeedsOcr(pages),
      sparsePages,
      pages,
      chapters: detectChapters({
        pageCount,
        outline,
        pageTexts: pages.map((page) => page.text),
      }),
    };
  } finally {
    await pdf.destroy();
  }
}

async function extractPage(pdf: { getPage: (n: number) => Promise<PdfPage> }, pageNumber: number): Promise<ExtractedPage> {
  const page = await pdf.getPage(pageNumber);
  const viewport = page.getViewport({ scale: 1 });
  const content = await page.getTextContent();
  type RawPiece = { s: string; x: number; y: number; w: number; h: number; cy: number; hasEol: boolean };
  const pieces: RawPiece[] = [];
  for (const raw of content.items) {
    if (!isTextItem(raw) || !raw.str?.trim()) continue;
    const tx = Util.transform(viewport.transform, raw.transform);
    const fontHeight = Math.max(Math.hypot(tx[2], tx[3]), 1);
    const x = tx[4] / viewport.width;
    const y = (tx[5] - fontHeight) / viewport.height;
    const w = raw.width / viewport.width;
    const h = fontHeight / viewport.height;
    pieces.push({
      s: raw.str,
      x: round(x),
      y: round(y),
      w: round(w),
      h: round(h),
      cy: y + h / 2,
      hasEol: Boolean(raw.hasEOL),
    });
  }

  const ordered = sortByReadingOrder(pieces);
  let text = "";
  const items: TextItem[] = [];
  let lineCenter = -1;
  let lineHeight = 0;

  for (const piece of ordered) {
    const sameLine = lineCenter >= 0 && Math.abs(piece.cy - lineCenter) <= Math.max(lineHeight, piece.h) * 0.55;
    if (text) {
      if (piece.hasEol && !text.endsWith("\n")) text += "\n";
      else if (!sameLine && !text.endsWith("\n")) text += "\n";
      else if (sameLine && !text.endsWith(" ") && !text.endsWith("\n")) text += " ";
    }
    if (!sameLine) {
      lineCenter = piece.cy;
      lineHeight = piece.h;
    }
    const start = text.length;
    text += piece.s;
    items.push({
      s: piece.s,
      start,
      x: piece.x,
      y: piece.y,
      w: piece.w,
      h: piece.h,
    });
    if (piece.hasEol) text += "\n";
  }

  const normalized = normalizeStudyText(text);
  return {
    page: pageNumber,
    text: normalized,
    items,
    printedLabel: findPrintedLabel(items),
    charCount: normalized.length,
  };
}

function findPrintedLabel(items: TextItem[]) {
  const candidate = items.find((item) => /^\d{1,4}$/.test(item.s.trim()) && (item.y < 0.08 || item.y > 0.9));
  return candidate?.s.trim() ?? null;
}

async function readOutline(pdf: PDFDocumentProxy): Promise<OutlineEntry[]> {
  const outline = await pdf.getOutline().catch(() => null);
  const entries: OutlineEntry[] = [];
  const walk = async (nodes: OutlineNode[] | null) => {
    for (const node of nodes ?? []) {
      try {
        const dest = typeof node.dest === "string" ? await pdf.getDestination(node.dest) : node.dest;
        const ref = Array.isArray(dest) ? dest[0] : null;
        if (ref) {
          const index = await pdf.getPageIndex(ref as Parameters<PDFDocumentProxy["getPageIndex"]>[0]);
          entries.push({ title: node.title || "Capítulo", page: index + 1 });
        }
      } catch {
        // Un destino del índice puede estar roto; se sigue con el resto.
      }
      if (node.items?.length) await walk(node.items);
    }
  };
  await walk(outline);
  return entries;
}

type OutlineNode = { title?: string; dest?: unknown; items?: OutlineNode[] };
type PdfPage = {
  getViewport: (params: { scale: number }) => { width: number; height: number; transform: number[] };
  getTextContent: () => Promise<{ items: unknown[] }>;
};

function isTextItem(value: unknown): value is TextItemLike {
  return Boolean(value && typeof value === "object" && "str" in value && "transform" in value);
}

function round(value: number) {
  return Math.round(value * 10000) / 10000;
}

function cleanMeta(value?: string) {
  return value?.replace(/\s+/g, " ").trim() ?? "";
}

export async function openPdf(url: string) {
  return getDocument({ url }).promise;
}

export async function openPdfBytes(data: ArrayBuffer) {
  const copy = data.slice(0);
  return getDocument({ data: new Uint8Array(copy) }).promise;
}
