/** Posición aproximada de un fragmento de texto en la página (0–1). */
export type PositionedText = {
  x: number;
  y: number;
  w: number;
  h: number;
};

export function sortByReadingOrder<T extends PositionedText>(items: T[]): T[] {
  if (items.length < 2) return [...items];
  const sorted = [...items].sort((a, b) => {
    const cyA = a.y + a.h / 2;
    const cyB = b.y + b.h / 2;
    const lineH = Math.max(a.h, b.h, 0.01);
    if (Math.abs(cyA - cyB) > lineH * 0.55) return cyA - cyB;
    return a.x - b.x;
  });

  const columns = detectColumns(sorted);
  if (columns.length <= 1) return sorted;

  const out: T[] = [];
  for (const column of columns) {
    out.push(...column.sort((a, b) => {
      const cyA = a.y + a.h / 2;
      const cyB = b.y + b.h / 2;
      const lineH = Math.max(a.h, b.h, 0.01);
      if (Math.abs(cyA - cyB) > lineH * 0.55) return cyA - cyB;
      return a.x - b.x;
    }));
  }
  return out;
}

function detectColumns<T extends PositionedText>(items: T[]): T[][] {
  const centers = items.map((item) => item.x + item.w / 2).sort((a, b) => a - b);
  if (centers.length < 6) return [items];

  let bestGap = 0;
  let splitAt = -1;
  for (let i = 1; i < centers.length; i += 1) {
    const gap = centers[i] - centers[i - 1];
    if (gap > bestGap && centers[i] > 0.38 && centers[i - 1] < 0.62) {
      bestGap = gap;
      splitAt = (centers[i] + centers[i - 1]) / 2;
    }
  }
  if (bestGap < 0.12 || splitAt < 0) return [items];

  const left = items.filter((item) => item.x + item.w / 2 <= splitAt);
  const right = items.filter((item) => item.x + item.w / 2 > splitAt);
  if (left.length < 3 || right.length < 3) return [items];
  return [left, right];
}
