import { FormEvent, useEffect, useRef, useState } from "react";
import { chatAboutBook } from "../lib/chatgpt/bookAssist";
import { useChatGptPlan } from "../lib/chatgpt/ChatGptPlanProvider";
import type { ExplanationLanguage } from "../lib/types";
import { MarkdownContent } from "./MarkdownContent";
import { SaveStudyButton } from "./SaveStudyButton";

type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
};

type Citation = { pdfPage: number; printedLabel: string | null; quote: string };

type Props = {
  bookId: string;
  bookTitle: string;
  chapterTitle?: string;
  chapterId: string | null;
  pageNumber: number;
  language: ExplanationLanguage;
  userId: string;
  disabled?: boolean;
  onBeforeSend: () => Promise<void>;
  onCitations: (citations: Citation[]) => void;
};

export function BookChat({
  bookId,
  bookTitle,
  chapterTitle,
  pageNumber,
  language,
  userId,
  chapterId,
  disabled,
  onBeforeSend,
  onCitations,
}: Props) {
  const plan = useChatGptPlan();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [streamingId, setStreamingId] = useState<string | null>(null);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages, busy, streamingId]);

  const send = async (event: FormEvent) => {
    event.preventDefault();
    const text = draft.trim();
    if (text.length < 2 || busy || disabled || !plan.connected) return;
    const userMessage: ChatMessage = { id: crypto.randomUUID(), role: "user", content: text };
    const history = [...messages, userMessage];
    setMessages(history);
    setDraft("");
    setBusy(true);
    onCitations([]);
    const assistantId = crypto.randomUUID();
    setStreamingId(assistantId);
    setMessages((current) => [...current, { id: assistantId, role: "assistant", content: "" }]);
    try {
      await onBeforeSend();
      const citations = await chatAboutBook({
        bookId,
        bookTitle,
        chapterTitle,
        pageNumber,
        language,
        messages: history.map((item) => ({ role: item.role, content: item.content })),
        onDelta: (delta) => {
          setMessages((current) => current.map((item) => (
            item.id === assistantId ? { ...item, content: item.content + delta } : item
          )));
        },
      });
      onCitations(citations);
    } catch (reason) {
      const error = reason instanceof Error ? reason.message : "No se pudo obtener respuesta.";
      setMessages((current) => current.map((item) => (
        item.id === assistantId ? { ...item, content: error } : item
      )));
    } finally {
      setBusy(false);
      setStreamingId(null);
    }
  };

  return (
    <section className="book-chat stack">
      <div className="row">
        <strong className="grow">Chat del libro</strong>
        {plan.connected && plan.model ? <span className="chip teal">Plus · {plan.model}</span> : null}
      </div>
      {!plan.connected ? (
        <p className="callout">Conecta ChatGPT en la pantalla de inicio para usar el chat.</p>
      ) : (
        <p className="muted">Conversación con contexto del PDF. Pide explicaciones, repasos, comparaciones o preguntas de examen.</p>
      )}
      <div className="chat-thread" aria-live="polite">
        {messages.length === 0 ? (
          <p className="muted chat-empty">Ejemplo: «Explícame este capítulo como para un examen» o «Hazme 5 preguntas de repaso».</p>
        ) : null}
        {messages.map((message, index) => {
          const streaming = message.id === streamingId;
          const priorUser = message.role === "assistant"
            ? [...messages.slice(0, index)].reverse().find((item) => item.role === "user")
            : undefined;
          return (
            <article key={message.id} className={`chat-bubble ${message.role}${streaming ? " streaming" : ""}`}>
              {message.role === "assistant" && message.content ? (
                <MarkdownContent source={message.content} streaming={streaming} />
              ) : (
                message.content || (streaming ? "…" : "")
              )}
              {message.role === "assistant" && userId && priorUser && message.content && !streaming && !busy ? (
                <SaveStudyButton
                  compact
                  variant="chat"
                  bookId={bookId}
                  userId={userId}
                  chapterId={chapterId}
                  pageNumber={pageNumber}
                  question={priorUser.content}
                  answer={message.content}
                />
              ) : null}
            </article>
          );
        })}
        <div ref={endRef} />
      </div>
      <form className="chat-compose" onSubmit={send}>
        <textarea
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="Escribe tu mensaje…"
          rows={3}
          disabled={!plan.connected}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              void send(event);
            }
          }}
        />
        <button className="btn" type="submit" disabled={draft.trim().length < 2 || busy || disabled || !plan.connected}>
          {busy ? "Respondiendo…" : "Enviar"}
        </button>
      </form>
    </section>
  );
}
