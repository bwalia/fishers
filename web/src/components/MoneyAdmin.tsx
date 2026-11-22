"use client";

/// The frame around each of the club's money pages for its admins — passes,
/// group fees, and prices and who pays: the way back to Payments, the title,
/// and "only the club's money admins" for anybody else.
///
/// The API decides who may (`can_manage` on the bank details, and a 403 on
/// every admin call); this only spares everyone else a page of refusals.

import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import type { UsualPrices } from "@/lib/payments";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

export function MoneyAdminPage({
  clubId,
  title,
  intro,
  children,
}: {
  clubId: string;
  title: string;
  intro: string;
  children: (club: { currency: string }) => ReactNode;
}) {
  const t = useT();
  const authed = useRequireAuth();
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const [currency, setCurrency] = useState("GBP");

  useEffect(() => {
    if (!authed || !clubId) return;
    Promise.all([
      api<{ can_manage: boolean }>("GET", `/clubs/${clubId}/payout-account`).catch(() => null),
      api<UsualPrices>("GET", `/clubs/${clubId}/payments/defaults`).catch(() => null),
    ]).then(([payout, usual]) => {
      setAllowed(payout?.can_manage ?? false);
      if (usual?.currency) setCurrency(usual.currency);
    });
  }, [authed, clubId]);

  if (!authed) return <main id="main" />;
  return (
    <main id="main" className="page money-page">
      <p className="muted">
        <Link href={`/clubs/${clubId}/payments`}>{t("pw3.back_to_payments")}</Link>
      </p>
      <h1>{title}</h1>
      {allowed === null ? (
        <div className="skeleton" style={{ height: 160 }} />
      ) : allowed ? (
        <>
          <p className="muted">{intro}</p>
          {children({ currency })}
        </>
      ) : (
        <>
          <p className="muted">{t("pay.only_money_admins")}</p>
          <p>
            <Link href={`/clubs/${clubId}`}>{t("rest.back_to_the_club")}</Link>
          </p>
        </>
      )}
    </main>
  );
}

/// The way into each of them, from the Payments page.
export function MoneyNav({ clubId }: { clubId: string }) {
  const t = useT();
  const links: [string, string, string][] = [
    [`/clubs/${clubId}/payments/passes`, t("pw3.passes"), t("pw3.nav_passes_help")],
    [`/clubs/${clubId}/payments/group-fees`, t("pw3.group_fees"), t("pw3.nav_fees_help")],
    [`/clubs/${clubId}/payments/members`, t("pw3.prices_and_payers"), t("pw3.nav_members_help")],
  ];
  return (
    <nav className="money-nav" aria-label={t("pw3.money_nav")}>
      {links.map(([href, label, help]) => (
        <Link key={href} href={href} className="money-nav-link">
          <strong>{label}</strong>
          <span className="subtle">{help}</span>
        </Link>
      ))}
    </nav>
  );
}
