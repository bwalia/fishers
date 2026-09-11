"use client";

import { useEffect, useRef, useState } from "react";
import { api, readErr, saveSession, saveUser, type AuthTokens, type PublicUser, type RoleIntent } from "@/lib/api";

type Config = { enabled: boolean; client_id: string | null };
type Signed = AuthTokens & { created: boolean };

type Gsi = {
  accounts: {
    id: {
      initialize: (o: Record<string, unknown>) => void;
      renderButton: (el: HTMLElement, o: Record<string, unknown>) => void;
    };
  };
};

let loading: Promise<Gsi> | null = null;

/// Google's own sign-in script, loaded once and only on pages that show the
/// button.
function loadGoogle(): Promise<Gsi> {
  loading ??= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://accounts.google.com/gsi/client";
    s.async = true;
    s.onload = () => {
      const g = (window as unknown as { google?: Gsi }).google;
      if (g) resolve(g);
      else reject(new Error("Google sign-in did not load"));
    };
    s.onerror = () => {
      loading = null;
      reject(new Error("Google sign-in did not load"));
    };
    document.head.appendChild(s);
  });
  return loading;
}

function isDark(): boolean {
  const set = document.documentElement.getAttribute("data-theme");
  return set ? set === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
}

/// "Continue with Google": signs in, or makes the account, in one step.
///
/// Google's own button, so it looks and behaves the way people trust — it is
/// drawn by Google's script, which hands back a signed token for the server to
/// check. Nothing here when the server has no Google client configured.
export function GoogleButton({
  mode,
  role,
  onSignedIn,
}: {
  mode: "signin" | "signup";
  /// On the register page: what they said they are here to do, saved onto a
  /// new account.
  role?: RoleIntent | null;
  onSignedIn: () => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [clientId, setClientId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // The button's callback is fixed when Google's script is set up; these keep
  // it reading the latest choice rather than the one at first render.
  const latest = useRef({ role, onSignedIn });
  latest.current = { role, onSignedIn };

  useEffect(() => {
    // An API that is restarting (a deploy, a local rebuild) cannot answer yet;
    // asking once would leave the button missing until somebody reloads.
    let gone = false;
    let timer: ReturnType<typeof setTimeout>;
    const ask = (tries: number) =>
      api<Config>("GET", "/auth/google", undefined, false)
        .then((c) => !gone && setClientId(c.enabled ? c.client_id : null))
        .catch(() => {
          if (!gone && tries > 1) timer = setTimeout(() => ask(tries - 1), 3000);
        });
    ask(10);
    return () => {
      gone = true;
      clearTimeout(timer);
    };
  }, []);

  useEffect(() => {
    if (!clientId || !box.current) return;
    let gone = false;
    loadGoogle()
      .then((google) => {
        if (gone || !box.current) return;
        google.accounts.id.initialize({
          client_id: clientId,
          ux_mode: "popup",
          auto_select: false,
          callback: async ({ credential }: { credential: string }) => {
            setBusy(true);
            setError(null);
            try {
              const signed = await api<Signed>("POST", "/auth/google", { credential }, false);
              saveSession(signed);
              const { role: chosen, onSignedIn: done } = latest.current;
              if (signed.created && chosen) {
                try {
                  saveUser(await api<PublicUser>("PATCH", "/me", { role_intent: chosen }));
                } catch {
                  /* the dashboard asks instead */
                }
              }
              done();
            } catch (err) {
              setError(readErr(err, "Google sign-in did not work — try again"));
              setBusy(false);
            }
          },
        });
        google.accounts.id.renderButton(box.current, {
          type: "standard",
          theme: isDark() ? "filled_black" : "outline",
          size: "large",
          shape: "pill",
          text: mode === "signup" ? "signup_with" : "continue_with",
          logo_alignment: "center",
          width: Math.min(400, Math.max(200, box.current.offsetWidth)),
        });
      })
      .catch(() => {
        if (!gone) setError("Google sign-in could not load. Use your email instead, or try again.");
      });
    return () => {
      gone = true;
    };
  }, [clientId, mode]);

  if (!clientId) return null;
  return (
    <div className="google-signin">
      <div ref={box} className="google-button" aria-busy={busy} />
      {busy && <p className="subtle google-note" role="status">Signing you in…</p>}
      {error && <p className="error">{error}</p>}
      <div className="auth-or" aria-hidden="true">
        <span>or with your email</span>
      </div>
    </div>
  );
}
