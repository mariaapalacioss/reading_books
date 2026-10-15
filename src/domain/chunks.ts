export type PageSlice = {
  page: number;
  text: string;
};

export type ChunkDraft = {
  pageStart: number;
  pageEnd: number;
  content: string;
};

const TARGET = 1800;

export function buildChunks(pages: PageSlice[]): ChunkDraft[] {
  const usable = pages.filter((page) => page.text.trim().length > 0);
  const chunks: ChunkDraft[] = [];
  let current: PageSlice[] = [];
  let size = 0;

  const flush = () => {
    if (!current.length) return;
    chunks.push({
      pageStart: current[0].page,
      pageEnd: current[current.length - 1].page,
      content: current.map((page) => `[p.${page.page}]\n${page.text.trim()}`).join("\n\n"),
    });
    current = [];
    size = 0;
  };

  for (const page of usable) {
    const block = page.text.trim();
    if (size > 0 && size + block.length > TARGET) flush();
    current.push(page);
    size += block.length;
    if (size >= TARGET) flush();
  }
  flush();
  return chunks;
}

export function windowsForAnalysis(pages: PageSlice[], maxChars = 12000): ChunkDraft[] {
  return buildChunks(pages).reduce<ChunkDraft[]>((groups, chunk) => {
    const last = groups[groups.length - 1];
    if (!last || last.content.length + chunk.content.length > maxChars) groups.push({ ...chunk });
    else {
      last.pageEnd = chunk.pageEnd;
      last.content = `${last.content}\n\n${chunk.content}`;
    }
    return groups;
  }, []);
}
