import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { bridgeHealthy } from "./bridge";
import { hasPlanUsage, loadCredentials, type ChatGptCredentials } from "./credentials";
import { getPreferredModel, resetPreferredModel } from "./planApi";
import { signInWithChatGpt, signOutChatGpt } from "./auth";

type ChatGptPlanContextValue = {
  credentials: ChatGptCredentials | null;
  connected: boolean;
  bridgeOk: boolean | null;
  model: string | null;
  loading: boolean;
  error: string;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  refresh: () => Promise<void>;
};

const ChatGptPlanContext = createContext<ChatGptPlanContextValue | null>(null);

export function ChatGptPlanProvider({ children }: { children: ReactNode }) {
  const [credentials, setCredentials] = useState<ChatGptCredentials | null>(null);
  const [bridgeOk, setBridgeOk] = useState<boolean | null>(null);
  const [model, setModel] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const refresh = useCallback(async () => {
    setBridgeOk(await bridgeHealthy());
    const next = await loadCredentials();
    setCredentials(next);
    if (next && hasPlanUsage(next)) {
      try {
        setModel(await getPreferredModel());
      } catch {
        setModel(null);
      }
    } else {
      setModel(null);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => { void refresh(); }, 8000);
    return () => window.clearInterval(timer);
  }, [refresh]);

  const connect = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      await signInWithChatGpt();
      resetPreferredModel();
      await refresh();
      if (!(await loadCredentials()) || !hasPlanUsage(await loadCredentials())) {
        throw new Error("No se autorizó el uso del plan ChatGPT. Vuelve a conectar y acepta los permisos.");
      }
      setModel(await getPreferredModel());
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "No se pudo conectar ChatGPT.");
      throw reason;
    } finally {
      setLoading(false);
    }
  }, [refresh]);

  const disconnect = useCallback(async () => {
    await signOutChatGpt();
    resetPreferredModel();
    setCredentials(null);
    setModel(null);
  }, []);

  const value = useMemo<ChatGptPlanContextValue>(() => ({
    credentials,
    connected: Boolean(credentials && hasPlanUsage(credentials)),
    bridgeOk,
    model,
    loading,
    error,
    connect,
    disconnect,
    refresh,
  }), [credentials, bridgeOk, model, loading, error, connect, disconnect, refresh]);

  return <ChatGptPlanContext.Provider value={value}>{children}</ChatGptPlanContext.Provider>;
}

export function useChatGptPlan() {
  const ctx = useContext(ChatGptPlanContext);
  if (!ctx) throw new Error("useChatGptPlan debe usarse dentro de ChatGptPlanProvider.");
  return ctx;
}

