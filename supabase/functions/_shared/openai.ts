import OpenAI from "npm:openai";

export function openAiConfig(): { apiKey: string; model: string; embeddingModel: string } | { error: string } {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL");
  const embeddingModel = Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "";
  if (!apiKey || !model) {
    return {
      error: "Falta configurar OPENAI_API_KEY y OPENAI_MODEL como secretos de la función. No se inventó ningún análisis.",
    };
  }
  return { apiKey, model, embeddingModel };
}

export function openAiClient(apiKey: string) {
  return new OpenAI({ apiKey });
}

export async function withRetries<T>(work: () => Promise<T>, attempts = 3): Promise<T> {
  let last: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await work();
    } catch (error) {
      last = error;
      const status = typeof error === "object" && error && "status" in error ? Number(error.status) : 0;
      const retry = status === 429 || status >= 500 || status === 0;
      if (!retry || attempt === attempts - 1) throw error;
      await new Promise((resolve) => setTimeout(resolve, 400 * 2 ** attempt));
    }
  }
  throw last;
}

export async function structuredResponse<T>(
  client: OpenAI,
  model: string,
  name: string,
  schema: Record<string, unknown>,
  instructions: string,
  content: string,
): Promise<T> {
  const response = await withRetries(() =>
    client.responses.create({
      model,
      input: [
        { role: "system", content: instructions },
        { role: "user", content },
      ],
      text: {
        format: {
          type: "json_schema",
          name,
          strict: true,
          schema,
        },
      },
    })
  );
  const text = response.output_text;
  if (!text) throw new Error("OpenAI no devolvió una respuesta estructurada.");
  return JSON.parse(text) as T;
}

export async function chatResponse(
  client: OpenAI,
  model: string,
  input: { role: "system" | "user" | "assistant"; content: string }[],
): Promise<string> {
  const response = await withRetries(() =>
    client.responses.create({ model, input }),
  );
  const text = response.output_text?.trim();
  if (!text) throw new Error("OpenAI no devolvió una respuesta.");
  return text;
}
