export type ParsedStudyCard = {
  kind: "note" | "qa" | "summary" | "review" | "explain";
  title: string;
  body: string;
  back?: string;
};

const ASSIST_TITLES: Record<string, string> = {
  key_points: "Puntos importantes",
  summary: "Resumen del capítulo",
  page: "Explicación de página",
  explain: "Explicación de fragmento",
  fragment_summary: "Resumen de fragmento",
  review: "Repaso activo",
};

export function titleForAssistMode(mode: string | null | undefined) {
  if (!mode) return "Nota de estudio";
  return ASSIST_TITLES[mode] ?? "Nota de asistencia";
}

/** Convierte repasos con preguntas numeradas en tarjetas Q&A. */
export function parseReviewIntoCards(markdown: string, baseTitle: string): ParsedStudyCard[] {
  const cards: ParsedStudyCard[] = [];
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  let question = "";
  let answerLines: string[] = [];
  let inAnswer = false;

  const flush = () => {
    const q = question.trim();
    const a = answerLines.join("\n").trim();
    if (q.length >= 8) {
      cards.push({
        kind: "qa",
        title: q.slice(0, 120),
        body: q,
        back: a || undefined,
      });
    }
    question = "";
    answerLines = [];
    inAnswer = false;
  };

  for (const line of lines) {
    const trimmed = line.trim();
    const numbered = trimmed.match(/^\d+[.)]\s+(.+)/);
    if (numbered) {
      flush();
      question = numbered[1];
      continue;
    }
    if (/^#{1,3}\s*respuesta/i.test(trimmed) || /^>\s/.test(trimmed)) {
      inAnswer = true;
      if (trimmed.startsWith(">")) answerLines.push(trimmed.replace(/^>\s?/, ""));
      continue;
    }
    if (inAnswer && trimmed) answerLines.push(trimmed);
  }
  flush();

  if (cards.length >= 2) return cards;

  return [{
    kind: "review",
    title: baseTitle,
    body: markdown.trim(),
  }];
}

export function cardsFromAssistContent(input: {
  mode: string | null;
  markdown: string;
  quote?: string | null;
}): ParsedStudyCard[] {
  const base = titleForAssistMode(input.mode);
  if (input.mode === "review") {
    return parseReviewIntoCards(input.markdown, base);
  }
  const kind = input.mode === "summary" ? "summary"
    : input.mode === "explain" || input.mode === "fragment_summary" ? "explain"
      : input.mode === "key_points" ? "note"
        : "note";
  return [{
    kind,
    title: base,
    body: input.markdown.trim(),
  }];
}

export function cardFromChatPair(question: string, answer: string): ParsedStudyCard {
  const q = question.trim();
  const a = answer.trim();
  const looksLikeQuiz = /^\d+[.)]\s/.test(q) || q.endsWith("?");
  if (looksLikeQuiz && a.length >= 8) {
    return { kind: "qa", title: q.slice(0, 120), body: q, back: a };
  }
  return {
    kind: "note",
    title: q.slice(0, 80) || "Conversación del libro",
    body: a,
    back: q.length > 8 ? `Pregunta: ${q}` : undefined,
  };
}
