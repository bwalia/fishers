"use client";

import { useEffect, useId, useRef, useState, type InputHTMLAttributes } from "react";
import { api, errCode, readErr } from "@/lib/api";
import type { PayoutAccounts } from "@/lib/payments";
import { useT } from "@/lib/i18n/provider";

/// What has been typed so far, for a preview of what players will see.
export type BankDraft = { holder: string; sort: string; number: string; personal: boolean };

type FieldErrors = Partial<Record<"holder" | "sort" | "number" | "again" | "label" | "password", string>>;

/// Add or change the club's bank details.
///
/// The account number is typed twice because there is no modulus check yet:
/// one wrong digit would send every player's money somewhere else. The
/// numbers are dropped from the page as soon as they are saved.
export function BankDetailsForm({
  clubId,
  changing,
  onCancel,
  onSaved,
  onDraft,
  submitLabel,
}: {
  clubId: string;
  changing: boolean;
  onCancel?: () => void;
  onSaved: (view: PayoutAccounts) => void;
  /// Told of every keystroke, for a live preview beside the form.
  onDraft?: (draft: BankDraft) => void;
  /// The save button's words, when not the usual ones.
  submitLabel?: string;
}) {
  const t = useT();
  const id = useId();
  const [holder, setHolder] = useState("");
  const [sort, setSort] = useState("");
  const [number, setNumber] = useState("");
  const [again, setAgain] = useState("");
  const [label, setLabel] = useState("");
  const [personal, setPersonal] = useState(false);
  const [password, setPassword] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const passwordField = useRef<HTMLInputElement>(null);

  useEffect(() => {
    onDraft?.({ holder, sort, number, personal });
  }, [onDraft, holder, sort, number, personal]);

  const digits = (s: string) => s.replace(/[\s-]/g, "");

  /// The API's own rules, checked here first so each mistake shows under its
  /// own field. The API checks them again.
  const check = (): FieldErrors => {
    const e: FieldErrors = {};
    const name = holder.trim().replace(/\s+/g, " ");
    if (!name) e.holder = t("pay.err_holder_missing");
    else if (name.length > 70) e.holder = t("pay.err_holder_long");
    else if (!new RegExp("^[\\p{L}\\p{N} &'\\-.,/()]+$", "u").test(name)) e.holder = t("pay.err_holder_chars");
    if (!/^\d{6}$/.test(digits(sort))) e.sort = t("pay.err_sort_code");
    const n = digits(number);
    if (!/^\d{7,8}$/.test(n)) e.number = t("pay.err_account_number");
    else if (digits(again) !== n) e.again = t("pay.err_numbers_differ");
    if (label.trim().length > 60) e.label = t("pay.err_label_long");
    return e;
  };

  const submit = async () => {
    const found = check();
    setErrors(found);
    setFormError(null);
    if (Object.keys(found).length > 0) {
      document.getElementById(`${id}-${Object.keys(found)[0]}`)?.focus();
      return;
    }
    setBusy(true);
    try {
      const view = await api<PayoutAccounts>("POST", `/clubs/${clubId}/payout-account`, {
        holder_name: holder.trim(),
        sort_code: digits(sort),
        account_number: digits(number),
        label: label.trim() || undefined,
        is_personal: personal,
        password: password || undefined,
      });
      setNumber("");
      setAgain("");
      setPassword("");
      onSaved(view);
    } catch (e) {
      const code = errCode(e);
      const said = readErr(e, t("le.that_did_not_work"));
      // A missing or mistyped password is a question for this form, not a
      // lapsed session: the API answers 428 or 403 so nobody is signed out.
      if (code === "reauth_required" || code === "wrong_password") {
        setErrors({ password: said });
        setPassword("");
        passwordField.current?.focus();
      } else {
        setFormError(said);
      }
    } finally {
      setBusy(false);
    }
  };

  const field = (
    key: keyof FieldErrors,
    labelText: string,
    input: InputHTMLAttributes<HTMLInputElement>,
    hint?: string,
  ) => {
    const err = errors[key];
    const described = [hint ? `${id}-${key}-hint` : "", err ? `${id}-${key}-error` : ""].filter(Boolean).join(" ");
    return (
      <label htmlFor={`${id}-${key}`}>
        {/* Named by the label text alone; the hint and any error are read
            as its description rather than run into its name. */}
        <span id={`${id}-${key}-label`}>{labelText}</span>
        <input
          {...input}
          id={`${id}-${key}`}
          aria-labelledby={`${id}-${key}-label`}
          aria-invalid={err ? true : undefined}
          aria-describedby={described || undefined}
        />
        {hint && (
          <span className="subtle" id={`${id}-${key}-hint`}>
            {hint}
          </span>
        )}
        {err && (
          <span className="field-error" id={`${id}-${key}-error`}>
            {err}
          </span>
        )}
      </label>
    );
  };

  return (
    <form
      className="bank-form"
      aria-labelledby={`${id}-title`}
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
    >
      <h3 id={`${id}-title`}>{changing ? t("pay.change_bank_details") : t("pay.add_bank_details")}</h3>
      {changing && <p className="pay-warn" role="note">{t("pay.change_waits")}</p>}
      <div className="setup-fields">
        {field(
          "holder",
          t("pay.account_name_exact"),
          { value: holder, maxLength: 70, autoComplete: "off", onChange: (e) => setHolder(e.target.value) },
          t("pay.account_name_hint"),
        )}
        {field(
          "sort",
          t("pay.sort_code"),
          { value: sort, inputMode: "numeric", maxLength: 8, autoComplete: "off", placeholder: "12-34-56", onChange: (e) => setSort(e.target.value) },
        )}
        {field(
          "number",
          t("pay.account_number"),
          { value: number, inputMode: "numeric", maxLength: 10, autoComplete: "off", onChange: (e) => setNumber(e.target.value) },
        )}
        {field(
          "again",
          t("pay.account_number_again"),
          {
            value: again,
            inputMode: "numeric",
            maxLength: 10,
            autoComplete: "off",
            onChange: (e) => setAgain(e.target.value),
            // Typed, not pasted: a pasted copy repeats the same mistake.
            onPaste: (e) => e.preventDefault(),
          },
          t("pay.account_number_again_hint"),
        )}
        {field(
          "label",
          t("pay.nickname_optional"),
          { value: label, maxLength: 60, placeholder: t("pay.nickname_hint"), onChange: (e) => setLabel(e.target.value) },
        )}
      </div>
      <label className="check-row">
        <input type="checkbox" checked={personal} onChange={(e) => setPersonal(e.target.checked)} />
        <span>
          <strong>{t("pay.this_is_personal")}</strong>
          <span className="subtle">{t("pay.this_is_personal_hint")}</span>
        </span>
      </label>
      <div className="setup-fields bank-password">
        <label htmlFor={`${id}-password`}>
          <span id={`${id}-password-label`}>{t("pay.your_password")}</span>
          <input
            ref={passwordField}
            id={`${id}-password`}
            aria-labelledby={`${id}-password-label`}
            type="password"
            autoComplete="current-password"
            value={password}
            aria-invalid={errors.password ? true : undefined}
            aria-describedby={[`${id}-password-hint`, errors.password ? `${id}-password-error` : ""].filter(Boolean).join(" ")}
            onChange={(e) => setPassword(e.target.value)}
          />
          <span className="subtle" id={`${id}-password-hint`}>
            {t("pay.your_password_hint")}
          </span>
          {errors.password && (
            <span className="field-error" id={`${id}-password-error`}>
              {errors.password}
            </span>
          )}
        </label>
      </div>
      {formError && <p className="error" role="alert">{formError}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy}>
          {busy ? t("pay.saving") : submitLabel ?? (changing ? t("pay.save_change") : t("pay.save_bank_details"))}
        </button>
        {onCancel && (
          <button className="btn" type="button" disabled={busy} onClick={onCancel}>
            {t("pay.never_mind")}
          </button>
        )}
      </div>
    </form>
  );
}
