"use client";

/// The club's money, for whoever looks after it: the owner, its secretaries
/// and its treasurers. The bank details players pay into, payments to check
/// against the bank, who owes what, recent bills and the settings.
///
/// The API decides who may open this (a 403 on /money), and this page says so
/// in words rather than showing an empty page.

import { useCallback, useEffect, useId, useRef, useState, type InputHTMLAttributes } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, errCode, isForbidden, money, readErr } from "@/lib/api";
import {
  MAX_SHARE_CENTS,
  STALE_CODES,
  dateTime,
  parseAmount,
  postOnce,
  shortDate,
  toAmount,
  useAttemptKey,
  type MemberBalance,
  type MoneyOverview,
  type Payment,
  type PaymentSettings,
  type PayoutAccount,
  type PayoutAccounts,
} from "@/lib/payments";
import { ReasonForm } from "@/components/ReasonForm";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

export default function ClubPaymentsPage() {
  const t = useT();
  const authed = useRequireAuth();
  const { id: clubId } = useParams<{ id: string }>();
  const [overview, setOverview] = useState<MoneyOverview | null>(null);
  const [forbidden, setForbidden] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!authed || !clubId) return;
    try {
      setOverview(await api<MoneyOverview>("GET", `/clubs/${clubId}/money`));
    } catch (e) {
      if (isForbidden(e)) setForbidden(true);
      else setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [authed, clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  // A notification links to #to-check or #bank-details, which exist only once
  // this has loaded.
  const arrived = useRef(false);
  useEffect(() => {
    if (!overview || arrived.current) return;
    arrived.current = true;
    const target = window.location.hash.slice(1);
    if (target) document.getElementById(target)?.scrollIntoView({ block: "start" });
  }, [overview]);

  if (!authed) return <main id="main" />;
  if (forbidden) {
    return (
      <main id="main" className="page">
        <h1>{t("pay.payments_title")}</h1>
        <p className="muted">{t("pay.only_money_admins")}</p>
        <p>
          <Link href={`/clubs/${clubId}`}>{t("rest.back_to_the_club")}</Link>
        </p>
      </main>
    );
  }
  if (!overview) {
    return (
      <main id="main">
        {error ? <p className="error" role="alert">{error}</p> : <div className="skeleton" style={{ height: 160 }} />}
      </main>
    );
  }

  /// Every change ends the same way: say what happened, and show the page as
  /// it is now — somebody else may have changed something meanwhile.
  const done = async (said: string) => {
    setNotice(said);
    setError(null);
    await load();
  };
  /// A refusal that means the page is behind: reload and say why.
  const stale = async (e: unknown) => {
    setNotice(null);
    setError(readErr(e, t("le.that_did_not_work")));
    await load();
  };

  const cur = overview.currency;
  return (
    <main id="main" className="page money-page">
      <p className="muted">
        <Link href={`/clubs/${clubId}`}>{t("rest.back_to_the_club")}</Link>
      </p>
      <h1>{t("pay.payments_title")}</h1>
      <p className="muted">{t("pay.payments_intro")}</p>

      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      <div className="grid cards money-headline">
        <div className="stat accent">
          <div className="stat-label">{t("pay.to_check")}</div>
          <div className="stat-value num">{money(overview.totals.waiting_cents, cur)}</div>
          <div className="stat-sub">{t("pay.n_payments", { count: overview.to_check.length, n: overview.to_check.length })}</div>
        </div>
        <div className="stat">
          <div className="stat-label">{t("pay.still_owed")}</div>
          <div className="stat-value num">{money(overview.totals.owed_cents, cur)}</div>
        </div>
        <div className="stat">
          <div className="stat-label">{t("pay.credit_held")}</div>
          <div className="stat-value num">{money(overview.totals.credit_cents, cur)}</div>
        </div>
      </div>

      <BankDetailsCard
        clubId={clubId}
        accounts={overview.account}
        onChanged={(view, said) => {
          setOverview({ ...overview, account: view });
          setNotice(said);
          setError(null);
        }}
        onStale={stale}
      />

      <ToCheck payments={overview.to_check} onDone={done} onStale={stale} />

      <WhoOwes clubId={clubId} members={overview.members} currency={cur} onDone={done} />

      <section className="panel" aria-labelledby="recent-bills">
        <h2 id="recent-bills">{t("pay.recent_bills")}</h2>
        {overview.bills.length === 0 ? (
          <p className="muted">{t("pay.no_bills_yet")}</p>
        ) : (
          <ul className="pay-list">
            {overview.bills.map((b) => (
              <li key={b.bill_id}>
                <div>
                  <Link href={`/events/${b.event_id}#money`}>{b.title}</Link>
                  <div className="muted">
                    {shortDate(b.event_start_at)} · {t("pay.n_people", { count: b.people, n: b.people })}
                    {b.unpaid > 0 && ` · ${t("pay.n_unpaid", { n: b.unpaid })}`}
                    {b.waiting > 0 && ` · ${t("pay.n_to_check", { n: b.waiting })}`}
                  </div>
                </div>
                <div className="pay-list-end num">
                  {t("pay.collected_of", { paid: money(b.paid_cents, b.currency), total: money(b.total_cents, b.currency) })}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <Settings
        clubId={clubId}
        settings={overview.settings}
        onSaved={(settings) => {
          setOverview({ ...overview, settings });
          setNotice(t("pay.settings_saved"));
          setError(null);
        }}
      />
    </main>
  );
}

// MARK: bank details

function BankDetailsCard({
  clubId,
  accounts,
  onChanged,
  onStale,
}: {
  clubId: string;
  accounts: PayoutAccounts;
  onChanged: (view: PayoutAccounts, said: string) => void;
  onStale: (e: unknown) => void;
}) {
  const t = useT();
  const nothing = !accounts.current && !accounts.pending && !accounts.frozen;
  const [adding, setAdding] = useState(nothing);
  /// `freeze:<id>` or `remove:<id>`: the question open under one set of details.
  const [asking, setAsking] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!accounts.current && !accounts.pending && !accounts.frozen) setAdding(true);
  }, [accounts]);

  const act = async (path: string, body: unknown, said: string) => {
    setBusy(true);
    setFormError(null);
    try {
      const view = await api<PayoutAccounts>("POST", `/clubs/${clubId}/payout-account/${path}`, body);
      setAsking(null);
      onChanged(view, said);
    } catch (e) {
      // Refused because the details moved on — frozen, removed or gone live
      // meanwhile — or because only the owner may: show them as they are now.
      const status = (e as { status?: number }).status;
      if (status === 409 || status === 403) {
        setAsking(null);
        onStale(e);
      } else {
        setFormError(readErr(e, t("le.that_did_not_work")));
      }
    } finally {
      setBusy(false);
    }
  };

  const block = (a: PayoutAccount, kind: "current" | "pending" | "frozen") => {
    const canRemove = kind !== "frozen" || accounts.is_owner;
    return (
      <div className={`bank-block is-${kind}`} key={a.id}>
        <div className="bank-head">
          <h3>
            {kind === "current" ? t("pay.players_pay_into") : kind === "pending" ? t("pay.change_waiting") : t("pay.frozen_details")}
          </h3>
          {a.is_personal && <span className="tag gold">{t("pay.personal_account")}</span>}
        </div>
        {kind === "pending" && (
          <p className="pay-warn" role="note">
            {t("pay.goes_live_at", { when: dateTime(a.live_from) })}
          </p>
        )}
        {kind === "frozen" && (
          <p className="pay-warn" role="note">
            {a.freeze_reason ? t("pay.frozen_because", { reason: a.freeze_reason }) : t("pay.frozen_note")}
          </p>
        )}
        {!a.readable && <p className="pay-warn" role="note">{t("pay.details_unreadable")}</p>}
        <dl className="bank-facts">
          <div>
            <dt>{t("pay.account_name")}</dt>
            <dd>{a.holder_name}</dd>
          </div>
          <div>
            <dt>{t("pay.sort_code")}</dt>
            <dd className="num">{a.sort_code ?? ""}</dd>
          </div>
          <div>
            <dt>{t("pay.account_number")}</dt>
            <dd className="num">
              <span aria-label={t("pay.ending_in", { last4: a.last4 })}>•••• {a.last4}</span>
            </dd>
          </div>
          <div>
            <dt>{t("pay.nickname")}</dt>
            <dd>{a.label}</dd>
          </div>
        </dl>
        <p className="subtle">
          {a.created_by_name
            ? t("pay.added_by_on", { name: a.created_by_name, date: shortDate(a.created_at) })
            : t("pay.added_on", { date: shortDate(a.created_at) })}
        </p>

        {asking === `freeze:${a.id}` ? (
          <ReasonForm
            label={t("pay.why_freeze")}
            hint={t("pay.freeze_hint")}
            submitLabel={t("pay.freeze")}
            required={false}
            danger
            busy={busy}
            error={formError}
            onCancel={() => setAsking(null)}
            onSubmit={(reason) => void act(`${a.id}/freeze`, { reason: reason || undefined }, t("pay.frozen_done"))}
          />
        ) : asking === `remove:${a.id}` ? (
          <div className="confirm-box" role="group" aria-label={t("pay.remove_details")}>
            <p>{kind === "pending" ? t("pay.cancel_change_confirm") : t("pay.remove_confirm")}</p>
            {formError && <p className="field-error">{formError}</p>}
            <div className="field-row">
              <button
                className="btn danger"
                type="button"
                disabled={busy}
                onClick={() =>
                  void act(`${a.id}/retire`, undefined, kind === "pending" ? t("pay.change_cancelled") : t("pay.details_removed"))
                }
              >
                {kind === "pending" ? t("pay.yes_cancel_change") : t("pay.yes_remove")}
              </button>
              <button className="btn" type="button" disabled={busy} onClick={() => setAsking(null)}>
                {t("pay.never_mind")}
              </button>
            </div>
          </div>
        ) : (
          <div className="field-row">
            {kind !== "frozen" && (
              <button
                className="btn"
                type="button"
                onClick={() => {
                  setFormError(null);
                  setAsking(`freeze:${a.id}`);
                }}
              >
                {t("pay.freeze")}
              </button>
            )}
            {kind === "frozen" && accounts.is_owner && (
              <button
                className="btn primary"
                type="button"
                disabled={busy}
                onClick={() => void act(`${a.id}/unfreeze`, undefined, t("pay.unfrozen_done"))}
              >
                {t("pay.unfreeze")}
              </button>
            )}
            {canRemove && (
              <button
                className="btn ghost"
                type="button"
                onClick={() => {
                  setFormError(null);
                  setAsking(`remove:${a.id}`);
                }}
              >
                {kind === "pending" ? t("pay.cancel_change") : t("pay.remove")}
              </button>
            )}
          </div>
        )}
        {kind === "frozen" && !accounts.is_owner && <p className="subtle">{t("pay.only_owner_unfreezes")}</p>}
      </div>
    );
  };

  return (
    <section className="panel" id="bank-details" aria-labelledby="bank-details-title">
      <div className="panel-head">
        <h2 id="bank-details-title">{t("pay.bank_details")}</h2>
        {!adding && !nothing && accounts.can_manage && (
          <button className="btn" type="button" onClick={() => setAdding(true)}>
            {accounts.current || accounts.pending ? t("pay.change_bank_details") : t("pay.add_bank_details")}
          </button>
        )}
      </div>
      {nothing && <p className="muted">{t("pay.no_details_intro")}</p>}
      {accounts.current && block(accounts.current, "current")}
      {accounts.pending && block(accounts.pending, "pending")}
      {accounts.frozen && block(accounts.frozen, "frozen")}
      {accounts.can_manage && adding && (
        <BankDetailsForm
          clubId={clubId}
          changing={!!accounts.current}
          onCancel={nothing ? undefined : () => setAdding(false)}
          onSaved={(view) => {
            setAdding(false);
            onChanged(
              view,
              view.pending ? t("pay.change_saved", { when: dateTime(view.pending.live_from) }) : t("pay.details_added"),
            );
          }}
        />
      )}
    </section>
  );
}

type FieldErrors = Partial<Record<"holder" | "sort" | "number" | "again" | "label" | "password", string>>;

/// Add or change the club's bank details.
///
/// The account number is typed twice because there is no modulus check yet:
/// one wrong digit would send every player's money somewhere else. The
/// numbers are dropped from the page as soon as they are saved.
function BankDetailsForm({
  clubId,
  changing,
  onCancel,
  onSaved,
}: {
  clubId: string;
  changing: boolean;
  onCancel?: () => void;
  onSaved: (view: PayoutAccounts) => void;
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
          {busy ? t("pay.saving") : changing ? t("pay.save_change") : t("pay.save_bank_details")}
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

// MARK: payments to check

function ToCheck({
  payments,
  onDone,
  onStale,
}: {
  payments: Payment[];
  onDone: (said: string) => Promise<void>;
  onStale: (e: unknown) => Promise<void>;
}) {
  const t = useT();
  const [busy, setBusy] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const decide = async (p: Payment, confirm: boolean, reason?: string) => {
    setBusy(p.id);
    setFormError(null);
    try {
      await api("POST", `/payments/${p.id}/${confirm ? "confirm" : "reject"}`, confirm ? undefined : { reason });
      setRejecting(null);
      await onDone(
        confirm
          ? t("pay.received_done", { name: p.name, amount: money(p.amount_cents, p.currency) })
          : t("pay.not_received_done", { name: p.name }),
      );
    } catch (e) {
      // `already_decided`: somebody else ticked it first.
      if (STALE_CODES.has(errCode(e) ?? "")) {
        setRejecting(null);
        await onStale(e);
      } else if (!confirm) {
        setFormError(readErr(e, t("le.that_did_not_work")));
      } else {
        await onStale(e);
      }
    } finally {
      setBusy(null);
    }
  };

  return (
    <section className="panel" id="to-check" aria-labelledby="to-check-title">
      <div className="panel-head">
        <h2 id="to-check-title">
          {t("pay.payments_to_check")}{" "}
          {payments.length > 0 && <span className="tag gold">{payments.length}</span>}
        </h2>
      </div>
      {payments.length === 0 ? (
        <p className="muted">{t("pay.nothing_to_check")}</p>
      ) : (
        <>
          <p className="muted">{t("pay.to_check_help")}</p>
          <ul className="pay-list check-list">
            {payments.map((p) => (
              <li key={p.id}>
                <div>
                  <strong>{p.name}</strong> <span className="num">{money(p.amount_cents, p.currency)}</span>
                  <div className="muted">
                    {p.method === "cash"
                      ? t("pay.says_cash")
                      : p.reference
                        ? t("pay.by_transfer_ref", { reference: p.reference })
                        : t("pay.by_transfer")}
                    {" · "}
                    {dateTime(p.created_at)}
                  </div>
                  {p.note && <div className="muted">{p.note}</div>}
                </div>
                {rejecting !== p.id && (
                  <div className="pay-list-end">
                    <button
                      className="btn primary"
                      type="button"
                      disabled={busy !== null}
                      aria-label={t("pay.received_from", { name: p.name, amount: money(p.amount_cents, p.currency) })}
                      onClick={() => void decide(p, true)}
                    >
                      {t("pay.received")}
                    </button>
                    <button
                      className="btn"
                      type="button"
                      disabled={busy !== null}
                      aria-label={t("pay.not_received_from", { name: p.name, amount: money(p.amount_cents, p.currency) })}
                      onClick={() => {
                        setFormError(null);
                        setRejecting(p.id);
                      }}
                    >
                      {t("pay.not_received")}
                    </button>
                  </div>
                )}
                {rejecting === p.id && (
                  <ReasonForm
                    label={t("pay.why_not_received")}
                    hint={t("pay.why_not_received_hint", { name: p.name })}
                    submitLabel={t("pay.not_received")}
                    busy={busy !== null}
                    error={formError}
                    onCancel={() => setRejecting(null)}
                    onSubmit={(reason) => void decide(p, false, reason)}
                  />
                )}
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}

// MARK: who owes what

function WhoOwes({
  clubId,
  members,
  currency,
  onDone,
}: {
  clubId: string;
  members: MemberBalance[];
  currency: string;
  onDone: (said: string) => Promise<void>;
}) {
  const t = useT();
  /// `record:<who>` or `refund:<who>`.
  const [open, setOpen] = useState<string | null>(null);
  const who = (m: MemberBalance) => m.user_id ?? `guest:${m.guest_name ?? m.name}`;

  return (
    <section className="panel" aria-labelledby="who-owes-title">
      <h2 id="who-owes-title">{t("pay.who_owes_what")}</h2>
      {members.length === 0 ? (
        <p className="muted">{t("pay.nobody_owes")}</p>
      ) : (
        <ul className="pay-list owes-list">
          {members.map((m) => (
            <li key={who(m)}>
              <div>
                <strong>{m.name}</strong> {m.user_id == null && <span className="tag grey">{t("pay.guest")}</span>}
                <div className="muted num">
                  {[
                    m.owed_cents > 0 && t("pay.owes_amount", { amount: money(m.owed_cents, currency) }),
                    m.waiting_cents > 0 && t("pay.amount_to_check", { amount: money(m.waiting_cents, currency) }),
                    m.credit_cents > 0 && t("pay.amount_in_credit", { amount: money(m.credit_cents, currency) }),
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
              </div>
              {open?.endsWith(`:${who(m)}`) ? null : (
                <div className="pay-list-end">
                  <button
                    className="btn"
                    type="button"
                    aria-label={t("pay.record_cash_for", { name: m.name })}
                    onClick={() => setOpen(`record:${who(m)}`)}
                  >
                    {t("pay.record_cash")}
                  </button>
                  {m.credit_cents > 0 && (
                    <button
                      className="btn ghost"
                      type="button"
                      aria-label={t("pay.refund_for", { name: m.name })}
                      onClick={() => setOpen(`refund:${who(m)}`)}
                    >
                      {t("pay.refund")}
                    </button>
                  )}
                </div>
              )}
              {open === `record:${who(m)}` && (
                <MoneyForm
                  clubId={clubId}
                  member={m}
                  currency={currency}
                  kind="record"
                  onCancel={() => setOpen(null)}
                  onDone={async (said) => {
                    setOpen(null);
                    await onDone(said);
                  }}
                />
              )}
              {open === `refund:${who(m)}` && (
                <MoneyForm
                  clubId={clubId}
                  member={m}
                  currency={currency}
                  kind="refund"
                  onCancel={() => setOpen(null)}
                  onDone={async (said) => {
                    setOpen(null);
                    await onDone(said);
                  }}
                />
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/// "Record cash" or "Refund", for one person. Confirmed as soon as it is
/// saved, so it is sent with a one-time key: a retry on bad signal cannot
/// record the same tenner twice.
function MoneyForm({
  clubId,
  member: m,
  currency,
  kind,
  onCancel,
  onDone,
}: {
  clubId: string;
  member: MemberBalance;
  currency: string;
  kind: "record" | "refund";
  onCancel: () => void;
  onDone: (said: string) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const start = kind === "refund" ? m.credit_cents : m.owed_cents;
  const [amount, setAmount] = useState(start > 0 ? toAmount(start) : "");
  const [method, setMethod] = useState<"cash" | "transfer">("cash");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const attempt = useAttemptKey();

  const cents = parseAmount(amount);
  const problem =
    amount.trim() && (cents == null || cents <= 0)
      ? t("pay.not_an_amount")
      : kind === "refund" && cents != null && cents > m.credit_cents
        ? t("pay.refund_at_most", { amount: money(m.credit_cents, currency) })
        : kind === "record" && cents != null && cents > MAX_SHARE_CENTS
          ? t("pay.too_much_each", { max: money(MAX_SHARE_CENTS, currency) })
          : null;
  const said = problem ?? error;

  const submit = async () => {
    if (cents == null || problem) return;
    setBusy(true);
    setError(null);
    const body = {
      user_id: m.user_id ?? undefined,
      guest_name: m.user_id ? undefined : (m.guest_name ?? m.name),
      amount_cents: cents,
      method: kind === "record" ? method : undefined,
      note: note.trim() || undefined,
    };
    try {
      await postOnce<Payment>(
        `/clubs/${clubId}/payments/${kind}`,
        body,
        attempt.key(JSON.stringify([kind, body])),
      );
      attempt.done();
      await onDone(
        kind === "record"
          ? t("pay.recorded_done", { name: m.name, amount: money(cents, currency) })
          : t("pay.refund_done", { name: m.name, amount: money(cents, currency) }),
      );
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      className="money-form"
      aria-label={kind === "record" ? t("pay.record_cash_for", { name: m.name }) : t("pay.refund_for", { name: m.name })}
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
    >
      <div className="setup-fields">
        <label htmlFor={`${id}-amount`}>
          <span id={`${id}-amount-label`}>{kind === "record" ? t("pay.amount_paid") : t("pay.amount_to_refund")}</span>
          <input
            id={`${id}-amount`}
            aria-labelledby={`${id}-amount-label`}
            inputMode="decimal"
            value={amount}
            autoFocus
            aria-invalid={said ? true : undefined}
            aria-describedby={said ? `${id}-error` : undefined}
            onChange={(e) => setAmount(e.target.value)}
          />
          {said && (
            <span className="field-error" id={`${id}-error`}>
              {said}
            </span>
          )}
        </label>
        {kind === "record" && (
          <label htmlFor={`${id}-method`}>
            {t("pay.how_they_paid")}
            <select id={`${id}-method`} value={method} onChange={(e) => setMethod(e.target.value as "cash" | "transfer")}>
              <option value="cash">{t("pay.method_cash")}</option>
              <option value="transfer">{t("pay.method_transfer")}</option>
            </select>
          </label>
        )}
        <label htmlFor={`${id}-note`}>
          {t("pay.note_optional")}
          <input id={`${id}-note`} value={note} maxLength={200} onChange={(e) => setNote(e.target.value)} />
        </label>
      </div>
      {kind === "refund" && <p className="subtle">{t("pay.refund_hint", { name: m.name })}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy || cents == null || !!problem}>
          {kind === "record" ? t("pay.record_it") : t("pay.refund_it")}
        </button>
        <button className="btn" type="button" disabled={busy} onClick={onCancel}>
          {t("pay.never_mind")}
        </button>
      </div>
    </form>
  );
}

// MARK: settings

function Settings({
  clubId,
  settings,
  onSaved,
}: {
  clubId: string;
  settings: PaymentSettings;
  onSaved: (s: PaymentSettings) => void;
}) {
  const t = useT();
  const id = useId();
  const [autoBill, setAutoBill] = useState(settings.auto_bill);
  const [hours, setHours] = useState(String(settings.auto_bill_after_hours));
  const [roundUp, setRoundUp] = useState(settings.round_shares_up);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const h = Number(hours);
  const hoursOk = Number.isInteger(h) && h >= 1 && h <= 336;

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      onSaved(
        await api<PaymentSettings>("PUT", `/clubs/${clubId}/payments/settings`, {
          auto_bill: autoBill,
          auto_bill_after_hours: autoBill && hoursOk ? h : undefined,
          round_shares_up: roundUp,
        }),
      );
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>{t("pay.settings")}</h2>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void save();
        }}
      >
        <label className="check-row">
          <input type="checkbox" checked={autoBill} onChange={(e) => setAutoBill(e.target.checked)} />
          <span>
            <strong>{t("pay.auto_bill")}</strong>
            <span className="subtle">{t("pay.auto_bill_hint")}</span>
          </span>
        </label>
        {autoBill && (
          <div className="setup-fields money-hours">
            <label htmlFor={`${id}-hours`}>
              <span id={`${id}-hours-label`}>{t("pay.auto_bill_after")}</span>
              <input
                id={`${id}-hours`}
                aria-labelledby={`${id}-hours-label`}
                type="number"
                inputMode="numeric"
                min={1}
                max={336}
                value={hours}
                aria-invalid={hoursOk ? undefined : true}
                aria-describedby={hoursOk ? undefined : `${id}-hours-error`}
                onChange={(e) => setHours(e.target.value)}
              />
              {!hoursOk && (
                <span className="field-error" id={`${id}-hours-error`}>
                  {t("pay.hours_range")}
                </span>
              )}
            </label>
          </div>
        )}
        <label className="check-row">
          <input type="checkbox" checked={roundUp} onChange={(e) => setRoundUp(e.target.checked)} />
          <span>
            <strong>{t("pay.round_up")}</strong>
            <span className="subtle">{t("pay.round_up_hint")}</span>
          </span>
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn primary" type="submit" disabled={busy || (autoBill && !hoursOk)}>
            {t("pay.save_settings")}
          </button>
        </div>
      </form>
    </section>
  );
}
