import { chatgptBridgeUrl } from "./constants";

export async function bridgeHealthy() {
  try {
    const response = await fetch(`${chatgptBridgeUrl()}/health`, { method: "GET" });
    return response.ok;
  } catch {
    return false;
  }
}

export async function exchangeAuthorizationCode(input: {
  code: string;
  codeVerifier: string;
  clientId: string;
}) {
  const response = await fetch(`${chatgptBridgeUrl()}/api/exchange`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      code: input.code,
      code_verifier: input.codeVerifier,
      client_id: input.clientId,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(String(payload.error || "No se pudo completar el inicio de sesión con ChatGPT."));
  }
  return payload as Record<string, unknown>;
}

export async function refreshAccessToken(input: { clientId: string; refreshToken: string }) {
  const response = await fetch(`${chatgptBridgeUrl()}/api/refresh`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      client_id: input.clientId,
      refresh_token: input.refreshToken,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(String(payload.error || "No se pudo renovar la sesión de ChatGPT."));
  }
  return payload as Record<string, unknown>;
}
