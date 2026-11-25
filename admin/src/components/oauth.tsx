// "Continue with Google" (Google Identity Services) and "Continue with Apple"
// (Sign in with Apple JS). Both hand an ID token to the backend, which checks
// it against the provider's keys before signing anyone in.
import { useEffect, useRef, useState } from "react";
import { api, type Admin } from "../lib/api";

export interface OAuthResult { admin: Admin; tokens: { access_token: string }; is_new: boolean }

declare global {
  interface Window {
    google?: any;
    AppleID?: any;
  }
}

const scripts: Record<string, Promise<void>> = {};
function load(src: string): Promise<void> {
  return (scripts[src] ||= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = src;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => { delete scripts[src]; reject(new Error("Couldn't load the sign-in script. Check your connection.")); };
    document.head.appendChild(s);
  }));
}

function AppleLogo() {
  return (
    <svg viewBox="0 0 17 20" width="15" height="18" aria-hidden fill="currentColor">
      <path d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9C3.6 4.8 2 5.8 1.1 7.4c-1.8 3.2-.5 7.9 1.3 10.5.9 1.3 1.9 2.7 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.6 1-1.5 1.4-2.9 1.4-3-.1 0-2.7-1-2.7-4.3ZM11.6 3c.7-.9 1.2-2 1-3.1-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1 3 1.1.1 2.2-.6 2.9-1.4Z" />
    </svg>
  );
}

export function OAuthButtons({
  googleClientId, appleServiceId, code, onDone, onError, verb = "Continue",
}: {
  googleClientId?: string | null; appleServiceId?: string | null; code?: string;
  onDone: (r: OAuthResult) => void; onError: (e: unknown) => void; verb?: string;
}) {
  const googleBox = useRef<HTMLDivElement>(null);
  const codeRef = useRef(code);
  codeRef.current = code;
  const [busy, setBusy] = useState<"google" | "apple" | null>(null);
  const [googleReady, setGoogleReady] = useState(false);
  const [googleFailed, setGoogleFailed] = useState(false);

  async function finish(provider: "google" | "apple", token: string, name?: string) {
    setBusy(provider);
    try {
      onDone(await api<OAuthResult>(`/admin/auth/oauth/${provider}`, {
        method: "POST", json: { token, code: codeRef.current || null, name: name || null },
      }));
    } catch (e) { onError(e); } finally { setBusy(null); }
  }

  // Google renders its own button (required for the ID-token popup flow).
  useEffect(() => {
    if (!googleClientId) return;
    let cancelled = false;
    load("https://accounts.google.com/gsi/client").then(() => {
      if (cancelled || !googleBox.current || !window.google?.accounts?.id) return;
      window.google.accounts.id.initialize({
        client_id: googleClientId,
        callback: (r: { credential?: string }) => r.credential && finish("google", r.credential),
        ux_mode: "popup",
        auto_select: false,
        itp_support: true,
      });
      const width = Math.min(400, Math.max(200, googleBox.current.offsetWidth));
      googleBox.current.innerHTML = "";
      window.google.accounts.id.renderButton(googleBox.current, {
        type: "standard", theme: "outline", size: "large", shape: "rectangular",
        text: verb === "Sign up" ? "signup_with" : "continue_with", logo_alignment: "center", width,
      });
      setGoogleReady(true);
    }).catch(() => setGoogleFailed(true));
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [googleClientId]);

  async function apple() {
    if (!appleServiceId) return;
    try {
      await load("https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js");
      window.AppleID.auth.init({
        clientId: appleServiceId, scope: "name email", usePopup: true,
        redirectURI: `${window.location.origin}/login`, state: crypto.randomUUID(),
      });
      const data = await window.AppleID.auth.signIn();
      const n = data?.user?.name;
      await finish("apple", data.authorization.id_token, n ? `${n.firstName ?? ""} ${n.lastName ?? ""}`.trim() : undefined);
    } catch (e: any) {
      if (e?.error === "popup_closed_by_user" || e?.error === "user_cancelled_authorize") return;
      onError(new Error("Apple sign-in didn't finish. Try again."));
    }
  }

  return (
    <div className="space-y-2.5">
      <div className="flex items-center gap-3 text-[11px] uppercase tracking-wider text-faint">
        <span className="h-px flex-1 bg-line" /> or <span className="h-px flex-1 bg-line" />
      </div>
      {googleClientId ? (
        <div className="relative h-10 overflow-hidden rounded-lg">
          <div ref={googleBox} className="flex h-10 w-full justify-center [color-scheme:light]" />
          {(!googleReady || busy === "google") && (
            <button type="button"
              onClick={() => googleFailed && onError(new Error("Couldn't reach Google. Check your connection or ad blocker and reload."))}
              className="absolute inset-0 flex items-center justify-center rounded-lg border border-line bg-white text-sm font-medium text-[#1f1f1f]">
              <GoogleLogo /> <span className="ml-2">{busy === "google" ? "Signing in…" : `${verb} with Google`}</span>
            </button>
          )}
        </div>
      ) : null}
      {googleClientId && import.meta.env.DEV && (
        <p className="text-[11px] leading-snug text-faint">
          Dev tip: if Google says “no registered origin”, add <code className="text-sub">{window.location.origin}</code> to
          {" "}<em>Authorized JavaScript origins</em> of the Web client in Google Cloud → APIs &amp; Services → Credentials.
        </p>
      )}
      {googleClientId ? null : (
        <Unavailable label={`${verb} with Google`} icon={<GoogleLogo />} hint="Set GOOGLE_SERVER_CLIENT_ID on the server" />
      )}
      {appleServiceId ? (
        <button type="button" onClick={apple} disabled={!!busy}
          className="flex h-10 w-full items-center justify-center gap-2 rounded-lg bg-black text-sm font-medium text-white ring-1 ring-inset ring-white/15 transition hover:bg-[#1a1a1a] disabled:opacity-60">
          <AppleLogo /> {busy === "apple" ? "Signing in…" : `${verb} with Apple`}
        </button>
      ) : (
        <Unavailable label={`${verb} with Apple`} icon={<AppleLogo />} hint="Set APPLE_SERVICE_ID on the server" />
      )}
    </div>
  );
}

function Unavailable({ label, icon, hint }: { label: string; icon: React.ReactNode; hint: string }) {
  return (
    <button type="button" disabled title={hint}
      className="flex h-10 w-full cursor-not-allowed items-center justify-center gap-2 rounded-lg border border-line text-sm font-medium text-faint">
      {icon} {label}
      <span className="sr-only">({hint})</span>
    </button>
  );
}

function GoogleLogo() {
  return (
    <svg viewBox="0 0 48 48" width="17" height="17" aria-hidden>
      <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.6 13.2l7.9 6.2C12.4 13.6 17.7 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.1 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.4c-.5 2.9-2.2 5.3-4.6 6.9l7.4 5.8c4.3-4 6.9-9.9 6.9-17.2z" />
      <path fill="#FBBC05" d="M10.5 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.2C.9 16.5 0 20.1 0 24s.9 7.5 2.6 10.8l7.9-6.2z" />
      <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.4-5.8c-2.1 1.4-4.8 2.3-8.5 2.3-6.3 0-11.6-4.1-13.5-9.9l-7.9 6.2C6.6 42.6 14.6 48 24 48z" />
    </svg>
  );
}
