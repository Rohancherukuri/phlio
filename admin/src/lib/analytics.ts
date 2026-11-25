// Loads the client scripts of the analytics tools switched on in
// Integrations (public ids only, from GET /analytics/config) and reports
// admin-panel page views to each. Server-side events from the app are sent by
// the backend; this only covers the panel itself.
import { api } from "./api";

type Config = Record<string, Record<string, string>>;
declare global {
  interface Window {
    dataLayer?: unknown[];
    gtag?: (...args: unknown[]) => void;
    posthog?: { capture: (e: string, p?: object) => void; init?: unknown };
    plausible?: (e: string, o?: object) => void;
    umami?: { track: (...args: any[]) => void };
    _paq?: unknown[][];
  }
}

let providers: Config = {};

function script(src: string, attrs: Record<string, string> = {}) {
  const s = document.createElement("script");
  s.async = true;
  s.src = src;
  Object.entries(attrs).forEach(([k, v]) => s.setAttribute(k, v));
  document.head.appendChild(s);
}

const safeHost = (h?: string) => (h && /^https:\/\/[\w.-]+(:\d+)?(\/[\w./-]*)?$/.test(h) ? h.replace(/\/$/, "") : null);

export async function initAnalytics() {
  try {
    providers = (await api<{ providers: Config }>("/analytics/config")).providers ?? {};
  } catch { return; }
  const ga = providers.ga4?.measurement_id;
  if (ga && /^G-[A-Z0-9]+$/.test(ga)) {
    window.dataLayer = window.dataLayer || [];
    window.gtag = function gtag() { window.dataLayer!.push(arguments); };
    window.gtag("js", new Date());
    window.gtag("config", ga, { send_page_view: false });
    script(`https://www.googletagmanager.com/gtag/js?id=${ga}`);
  }
  const ph = providers.posthog;
  const phHost = safeHost(ph?.host) ?? "https://us.i.posthog.com";
  if (ph?.project_api_key) {
    // Minimal loader: queue calls until the library arrives.
    const queue: [string, object?][] = [];
    window.posthog = { capture: (e, p) => queue.push([e, p]) };
    const s = document.createElement("script");
    s.async = true;
    s.src = `${phHost.replace(".i.posthog.com", "-assets.i.posthog.com")}/static/array.js`;
    s.onload = () => {
      const lib = (window as any).posthog;
      if (lib?.init) {
        lib.init(ph.project_api_key, { api_host: phHost, autocapture: false, capture_pageview: false, persistence: "memory" });
        queue.forEach(([e, p]) => lib.capture(e, p));
      }
    };
    document.head.appendChild(s);
  }
  const pl = providers.plausible;
  if (pl?.domain) {
    window.plausible = window.plausible || function (...a: unknown[]) { ((window.plausible as any).q ||= []).push(a); };
    script(`${safeHost(pl.host) ?? "https://plausible.io"}/js/script.manual.js`, { "data-domain": pl.domain });
  }
  const um = providers.umami;
  if (um?.website_id && safeHost(um.host)) {
    script(`${safeHost(um.host)}/script.js`, { "data-website-id": um.website_id, "data-auto-track": "false" });
  }
  const mt = providers.matomo;
  if (mt?.site_id && safeHost(mt.host)) {
    const host = safeHost(mt.host)!;
    window._paq = window._paq || [];
    window._paq.push(["setTrackerUrl", `${host}/matomo.php`], ["setSiteId", mt.site_id], ["disableCookies"]);
    script(`${host}/matomo.js`);
  }
}

export function trackPage(path: string, title: string) {
  if (window.gtag && providers.ga4) window.gtag("event", "page_view", { page_path: path, page_title: title });
  if (window.posthog && providers.posthog) window.posthog.capture("$pageview", { $current_url: path });
  if (window.plausible && providers.plausible) window.plausible("pageview", { u: location.origin + path });
  if (window.umami && providers.umami) window.umami.track((p: any) => ({ ...p, url: path, title }));
  if (window._paq && providers.matomo) window._paq.push(["setCustomUrl", path], ["setDocumentTitle", title], ["trackPageView"]);
}
