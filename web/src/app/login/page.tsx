"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { api, saveSession, type PublicUser } from "@/lib/api";

type AuthTokens = {
  access_token: string;
  refresh_token: string;
  user: PublicUser;
};

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("demo@fishers.test");
  const [password, setPassword] = useState("password123");
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
        { email, password },
        false
      );
      saveSession(tokens);
      router.push("/");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main>
      <section className="hero">
        <h1>Sign in</h1>
        <p>Same accounts as the iOS app and API.</p>
      </section>
      <form className="panel form" onSubmit={onSubmit}>
        <label>
          Email
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username"
            required
          />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
          />
        </label>
        {error && <p className="error">{error}</p>}
        <button className="btn primary" type="submit" disabled={busy}>
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </main>
  );
}
