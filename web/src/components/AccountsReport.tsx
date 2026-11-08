"use client";

/// The Income & Expenditure account and the balance sheet, this year beside
/// last, laid out the way a club treasurer's AGM report is. Used on screen and
/// on the printable page, so the two can never show different figures.

import {
  figure,
  previousAmount,
  type AccountsReport,
  type ReportLine,
} from "@/lib/accounts";
import { useT } from "@/lib/i18n/provider";

function Lines({
  lines,
  previous,
  hasPrevious,
}: {
  lines: ReportLine[];
  previous?: ReportLine[];
  hasPrevious: boolean;
}) {
  return (
    <>
      {lines.map((l) => {
        const prev = previousAmount(l, previous);
        return (
          <tr key={l.category_id}>
            <td className="num">{figure(l.amount_cents)}</td>
            <td>
              {l.name}
              {l.footnote != null && <sup>({l.footnote})</sup>}
            </td>
            {hasPrevious && <td className="num muted">{prev == null ? "—" : figure(prev)}</td>}
          </tr>
        );
      })}
    </>
  );
}

export function IncomeAndExpenditure({
  current,
  previous,
}: {
  current: AccountsReport;
  previous: AccountsReport | null;
}) {
  const t = useT();
  const hasPrev = !!previous;
  const head = (
    <tr>
      <th className="num">{current.label}</th>
      <th />
      {hasPrev && <th className="num">{previous!.label}</th>}
    </tr>
  );
  return (
    <div className="acc-statement">
      <table>
        <thead>{head}</thead>
        <tbody>
          <tr className="acc-section">
            <td />
            <td colSpan={hasPrev ? 2 : 1}>{t("acc.income")}</td>
          </tr>
          <Lines lines={current.income} previous={previous?.income} hasPrevious={hasPrev} />
          <tr className="acc-total">
            <td className="num">{figure(current.income_total_cents)}</td>
            <td>{t("acc.total")}</td>
            {hasPrev && <td className="num">{figure(previous!.income_total_cents)}</td>}
          </tr>
          <tr className={current.surplus_cents < 0 ? "acc-loss" : "acc-surplus"}>
            <td className="num">{figure(current.surplus_cents)}</td>
            <td>{t("acc.excess_income_over_expenditure")}</td>
            {hasPrev && <td className="num">{figure(previous!.surplus_cents)}</td>}
          </tr>

          <tr className="acc-section">
            <td />
            <td colSpan={hasPrev ? 2 : 1}>{t("acc.expenditure")}</td>
          </tr>
          <Lines lines={current.expenditure} previous={previous?.expenditure} hasPrevious={hasPrev} />
          <tr className="acc-total">
            <td className="num">{figure(current.expenditure_total_cents)}</td>
            <td>{t("acc.total")}</td>
            {hasPrev && <td className="num">{figure(previous!.expenditure_total_cents)}</td>}
          </tr>
        </tbody>
      </table>
      {current.footnotes.length > 0 && (
        <ol className="acc-footnotes">
          {current.footnotes.map((f) => (
            <li key={f.number} value={f.number}>{f.text}</li>
          ))}
        </ol>
      )}
    </div>
  );
}

export function BalanceSheet({
  current,
  previous,
}: {
  current: AccountsReport;
  previous: AccountsReport | null;
}) {
  const t = useT();
  const b = current.balance_sheet;
  const p = previous?.balance_sheet;
  const hasPrev = !!p;
  const row = (label: string, now: number, then?: number, cls?: string) => (
    <tr className={cls}>
      <td className="num">{figure(now)}</td>
      <td>{label}</td>
      {hasPrev && <td className="num muted">{then == null ? "—" : figure(then)}</td>}
    </tr>
  );
  const assetLabel = (kind: string, label: string) =>
    kind === "debtors" ? t("acc.debtors") : kind === "creditors" ? t("acc.creditors") : label;
  const prevAsset = (kind: string, label: string) =>
    p?.represented_by.find((a) => a.kind === kind && (kind === "debtors" || kind === "creditors" || a.label === label))
      ?.amount_cents;

  return (
    <div className="acc-statement">
      <table>
        <thead>
          <tr>
            <th className="num">{current.label}</th>
            <th />
            {hasPrev && <th className="num">{previous!.label}</th>}
          </tr>
        </thead>
        <tbody>
          {row(t("acc.balance_bf"), b.brought_forward_cents, p?.brought_forward_cents)}
          {(b.adjustments_cents !== 0 || (p?.adjustments_cents ?? 0) !== 0) &&
            row(t("acc.prior_period_adjustment"), b.adjustments_cents, p?.adjustments_cents)}
          {row(t("acc.income_received"), b.income_cents, p?.income_cents)}
          {row(t("acc.total"), b.total_cents, p?.total_cents, "acc-total")}
          {row(t("acc.expenditure"), b.expenditure_cents, p?.expenditure_cents)}
          {row(t("acc.balance_cf"), b.carried_forward_cents, p?.carried_forward_cents, "acc-total")}
          <tr className="acc-section">
            <td />
            <td colSpan={hasPrev ? 2 : 1}>{t("acc.represented_by")}</td>
          </tr>
          {b.represented_by.map((a) => (
            <tr key={`${a.kind}:${a.label}`}>
              <td className="num">{figure(a.amount_cents)}</td>
              <td>
                {assetLabel(a.kind, a.label)}
                {a.reconciled === false && (
                  <span className="tag grey acc-flag">{t("acc.not_reconciled")}</span>
                )}
              </td>
              {hasPrev && (
                <td className="num muted">
                  {(() => {
                    const v = prevAsset(a.kind, a.label);
                    return v == null ? "—" : figure(v);
                  })()}
                </td>
              )}
            </tr>
          ))}
          {row(t("acc.total"), b.represented_total_cents, p?.represented_total_cents, "acc-total")}
        </tbody>
      </table>
      <Reconciliation report={current} />
    </div>
  );
}

/// Whether the books agree. Never hidden: a gap is the first thing an AGM
/// should hear about, not something to find on the third page.
export function Reconciliation({ report }: { report: AccountsReport }) {
  const t = useT();
  const b = report.balance_sheet;
  if (b.difference_cents === 0 && b.unreconciled_accounts.length === 0) {
    return <p className="acc-agrees">{t("acc.books_agree")}</p>;
  }
  return (
    <div className="acc-gap" role="status">
      {b.difference_cents !== 0 && (
        <p>
          <strong>
            {t(b.difference_cents < 0 ? "acc.gap_short" : "acc.gap_over", {
              amount: figure(Math.abs(b.difference_cents)),
            })}
          </strong>{" "}
          {t("acc.gap_explained", {
            represented: figure(b.represented_total_cents),
            cf: figure(b.carried_forward_cents),
          })}
        </p>
      )}
      {b.unreconciled_accounts.length > 0 && (
        <p>{t("acc.unreconciled", { accounts: b.unreconciled_accounts.join(", ") })}</p>
      )}
    </div>
  );
}

export function DebtorsNote({ report }: { report: AccountsReport }) {
  const t = useT();
  const block = (title: string, rows: AccountsReport["debtors"], total: number) => (
    <div>
      <h3>{title}</h3>
      {rows.length === 0 ? (
        <p className="muted">{t("acc.none")}</p>
      ) : (
        <table className="acc-plain">
          <tbody>
            {rows.map((d) => (
              <tr key={d.id}>
                <td>
                  {d.description}
                  {d.counterparty ? <span className="muted"> · {d.counterparty}</span> : null}
                  {d.paid_since_close_cents > 0 && (
                    <div className="muted small">
                      {t("acc.paid_since_close", { amount: figure(d.paid_since_close_cents) })}
                    </div>
                  )}
                </td>
                <td className="num">{figure(d.outstanding_at_close_cents)}</td>
              </tr>
            ))}
            <tr className="acc-total">
              <td>{t("acc.total")}</td>
              <td className="num">{figure(total)}</td>
            </tr>
          </tbody>
        </table>
      )}
    </div>
  );
  return (
    <div className="acc-notes">
      {block(t("acc.debtors_note"), report.debtors, report.debtors_total_cents)}
      {block(t("acc.creditors_note"), report.creditors, report.creditors_total_cents)}
    </div>
  );
}

/// The handful of numbers a treasurer reaches for when writing the report.
export function Insights({ report }: { report: AccountsReport }) {
  const t = useT();
  const i = report.insights;
  const items: { label: string; value: string; sub?: string }[] = [
    {
      label: t("acc.result_for_the_year"),
      value: figure(i.surplus_cents),
      sub: i.surplus_cents < 0 ? t("acc.a_loss") : t("acc.a_surplus"),
    },
  ];
  if (i.extraordinary_cents !== 0) {
    items.push({
      label: t("acc.without_one_offs"),
      value: figure(i.surplus_excluding_extraordinary_cents),
      sub: t("acc.one_offs_were", { amount: figure(i.extraordinary_cents) }),
    });
  }
  if (i.nets) {
    items.push({
      label: t("acc.winter_nets"),
      value: figure(i.nets.net_cents),
      sub: t("acc.nets_working", {
        received: figure(i.nets.received_cents),
        cost: figure(i.nets.cost_cents),
      }),
    });
  }
  if (i.matches_played > 0) {
    items.push({
      label: t("acc.fees_per_match"),
      value: figure(i.match_fee_per_match_cents ?? 0),
      sub: t("acc.matches_played", { count: i.matches_played, n: i.matches_played }),
    });
    if (i.equipment_per_match_cents != null) {
      items.push({
        label: t("acc.equipment_per_match"),
        value: figure(i.equipment_per_match_cents),
      });
    }
  }
  items.push({
    label: t("acc.owed_to_the_club"),
    value: figure(i.debtors_at_close_cents),
    sub:
      i.paid_since_close_cents > 0
        ? t("acc.paid_since_close", { amount: figure(i.paid_since_close_cents) })
        : undefined,
  });
  return (
    <div className="grid cards">
      {items.map((it) => (
        <div className="stat" key={it.label}>
          <div className="stat-label">{it.label}</div>
          <div className="stat-value">{it.value}</div>
          {it.sub && <div className="stat-sub">{it.sub}</div>}
        </div>
      ))}
    </div>
  );
}
