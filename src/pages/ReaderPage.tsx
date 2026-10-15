import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { CATEGORY_LABELS } from "../domain/intensity";
import { INTENSITY_LIMITS, type HighlightIntensity } from "../domain/intensity";
import { normalizeChapterDrafts } from "../domain/chapters";
import { ensureAnalysis, subscribeAnalysis } from "../lib/analysis";
import { ensureOcr, prioritizeOcrPages, subscribeOcr } from "../lib/ocrJob";
import { ensurePageText, ensurePagesText } from "../lib/pageOcr";
import { AssistPanel, type AssistJob } from "../components/AssistPanel";
import { isSparsePage } from "../domain/ocrLayout";
import { locateQuote } from "../domain/quotes";
import { runBookAssist, type AssistMode } from "../lib/chatgpt/bookAssist";
import { useChatGptPlan } from "../lib/chatgpt/ChatGptPlanProvider";
import {
  createManualHighlight,
  getBook,
  getPage,
  listBookmarks,
  listChapters,
  listHighlights,
  patchHighlight,
  replaceChapters,
  toggleBookmark,
  updateBook,
} from "../lib/books";
import { PdfView } from "../components/PdfView";
import { ThemeSwitch } from "../components/ThemeSwitch";
import { useSession } from "../lib/session";
import { pageLabel, type Book, type Bookmark, type Chapter, type Highlight, type PageRow } from "../lib/types";
import type { NormRect } from "../domain/rects";

type SelectionState = { quote: string; rects: NormRect[]; x: number; y: number; previewUrl?: string };
type Citation = { pdfPage: number; printedLabel: string | null; quote: string };

const MOBILE_READER_BREAK = 980;

export function ReaderPage() {
  const { bookId = "" } = useParams();
  const [searchParams] = useSearchParams();
  const requestedPage = Number(searchParams.get("pagina")) || 0;
  const session = useSession();
  const chatGpt = useChatGptPlan();
  const [book, setBook] = useState<Book | null>(null);
  const [chapters, setChapters] = useState<Chapter[]>([]);
  const [highlights, setHighlights] = useState<Highlight[]>([]);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [page, setPage] = useState(1);
  const [zoom, setZoom] = useState(1.15);
  const [pageRow, setPageRow] = useState<PageRow | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const [chaptersOpen, setChaptersOpen] = useState(() => window.innerWidth > 980);
  const [assistOpen, setAssistOpen] = useState(() => window.innerWidth > 980);
  const [selection, setSelection] = useState<SelectionState | null>(null);
  const [popover, setPopover] = useState<{ highlight: Highlight; x: number; y: number } | null>(null);
  const [editing, setEditing] = useState(false);
  const [drafts, setDrafts] = useState<{ title: string; startPage: number; endPage: number }[]>([]);
  const [assistText, setAssistText] = useState("");
  const [citations, setCitations] = useState<Citation[]>([]);
  const [assistJob, setAssistJob] = useState<AssistJob>({ mode: null, status: "idle", label: "", error: "" });
  const [ocrPageBusy, setOcrPageBusy] = useState(false);
  const [regionOcrBusy, setRegionOcrBusy] = useState(false);
  const [selectionMode, setSelectionMode] = useState<"text" | "capture">("capture");
  const [selectionNotice, setSelectionNotice] = useState("");
  const [analysisMessage, setAnalysisMessage] = useState("");
  const [ocrProgress, setOcrProgress] = useState("");
  const stageRef = useRef<HTMLDivElement>(null);
  const [stageWidth, setStageWidth] = useState(0);

  const closeReaderPanels = useCallback(() => {
    setChaptersOpen(false);
    setAssistOpen(false);
  }, []);

  const goToPage = useCallback((next: number) => {
    setPage(next);
    if (window.innerWidth <= MOBILE_READER_BREAK) closeReaderPanels();
  }, [closeReaderPanels]);

  useEffect(() => {
    const el = stageRef.current;
    if (!el) return;
    const update = () => setStageWidth(el.clientWidth);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    window.addEventListener("orientationchange", update);
    return () => {
      ro.disconnect();
      window.removeEventListener("orientationchange", update);
    };
  }, [ready, book?.id]);

  const reload = async (current = book) => {
    if (!current) return;
    const [nextBook, nextChapters, nextHighlights, nextBookmarks] = await Promise.all([
      getBook(current.id),
      listChapters(current.id),
      listHighlights(current.id),
      listBookmarks(current.id),
    ]);
    if (nextBook) setBook(nextBook);
    setChapters(nextChapters);
    setHighlights(nextHighlights);
    setBookmarks(nextBookmarks);
  };

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const next = await getBook(bookId);
        if (!active) return;
        if (!next) {
          setError("No se encontró el libro.");
          return;
        }
        setBook(next);
        setPage(requestedPage || next.current_page || 1);
        setZoom(next.zoom || 1.15);
        const [nextChapters, nextHighlights, nextBookmarks] = await Promise.all([
          listChapters(next.id),
          listHighlights(next.id),
          listBookmarks(next.id),
        ]);
        if (!active) return;
        setChapters(nextChapters);
        setHighlights(nextHighlights);
        setBookmarks(nextBookmarks);
        setReady(true);
        if (next.status === "extracting" || next.status === "needs_ocr") {
          void ensureOcr(next);
        }
        if (next.status === "analyzing" || next.status === "ready" || next.status === "partial" || next.status === "extracting") {
          void ensureAnalysis(next);
        }
      } catch (reason) {
        if (active) setError(reason instanceof Error ? reason.message : "No se pudo abrir el libro.");
      }
    })();
    return () => { active = false; };
    // La página inicial se lee una vez; el efecto no debe reabrir el PDF al cambiar la query.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bookId]);

  useEffect(() => {
    if (!book) return;
    const stopAnalysis = subscribeAnalysis((event) => {
      if (event.bookId !== book.id) return;
      setAnalysisMessage(event.error || `${event.message} · ${event.done}/${event.total}`);
      void reload(book);
    });
    const stopOcr = subscribeOcr((event) => {
      if (event.bookId !== book.id) return;
      const note = event.error || event.message;
      if (/ArrayBuffer|sendWithPromise/i.test(note)) return;
      setOcrProgress(note);
      void reload(book);
    });
    return () => {
      stopAnalysis();
      stopOcr();
    };
  }, [book?.id]);

  useEffect(() => {
    if (!book) return;
    let active = true;
    prioritizeOcrPages(book.id, [page - 1, page, page + 1]);
    void ensureOcr(book);
    getPage(book.id, page).then((row) => { if (active) setPageRow(row); }).catch(() => undefined);
    return () => { active = false; };
  }, [book?.id, page]);

  useEffect(() => {
    if (!pageRow) return;
    const chars = (pageRow.text ?? "").trim().length;
    const hasOcrItems = (pageRow.items?.length ?? 0) > 4;
    if (isSparsePage(chars) && hasOcrItems) setSelectionMode("capture");
    else if (chars > 400) setSelectionMode("text");
    else setSelectionMode("capture");
  }, [pageRow?.page_number, pageRow?.text, pageRow?.items?.length]);

  useEffect(() => {
    if (!book || book.status !== "extracting") return;
    const timer = window.setInterval(() => {
      void getPage(book.id, page).then(setPageRow).catch(() => undefined);
    }, 4000);
    return () => window.clearInterval(timer);
  }, [book?.id, book?.status, page]);

  useEffect(() => {
    if (!book || !ready) return;
    const timer = window.setTimeout(() => {
      void updateBook(book.id, { current_page: page, zoom, last_read_at: new Date().toISOString() });
    }, 700);
    return () => window.clearTimeout(timer);
  }, [book?.id, page, zoom, ready]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT") return;
      if (event.key === "ArrowRight") setPage((current) => Math.min(book?.page_count || current, current + 1));
      if (event.key === "ArrowLeft") setPage((current) => Math.max(1, current - 1));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [book?.page_count]);

  if (error) return <main className="page"><p className="callout bad">{error}</p><Link to="/">Volver a la biblioteca</Link></main>;
  if (!book) return <main className="page"><p>Abriendo el libro…</p></main>;

  const chapter = chapters.find((item) => page >= item.start_page && page <= item.end_page) ?? null;
  const language = book.explanation_language;
  const visibleHighlights = highlights.filter((item) => item.origin === "user" || item.intensity === book.highlight_intensity);
  const pageHasText = Boolean(pageRow && !isSparsePage((pageRow.text ?? "").trim().length));
  /** PDF escaneado o maquetado en columnas: solo recorte, nunca selección horizontal. */
  const captureOnly = !pageHasText || book.status === "extracting" || book.status === "needs_ocr"
    || book.status === "partial" || (pageRow?.items?.length ?? 0) > 12;
  const assistBusy = assistJob.status === "loading" || assistJob.status === "streaming";
  const bookmarked = bookmarks.some((item) => item.page_number === page);
  const activeId = searchParams.get("resalte") ?? popover?.highlight.id;
  const readerPanelOpen = chaptersOpen || assistOpen;

  const prepareAssistContext = async () => {
    if (chapter) {
      await ensurePagesText(book, [page - 1, page, page + 1, chapter.start_page, chapter.start_page + 1]);
    } else {
      await ensurePageText(book, page);
    }
    const row = await getPage(book.id, page);
    if (row) setPageRow(row);
  };

  const assistLoadingLabel = (mode: AssistMode) => {
    if (mode === "key_points") return "Analizando ideas clave…";
    if (mode === "page") return "Analizando contenido…";
    if (mode === "explain" || mode === "fragment_summary") return "Analizando el fragmento…";
    if (mode === "review") return "Preparando repaso activo…";
    return "Analizando contenido…";
  };

  const runAssist = async (mode: AssistMode, retry = false) => {
    setAssistOpen(true);
    setAssistJob({ mode, status: "loading", label: assistLoadingLabel(mode), error: "" });
    setAssistText("");
    setCitations([]);
    try {
      if (!chatGpt.connected) throw new Error("Conecta ChatGPT Plus en inicio de sesión o en Biblioteca → Conectar ChatGPT.");
      await prepareAssistContext();
      if (mode === "explain" || mode === "fragment_summary") {
        if (!selection) throw new Error("Selecciona un fragmento en el PDF.");
        if (pageRow?.text && !selection.previewUrl && !locateQuote(pageRow.text, selection.quote)) {
          throw new Error("Ese texto no coincide con la capa legible de la página. Vuelve a seleccionar sobre el PDF.");
        }
      }
      setAssistJob({ mode, status: "streaming", label: assistLoadingLabel(mode), error: "" });
      await runBookAssist({
        mode,
        bookId: book.id,
        chapterId: chapter?.id,
        pageNumber: page,
        quote: selection?.quote,
        language,
        skipCache: retry,
        onDelta: (delta) => {
          setAssistText((current) => current + delta);
        },
      });
      setAssistJob({ mode, status: "done", label: "", error: "" });
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : "No se pudo consultar el libro.";
      setAssistJob({ mode, status: "error", label: "", error: message });
      if (!assistText) setAssistText("");
    }
  };

  const runPageOcr = async () => {
    if (!book || ocrPageBusy) return;
    setOcrPageBusy(true);
    try {
      const row = await ensurePageText(book, page);
      if (row) setPageRow(row);
    } finally {
      setOcrPageBusy(false);
    }
  };

  const saveManual = async () => {
    if (!selection || !session?.user) return;
    const created = await createManualHighlight({
      bookId: book.id,
      userId: session.user.id,
      chapterId: chapter?.id ?? null,
      pageNumber: page,
      quote: selection.quote,
      rects: selection.rects,
    });
    setHighlights((current) => [...current, created]);
    setSelection(null);
    window.getSelection()?.removeAllRanges();
  };

  return (
    <section className="reader reader-workspace">
      <header className="reader-bar reader-bar-premium">
        <Link className="btn-ghost" to="/">Biblioteca</Link>
        <h1 title={book.title}>{book.title}</h1>
        <div className="row grow">
          <button className="icon-btn" type="button" onClick={() => setPage((current) => Math.max(1, current - 1))} aria-label="Página anterior">←</button>
          <label className="muted">
            <input
              aria-label="Número de página"
              style={{ width: 64 }}
              type="number"
              min={1}
              max={book.page_count}
              value={page}
              onChange={(event) => setPage(Math.min(book.page_count, Math.max(1, Number(event.target.value) || 1)))}
            />
            / {book.page_count}
          </label>
          <button className="icon-btn" type="button" onClick={() => setPage((current) => Math.min(book.page_count, current + 1))} aria-label="Página siguiente">→</button>
          <button className="icon-btn" type="button" onClick={() => setZoom((current) => Math.max(0.7, Number((current - 0.15).toFixed(2))))} aria-label="Alejar">−</button>
          <span className="muted">{Math.round(zoom * 100)}%</span>
          <button className="icon-btn" type="button" onClick={() => setZoom((current) => Math.min(2.4, Number((current + 0.15).toFixed(2))))} aria-label="Acercar">+</button>
        </div>
        <select
          aria-label="Intensidad de resaltado"
          value={book.highlight_intensity}
          onChange={(event) => {
            const highlight_intensity = event.target.value as HighlightIntensity;
            const next = { ...book, highlight_intensity };
            setBook(next);
            void updateBook(book.id, { highlight_intensity }).then(() => ensureAnalysis(next));
          }}
        >
          {Object.entries(INTENSITY_LIMITS).map(([id, item]) => <option key={id} value={id}>{item.label}</option>)}
        </select>
        <div className="seg" aria-label="Idioma de las explicaciones">
          {(["es", "en"] as const).map((id) => (
            <button key={id} type="button" aria-pressed={language === id} onClick={() => {
              setBook({ ...book, explanation_language: id });
              void updateBook(book.id, { explanation_language: id });
            }}>{id === "es" ? "ES" : "EN"}</button>
          ))}
        </div>
        <button className="btn-ghost" type="button" onClick={() => {
          const show_ai_highlights = !book.show_ai_highlights;
          setBook({ ...book, show_ai_highlights });
          void updateBook(book.id, { show_ai_highlights });
        }}>{book.show_ai_highlights ? "Ocultar IA" : "Mostrar IA"}</button>
        <span className="chip teal">{captureOnly ? "Captura de zona" : "Texto o captura"}</span>
        {!captureOnly ? (
          <div className="seg" aria-label="Modo de selección">
            <button type="button" aria-pressed={selectionMode === "text"} onClick={() => setSelectionMode("text")}>Texto</button>
            <button type="button" aria-pressed={selectionMode === "capture"} onClick={() => setSelectionMode("capture")}>Captura</button>
          </div>
        ) : null}
        <ThemeSwitch />
      </header>
      <div className={`reader-body reader-grid${chaptersOpen ? "" : " no-chapters"}${assistOpen ? "" : " no-assist"}`}>
        <aside className={`drawer reader-drawer${chaptersOpen ? " open" : ""}`} aria-hidden={!chaptersOpen}>
          <div className="drawer-inner reader-panel-inner">
            <button className="drawer-back-mobile btn" type="button" onClick={closeReaderPanels}>Volver al libro</button>
            <div className="row">
              <strong className="grow">Capítulos</strong>
              <button className="btn-ghost" type="button" onClick={() => {
                setDrafts(chapters.map((item) => ({ title: item.title, startPage: item.start_page, endPage: item.end_page })));
                setEditing(true);
              }}>Corregir</button>
            </div>
            {chapters.map((item) => (
              <button className={`chapter-btn${chapter?.id === item.id ? " active" : ""}`} type="button" key={item.id} onClick={() => goToPage(item.start_page)}>
                <span className={`dot ${item.analysis_status}`} /> {item.title}
                <small>PDF {item.start_page}–{item.end_page} · {labelStatus(item.analysis_status)}</small>
                {item.analysis_error ? <small>{item.analysis_error}</small> : null}
              </button>
            ))}
            <button className="btn-ghost" type="button" onClick={() => {
              if (!session?.user) return;
              void toggleBookmark(book.id, session.user.id, page, bookmarked).then(() => listBookmarks(book.id).then(setBookmarks));
            }}>{bookmarked ? "Quitar marcador" : "Marcar esta página"}</button>
            {bookmarks.map((item) => (
              <button className="chapter-btn" type="button" key={item.id} onClick={() => goToPage(item.page_number)}>
                {item.label || `Página ${item.page_number}`}
              </button>
            ))}
            {highlights.some((item) => item.dismissed) ? <strong>Marcas quitadas</strong> : null}
            {highlights.filter((item) => item.dismissed).map((item) => (
              <button className="chapter-btn" type="button" key={item.id} onClick={() => {
                void patchHighlight(item.id, { dismissed: false }).then(() => setHighlights((current) => current.map((row) => row.id === item.id ? { ...row, dismissed: false } : row)));
                goToPage(item.page_number);
              }}>
                Restaurar · PDF {item.page_number}
                <small>{item.quote.slice(0, 80)}</small>
              </button>
            ))}
          </div>
        </aside>
        <div className="stage reader-stage" ref={stageRef}>
          {book.status === "extracting" ? (
            <p className="callout">{ocrProgress || book.status_detail || "Leyendo el texto escaneado en segundo plano…"} Puedes ir pasando páginas; el análisis del primer capítulo empieza en cuanto haya texto.</p>
          ) : null}
          {book.status === "needs_ocr" ? (
            <div className="callout stack">
              <p>No se pudo leer suficiente texto. Puedes reintentar la lectura en segundo plano.</p>
              <button className="btn" type="button" onClick={() => void ensureOcr(book)}>Reintentar lectura</button>
            </div>
          ) : null}
          {analysisMessage ? <p className="callout">{analysisMessage}</p> : null}
          <p className="muted">{pageRow ? pageLabel(page, pageRow.printed_label) : `PDF ${page}`}</p>
          {!pageHasText ? (
            <div className="callout stack">
              <p>Esta página aún no tiene texto seleccionable (PDF escaneado o en cola de lectura).</p>
              <button className="btn" type="button" disabled={ocrPageBusy} onClick={() => void runPageOcr()}>
                {ocrPageBusy ? "Leyendo texto…" : "Leer texto de esta página"}
              </button>
            </div>
          ) : null}
          {regionOcrBusy ? <p className="callout">Leyendo la zona seleccionada…</p> : null}
          {selectionNotice ? <p className="callout bad">{selectionNotice}</p> : null}
          <PdfView
            storagePath={book.storage_path}
            pageNumber={page}
            zoom={zoom}
            fitMaxWidth={stageWidth > 280 ? stageWidth - 24 : undefined}
            page={pageRow}
            highlights={visibleHighlights}
            showAi={book.show_ai_highlights}
            activeId={activeId ?? undefined}
            selectionMode={captureOnly ? "capture" : selectionMode}
            captureOnly={captureOnly}
            selectionRects={selection?.rects}
            selectionActive={Boolean(selection && (assistJob.mode === "explain" || assistJob.mode === "fragment_summary") && assistBusy)}
            onRegionBusy={setRegionOcrBusy}
            onSelect={(next) => {
              if (!next) {
                setSelectionNotice("No se leyó texto en esa zona. Amplía el rectángulo o usa «Leer texto de esta página» antes.");
                return;
              }
              setSelectionNotice("");
              setSelection(next);
            }}
            onHighlight={(highlight, anchor) => {
              setSelection(null);
              setPopover({ highlight, ...anchor });
            }}
          />
        </div>
        <aside className={`drawer reader-drawer right${assistOpen ? " open" : ""}`} aria-hidden={!assistOpen}>
          <AssistPanel
            onBackToBook={closeReaderPanels}
            bookId={book.id}
            bookTitle={book.title}
            chapter={chapter}
            pageNumber={page}
            language={language}
            chatGptConnected={chatGpt.connected}
            chatGptModel={chatGpt.model}
            selectionQuote={selection?.quote ?? null}
            pageHasText={pageHasText}
            job={assistJob}
            assistText={assistText}
            citations={citations}
            onRun={(mode) => void runAssist(mode)}
            onRetry={() => assistJob.mode && void runAssist(assistJob.mode, true)}
            onBeforeChat={prepareAssistContext}
            onCitations={setCitations}
            onCitationPage={(pdfPage) => goToPage(pdfPage)}
            userId={session?.user?.id ?? ""}
            selectionPreviewUrl={selection?.previewUrl ?? null}
          />
        </aside>
      </div>
      {readerPanelOpen ? (
        <button
          className="reader-backdrop"
          type="button"
          aria-label="Volver al libro"
          onClick={closeReaderPanels}
        />
      ) : null}
      <div className={`mobile-tools${readerPanelOpen ? " panel-open" : ""}`}>
        {readerPanelOpen ? (
          <button className="btn mobile-back-book" type="button" onClick={closeReaderPanels}>Volver al libro</button>
        ) : (
          <>
            <button className="btn-ghost" type="button" onClick={() => { setChaptersOpen(true); setAssistOpen(false); }}>Capítulos</button>
            <button className="btn-ghost" type="button" onClick={() => { setAssistOpen(true); setChaptersOpen(false); }}>Asistencia</button>
          </>
        )}
      </div>
      {selection ? (
        <div className="selection-menu selection-menu-sheet" style={{ left: selection.x, top: selection.y }}>
          {selection.previewUrl ? (
            <img className="selection-crop" src={selection.previewUrl} alt="Zona seleccionada" />
          ) : null}
          <p className="quote">{selection.quote.slice(0, 180)}</p>
          <div className="row wrap">
            <button className="btn" type="button" onClick={() => void saveManual()}>Resaltar</button>
            <button className="btn-ghost" type="button" onClick={() => { setAssistOpen(true); void runAssist("explain"); }}>Explicar con IA</button>
            <button className="btn-ghost" type="button" onClick={() => { setAssistOpen(true); void runAssist("fragment_summary"); }}>Resumir</button>
            <button className="btn-ghost" type="button" onClick={() => setSelection(null)}>Cerrar</button>
          </div>
        </div>
      ) : null}
      {popover ? (
        <HighlightCard
          highlight={popover.highlight}
          language={language}
          x={popover.x}
          y={popover.y}
          onClose={() => setPopover(null)}
          onChange={(next) => {
            setHighlights((current) => current.map((item) => item.id === next.id ? next : item));
            setPopover((current) => current ? { ...current, highlight: next } : current);
          }}
        />
      ) : null}
      {editing ? (
        <div className="backdrop">
          <form className="dialog stack" onSubmit={(event) => {
            event.preventDefault();
            if (!session?.user) return;
            const next = normalizeChapterDrafts(drafts, book.page_count);
            void replaceChapters(book.id, session.user.id, next).then(() => reload(book)).then(() => setEditing(false));
          }}>
            <h2>Corregir capítulos</h2>
            <p className="muted">Si la estructura no coincide con el libro, ajusta los rangos de páginas del PDF. Al guardar se quitan los resaltados automáticos anteriores y el capítulo queda listo para un análisis nuevo.</p>
            {drafts.map((draft, index) => (
              <div className="row" key={index}>
                <input className="grow" value={draft.title} onChange={(event) => setDrafts((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, title: event.target.value } : item))} />
                <input aria-label="Página inicial" type="number" style={{ width: 80 }} value={draft.startPage} onChange={(event) => setDrafts((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, startPage: Number(event.target.value) } : item))} />
                <input aria-label="Página final" type="number" style={{ width: 80 }} value={draft.endPage} onChange={(event) => setDrafts((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, endPage: Number(event.target.value) } : item))} />
              </div>
            ))}
            <div className="row">
              <button className="btn" type="submit">Guardar rangos</button>
              <button className="btn-ghost" type="button" onClick={() => setDrafts((current) => [...current, { title: "Nuevo capítulo", startPage: page, endPage: page }])}>Añadir</button>
              <button className="btn-ghost" type="button" onClick={() => setEditing(false)}>Cerrar</button>
            </div>
          </form>
        </div>
      ) : null}
    </section>
  );
}

function HighlightCard({ highlight, language, x, y, onClose, onChange }: {
  highlight: Highlight;
  language: "es" | "en";
  x: number;
  y: number;
  onClose: () => void;
  onChange: (highlight: Highlight) => void;
}) {
  const explanation = language === "en" ? highlight.explanation_en : highlight.explanation_es;
  const update = async (patch: Partial<Highlight>) => {
    await patchHighlight(highlight.id, patch);
    onChange({ ...highlight, ...patch });
  };
  return (
    <aside className="popover" style={{ left: Math.min(x, window.innerWidth - 340), top: Math.min(y, window.innerHeight - 280) }}>
      <strong>{CATEGORY_LABELS[highlight.category]} · {highlight.origin === "ai" ? "IA" : "Tuyo"}</strong>
      <blockquote className="quote">{highlight.quote}</blockquote>
      <p>{explanation || "Este resaltado no tiene explicación todavía."}</p>
      <label className="field">
        <span>Nota</span>
        <textarea defaultValue={highlight.note ?? ""} onBlur={(event) => void update({ note: event.target.value })} />
      </label>
      <div className="row">
        <button className="btn-ghost" type="button" onClick={() => void update({ reviewed: !highlight.reviewed, review_again: false })}>{highlight.reviewed ? "Revisado" : "Marcar revisado"}</button>
        <button className="btn-ghost" type="button" onClick={() => void update({ review_again: true, reviewed: false })}>Repasar de nuevo</button>
        <button className="btn-ghost" type="button" onClick={() => void update({ dismissed: true }).then(onClose)}>Eliminar</button>
      </div>
    </aside>
  );
}

function labelStatus(status: Chapter["analysis_status"]) {
  if (status === "done") return "analizado";
  if (status === "processing" || status === "queued") return "en curso";
  if (status === "failed") return "con error";
  return "pendiente";
}
