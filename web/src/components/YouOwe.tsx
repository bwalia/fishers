"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, money } from "@/lib/api";
import type { Dues } from "@/lib/payments";
import { useT } from "@/lib/i18n/provider";

/// "You owe Riverside £15.00", with the way to pay it.
///
/// On Home it appears only while something is owed. On Profile (`always`) it
/// also stays as the way into the payments list once everything is paid, as
/// long as any club has ever billed them.
///
/// Says nothing at all if the dues cannot be loaded: this is a nudge, and a
/// red box about it on the dashboard would be louder than the debt.
export function YouOwe({ always = false }: { always?: boolean }) {
  const t = useT();
  const [dues, setDues] = useState<Dues | null>(null);

  useEffect(() => {
    api<Dues>("GET", "/me/dues").then(setDues).catch(() => setDues(null));
  }, []);

  if (!dues || dues.clubs.length === 0) return null;
  const owing = dues.clubs.filter((c) => c.owed_cents > 0);
  if (owing.length === 0 && !always) return null;

  if (owing.length === 0) {
    return (
      <section className="panel pay-owe-card" aria-labelledby="you-owe-title">
        <div className="panel-head">
          <h2 id="you-owe-title">{t("pay.payments")}</h2>
          <Link href="/profile/payments">{t("pay.see_your_payments")}</Link>
        </div>
        <p className="muted">
          {dues.clubs.some((c) => c.waiting_cents > 0) ? t("pay.said_you_paid") : t("pay.all_paid_up")}
        </p>
      </section>
    );
  }

  const one = owing.length === 1 ? owing[0] : null;
  return (
    <section className="panel pay-owe-card owing" aria-labelledby="you-owe-title">
      <div className="panel-head">
        <h2 id="you-owe-title">
          {one
            ? t("pay.you_owe_club", { club: one.club_name, amount: money(one.owed_cents, one.currency) })
            : t("pay.you_owe_n_clubs", { count: owing.length, n: owing.length })}
        </h2>
        <Link href="/profile/payments">{t("pay.see_your_payments")}</Link>
      </div>
      <ul className="pay-list">
        {owing.map((c) => (
          <li key={c.club_id}>
            <div>
              <strong>{c.club_name}</strong>
              <div className="muted num">
                {money(c.owed_cents, c.currency)}
                {c.waiting_cents > 0 &&
                  ` · ${t("pay.amount_waiting", { amount: money(c.waiting_cents, c.currency) })}`}
              </div>
            </div>
            <Link
              className="btn primary"
              href={`/clubs/${c.club_id}/pay`}
              aria-label={t("pay.pay_club_amount", { club: c.club_name, amount: money(c.owed_cents, c.currency) })}
            >
              {t("pay.pay")}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
