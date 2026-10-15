#!/usr/bin/env node
/**
 * Puente local oficial para Sign in with ChatGPT (open-source / agent host).
 * Escucha en 127.0.0.1 — requerido por OpenAI para el callback loopback.
 */
import http from "node:http";
import { URL } from "node:url";

const HOST = "127.0.0.1";
const PORT = Number(process.env.SMARTBOOKS_OAUTH_PORT || 1455);
const REDIRECT_PATH = "/auth/callback";
const REDIRECT_URI = `http://${HOST}:${PORT}${REDIRECT_PATH}`;
const TOKEN_URL = "https://auth.openai.com/api/accounts/oauth/token";
const RESOURCE = "https://api.openai.com/v1";

async function exchangeToken(body) {
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload.error_description || payload.error || `Token HTTP ${response.status}`;
    throw new Error(message);
  }
  return payload;
}

function htmlPage(title, body) {
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"/><title>${title}</title></head><body>${body}</body></html>`;
}

function corsHeaders(req) {
  const origin = req.headers.origin;
  const allowed = origin && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin) ? origin : "http://localhost:5173";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    Vary: "Origin",
  };
}

const server = http.createServer(async (req, res) => {
  const cors = corsHeaders(req);
  try {
    const url = new URL(req.url || "/", `http://${HOST}:${PORT}`);

    if (req.method === "OPTIONS") {
      res.writeHead(204, cors);
      res.end();
      return;
    }

    if (req.method === "GET" && url.pathname === "/health") {
      res.writeHead(200, { ...cors, "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, redirectUri: REDIRECT_URI }));
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/refresh") {
      let raw = "";
      for await (const chunk of req) raw += chunk;
      const json = JSON.parse(raw || "{}");
      const payload = await exchangeToken({
        grant_type: "refresh_token",
        client_id: json.client_id,
        refresh_token: json.refresh_token,
        resource: RESOURCE,
      });
      res.writeHead(200, { ...cors, "content-type": "application/json" });
      res.end(JSON.stringify(payload));
      return;
    }

    if (req.method === "GET" && url.pathname === REDIRECT_PATH) {
      const error = url.searchParams.get("error");
      const state = url.searchParams.get("state") || "";
      if (error) {
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        res.end(htmlPage("Smart Books", `<p>Autorización cancelada (${error}). Puedes cerrar esta ventana.</p><script>window.opener?.postMessage({source:"smartbooks-oauth",error:${JSON.stringify(error)}}, "*");</script>`));
        return;
      }
      const code = url.searchParams.get("code");
      const issuedClientId = url.searchParams.get("client_id") || "";
      if (!code) {
        res.writeHead(400, { "content-type": "text/plain" });
        res.end("Falta code");
        return;
      }
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(htmlPage(
        "Smart Books",
        `<p>Conectando tu ChatGPT Plus…</p><script>
          window.opener?.postMessage({
            source: "smartbooks-oauth",
            state: ${JSON.stringify(state)},
            code: ${JSON.stringify(code)},
            clientId: ${JSON.stringify(issuedClientId)},
          }, "*");
          setTimeout(() => window.close(), 400);
        </script>`,
      ));
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/exchange") {
      let raw = "";
      for await (const chunk of req) raw += chunk;
      const json = JSON.parse(raw || "{}");
      const payload = await exchangeToken({
        grant_type: "authorization_code",
        client_id: json.client_id,
        code: json.code,
        redirect_uri: REDIRECT_URI,
        code_verifier: json.code_verifier,
        resource: RESOURCE,
      });
      res.writeHead(200, { ...cors, "content-type": "application/json" });
      res.end(JSON.stringify({ ...payload, redirect_uri: REDIRECT_URI }));
      return;
    }

    res.writeHead(404, { ...cors, "content-type": "text/plain" });
    res.end("Not found");
  } catch (error) {
    res.writeHead(500, { ...cors, "content-type": "application/json" });
    res.end(JSON.stringify({ error: error instanceof Error ? error.message : "Error del puente OAuth." }));
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Smart Books OAuth bridge → ${REDIRECT_URI}`);
});
