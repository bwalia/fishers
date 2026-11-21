"use client";

/// Paying the club, signed in (plan §5.2): what you owe and what for, who the
/// money goes to, the four things your banking app asks for — each with a
/// Copy button — then "I've paid" or "I paid cash". After that, "Thanks —
/// waiting for Aman to check", with Undo and Add a screenshot.
///
/// The app never touches the money. It goes from the player's bank to the
/// club's; this page only says where, and records that they say they sent it.
/// A treasurer confirms it once it shows up. The same design as the public
/// pay page (`/p/<token>`), so a player sees one thing whichever way in.

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, errCode, money, readErr } from "@/lib/api";
import {
  STALE_CODES,
  checker,
  dateTime,
  markPaidBefore,
  postImage,
  postOnce,
  shareDate,
  shareStateLabel,
  shareStateTag,
  useAttemptKey,
  type PayScreen,
  type Payment,
} from "@/lib/payments";
import { PayDetails, SendDetails } from "@/components/PayDetails";
import { ScreenshotButton } from "@/components/ScreenshotButton";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// A screenshot is taken up to two hours after the payment is said.
const SCREENSHOT_MS = 120 * 60_000;

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

  const owes = pay.owed_cents > 0;
  const account = pay.account_state === "active" ? pay.account : null;
  const who = checker(pay.account);
  // What it's for, in one line when it is one thing: "You owe £5 for Friday nets".
  const owing = pay.shares.filter((s) => s.state === "owed" || s.state === "part_paid");
  const forTitle = owing.length === 1 ? owing[0].title : null;
  const amount = money(pay.owed_cents, pay.currency);

  const claim = async (method: "transfer" | "cash") => {
    setBusy(method);
    setError(null);
    setNotice(null);
    try {
      // Everything owed, in one go: the body names no amount. The key is the
      // same for every press of this button until one works, so tapping
      // twice on a bad signal still makes one payment.
      await postOnce<Payment>(`/clubs/${clubId}/payments`, { method }, attempt.key(`${method}:${pay.owed_cents}`));
      attempt.done();
      if (method === "transfer" && account) markPaidBefore(account);
      await load();
      document.getElementById("pay-waiting")?.focus();
    } catch (e) {
      // `nothing_owed`: already said, perhaps on another device. The
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

  return (
    <main id="main" className="page pay-page">
      <p className="muted">
        <Link href="/profile/payments">{t("pay.back_to_your_payments")}</Link>
      </p>
      <h1>{t("pay.pay_club", { club: pay.club_name })}</h1>

      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="panel pay-sum" aria-labelledby="pay-owe">
        <p className="pay-headline" id="pay-owe">
          {owes
            ? forTitle
              ? t("pw2.you_owe_for", { amount, title: forTitle })
              : t("pay.you_owe_amount", { amount })
            : pay.waiting_cents > 0
              ? t("pay.said_you_paid")
              : t("pay.all_paid_up")}
        </p>
        {owes && pay.waiting_cents > 0 && (
          <p className="muted">{t("pay.amount_waiting", { amount: money(pay.waiting_cents, pay.currency) })}</p>
        )}
        {pay.credit_cents > 0 && (
          <p className="muted">{t("pay.amount_credit", { amount: money(pay.credit_cents, pay.currency) })}</p>
        )}
      </section>

      {owes && account && (
        <section className="panel" aria-label={t("pay.how_to_pay")}>
          <PayDetails account={account} reference={pay.reference} amountCents={pay.owed_cents} currency={pay.currency} />
          <p className="pay-then">{t("pw2.then_tap")}</p>
          <div className="pay-buttons">
            <button
              className="btn primary xl"
              type="button"
              disabled={busy !== null}
              aria-describedby={error ? "pay-error" : undefined}
              onClick={() => void claim("transfer")}
            >
              {busy === "transfer" ? t("pay.sending") : t("pay.ive_paid")}
            </button>
            <button
              className="btn xl"
              type="button"
              disabled={busy !== null}
              aria-describedby={error ? "pay-error" : undefined}
              onClick={() => void claim("cash")}
            >
              {busy === "cash" ? t("pay.sending") : t("pay.i_paid_cash")}
            </button>
          </div>
          {error && <p className="field-error" id="pay-error" role="alert">{error}</p>}
          <SendDetails
            account={account}
            reference={pay.reference}
            amountCents={pay.owed_cents}
            currency={pay.currency}
            title={forTitle ?? pay.club_name}
          />
        </section>
      )}

      {owes && !account && (
        <section className="panel" aria-labelledby="pay-how">
          <AccountProblem state={pay.account_state} />
          {/* "Don't pay yet" means it: no button to say otherwise. */}
          {pay.account_state !== "frozen" && (
            <div className="pay-buttons">
              <button className="btn primary xl" type="button" disabled={busy !== null} onClick={() => void claim("cash")}>
                {busy === "cash" ? t("pay.sending") : t("pay.i_paid_cash")}
              </button>
            </div>
          )}
          {error && <p className="field-error" role="alert">{error}</p>}
        </section>
      )}

      {!owes && error && <p className="error" role="alert">{error}</p>}

      {pay.claims.length > 0 && (
        <section className="panel pay-waiting" aria-labelledby="pay-waiting">
          <h2 id="pay-waiting" tabIndex={-1}>
            {who ? t("pw2.thanks_waiting", { first: who }) : t("pw2.thanks_waiting_club")}
          </h2>
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
                  {c.method === "transfer" && Date.now() - new Date(c.created_at).getTime() < SCREENSHOT_MS && (
                    <ScreenshotButton
                      done={!!c.has_screenshot}
                      who={who}
                      upload={(image) => postImage(`/payments/${c.id}/screenshot`, image)}
                      onUploaded={load}
                    />
                  )}
                </div>
                <button
                  className="btn"
                  type="button"
                  disabled={busy !== null}
                  aria-label={t("pw2.undo_amount", { amount: money(c.amount_cents, c.currency) })}
                  onClick={() => void undo(c)}
                >
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
                  {s.event_id ? <Link href={`/events/${s.event_id}#money`}>{s.title}</Link> : <strong>{s.title}</strong>}
                  <div className="muted">{shareDate(s)}</div>
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

/// Why there are no bank details to copy, in the same words as the pay link.
function AccountProblem({ state }: { state: string }) {
  const t = useT();
  const [title, body]: [Key, Key] =
    state === "frozen"
      ? ["pw2.frozen_title", "pw2.frozen_body"]
      : state === "unreadable"
        ? ["pw2.unreadable_title", "pw2.unreadable_body"]
        : ["pw2.none_title", "pw2.none_body"];
  return (
    <div className={`paylink-state small is-${state}`} role="note">
      <h2 id="pay-how">{t(title)}</h2>
      <p>{t(body)}</p>
    </div>
  );
}
