import { useChatGptPlan } from "../lib/chatgpt/ChatGptPlanProvider";

type Props = {
  variant?: "hero" | "compact" | "panel";
};

export function ChatGptConnect({ variant = "panel" }: Props) {
  const plan = useChatGptPlan();
  const bridgeDown = plan.bridgeOk === false;

  if (plan.connected && plan.model) {
    return (
      <div className={`chatgpt-status${variant === "hero" ? " hero" : ""}`}>
        <span className="chip teal">
          Tu Plus · {plan.credentials?.email ?? plan.model}
          {plan.model ? ` · ${plan.model}` : ""}
        </span>
        <button className="btn-ghost" type="button" onClick={() => void plan.disconnect()}>Desconectar</button>
      </div>
    );
  }

  return (
    <div className={`chatgpt-connect${variant === "hero" ? " hero" : ""}`}>
      {bridgeDown ? (
        <p className="callout bad">
          Falta el puente OAuth local. Cierra la app y arranca con <strong>npm run dev</strong> (no solo <code>vite</code>).
          Debe aparecer en terminal: <code>Smart Books OAuth bridge → http://127.0.0.1:1455/...</code>
        </p>
      ) : plan.bridgeOk === null ? (
        <p className="muted">Comprobando puente local…</p>
      ) : null}
      {plan.error ? <p className="callout bad">{plan.error}</p> : null}
      <button
        className={`btn chatgpt-signin${variant === "hero" ? " hero" : ""}`}
        type="button"
        disabled={plan.loading || bridgeDown}
        onClick={() => void plan.connect().catch(() => undefined)}
      >
        {plan.loading ? "Conectando…" : "Continuar con ChatGPT"}
      </button>
      {variant === "hero" ? (
        <p className="muted">
          Cada cuenta de Smart Books conecta su propio ChatGPT (Plus/Go/Pro cuando el plan lo permita).
          Sign in with ChatGPT oficial: tus libros y tu uso de IA no se comparten con otros usuarios.
        </p>
      ) : null}
    </div>
  );
}
