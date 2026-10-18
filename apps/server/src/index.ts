import { trpcServer } from "@hono/trpc-server";
import { createContext } from "@sorcerer/api/context";
import { appRouter } from "@sorcerer/api/routers/index";
import { env } from "@sorcerer/env/server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { getMonitor } from "./shared/getmonitor";

void getMonitor;

const app = new Hono();

app.use(logger());
app.use(
  "/*",
  cors({
    origin: env.CORS_ORIGIN,
    allowMethods: ["GET", "POST", "OPTIONS"],
  }),
);

app.use(
  "/trpc/*",
  trpcServer({
    router: appRouter,
    createContext: (_opts, context) => {
      return createContext({ context });
    },
  }),
);

app.get("/", (c) => {
  return c.text("OK");
});

export default app;
