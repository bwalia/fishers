/// Club accounts — the shapes `/clubs/{id}/accounts/…` answers with, and the
/// small amount of arithmetic the screens do themselves.
///
/// Money is pence, as an integer, everywhere. The only place a decimal exists
/// is the text box the treasurer types into; `parsePounds` turns it back into
/// pence before anything else sees it.

export type AccountPeriod = {
  id: string;
  club_id: string;
  label: string;
  starts_on: string;
  ends_on: string;
  status: "open" | "closed";
  currency: string;
  opening_balance_cents: number;
  report_text: string | null;
  statement_text: string | null;
  signed_by_name: string | null;
  signed_on: string | null;
  closed_at: string | null;
};

export type AccountCategory = {
  id: string;
  kind: "income" | "expenditure";
  name: string;
  system_key: string | null;
  sort_order: number;
  footnote: string | null;
  archived: boolean;
};

export type MoneyAccount = {
  id: string;
  name: string;
  kind: "bank" | "cash" | "supplier_credit" | "provider";
  sort_order: number;
  archived: boolean;
};

export type MoneyPosition = {
  id: string;
  name: string;
  kind: string;
  opening_cents: number;
  computed_closing_cents: number;
  reconciled_cents: number | null;
  reconciled_on: string | null;
};

export type AccountTransaction = {
  id: string;
  period_id: string;
  occurred_on: string;
  kind: "income" | "expenditure" | "adjustment";
  category_id: string | null;
  category_name: string | null;
  money_account_id: string | null;
  money_account_name: string | null;
  amount_cents: number;
  description: string;
  counterparty: string | null;
  member_name: string | null;
  note: string | null;
  receipt_url: string | null;
  extraordinary: boolean;
  authorised_on: string | null;
  authorisation_ref: string | null;
  source: string | null;
  voided_at: string | null;
  void_reason: string | null;
  created_by_name: string | null;
};

export type DebtPosition = {
  id: string;
  period_id: string;
  period_label: string;
  direction: "debtor" | "creditor";
  kind: "member_fees" | "cost_share" | "other";
  description: string;
  counterparty: string | null;
  member_name: string | null;
  raised_on: string;
  amount_cents: number;
  outstanding_at_close_cents: number;
  paid_since_close_cents: number;
  outstanding_now_cents: number;
  note: string | null;
};

export type StockPosition = {
  item_id: string;
  name: string;
  opening_quantity: number;
  opening_cents: number;
  closing_quantity: number;
  closing_cents: number;
  counted_on: string | null;
};

export type ReportLine = {
  category_id: string;
  name: string;
  system_key: string | null;
  amount_cents: number;
  footnote: number | null;
  stock_adjustment_cents: number;
};

export type AssetLine = {
  label: string;
  kind: "money" | "stock" | "debtors" | "creditors";
  amount_cents: number;
  reconciled: boolean | null;
  computed_cents: number | null;
};

export type AccountsReport = {
  period_id: string;
  label: string;
  starts_on: string;
  ends_on: string;
  status: "open" | "closed";
  currency: string;
  income: ReportLine[];
  income_total_cents: number;
  expenditure: ReportLine[];
  expenditure_total_cents: number;
  surplus_cents: number;
  footnotes: { number: number; text: string }[];
  balance_sheet: {
    brought_forward_cents: number;
    adjustments_cents: number;
    income_cents: number;
    total_cents: number;
    expenditure_cents: number;
    carried_forward_cents: number;
    represented_by: AssetLine[];
    represented_total_cents: number;
    difference_cents: number;
    unreconciled_accounts: string[];
  };
  debtors: DebtPosition[];
  debtors_total_cents: number;
  creditors: DebtPosition[];
  creditors_total_cents: number;
  stock: StockPosition[];
  insights: {
    surplus_cents: number;
    extraordinary_cents: number;
    surplus_excluding_extraordinary_cents: number;
    nets: { received_cents: number; cost_cents: number; net_cents: number } | null;
    match_fees_cents: number;
    matches_played: number;
    match_fee_per_match_cents: number | null;
    equipment_per_match_cents: number | null;
    debtors_at_close_cents: number;
    paid_since_close_cents: number;
  };
  report_text: string | null;
  statement_text: string | null;
  signed_by_name: string | null;
  signed_on: string | null;
};

export type ReportResponse = {
  current: AccountsReport;
  previous: AccountsReport | null;
  club_name: string;
};

export type AccountsOverview = {
  access: { is_owner: boolean; is_treasurer: boolean };
  periods: AccountPeriod[];
  open_period_id: string | null;
  categories: AccountCategory[];
  money_accounts: MoneyAccount[];
  open_report: AccountsReport | null;
  suggested_next: { label: string; starts_on: string; ends_on: string };
};

export type PaymentSuggestion = {
  payment_id: string;
  paid_on: string;
  amount_cents: number;
  currency: string;
  member_name: string;
  event_title: string;
  event_subtype: string;
  settles_debt_id: string | null;
};

export type UnpaidFee = {
  event_id: string;
  event_title: string;
  played_on: string;
  member_id: string;
  member_name: string;
  amount_cents: number;
  already_raised: boolean;
};

export type Suggestions = { payments: PaymentSuggestion[]; unpaid_fees: UnpaidFee[] };

export type AuditEntry = {
  id: number;
  actor_name: string | null;
  action: string;
  entity: string;
  created_at: string;
};

/// "12.50", "£12.50", "1,234", "-69.92" → pence. `null` for anything that is
/// not a sum of money, so a typo is refused rather than saved as zero.
export function parsePounds(raw: string): number | null {
  const s = raw.replace(/[£,\s]/g, "");
  if (!/^-?\d+(\.\d{1,2})?$/.test(s)) return null;
  const negative = s.startsWith("-");
  const [whole, frac = ""] = s.replace("-", "").split(".");
  const pence = Number(whole) * 100 + Number(frac.padEnd(2, "0"));
  return negative ? -pence : pence;
}

/// Pence as the figure a treasurer types: "1234.50", no symbol, no commas.
export function toPounds(cents: number): string {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, "0")}`;
}

/// An accounts figure: thousands separated, two places, a minus for a loss.
/// No currency symbol — every column on an AGM report is in the same money,
/// and a £ on each line is noise.
export function figure(cents: number): string {
  const abs = Math.abs(cents);
  const pounds = Math.floor(abs / 100).toLocaleString("en-GB");
  return `${cents < 0 ? "-" : ""}${pounds}.${String(abs % 100).padStart(2, "0")}`;
}

/// "2026-09-30" → "30 Sep 2026", in the reader's locale, without the time
/// zone sliding it to the day before.
export function day(iso: string, locale = "en-GB"): string {
  const [y, m, d] = iso.split("-").map(Number);
  // The app's "en" is British English: 30 Sep 2026, never Sep 30, 2026.
  const tag = locale === "en" ? "en-GB" : locale;
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString(tag, {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  });
}

/// The same line in last year's report, matched by category, then by name
/// for a line renamed since.
export function previousAmount(
  line: ReportLine,
  previous: ReportLine[] | undefined,
): number | null {
  if (!previous) return null;
  const hit =
    previous.find((p) => p.category_id === line.category_id) ??
    previous.find((p) => p.name === line.name);
  return hit ? hit.amount_cents : null;
}

/// A CSV cell, quoted when it has to be.
export function csvCell(v: string | number | null | undefined): string {
  const s = v == null ? "" : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function downloadCsv(filename: string, rows: (string | number | null | undefined)[][]) {
  const text = rows.map((r) => r.map(csvCell).join(",")).join("\n");
  const blob = new Blob([text], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
