const memory = new Map<string, string>();
const inflight = new Map<string, Promise<string>>();

export function assistCacheKey(parts: Record<string, string | number | boolean | undefined>) {
  return Object.entries(parts)
    .filter(([, value]) => value !== undefined)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join("|");
}

export function readAssistCache(key: string) {
  return memory.get(key);
}

export function writeAssistCache(key: string, value: string) {
  memory.set(key, value);
}

export function runAssistOnce(key: string, job: () => Promise<string>) {
  const cached = memory.get(key);
  if (cached) return Promise.resolve(cached);

  const running = inflight.get(key);
  if (running) return running;

  const promise = job().then((text) => {
    memory.set(key, text);
    return text;
  }).finally(() => {
    inflight.delete(key);
  });
  inflight.set(key, promise);
  return promise;
}

export function clearAssistCacheForBook(bookId: string) {
  for (const key of memory.keys()) {
    if (key.includes(`bookId=${bookId}`)) memory.delete(key);
  }
}
