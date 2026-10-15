import { Link } from "react-router-dom";
import type { AssistMode } from "../lib/chatgpt/bookAssist";
import type { Chapter, ExplanationLanguage } from "../lib/types";
import { BookChat } from "./BookChat";
import { MarkdownContent } from "./MarkdownContent";
import { SaveStudyButton } from "./SaveStudyButton";

export type AssistJob = {
  mode: AssistMode | null;
  status: "idle" | "loading" | "streaming" | "error" | "done";
  label: string;
  error: string;
};

type Citation = { pdfPage: number; printedLabel: string | null; quote: string };

type Props = {
  bookId: string;
  bookTitle: string;
  chapter: Chapter | null;
  pageNumber: number;
  language: ExplanationLanguage;
  chatGptConnected: boolean;
  chatGptModel: string | null;
  selectionQuote: string | null;
  pageHasText: boolean;
  job: AssistJob;
  assistText: string;
  citations: Citation[];
  onRun: (mode: AssistMode) => void;
  onRetry: () => void;
  onBeforeChat: () => Promise<void>;
  onCitations: (citations: Citation[]) => void;
  onCitationPage: (pdfPage: number) => void;
  userId: string;
  selectionPreviewUrl?: string | null;
  onBackToBook?: () => void;
};

const LABELS: Partial<Record<AssistMode, string>> = {
  key_points: "Puntos importantes de este capítulo",
  summary: "Resume este capítulo",
  page: "Explícame esta página",
  explain: "Explícame este fragmento",
  review: "Revisar lo importante",
};

const LOADING: Partial<Record<AssistMode, string>> = {
  key_points: "Analizando ideas clave…",
  summary: "Analizando contenido…",
  page: "Analizando esta página…",
  explain: "Analizando el fragmento…",
  review: "Preparando repaso activo…",
};

export function AssistPanel(props: Props) {
  const busy = props.job.status === "loading" || props.job.status === "streaming";
  const active = props.job.mode;

  const buttonState = (mode: AssistMode) => {
    if (active === mode && busy) return LOADING[mode] ?? "Analizando…";
    if (active === mode && props.job.status === "error") return "Reintentar";
    return LABELS[mode] ?? mode;
  };

  const disabled = (mode: AssistMode) => {
    if (busy && active !== mode) return true;
    if (mode === "explain" && !props.selectionQuote) return true;
    if ((mode === "key_points" || mode === "summary" || mode === "review") && !props.chapter) return true;
    if (!props.chatGptConnected) return false;
    return false;
  };

  return (
    <div className="drawer-inner assist-panel">
      {props.onBackToBook ? (
        <button className="drawer-back-mobile btn" type="button" onClick={props.onBackToBook}>Volver al libro</button>
      ) : null}
      <strong>Asistencia</strong>
      {props.chatGptConnected && props.chatGptModel ? (
        <span className="chip teal">ChatGPT Plus · {props.chatGptModel}</span>
      ) : (
        <p className="callout"><Link to="/conectar-chatgpt">Conectar ChatGPT Plus</Link> para usar resúmenes y chat.</p>
      )}

      {props.job.status !== "idle" && props.job.label ? (
        <p className="assist-status" role="status" aria-live="polite">
          {props.job.status === "error" ? props.job.error : props.job.label}
        </p>
      ) : null}

      <p className="muted">{props.chapter ? props.chapter.title : "Sin capítulo en esta página"}</p>

      <button
        className={`btn${active === "key_points" && busy ? " loading" : ""}`}
        type="button"
        disabled={disabled("key_points") || (busy && active === "key_points")}
        onClick={() => props.onRun("key_points")}
      >
        {buttonState("key_points")}
      </button>
      <button
        className="btn-ghost"
        type="button"
        disabled={disabled("summary") || (busy && active === "summary")}
        onClick={() => props.onRun("summary")}
      >
        {buttonState("summary")}
      </button>
      <button
        className="btn-ghost"
        type="button"
        disabled={disabled("page") || (busy && active === "page")}
        onClick={() => props.onRun("page")}
      >
        {props.pageHasText ? buttonState("page") : "Explícame esta página (sin texto aún)"}
      </button>
      <button
        className="btn-ghost"
        type="button"
        disabled={disabled("explain") || (busy && active === "explain")}
        onClick={() => props.onRun("explain")}
      >
        {props.selectionQuote ? buttonState("explain") : "Selecciona texto en el PDF"}
      </button>
      <button
        className="btn-ghost"
        type="button"
        disabled={disabled("review") || (busy && active === "review")}
        onClick={() => props.onRun("review")}
      >
        {buttonState("review")}
      </button>
      <Link className="btn-ghost" to={`/revisar/${props.bookId}`}>Ir a repaso (tarjetas, puntos y resaltados) →</Link>

      {props.selectionQuote ? (
        <blockquote className="quote selection-preview">
          <small>Fragmento seleccionado</small>
          {props.selectionQuote.slice(0, 220)}{props.selectionQuote.length > 220 ? "…" : ""}
        </blockquote>
      ) : null}

      {props.assistText ? (
        <div className="assist-result card">
          <MarkdownContent source={props.assistText} streaming={props.job.status === "streaming"} />
          {props.job.status === "error" ? (
            <button className="btn-ghost" type="button" onClick={props.onRetry}>Reintentar</button>
          ) : null}
          {props.job.status === "done" && props.userId ? (
            <SaveStudyButton
              variant="assist"
              bookId={props.bookId}
              userId={props.userId}
              chapterId={props.chapter?.id ?? null}
              pageNumber={props.pageNumber}
              mode={props.job.mode}
              markdown={props.assistText}
              quote={props.selectionQuote}
              previewUrl={props.selectionPreviewUrl}
            />
          ) : null}
        </div>
      ) : null}

      {props.citations.map((citation) => (
        <button
          className="result-btn"
          type="button"
          key={`${citation.pdfPage}-${citation.quote.slice(0, 24)}`}
          onClick={() => props.onCitationPage(citation.pdfPage)}
        >
          PDF {citation.pdfPage}
          <small>{citation.quote}</small>
        </button>
      ))}

      <BookChat
        bookId={props.bookId}
        bookTitle={props.bookTitle}
        chapterTitle={props.chapter?.title}
        chapterId={props.chapter?.id ?? null}
        pageNumber={props.pageNumber}
        language={props.language}
        userId={props.userId}
        disabled={busy}
        onBeforeSend={props.onBeforeChat}
        onCitations={props.onCitations}
      />
    </div>
  );
}
