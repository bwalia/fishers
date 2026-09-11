"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, saveSession, saveUser, type AuthTokens, type PublicUser, type RoleIntent } from "@/lib/api";
import { AuthPitch } from "@/components/AuthPitch";
import { RoleChooser } from "@/components/RoleChooser";

type Method = "email" | "phone";

export default function RegisterPage() {
  const router = useRouter();
  const [method, setMethod] = useState<Method>("email");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // Somebody arriving from an invite link is joining a club, not starting one.
  const [role, setRole] = useState<RoleIntent | null>(() =>
    typeof window !== "undefined" &&
    new URLSearchParams(window.location.search).get("next")?.startsWith("/invite/")
      ? "player"
      : null
  );

  const tooShort = password.length > 0 && password.length < 8;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const tokens = await api<AuthTokens>(
        "POST",
        "/auth/signup",
        {
          name: name.trim(),
          // Send only what they chose. The other stays absent rather than
          // being an empty string the API would have to interpret.
          email: method === "email" ? email.trim() : undefined,
          phone: method === "phone" ? phone.trim() : undefined,
          password,
        },
        false
      );
      saveSession(tokens);
      // Saved straight after the account exists, so the dashboard opens on the
      // right guide instead of asking again.
      if (role) {
        try {
          saveUser(await api<PublicUser>("PATCH", "/me", { role_intent: role }));
        } catch {
          /* the dashboard asks instead */
        }
      }
      // An invite link sends people here to sign up; land them back on it so
      // they actually join the club they were invited to.
      const next = new URLSearchParams(window.location.search).get("next");
      router.push(next && next.startsWith("/") && !next.startsWith("//") ? next : "/");
    } catch (err) {
      // The API says what is wrong — already registered, too short — and those
      // are worth passing on rather than flattening.
      const message = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(message).error ?? "Could not create the account.");
      } catch {
        setError(message || "Could not create the account.");
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <main id="main" className="auth-shell">
      <AuthPitch />

      <div className="auth-card">
        <h2>Create an account</h2>
        <p>An email address or a mobile number — whichever you actually use.</p>

        <div className="tabs" role="tablist" aria-label="Register with">
          {(["email", "phone"] as const).map((m) => (
            <button
              key={m}
              role="tab"
              aria-selected={method === m}
              className={`tab${method === m ? " active" : ""}`}
              type="button"
              onClick={() => setMethod(m)}
            >
              {m === "email" ? "Email" : "Mobile number"}
            </button>
          ))}
        </div>

        <form className="auth-form" onSubmit={onSubmit}>
          <fieldset className="auth-role">
            <legend>I&apos;m here to…</legend>
            <RoleChooser compact value={role} onPicked={(_, r) => setRole(r)} />
          </fieldset>

          <label>
            Your name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoComplete="name"
              placeholder="As it goes on a team sheet"
              required
            />
          </label>

          {method === "email" ? (
            <label>
              Email
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                placeholder="you@club.test"
                required
              />
            </label>
          ) : (
            <label>
              Mobile number
              <input
                type="tel"
                inputMode="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                autoComplete="tel"
                placeholder="+44 7700 900123"
                required
              />
            </label>
          )}

          <label>
            Password
            <span className="password-field">
              <input
                type={show ? "text" : "password"}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="new-password"
                minLength={8}
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
            {tooShort && <span className="subtle">At least eight characters.</span>}
          </label>

          {error && <p className="error">{error}</p>}

          <button className="btn primary" type="submit" disabled={busy || tooShort}>
            {busy ? "Creating…" : "Create account"}
          </button>
        </form>

        {method === "phone" && (
          <p className="auth-hint">
            Your number is how you sign in. Include the country code — we may confirm it with a
            WhatsApp code.
          </p>
        )}

        <p className="auth-alt">
          Already have an account? <Link href="/login">Sign in</Link>
        </p>
      </div>
    </main>
  );
}
