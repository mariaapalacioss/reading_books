import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/source-sans-3/400.css";
import "@fontsource/source-sans-3/600.css";
import "@fontsource/source-sans-3/700.css";
import "@fontsource/source-serif-4/500.css";
import "@fontsource/source-serif-4/600.css";
import { App } from "./App";
import { ChatGptPlanProvider } from "./lib/chatgpt/ChatGptPlanProvider";
import { ThemeProvider } from "./theme/ThemeProvider";
import "./styles/global.css";
import "./styles/notario-auth.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <ChatGptPlanProvider>
        <App />
      </ChatGptPlanProvider>
    </ThemeProvider>
  </StrictMode>,
);
