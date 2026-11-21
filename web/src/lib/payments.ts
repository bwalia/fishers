/// Paying the club by bank transfer: the shapes the API answers with, and the
/// little the screens work out for themselves. The contract is
/// docs/PAY_BY_BANK_TRANSFER.md §11; the serde structs in
/// backend/api/src/routes/club_payments.rs are the source of truth.
///
/// Money is minor units plus a currency, always, and `money()` in api.ts
/// formats it in that currency. A decimal exists only in a text box, and
/// `parseAmount` turns it back into minor units before anything else sees it.
///
/// States are strings, not closed unions: a value this build has never heard
/// of still renders under its own name rather than breaking the screen.

import { useRef } from "react";
import { api } from "./api";
import type { T } from "./i18n";
import type { Key } from "./i18n/en";
import { randomUUID } from "./uuid";

/// `owed`, `part_paid`, `waiting` (somebody said they paid; not confirmed),
/// `paid`, `waived` or `void`.
export type ShareState = string;

export type Share = {
  id: string;
  bill_id: string;
  event_id: string;
  title: string;
  event_start_at: string;
  user_id: string | null;
  guest_name: string | null;
  name: string;
  amount_cents: number;
  paid_cents: number;
  waiting_cents: number;
  currency: string;
  state: ShareState;
  reason: string | null;
};

export type ClubDues = {
  club_id: string;
  club_name: string;
  currency: string;
  owed_cents: number;
  waiting_cents: number;
  credit_cents: number;
  /// Still to pay or waiting first, then the most recent paid ones.
  shares: Share[];
};

export type Dues = { clubs: ClubDues[] };

/// The full details, shown only to somebody who owes the club, or its admins.
export type BankDetails = {
  label: string;
  holder_name: string;
  sort_code: string;
  account_number: string;
  is_personal: boolean;
  changed_at: string | null;
};

export type Payment = {
  id: string;
  club_id: string;
  user_id: string | null;
  guest_name: string | null;
  name: string;
  amount_cents: number;
  currency: string;
  /// `transfer`, `cash`, `card`, `credit` or `refund`.
  method: string;
  reference: string | null;
  payout_account_id: string | null;
  /// `claimed`, `confirmed`, `rejected` or `cancelled`.
  status: string;
  note: string | null;
  created_by: string | null;
  created_at: string;
  decided_by: string | null;
  decided_by_name: string | null;
  decided_at: string | null;
  decision_reason: string | null;
};

/// `active`, `none`, `frozen`, `unreadable` or `nothing_owed`.
export type AccountState = string;

export type PayScreen = {
  club_id: string;
  club_name: string;
  currency: string;
  owed_cents: number;
  waiting_cents: number;
  credit_cents: number;
  shares: Share[];
  account_state: AccountState;
  account: BankDetails | null;
  reference: string;
  /// Your claims nobody has confirmed yet.
  claims: Payment[];
};

/// One set of bank details as an admin sees it. Never the full number.
export type PayoutAccount = {
  id: string;
  label: string;
  holder_name: string;
  is_personal: boolean;
  sort_code: string | null;
  last4: string;
  /// `active`, `pending`, `frozen`, `superseded` or `retired`.
  state: string;
  live_from: string;
  created_at: string;
  created_by_name: string | null;
  freeze_reason: string | null;
  /// False when the key that sealed the number is gone: enter them again.
  readable: boolean;
};

export type PayoutAccounts = {
  can_manage: boolean;
  is_owner: boolean;
  current: PayoutAccount | null;
  /// A change waiting out its delay. Admins only.
  pending: PayoutAccount | null;
  /// Frozen details waiting for the owner. Admins only.
  frozen: PayoutAccount | null;
  changed_at: string | null;
};

export type PaymentSettings = {
  payments_enabled_at: string | null;
  auto_bill: boolean;
  auto_bill_after_hours: number;
  round_shares_up: boolean;
  fee_chase_after_hours: number;
  fee_chase_max_reminders: number;
};

export type MemberBalance = {
  user_id: string | null;
  guest_name: string | null;
  name: string;
  owed_cents: number;
  waiting_cents: number;
  credit_cents: number;
};

export type BillSummary = {
  bill_id: string;
  event_id: string;
  title: string;
  event_start_at: string;
  currency: string;
  total_cents: number;
  paid_cents: number;
  waiting_cents: number;
  owed_cents: number;
  people: number;
  unpaid: number;
  waiting: number;
};

export type MoneyOverview = {
  currency: string;
  settings: PaymentSettings;
  account: PayoutAccounts;
  to_check: Payment[];
  members: MemberBalance[];
  totals: { owed_cents: number; waiting_cents: number; credit_cents: number };
  bills: BillSummary[];
};

/// `split_total` (a total shared between whoever came) or `per_player`.
export type CostMode = string;

export type EventCost = {
  event_id: string;
  club_id: string;
  mode: CostMode;
  amount_cents: number;
  currency: string;
  note: string | null;
  updated_at: string;
};

export type Bill = {
  id: string;
  event_id: string;
  club_id: string;
  title: string;
  mode: CostMode;
  amount_cents: number;
  total_cents: number;
  currency: string;
  /// `issued` or `void`.
  status: string;
  /// Sent back to re-split, so two people changing it at once cannot both win.
  version: number;
  auto: boolean;
  note: string | null;
  issued_at: string;
  paid_cents: number;
  waiting_cents: number;
  owed_cents: number;
  surplus_cents: number;
};

export type Candidate = {
  user_id: string;
  name: string;
  /// `going`, `maybe`, `not_going`, `invited`, or `not_invited` for somebody
  /// in the club who was never asked — a walk-in who joined afterwards.
  rsvp: string;
  attended: boolean | null;
  /// Ticked to start with.
  suggested: boolean;
};

export type BillResponse = {
  event_id: string;
  club_id: string;
  title: string;
  start_at: string;
  end_at: string;
  event_status: string;
  cost: EventCost | null;
  bill: Bill | null;
  can_bill: boolean;
  can_manage_money: boolean;
  /// Everyone's for those who run it; only your own otherwise.
  shares: Share[];
  my_share: Share | null;
  /// Empty unless `can_bill`.
  candidates: Candidate[];
  /// Guests on the current bill, to carry into a re-split.
  guests: string[];
  has_payout_account: boolean;
  round_shares_up: boolean;
};

export type Preview = {
  shares: { user_id: string | null; name: string; amount_cents: number }[];
  total_cents: number;
  surplus_cents: number;
  currency: string;
};

/// The API's own limits, mirrored so the form can say so before sending.
/// The API still has the last word (`amount_limit`).
export const MAX_SHARE_CENTS = 100_000;
export const MAX_BILL_CENTS = 1_000_000;
/// Above this a head, the form asks "is that right?" first.
export const CONFIRM_SHARE_CENTS = 10_000;

const STATE_LABEL: Record<string, Key> = {
  owed: "pay.state_owed",
  part_paid: "pay.state_part_paid",
  waiting: "pay.state_waiting",
  paid: "pay.state_paid",
  waived: "pay.state_waived",
  void: "pay.state_void",
};

export function shareStateLabel(state: ShareState, t: T): string {
  const key = STATE_LABEL[state];
  return key ? t(key) : state.replaceAll("_", " ");
}

/// The badge colour: owed stands out, settled recedes.
export function shareStateTag(state: ShareState): string {
  if (state === "paid") return "tag";
  if (state === "owed" || state === "part_paid") return "tag gold";
  return "tag grey";
}

/// "60", "7.50", "£1,234.5", "₹ 500" → minor units. `null` for anything that
/// is not plainly an amount, so a typo is refused rather than sent as zero.
export function parseAmount(raw: string): number | null {
  const s = raw.trim().replace(/^[£$€₹]/, "").replace(/[,\s]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const [whole, frac = ""] = s.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

/// Minor units as somebody would type them: "7.50".
export function toAmount(cents: number): string {
  return `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, "0")}`;
}

/// "Fri 20 Nov".
export function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
}

/// "Sat 21 Nov, 14:30".
export function dateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/// Codes that mean somebody else got there first, or the page is behind:
/// reload, and show the server's sentence.
export const STALE_CODES = new Set(["version_conflict", "already_billed", "already_decided", "nothing_owed", "no_bill"]);

/// A POST that must happen once however many times it is sent.
///
/// The server keeps the first answer for an `Idempotency-Key` and gives it
/// back to every retry, so a double tap or a lost reply on bad signal can
/// never make two payments.
export function postOnce<R>(path: string, body: unknown, key: string): Promise<R> {
  return api<R>("POST", path, body, true, false, undefined, { "Idempotency-Key": key });
}

/// One key per attempt, kept until it succeeds.
///
/// `key(what)` gives the same UUID for as long as `what` — everything the
/// request says — stays the same, so pressing again after a failure is a
/// retry. A different `what` is a different request and gets a new key: had
/// the first one quietly succeeded, reusing its key would hand back that
/// payment instead of making this one. `done()` after success.
export function useAttemptKey() {
  const held = useRef<{ what: string; key: string } | null>(null);
  return {
    key(what: string): string {
      if (held.current?.what !== what) held.current = { what, key: randomUUID() };
      return held.current.key;
    },
    done() {
      held.current = null;
    },
  };
}

/// Shares that differ by a penny, said the way a person would:
/// "6 pay £6.67, 3 pay £6.66" — or just the one amount when they are all equal.
export function shareGroups(amounts: number[]): { amount_cents: number; count: number }[] {
  const by = new Map<number, number>();
  for (const a of amounts) by.set(a, (by.get(a) ?? 0) + 1);
  return [...by.entries()].sort((a, b) => b[0] - a[0]).map(([amount_cents, count]) => ({ amount_cents, count }));
}
