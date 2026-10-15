import { Link, NavLink } from "react-router-dom";
import { ThemeSwitch } from "./ThemeSwitch";
import { useChatGptPlan } from "../lib/chatgpt/ChatGptPlanProvider";
import { supabase } from "../lib/supabase";

export function Brand() {
  return (
    <Link to="/" className="brand">
      <img src={`${import.meta.env.BASE_URL}brand/logo-bookifi.svg`} alt="Bookifi" />
      <span className="brand-name">
        <strong>Smart Books</strong>
        <span>by Bookifi</span>
      </span>
    </Link>
  );
}

export function TopBar({ name }: { name?: string }) {
  const plan = useChatGptPlan();
  const signOut = () => {
    void plan.disconnect().finally(() => void supabase?.auth.signOut());
  };
  return (
    <header className="topbar">
      <Brand />
      <nav className="top-nav" aria-label="Principal">
        <NavLink to="/" end>Biblioteca</NavLink>
        <NavLink to="/buscar">Buscar</NavLink>
      </nav>
      <div className="top-actions">
        {plan.connected && plan.model ? (
          <span className="chip teal">Plus · {plan.model}</span>
        ) : (
          <Link className="btn-ghost" to="/conectar-chatgpt">Conectar ChatGPT</Link>
        )}
        {name ? <span className="muted">{name}</span> : null}
        <ThemeSwitch />
        {supabase ? (
          <button className="btn-ghost" type="button" onClick={signOut}>Salir</button>
        ) : null}
      </div>
    </header>
  );
}
