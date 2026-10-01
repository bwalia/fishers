"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { api, readErr, saveUser, type PublicUser, type VerificationStatus } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

type Channel = "email" | "phone";

/// Confirm an email address or a phone number with a six-digit code.
///
/// The input is there from the start rather than behind a "send code" button:
/// signup already sent the first email, so most people only need to type it.
/// "Send a new code" covers the rest.
export function VerifyContact({
  status,
  onVerified,
  compact = false,
}: {
  status: VerificationStatus;
  onVerified: (user: PublicUser) => void;
  /// Inside another card (a gated form): no heading of its own.
  compact?: boolean;
}) {
  const t = useT();
  const channels: Channel[] = (["email", "phone"] as const).filter((c) => status[c].available);
  const [channel, setChannel] = useState<Channel>(channels[0] ?? "email");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [wait, setWait] = useState(0);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (wait <= 0) return;
    const t = setTimeout(() => setWait((w) => w - 1), 1000);
    return () => clearTimeout(t);
  }, [wait]);

  if (channels.length === 0) return null;

  const address = status[channel].address ?? "";
  const where = channel === "email" ? t("le.emailed") : t("le.sent_on_whatsapp");

  const send = async () => {
    setError(null);
    setNote(null);
    try {
      const sent = await api<{ sent_to: string; resend_after: number }>(
        "POST",
        `/me/verification/${channel}`
      );
      setNote(t("le.new_code_sent", { where, address: sent.sent_to }));
      setWait(sent.resend_after);
      setCode("");
      input.current?.focus();
    } catch (err) {
      const msg = readErr(err, t("le.could_not_send_a_code"));
      // "you can ask for another in 42s" — show it as a countdown instead.
      const secs = Number(/in (\d+)s/.exec(msg)?.[1]);
      if (secs) setWait(secs);
      else setError(msg);
    }
  };

  const confirm = async (e?: FormEvent) => {
    e?.preventDefault();
    if (code.length !== 6 || busy) return;
    setBusy(true);
    setError(null);
    try {
      const user = await api<PublicUser>("POST", `/me/verification/${channel}/confirm`, { code });
      saveUser(user);
      onVerified(user);
    } catch (err) {
      setError(readErr(err, t("le.that_code_did_not_work")));
      setCode("");
      input.current?.focus();
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className={`verify${compact ? " compact" : ""}`} onSubmit={confirm}>
      {!compact && (
        <div className="verify-head">
          <span className="verify-icon" aria-hidden="true">
            <Icon name={channel === "email" ? "mail" : "chat"} size={20} />
          </span>
          <div>
            <h3>{channel === "email" ? t("le.confirm_your_email") : t("le.confirm_your_phone")}</h3>
            <p className="muted">
              {t("le.enter_the_code_we_sent", { where })} <strong>{address}</strong>.
            </p>
          </div>
        </div>
      )}
      {compact && (
        <p className="muted verify-lede">
          {t("le.enter_the_code_we_sent", { where })} <strong>{address}</strong>.
        </p>
      )}

      <div className="verify-row">
        <label className="sr-only" htmlFor={`code-${channel}`}>
          {t("rest.verification_code")}
        </label>
        <input
          id={`code-${channel}`}
          ref={input}
          className="verify-code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]*"
          maxLength={6}
          placeholder={t("rest.x")}
          value={code}
          onChange={(e) => {
            const digits = e.target.value.replace(/\D/g, "").slice(0, 6);
            setCode(digits);
          }}
          aria-describedby={`code-${channel}-help`}
          aria-invalid={error ? true : undefined}
        />
        <button className="btn primary" type="submit" disabled={code.length !== 6 || busy}>
          {busy ? t("le.checking") : t("le.confirm")}
        </button>
      </div>

      <p className="verify-foot subtle" id={`code-${channel}-help`}>
        {wait > 0 ? (
          <span>{t("le.send_new_code_in", { n: wait })}</span>
        ) : (
          <button type="button" className="linkish" onClick={send}>
            {t("rest.send_a_new_code")}
          </button>
        )}
        {channels.length > 1 && (
          <>
            {" · "}
            <button
              type="button"
              className="linkish"
              onClick={() => {
                setChannel(channel === "email" ? "phone" : "email");
                setCode("");
                setError(null);
                setNote(null);
                setWait(0);
              }}
            >
              Use {channel === "email" ? "WhatsApp" : "email"} instead
            </button>
          </>
        )}
      </p>
      {note && (
        <p className="verify-note" role="status">
          {note}
        </p>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </form>
  );
}
