import { CHATGPT_PLAN_SCOPE, CREDENTIALS_DB, CREDENTIALS_STORE } from "./constants";

export type ChatGptCredentials = {
  email: string | null;
  subject: string | null;
  client_id: string;
  ext_agent_host_id: string;
  id_token: string;
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_at: number;
  scopes: string[];
  saved_at: string;
};

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(CREDENTIALS_DB, 1);
    request.onerror = () => reject(request.error ?? new Error("No se pudo abrir credenciales."));
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(CREDENTIALS_STORE)) {
        db.createObjectStore(CREDENTIALS_STORE);
      }
    };
  });
}

const RECORD_KEY = "default";

export async function loadCredentials(): Promise<ChatGptCredentials | null> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(CREDENTIALS_STORE, "readonly");
    const request = tx.objectStore(CREDENTIALS_STORE).get(RECORD_KEY);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      db.close();
      resolve((request.result as ChatGptCredentials | undefined) ?? null);
    };
  });
}

export async function saveCredentials(record: ChatGptCredentials) {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(CREDENTIALS_STORE, "readwrite");
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onerror = () => reject(tx.error);
    tx.objectStore(CREDENTIALS_STORE).put(record, RECORD_KEY);
  });
}

export async function clearCredentials() {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(CREDENTIALS_STORE, "readwrite");
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onerror = () => reject(tx.error);
    tx.objectStore(CREDENTIALS_STORE).delete(RECORD_KEY);
  });
}

export function credentialsFromTokenResponse(input: {
  token: Record<string, unknown>;
  clientId: string;
  hostId: string;
  email?: string | null;
  subject?: string | null;
}): ChatGptCredentials {
  const scopeRaw = String(input.token.scope ?? "");
  const scopes = scopeRaw.split(/[\s+]+/).filter(Boolean);
  const expiresIn = Number(input.token.expires_in ?? 3600);
  return {
    email: input.email ?? null,
    subject: input.subject ?? null,
    client_id: input.clientId,
    ext_agent_host_id: input.hostId,
    id_token: String(input.token.id_token ?? ""),
    access_token: String(input.token.access_token ?? ""),
    refresh_token: String(input.token.refresh_token ?? ""),
    token_type: String(input.token.token_type ?? "Bearer"),
    expires_at: Date.now() + expiresIn * 1000 - 60_000,
    scopes,
    saved_at: new Date().toISOString(),
  };
}

export function hasPlanUsage(credentials: ChatGptCredentials | null) {
  return Boolean(credentials?.scopes.includes(CHATGPT_PLAN_SCOPE));
}
