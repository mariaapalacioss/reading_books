import {
  CHATGPT_AGENT_NAME,
  CHATGPT_AUTH_URL,
  CHATGPT_PLAN_SCOPE,
  CHATGPT_RESOURCE,
} from "./constants";
import { bridgeHealthy, exchangeAuthorizationCode } from "./bridge";
import { credentialsFromTokenResponse, loadCredentials, saveCredentials } from "./credentials";
import { requireSmartBooksUserId } from "./sessionUser";
import { getOrCreateHostId } from "./hostId";
import { createPkce, randomState } from "./pkce";
import { resetPreferredModel } from "./planApi";

const PENDING_KEY = "smartbooks_oauth_pending";

type PendingOAuth = {
  state: string;
  verifier: string;
  clientId: string;
  hostId: string;
  smartbooksUserId: string;
};

function decodeJwtPayload(token: string) {
  const part = token.split(".")[1];
  if (!part) return null;
  const json = atob(part.replace(/-/g, "+").replace(/_/g, "/"));
  return JSON.parse(json) as { sub?: string; email?: string };
}

function savePending(pending: PendingOAuth) {
  sessionStorage.setItem(PENDING_KEY, JSON.stringify(pending));
}

function loadPending(): PendingOAuth | null {
  const raw = sessionStorage.getItem(PENDING_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as PendingOAuth;
  } catch {
    return null;
  }
}

function clearPending() {
  sessionStorage.removeItem(PENDING_KEY);
}

export async function signInWithChatGpt(): Promise<void> {
  if (!(await bridgeHealthy())) {
    throw new Error(
      "El puente OAuth local no está activo. Ejecuta: npm run dev (incluye el puente en 127.0.0.1:1455).",
    );
  }

  const smartbooksUserId = await requireSmartBooksUserId();
  const existing = await loadCredentials(smartbooksUserId);
  const hostId = getOrCreateHostId();
  const { verifier, challenge } = await createPkce();
  const state = randomState();
  const clientId = existing?.client_id || "dynamic_agent_client";

  savePending({ state, verifier, clientId, hostId, smartbooksUserId });

  const params = new URLSearchParams({
    client_id: clientId,
    response_type: "code",
    redirect_uri: "http://127.0.0.1:1455/auth/callback",
    scope: ["openid", "profile", "email", "offline_access", "resource.invoke", CHATGPT_PLAN_SCOPE].join(" "),
    resource: CHATGPT_RESOURCE,
    state,
    nonce: randomState(),
    code_challenge_method: "S256",
    code_challenge: challenge,
    ext_agent_host_id: hostId,
  });
  if (!existing) params.set("agent_name_hint", CHATGPT_AGENT_NAME);
  else if (existing.id_token) params.set("id_token_hint", existing.id_token);
  if (existing?.email) params.set("login_hint", existing.email);

  const popup = window.open(`${CHATGPT_AUTH_URL}?${params.toString()}`, "smartbooks_chatgpt_oauth", "width=520,height=720");
  if (!popup) throw new Error("Permite ventanas emergentes para conectar ChatGPT.");

  await new Promise<void>((resolve, reject) => {
    const timeout = window.setTimeout(() => {
      window.removeEventListener("message", onMessage);
      reject(new Error("Tiempo agotado al iniciar sesión con ChatGPT."));
    }, 120_000);

    const onMessage = (event: MessageEvent) => {
      const data = event.data as { source?: string; error?: string; state?: string; code?: string; clientId?: string };
      if (data?.source !== "smartbooks-oauth") return;
      window.clearTimeout(timeout);
      window.removeEventListener("message", onMessage);
      if (data.error) {
        reject(new Error("Autorización cancelada."));
        return;
      }
      void finishOAuth(data.state || "", data.code || "", data.clientId || clientId)
        .then(resolve)
        .catch(reject);
    };
    window.addEventListener("message", onMessage);
  });
}

async function finishOAuth(state: string, code: string, issuedClientId: string) {
  const pending = loadPending();
  clearPending();
  if (!pending || pending.state !== state) throw new Error("Estado OAuth inválido. Intenta de nuevo.");
  const clientId = issuedClientId && issuedClientId !== "dynamic_agent_client" ? issuedClientId : pending.clientId;
  const token = await exchangeAuthorizationCode({
    code,
    codeVerifier: pending.verifier,
    clientId,
  });
  const idToken = String(token.id_token ?? "");
  const claims = idToken ? decodeJwtPayload(idToken) : null;
  const record = credentialsFromTokenResponse({
    token,
    clientId,
    hostId: pending.hostId,
    email: claims?.email ?? null,
    subject: claims?.sub ?? null,
    smartbooksUserId: pending.smartbooksUserId,
  });
  await saveCredentials(record, pending.smartbooksUserId);
}

export async function signOutChatGpt(userId?: string | null) {
  const { clearCredentials } = await import("./credentials");
  await clearCredentials(userId ?? undefined);
  resetPreferredModel();
}
