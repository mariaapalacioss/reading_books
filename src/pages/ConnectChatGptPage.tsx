import { Link } from "react-router-dom";
import { AuthShell } from "../components/AuthShell";
import { ChatGptConnect } from "../components/ChatGptConnect";

export function ConnectChatGptPage() {
  return (
    <AuthShell
      title="Conectar ChatGPT Plus"
      subtitle="Autoriza tu suscripción para resúmenes, chat contextual y análisis del PDF."
      showPillars={false}
      trustText="Sign in with ChatGPT · uso personal con puente local"
    >
      <ChatGptConnect variant="hero" />
      <p className="login-subheading" style={{ marginTop: 16 }}>
        <Link to="/">← Volver a la biblioteca</Link>
      </p>
    </AuthShell>
  );
}
