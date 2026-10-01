"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, saveSession, saveUser, type AuthTokens, type PublicUser, type RoleIntent } from "@/lib/api";
import { AuthPitch } from "@/components/AuthPitch";
import { RoleChooser } from "@/components/RoleChooser";
import { GoogleButton } from "@/components/GoogleButton";
import { useT } from "@/lib/i18n/provider";

type Method = "email" | "phone";

export default function RegisterPage() {
  const t = useT();
  const router = useRouter();
  const [method, setMethod] = useState<Method>("email");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // Somebody arriving from an invite link is joining a club, not starting one;
  // the landing page's two buttons say which they are with ?as=. Read after
  // the first render: the server has no query string to read, and a first
  // render that differs from the server's is thrown away and redrawn — taking
  // anything already typed into the form with it.
  const [role, setRole] = useState<RoleIntent | null>(null);
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const as = q.get("as");
    if (q.get("next")?.startsWith("/invite/")) setRole("player");
    else if (as === "secretary" || as === "player") setRole(as);
  }, []);

  const tooShort = password.length > 0 && password.length < 8;

  // An invite link sends people here to sign up; land them back on it so they
  // actually join the club they were invited to. Otherwise, the quick start.
  function goNext() {
    const next = new URLSearchParams(window.location.search).get("next");
    router.push(next && next.startsWith("/") && !next.startsWith("//") ? next : "/welcome");
  }

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
      goNext();
    } catch (err) {
      // The API says what is wrong — already registered, too short — and those
      // are worth passing on rather than flattening.
      const message = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(message).error ?? t("le.could_not_create_the_account"));
      } catch {
        setError(message || t("le.could_not_create_the_account"));
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <main id="main" className="auth-shell">
      <AuthPitch />

      <div className="auth-card">
        <h2>{t("rest.create_an_account")}</h2>
        <p>{t("rest.with_google_an_email_address_or_a_mobi")}</p>

        {/* Asked first, so it applies however they sign up — Google included. */}
        <fieldset className="auth-role">
          <legend>{t("rest.im_here_to")}</legend>
          <RoleChooser compact value={role} onPicked={(_, r) => setRole(r)} />
        </fieldset>

        <GoogleButton mode="signup" role={role} onSignedIn={goNext} />

        <div className="tabs" role="tablist" aria-label={t("rest.register_with")}>
          {(["email", "phone"] as const).map((m) => (
            <button
              key={m}
              role="tab"
              aria-selected={method === m}
              className={`tab${method === m ? " active" : ""}`}
              type="button"
              onClick={() => setMethod(m)}
            >
              {m === "email" ? t("rest.email") : t("rest.mobile_number")}
            </button>
          ))}
        </div>

        <form className="auth-form" onSubmit={onSubmit}>

          <label>
            {t("rest.your_name")}
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoComplete="name"
              placeholder={t("rest.as_it_goes_on_a_team_sheet")}
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
                placeholder={t("rest.you_club_test")}
                required
              />
            </label>
          ) : (
            <label>
              {t("rest.mobile_number")}
              <input
                type="tel"
                inputMode="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                autoComplete="tel"
                placeholder={t("rest.44_7700_900123")}
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
                aria-label={show ? t("le.hide_password") : t("le.show_password")}
              >
                {show ? "Hide" : t("le.show")}
              </button>
            </span>
            {tooShort && <span className="subtle">{t("rest.at_least_eight_characters")}</span>}
          </label>

          {error && <p className="error">{error}</p>}

          <button className="btn primary" type="submit" disabled={busy || tooShort}>
            {busy ? "Creating…" : t("le.create_account")}
          </button>
        </form>

        {method === "phone" && (
          <p className="auth-hint">
            {t("rest.your_number_is_how_you_sign_in_include")}
          </p>
        )}

        <p className="auth-alt">
          {t("rest.already_have_an_account")} <Link href="/login">Sign in</Link>
        </p>
      </div>
    </main>
  );
}
