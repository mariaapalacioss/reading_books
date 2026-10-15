export type QuoteHit = {
  start: number;
  end: number;
};

/**
 * Localiza un fragmento literal dentro del texto extraído.
 * Acepta diferencias de espacios y guiones de fin de línea.
 * Si no hay una correspondencia precisa, devuelve null: no se debe dibujar un resaltado aproximado.
 */
export function locateQuote(haystack: string, quote: string): QuoteHit | null {
  const needle = quote.replace(/\u00ad/g, "").trim();
  if (needle.length < 12) return null;

  const exact = haystack.indexOf(needle);
  if (exact >= 0) return { start: exact, end: exact + needle.length };

  const source = collapseWithMap(haystack);
  const target = collapseWithMap(needle).text;
  if (target.length < 12) return null;
  const at = source.text.indexOf(target);
  if (at < 0) return null;

  const start = source.map[at];
  const last = source.map[at + target.length - 1];
  if (start === undefined || last === undefined) return null;
  return { start, end: last + 1 };
}

export function collapseWithMap(input: string): { text: string; map: number[] } {
  let text = "";
  const map: number[] = [];
  let pendingSpace = false;

  const pushSpace = (origin: number) => {
    if (!text || text.endsWith(" ")) return;
    text += " ";
    map.push(origin);
  };

  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (ch === "\u00ad") continue;

    if (ch === "-" && (input[i + 1] === "\n" || input[i + 1] === "\r")) {
      if (input[i + 1] === "\r" && input[i + 2] === "\n") i += 2;
      else i += 1;
      pendingSpace = false;
      continue;
    }

    if (/\s/.test(ch)) {
      pendingSpace = true;
      continue;
    }

    if (pendingSpace) {
      pushSpace(i);
      pendingSpace = false;
    }
    text += ch;
    map.push(i);
  }

  return { text, map };
}

export async function quoteHash(quote: string): Promise<string> {
  const normalized = quote.replace(/\s+/g, " ").trim();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalized));
  return [...new Uint8Array(digest)].slice(0, 16).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function snippetAround(text: string, start: number, end: number, radius = 80): string {
  const from = Math.max(0, start - radius);
  const to = Math.min(text.length, end + radius);
  const prefix = from > 0 ? "…" : "";
  const suffix = to < text.length ? "…" : "";
  return `${prefix}${text.slice(from, to).replace(/\s+/g, " ").trim()}${suffix}`;
}
