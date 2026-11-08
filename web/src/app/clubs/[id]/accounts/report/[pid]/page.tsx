"use client";

/// The treasurer's annual report as it is handed round at an AGM: the words,
/// the Income & Expenditure account, the balance sheet and its notes. Laid
/// out for A4; the browser's "Save as PDF" makes the file.
///
/// The club's name and the year head it. No app branding inside the
/// document — it is the club's report, not ours.

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, isForbidden, readErr } from "@/lib/api";
import { day, figure, type ReportResponse } from "@/lib/accounts";
import {
  BalanceSheet,
  DebtorsNote,
  IncomeAndExpenditure,
} from "@/components/AccountsReport";
import { useRequireAuth } from "@/lib/require-auth";
import { useLocale, useT } from "@/lib/i18n/provider";

export default function PrintableAccountsReport() {
  const t = useT();
  const { locale } = useLocale();
  const authed = useRequireAuth();
  const { id: clubId, pid } = useParams<{ id: string; pid: string }>();
  const [data, setData] = useState<ReportResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!authed) return;
    api<ReportResponse>("GET", `/clubs/${clubId}/accounts/periods/${pid}/report`).then(setData, (e) =>
      setError(isForbidden(e) ? t("acc.only_owner_or_treasurer") : readErr(e, t("le.something_went_wrong"))),
    );
  }, [authed, clubId, pid, t]);

  if (!authed) return <main id="main" />;
  if (error) return <main id="main" className="page"><p className="error">{error}</p></main>;
  if (!data) return <main id="main"><div className="skeleton" style={{ height: 200 }} /></main>;

  const r = data.current;
  const period = `${day(r.starts_on, locale)} – ${day(r.ends_on, locale)}`;

  return (
    <main id="main" className="acc-print">
      <div className="acc-print-bar no-print">
        <Link href={`/clubs/${clubId}/accounts?tab=report`}>{t("acc.back_to_the_accounts")}</Link>
        <button className="btn primary" onClick={() => window.print()}>{t("acc.print_or_save_pdf")}</button>
      </div>

      <article className="acc-sheet">
        <header>
          <h1>{t("acc.treasurers_annual_report")}</h1>
          <p className="acc-club">{data.club_name}</p>
          <p className="muted">{period}</p>
          {r.status === "open" && <p className="acc-draft">{t("acc.draft_year_open")}</p>}
        </header>

        <p className="acc-lede">
          {t(r.surplus_cents < 0 ? "acc.lede_loss" : "acc.lede_surplus", {
            assets: figure(r.balance_sheet.carried_forward_cents),
            result: figure(Math.abs(r.surplus_cents)),
            debtors: figure(r.debtors_total_cents),
          })}
        </p>

        {r.report_text && (
          <section className="acc-narrative">
            {r.report_text.split(/\n{2,}/).map((para, i) => (
              <p key={i}>{para}</p>
            ))}
          </section>
        )}

        {(r.statement_text || r.signed_by_name) && (
          <section className="acc-signed">
            {r.statement_text && <p>{r.statement_text}</p>}
            {r.signed_by_name && (
              <p>
                <strong>{r.signed_by_name}</strong>
                {r.signed_on ? `, ${day(r.signed_on, locale)}` : ""}
              </p>
            )}
          </section>
        )}

        <section className="acc-page-break">
          <h2>{data.club_name}</h2>
          <h3>{t("acc.income_and_expenditure")}</h3>
          <p className="muted">{period}</p>
          <IncomeAndExpenditure current={r} previous={data.previous} />
        </section>

        <section className="acc-page-break">
          <h2>{data.club_name}</h2>
          <h3>{t("acc.balance_sheet")}</h3>
          <p className="muted">{period}</p>
          <BalanceSheet current={r} previous={data.previous} />
          <DebtorsNote report={r} />
        </section>
      </article>
    </main>
  );
}
