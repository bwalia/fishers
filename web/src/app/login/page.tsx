"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, saveSession, type AuthTokens } from "@/lib/api";
import { AuthPitch } from "@/components/AuthPitch";

export default function LoginPage() {
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const tokens = await api<AuthTokens>(
        "POST",
        "/auth/login",
        { identifier: identifier.trim(), password },
        false
      );
      saveSession(tokens);
      // Come back to whatever expired — a scorer sent here mid-over lands back
      // on the same match. Only same-origin paths, never an absolute URL.
      const next = new URLSearchParams(window.location.search).get("next");
      router.push(next && next.startsWith("/") && !next.startsWith("//") ? next : "/");
    } catch {
      // Never say which half was wrong: that tells anyone guessing whether an
      // account exists.
      setError("That email or number and password do not match.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main id="main" className="auth-shell">
      <AuthPitch />

      <div className="auth-card">
        <h2>Sign in</h2>
        <p>The same account as the iOS app.</p>

        <form className="auth-form" onSubmit={onSubmit}>
          <label>
            Email or mobile number
            <input
              type="text"
              inputMode="email"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              autoComplete="username"
              placeholder="you@club.test or 07700 900123"
              required
            />
          </label>
          <label>
            Password
            <span className="password-field">
              <input
                type={show ? "text" : "password"}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                required
              />
              <button
                type="button"
                className="btn ghost sm"
                onClick={() => setShow((v) => !v)}
                aria-label={show ? "Hide password" : "Show password"}
              >
                {show ? "Hide" : "Show"}
              </button>
            </span>
          </label>

          {error && <p className="error">{error}</p>}

          <button className="btn primary" type="submit" disabled={busy}>
            {busy ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <p className="auth-alt">
          New here? <Link href="/register">Create an account</Link>
        </p>
      </div>
    </main>
  );
}
