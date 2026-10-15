import { FormEvent, useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { snippetAround } from "../domain/quotes";
import { invokeFunction } from "../lib/api";
import { listBooks } from "../lib/books";
import { requireSupabase } from "../lib/supabase";
import { pageLabel, type Book } from "../lib/types";

type Scope = "book" | "highlights" | "library";
type Mode = "text" | "semantic";
type Result = {
  id: string;
  bookId: string;
  title: string;
  pdfPage: number;
  printedLabel?: string | null;
  snippet: string;
};

export function SearchPage() {
  const [params] = useSearchParams();
  const [books, setBooks] = useState<Book[]>([]);
  const [bookId, setBookId] = useState(params.get("libro") ?? "");
  const [scope, setScope] = useState<Scope>(params.get("libro") ? "book" : "library");
  const [mode, setMode] = useState<Mode>("text");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Result[]>([]);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    listBooks().then(setBooks).catch((reason) => setMessage(reason instanceof Error ? reason.message : "No se pudo cargar la biblioteca."));
  }, []);

  const search = async (event: FormEvent) => {
    event.preventDefault();
    const term = query.trim();
    if (term.length < 2) return;
    setBusy(true);
    setMessage("");
    setResults([]);
    try {
      if (mode === "semantic") {
        const data = await invokeFunction<{ results: { chunkId: string; bookId: string; title: string; pdfPage: number; snippet: string }[] }>("semantic-search", {
          query: term,
          bookId: scope === "library" ? null : bookId || null,
          scope: scope === "highlights" ? "highlights" : scope,
        });
        setResults((data.results ?? []).map((item) => ({
          id: item.chunkId,
          bookId: item.bookId,
          title: item.title,
          pdfPage: item.pdfPage,
          snippet: item.snippet,
        })));
        if (!data.results?.length) setMessage("No hubo coincidencias semánticas. Si el índice todavía se está creando, prueba de nuevo en unos minutos.");
      } else {
        setResults(await textSearch(term, scope, scope === "library" ? undefined : bookId, books));
      }
    } catch (reason) {
      setMessage(reason instanceof Error ? reason.message : "No se pudo buscar.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="page">
      <div className="hero">
        <div>
          <h1>Buscar</h1>
          <p className="muted">La búsqueda de texto encuentra palabras. La semántica puede relacionar una pregunta en español con un libro en inglés.</p>
        </div>
      </div>
      <form className="stack" onSubmit={search}>
        <div className="row">
          <div className="seg">
            <button type="button" aria-pressed={mode === "text"} onClick={() => setMode("text")}>Texto</button>
            <button type="button" aria-pressed={mode === "semantic"} onClick={() => setMode("semantic")}>Semántica</button>
          </div>
          <div className="seg">
            <button type="button" aria-pressed={scope === "book"} onClick={() => setScope("book")}>Este libro</button>
            <button type="button" aria-pressed={scope === "highlights"} onClick={() => setScope("highlights")}>Resaltados y notas</button>
            <button type="button" aria-pressed={scope === "library"} onClick={() => setScope("library")}>Biblioteca</button>
          </div>
        </div>
        {scope !== "library" ? (
          <label className="field">
            <span>Libro</span>
            <select value={bookId} onChange={(event) => setBookId(event.target.value)} required={scope === "book"}>
              <option value="">Elige un libro</option>
              {books.map((book) => <option key={book.id} value={book.id}>{book.title}</option>)}
            </select>
          </label>
        ) : null}
        <div className="row">
          <input className="grow" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Concepto, cita o pregunta" />
          <button className="btn" disabled={busy} type="submit">{busy ? "Buscando…" : "Buscar"}</button>
        </div>
      </form>
      {message ? <p className="callout">{message}</p> : null}
      <div className="stack" style={{ marginTop: 18 }}>
        {results.map((result) => (
          <Link className="card result" key={`${result.id}-${result.pdfPage}`} to={`/leer/${result.bookId}?pagina=${result.pdfPage}`}>
            <strong>{result.title}</strong>
            <span className="muted">{pageLabel(result.pdfPage, result.printedLabel)}</span>
            <span>{result.snippet}</span>
          </Link>
        ))}
      </div>
    </main>
  );
}

async function textSearch(query: string, scope: Scope, bookId: string | undefined, books: Book[]): Promise<Result[]> {
  const supabase = requireSupabase();
  const safe = query.replace(/[%_\\,]/g, " ").trim();
  const titles = new Map(books.map((book) => [book.id, book.title]));
  if (scope === "highlights") {
    let request = supabase.from("highlights").select("id, book_id, page_number, quote, note, explanation_es").or(`quote.ilike.%${safe}%,note.ilike.%${safe}%,explanation_es.ilike.%${safe}%`).limit(40);
    if (bookId) request = request.eq("book_id", bookId);
    const { data, error } = await request;
    if (error) throw error;
    return (data ?? []).map((row) => ({
      id: row.id,
      bookId: row.book_id,
      title: titles.get(row.book_id) ?? "Libro",
      pdfPage: row.page_number,
      snippet: row.quote || row.note || row.explanation_es || "",
    }));
  }

  let request = supabase.from("book_pages").select("id, book_id, page_number, printed_label, text").ilike("text", `%${safe}%`).limit(40);
  if (bookId) request = request.eq("book_id", bookId);
  const { data, error } = await request;
  if (error) throw error;
  return (data ?? []).map((row) => {
    const at = row.text.toLowerCase().indexOf(safe.toLowerCase());
    return {
      id: row.id,
      bookId: row.book_id,
      title: titles.get(row.book_id) ?? "Libro",
      pdfPage: row.page_number,
      printedLabel: row.printed_label,
      snippet: at >= 0 ? snippetAround(row.text, at, at + safe.length, 90) : row.text.slice(0, 180),
    };
  });
}
