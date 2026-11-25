import { createLogger, defineConfig, loadEnv, type ProxyOptions } from "vite";
import react from "@vitejs/plugin-react";

// In `npm run dev`, /api is proxied to the Phlio backend. Set VITE_API_PROXY
// (in admin/.env.local) to point somewhere specific; otherwise the first of
// these that answers /health is used: the backend's default port (8000) and
// the one the Flutter app's dart_defines.json uses (8002).
const CANDIDATES = ["http://127.0.0.1:8000", "http://127.0.0.1:8002"];

async function findBackend(): Promise<string | null> {
  for (const url of CANDIDATES) {
    try {
      const res = await fetch(`${url}/health`, { signal: AbortSignal.timeout(800) });
      if (res.ok) return url;
    } catch {
      /* not running there */
    }
  }
  return null;
}

export default defineConfig(async ({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  let target = env.VITE_API_PROXY?.replace(/\/$/, "");
  if (!target && command === "serve") target = (await findBackend()) ?? undefined;
  target ||= CANDIDATES[0];
  const port = new URL(target).port || "8000";

  let warned = 0;
  const proxy: ProxyOptions = {
    target,
    changeOrigin: true,
    ws: true,
    configure: (p) => {
      // One clear line instead of a stack trace per request, and a JSON error
      // the panel can show ("start the backend") instead of an empty 500.
      p.on("error", (err: NodeJS.ErrnoException, _req, res) => {
        if (Date.now() - warned > 10_000) {
          warned = Date.now();
          console.warn(
            `\n  [phlio-admin] Can't reach the Phlio API at ${target} (${err.code ?? err.message}).` +
              `\n  Start it from backend/:  uv run uvicorn app.main:app --reload --port ${port}` +
              `\n  or point the panel elsewhere with VITE_API_PROXY in admin/.env.local\n`,
          );
        }
        if (res && "writeHead" in res && !res.headersSent) {
          res.writeHead(502, { "Content-Type": "application/json" });
          res.end(JSON.stringify({
            error: { code: "backend_offline", message: `The Phlio API isn't running at ${target}. Start the backend, then reload this page.` },
          }));
        }
      });
    },
  };

  if (command === "serve") console.log(`  [phlio-admin] API proxy: /api → ${target}`);

  // Vite prints a stack trace for every failed proxy request; the handler
  // above already explains it once, so drop those.
  const logger = createLogger();
  const error = logger.error.bind(logger);
  logger.error = (msg, options) => {
    if (!msg.includes("http proxy error")) error(msg, options);
  };

  return {
    customLogger: logger,
    plugins: [react()],
    server: { port: 5174, proxy: { "/api": proxy } },
    preview: { port: 4173, proxy: { "/api": proxy } },
    build: { outDir: "dist", sourcemap: false, chunkSizeWarningLimit: 900 },
  };
});
