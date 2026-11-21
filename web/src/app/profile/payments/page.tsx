"use client";

/// Everything you owe, across all your clubs, and what you paid lately.
/// Each club opens its own pay screen: a transfer goes to one club's account,
/// so paying is always per club.

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, money, readErr } from "@/lib/api";
import { shareDate, shareStateLabel, shareStateTag, type Dues } from "@/lib/payments";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

export default function YourPaymentsPage() {
  const t = useT();
  const authed = useRequireAuth();
  const [dues, setDues] = useState<Dues | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!authed) return;
    api<Dues>("GET", "/me/dues")
      .then(setDues)
      .catch((e) => setError(readErr(e, t("le.something_went_wrong"))));
  }, [authed, t]);

  if (!authed) return <main id="main" />;

  return (
    <main id="main" className="page">
      <p className="muted">
        <Link href="/profile">{t("pay.back_to_profile")}</Link>
      </p>
      <h1>{t("pay.your_payments")}</h1>
      <p className="muted">{t("pay.your_payments_intro")}</p>

      {error && <p className="error" role="alert">{error}</p>}
      {!dues && !error && <div className="skeleton" style={{ height: 160 }} />}
      {dues && dues.clubs.length === 0 && (
        <div className="panel">
          <p className="muted">{t("pay.nothing_billed_yet")}</p>
        </div>
      )}

      {dues?.clubs.map((c) => (
        <section className="panel" key={c.club_id} aria-labelledby={`dues-${c.club_id}`}>
          <div className="panel-head">
            <h2 id={`dues-${c.club_id}`}>{c.club_name}</h2>
            {c.owed_cents > 0 && (
              <Link className="btn primary" href={`/clubs/${c.club_id}/pay`}>
                {t("pay.pay_amount", { amount: money(c.owed_cents, c.currency) })}
              </Link>
            )}
          </div>
          <p>
            {c.owed_cents > 0
              ? t("pay.you_owe_amount", { amount: money(c.owed_cents, c.currency) })
              : c.waiting_cents > 0
                ? t("pay.said_you_paid")
                : t("pay.all_paid_up")}
          </p>
          {c.waiting_cents > 0 && (
            <p className="muted">{t("pay.amount_waiting", { amount: money(c.waiting_cents, c.currency) })}</p>
          )}
          {c.credit_cents > 0 && (
            <p className="muted">{t("pay.amount_credit", { amount: money(c.credit_cents, c.currency) })}</p>
          )}
          {c.shares.length > 0 && (
            <ul className="pay-list">
              {c.shares.map((s) => (
                <li key={s.id}>
                  <div>
                    {s.event_id ? <Link href={`/events/${s.event_id}#money`}>{s.title}</Link> : <strong>{s.title}</strong>}
                    <div className="muted">
                      {shareDate(s)}
                      {s.state === "waiting" && ` · ${t("pay.waiting_for_the_club")}`}
                      {s.state === "part_paid" &&
                        ` · ${t("pay.paid_of", { paid: money(s.paid_cents, s.currency), amount: money(s.amount_cents, s.currency) })}`}
                    </div>
                  </div>
                  <div className="pay-list-end">
                    <span className="num">{money(s.amount_cents, s.currency)}</span>
                    <span className={shareStateTag(s.state)}>{shareStateLabel(s.state, t)}</span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      ))}
    </main>
  );
}
