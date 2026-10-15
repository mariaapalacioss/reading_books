#!/usr/bin/env node
import { spawn } from "node:child_process";

const bridge = spawn(process.execPath, ["scripts/chatgpt-oauth-bridge.mjs"], {
  stdio: "inherit",
  env: process.env,
});

const vite = spawn(process.execPath, ["node_modules/vite/bin/vite.js"], {
  stdio: "inherit",
  env: process.env,
});

function shutdown(code = 0) {
  bridge.kill("SIGTERM");
  vite.kill("SIGTERM");
  process.exit(code);
}

process.on("SIGINT", () => shutdown(0));
process.on("SIGTERM", () => shutdown(0));
bridge.on("exit", (code) => { if (code) shutdown(code ?? 1); });
vite.on("exit", (code) => shutdown(code ?? 0));
