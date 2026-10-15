/** App servida en GitHub Pages u otro host público (no localhost). */
export function isPublicWebDeploy() {
  if (typeof window === "undefined") return import.meta.env.PROD;
  const host = window.location.hostname;
  if (host === "localhost" || host === "127.0.0.1") return false;
  return import.meta.env.PROD || host.endsWith(".github.io");
}

export function isLocalDevHost() {
  if (typeof window === "undefined") return import.meta.env.DEV;
  const host = window.location.hostname;
  return host === "localhost" || host === "127.0.0.1";
}
