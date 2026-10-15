import { describe, expect, it } from "vitest";
import { cardFromChatPair, cardsFromAssistContent, parseReviewIntoCards } from "../src/domain/studyCardsParse.ts";

describe("parseReviewIntoCards", () => {
  it("parte repaso numerado en tarjetas Q&A", () => {
    const md = `1. ¿Qué es la osteointegración?
> Respuesta corta sobre unión ósea.

2. ¿Cuándo contraindicar implantes?
Respuesta sobre salud sistémica.`;
    const cards = parseReviewIntoCards(md, "Repaso");
    expect(cards.length).toBeGreaterThanOrEqual(2);
    expect(cards[0].kind).toBe("qa");
    expect(cards[0].body).toContain("osteointegración");
    expect(cards[0].back).toBeTruthy();
  });

  it("devuelve una tarjeta review si no hay preguntas claras", () => {
    const cards = parseReviewIntoCards("Texto libre sin numeración.", "Repaso");
    expect(cards).toHaveLength(1);
    expect(cards[0].kind).toBe("review");
  });
});

describe("cardsFromAssistContent", () => {
  it("usa modo review para múltiples tarjetas", () => {
    const cards = cardsFromAssistContent({
      mode: "review",
      markdown: "1. Pregunta uno?\nRespuesta uno.",
    });
    expect(cards.length).toBeGreaterThanOrEqual(1);
  });

  it("resume como summary", () => {
    const cards = cardsFromAssistContent({ mode: "summary", markdown: "## Resumen\nContenido." });
    expect(cards[0].kind).toBe("summary");
  });
});

describe("cardFromChatPair", () => {
  it("detecta par pregunta-respuesta", () => {
    const card = cardFromChatPair("¿Qué es un tercer molar?", "Es la última muela.");
    expect(card.kind).toBe("qa");
    expect(card.back).toContain("última");
  });
});
