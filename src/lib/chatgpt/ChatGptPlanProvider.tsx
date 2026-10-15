import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { useSession } from "../session";
import { bridgeHealthy } from "./bridge";
import { hasPlanUsage, loadCredentials, setCredentialUserId, type ChatGptCredentials } from "./credentials";
import { getPreferredModel, resetPreferredModel } from "./planApi";
import { clearAssistCacheAll } from "./assistCache";
import { signInWithChatGpt, signOutChatGpt } from "./auth";
import { isPublicWebDeploy } from "./environment";

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
  const session = useSession();
  const userId = session?.user?.id ?? null;
  const [credentials, setCredentials] = useState<ChatGptCredentials | null>(null);
  const [bridgeOk, setBridgeOk] = useState<boolean | null>(null);
  const [model, setModel] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    setCredentialUserId(userId);
    if (!userId) {
      setCredentials(null);
      setModel(null);
      resetPreferredModel();
      clearAssistCacheAll();
    } else {
      clearAssistCacheAll();
    }
  }, [userId]);

  const refresh = useCallback(async () => {
    if (isPublicWebDeploy()) {
      setBridgeOk(null);
    } else {
      setBridgeOk(await bridgeHealthy());
    }
    if (!userId) {
      setCredentials(null);
      setModel(null);
      return;
    }
    setCredentialUserId(userId);
    const next = await loadCredentials(userId);
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
  }, [userId]);

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => { void refresh(); }, 8000);
    return () => window.clearInterval(timer);
  }, [refresh]);

  const connect = useCallback(async () => {
    if (!userId) throw new Error("Crea una cuenta o entra en Smart Books antes de conectar ChatGPT.");
    setLoading(true);
    setError("");
    try {
      await signInWithChatGpt();
      resetPreferredModel();
      await refresh();
      const saved = await loadCredentials(userId);
      if (!saved || !hasPlanUsage(saved)) {
        throw new Error("No se autorizó el uso del plan ChatGPT. Vuelve a conectar y acepta los permisos.");
      }
      setModel(await getPreferredModel());
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "No se pudo conectar ChatGPT.");
      throw reason;
    } finally {
      setLoading(false);
    }
  }, [refresh, userId]);

  const disconnect = useCallback(async () => {
    if (userId) await signOutChatGpt(userId);
    resetPreferredModel();
    setCredentials(null);
    setModel(null);
  }, [userId]);

  const value = useMemo<ChatGptPlanContextValue>(() => ({
    credentials,
    connected: Boolean(userId && credentials && hasPlanUsage(credentials)),
    bridgeOk,
    model,
    loading,
    error,
    connect,
    disconnect,
    refresh,
  }), [credentials, bridgeOk, model, loading, error, connect, disconnect, refresh, userId]);

  return <ChatGptPlanContext.Provider value={value}>{children}</ChatGptPlanContext.Provider>;
}

export function useChatGptPlan() {
  const ctx = useContext(ChatGptPlanContext);
  if (!ctx) throw new Error("useChatGptPlan debe usarse dentro de ChatGptPlanProvider.");
  return ctx;
}
