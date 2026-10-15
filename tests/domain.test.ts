import { describe, expect, it } from "vitest";
import { detectChapters, normalizeChapterDrafts } from "../src/domain/chapters.ts";
import { documentNeedsOcr, layoutOcrWords } from "../src/domain/ocrLayout.ts";
import { buildChunks } from "../src/domain/chunks.ts";
import { detectLanguage } from "../src/domain/language.ts";
import { locateQuote } from "../src/domain/quotes.ts";
import { rectsForRange, sameRelativePosition, type TextItem } from "../src/domain/rects.ts";
import { validateHighlights } from "../src/domain/validate.ts";
import { isLocalPdfPath, isStorageSizeError } from "../src/lib/pdfLocal.ts";

describe("locateQuote", () => {
  const page = "La constitución del mercado\nexige reglas claras.\nEl precio de equilibrio aparece cuando la oferta encuentra a la demanda.";

  it("encuentra una cita literal", () => {
    const hit = locateQuote(page, "El precio de equilibrio aparece cuando la oferta encuentra a la demanda.");
    expect(hit).toEqual({ start: page.indexOf("El precio"), end: page.length });
  });

  it("tolera espacios y guiones de corte", () => {
    const hit = locateQuote("constitu-\nción del mercado interior", "constitución del mercado");
    expect(hit).not.toBeNull();
    expect("constitu-\nción del mercado interior".slice(hit!.start, hit!.end)).toContain("constitu");
  });

  it("rechaza texto que no está", () => {
    expect(locateQuote(page, "esta frase no pertenece al libro original")).toBeNull();
  });

  it("rechaza fragmentos demasiado cortos para ser precisos", () => {
    expect(locateQuote(page, "precio")).toBeNull();
  });
});

describe("validateHighlights", () => {
  const pages = [
    { page: 2, text: "Chapter 1. A market is a set of buyers and sellers.", printedLabel: "1" },
    { page: 3, text: "The equilibrium price clears the market.", printedLabel: "2" },
  ];

  it("conserva solo citas reales y su página del PDF", () => {
    const result = validateHighlights(pages, [
      {
        quote: "The equilibrium price clears the market.",
        category: "conclusion",
        explanation_es: "Define el resultado del capítulo.",
        explanation_en: "States the chapter result.",
      },
      {
        quote: "This sentence was invented by the model.",
        category: "idea",
        explanation_es: "No debería entrar.",
        explanation_en: "Should be dropped.",
      },
    ], "balanced");

    expect(result.kept).toHaveLength(1);
    expect(result.kept[0].pageNumber).toBe(3);
    expect(result.kept[0].printedLabel).toBe("2");
    expect(result.dropped).toBe(1);
  });
});

describe("detectChapters", () => {
  it("usa el índice del PDF cuando existe", () => {
    const chapters = detectChapters({
      pageCount: 20,
      outline: [
        { title: "Introducción", page: 1 },
        { title: "Capítulo 1. La demanda", page: 6 },
      ],
      pageTexts: [],
    });
    expect(chapters.map((chapter) => [chapter.startPage, chapter.endPage])).toEqual([[1, 5], [6, 20]]);
  });

  it("lee un índice textual en español", () => {
    const texts = Array.from({ length: 16 }, () => "Texto de página.");
    texts[1] = "Índice\nCapítulo 1 La demanda .... 4\nCapítulo 2 La oferta .... 9";
    const chapters = detectChapters({ pageCount: 16, outline: [], pageTexts: texts });
    expect(chapters.map((chapter) => chapter.startPage)).toEqual([4, 9]);
  });

  it("detecta encabezados en inglés", () => {
    const texts = Array.from({ length: 10 }, () => "Body copy about the topic continues here.");
    texts[0] = "Chapter 1\nScarcity";
    texts[5] = "Chapter 2\nChoice";
    const chapters = detectChapters({ pageCount: 10, outline: [], pageTexts: texts });
    expect(chapters).toHaveLength(2);
    expect(chapters[1].startPage).toBe(6);
  });

  it("normaliza rangos corregidos por el lector", () => {
    const chapters = normalizeChapterDrafts(
      [{ title: "Parte A", startPage: 3, endPage: 8 }],
      10,
    );
    expect(chapters[0]).toMatchObject({ startPage: 3, endPage: 8, source: "user" });
  });
});

describe("detectLanguage", () => {
  it("distingue español e inglés", () => {
    const spanish = "El libro de la casa es una obra que se lee en los cursos de historia y que plantea una idea para comprender el pasado.";
    const english = "The book of the house is a work that is read in the course of history and that is written for the students.";
    expect(detectLanguage(spanish)).toBe("es");
    expect(detectLanguage(english)).toBe("en");
  });
});

describe("rects", () => {
  it("mantiene la posición relativa al cambiar el zoom", () => {
    const rect = { x: 0.2, y: 0.4, w: 0.3, h: 0.05 };
    expect(sameRelativePosition(rect, 600, 800, 960, 1280)).toBe(true);
  });

  it("une fragmentos de la misma línea", () => {
    const items: TextItem[] = [
      { s: "precio", start: 0, x: 0.1, y: 0.2, w: 0.1, h: 0.02 },
      { s: "justo", start: 7, x: 0.22, y: 0.2, w: 0.1, h: 0.02 },
    ];
    const rects = rectsForRange(items, 0, 12);
    expect(rects).toHaveLength(1);
    expect(rects[0].w).toBeGreaterThan(0.2);
  });
});

describe("ocr", () => {
  it("marca un libro como escaneado solo cuando casi no hay texto", () => {
    const scanned = Array.from({ length: 10 }, () => ({ charCount: 0 }));
    const readable = Array.from({ length: 10 }, () => ({ charCount: 400 }));
    expect(documentNeedsOcr(scanned)).toBe(true);
    expect(documentNeedsOcr(readable)).toBe(false);
  });

  it("conserva el orden de las palabras y su posición relativa", () => {
    const laid = layoutOcrWords([
      { text: "demanda", x0: 120, y0: 40, x1: 220, y1: 60 },
      { text: "La", x0: 40, y0: 40, x1: 80, y1: 60 },
      { text: "oferta", x0: 40, y0: 80, x1: 140, y1: 100 },
    ], 400, 200);
    expect(laid.text).toBe("La demanda\noferta");
    expect(laid.items[0].x).toBe(0.1);
    expect(laid.items[1].start).toBe(3);
  });
});

describe("pdfLocal", () => {
  it("detecta rutas locales y errores de tamaño en Storage", () => {
    expect(isLocalPdfPath("local/user/book.pdf")).toBe(true);
    expect(isLocalPdfPath("user/book.pdf")).toBe(false);
    expect(isStorageSizeError({ statusCode: "413", message: "x" })).toBe(true);
    expect(isStorageSizeError({ message: "The object exceeded the maximum allowed size" })).toBe(true);
  });
});

describe("buildChunks", () => {
  it("no mete el libro entero en un solo bloque", () => {
    const pages = Array.from({ length: 8 }, (_, index) => ({
      page: index + 1,
      text: "palabra ".repeat(200),
    }));
    const chunks = buildChunks(pages);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks[0].content).toContain("[p.1]");
    expect(chunks.every((chunk) => chunk.content.length < 8000)).toBe(true);
  });
});
