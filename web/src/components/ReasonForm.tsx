"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useT } from "@/lib/i18n/provider";

/// Asks why, in place, before something that tells other people about it:
/// turning a payment down, letting somebody off, cancelling a bill.
///
/// In the page rather than `window.prompt`, so the question has a label, the
/// answer can be read back before it is sent, and the server's objection
/// appears under the field it is about.
export function ReasonForm({
  label,
  hint,
  submitLabel,
  required = true,
  danger = false,
  busy,
  error,
  onSubmit,
  onCancel,
}: {
  label: string;
  hint?: string;
  submitLabel: string;
  required?: boolean;
  danger?: boolean;
  busy: boolean;
  /// The server's sentence, shown under the field.
  error?: string | null;
  onSubmit: (reason: string) => void;
  onCancel: () => void;
}) {
  const t = useT();
  const id = useId();
  const field = useRef<HTMLInputElement>(null);
  const [reason, setReason] = useState("");
  const [missing, setMissing] = useState(false);
  useEffect(() => field.current?.focus(), []);

  const said = missing ? t("pay.say_why") : error;
  return (
    <form
      className="reason-form"
      onSubmit={(e) => {
        e.preventDefault();
        if (required && !reason.trim()) {
          setMissing(true);
          field.current?.focus();
          return;
        }
        onSubmit(reason.trim());
      }}
    >
      <label htmlFor={`${id}-reason`}>{label}</label>
      {hint && (
        <span className="subtle" id={`${id}-hint`}>
          {hint}
        </span>
      )}
      <input
        ref={field}
        id={`${id}-reason`}
        value={reason}
        maxLength={200}
        aria-invalid={said ? true : undefined}
        aria-describedby={[hint ? `${id}-hint` : "", said ? `${id}-error` : ""].filter(Boolean).join(" ") || undefined}
        onChange={(e) => {
          setReason(e.target.value);
          setMissing(false);
        }}
      />
      {said && (
        <span className="field-error" id={`${id}-error`}>
          {said}
        </span>
      )}
      <div className="field-row">
        <button className={danger ? "btn danger" : "btn primary"} type="submit" disabled={busy}>
          {submitLabel}
        </button>
        <button className="btn" type="button" onClick={onCancel} disabled={busy}>
          {t("pay.never_mind")}
        </button>
      </div>
    </form>
  );
}
