import { BrowserRouter, Navigate, Outlet, Route, Routes } from "react-router-dom";
import { TopBar } from "./components/Shell";
import { useSession } from "./lib/session";
import { isConfigured } from "./lib/supabase";
import { AuthPage } from "./pages/AuthPage";
import { ConnectChatGptPage } from "./pages/ConnectChatGptPage";
import { LibraryPage } from "./pages/LibraryPage";
import { ReaderPage } from "./pages/ReaderPage";
import { ReviewPage } from "./pages/ReviewPage";
import { SearchPage } from "./pages/SearchPage";
import { SetupPage } from "./pages/SetupPage";

const basename = import.meta.env.BASE_URL.replace(/\/$/, "");

export function App() {
  return (
    <BrowserRouter basename={basename}>
      <Gate />
    </BrowserRouter>
  );
}

function Gate() {
  const session = useSession();
  if (!isConfigured) return <SetupPage />;
  if (session === undefined) return <main className="page"><p>Abriendo Smart Books…</p></main>;
  if (!session) return <AuthPage />;
  const name = typeof session.user.user_metadata?.display_name === "string"
    ? session.user.user_metadata.display_name
    : undefined;
  return (
    <Routes>
      <Route path="/leer/:bookId" element={<ReaderPage />} />
      <Route path="/conectar-chatgpt" element={<ConnectChatGptPage />} />
      <Route element={<ShellLayout name={name} />}>
        <Route path="/" element={<LibraryPage />} />
        <Route path="/buscar" element={<SearchPage />} />
        <Route path="/revisar/:bookId" element={<ReviewPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}

function ShellLayout({ name }: { name?: string }) {
  return (
    <div className="app-shell">
      <a className="skip" href="#contenido">Saltar al contenido</a>
      <TopBar name={name} />
      <div id="contenido">
        <Outlet />
      </div>
    </div>
  );
}
