const KEY = "smartbooks_ext_agent_host_id";

export function getOrCreateHostId() {
  const existing = localStorage.getItem(KEY);
  if (existing) return existing;
  const id = `urn:uuid:${crypto.randomUUID()}`;
  localStorage.setItem(KEY, id);
  return id;
}
