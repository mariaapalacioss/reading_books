const ESCAPE: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (ch) => ESCAPE[ch] ?? ch);
}

function inlineFormat(value: string) {
  let out = escapeHtml(value);
  out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
  out = out.replace(/\*\*\*([^*]+)\*\*\*/g, "<strong><em>$1</em></strong>");
  out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/\*([^*]+)\*/g, "<em>$1</em>");
  out = out.replace(/\[p\.(\d+)\]/g, '<span class="md-page-ref">[p.$1]</span>');
  return out;
}

function isTableRow(line: string) {
  return line.includes("|") && line.trim().startsWith("|");
}

function parseTableRow(line: string) {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((cell) => cell.trim());
}

/** Convierte Markdown académico común a HTML seguro (sin scripts ni URLs peligrosas). */
export function markdownToSafeHtml(source: string): string {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const html: string[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      i += 1;
      continue;
    }

    if (/^#{1,6}\s+/.test(trimmed)) {
      const level = trimmed.match(/^#+/)![0].length;
      const tag = `h${Math.min(level, 4)}`;
      html.push(`<${tag}>${inlineFormat(trimmed.replace(/^#+\s*/, ""))}</${tag}>`);
      i += 1;
      continue;
    }

    if (trimmed.startsWith(">")) {
      const quote: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith(">")) {
        quote.push(lines[i].trim().replace(/^>\s?/, ""));
        i += 1;
      }
      html.push(`<blockquote><p>${inlineFormat(quote.join(" "))}</p></blockquote>`);
      continue;
    }

    if (isTableRow(trimmed)) {
      const rows: string[][] = [];
      while (i < lines.length && isTableRow(lines[i])) {
        rows.push(parseTableRow(lines[i]));
        i += 1;
      }
      if (rows.length >= 2 && rows[1].every((cell) => /^:?-+:?$/.test(cell.replace(/\s/g, "")))) {
        const header = rows[0];
        const body = rows.slice(2);
        html.push("<table><thead><tr>");
        for (const cell of header) html.push(`<th>${inlineFormat(cell)}</th>`);
        html.push("</tr></thead><tbody>");
        for (const row of body) {
          html.push("<tr>");
          for (const cell of row) html.push(`<td>${inlineFormat(cell)}</td>`);
          html.push("</tr>");
        }
        html.push("</tbody></table>");
      } else {
        for (const row of rows) {
          html.push(`<p>${inlineFormat(row.join(" · "))}</p>`);
        }
      }
      continue;
    }

    if (/^[-*]\s+/.test(trimmed)) {
      html.push("<ul>");
      while (i < lines.length && /^[-*]\s+/.test(lines[i].trim())) {
        html.push(`<li>${inlineFormat(lines[i].trim().replace(/^[-*]\s+/, ""))}</li>`);
        i += 1;
      }
      html.push("</ul>");
      continue;
    }

    if (/^\d+\.\s+/.test(trimmed)) {
      html.push("<ol>");
      while (i < lines.length && /^\d+\.\s+/.test(lines[i].trim())) {
        html.push(`<li>${inlineFormat(lines[i].trim().replace(/^\d+\.\s+/, ""))}</li>`);
        i += 1;
      }
      html.push("</ol>");
      continue;
    }

    const para: string[] = [trimmed];
    i += 1;
    while (i < lines.length && lines[i].trim() && !/^#{1,6}\s/.test(lines[i].trim()) && !lines[i].trim().startsWith(">") && !/^[-*]\s+/.test(lines[i].trim()) && !/^\d+\.\s+/.test(lines[i].trim()) && !isTableRow(lines[i])) {
      para.push(lines[i].trim());
      i += 1;
    }
    html.push(`<p>${inlineFormat(para.join(" "))}</p>`);
  }

  return html.join("\n");
}
