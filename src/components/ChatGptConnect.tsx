import { useChatGptPlan } from "../lib/chatgpt/ChatGptPlanProvider";
import { isPublicWebDeploy } from "../lib/chatgpt/environment";

type Props = {
  variant?: "hero" | "compact" | "panel";
  /** En login público: mensaje suave, sin bloquear el acceso con correo. */
  placement?: "login" | "app";
};

export function ChatGptConnect({ variant = "panel", placement = "app" }: Props) {
  const plan = useChatGptPlan();
  const hosted = isPublicWebDeploy();
  const bridgeDown = !hosted && plan.bridgeOk === false;

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
      {hosted && placement === "login" ? (
        <p className="callout chatgpt-hosted-hint">
          Ya puedes <strong>entrar o crear cuenta</strong> abajo con correo y contraseña.
          Para vincular <strong>tu ChatGPT Plus</strong> (Sign in with ChatGPT), usa Smart Books en tu computadora con{" "}
          <code>npm run dev</code> e inicia sesión con el mismo correo; el puente OAuth solo corre en local por política de OpenAI.
        </p>
      ) : null}
      {hosted && placement === "app" ? (
        <p className="callout chatgpt-hosted-hint">
          La conexión con tu plan ChatGPT requiere abrir Smart Books en local (<code>npm run dev</code>) en este equipo.
          La biblioteca, el PDF y el repaso siguen disponibles aquí en la web.
        </p>
      ) : null}
      {!hosted && bridgeDown ? (
        <p className="callout bad">
          Falta el puente OAuth local. Arranca con <strong>npm run dev</strong> (no solo <code>vite</code>).
          Debe aparecer: <code>Smart Books OAuth bridge → http://127.0.0.1:1455/...</code>
        </p>
      ) : null}
      {!hosted && plan.bridgeOk === null ? (
        <p className="muted">Comprobando puente local…</p>
      ) : null}
      {plan.error ? <p className="callout bad">{plan.error}</p> : null}
      {!hosted ? (
        <button
          className={`btn chatgpt-signin${variant === "hero" ? " hero" : ""}`}
          type="button"
          disabled={plan.loading || bridgeDown}
          onClick={() => void plan.connect().catch(() => undefined)}
        >
          {plan.loading ? "Conectando…" : "Continuar con ChatGPT"}
        </button>
      ) : null}
      {variant === "hero" && !hosted ? (
        <p className="muted">
          Cada cuenta de Smart Books conecta su propio ChatGPT (Plus/Go/Pro cuando el plan lo permita).
          Sign in with ChatGPT oficial: tus libros y tu uso de IA no se comparten con otros usuarios.
        </p>
      ) : null}
    </div>
  );
}
