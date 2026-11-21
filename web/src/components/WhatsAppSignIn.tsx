"use client";

/// Sign in with your mobile number and a code sent on WhatsApp (plan §5.4):
/// for the players who live in the club's WhatsApp group and never remember
/// a password.
///
/// Shown only when the server says it is switched on (`GET /auth/whatsapp`).
/// "A code is on its way" is said the same whether or not the number has an
/// account, because the server answers the same: the page must not be a way
/// to find out who is signed up.

import { useEffect, useId, useRef, useState } from "react";
import { api, errCode, readErr, saveSession, type AuthTokens } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

type Started = { sent: boolean; expires_in: number; resend_after: number };

export function WhatsAppSignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const t = useT();
  const id = useId();
  const [enabled, setEnabled] = useState(false);
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [phoneError, setPhoneError] = useState<string | null>(null);
  const [codeError, setCodeError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  /// When a new code may be asked for.
  const [resendAt, setResendAt] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const phoneField = useRef<HTMLInputElement>(null);
  const codeField = useRef<HTMLInputElement>(null);

  useEffect(() => {
    api<{ enabled: boolean }>("GET", "/auth/whatsapp", undefined, false)
      .then((r) => setEnabled(r.enabled === true))
      .catch(() => setEnabled(false));
  }, []);

  // A second hand for "ask again in 42 seconds", only while it matters.
  useEffect(() => {
    if (step !== "code" || now >= resendAt) return;
    const timer = window.setTimeout(() => setNow(Date.now()), 1000);
    return () => window.clearTimeout(timer);
  }, [step, now, resendAt]);

  useEffect(() => {
    if (!open) return;
    (step === "phone" ? phoneField : codeField).current?.focus();
  }, [open, step]);

  if (!enabled) return null;

  const start = async () => {
    setPhoneError(null);
    setCodeError(null);
    setFormError(null);
    if (!phone.trim()) {
      setPhoneError(t("pw2.wa_phone_missing"));
      phoneField.current?.focus();
      return;
    }
    setBusy(true);
    try {
      const out = await api<Started>("POST", "/auth/whatsapp/start", { phone: phone.trim() }, false);
      setResendAt(Date.now() + (out.resend_after ?? 60) * 1000);
      setNow(Date.now());
      setCode("");
      setStep("code");
    } catch (e) {
      const said = readErr(e, t("le.that_did_not_work"));
      const c = errCode(e);
      if (c === "whatsapp_off") setEnabled(false);
      else if (c === "bad_phone" || c === "slow_down") setPhoneError(said);
      else setFormError(said);
    } finally {
      setBusy(false);
    }
  };

  const verify = async () => {
    setCodeError(null);
    setFormError(null);
    const digits = code.replace(/\D/g, "");
    if (digits.length !== 6) {
      setCodeError(t("pw2.wa_code_six"));
      codeField.current?.focus();
      return;
    }
    setBusy(true);
    try {
      saveSession(await api<AuthTokens>("POST", "/auth/whatsapp/verify", { phone: phone.trim(), code: digits }, false));
      onSignedIn();
    } catch (e) {
      const said = readErr(e, t("le.that_did_not_work"));
      const c = errCode(e);
      if (c === "wrong_code" || c === "slow_down") {
        setCodeError(said);
        codeField.current?.focus();
      } else if (c === "bad_phone") {
        setStep("phone");
        setPhoneError(said);
      } else setFormError(said);
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button className="btn wa-signin-open" type="button" onClick={() => setOpen(true)}>
        <Icon name="chat" size={18} /> {t("pw2.wa_signin")}
      </button>
    );
  }

  const wait = Math.max(0, Math.ceil((resendAt - now) / 1000));
  return (
    <form
      className="auth-form wa-signin"
      aria-labelledby={`${id}-title`}
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void (step === "phone" ? start() : verify());
      }}
    >
      <h3 id={`${id}-title`}>{t("pw2.wa_signin")}</h3>
      {step === "phone" ? (
        <label htmlFor={`${id}-phone`}>
          <span id={`${id}-phone-label`}>{t("pw2.wa_phone")}</span>
          <input
            ref={phoneField}
            id={`${id}-phone`}
            aria-labelledby={`${id}-phone-label`}
            type="tel"
            inputMode="tel"
            autoComplete="tel"
            value={phone}
            placeholder="+44 7700 900123"
            aria-invalid={phoneError ? true : undefined}
            aria-describedby={phoneError ? `${id}-phone-error` : `${id}-phone-hint`}
            onChange={(e) => setPhone(e.target.value)}
          />
          <span className="subtle" id={`${id}-phone-hint`}>
            {t("pw2.wa_phone_hint")}
          </span>
          {phoneError && (
            <span className="field-error" id={`${id}-phone-error`}>
              {phoneError}
            </span>
          )}
        </label>
      ) : (
        <>
          <p className="muted" role="status">
            {t("pw2.wa_sent", { phone: phone.trim() })}
          </p>
          <label htmlFor={`${id}-code`}>
            <span id={`${id}-code-label`}>{t("pw2.wa_code")}</span>
            <input
              ref={codeField}
              id={`${id}-code`}
              aria-labelledby={`${id}-code-label`}
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={7}
              value={code}
              aria-invalid={codeError ? true : undefined}
              aria-describedby={codeError ? `${id}-code-error` : undefined}
              onChange={(e) => setCode(e.target.value)}
            />
            {codeError && (
              <span className="field-error" id={`${id}-code-error`}>
                {codeError}
              </span>
            )}
          </label>
        </>
      )}

      {formError && (
        <p className="error" role="alert">
          {formError}
        </p>
      )}

      <button className="btn primary" type="submit" disabled={busy}>
        {busy ? t("pay.sending") : step === "phone" ? t("pw2.wa_send_code") : t("rest.sign_in")}
      </button>
      {step === "code" && (
        <div className="field-row">
          <button className="btn ghost" type="button" disabled={busy || wait > 0} onClick={() => void start()}>
            {wait > 0 ? t("pw2.wa_resend_in", { count: wait, n: wait }) : t("pw2.wa_resend")}
          </button>
          <button
            className="btn ghost"
            type="button"
            disabled={busy}
            onClick={() => {
              setStep("phone");
              setCode("");
              setCodeError(null);
              setFormError(null);
            }}
          >
            {t("pw2.wa_other_number")}
          </button>
        </div>
      )}
    </form>
  );
}
