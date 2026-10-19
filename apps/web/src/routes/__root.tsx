import { Toaster } from "@sorcerer/ui/components/sonner";
import type { QueryClient } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import {
  createRootRouteWithContext,
  HeadContent,
  Outlet,
} from "@tanstack/react-router";
import { TanStackRouterDevtools } from "@tanstack/react-router-devtools";
import { ThemeProvider } from "@/components/theme-provider";
import type { trpc } from "@/utils/trpc";
import "../index.css";
import { GetMonitorErrorBoundary } from "@getmonitor/react";

export interface RouterAppContext {
  trpc: typeof trpc;
  queryClient: QueryClient;
}

export const Route = createRootRouteWithContext<RouterAppContext>()({
  component: RootComponent,
});

function GetMonitorOutlet() {
  return (
    <GetMonitorErrorBoundary
      fallback={(error, reset) => (
        <div>
          <p>Something went wrong.</p>
          <button type="button" onClick={reset}>
            Try again
          </button>
        </div>
      )}
    >
      <Outlet />
    </GetMonitorErrorBoundary>
  );
}

function RootComponent() {
  return (
    <>
      <HeadContent />
      <ThemeProvider
        attribute="class"
        defaultTheme="dark"
        disableTransitionOnChange
        storageKey="vite-ui-theme"
      >
        <GetMonitorOutlet />
        <Toaster richColors />
      </ThemeProvider>
      <TanStackRouterDevtools position="bottom-left" />
      <ReactQueryDevtools position="bottom" buttonPosition="bottom-right" />
    </>
  );
}
