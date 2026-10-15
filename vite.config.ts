import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const base = process.env.VITE_BASE || "/";

export default defineConfig({
  base,
  plugins: [react()],
  build: {
    outDir: "dist",
    sourcemap: true,
  },
  server: {
    port: 5173,
    proxy: {
      "/oauth-bridge": {
        target: "http://127.0.0.1:1455",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/oauth-bridge/, ""),
      },
    },
  },
});
