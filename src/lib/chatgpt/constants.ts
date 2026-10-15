export const CHATGPT_AGENT_NAME = "Smart Books";
export function chatgptBridgeUrl() {
  const configured = import.meta.env.VITE_CHATGPT_BRIDGE_URL?.trim();
  if (configured) return configured;
  if (import.meta.env.DEV && typeof window !== "undefined") {
    return `${window.location.origin}/oauth-bridge`;
  }
  return "http://127.0.0.1:1455";
}
export const CHATGPT_AUTH_URL = "https://auth.openai.com/api/accounts/authorize";
export const CHATGPT_RESOURCE = "https://api.openai.com/v1";
export const CHATGPT_RESPONSES_URL = "https://api.openai.com/v1/responses";
export const CHATGPT_MODELS_URL = "https://api.openai.com/v1/models";
export const CHATGPT_PLAN_SCOPE = "chatgpt.tokens.use.direct";
export const CREDENTIALS_DB = "smartbooks-chatgpt";
export const CREDENTIALS_STORE = "credentials";
