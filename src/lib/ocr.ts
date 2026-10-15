import { getDocument, type PDFDocumentProxy } from "pdfjs-dist";
import { detectChapters } from "../domain/chapters";
import { detectLanguage } from "../domain/language";
import { documentNeedsOcr, isSparsePage, layoutOcrWords, type OcrWord } from "../domain/ocrLayout";
import { normalizeStudyText } from "../domain/studyText";
import type { TextItem } from "../domain/rects";
import type { ExtractedPage, ExtractedPdf } from "./pdf";

export async function recognizeScannedPdf(
  data: ArrayBuffer,
  extracted: ExtractedPdf,
  onProgress?: (page: number, total: number) => void,
  shouldStop?: () => boolean,
): Promise<ExtractedPdf> {
  const targets = extracted.pages.filter((page) => isSparsePage(page.charCount));
  if (!targets.length) return extracted;

  const session = await createOcrSession(data);
  const pages = extracted.pages.map((page) => ({ ...page }));
  try {
    for (const target of targets) {
      if (shouldStop?.()) throw new Error("Lectura cancelada.");
      onProgress?.(target.page, extracted.pageCount);
      const [recognized] = await session.recognize([target.page]);
      const index = target.page - 1;
      if (recognized.charCount > pages[index].charCount) pages[index] = recognized;
    }
  } finally {
    await session.close();
  }

  const sample = pages.filter((page) => !isSparsePage(page.charCount)).slice(0, 12).map((page) => page.text).join("\n");
  const chapters = extracted.chapters.length >= 2
    ? extracted.chapters
    : detectChapters({
      pageCount: extracted.pageCount,
      outline: [],
      pageTexts: pages.map((page) => page.text),
    });

  return {
    ...extracted,
    pages,
    chapters,
    language: detectLanguage(sample),
    sparsePages: pages.filter((page) => isSparsePage(page.charCount)).length,
    needsOcr: documentNeedsOcr(pages),
  };
}

export type OcrSession = {
  recognize: (pageNumbers: number[]) => Promise<ExtractedPage[]>;
  close: () => Promise<void>;
};

export async function createOcrSession(data: ArrayBuffer): Promise<OcrSession> {
  const { createWorker } = await import("tesseract.js");
  const worker = await createWorker("spa+eng");
  const pdf = await getDocument({ data: new Uint8Array(data.slice(0)) }).promise;
  return {
    async recognize(pageNumbers: number[]) {
      const pages: ExtractedPage[] = [];
      for (const pageNumber of pageNumbers) {
        pages.push(await recognizePage(pdf, worker, pageNumber));
      }
      return pages;
    },
    async close() {
      await worker.terminate();
      await pdf.destroy();
    },
  };
}

type OcrBlock = {
  paragraphs?: {
    lines?: {
      words?: { text?: string | null; confidence?: number | null; bbox?: { x0: number; y0: number; x1: number; y1: number } }[];
    }[];
  }[];
};

async function recognizePage(
  pdf: PDFDocumentProxy,
  worker: { recognize: (image: CanvasImageSource, options: Record<string, never>, output: { text: boolean; blocks: boolean; hocr: boolean; tsv: boolean }) => Promise<{ data: { blocks?: OcrBlock[] | null } }> },
  pageNumber: number,
): Promise<ExtractedPage> {
  const page = await pdf.getPage(pageNumber);
  const base = page.getViewport({ scale: 1 });
  const scale = Math.min(2, 1800 / Math.max(base.width, base.height, 1));
  const viewport = page.getViewport({ scale });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) throw new Error("El navegador no pudo preparar la página para leerla.");
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: context, viewport }).promise;

  try {
    const result = await worker.recognize(canvas, {}, { text: true, blocks: true, hocr: false, tsv: false });
    const words = wordsFromBlocks(result.data.blocks);
    const laid = layoutOcrWords(words, canvas.width, canvas.height);
    const text = normalizeStudyText(laid.text);
    return {
      page: pageNumber,
      text,
      items: laid.items,
      printedLabel: printedLabel(laid.items),
      charCount: text.length,
    };
  } finally {
    page.cleanup();
    canvas.width = 0;
    canvas.height = 0;
  }
}

function wordsFromBlocks(blocks: OcrBlock[] | null | undefined): OcrWord[] {
  const words: OcrWord[] = [];
  for (const block of blocks ?? []) {
    for (const paragraph of block.paragraphs ?? []) {
      for (const line of paragraph.lines ?? []) {
        for (const word of line.words ?? []) {
          const text = word.text?.trim() ?? "";
          if (!text || (word.confidence ?? 0) < 15 || !word.bbox) continue;
          words.push({
            text,
            x0: word.bbox.x0,
            y0: word.bbox.y0,
            x1: word.bbox.x1,
            y1: word.bbox.y1,
          });
        }
      }
    }
  }
  return words;
}

function printedLabel(items: TextItem[]) {
  const candidate = items.find((item) => /^\d{1,4}$/.test(item.s.trim()) && (item.y < 0.08 || item.y > 0.9));
  return candidate?.s.trim() ?? null;
}
