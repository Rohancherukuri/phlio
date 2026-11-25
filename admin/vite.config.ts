import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// VITE_API_URL points the panel at the Phlio backend (default: same origin,
// with /api proxied to a local backend during `npm run dev`).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    proxy: {
      "/api": { target: "http://localhost:8000", changeOrigin: true, ws: true },
    },
  },
  build: { outDir: "dist", sourcemap: false, chunkSizeWarningLimit: 900 },
});
