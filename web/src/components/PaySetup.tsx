"use client";

/// Setting up payments the first time (plan §5.3), for whoever looks after
/// the club's money when the club has no bank details and no usual prices:
///
///   1. where players send money — with exactly what they will see;
///   2. what you usually charge for nets and for a match;
///   3. done: after each session, share the bill to WhatsApp.
///
/// Every step can be skipped, and the wizard can be put off: it is a quicker
/// way through the Payments page, not a gate in front of it.

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { api, getStoredUser, money, readErr, type MyRole } from "@/lib/api";
import { parseAmount, toAmount, type BankDetails, type PaymentSettings, type PayoutAccounts } from "@/lib/payments";
import { surnameRef } from "@/lib/pay-link";
import { BankDetailsForm, type BankDraft } from "@/components/BankDetailsForm";
import { CostModePicker, costCheck } from "@/components/EventMoney";
import { PayDetails } from "@/components/PayDetails";
import { useT } from "@/lib/i18n/provider";

/// "Set up later", remembered per club in this browser.
export const setupPutOffKey = (clubId: string) => `fishers:pay-setup-later:${clubId}`;

export function setupPutOff(clubId: string): boolean {
  try {
    return localStorage.getItem(setupPutOffKey(clubId)) === "1";
  } catch {
    return false;
  }
}

/// Whether the club is still at the very start: nothing to pay into and
/// nothing it usually charges.
export function needsSetup(accounts: PayoutAccounts, settings: PaymentSettings): boolean {
  return (
    accounts.can_manage &&
    !accounts.current &&
    !accounts.pending &&
    !accounts.frozen &&
    settings.default_nets_cents == null &&
    settings.default_match_fee_cents == null
  );
}

export function SetupWizard({
  clubId,
  currency,
  settings,
  onAccounts,
  onSettings,
  onClose,
}: {
  clubId: string;
  currency: string;
  settings: PaymentSettings;
  onAccounts: (view: PayoutAccounts) => void;
  onSettings: (s: PaymentSettings) => void;
  /// Finished, or put off for later.
  onClose: (putOff: boolean) => void;
}) {
  const t = useT();
  const id = useId();
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [draft, setDraft] = useState<BankDraft>({ holder: "", sort: "", number: "", personal: false });
  const [role, setRole] = useState<MyRole | null>(null);
  const onDraft = useCallback((d: BankDraft) => setDraft(d), []);

  useEffect(() => {
    api<MyRole>("GET", `/clubs/${clubId}/my-role`).then(setRole).catch(() => setRole(null));
  }, [clubId]);

  // Focus follows the step, so a screen reader hears it change — but not on
  // arrival, where it would jump past everything above the wizard.
  const shown = useRef(step);
  useEffect(() => {
    if (shown.current !== step) document.getElementById(`${id}-step`)?.focus();
    shown.current = step;
  }, [id, step]);

  // The preview is the pay screen itself, drawn from what is typed so far.
  const digits = (s: string) => s.replace(/\D/g, "");
  const sort = digits(draft.sort);
  const preview: BankDetails = {
    label: "",
    holder_name: draft.holder.trim() || t("pw2.preview_holder"),
    sort_code: sort.length === 6 ? `${sort.slice(0, 2)}-${sort.slice(2, 4)}-${sort.slice(4)}` : draft.sort.trim() || "00-00-00",
    account_number: digits(draft.number) || "00000000",
    is_personal: draft.personal,
    changed_at: null,
    // Who the server will say it is: the treasurer first, as it does.
    payee_role: draft.personal
      ? role?.is_treasurer
        ? "treasurer"
        : role?.is_secretary
          ? "secretary"
          : role?.is_owner
            ? "owner"
            : null
      : null,
  };
  const me = typeof window !== "undefined" ? getStoredUser() : null;

  return (
    <section className="panel setup-wizard" aria-labelledby={`${id}-step`}>
      <div className="panel-head">
        <p className="stat-label">{t("pw2.setup_step", { n: step })}</p>
        {step < 3 && (
          <button className="btn ghost" type="button" onClick={() => onClose(true)}>
            {t("pw2.setup_later")}
          </button>
        )}
      </div>

      {step === 1 && (
        <>
          <h2 id={`${id}-step`} tabIndex={-1}>
            {t("pw2.setup_bank_title")}
          </h2>
          <p className="muted">{t("pw2.setup_bank_help")}</p>
          <div className="setup-split">
            <BankDetailsForm
              clubId={clubId}
              changing={false}
              onDraft={onDraft}
              submitLabel={t("pw2.save_and_next")}
              onSaved={(view) => {
                onAccounts(view);
                setStep(2);
              }}
            />
            <div className="setup-preview" aria-labelledby={`${id}-preview`}>
              <h3 id={`${id}-preview`}>{t("pw2.preview_title")}</h3>
              <p className="subtle">{t("pw2.preview_help")}</p>
              <div className="setup-preview-card">
                <p className="pay-headline">{t("pw2.you_owe_for", { amount: money(500, currency), title: t("pw2.preview_event") })}</p>
                <PayDetails
                  account={preview}
                  reference={me ? surnameRef(me.name) || "SMITH" : "SMITH"}
                  amountCents={500}
                  currency={currency}
                  headingLevel={3}
                />
              </div>
            </div>
          </div>
          <div className="field-row">
            <button className="btn ghost" type="button" onClick={() => setStep(2)}>
              {t("pw2.skip_step")}
            </button>
          </div>
        </>
      )}

      {step === 2 && (
        <>
          <h2 id={`${id}-step`} tabIndex={-1}>
            {t("pw2.setup_prices_title")}
          </h2>
          <p className="muted">{t("pw2.setup_prices_help")}</p>
          <UsualPrices
            clubId={clubId}
            currency={currency}
            settings={settings}
            submitLabel={t("pw2.save_and_next")}
            onSaved={(s) => {
              onSettings(s);
              setStep(3);
            }}
          />
          <div className="field-row">
            <button className="btn ghost" type="button" onClick={() => setStep(3)}>
              {t("pw2.skip_step")}
            </button>
          </div>
        </>
      )}

      {step === 3 && (
        <>
          <h2 id={`${id}-step`} tabIndex={-1}>
            {t("pw2.setup_done_title")}
          </h2>
          <ol className="setup-done">
            <li>{t("pw2.setup_done_1")}</li>
            <li>{t("pw2.setup_done_2")}</li>
            <li>{t("pw2.setup_done_3")}</li>
          </ol>
          <button className="btn primary lg" type="button" onClick={() => onClose(false)}>
            {t("pw2.setup_finish")}
          </button>
        </>
      )}
    </section>
  );
}

/// The club's usual nets price and match fee, offered on every new session
/// so nobody types them each week.
export function UsualPrices({
  clubId,
  currency,
  settings,
  submitLabel,
  onSaved,
}: {
  clubId: string;
  currency: string;
  settings: PaymentSettings;
  submitLabel?: string;
  onSaved: (s: PaymentSettings) => void;
}) {
  const t = useT();
  const id = useId();
  const [mode, setMode] = useState(settings.default_nets_mode ?? "");
  const [nets, setNets] = useState(settings.default_nets_cents != null ? toAmount(settings.default_nets_cents) : "");
  const [fee, setFee] = useState(settings.default_match_fee_cents != null ? toAmount(settings.default_match_fee_cents) : "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const netsCheck = costCheck(mode, nets, currency, t);
  const feeCheck = costCheck("per_player", fee, currency, t);
  const netsMissing = !!mode && !nets.trim();
  const netsProblem = netsCheck.problem ?? (netsMissing ? t("pw2.price_missing") : null);
  const feeProblem = feeCheck.problem;

  const save = async () => {
    if (netsProblem || feeProblem) return;
    setBusy(true);
    setError(null);
    try {
      const feeCents = fee.trim() ? parseAmount(fee) : null;
      onSaved(
        await api<PaymentSettings>("PUT", `/clubs/${clubId}/payments/settings`, {
          default_nets: mode && netsCheck.cents != null ? { mode, amount_cents: netsCheck.cents } : null,
          default_match_fee_cents: feeCents,
        }),
      );
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      className="usual-prices"
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <fieldset className="setup-group">
        <legend>{t("pw2.usual_nets")}</legend>
        <CostModePicker mode={mode} onMode={setMode} withNone />
        {mode && (
          <div className="setup-fields">
            <label htmlFor={`${id}-nets`}>
              <span id={`${id}-nets-label`}>{mode === "split_total" ? t("pay.total_to_split") : t("pay.each_person_pays")}</span>
              <input
                id={`${id}-nets`}
                aria-labelledby={`${id}-nets-label`}
                inputMode="decimal"
                value={nets}
                placeholder={mode === "split_total" ? "60.00" : "5.00"}
                aria-invalid={netsProblem ? true : undefined}
                aria-describedby={netsProblem ? `${id}-nets-error` : `${id}-nets-hint`}
                onChange={(e) => setNets(e.target.value)}
              />
              <span className="subtle" id={`${id}-nets-hint`}>
                {mode === "split_total" ? t("pay.split_hint") : t("pay.each_hint")}
              </span>
              {netsProblem && (
                <span className="field-error" id={`${id}-nets-error`}>
                  {netsProblem}
                </span>
              )}
            </label>
          </div>
        )}
      </fieldset>
      <div className="setup-fields">
        <label htmlFor={`${id}-fee`}>
          <span id={`${id}-fee-label`}>{t("pw2.usual_match_fee")}</span>
          <input
            id={`${id}-fee`}
            aria-labelledby={`${id}-fee-label`}
            inputMode="decimal"
            value={fee}
            placeholder="5.00"
            aria-invalid={feeProblem ? true : undefined}
            aria-describedby={feeProblem ? `${id}-fee-error` : `${id}-fee-hint`}
            onChange={(e) => setFee(e.target.value)}
          />
          <span className="subtle" id={`${id}-fee-hint`}>
            {t("pw2.usual_match_fee_hint")}
          </span>
          {feeProblem && (
            <span className="field-error" id={`${id}-fee-error`}>
              {feeProblem}
            </span>
          )}
        </label>
      </div>
      {error && <p className="field-error" role="alert">{error}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy || !!netsProblem || !!feeProblem}>
          {submitLabel ?? t("pw2.save_usual_prices")}
        </button>
      </div>
    </form>
  );
}
