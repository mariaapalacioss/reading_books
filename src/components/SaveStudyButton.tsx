import { useState } from "react";
import { Link } from "react-router-dom";
import { saveAssistAsStudyCards, saveChatAsStudyCard } from "../lib/studyCards";

type AssistSave = {
  variant: "assist";
  bookId: string;
  userId: string;
  chapterId?: string | null;
  pageNumber?: number;
  mode: string | null;
  markdown: string;
  quote?: string | null;
  previewUrl?: string | null;
};

type ChatSave = {
  variant: "chat";
  bookId: string;
  userId: string;
  chapterId?: string | null;
  pageNumber?: number;
  question: string;
  answer: string;
};

type Props = (AssistSave | ChatSave) & {
  disabled?: boolean;
  compact?: boolean;
};

export function SaveStudyButton(props: Props) {
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState("");
  const [count, setCount] = useState(0);

  const save = async () => {
    setBusy(true);
    setError("");
    try {
      let created = 0;
      if (props.variant === "assist") {
        if (props.markdown.trim().length < 12) throw new Error("Todavía no hay respuesta para guardar.");
        const rows = await saveAssistAsStudyCards(props);
        created = rows.length;
      } else {
        if (props.answer.trim().length < 8) throw new Error("La respuesta está vacía.");
        const rows = await saveChatAsStudyCard(props);
        created = rows.length;
      }
      setCount(created);
      setDone(true);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "No se pudo guardar.");
    } finally {
      setBusy(false);
    }
  };

  if (done) {
    return (
      <p className="save-study-done muted">
        {count > 1 ? `${count} tarjetas guardadas.` : "Guardado para repasar."}{" "}
        <Link to={`/revisar/${props.bookId}`}>Ver tarjetas</Link>
      </p>
    );
  }

  return (
    <div className="save-study-wrap">
      <button
        className={`btn-ghost save-study-btn${props.compact ? " compact" : ""}`}
        type="button"
        disabled={props.disabled || busy}
        onClick={() => void save()}
      >
        {busy ? "Guardando…" : "Guardar para repasar"}
      </button>
      {error ? <span className="save-study-error">{error}</span> : null}
    </div>
  );
}
