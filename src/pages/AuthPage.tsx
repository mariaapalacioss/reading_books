import { FormEvent, useState } from "react";
import { AuthShell } from "../components/AuthShell";
import { ChatGptConnect } from "../components/ChatGptConnect";
import { supabase } from "../lib/supabase";

function UserIcon() {
  return (
    <svg className="login-input-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 12a4 4 0 1 0-4-4 4 4 0 0 0 4 4zm0 2c-4.42 0-8 2.24-8 5v1h16v-1c0-2.76-3.58-5-8-5z" />
    </svg>
  );
}

function LockIcon() {
  return (
    <svg className="login-input-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M17 9h-1V7a4 4 0 0 0-8 0v2H7a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8a2 2 0 0 0-2-2zm-3 0H10V7a2 2 0 1 1 4 0z" />
    </svg>
  );
}

export function AuthPage() {
  const [mode, setMode] = useState<"entrar" | "crear">("entrar");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!supabase) return;
    setBusy(true);
    setError("");
    setMessage("");
    const result = mode === "entrar"
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({
        email,
        password,
        options: { data: { display_name: name || email.split("@")[0] } },
      });
    setBusy(false);
    if (result.error) {
      setError(result.error.message);
      return;
    }
    if (mode === "crear" && !result.data.session) {
      setMessage("Cuenta creada. Si la confirmación por correo está activa, abre el enlace antes de entrar.");
    }
  };

  return (
    <AuthShell
      title="Bienvenida de vuelta"
      subtitle="Entra a tu biblioteca privada. Cada usuario tiene sus libros y datos separados."
    >
      <div className="login-divider">Acceso a tu biblioteca</div>

      <form onSubmit={submit}>
        <div className="seg login-seg" role="group" aria-label="Modo de acceso">
          <button type="button" aria-pressed={mode === "entrar"} onClick={() => setMode("entrar")}>Entrar</button>
          <button type="button" aria-pressed={mode === "crear"} onClick={() => setMode("crear")}>Crear cuenta</button>
        </div>

        {mode === "crear" ? (
          <label className="login-field">
            <span className="login-label">Nombre</span>
            <div className="login-input-wrap">
              <UserIcon />
              <input className="login-control" value={name} onChange={(event) => setName(event.target.value)} placeholder="Tu nombre" autoComplete="name" />
            </div>
          </label>
        ) : null}

        <label className="login-field">
          <span className="login-label">Correo</span>
          <div className="login-input-wrap">
            <UserIcon />
            <input className="login-control" type="email" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="tu@correo.com" autoComplete="username" />
          </div>
        </label>

        <label className="login-field">
          <span className="login-label">Contraseña</span>
          <div className="login-input-wrap">
            <LockIcon />
            <input className="login-control" type="password" required minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Ingresa tu contraseña" autoComplete={mode === "entrar" ? "current-password" : "new-password"} />
          </div>
        </label>

        {error ? <p className="callout bad">{error}</p> : null}
        {message ? <p className="callout good">{message}</p> : null}

        <button className="login-submit-btn" disabled={busy} type="submit">
          {busy ? "Espera…" : mode === "entrar" ? "Iniciar sesión" : "Crear cuenta"}
        </button>
      </form>

      <div className="login-divider">ChatGPT Plus (opcional)</div>
      <ChatGptConnect variant="hero" placement="login" />
    </AuthShell>
  );
}
