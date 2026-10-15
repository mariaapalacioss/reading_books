import type { ReactNode } from "react";
import { ThemeSwitch } from "./ThemeSwitch";

function ShieldIcon() {
  return (
    <svg className="login-pillars-sep__icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 2 4 5v6c0 5.25 3.4 10.15 8 11.35 4.6-1.2 8-6.1 8-11.35V5l-8-3zm0 2.2 6 2.25V11c0 4.2-2.65 8.15-6 9.2-3.35-1.05-6-5-6-9.2V6.45l6-2.25z" />
    </svg>
  );
}

export function AuthShell({
  title,
  subtitle,
  children,
  showPillars = true,
  trustText = "Lectura segura · Supabase · IA con tu plan ChatGPT Plus",
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
  showPillars?: boolean;
  trustText?: string;
}) {
  const logo = `${import.meta.env.BASE_URL}brand/logo-bookifi.svg`;
  return (
    <main className="login-page login-page--notarial">
      <div className="login-page__inner">
        <section className="login-card">
          <div className="login-card__top">
            <div className="login-brand-header">
              <div className="login-brand-logo-box">
                <img src={logo} alt="Bookifi" />
              </div>
              <div>
                <span className="login-brand-name">Smart Books</span>
                <span className="login-brand-tagline">Lectura académica inteligente · Bookifi</span>
              </div>
            </div>
            <ThemeSwitch className="login-theme-compact" />
          </div>

          <header className="login-header">
            <h1 className="login-heading">{title}</h1>
            <p className="login-subheading">{subtitle}</p>
          </header>

          {children}

          {showPillars ? (
            <>
              <div className="login-pillars-sep">
                <span className="login-pillars-sep__line" />
                <ShieldIcon />
                <span className="login-pillars-sep__line" />
              </div>
              <div className="login-pillars">
                <div className="login-pillars__item">
                  <span className="login-pillars__glyph">PDF</span>
                  <span>Documentos</span>
                </div>
                <div className="login-pillars__divider" />
                <div className="login-pillars__item">
                  <span className="login-pillars__glyph">IA</span>
                  <span>Asistencia</span>
                </div>
                <div className="login-pillars__divider" />
                <div className="login-pillars__item">
                  <span className="login-pillars__glyph">HL</span>
                  <span>Resaltados</span>
                </div>
              </div>
            </>
          ) : null}
        </section>
        <p className="login-trust-banner">{trustText}</p>
      </div>
    </main>
  );
}
