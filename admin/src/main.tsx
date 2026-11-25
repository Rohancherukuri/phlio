import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import { StrictMode, Suspense, lazy, useEffect, useSyncExternalStore } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { Layout } from "./components/Layout";
import { Skeleton } from "./components/ui";
import { api, auth, type Admin } from "./lib/api";
import { initAnalytics } from "./lib/analytics";
import { Login, Signup } from "./pages/Auth";
import "./index.css";

const Overview = lazy(() => import("./pages/Overview"));
const Platform = lazy(() => import("./pages/Platform"));
const Live = lazy(() => import("./pages/Live"));
const Users = lazy(() => import("./pages/Users"));
const Integrations = lazy(() => import("./pages/Integrations"));
const Team = lazy(() => import("./pages/Team"));

const client = new QueryClient({
  defaultOptions: { queries: { staleTime: 20_000, retry: (n, e: any) => e?.status !== 401 && e?.status !== 403 && n < 2 } },
});

function useToken() {
  return useSyncExternalStore(
    (cb) => { window.addEventListener("phlio-auth", cb); return () => window.removeEventListener("phlio-auth", cb); },
    () => auth.token,
  );
}

function Protected() {
  const token = useToken();
  const me = useQuery({ queryKey: ["me", token], queryFn: () => api<Admin>("/admin/auth/me"), enabled: !!token });
  if (!token) return <Navigate to="/login" replace />;
  if (me.isError) return <Navigate to="/login" replace />;
  if (!me.data) return <div className="p-6"><Skeleton className="h-10 w-48" /></div>;
  return <Layout admin={me.data} />;
}

function Guest({ children }: { children: JSX.Element }) {
  return useToken() ? <Navigate to="/" replace /> : children;
}

const page = (el: JSX.Element) => <Suspense fallback={<Skeleton className="h-64" />}>{el}</Suspense>;

function App() {
  useEffect(() => { initAnalytics(); }, []);
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Guest><Login /></Guest>} />
        <Route path="/signup" element={<Guest><Signup /></Guest>} />
        <Route element={<Protected />}>
          <Route index element={page(<Overview />)} />
          <Route path="live" element={page(<Live />)} />
          <Route path="p/:platform" element={page(<Platform />)} />
          <Route path="users" element={page(<Users />)} />
          <Route path="integrations" element={page(<Integrations />)} />
          <Route path="team" element={page(<Team />)} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={client}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
);
