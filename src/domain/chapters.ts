export type OutlineEntry = {
  title: string;
  page: number;
};

export type ChapterDraft = {
  title: string;
  startPage: number;
  endPage: number;
  source: "detected" | "user";
};

const HEADING =
  /^(cap[ií]tulo|chapter|parte|part|secci[oó]n|section|unidad|unit)\b(.{0,80})$/i;

const TOC_LINE = /^(.*?)\s+\.{2,}\s*(\d{1,4})\s*$|^((?:cap[ií]tulo|chapter|parte|part|secci[oó]n|section|\d{1,2}[\).]).{0,90}?)\s+(\d{1,4})\s*$/i;

export function detectChapters(input: {
  pageCount: number;
  outline: OutlineEntry[];
  pageTexts: string[];
}): ChapterDraft[] {
  const pageCount = Math.max(0, input.pageCount);
  if (pageCount === 0) return [];

  const fromOutline = chaptersFromStarts(
    input.outline
      .filter((entry) => entry.page >= 1 && entry.page <= pageCount && entry.title.trim())
      .map((entry) => ({ title: cleanTitle(entry.title), page: entry.page })),
    pageCount,
  );
  if (fromOutline.length >= 2) return fromOutline;

  const toc = chaptersFromToc(input.pageTexts, pageCount);
  if (toc.length >= 2) return toc;

  const headings = chaptersFromHeadings(input.pageTexts, pageCount);
  if (headings.length >= 2) return headings;

  if (fromOutline.length === 1) return fromOutline;
  return [
    {
      title: "Documento completo",
      startPage: 1,
      endPage: pageCount,
      source: "detected",
    },
  ];
}

export function chaptersFromStarts(
  starts: { title: string; page: number }[],
  pageCount: number,
): ChapterDraft[] {
  const sorted = [...starts]
    .filter((item) => item.page >= 1 && item.page <= pageCount)
    .sort((a, b) => a.page - b.page)
    .filter((item, index, list) => index === 0 || item.page !== list[index - 1].page);

  if (!sorted.length) return [];

  return sorted.map((item, index) => {
    const next = sorted[index + 1]?.page ?? pageCount + 1;
    return {
      title: item.title || `Capítulo ${index + 1}`,
      startPage: item.page,
      endPage: Math.max(item.page, next - 1),
      source: "detected" as const,
    };
  });
}

function chaptersFromToc(pageTexts: string[], pageCount: number): ChapterDraft[] {
  const starts: { title: string; page: number }[] = [];
  const scanUntil = Math.min(pageTexts.length, 15);
  for (let pageIndex = 0; pageIndex < scanUntil; pageIndex++) {
    const lines = pageTexts[pageIndex]?.split(/\n+/) ?? [];
    let tocHits = 0;
    for (const line of lines) {
      const match = line.trim().match(TOC_LINE);
      if (!match) continue;
      const title = cleanTitle(match[1] || match[3] || "");
      const printed = Number(match[2] || match[4]);
      if (!title || title.length < 3) continue;
      if (!Number.isInteger(printed) || printed < 1 || printed > pageCount) continue;
      tocHits += 1;
      starts.push({ title, page: printed });
    }
    if (tocHits === 0 && starts.length) break;
  }
  return chaptersFromStarts(starts, pageCount);
}

function chaptersFromHeadings(pageTexts: string[], pageCount: number): ChapterDraft[] {
  const starts: { title: string; page: number }[] = [];
  pageTexts.forEach((text, index) => {
    const first = text
      .split(/\n+/)
      .map((line) => line.trim())
      .find((line) => line.length > 0);
    if (!first || first.length > 90) return;
    const match = first.match(HEADING);
    if (!match) return;
    starts.push({ title: cleanTitle(first), page: index + 1 });
  });
  return chaptersFromStarts(starts, pageCount);
}

function cleanTitle(value: string): string {
  return value.replace(/\s+/g, " ").replace(/[.\s]+$/g, "").trim().slice(0, 140);
}

export function normalizeChapterDrafts(
  drafts: { title: string; startPage: number; endPage: number }[],
  pageCount: number,
): ChapterDraft[] {
  const cleaned = drafts
    .map((draft) => ({
      title: cleanTitle(draft.title) || "Capítulo",
      startPage: Math.min(pageCount, Math.max(1, Math.floor(draft.startPage))),
      endPage: Math.min(pageCount, Math.max(1, Math.floor(draft.endPage))),
    }))
    .filter((draft) => draft.endPage >= draft.startPage)
    .sort((a, b) => a.startPage - b.startPage);

  return cleaned.map((draft) => ({ ...draft, source: "user" as const }));
}
