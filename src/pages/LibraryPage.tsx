import { FormEvent, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { INTENSITY_LIMITS, type HighlightIntensity } from "../domain/intensity";
import { ensureAnalysis, subscribeAnalysis } from "../lib/analysis";
import { deleteBook, listBooks, preparePdf, saveBook } from "../lib/books";
import { ensureOcr, resumeBackgroundOcr, subscribeOcr } from "../lib/ocrJob";
import { useSession } from "../lib/session";
import { LANGUAGE_LABEL, STATUS_LABEL, type Book, type BookLanguage, type ExplanationLanguage } from "../lib/types";
import type { ExtractedPdf } from "../lib/pdf";
import { formatFileSize, isLocalPdfPath, maxCloudPdfBytes } from "../lib/pdfLocal";

export function LibraryPage() {
  const session = useSession();
  const [books, setBooks] = useState<Book[]>([]);
  const [query, setQuery] = useState("");
  const [language, setLanguage] = useState<"all" | BookLanguage>("all");
  const [status, setStatus] = useState("all");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [draft, setDraft] = useState<ExtractedPdf | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [author, setAuthor] = useState("");
  const [bookLanguage, setBookLanguage] = useState<BookLanguage>("unknown");
  const [intensity, setIntensity] = useState<HighlightIntensity>("balanced");
  const [progress, setProgress] = useState("");
  const load = async () => {
    try {
      setBooks(await listBooks());
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "No se pudo cargar la biblioteca.");
    }
  };

  useEffect(() => {
    void load().then(() => listBooks().then(resumeBackgroundOcr));
    const stopAnalysis = subscribeAnalysis(() => { void load(); });
    const stopOcr = subscribeOcr(() => { void load(); });
    return () => {
      stopAnalysis();
      stopOcr();
    };
  }, []);

  const visible = useMemo(() => books.filter((book) => {
    const haystack = `${book.title} ${book.author ?? ""}`.toLowerCase();
    if (query && !haystack.includes(query.toLowerCase())) return false;
    if (language !== "all" && book.language !== language) return false;
    if (status === "ocr") return book.status === "needs_ocr" || book.status === "extracting";
    if (status === "analysis") return book.status === "analyzing" || book.status === "partial";
    if (status === "ready") return book.status === "analyzed" || book.status === "ready";
    if (status === "error") return book.status === "error";
    return true;
  }), [books, query, language, status]);

  const chooseFile = async (next: File | null) => {
    if (!next) return;
    setError("");
    setFile(next);
    setProgress("Abriendo el PDF…");
    try {
      const extracted = await preparePdf(next, (page, total) => setProgress(`Leyendo la página ${page} de ${total}…`));
      setDraft(extracted);
      setTitle(extracted.title);
      setAuthor(extracted.author);
      setBookLanguage(extracted.language);
      setProgress("");
    } catch (reason) {
      setProgress("");
      setError(reason instanceof Error ? reason.message : "No se pudo leer el PDF.");
    }
  };

  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (!draft || !file || !session?.user || progress) return;
    setError("");
    try {
      setProgress("Guardando…");
      const explanationLanguage: ExplanationLanguage = "es";
      const bookId = await saveBook({
        file,
        userId: session.user.id,
        extracted: draft,
        title,
        author,
        language: bookLanguage,
        intensity,
        explanationLanguage,
        onProgress: setProgress,
      });
      setDraft(null);
      setFile(null);
      await load();
      const saved = (await listBooks()).find((book) => book.id === bookId);
      if (!saved) {
        setProgress("");
        return;
      }
      if (isLocalPdfPath(saved.storage_path)) {
        setNotice(
          "Libro guardado en este navegador (el PDF supera el límite de la nube). No lo borres del historial ni cambies de dispositivo si quieres conservar el archivo.",
        );
      } else if (draft.needsOcr) {
        setNotice("Libro guardado. Smart Books lee el texto en segundo plano; puedes abrirlo ya y el primer capítulo se analizará en cuanto esté listo.");
      } else {
        setNotice("El análisis empezó por el primer capítulo. Ya puedes abrir el libro.");
      }
      if (draft.needsOcr) void ensureOcr(saved);
      else void ensureAnalysis(saved);
      setProgress("");
    } catch (reason) {
      setProgress("");
      setError(reason instanceof Error ? reason.message : "No se pudo guardar el libro.");
    }
  };

  const name = session?.user.user_metadata?.display_name as string | undefined;

  return (
    <main className="page library-page">
      <header className="library-header card">
        <div className="library-header-copy">
          <span className="library-eyebrow">Smart Books</span>
          <h1>{name ? `Biblioteca de ${name}` : "Tu biblioteca"}</h1>
          <p className="muted">PDFs académicos con resaltados, OCR y asistencia conectada a tu plan ChatGPT Plus.</p>
        </div>
        <label className="btn library-upload">
          Subir PDF
          <input hidden type="file" accept="application/pdf,.pdf" onChange={(event) => void chooseFile(event.target.files?.[0] ?? null)} />
        </label>
      </header>

      {(notice || error || progress) ? (
        <div className="library-alerts stack">
          {notice ? <p className="callout good">{notice}</p> : null}
          {error ? <p className="callout bad">{error}</p> : null}
          {progress ? <p className="callout">{progress}</p> : null}
        </div>
      ) : null}

      <section className="library-toolbar card" aria-label="Filtros">
        <input
          className="library-search"
          placeholder="Buscar por título o autor"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          aria-label="Buscar libros"
        />
        <select value={language} onChange={(event) => setLanguage(event.target.value as typeof language)} aria-label="Filtrar por idioma">
          <option value="all">Todos los idiomas</option>
          <option value="es">Español</option>
          <option value="en">Inglés</option>
          <option value="unknown">Sin detectar</option>
        </select>
        <select value={status} onChange={(event) => setStatus(event.target.value)} aria-label="Filtrar por estado">
          <option value="all">Todos los estados</option>
          <option value="ready">Listos</option>
          <option value="analysis">En análisis</option>
          <option value="ocr">Requieren OCR</option>
          <option value="error">Con error</option>
        </select>
      </section>

      {visible.length === 0 ? (
        <div className="empty library-empty card">
          <h2>Todavía no hay libros aquí</h2>
          <p className="muted">Sube tu primer PDF con el botón superior. Verás el avance del OCR y podrás continuar la lectura en cualquier dispositivo.</p>
        </div>
      ) : (
        <section className="library-grid" aria-label="Libros">
          {visible.map((book) => (
            <article className="library-card card" key={book.id}>
              <div className="library-card-head">
                <div className="chips">
                  <span className="chip">{LANGUAGE_LABEL[book.language]}</span>
                  <span className={book.status === "needs_ocr" || book.status === "error" ? "chip warn" : book.status === "extracting" ? "chip" : "chip teal"}>{STATUS_LABEL[book.status]}</span>
                  {isLocalPdfPath(book.storage_path) ? <span className="chip warn">Solo en este navegador</span> : null}
                </div>
                <span className="library-pages muted">{book.page_count} pág.</span>
              </div>
              <div className="library-card-body">
                <h2>{book.title}</h2>
                <p className="muted">{book.author || "Autor sin indicar"}</p>
              </div>
              <div className="progress" aria-label={book.status === "extracting" ? "Progreso de lectura" : "Progreso del análisis"}>
                <span style={{ width: `${Math.round((book.analysis_progress || 0) * 100)}%` }} />
              </div>
              {book.status === "extracting" && book.status_detail ? (
                <p className="library-status muted">{book.status_detail}</p>
              ) : null}
              <div className="library-card-actions">
                <Link className="btn" to={`/leer/${book.id}`}>Continuar lectura</Link>
                {book.status !== "needs_ocr" && book.status !== "extracting" && book.status !== "analyzing" && book.status !== "analyzed" ? (
                  <button className="btn-ghost" type="button" onClick={() => void ensureAnalysis(book)}>Analizar</button>
                ) : null}
                <button className="btn-ghost btn-danger-text" type="button" onClick={() => {
                  if (window.confirm(`¿Quitar «${book.title}» de tu biblioteca?`)) void deleteBook(book).then(load);
                }}>Quitar</button>
              </div>
            </article>
          ))}
        </section>
      )}

      {draft && file ? (
        <div className="backdrop" role="presentation">
          <form className="dialog stack" onSubmit={save}>
            <h2>Ficha del libro</h2>
            <p className="muted">{draft.pageCount} páginas · {draft.chapters.length} capítulo{draft.chapters.length === 1 ? "" : "s"} detectado{draft.chapters.length === 1 ? "" : "s"}.</p>
            {file.size > maxCloudPdfBytes() ? (
              <p className="callout">
                Este PDF pesa {formatFileSize(file.size)} y supera el límite de subida a Supabase ({formatFileSize(maxCloudPdfBytes())} en plan Free).
                Smart Books lo guardará en este navegador; metadatos y análisis siguen en la nube.
              </p>
            ) : null}
            {draft.needsOcr ? (
              <p className="callout">Este PDF está escaneado. Al guardarlo, Smart Books guarda el archivo y lee el texto en segundo plano. Puedes cerrar esta ventana y abrir el libro; el primer capítulo se analiza en cuanto tenga texto.</p>
            ) : null}
            {progress ? <p className="callout">{progress}</p> : null}
            <label className="field"><span>Título</span><input value={title} onChange={(event) => setTitle(event.target.value)} required /></label>
            <label className="field"><span>Autor</span><input value={author} onChange={(event) => setAuthor(event.target.value)} /></label>
            <label className="field">
              <span>Idioma del libro</span>
              <select value={bookLanguage} onChange={(event) => setBookLanguage(event.target.value as BookLanguage)}>
                <option value="es">Español</option>
                <option value="en">Inglés</option>
                <option value="unknown">Sin detectar</option>
              </select>
            </label>
            <label className="field">
              <span>Intensidad de resaltado</span>
              <select value={intensity} onChange={(event) => setIntensity(event.target.value as HighlightIntensity)}>
                {Object.entries(INTENSITY_LIMITS).map(([id, item]) => <option key={id} value={id}>{item.label}</option>)}
              </select>
            </label>
            <p className="muted">{INTENSITY_LIMITS[intensity].hint}</p>
            <div className="row">
              <button className="btn" type="submit" disabled={Boolean(progress)}>{progress ? "Guardando…" : draft.needsOcr ? "Guardar y leer en segundo plano" : "Guardar y analizar"}</button>
              <button className="btn-ghost" type="button" onClick={() => { if (!progress) { setDraft(null); setFile(null); } }}>Cancelar</button>
            </div>
          </form>
        </div>
      ) : null}
    </main>
  );
}
