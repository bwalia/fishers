"use client";

/// Everything you owe, across all your clubs, and what you paid lately.
/// Each club opens its own pay screen: a transfer goes to one club's account,
/// so paying is always per club.
///
/// A parent sees each junior they pay for as their own block under the club,
/// and one **Pay for everyone** button: one transfer, one reference, for all
/// of it (plan §4).

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, money, readErr } from "@/lib/api";
import { clubBlocks, type Dues } from "@/lib/payments";
import { DueList } from "@/components/DueList";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";
import { firstName } from "@/lib/pay-link";

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
  const blocks = dues ? clubBlocks(dues) : [];

  return (
    <main id="main" className="page">
      <p className="muted">
        <Link href="/profile">{t("pay.back_to_profile")}</Link>
      </p>
      <h1>{t("pay.your_payments")}</h1>
      <p className="muted">{t("pay.your_payments_intro")}</p>

      {error && <p className="error" role="alert">{error}</p>}
      {!dues && !error && <div className="skeleton" style={{ height: 160 }} />}
      {dues && blocks.length === 0 && (
        <div className="panel">
          <p className="muted">{t("pay.nothing_billed_yet")}</p>
        </div>
      )}

      {blocks.map((b) => {
        const mine = b.mine;
        const owingPeople = b.people.filter((p) => p.dues.owed_cents > 0);
        const total = (mine?.owed_cents ?? 0) + owingPeople.reduce((sum, p) => sum + p.dues.owed_cents, 0);
        const many = owingPeople.length > 0;
        return (
          <section className="panel" key={b.club_id} aria-labelledby={`dues-${b.club_id}`}>
            <div className="panel-head">
              <h2 id={`dues-${b.club_id}`}>{b.club_name}</h2>
            </div>

            {many ? (
              <p className="pay-total">{t("pw3.you_owe_everyone", { amount: money(total, b.currency) })}</p>
            ) : null}

            {mine && (
              <div className={b.people.length > 0 ? "pay-person" : undefined}>
                {b.people.length > 0 && <h3 className="pay-person-name">{t("nav.you")}</h3>}
                <p>
                  {mine.owed_cents > 0
                    ? t("pay.you_owe_amount", { amount: money(mine.owed_cents, mine.currency) })
                    : mine.waiting_cents > 0
                      ? t("pay.said_you_paid")
                      : t("pay.all_paid_up")}
                </p>
                {mine.waiting_cents > 0 && (
                  <p className="muted">{t("pay.amount_waiting", { amount: money(mine.waiting_cents, mine.currency) })}</p>
                )}
                {mine.credit_cents > 0 && (
                  <p className="muted">{t("pay.amount_credit", { amount: money(mine.credit_cents, mine.currency) })}</p>
                )}
                <DueList shares={mine.shares} />
              </div>
            )}

            {b.people.map((p) => (
              <div className="pay-person" key={p.user_id} aria-labelledby={`person-${p.user_id}`}>
                <h3 className="pay-person-name" id={`person-${p.user_id}`}>
                  {p.name}
                </h3>
                <p>
                  {p.dues.owed_cents > 0
                    ? t("pw3.they_owe", { name: firstName(p.name), amount: money(p.dues.owed_cents, p.dues.currency) })
                    : p.dues.waiting_cents > 0
                      ? t("pw3.they_said_paid", { name: firstName(p.name) })
                      : t("pw3.they_paid_up", { name: firstName(p.name) })}
                </p>
                <DueList shares={p.dues.shares} label={p.name} />
              </div>
            ))}

            {total > 0 && (
              <div className="pay-buttons">
                <Link className="btn primary xl" href={`/clubs/${b.club_id}/pay`}>
                  {many
                    ? t("pw3.pay_for_everyone", { amount: money(total, b.currency) })
                    : t("pay.pay_amount", { amount: money(total, b.currency) })}
                </Link>
              </div>
            )}
          </section>
        );
      })}
    </main>
  );
}
