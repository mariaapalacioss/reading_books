import { ThemeSwitch } from "../components/ThemeSwitch";

export function SetupPage() {
  return (
    <main className="auth-wrap">
      <section className="card auth-card stack">
        <img src={`${import.meta.env.BASE_URL}brand/logo-bookifi.svg`} alt="Bookifi" width={140} />
        <div>
          <h1>Smart Books</h1>
          <p className="muted">La interfaz está lista. Falta conectar Supabase para guardar los libros de forma privada.</p>
        </div>
        <div className="callout stack">
          <strong>Configuración pendiente</strong>
          <p>Copia <code>.env.example</code> a <code>.env</code> y completa <code>VITE_SUPABASE_URL</code> y <code>VITE_SUPABASE_ANON_KEY</code>.</p>
          <p>La clave de OpenAI no va en este archivo. Se configura como secreto de las Edge Functions, junto con <code>OPENAI_MODEL</code>.</p>
          <p>Sin esas credenciales no se muestra ningún análisis: Smart Books no simula resaltados.</p>
        </div>
        <ThemeSwitch />
      </section>
    </main>
  );
}
