/// <reference types="vitest/config" />
import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// In development the Rails API is reached through this proxy, so the browser sees one origin and
// no CORS is needed. VITE_PROXY_TARGET points it at a Rails server (default: bin/rails s -p 3100).
// Production builds call VITE_API_URL directly (see src/lib/api.ts); Rails then allows the
// frontend origin through rack-cors (CORS_ORIGINS).
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const target = env.VITE_PROXY_TARGET || "http://127.0.0.1:3100";

  return {
    plugins: [react(), tailwindcss()],
    server: {
      port: 5173,
      proxy: {
        // SSE passes through the proxy unbuffered; Rails sets X-Accel-Buffering: no.
        "/api": { target, changeOrigin: true },
      },
    },
    preview: { port: 4173 },
    build: {
      rollupOptions: {
        output: {
          manualChunks(id: string) {
            if (id.includes("react-markdown") || id.includes("remark") || id.includes("micromark") || id.includes("mdast")) return "markdown";
          },
        },
      },
    },
    test: {
      environment: "node",
      include: ["src/**/*.test.ts"],
    },
  };
});
