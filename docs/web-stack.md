# Web stack

Setup notes for the TypeScript side of the repo (landing page, API, database), scaffolded with [kubojs](https://github.com/albuquerquesz/kubo).

## Getting Started

First, install the dependencies:

```bash
bun install
```
## Database Setup

This project uses PostgreSQL with Drizzle ORM.

1. Make sure you have a PostgreSQL database set up.
2. Update your `apps/server/.env` file with your PostgreSQL connection details.

3. Apply the schema to your database:
```bash
bun run db:push
```





## GetMonitor Setup

This project includes the [GetMonitor JavaScript error-tracking SDK](https://github.com/get-monitor/getmonitor-js).

Keys are **optional for local first run** — the app starts without them and capture stays idle until you configure a project key.

1. Create a GetMonitor project and copy its public project key (`gm_xxx`).
2. Set the generated `.env` value ending in `GETMONITOR_API_KEY` for the web app and/or server when you are ready to send events.
3. Ingestion uses a fixed host (`http://ingest.getmonitor.io`) — no `apiHost` env var is required.
4. Optional (Next.js / Nuxt production builds): set `GETMONITOR_AUTH_TOKEN` (secret, never public) so source maps upload during `next build` / `nuxt build`.

Browser uncaught errors are captured after the client bootstrap runs. React apps also wrap the tree in `<GetMonitorErrorBoundary>`. Node server errors are captured when the server key is configured.

See the [browser](https://github.com/get-monitor/getmonitor-js/tree/main/packages/browser), [Node](https://github.com/get-monitor/getmonitor-js/tree/main/packages/node), [React](https://github.com/get-monitor/getmonitor-js/tree/main/packages/react), [Next.js](https://github.com/get-monitor/getmonitor-js/tree/main/packages/nextjs-config), and [Nuxt](https://github.com/get-monitor/getmonitor-js/tree/main/packages/nuxt) package guides.


## AraraHQ Setup

This project includes the official [AraraHQ Node SDK](https://docs.ararahq.com/sdks/node) for WhatsApp messaging.

1. Create an AraraHQ API key.
2. Set `ARARA_API_KEY` in `the server .env`.
3. Use the SDK only from server code. AraraHQ is not generated for browser code or Edge/Workers runtimes.
4. With Convex, call the generated `api.arara.execute` Node Action.

```ts
import { arara } from "@sorcerer/arara";

await arara.sendMessage({
  receiver: "whatsapp:+5511999999999",
  body: "Olá!",
});

await arara.getMessage("ara_msg_xxx");
await arara.listTemplates();
```

The package also exposes template creation and template-status helpers. See the [official SDK docs](https://docs.ararahq.com/sdks/node).


Then, run the development server:

```bash
bun run dev
```

Open [http://localhost:3001](http://localhost:3001) in your browser to see the web application.
The API is running at [http://localhost:3000](http://localhost:3000).

## UI Customization

React web apps in this stack share shadcn/ui primitives through `packages/ui`.

- Change design tokens and global styles in `packages/ui/src/styles/globals.css`
- Update shared primitives in `packages/ui/src/components/*`
- Adjust shadcn aliases or style config in `packages/ui/components.json` and `apps/web/components.json`

### Add more shared components

Run this from the project root to add more primitives to the shared UI package:

```bash
npx shadcn@latest add accordion dialog popover sheet table -c packages/ui
```

Import shared components like this:

```tsx
import { Button } from "@sorcerer/ui/components/button"
```

### Add app-specific blocks

If you want to add app-specific blocks instead of shared primitives, run the shadcn CLI from `apps/web`.



## Git Hooks and Formatting

- Run checks: `bun run check`



## Project Structure

```
sorcerer/
├── apps/
│   ├── web/         # Frontend application (React + TanStack Router)
│   └── server/      # Backend API (Hono, TRPC)
├── packages/
│   ├── ui/          # Shared shadcn/ui components and styles
│   ├── api/         # API layer / business logic
│   └── db/          # Database schema & queries
```

## Available Scripts

- `bun run dev`: Start all applications in development mode
- `bun run build`: Build all applications
- `bun run dev:web`: Start only the web application
- `bun run dev:server`: Start only the server
- `bun run check-types`: Check TypeScript types across all apps
- `bun run db:push`: Push schema changes to database
- `bun run db:generate`: Generate database client/types
- `bun run db:migrate`: Run database migrations
- `bun run db:studio`: Open database studio UI
- `bun run check`: Run Biome formatting and linting
