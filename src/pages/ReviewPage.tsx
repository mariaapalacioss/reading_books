import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { CATEGORY_LABELS } from "../domain/intensity";
import { StudyCardView } from "../components/StudyCardView";
import { getBook, listChapters, listHighlights, listPoints, patchHighlight, patchPoint } from "../lib/books";
import { deleteStudyCard, listStudyCards, patchStudyCard } from "../lib/studyCards";
import { pageLabel, type Book, type Chapter, type ChapterPoint, type Highlight, type StudyCard } from "../lib/types";

type Filter = "pendientes" | "revisados" | "repasar";

export function ReviewPage() {
  const { bookId = "" } = useParams();
  const [book, setBook] = useState<Book | null>(null);
  const [chapters, setChapters] = useState<Chapter[]>([]);
  const [highlights, setHighlights] = useState<Highlight[]>([]);
  const [points, setPoints] = useState<ChapterPoint[]>([]);
  const [studyCards, setStudyCards] = useState<StudyCard[]>([]);
  const [filter, setFilter] = useState<Filter>("pendientes");
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    Promise.all([
      getBook(bookId),
      listChapters(bookId),
      listHighlights(bookId),
      listPoints(bookId),
      listStudyCards(bookId),
    ])
      .then(([nextBook, nextChapters, nextHighlights, nextPoints, nextCards]) => {
        if (!active) return;
        setBook(nextBook);
        setChapters(nextChapters);
        setHighlights(nextHighlights);
        setPoints(nextPoints);
        setStudyCards(nextCards);
      })
      .catch((reason) => {
        if (active) setError(reason instanceof Error ? reason.message : "No se pudo abrir el repaso.");
      });
    return () => { active = false; };
  }, [bookId]);

  const language = book?.explanation_language ?? "es";
  const matches = (item: { reviewed: boolean; review_again: boolean }) => {
    if (filter === "revisados") return item.reviewed;
    if (filter === "repasar") return item.review_again;
    return !item.reviewed;
  };

  const visibleHighlights = useMemo(
    () => highlights.filter((item) => !item.dismissed && (item.origin === "user" || item.intensity === book?.highlight_intensity)),
    [highlights, book?.highlight_intensity],
  );

  const filteredStudyCards = useMemo(() => studyCards.filter(matches), [studyCards, filter]);

  const stats = useMemo(() => {
    const pendingPoints = points.filter((item) => !item.reviewed).length;
    const pendingHighlights = visibleHighlights.filter((item) => !item.reviewed).length;
    const pendingStudy = studyCards.filter((item) => !item.reviewed).length;
    const reviewAgain = [...points, ...visibleHighlights, ...studyCards].filter((item) => item.review_again).length;
    return {
      pendingPoints,
      pendingHighlights,
      pendingStudy,
      reviewAgain,
      total: points.length + visibleHighlights.length + studyCards.length,
    };
  }, [points, visibleHighlights, studyCards]);

  const groups = useMemo(
    () => chapters.map((chapter) => ({
      chapter,
      points: points.filter((item) => item.chapter_id === chapter.id && matches(item)),
      highlights: visibleHighlights.filter((item) => item.chapter_id === chapter.id && matches(item)),
      cards: filteredStudyCards.filter((item) => item.chapter_id === chapter.id),
    })).filter((group) => group.points.length || group.highlights.length || group.cards.length),
    [chapters, points, visibleHighlights, filteredStudyCards, filter],
  );

  const orphanStudyCards = useMemo(
    () => filteredStudyCards.filter((item) => !item.chapter_id || !chapters.some((ch) => ch.id === item.chapter_id)),
    [filteredStudyCards, chapters],
  );

  const hasAny = groups.length > 0 || orphanStudyCards.length > 0;

  if (error) return <main className="page"><p className="callout bad">{error}</p></main>;
  if (!book) return <main className="page"><p>Abriendo el repaso…</p></main>;

  const updateCard = (id: string, patch: Partial<Pick<StudyCard, "reviewed" | "review_again">>) => {
    void patchStudyCard(id, patch).then(() => {
      setStudyCards((current) => current.map((item) => (item.id === id ? { ...item, ...patch } : item)));
    });
  };

  return (
    <main className="page review-page">
      <section className="review-hero card">
        <div className="review-hero-copy">
          <span className="eyebrow">Smart Books · Repaso</span>
          <h1>Tarjetas guardadas</h1>
          <p>
            Puntos del análisis, resaltados del PDF y tarjetas que guardes desde Asistencia o el chat.
            Usa <strong>Guardar para repasar</strong> cuando una respuesta te sirva para estudiar después.
          </p>
        </div>
        <Link className="btn" to={`/leer/${book.id}`}>Volver al libro</Link>
      </section>

      <div className="review-stats">
        <article className="stat-card">
          <strong>{stats.pendingStudy}</strong>
          <span>Tarjetas de estudio</span>
          <small>Chat y asistencia guardadas por ti</small>
        </article>
        <article className="stat-card">
          <strong>{stats.pendingPoints}</strong>
          <span>Puntos clave pendientes</span>
          <small>Ideas del análisis automático por capítulo</small>
        </article>
        <article className="stat-card">
          <strong>{stats.pendingHighlights}</strong>
          <span>Resaltados pendientes</span>
          <small>Citas del PDF + explicación (IA o tuyas)</small>
        </article>
        <article className="stat-card">
          <strong>{stats.reviewAgain}</strong>
          <span>Para repasar</span>
          <small>Marcados para volver a practicar</small>
        </article>
      </div>

      <details className="review-explainer card">
        <summary>¿Qué se guarda exactamente?</summary>
        <ul>
          <li><strong>Tarjetas de estudio</strong> — Lo que guardes con el botón en Asistencia o en cada respuesta del chat (incluye repasos con preguntas en varias tarjetas).</li>
          <li><strong>Puntos clave</strong> — Tras analizar un capítulo, la IA extrae ideas verificadas con cita y página PDF.</li>
          <li><strong>Resaltados</strong> — Fragmentos que marcaste tú o que sugirió la IA, con explicación en ES/EN y enlace a la página.</li>
        </ul>
        <p className="muted">Las respuestas del chat no se guardan solas: pulsa <em>Guardar para repasar</em> cuando quieras conservarlas.</p>
      </details>

      <div className="seg review-filters" aria-label="Filtro de repaso">
        {([["pendientes", "Pendientes"], ["revisados", "Revisados"], ["repasar", "Para repasar"]] as const).map(([id, label]) => (
          <button key={id} type="button" aria-pressed={filter === id} onClick={() => setFilter(id)}>{label}</button>
        ))}
      </div>

      {!hasAny ? (
        <p className="empty review-empty">
          No hay tarjetas en este filtro. Guarda respuestas desde Asistencia, usa el chat o espera el análisis del capítulo.
        </p>
      ) : null}

      <div className="study-list review-grid">
        {orphanStudyCards.length ? (
          <section className="study-block review-chapter">
            <header className="review-chapter-head">
              <h2>Guardadas desde chat y asistencia</h2>
              <span className="chip">{orphanStudyCards.length} tarjetas</span>
            </header>
            {orphanStudyCards.map((card) => (
              <StudyCardView
                key={card.id}
                card={card}
                bookId={book.id}
                onReviewed={() => updateCard(card.id, { reviewed: true, review_again: false })}
                onRepasar={() => updateCard(card.id, { review_again: true, reviewed: false })}
                onDelete={() => void deleteStudyCard(card.id).then(() => setStudyCards((c) => c.filter((item) => item.id !== card.id)))}
              />
            ))}
          </section>
        ) : null}

        {groups.map((group) => (
          <section key={group.chapter.id} className="study-block review-chapter">
            <header className="review-chapter-head">
              <h2>{group.chapter.title}</h2>
              <span className="chip">{group.points.length + group.highlights.length + group.cards.length} tarjetas</span>
            </header>
            {group.cards.map((card) => (
              <StudyCardView
                key={card.id}
                card={card}
                bookId={book.id}
                onReviewed={() => updateCard(card.id, { reviewed: true, review_again: false })}
                onRepasar={() => updateCard(card.id, { review_again: true, reviewed: false })}
                onDelete={() => void deleteStudyCard(card.id).then(() => setStudyCards((c) => c.filter((item) => item.id !== card.id)))}
              />
            ))}
            {group.points.map((point) => (
              <article className="card study-item study-card-premium" key={point.id}>
                <div className="study-card-top">
                  <span className="chip purple">Punto clave · IA</span>
                  {point.page_number ? <span className="muted">{pageLabel(point.page_number, point.printed_label)}</span> : null}
                </div>
                <p className="study-card-body">{language === "en" ? point.text_en : point.text_es}</p>
                {point.quote ? <blockquote className="quote">{point.quote}</blockquote> : null}
                <div className="row study-card-actions">
                  {point.page_number ? (
                    <Link className="btn" to={`/leer/${book.id}?pagina=${point.page_number}`}>Abrir en el libro</Link>
                  ) : (
                    <span className="muted">Sin página verificada</span>
                  )}
                  <button className="btn-ghost" type="button" onClick={() => patchPoint(point.id, { reviewed: true, review_again: false }).then(() => setPoints((current) => current.map((item) => item.id === point.id ? { ...item, reviewed: true, review_again: false } : item)))}>Revisado</button>
                  <button className="btn-ghost" type="button" onClick={() => patchPoint(point.id, { review_again: true, reviewed: false }).then(() => setPoints((current) => current.map((item) => item.id === point.id ? { ...item, review_again: true, reviewed: false } : item)))}>Repasar</button>
                </div>
              </article>
            ))}
            {group.highlights.map((highlight) => (
              <article className="card study-item study-card-premium" key={highlight.id}>
                <div className="study-card-top">
                  <span className="chip">{CATEGORY_LABELS[highlight.category]} · {highlight.origin === "ai" ? "IA" : "Tuyo"}</span>
                  <span className="muted">PDF {highlight.page_number}</span>
                </div>
                <blockquote className="quote">{highlight.quote}</blockquote>
                <p className="study-card-body">{(language === "en" ? highlight.explanation_en : highlight.explanation_es) || highlight.note || "Sin explicación adicional."}</p>
                <div className="row study-card-actions">
                  <Link className="btn" to={`/leer/${book.id}?pagina=${highlight.page_number}&resalte=${highlight.id}`}>Abrir en el libro</Link>
                  <button className="btn-ghost" type="button" onClick={() => patchHighlight(highlight.id, { reviewed: true, review_again: false }).then(() => setHighlights((current) => current.map((item) => item.id === highlight.id ? { ...item, reviewed: true, review_again: false } : item)))}>Revisado</button>
                  <button className="btn-ghost" type="button" onClick={() => patchHighlight(highlight.id, { review_again: true, reviewed: false }).then(() => setHighlights((current) => current.map((item) => item.id === highlight.id ? { ...item, review_again: true, reviewed: false } : item)))}>Repasar</button>
                </div>
              </article>
            ))}
          </section>
        ))}
      </div>
    </main>
  );
}
