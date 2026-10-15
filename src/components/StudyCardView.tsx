import { useState } from "react";
import { Link } from "react-router-dom";
import { MarkdownContent } from "./MarkdownContent";
import type { StudyCard } from "../lib/types";

type Props = {
  card: StudyCard;
  bookId: string;
  onReviewed: () => void;
  onRepasar: () => void;
  onDelete?: () => void;
};

const KIND_LABEL: Record<StudyCard["kind"], string> = {
  note: "Nota",
  qa: "Pregunta",
  summary: "Resumen",
  review: "Repaso",
  explain: "Explicación",
  capture: "Captura",
};

export function StudyCardView({ card, bookId, onReviewed, onRepasar, onDelete }: Props) {
  const [revealed, setRevealed] = useState(false);
  const isQa = card.kind === "qa" && Boolean(card.back);

  return (
    <article className="card study-item study-card-premium study-flashcard">
      <div className="study-card-top">
        <span className="chip purple">{KIND_LABEL[card.kind]} · {card.source === "chat" ? "Chat" : "Asistencia"}</span>
        {card.page_number ? (
          <Link className="muted" to={`/leer/${bookId}?pagina=${card.page_number}`}>PDF {card.page_number}</Link>
        ) : null}
      </div>
      <h3 className="study-flash-title">{card.title}</h3>
      {card.quote ? <blockquote className="quote">{card.quote.slice(0, 280)}{card.quote.length > 280 ? "…" : ""}</blockquote> : null}
      {card.preview_url ? (
        <img className="selection-crop study-card-thumb" src={card.preview_url} alt="Recorte del PDF" />
      ) : null}
      {isQa ? (
        <div className="study-flash-body">
          <p className="study-flash-front">{card.body}</p>
          {revealed ? (
            <div className="study-flash-back">
              <MarkdownContent source={card.back ?? ""} />
            </div>
          ) : (
            <button className="btn-ghost" type="button" onClick={() => setRevealed(true)}>Mostrar respuesta</button>
          )}
        </div>
      ) : (
        <div className="study-card-body study-flash-body">
          <MarkdownContent source={card.body} />
        </div>
      )}
      {card.context_question && card.source === "chat" ? (
        <p className="muted study-context">Pregunta: {card.context_question.slice(0, 160)}{card.context_question.length > 160 ? "…" : ""}</p>
      ) : null}
      <div className="row study-card-actions">
        {card.page_number ? <Link className="btn" to={`/leer/${bookId}?pagina=${card.page_number}`}>Abrir en el libro</Link> : null}
        <button className="btn-ghost" type="button" onClick={onReviewed}>Revisado</button>
        <button className="btn-ghost" type="button" onClick={onRepasar}>Repasar</button>
        {onDelete ? (
          <button className="btn-ghost btn-danger-text" type="button" onClick={onDelete}>Quitar</button>
        ) : null}
      </div>
    </article>
  );
}
