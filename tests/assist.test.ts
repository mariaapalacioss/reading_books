import { describe, expect, it } from "vitest";
import { markdownToSafeHtml } from "../src/domain/markdown.ts";
import { normalizeStudyText, assessTextQuality } from "../src/domain/studyText.ts";
import { sortByReadingOrder } from "../src/domain/readingOrder.ts";
import { textFromRegion } from "../src/domain/regionSelect.ts";
import type { TextItem } from "../src/domain/rects.ts";
import { assistCacheKey, readAssistCache, runAssistOnce } from "../src/lib/chatgpt/assistCache.ts";

describe("normalizeStudyText", () => {
  it("une palabras cortadas por guión de fin de línea", () => {
    expect(normalizeStudyText("extrac-\nción del molar")).toBe("extracción del molar");
  });

  it("colapsa espacios sin alterar términos técnicos", () => {
    const text = normalizeStudyText("tercer   molar\n\nincluido");
    expect(text).toContain("tercer molar");
    expect(text).toContain("incluido");
  });
});

describe("assessTextQuality", () => {
  it("marca OCR ruidoso como poco fiable", () => {
    const noisy = "!@#$%^&*()_+={}[]|:;<>?/\\".repeat(12);
    const q = assessTextQuality(noisy);
    expect(q.reliable).toBe(false);
    expect(q.issues.length).toBeGreaterThan(0);
  });

  it("acepta párrafo académico legible", () => {
    const text = "La extracción del tercer molar incluido requiere evaluar riesgos, indicaciones y contraindicaciones basadas en evidencia clínica.";
    const q = assessTextQuality(text);
    expect(q.score).toBeGreaterThan(0.5);
  });
});

describe("markdownToSafeHtml", () => {
  it("renderiza encabezados y negritas sin mostrar símbolos crudos", () => {
    const html = markdownToSafeHtml("## Idea principal\n\n**La demanda** aumenta.");
    expect(html).toContain("<h2>");
    expect(html).toContain("<strong>La demanda</strong>");
    expect(html).not.toContain("##");
    expect(html).not.toContain("**");
  });

  it("escapa HTML peligroso", () => {
    const html = markdownToSafeHtml("<script>alert(1)</script>");
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("renderiza listas numeradas", () => {
    const html = markdownToSafeHtml("1. Primer punto\n2. Segundo punto");
    expect(html).toContain("<ol>");
    expect(html).toContain("<li>Primer punto</li>");
  });
});

describe("sortByReadingOrder", () => {
  it("ordena columnas de izquierda a derecha", () => {
    type Piece = { id: string; x: number; y: number; w: number; h: number };
    const ordered = sortByReadingOrder<Piece>([
      { id: "B", x: 0.55, y: 0.1, w: 0.1, h: 0.02 },
      { id: "A", x: 0.08, y: 0.1, w: 0.1, h: 0.02 },
      { id: "C", x: 0.08, y: 0.2, w: 0.1, h: 0.02 },
    ]);
    expect(ordered.map((item) => item.id).join("")).toBe("ABC");
  });
});

describe("textFromRegion", () => {
  it("extrae palabras OCR dentro del rectángulo", () => {
    const items: TextItem[] = [
      { s: "La", start: 0, x: 0.1, y: 0.2, w: 0.04, h: 0.02 },
      { s: "demanda", start: 3, x: 0.16, y: 0.2, w: 0.12, h: 0.02 },
      { s: "oferta", start: 11, x: 0.1, y: 0.5, w: 0.1, h: 0.02 },
    ];
    const pageText = "La demanda oferta";
    const hit = textFromRegion(items, { x: 0.05, y: 0.15, w: 0.3, h: 0.15 }, pageText);
    expect(hit.quote).toContain("demanda");
    expect(hit.quote).not.toContain("oferta");
    expect(hit.rects.length).toBeGreaterThan(0);
  });
});

describe("assistCache", () => {
  it("deduplica solicitudes en vuelo y guarda respuestas", async () => {
    const key = assistCacheKey({ mode: "page", bookId: "b1", pageNumber: 3 });
    let calls = 0;
    const p1 = runAssistOnce(key, async () => {
      calls += 1;
      return "respuesta";
    });
    const p2 = runAssistOnce(key, async () => {
      calls += 1;
      return "otra";
    });
    expect(await p1).toBe("respuesta");
    expect(await p2).toBe("respuesta");
    expect(calls).toBe(1);
    expect(readAssistCache(key)).toBe("respuesta");
  });
});
