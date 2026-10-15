import {
  CHATGPT_MODELS_URL,
  CHATGPT_RESPONSES_URL,
} from "./constants";
import { refreshAccessToken } from "./bridge";
import {
  loadCredentials,
  saveCredentials,
  credentialsFromTokenResponse,
  type ChatGptCredentials,
} from "./credentials";

let refreshPromise: Promise<ChatGptCredentials> | null = null;

export async function getCredentials(): Promise<ChatGptCredentials | null> {
  return loadCredentials();
}

export async function ensureAccessToken(): Promise<string> {
  const current = await loadCredentials();
  if (!current) throw new Error("Conecta tu ChatGPT Plus con «Continuar con ChatGPT».");
  if (Date.now() < current.expires_at) return current.access_token;

  if (!refreshPromise) {
    refreshPromise = (async () => {
      const fresh = await loadCredentials();
      if (!fresh) throw new Error("Sesión de ChatGPT no encontrada.");
      const token = await refreshAccessToken({
        clientId: fresh.client_id,
        refreshToken: fresh.refresh_token,
      });
      const next = credentialsFromTokenResponse({
        token,
        clientId: fresh.client_id,
        hostId: fresh.ext_agent_host_id,
        email: fresh.email,
        subject: fresh.subject,
      });
      await saveCredentials(next);
      return next;
    })().finally(() => { refreshPromise = null; });
  }
  const updated = await refreshPromise;
  return updated.access_token;
}

export type PlanModel = { slug: string; display_name: string };

export async function listPlanModels(): Promise<PlanModel[]> {
  const token = await ensureAccessToken();
  const response = await fetch(CHATGPT_MODELS_URL, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error("No se pudo listar modelos de tu plan ChatGPT.");
  const payload = await response.json() as { models?: { slug: string; display_name?: string; visibility?: string }[] };
  return (payload.models ?? [])
    .filter((model) => model.visibility === "list")
    .map((model) => ({ slug: model.slug, display_name: model.display_name || model.slug }));
}

let preferredModel: string | null = null;

export function resetPreferredModel() {
  preferredModel = null;
}

export async function getPreferredModel() {
  if (preferredModel) return preferredModel;
  const models = await listPlanModels();
  const pick = models.find((model) => /gpt-4|gpt-5|sol|o4|mini/i.test(model.slug)) ?? models[0];
  if (!pick) throw new Error("Tu cuenta ChatGPT no devolvió modelos disponibles para Smart Books.");
  preferredModel = pick.slug;
  return preferredModel;
}

type InputItem = { role: "user" | "assistant" | "developer"; content: string };

export async function streamPlanResponse(input: {
  instructions: string;
  input: InputItem[];
  onDelta: (text: string) => void;
}) {
  const token = await ensureAccessToken();
  const model = await getPreferredModel();
  const response = await fetch(CHATGPT_RESPONSES_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "text/event-stream",
    },
    body: JSON.stringify({
      model,
      instructions: input.instructions,
      input: input.input,
      store: false,
      stream: true,
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(err || `ChatGPT plan HTTP ${response.status}`);
  }
  if (!response.body) throw new Error("La respuesta no llegó en streaming.");

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let completed = false;
  let eventName = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) {
        eventName = "";
        continue;
      }
      if (trimmed.startsWith("event:")) {
        eventName = trimmed.slice(6).trim();
        continue;
      }
      if (!trimmed.startsWith("data:")) continue;
      const data = trimmed.slice(5).trim();
      if (!data || data === "[DONE]") continue;
      try {
        const event = JSON.parse(data) as { type?: string; delta?: string; response?: { error?: { code?: string } } };
        const type = event.type || eventName;
        if (type === "response.output_text.delta" && event.delta) {
          input.onDelta(event.delta);
        } else if (type === "response.failed") {
          const code = event.response?.error?.code ?? "unknown_error";
          throw new Error(`ChatGPT plan: ${code}`);
        } else if (type === "response.completed") {
          completed = true;
        }
      } catch (error) {
        if (error instanceof SyntaxError) continue;
        throw error;
      }
    }
  }
  if (!completed) throw new Error("La respuesta se interrumpió antes de completarse.");
}

export async function completePlanText(input: {
  instructions: string;
  input: InputItem[];
}) {
  let text = "";
  await streamPlanResponse({
    ...input,
    onDelta: (delta) => { text += delta; },
  });
  return text.trim();
}

export async function completePlanJson<T>(input: {
  instructions: string;
  user: string;
}) {
  const raw = await completePlanText({
    instructions: `${input.instructions}\nResponde únicamente con JSON válido, sin markdown.`,
    input: [{ role: "user", content: input.user }],
  });
  const cleaned = raw.replace(/^```json\s*/i, "").replace(/```\s*$/i, "").trim();
  return JSON.parse(cleaned) as T;
}
