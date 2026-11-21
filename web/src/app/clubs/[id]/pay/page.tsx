"use client";

/// Paying the club: the amount, the club's bank details and your reference,
/// each ready to copy into a banking app, then "I've paid".
///
/// The app never touches the money. It goes from the player's bank to the
/// club's; this page only says where, and records that they say they sent it.
/// A treasurer confirms it once it shows up.

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, errCode, money, readErr } from "@/lib/api";
import {
  STALE_CODES,
  dateTime,
  postOnce,
  shareStateLabel,
  shareStateTag,
  shortDate,
  useAttemptKey,
  type PayScreen,
  type Payment,
} from "@/lib/payments";
import { CopyButton } from "@/components/CopyButton";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

export default function PayPage() {
  const t = useT();
  const authed = useRequireAuth();
  const { id: clubId } = useParams<{ id: string }>();
  const [pay, setPay] = useState<PayScreen | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const attempt = useAttemptKey();

  const load = useCallback(async () => {
    if (!authed || !clubId) return;
    try {
      setPay(await api<PayScreen>("GET", `/clubs/${clubId}/pay`));
      setLoadError(null);
    } catch (e) {
      setLoadError(readErr(e, t("le.something_went_wrong")));
    }
  }, [authed, clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!authed) return <main id="main" />;
  if (!pay) {
    return (
      <main id="main">
        {loadError ? <p className="error" role="alert">{loadError}</p> : <div className="skeleton" style={{ height: 240 }} />}
      </main>
    );
  }

  const claim = async (method: "transfer" | "cash") => {
    setBusy(method);
    setError(null);
    setNotice(null);
    try {
      // Everything owed, in one go: the body names no amount. The key is the
      // same for every press of this button until one works, so tapping
      // twice on a bad signal still makes one claim.
      await postOnce<Payment>(`/clubs/${clubId}/payments`, { method }, attempt.key(`${method}:${pay.owed_cents}`));
      attempt.done();
      setNotice(method === "transfer" ? t("pay.claimed_transfer") : t("pay.claimed_cash"));
      await load();
    } catch (e) {
      // `nothing_owed`: already claimed, perhaps on another device. The
      // server's sentence says which, and the page catches up.
      if (STALE_CODES.has(errCode(e) ?? "")) {
        attempt.done();
        await load();
      }
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(null);
    }
  };

  const undo = async (p: Payment) => {
    setBusy(p.id);
    setError(null);
    setNotice(null);
    try {
      await api("DELETE", `/payments/${p.id}`);
      setNotice(t("pay.claim_undone"));
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      await load();
      setBusy(null);
    }
  };

  const owes = pay.owed_cents > 0;
  const account = pay.account_state === "active" ? pay.account : null;

  return (
    <main id="main" className="page pay-page">
      <p className="muted">
        <Link href="/profile/payments">{t("pay.back_to_your_payments")}</Link>
      </p>
      <h1>{t("pay.pay_club", { club: pay.club_name })}</h1>

      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="panel pay-sum" aria-labelledby="pay-owe">
        <p className="stat-label" id="pay-owe">{t("pay.you_owe")}</p>
        <p className="pay-big num">{money(pay.owed_cents, pay.currency)}</p>
        {pay.waiting_cents > 0 && (
          <p className="muted">{t("pay.amount_waiting", { amount: money(pay.waiting_cents, pay.currency) })}</p>
        )}
        {pay.credit_cents > 0 && (
          <p className="muted">{t("pay.amount_credit", { amount: money(pay.credit_cents, pay.currency) })}</p>
        )}
        {!owes && pay.waiting_cents === 0 && <p>{t("pay.all_paid_up")}</p>}
        {!owes && pay.waiting_cents > 0 && <p>{t("pay.said_you_paid")}</p>}
      </section>

      {owes && account && (
        <section className="panel" aria-labelledby="pay-how">
          <h2 id="pay-how">{t("pay.pay_by_bank_transfer")}</h2>
          {account.changed_at && (
            <p className="pay-warn" role="note">
              {t("pay.details_changed_on", { date: shortDate(account.changed_at) })}
            </p>
          )}
          {account.is_personal && (
            <p className="muted">
              <span className="tag gold">{t("pay.personal_account")}</span>{" "}
              {t("pay.personal_account_note", { name: account.holder_name })}
            </p>
          )}
          <dl className="pay-details">
            <Detail term={t("pay.amount")} value={money(pay.owed_cents, pay.currency)} copy={(pay.owed_cents / 100).toFixed(2)} />
            <Detail term={t("pay.account_name")} value={account.holder_name} />
            <Detail term={t("pay.sort_code")} value={account.sort_code} />
            <Detail term={t("pay.account_number")} value={account.account_number} />
            <Detail term={t("pay.reference")} value={pay.reference} />
          </dl>
          <p className="subtle">{t("pay.reference_why")}</p>
          <CopyButton
            what={t("pay.all_the_details")}
            label={t("pay.copy_all")}
            text={[
              `${t("pay.amount")}: ${money(pay.owed_cents, pay.currency)}`,
              `${t("pay.account_name")}: ${account.holder_name}`,
              `${t("pay.sort_code")}: ${account.sort_code}`,
              `${t("pay.account_number")}: ${account.account_number}`,
              `${t("pay.reference")}: ${pay.reference}`,
            ].join("\n")}
          />

          <p className="pay-then">{t("pay.then_tap")}</p>
          <div className="field-row">
            <button className="btn primary lg" type="button" disabled={busy !== null} onClick={() => void claim("transfer")}>
              {busy === "transfer" ? t("pay.sending") : t("pay.ive_paid")}
            </button>
            <button className="btn ghost" type="button" disabled={busy !== null} onClick={() => void claim("cash")}>
              {t("pay.i_paid_cash")}
            </button>
          </div>
        </section>
      )}

      {owes && !account && (
        <section className="panel" aria-labelledby="pay-how">
          <h2 id="pay-how">{t("pay.how_to_pay")}</h2>
          <p className={pay.account_state === "frozen" ? "pay-warn" : undefined} role="note">
            {pay.account_state === "frozen"
              ? t("pay.state_frozen")
              : pay.account_state === "unreadable"
                ? t("pay.state_unreadable")
                : t("pay.state_none")}
          </p>
          <button className="btn" type="button" disabled={busy !== null} onClick={() => void claim("cash")}>
            {t("pay.i_paid_cash")}
          </button>
        </section>
      )}

      {pay.claims.length > 0 && (
        <section className="panel" aria-labelledby="pay-claims">
          <h2 id="pay-claims">{t("pay.waiting_for_the_club")}</h2>
          <ul className="pay-list">
            {pay.claims.map((c) => (
              <li key={c.id}>
                <div>
                  <strong className="num">{money(c.amount_cents, c.currency)}</strong>{" "}
                  <span className="muted">
                    {c.method === "cash" ? t("pay.in_cash") : t("pay.by_transfer_ref", { reference: c.reference ?? "" })}
                    {" · "}
                    {dateTime(c.created_at)}
                  </span>
                </div>
                <button className="btn" type="button" disabled={busy !== null} onClick={() => void undo(c)}>
                  {t("pay.undo")}
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {pay.shares.length > 0 && (
        <section className="panel" aria-labelledby="pay-for">
          <h2 id="pay-for">{t("pay.what_its_for")}</h2>
          <ul className="pay-list">
            {pay.shares.map((s) => (
              <li key={s.id}>
                <div>
                  <Link href={`/events/${s.event_id}#money`}>{s.title}</Link>
                  <div className="muted">{shortDate(s.event_start_at)}</div>
                </div>
                <div className="pay-list-end">
                  <span className="num">{money(s.amount_cents, s.currency)}</span>
                  <span className={shareStateTag(s.state)}>{shareStateLabel(s.state, t)}</span>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
    </main>
  );
}

/// One line of the details: what it is, the value, and a button to copy it.
function Detail({ term, value, copy }: { term: string; value: string; copy?: string }) {
  return (
    <div className="pay-detail">
      <dt>{term}</dt>
      <dd>
        <span className="pay-value">{value}</span>
        <CopyButton text={copy ?? value} what={term.toLowerCase()} />
      </dd>
    </div>
  );
}
