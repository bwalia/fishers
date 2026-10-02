"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { api, readErr } from "@/lib/api";
import { AuthPitch } from "@/components/AuthPitch";
import { useT } from "@/lib/i18n/provider";

type Sent = { sent_to: string; expires_in: number; resend_after: number };

/// Two steps on one screen: ask for the address, then take the code and the
/// new password.
///
/// One page rather than two because the second step is useless without the
/// first — a `/reset` of its own would be a URL somebody could land on with no
/// code and nothing to do. The address stays in React state between the steps,
/// never in the URL, so the thing a reset is about is not in anybody's history
/// or in a referrer header.
export default function ForgotPage() {
  const t = useT();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState<Sent | null>(null);
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function ask(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      setSent(await api<Sent>("POST", "/auth/forgot", { email: email.trim() }, false));
    } catch (err) {
      setError(readErr(err, t("fp.could_not_send")));
    } finally {
      setBusy(false);
    }
  }

  async function reset(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api<unknown>(
        "POST",
        "/auth/reset",
        { email: email.trim(), code: code.trim(), password },
        false
      );
      setDone(true);
    } catch (err) {
      setError(readErr(err, t("fp.could_not_reset")));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main id="main" className="auth-shell">
      <AuthPitch />

      <div className="auth-card">
        <h2>{t("fp.title")}</h2>

        {done ? (
          <>
            <p className="ok-note">{t("fp.done")}</p>
            <Link className="btn primary" href="/login">{t("rest.sign_in")}</Link>
          </>
        ) : !sent ? (
          <>
            <p>{t("fp.ask")}</p>
            <form className="auth-form" onSubmit={ask}>
              <label>
                {t("cl.email")}
                <input
                  type="email"
                  inputMode="email"
                  autoComplete="username"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </label>
              {error && <p className="error">{error}</p>}
              <button className="btn primary" type="submit" disabled={busy}>
                {busy ? t("fp.sending") : t("fp.send_code")}
              </button>
            </form>
            <p className="muted">{t("fp.no_account_no_tell")}</p>
          </>
        ) : (
          <>
            <p>{t("fp.sent", { address: sent.sent_to })}</p>
            <form className="auth-form" onSubmit={reset}>
              <label>
                {t("fp.code")}
                <input
                  type="text"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  pattern="[0-9]*"
                  maxLength={6}
                  value={code}
                  onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                  required
                />
              </label>
              <label>
                {t("cl.new_password")}
                <span className="password-field">
                  <input
                    type={show ? "text" : "password"}
                    autoComplete="new-password"
                    minLength={8}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                  />
                  <button
                    type="button"
                    className="btn ghost sm"
                    onClick={() => setShow((v) => !v)}
                    aria-label={show ? t("le.hide_password") : t("le.show_password")}
                  >
                    {show ? t("rest.hide") : t("le.show")}
                  </button>
                </span>
              </label>
              <p className="muted">{t("fp.min")} {t("fp.signs_out_everywhere")}</p>
              {error && <p className="error">{error}</p>}
              <button
                className="btn primary"
                type="submit"
                disabled={busy || code.length !== 6 || password.length < 8}
              >
                {busy ? t("fp.setting") : t("fp.set")}
              </button>
            </form>
            <p className="auth-alt">
              <button className="btn ghost sm" type="button" onClick={() => setSent(null)}>
                {t("fp.again")}
              </button>
            </p>
          </>
        )}
      </div>
    </main>
  );
}
