export type NormRect = {
  x: number;
  y: number;
  w: number;
  h: number;
};

export type TextItem = {
  s: string;
  start: number;
  x: number;
  y: number;
  w: number;
  h: number;
};

export function scaleRect(rect: NormRect, width: number, height: number) {
  return {
    left: rect.x * width,
    top: rect.y * height,
    width: rect.w * width,
    height: rect.h * height,
  };
}

export function rectsForRange(items: TextItem[], start: number, end: number): NormRect[] {
  const selected = items.filter((item) => item.s && item.start < end && item.start + item.s.length > start && item.w > 0 && item.h > 0);
  if (!selected.length) return [];

  const lines: TextItem[][] = [];
  for (const item of selected) {
    const line = lines.find((group) => Math.abs(group[0].y - item.y) < Math.max(item.h, group[0].h) * 0.6);
    if (line) line.push(item);
    else lines.push([item]);
  }

  return lines.map((line) => {
    const x = Math.min(...line.map((item) => item.x));
    const y = Math.min(...line.map((item) => item.y));
    const right = Math.max(...line.map((item) => item.x + item.w));
    const bottom = Math.max(...line.map((item) => item.y + item.h));
    return {
      x: clamp01(x),
      y: clamp01(y),
      w: clamp01(right) - clamp01(x),
      h: clamp01(bottom) - clamp01(y),
    };
  }).filter((rect) => rect.w > 0.001 && rect.h > 0.001);
}

function clamp01(value: number) {
  return Math.min(1, Math.max(0, value));
}

export function sameRelativePosition(rect: NormRect, widthA: number, heightA: number, widthB: number, heightB: number) {
  const a = scaleRect(rect, widthA, heightA);
  const b = scaleRect(rect, widthB, heightB);
  const ratio = (box: { left: number; top: number }, width: number, height: number) => ({
    x: box.left / width,
    y: box.top / height,
  });
  const ra = ratio(a, widthA, heightA);
  const rb = ratio(b, widthB, heightB);
  return Math.abs(ra.x - rb.x) < 0.0001 && Math.abs(ra.y - rb.y) < 0.0001;
}
