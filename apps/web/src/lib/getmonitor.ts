import { GetMonitor } from "@getmonitor/browser";
import { env } from "@sorcerer/env/web";

if (typeof window !== "undefined" && env.VITE_GETMONITOR_API_KEY) {
  GetMonitor.init(env.VITE_GETMONITOR_API_KEY, {
    environment: import.meta.env.MODE,
    apiHost: "http://ingest.getmonitor.io",
    // Avoid duplicate events: React logs boundary catches via console.error.
    captureConsoleErrors: false,
  });
}
