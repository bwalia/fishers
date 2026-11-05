"use client";

/// The club's books. Open to the club owner and its treasurers; the API
/// refuses everyone else, and this page says so in words rather than showing
/// an empty table.

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, isForbidden, readErr } from "@/lib/api";
import {
  day,
  downloadCsv,
  figure,
  parsePounds,
  toPounds,
  type AccountCategory,
  type AccountPeriod,
  type AccountTransaction,
  type AccountsOverview,
  type AuditEntry,
  type DebtPosition,
  type MoneyPosition,
  type ReportResponse,
  type StockPosition,
  type Suggestions,
} from "@/lib/accounts";
import {
  BalanceSheet,
  DebtorsNote,
  IncomeAndExpenditure,
  Insights,
} from "@/components/AccountsReport";
import { useRequireAuth } from "@/lib/require-auth";
import { useLocale, useT } from "@/lib/i18n/provider";

const TABS = ["overview", "transactions", "debts", "money", "report", "settings"] as const;
type Tab = (typeof TABS)[number];

const today = () => new Date().toISOString().slice(0, 10);

/// Clamp a date into a year, so a form opened on a closed-out year's page
/// starts on a day the API will take.
const within = (d: string, p: AccountPeriod) =>
  d < p.starts_on ? p.starts_on : d > p.ends_on ? p.ends_on : d;

export default function ClubAccountsPage() {
  const t = useT();
  const authed = useRequireAuth();
  const { id: clubId } = useParams<{ id: string }>();

  // The tab lives in the URL so a link can land on it, but is read in an
  // effect rather than through useSearchParams, which would make the whole
  // page wait on a Suspense boundary to render anything.
  const [tab, setTabState] = useState<Tab>("overview");
  useEffect(() => {
    const want = new URLSearchParams(window.location.search).get("tab") ?? "";
    if ((TABS as readonly string[]).includes(want)) setTabState(want as Tab);
  }, []);
  const setTab = (next: Tab) => {
    setTabState(next);
    window.history.replaceState(null, "", `/clubs/${clubId}/accounts?tab=${next}`);
  };

  const [overview, setOverview] = useState<AccountsOverview | null>(null);
  const [periodId, setPeriodId] = useState<string | null>(null);
  const [forbidden, setForbidden] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!authed || !clubId) return;
    try {
      const o = await api<AccountsOverview>("GET", `/clubs/${clubId}/accounts`);
      setOverview(o);
      setPeriodId((cur) =>
        cur && o.periods.some((p) => p.id === cur) ? cur : o.open_period_id ?? o.periods[0]?.id ?? null,
      );
      setError(null);
    } catch (e) {
      if (isForbidden(e)) setForbidden(true);
      else setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [authed, clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  const period = overview?.periods.find((p) => p.id === periodId) ?? null;

  if (!authed) return <main id="main" />;
  if (forbidden) {
    return (
      <main id="main" className="page">
        <h1>{t("acc.title")}</h1>
        <p className="muted">{t("acc.only_owner_or_treasurer")}</p>
        <p>
          <Link href={`/clubs/${clubId}`}>{t("rest.back_to_the_club")}</Link>
        </p>
      </main>
    );
  }
  if (!overview) {
    return (
      <main id="main">
        {error ? <p className="error">{error}</p> : <div className="skeleton" style={{ height: 120 }} />}
      </main>
    );
  }

  const flash = (msg: string) => {
    setNotice(msg);
    setError(null);
  };
  const fail = (e: unknown) => {
    setError(readErr(e, t("le.something_went_wrong")));
    setNotice(null);
  };

  return (
    <main id="main" className="page acc-page">
      <p className="muted">
        <Link href={`/clubs/${clubId}`}>{t("rest.back_to_the_club")}</Link>
      </p>
      <div className="acc-head">
        <h1>{t("acc.title")}</h1>
        {overview.periods.length > 0 && (
          <label className="field acc-year-pick">
            <span>{t("acc.year")}</span>
            <select value={periodId ?? ""} onChange={(e) => setPeriodId(e.target.value)}>
              {overview.periods.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.label} {p.status === "closed" ? `· ${t("acc.closed")}` : `· ${t("acc.open")}`}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>
      <p className="muted">
        {overview.access.is_owner ? t("acc.you_are_owner") : t("acc.you_are_treasurer")}
      </p>

      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      {overview.periods.length === 0 || !overview.open_period_id ? (
        <StartYear
          clubId={clubId}
          overview={overview}
          onDone={async (p) => {
            await load();
            setPeriodId(p.id);
            flash(t("acc.year_opened", { label: p.label }));
          }}
          onError={fail}
        />
      ) : null}

      {period && (
        <>
          {period.status === "closed" && (
            <p className="acc-closed-note">{t("acc.closed_year_note", { label: period.label })}</p>
          )}
          <nav className="tabs" role="tablist" aria-label={t("acc.title")}>
            {TABS.map((k) => (
              <button
                key={k}
                role="tab"
                aria-selected={tab === k}
                className={`tab${tab === k ? " active" : ""}`}
                onClick={() => setTab(k)}
              >
                {t(`acc.tab_${k}` as Parameters<typeof t>[0])}
              </button>
            ))}
          </nav>

          {tab === "overview" && <OverviewTab clubId={clubId} period={period} onError={fail} />}
          {tab === "transactions" && (
            <TransactionsTab
              clubId={clubId}
              period={period}
              categories={overview.categories}
              accounts={overview.money_accounts}
              onError={fail}
              onDone={flash}
            />
          )}
          {tab === "debts" && (
            <DebtsTab
              clubId={clubId}
              period={period}
              accounts={overview.money_accounts}
              onError={fail}
              onDone={flash}
            />
          )}
          {tab === "money" && (
            <MoneyTab clubId={clubId} period={period} onError={fail} onDone={async (m) => { await load(); flash(m); }} />
          )}
          {tab === "report" && <ReportTab clubId={clubId} period={period} onError={fail} onDone={flash} />}
          {tab === "settings" && (
            <SettingsTab
              clubId={clubId}
              overview={overview}
              onError={fail}
              onDone={async (m) => {
                await load();
                flash(m);
              }}
            />
          )}
        </>
      )}
    </main>
  );
}

type TabProps = { clubId: string; period: AccountPeriod; onError: (e: unknown) => void };

// MARK: starting a year

function StartYear({
  clubId,
  overview,
  onDone,
  onError,
}: {
  clubId: string;
  overview: AccountsOverview;
  onDone: (p: AccountPeriod) => void;
  onError: (e: unknown) => void;
}) {
  const t = useT();
  const first = overview.periods.length === 0;
  const [label, setLabel] = useState(overview.suggested_next.label);
  const [startsOn, setStartsOn] = useState(overview.suggested_next.starts_on);
  const [endsOn, setEndsOn] = useState(overview.suggested_next.ends_on);
  const [opening, setOpening] = useState("0.00");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    const pence = parsePounds(opening);
    if (first && pence == null) return onError(new Error(t("acc.not_an_amount")));
    setBusy(true);
    try {
      const p = await api<AccountPeriod>("POST", `/clubs/${clubId}/accounts/periods`, {
        label: label.trim(),
        starts_on: startsOn,
        ends_on: endsOn,
        opening_balance_cents: first ? pence : undefined,
      });
      onDone(p);
    } catch (e) {
      onError(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel">
      <h2>{first ? t("acc.start_the_books") : t("acc.start_the_next_year")}</h2>
      <p className="muted">{first ? t("acc.start_the_books_help") : t("acc.next_year_help")}</p>
      <div className="toolbar acc-form">
        <label className="field">
          <span>{t("acc.year_name")}</span>
          <input value={label} onChange={(e) => setLabel(e.target.value)} />
        </label>
        <label className="field">
          <span>{t("acc.starts")}</span>
          <input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} />
        </label>
        <label className="field">
          <span>{t("acc.ends")}</span>
          <input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
        </label>
        {first && (
          <label className="field">
            <span>{t("acc.balance_bf")}</span>
            <input value={opening} onChange={(e) => setOpening(e.target.value)} inputMode="decimal" />
          </label>
        )}
        <button className="btn primary" disabled={busy || !label.trim()} onClick={() => void submit()}>
          {t("acc.open_the_year")}
        </button>
      </div>
    </section>
  );
}

// MARK: overview

function useReport(clubId: string, periodId: string, onError: (e: unknown) => void) {
  const [report, setReport] = useState<ReportResponse | null>(null);
  const reload = useCallback(async () => {
    try {
      setReport(await api<ReportResponse>("GET", `/clubs/${clubId}/accounts/periods/${periodId}/report`));
    } catch (e) {
      onError(e);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubId, periodId]);
  useEffect(() => {
    void reload();
  }, [reload]);
  return { report, reload };
}

function OverviewTab({ clubId, period, onError }: TabProps) {
  const t = useT();
  const { report } = useReport(clubId, period.id, onError);
  if (!report) return <div className="skeleton" style={{ height: 160 }} />;
  const r = report.current;
  return (
    <>
      <div className="grid cards acc-headline">
        <div className="stat primary">
          <div className="stat-label">{t("acc.balance_cf")}</div>
          <div className="stat-value">{figure(r.balance_sheet.carried_forward_cents)}</div>
          <div className="stat-sub">{t("acc.balance_bf_was", { amount: figure(r.balance_sheet.brought_forward_cents) })}</div>
        </div>
        <div className="stat">
          <div className="stat-label">{t("acc.income")}</div>
          <div className="stat-value">{figure(r.income_total_cents)}</div>
        </div>
        <div className="stat">
          <div className="stat-label">{t("acc.expenditure")}</div>
          <div className="stat-value">{figure(r.expenditure_total_cents)}</div>
        </div>
        <div className={`stat ${r.surplus_cents < 0 ? "acc-stat-loss" : "accent"}`}>
          <div className="stat-label">{t("acc.excess_income_over_expenditure")}</div>
          <div className="stat-value">{figure(r.surplus_cents)}</div>
        </div>
      </div>
      <section className="panel">
        <h2>{t("acc.do_the_books_agree")}</h2>
        <BalanceSheet current={r} previous={report.previous} />
      </section>
      <section className="panel">
        <h2>{t("acc.for_the_report")}</h2>
        <Insights report={r} />
      </section>
    </>
  );
}

// MARK: transactions

function TransactionsTab({
  clubId,
  period,
  categories,
  accounts,
  onError,
  onDone,
}: TabProps & {
  categories: AccountCategory[];
  accounts: AccountsOverview["money_accounts"];
  onDone: (m: string) => void;
}) {
  const t = useT();
  const { locale } = useLocale();
  const [rows, setRows] = useState<AccountTransaction[]>([]);
  const [q, setQ] = useState("");
  const [kindFilter, setKindFilter] = useState("");
  const [showVoided, setShowVoided] = useState(false);
  const open = period.status === "open";

  const reload = useCallback(async () => {
    const params = new URLSearchParams();
    if (q.trim()) params.set("q", q.trim());
    if (kindFilter) params.set("kind", kindFilter);
    if (showVoided) params.set("include_voided", "true");
    try {
      setRows(
        await api<AccountTransaction[]>(
          "GET",
          `/clubs/${clubId}/accounts/periods/${period.id}/transactions?${params}`,
        ),
      );
    } catch (e) {
      onError(e);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubId, period.id, q, kindFilter, showVoided]);

  useEffect(() => {
    const h = window.setTimeout(() => void reload(), 200);
    return () => window.clearTimeout(h);
  }, [reload]);

  const voidRow = async (row: AccountTransaction) => {
    const reason = window.prompt(t("acc.why_void"));
    if (!reason || reason.trim().length < 3) return;
    try {
      await api("POST", `/clubs/${clubId}/accounts/transactions/${row.id}/void`, { reason });
      await reload();
      onDone(t("acc.voided"));
    } catch (e) {
      onError(e);
    }
  };

  const exportCsv = () =>
    downloadCsv(`accounts-${period.label.replace("/", "-")}-transactions.csv`, [
      ["Date", "Kind", "Line", "Account", "Amount", "Description", "Paid by/to", "Member", "Extraordinary", "Voided", "Void reason"],
      ...rows.map((r) => [
        r.occurred_on,
        r.kind,
        r.category_name,
        r.money_account_name,
        toPounds(r.kind === "expenditure" ? -r.amount_cents : r.amount_cents),
        r.description,
        r.counterparty,
        r.member_name,
        r.extraordinary ? "yes" : "",
        r.voided_at ? r.voided_at.slice(0, 10) : "",
        r.void_reason,
      ]),
    ]);

  return (
    <>
      {open && (
        <AddTransaction
          clubId={clubId}
          period={period}
          categories={categories}
          accounts={accounts}
          onError={onError}
          onDone={async () => {
            await reload();
            onDone(t("acc.saved"));
          }}
        />
      )}
      <section className="panel">
        <div className="panel-head">
          <h2>{t("acc.tab_transactions")}</h2>
          <button className="btn ghost sm" onClick={exportCsv} disabled={rows.length === 0}>
            {t("acc.export_csv")}
          </button>
        </div>
        <div className="toolbar acc-form">
          <label className="field">
            <span>{t("acc.search")}</span>
            <input value={q} onChange={(e) => setQ(e.target.value)} />
          </label>
          <label className="field">
            <span>{t("acc.kind")}</span>
            <select value={kindFilter} onChange={(e) => setKindFilter(e.target.value)}>
              <option value="">{t("acc.all")}</option>
              <option value="income">{t("acc.income")}</option>
              <option value="expenditure">{t("acc.expenditure")}</option>
              <option value="adjustment">{t("acc.adjustment")}</option>
            </select>
          </label>
          <label className="field acc-check">
            <input type="checkbox" checked={showVoided} onChange={(e) => setShowVoided(e.target.checked)} />
            <span>{t("acc.show_voided")}</span>
          </label>
        </div>
        {rows.length === 0 ? (
          <p className="muted">{t("acc.no_transactions")}</p>
        ) : (
          <div className="roster-grid">
            <table className="acc-tx">
              <thead>
                <tr>
                  <th>{t("acc.date")}</th>
                  <th>{t("acc.description")}</th>
                  <th>{t("acc.line")}</th>
                  <th>{t("acc.account")}</th>
                  <th className="num">{t("acc.amount")}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className={r.voided_at ? "acc-voided" : undefined}>
                    <td>{day(r.occurred_on, locale)}</td>
                    <td>
                      {r.description}
                      {(r.counterparty || r.member_name) && (
                        <div className="muted small">{r.counterparty ?? r.member_name}</div>
                      )}
                      {r.extraordinary && <span className="tag gold acc-flag">{t("acc.extraordinary")}</span>}
                      {r.source && <span className="tag grey acc-flag">{t("acc.from_the_app")}</span>}
                      {r.voided_at && <div className="muted small">{t("acc.voided_because", { reason: r.void_reason ?? "" })}</div>}
                    </td>
                    <td>{r.kind === "adjustment" ? t("acc.prior_period_adjustment") : r.category_name}</td>
                    <td>{r.money_account_name ?? <span className="muted">{t("acc.owed")}</span>}</td>
                    <td className={`num ${r.kind === "expenditure" ? "acc-out" : "acc-in"}`}>
                      {figure(r.kind === "expenditure" ? -r.amount_cents : r.amount_cents)}
                    </td>
                    <td>
                      {open && !r.voided_at && !r.source?.startsWith("debt_") && (
                        <button className="btn ghost sm" onClick={() => void voidRow(r)}>
                          {t("acc.void")}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

function AddTransaction({
  clubId,
  period,
  categories,
  accounts,
  onError,
  onDone,
}: TabProps & {
  categories: AccountCategory[];
  accounts: AccountsOverview["money_accounts"];
  onDone: () => void;
}) {
  const t = useT();
  const [kind, setKind] = useState<"income" | "expenditure" | "adjustment">("expenditure");
  const [date, setDate] = useState(within(today(), period));
  const [categoryId, setCategoryId] = useState("");
  const [accountId, setAccountId] = useState(accounts.find((a) => !a.archived)?.id ?? "");
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");
  const [counterparty, setCounterparty] = useState("");
  const [extraordinary, setExtraordinary] = useState(false);
  const [authorisedOn, setAuthorisedOn] = useState("");
  const [authorisationRef, setAuthorisationRef] = useState("");
  const [busy, setBusy] = useState(false);

  const lines = useMemo(
    () => categories.filter((c) => c.kind === kind && !c.archived),
    [categories, kind],
  );
  useEffect(() => {
    if (kind !== "adjustment" && !lines.some((c) => c.id === categoryId)) setCategoryId(lines[0]?.id ?? "");
  }, [kind, lines, categoryId]);

  const submit = async () => {
    const pence = parsePounds(amount);
    if (pence == null || pence === 0 || (kind !== "adjustment" && pence < 0)) {
      return onError(new Error(t("acc.not_an_amount")));
    }
    setBusy(true);
    try {
      await api("POST", `/clubs/${clubId}/accounts/periods/${period.id}/transactions`, {
        occurred_on: date,
        kind,
        category_id: kind === "adjustment" ? undefined : categoryId,
        money_account_id: accountId || undefined,
        amount_cents: pence,
        description: description.trim(),
        counterparty: counterparty.trim() || undefined,
        extraordinary: kind === "expenditure" || kind === "income" ? extraordinary : false,
        authorised_on: extraordinary && authorisedOn ? authorisedOn : undefined,
        authorisation_ref: extraordinary && authorisationRef.trim() ? authorisationRef.trim() : undefined,
      });
      setAmount("");
      setDescription("");
      setCounterparty("");
      setExtraordinary(false);
      setAuthorisedOn("");
      setAuthorisationRef("");
      onDone();
    } catch (e) {
      onError(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel">
      <h2>{t("acc.add_a_line")}</h2>
      <div className="toolbar acc-form">
        <label className="field">
          <span>{t("acc.kind")}</span>
          <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>
            <option value="expenditure">{t("acc.money_out")}</option>
            <option value="income">{t("acc.money_in")}</option>
            <option value="adjustment">{t("acc.prior_period_adjustment")}</option>
          </select>
        </label>
        <label className="field">
          <span>{t("acc.date")}</span>
          <input type="date" min={period.starts_on} max={period.ends_on} value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        {kind !== "adjustment" && (
          <label className="field">
            <span>{t("acc.line")}</span>
            <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              {lines.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
        )}
        <label className="field">
          <span>{t("acc.account")}</span>
          <select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            {accounts.filter((a) => !a.archived).map((a) => (
              <option key={a.id} value={a.id}>{a.name}</option>
            ))}
            <option value="">{t("acc.no_account_owed")}</option>
          </select>
        </label>
        <label className="field">
          <span>{kind === "adjustment" ? t("acc.amount_signed") : t("acc.amount")}</span>
          <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" placeholder="0.00" />
        </label>
        <label className="field acc-wide">
          <span>{t("acc.description")}</span>
          <input value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
        <label className="field">
          <span>{t("acc.paid_by_or_to")}</span>
          <input value={counterparty} onChange={(e) => setCounterparty(e.target.value)} placeholder={t("le.optional")} />
        </label>
        {kind !== "adjustment" && (
          <label className="field acc-check">
            <input type="checkbox" checked={extraordinary} onChange={(e) => setExtraordinary(e.target.checked)} />
            <span>{t("acc.extraordinary_one_off")}</span>
          </label>
        )}
        {extraordinary && (
          <>
            <label className="field">
              <span>{t("acc.authorised_on")}</span>
              <input type="date" value={authorisedOn} onChange={(e) => setAuthorisedOn(e.target.value)} />
            </label>
            <label className="field">
              <span>{t("acc.minute_reference")}</span>
              <input value={authorisationRef} onChange={(e) => setAuthorisationRef(e.target.value)} />
            </label>
          </>
        )}
        <button className="btn primary" disabled={busy || !amount || !description.trim()} onClick={() => void submit()}>
          {t("acc.add")}
        </button>
      </div>
      {kind === "adjustment" && <p className="muted small">{t("acc.adjustment_help")}</p>}
    </section>
  );
}

// MARK: debtors and creditors

function DebtsTab({
  clubId,
  period,
  accounts,
  onError,
  onDone,
}: TabProps & { accounts: AccountsOverview["money_accounts"]; onDone: (m: string) => void }) {
  const t = useT();
  const { locale } = useLocale();
  const [debts, setDebts] = useState<DebtPosition[]>([]);
  const [sugg, setSugg] = useState<Suggestions | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const liveAccounts = accounts.filter((a) => !a.archived);
  const [intoAccount, setIntoAccount] = useState(liveAccounts[0]?.id ?? "");
  const open = period.status === "open";

  const reload = useCallback(async () => {
    try {
      const [d, s] = await Promise.all([
        api<DebtPosition[]>("GET", `/clubs/${clubId}/accounts/periods/${period.id}/debts`),
        api<Suggestions>("GET", `/clubs/${clubId}/accounts/periods/${period.id}/suggestions`),
      ]);
      setDebts(d);
      setSugg(s);
      setPicked(new Set(s.payments.map((p) => p.payment_id)));
    } catch (e) {
      onError(e);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubId, period.id]);
  useEffect(() => {
    void reload();
  }, [reload]);

  const settle = async (d: DebtPosition, kind: "payment" | "write_off" | "shortfall") => {
    const raw = window.prompt(
      kind === "payment" ? t("acc.how_much_was_paid") : kind === "write_off" ? t("acc.how_much_to_write_off") : t("acc.how_much_short"),
      toPounds(d.outstanding_now_cents),
    );
    if (raw == null) return;
    const pence = parsePounds(raw);
    if (pence == null || pence <= 0) return onError(new Error(t("acc.not_an_amount")));
    try {
      await api("POST", `/clubs/${clubId}/accounts/debts/${d.id}/settlements`, {
        kind,
        amount_cents: pence,
        settled_on: within(today(), period),
        money_account_id: kind === "payment" ? intoAccount : undefined,
      });
      await reload();
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    }
  };

  const voidDebt = async (d: DebtPosition) => {
    const reason = window.prompt(t("acc.why_void"));
    if (!reason || reason.trim().length < 3) return;
    try {
      await api("POST", `/clubs/${clubId}/accounts/debts/${d.id}/void`, { reason });
      await reload();
      onDone(t("acc.voided"));
    } catch (e) {
      onError(e);
    }
  };

  const accept = async () => {
    try {
      const out = await api<{ posted: number; settled: number }>(
        "POST",
        `/clubs/${clubId}/accounts/periods/${period.id}/accept-payments`,
        { payment_ids: [...picked], money_account_id: intoAccount },
      );
      await reload();
      onDone(t("acc.payments_taken_in", { posted: out.posted, settled: out.settled }));
    } catch (e) {
      onError(e);
    }
  };

  const raiseUnpaid = async () => {
    try {
      const out = await api<{ raised: number }>(
        "POST",
        `/clubs/${clubId}/accounts/periods/${period.id}/raise-unpaid-fees`,
        { event_ids: [] },
      );
      await reload();
      onDone(t("acc.fees_raised", { count: out.raised, n: out.raised }));
    } catch (e) {
      onError(e);
    }
  };

  const unraised = sugg?.unpaid_fees.filter((f) => !f.already_raised) ?? [];
  const table = (direction: "debtor" | "creditor") => {
    const rows = debts.filter((d) => d.direction === direction && (d.outstanding_now_cents > 0 || d.outstanding_at_close_cents > 0));
    if (rows.length === 0) return <p className="muted">{t("acc.none")}</p>;
    return (
      <div className="roster-grid">
        <table>
          <thead>
            <tr>
              <th>{t("acc.description")}</th>
              <th>{t("acc.raised")}</th>
              <th className="num">{t("acc.at_year_end")}</th>
              <th className="num">{t("acc.owed_now")}</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((d) => (
              <tr key={d.id}>
                <td>
                  {d.description}
                  {(d.counterparty || d.member_name) && <div className="muted small">{d.counterparty ?? d.member_name}</div>}
                </td>
                <td>{day(d.raised_on, locale)} <span className="muted small">{d.period_label}</span></td>
                <td className="num">{figure(d.outstanding_at_close_cents)}</td>
                <td className="num">{figure(d.outstanding_now_cents)}</td>
                <td className="acc-actions">
                  {d.outstanding_now_cents > 0 && (
                    <>
                      <button className="btn ghost sm" onClick={() => void settle(d, "payment")} disabled={!intoAccount}>
                        {t("acc.paid")}
                      </button>
                      {direction === "debtor" && (
                        <>
                          <button className="btn ghost sm" onClick={() => void settle(d, "shortfall")}>{t("acc.came_in_short")}</button>
                          <button className="btn ghost sm" onClick={() => void settle(d, "write_off")}>{t("acc.write_off")}</button>
                        </>
                      )}
                    </>
                  )}
                  {open && d.period_id === period.id && d.outstanding_now_cents === d.amount_cents && (
                    <button className="btn ghost sm" onClick={() => void voidDebt(d)}>{t("acc.void")}</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  };

  return (
    <>
      {liveAccounts.length > 0 && (
        <label className="field acc-into">
          <span>{t("acc.payments_go_into")}</span>
          <select value={intoAccount} onChange={(e) => setIntoAccount(e.target.value)}>
            {liveAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </label>
      )}

      {open && sugg && sugg.payments.length > 0 && (
        <section className="panel">
          <h2>{t("acc.paid_in_the_app")}</h2>
          <p className="muted">{t("acc.paid_in_the_app_help")}</p>
          <ul className="acc-pick">
            {sugg.payments.map((p) => (
              <li key={p.payment_id}>
                <label>
                  <input
                    type="checkbox"
                    checked={picked.has(p.payment_id)}
                    onChange={(e) => {
                      const next = new Set(picked);
                      if (e.target.checked) next.add(p.payment_id);
                      else next.delete(p.payment_id);
                      setPicked(next);
                    }}
                  />
                  <span>
                    {day(p.paid_on, locale)} · {p.member_name} · {p.event_title}
                    {p.settles_debt_id && <span className="tag grey acc-flag">{t("acc.pays_off_a_debt")}</span>}
                  </span>
                  <span className="num">{figure(p.amount_cents)}</span>
                </label>
              </li>
            ))}
          </ul>
          <button className="btn primary" disabled={picked.size === 0 || !intoAccount} onClick={() => void accept()}>
            {t("acc.take_into_the_books", { count: picked.size, n: picked.size })}
          </button>
          {!intoAccount && <p className="muted small">{t("acc.add_an_account_first")}</p>}
        </section>
      )}

      {open && unraised.length > 0 && (
        <section className="panel">
          <h2>{t("acc.fees_still_unpaid")}</h2>
          <p className="muted">
            {t("acc.fees_still_unpaid_help", {
              count: unraised.length,
              n: unraised.length,
              amount: figure(unraised.reduce((s, f) => s + f.amount_cents, 0)),
            })}
          </p>
          <button className="btn" onClick={() => void raiseUnpaid()}>{t("acc.raise_as_debtors")}</button>
        </section>
      )}

      {open && <RaiseDebt clubId={clubId} period={period} onError={onError} onDone={async () => { await reload(); onDone(t("acc.saved")); }} />}

      <section className="panel">
        <h2>{t("acc.owed_to_the_club")}</h2>
        {table("debtor")}
      </section>
      <section className="panel">
        <h2>{t("acc.owed_by_the_club")}</h2>
        {table("creditor")}
      </section>
    </>
  );
}

function RaiseDebt({ clubId, period, onError, onDone }: TabProps & { onDone: () => void }) {
  const t = useT();
  const [direction, setDirection] = useState<"debtor" | "creditor">("debtor");
  const [kind, setKind] = useState<"member_fees" | "cost_share" | "other">("member_fees");
  const [description, setDescription] = useState("");
  const [counterparty, setCounterparty] = useState("");
  const [amount, setAmount] = useState("");
  const [raisedOn, setRaisedOn] = useState(within(today(), period));
  const [accrue, setAccrue] = useState(true);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    const pence = parsePounds(amount);
    if (pence == null || pence <= 0) return onError(new Error(t("acc.not_an_amount")));
    setBusy(true);
    try {
      await api("POST", `/clubs/${clubId}/accounts/debts`, {
        direction,
        kind,
        description: description.trim(),
        counterparty: counterparty.trim() || undefined,
        amount_cents: pence,
        raised_on: raisedOn,
        accrue,
      });
      setDescription("");
      setCounterparty("");
      setAmount("");
      onDone();
    } catch (e) {
      onError(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <details className="panel acc-details">
      <summary><h2>{t("acc.record_a_debt")}</h2></summary>
      <div className="toolbar acc-form">
        <label className="field">
          <span>{t("acc.who_owes")}</span>
          <select value={direction} onChange={(e) => setDirection(e.target.value as typeof direction)}>
            <option value="debtor">{t("acc.owed_to_the_club")}</option>
            <option value="creditor">{t("acc.owed_by_the_club")}</option>
          </select>
        </label>
        <label className="field">
          <span>{t("acc.kind")}</span>
          <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>
            <option value="member_fees">{t("acc.kind_member_fees")}</option>
            <option value="cost_share">{t("acc.kind_cost_share")}</option>
            <option value="other">{t("acc.kind_other")}</option>
          </select>
        </label>
        <label className="field acc-wide">
          <span>{t("acc.description")}</span>
          <input value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
        <label className="field">
          <span>{t("acc.who")}</span>
          <input value={counterparty} onChange={(e) => setCounterparty(e.target.value)} />
        </label>
        <label className="field">
          <span>{t("acc.amount")}</span>
          <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" placeholder="0.00" />
        </label>
        <label className="field">
          <span>{t("acc.date")}</span>
          <input type="date" min={period.starts_on} max={period.ends_on} value={raisedOn} onChange={(e) => setRaisedOn(e.target.value)} />
        </label>
        <label className="field acc-check">
          <input type="checkbox" checked={accrue} onChange={(e) => setAccrue(e.target.checked)} />
          <span>{t("acc.count_it_this_year")}</span>
        </label>
        <button className="btn primary" disabled={busy || !description.trim() || !amount} onClick={() => void submit()}>
          {t("acc.add")}
        </button>
      </div>
      <p className="muted small">{t("acc.count_it_this_year_help")}</p>
    </details>
  );
}

// MARK: money and stock

function MoneyTab({ clubId, period, onError, onDone }: TabProps & { onDone: (m: string) => void }) {
  const t = useT();
  const [money, setMoney] = useState<MoneyPosition[]>([]);
  const [stock, setStock] = useState<StockPosition[]>([]);
  const [statement, setStatement] = useState<Record<string, string>>({});
  const [opening, setOpening] = useState<Record<string, string>>({});
  const [counts, setCounts] = useState<Record<string, { open: string; close: string }>>({});
  const [newAccount, setNewAccount] = useState({ name: "", kind: "bank", opening: "0.00" });
  const [newItem, setNewItem] = useState("");
  const [isFirstYear, setIsFirstYear] = useState(false);
  const open = period.status === "open";

  const reload = useCallback(async () => {
    try {
      const [m, s, report] = await Promise.all([
        api<MoneyPosition[]>("GET", `/clubs/${clubId}/accounts/periods/${period.id}/money`),
        api<StockPosition[]>("GET", `/clubs/${clubId}/accounts/periods/${period.id}/stock`),
        api<ReportResponse>("GET", `/clubs/${clubId}/accounts/periods/${period.id}/report`),
      ]);
      setMoney(m);
      setStock(s);
      setIsFirstYear(!report.previous);
      setStatement(Object.fromEntries(m.map((a) => [a.id, a.reconciled_cents == null ? "" : toPounds(a.reconciled_cents)])));
      setOpening(Object.fromEntries(m.map((a) => [a.id, toPounds(a.opening_cents)])));
      setCounts(Object.fromEntries(s.map((i) => [i.item_id, { open: toPounds(i.opening_cents), close: toPounds(i.closing_cents) }])));
    } catch (e) {
      onError(e);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubId, period.id]);
  useEffect(() => {
    void reload();
  }, [reload]);

  const saveBalance = async (a: MoneyPosition) => {
    const raw = statement[a.id]?.trim() ?? "";
    const reconciled = raw === "" ? null : parsePounds(raw);
    if (raw !== "" && reconciled == null) return onError(new Error(t("acc.not_an_amount")));
    const open = isFirstYear ? parsePounds(opening[a.id] ?? "") : null;
    try {
      await api("PUT", `/clubs/${clubId}/accounts/money-accounts/${a.id}/balance`, {
        period_id: period.id,
        reconciled_cents: reconciled,
        opening_cents: isFirstYear && open != null ? open : undefined,
      });
      await reload();
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    }
  };

  const saveCount = async (s: StockPosition) => {
    const c = counts[s.item_id];
    const close = parsePounds(c?.close ?? "");
    const opn = isFirstYear ? parsePounds(c?.open ?? "") : null;
    if (close == null || (isFirstYear && opn == null)) return onError(new Error(t("acc.not_an_amount")));
    try {
      await api("PUT", `/clubs/${clubId}/accounts/stock/${s.item_id}/count`, {
        period_id: period.id,
        closing_cents: close,
        opening_cents: isFirstYear ? opn : undefined,
        counted_on: within(today(), period),
      });
      await reload();
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    }
  };

  const addAccount = async () => {
    const pence = parsePounds(newAccount.opening);
    if (pence == null) return onError(new Error(t("acc.not_an_amount")));
    try {
      await api("POST", `/clubs/${clubId}/accounts/money-accounts`, {
        name: newAccount.name.trim(),
        kind: newAccount.kind,
        opening_cents: isFirstYear ? pence : 0,
      });
      setNewAccount({ name: "", kind: "bank", opening: "0.00" });
      await reload();
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    }
  };

  const addItem = async () => {
    try {
      await api("POST", `/clubs/${clubId}/accounts/stock`, { name: newItem.trim() });
      setNewItem("");
      await reload();
    } catch (e) {
      onError(e);
    }
  };

  return (
    <>
      <section className="panel">
        <h2>{t("acc.money_accounts")}</h2>
        <p className="muted">{t("acc.money_accounts_help")}</p>
        {money.length === 0 ? (
          <p className="muted">{t("acc.no_accounts_yet")}</p>
        ) : (
          <div className="roster-grid">
            <table>
              <thead>
                <tr>
                  <th>{t("acc.account")}</th>
                  <th className="num">{t("acc.opening")}</th>
                  <th className="num">{t("acc.books_say")}</th>
                  <th className="num">{t("acc.statement_says")}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {money.map((a) => {
                  const off = a.reconciled_cents != null && a.reconciled_cents !== a.computed_closing_cents;
                  return (
                    <tr key={a.id}>
                      <td>{a.name} <span className="muted small">{t(`acc.money_kind_${a.kind}` as Parameters<typeof t>[0])}</span></td>
                      <td className="num">
                        {open && isFirstYear ? (
                          <input className="acc-num" value={opening[a.id] ?? ""} onChange={(e) => setOpening({ ...opening, [a.id]: e.target.value })} inputMode="decimal" />
                        ) : (
                          figure(a.opening_cents)
                        )}
                      </td>
                      <td className="num">{figure(a.computed_closing_cents)}</td>
                      <td className="num">
                        {open ? (
                          <input
                            className="acc-num"
                            value={statement[a.id] ?? ""}
                            placeholder="—"
                            onChange={(e) => setStatement({ ...statement, [a.id]: e.target.value })}
                            inputMode="decimal"
                          />
                        ) : a.reconciled_cents == null ? "—" : figure(a.reconciled_cents)}
                        {off && (
                          <div className="acc-gap-inline small">
                            {t("acc.differs_by", { amount: figure((a.reconciled_cents ?? 0) - a.computed_closing_cents) })}
                          </div>
                        )}
                      </td>
                      <td>{open && <button className="btn ghost sm" onClick={() => void saveBalance(a)}>{t("acc.save")}</button>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        {open && (
          <div className="toolbar acc-form" style={{ marginTop: 12 }}>
            <label className="field">
              <span>{t("acc.new_account")}</span>
              <input value={newAccount.name} onChange={(e) => setNewAccount({ ...newAccount, name: e.target.value })} placeholder={t("acc.bank_current_account")} />
            </label>
            <label className="field">
              <span>{t("acc.kind")}</span>
              <select value={newAccount.kind} onChange={(e) => setNewAccount({ ...newAccount, kind: e.target.value })}>
                {(["bank", "cash", "supplier_credit", "provider"] as const).map((k) => (
                  <option key={k} value={k}>{t(`acc.money_kind_${k}`)}</option>
                ))}
              </select>
            </label>
            {isFirstYear && (
              <label className="field">
                <span>{t("acc.opening")}</span>
                <input value={newAccount.opening} onChange={(e) => setNewAccount({ ...newAccount, opening: e.target.value })} inputMode="decimal" />
              </label>
            )}
            <button className="btn" disabled={!newAccount.name.trim()} onClick={() => void addAccount()}>{t("acc.add")}</button>
          </div>
        )}
      </section>

      <section className="panel">
        <h2>{t("acc.stock")}</h2>
        <p className="muted">{t("acc.stock_help")}</p>
        {stock.length > 0 && (
          <div className="roster-grid">
            <table>
              <thead>
                <tr>
                  <th>{t("acc.item")}</th>
                  <th className="num">{t("acc.at_the_start")}</th>
                  <th className="num">{t("acc.at_the_end")}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {stock.map((s) => (
                  <tr key={s.item_id}>
                    <td>{s.name}</td>
                    <td className="num">
                      {open && isFirstYear ? (
                        <input className="acc-num" value={counts[s.item_id]?.open ?? ""} onChange={(e) => setCounts({ ...counts, [s.item_id]: { ...counts[s.item_id], open: e.target.value } })} inputMode="decimal" />
                      ) : figure(s.opening_cents)}
                    </td>
                    <td className="num">
                      {open ? (
                        <input className="acc-num" value={counts[s.item_id]?.close ?? ""} onChange={(e) => setCounts({ ...counts, [s.item_id]: { ...counts[s.item_id], close: e.target.value } })} inputMode="decimal" />
                      ) : figure(s.closing_cents)}
                    </td>
                    <td>{open && <button className="btn ghost sm" onClick={() => void saveCount(s)}>{t("acc.save")}</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {open && (
          <div className="toolbar acc-form" style={{ marginTop: 12 }}>
            <label className="field">
              <span>{t("acc.new_item")}</span>
              <input value={newItem} onChange={(e) => setNewItem(e.target.value)} placeholder={t("acc.match_balls")} />
            </label>
            <button className="btn" disabled={!newItem.trim()} onClick={() => void addItem()}>{t("acc.add")}</button>
          </div>
        )}
      </section>
    </>
  );
}

// MARK: the report

function ReportTab({ clubId, period, onError, onDone }: TabProps & { onDone: (m: string) => void }) {
  const t = useT();
  const { report, reload } = useReport(clubId, period.id, onError);
  const [text, setText] = useState(period.report_text ?? "");
  const [statement, setStatement] = useState(period.statement_text ?? t("acc.default_statement"));
  const [signedBy, setSignedBy] = useState(period.signed_by_name ?? "");
  const [signedOn, setSignedOn] = useState(period.signed_on ?? "");
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setBusy(true);
    try {
      await api("PATCH", `/clubs/${clubId}/accounts/periods/${period.id}`, {
        report_text: text,
        statement_text: statement,
        signed_by_name: signedBy.trim() || undefined,
        signed_on: signedOn || undefined,
      });
      await reload();
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    } finally {
      setBusy(false);
    }
  };

  const exportTables = () => {
    if (!report) return;
    const r = report.current;
    const p = report.previous;
    const prevOf = (lines: typeof r.income, id: string, name: string) =>
      lines.find((l) => l.category_id === id) ?? lines.find((l) => l.name === name);
    downloadCsv(`accounts-${r.label.replace("/", "-")}.csv`, [
      ["Section", "Line", r.label, p?.label ?? ""],
      ...r.income.map((l) => ["Income", l.name, toPounds(l.amount_cents), p ? toPounds(prevOf(p.income, l.category_id, l.name)?.amount_cents ?? 0) : ""]),
      ["Income", "Total", toPounds(r.income_total_cents), p ? toPounds(p.income_total_cents) : ""],
      ...r.expenditure.map((l) => ["Expenditure", l.name, toPounds(l.amount_cents), p ? toPounds(prevOf(p.expenditure, l.category_id, l.name)?.amount_cents ?? 0) : ""]),
      ["Expenditure", "Total", toPounds(r.expenditure_total_cents), p ? toPounds(p.expenditure_total_cents) : ""],
      ["Result", "Excess of income over expenditure", toPounds(r.surplus_cents), p ? toPounds(p.surplus_cents) : ""],
      ["Balance sheet", "Balance b/f", toPounds(r.balance_sheet.brought_forward_cents), p ? toPounds(p.balance_sheet.brought_forward_cents) : ""],
      ["Balance sheet", "Prior-period adjustments", toPounds(r.balance_sheet.adjustments_cents), p ? toPounds(p.balance_sheet.adjustments_cents) : ""],
      ["Balance sheet", "Balance c/f", toPounds(r.balance_sheet.carried_forward_cents), p ? toPounds(p.balance_sheet.carried_forward_cents) : ""],
      ...r.balance_sheet.represented_by.map((a) => ["Represented by", a.label, toPounds(a.amount_cents), ""]),
      ["Represented by", "Total", toPounds(r.balance_sheet.represented_total_cents), p ? toPounds(p.balance_sheet.represented_total_cents) : ""],
      ["Represented by", "Difference from c/f", toPounds(r.balance_sheet.difference_cents), p ? toPounds(p.balance_sheet.difference_cents) : ""],
    ]);
  };

  return (
    <>
      <section className="panel">
        <div className="panel-head">
          <h2>{t("acc.treasurers_report")}</h2>
          <div className="acc-actions">
            <button className="btn ghost sm" onClick={exportTables} disabled={!report}>{t("acc.export_csv")}</button>
            <Link className="btn sm" href={`/clubs/${clubId}/accounts/report/${period.id}`}>
              {t("acc.printable_report")}
            </Link>
          </div>
        </div>
        <p className="muted">{t("acc.report_help")}</p>
        <label className="field">
          <span>{t("acc.report_text")}</span>
          <textarea rows={12} value={text} onChange={(e) => setText(e.target.value)} />
        </label>
        <label className="field">
          <span>{t("acc.statement")}</span>
          <textarea rows={3} value={statement} onChange={(e) => setStatement(e.target.value)} />
        </label>
        <div className="toolbar acc-form">
          <label className="field">
            <span>{t("acc.signed_by")}</span>
            <input value={signedBy} onChange={(e) => setSignedBy(e.target.value)} />
          </label>
          <label className="field">
            <span>{t("acc.signed_on")}</span>
            <input type="date" value={signedOn} onChange={(e) => setSignedOn(e.target.value)} />
          </label>
          <button className="btn primary" disabled={busy} onClick={() => void save()}>{t("acc.save")}</button>
        </div>
      </section>
      {report && (
        <>
          <section className="panel">
            <h2>{t("acc.for_the_report")}</h2>
            <Insights report={report.current} />
          </section>
          <section className="panel">
            <h2>{t("acc.income_and_expenditure")}</h2>
            <IncomeAndExpenditure current={report.current} previous={report.previous} />
          </section>
          <section className="panel">
            <h2>{t("acc.balance_sheet")}</h2>
            <BalanceSheet current={report.current} previous={report.previous} />
            <DebtorsNote report={report.current} />
          </section>
        </>
      )}
    </>
  );
}

// MARK: settings

function SettingsTab({
  clubId,
  overview,
  onError,
  onDone,
}: {
  clubId: string;
  overview: AccountsOverview;
  onError: (e: unknown) => void;
  onDone: (m: string) => void;
}) {
  const t = useT();
  const { locale } = useLocale();
  const [newLine, setNewLine] = useState({ kind: "expenditure", name: "" });
  const [audit, setAudit] = useState<AuditEntry[]>([]);

  useEffect(() => {
    api<AuditEntry[]>("GET", `/clubs/${clubId}/accounts/audit?limit=50`).then(setAudit, onError);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clubId]);

  const patchLine = async (c: AccountCategory, body: Record<string, unknown>) => {
    try {
      await api("PATCH", `/clubs/${clubId}/accounts/categories/${c.id}`, body);
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    }
  };

  const addLine = async () => {
    try {
      await api("POST", `/clubs/${clubId}/accounts/categories`, { kind: newLine.kind, name: newLine.name.trim() });
      setNewLine({ ...newLine, name: "" });
      onDone(t("acc.saved"));
    } catch (e) {
      onError(e);
    }
  };

  const closeYear = async (p: AccountPeriod) => {
    if (!window.confirm(t("acc.close_confirm", { label: p.label }))) return;
    try {
      await api("POST", `/clubs/${clubId}/accounts/periods/${p.id}/close`);
      onDone(t("acc.year_closed", { label: p.label }));
    } catch (e) {
      onError(e);
    }
  };

  const reopenYear = async (p: AccountPeriod) => {
    const reason = window.prompt(t("acc.why_reopen", { label: p.label }));
    if (!reason || reason.trim().length < 3) return;
    try {
      await api("POST", `/clubs/${clubId}/accounts/periods/${p.id}/reopen`, { reason });
      onDone(t("acc.year_reopened", { label: p.label }));
    } catch (e) {
      onError(e);
    }
  };

  const block = (kind: "income" | "expenditure") => (
    <div>
      <h3>{t(kind === "income" ? "acc.income" : "acc.expenditure")}</h3>
      <ul className="acc-lines">
        {overview.categories
          .filter((c) => c.kind === kind)
          .sort((a, b) => a.sort_order - b.sort_order)
          .map((c) => (
            <li key={c.id} className={c.archived ? "acc-archived" : undefined}>
              <span>{c.name}</span>
              <span className="acc-actions">
                <button
                  className="btn ghost sm"
                  onClick={() => {
                    const name = window.prompt(t("acc.rename_line"), c.name);
                    if (name && name.trim() && name !== c.name) void patchLine(c, { name: name.trim() });
                  }}
                >
                  {t("acc.rename")}
                </button>
                <button
                  className="btn ghost sm"
                  onClick={() => {
                    const note = window.prompt(t("acc.footnote_prompt"), c.footnote ?? "");
                    if (note != null) void patchLine(c, { footnote: note.trim() || null });
                  }}
                >
                  {c.footnote ? t("acc.edit_footnote") : t("acc.add_footnote")}
                </button>
                {!c.system_key && (
                  <button className="btn ghost sm" onClick={() => void patchLine(c, { archived: !c.archived })}>
                    {c.archived ? t("acc.restore") : t("acc.archive")}
                  </button>
                )}
              </span>
            </li>
          ))}
      </ul>
    </div>
  );

  return (
    <>
      <section className="panel">
        <h2>{t("acc.years")}</h2>
        <ul className="acc-lines">
          {overview.periods.map((p) => (
            <li key={p.id}>
              <span>
                <strong>{p.label}</strong>{" "}
                <span className="muted small">{day(p.starts_on, locale)} – {day(p.ends_on, locale)}</span>{" "}
                <span className={`tag ${p.status === "open" ? "gold" : "grey"}`}>{p.status === "open" ? t("acc.open") : t("acc.closed")}</span>
              </span>
              <span className="acc-actions">
                {p.status === "open" ? (
                  <button className="btn sm" onClick={() => void closeYear(p)}>{t("acc.close_the_year")}</button>
                ) : overview.access.is_owner ? (
                  <button className="btn ghost sm" onClick={() => void reopenYear(p)}>{t("acc.reopen")}</button>
                ) : null}
              </span>
            </li>
          ))}
        </ul>
        {!overview.access.is_owner && <p className="muted small">{t("acc.only_owner_reopens")}</p>}
      </section>

      <section className="panel">
        <h2>{t("acc.lines_in_the_accounts")}</h2>
        <p className="muted">{t("acc.lines_help")}</p>
        <div className="acc-notes">
          {block("income")}
          {block("expenditure")}
        </div>
        <div className="toolbar acc-form" style={{ marginTop: 12 }}>
          <label className="field">
            <span>{t("acc.kind")}</span>
            <select value={newLine.kind} onChange={(e) => setNewLine({ ...newLine, kind: e.target.value })}>
              <option value="income">{t("acc.income")}</option>
              <option value="expenditure">{t("acc.expenditure")}</option>
            </select>
          </label>
          <label className="field">
            <span>{t("acc.new_line")}</span>
            <input value={newLine.name} onChange={(e) => setNewLine({ ...newLine, name: e.target.value })} />
          </label>
          <button className="btn" disabled={!newLine.name.trim()} onClick={() => void addLine()}>{t("acc.add")}</button>
        </div>
      </section>

      <section className="panel">
        <h2>{t("acc.who_changed_what")}</h2>
        {audit.length === 0 ? (
          <p className="muted">{t("acc.none")}</p>
        ) : (
          <ul className="acc-audit">
            {audit.map((a) => (
              <li key={a.id}>
                <span className="muted small">{new Date(a.created_at).toLocaleString(locale === "en" ? "en-GB" : locale)}</span>{" "}
                <strong>{a.actor_name ?? "—"}</strong> · {a.action.replace(/_/g, " ")} {a.entity.replace(/_/g, " ")}
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
