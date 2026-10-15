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
  /** Usuario de Smart Books que autorizó esta conexión. */
  smartbooks_user_id: string;
};

const LEGACY_KEY = "default";
const DB_VERSION = 2;

let activeSmartBooksUserId: string | null = null;

/** Debe llamarse cuando cambia la sesión de Supabase (login / logout). */
export function setCredentialUserId(userId: string | null) {
  activeSmartBooksUserId = userId;
}

export function credentialStorageKey(userId: string) {
  return `user:${userId}`;
}

function resolveUserId(explicit?: string | null) {
  const id = explicit ?? activeSmartBooksUserId;
  if (!id) return null;
  return id;
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(CREDENTIALS_DB, DB_VERSION);
    request.onerror = () => reject(request.error ?? new Error("No se pudo abrir credenciales."));
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(CREDENTIALS_STORE)) {
        db.createObjectStore(CREDENTIALS_STORE);
      }
      if (request.transaction) {
        const store = request.transaction.objectStore(CREDENTIALS_STORE);
        store.delete(LEGACY_KEY);
      }
    };
  });
}

export async function loadCredentials(userId?: string | null): Promise<ChatGptCredentials | null> {
  const id = resolveUserId(userId);
  if (!id) return null;
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(CREDENTIALS_STORE, "readonly");
    const request = tx.objectStore(CREDENTIALS_STORE).get(credentialStorageKey(id));
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      db.close();
      const row = request.result as ChatGptCredentials | undefined;
      if (!row) {
        resolve(null);
        return;
      }
      if (row.smartbooks_user_id && row.smartbooks_user_id !== id) {
        resolve(null);
        return;
      }
      resolve(row);
    };
  });
}

export async function saveCredentials(record: ChatGptCredentials, userId?: string | null) {
  const id = resolveUserId(userId ?? record.smartbooks_user_id);
  if (!id) throw new Error("Inicia sesión en Smart Books antes de conectar ChatGPT.");
  const db = await openDb();
  const payload: ChatGptCredentials = { ...record, smartbooks_user_id: id };
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(CREDENTIALS_STORE, "readwrite");
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onerror = () => reject(tx.error);
    tx.objectStore(CREDENTIALS_STORE).put(payload, credentialStorageKey(id));
  });
}

export async function clearCredentials(userId?: string | null) {
  const id = resolveUserId(userId);
  if (!id) return;
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(CREDENTIALS_STORE, "readwrite");
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onerror = () => reject(tx.error);
    tx.objectStore(CREDENTIALS_STORE).delete(credentialStorageKey(id));
  });
}

export function credentialsFromTokenResponse(input: {
  token: Record<string, unknown>;
  clientId: string;
  hostId: string;
  email?: string | null;
  subject?: string | null;
  smartbooksUserId: string;
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
    smartbooks_user_id: input.smartbooksUserId,
  };
}

export function hasPlanUsage(credentials: ChatGptCredentials | null) {
  return Boolean(credentials?.scopes.includes(CHATGPT_PLAN_SCOPE));
}
