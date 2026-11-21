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
import { api, apiV1, money, usableToken } from "./api";
import type { T } from "./i18n";
import type { Key } from "./i18n/en";
import { firstName, fingerprint, fitWithin } from "./pay-link";
import { longDay, shortDay } from "./passes";
import { randomUUID } from "./uuid";

/// `owed`, `part_paid`, `waiting` (somebody said they paid; not confirmed),
/// `paid`, `waived`, `covered` (by a pass: nothing to pay) or `void`.
export type ShareState = string;

export type Share = {
  id: string;
  bill_id: string;
  /// The session it is for. Null for a line that is not from a session: a
  /// monthly pass charge or a group fee.
  event_id: string | null;
  /// `event`, `pass` or `collection`. Older APIs leave it out, meaning `event`.
  kind?: string;
  /// When a pass charge or group fee falls due, as a date.
  due_on?: string | null;
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

/// Somebody you pay for (a parent's junior), and what they owe one club.
export type PersonDues = {
  user_id: string;
  name: string;
  /// Has no sign-in of their own: a junior added by name.
  managed: boolean;
  club_id: string;
  dues: ClubDues;
};

/// `people` is missing from APIs older than passes (step B).
export type Dues = { clubs: ClubDues[]; people?: PersonDues[] };

/// The full details, shown only to somebody who owes the club, or its admins.
export type BankDetails = {
  label: string;
  holder_name: string;
  sort_code: string;
  account_number: string;
  is_personal: boolean;
  changed_at: string | null;
  /// What the person who added personal details is to the club —
  /// `secretary`, `treasurer` or `owner` — for "Pay Aman Gill, the club
  /// secretary". Null for a club account.
  payee_role?: string | null;
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
  /// The line on a bill this pays, when it was said from a pay link or
  /// ticked as cash at the ground.
  share_id?: string | null;
  /// Said from a WhatsApp pay link rather than in the app.
  via_link?: string | null;
  /// A picture of the payment came with it.
  has_screenshot?: boolean;
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

/// `GET /clubs/{id}/payments/defaults`: the club's usual prices, readable by
/// any member (a captain scheduling nets), unlike the full settings.
export type UsualPrices = {
  default_nets_mode: CostMode | null;
  default_nets_cents: number | null;
  default_match_fee_cents: number | null;
  currency: string;
};

export type PaymentSettings = {
  payments_enabled_at: string | null;
  auto_bill: boolean;
  auto_bill_after_hours: number;
  round_shares_up: boolean;
  fee_chase_after_hours: number;
  fee_chase_max_reminders: number;
  /// The club's usual nets price, offered on every new nets session.
  default_nets_mode?: string | null;
  default_nets_cents?: number | null;
  /// The usual match fee, offered on every new match.
  default_match_fee_cents?: number | null;
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
  /// Null for a bill that is not for a session: a group fee.
  event_id: string | null;
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
  /// The session's own prices for juniors, guests and so on. Older APIs leave
  /// it out.
  prices?: TypePrice[];
};

/// One group's price for one session: "Junior £3".
export type TypePrice = { price_type_id: string; name: string; amount_cents: number };

export type Preview = {
  /// `covered` is why somebody owes nothing ("Covered by Monthly nets",
  /// "Free: Coach"), or null.
  shares: { user_id: string | null; name: string; amount_cents: number; covered?: string | null }[];
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
  covered: "pw2.state_covered",
  void: "pay.state_void",
};

export function shareStateLabel(state: ShareState, t: T): string {
  const key = STATE_LABEL[state];
  return key ? t(key) : state.replaceAll("_", " ");
}

/// The badge colour: owed stands out, settled recedes.
export function shareStateTag(state: ShareState): string {
  if (state === "paid" || state === "covered") return "tag";
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

/// When a line is for: its session's day, or the day a pass charge or group
/// fee falls due. Empty when neither is known.
export function shareDate(s: { event_start_at?: string | null; due_on?: string | null }): string {
  const when = s.event_start_at || s.due_on;
  return when ? shortDate(when) : "";
}

/// When a line is for, in words: a session's day, or "by Sun 6 Dec" for a
/// pass charge or group fee with a due date. A line that is not a session and
/// has no due date says nothing — its own date is only when it was sent.
export function shareWhen(s: Pick<Share, "kind" | "event_start_at" | "due_on">, t: T): string {
  if (s.kind && s.kind !== "event") return s.due_on ? t("pw3.by_date", { date: shortDay(s.due_on) }) : "";
  return s.event_start_at ? shortDate(s.event_start_at) : "";
}

/// The badge on a line. A covered one says why, in the server's words
/// ("Covered by Monthly nets", "Free: Coach"), with a tick: there is nothing
/// to pay and nothing to tap.
export function shareTag(s: Pick<Share, "state" | "reason">, t: T): string {
  if (s.state === "covered") return `${s.reason || t("pw2.state_covered")} ✓`;
  return shareStateLabel(s.state, t);
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

// MARK: easy paying (step A)

/// `POST /events/{id}/bill/link`: the bill's pay link and the messages to
/// post with it.
export type PayLinkShare = {
  url: string;
  expires_at: string;
  /// "🏏 Friday nets, Fri 20 Nov: £5.00 each.\nTap to pay: …"
  bill_message: string;
  /// "Still to pay for Friday nets: Josh and Imran.\nTap to pay: …"
  reminder_message: string;
  /// Who still owes, by full name.
  still_to_pay: string[];
};

/// `GET /pay-links/{token}`: what the public pay page opens on.
export type LinkPage = {
  club_name: string;
  title: string;
  event_start_at: string;
  currency: string;
  expires_at: string;
  /// Everybody on the bill, by name only.
  people: { id: string; name: string }[];
  /// Your own line, when you are signed in on this phone and on the bill.
  me: string | null;
  account_state: AccountState;
  account: BankDetails | null;
};

/// A payment said from the link, waiting for the club to check it.
export type LinkClaim = {
  id: string;
  /// `transfer` or `cash`.
  method: string;
  amount_cents: number;
  created_at: string;
  /// Taken back from this link, within the hour, while nobody has checked it.
  can_undo: boolean;
  has_screenshot: boolean;
};

/// `GET /pay-links/{token}/people/{id}`: one person's line on the bill.
export type LinkPerson = Share & {
  /// Still to pay on this bill: not paid, said to be paid or let off.
  owed_cents: number;
  /// What to write in the reference box.
  reference: string;
  claim: LinkClaim | null;
};

/// `POST /events/{id}/bill/cash`.
export type CashRecorded = { recorded: number; total_cents: number; received: boolean };

/// `POST /clubs/{id}/payments/confirm`.
export type Confirmed = { confirmed: number; skipped: number };

// MARK: passes, prices by group, group fees, paying for others (steps B and C)

/// A group with its own price: juniors, students, guests, coaches.
export type PriceType = {
  id: string;
  club_id: string;
  name: string;
  /// Owes nothing at a session: coaches, say.
  free: boolean;
  /// The price a guest added by name pays.
  for_guests: boolean;
  sort_order: number;
  archived_at: string | null;
};

/// `up_to_date`, `behind` (a payment late, still covering) or `suspended`
/// (not covering until paid up).
export type PassStanding = string;

/// Somebody on a pass.
export type PassHolder = {
  id: string;
  plan_id: string;
  club_id: string;
  user_id: string;
  name: string;
  started_on: string;
  /// The last day it covers, once cancelled or ended.
  ends_on: string | null;
  cancelled_at: string | null;
  /// Covers however far behind, because an admin said so.
  keep_covering: boolean;
  plan_name: string;
  /// `once`, `monthly` or `instalments`.
  billing: string;
  standing: PassStanding;
  /// A card's sessions left, where it has a number.
  sessions_left: number | null;
  /// Covers sessions today.
  running: boolean;
  next_charge_on: string | null;
};

/// A pass the club offers.
export type PassPlan = {
  id: string;
  club_id: string;
  name: string;
  price_cents: number;
  currency: string;
  billing: string;
  instalments: number | null;
  /// Session kinds: `nets`, `training`, `friendly`, `league_match`,
  /// `tournament`, `social`. Empty for a membership.
  covers: string[];
  team_id: string | null;
  valid_until: string | null;
  sessions: number | null;
  /// Only for members in this group.
  price_type_id: string | null;
  /// Players may get it themselves; otherwise the secretary adds them.
  open_to_join: boolean;
  created_at: string;
  archived_at: string | null;
  /// One payment: the price, or one part of it.
  charge_cents: number;
  holders: number;
  /// Your own running pass on it.
  mine: PassHolder | null;
};

/// Exactly what to type into a banking app for a monthly pass.
export type StandingOrder = {
  amount_cents: number;
  /// "month".
  every: string;
  first_payment_on: string;
  reference: string;
};

/// `GET /me/passes`: yours, and those of people you pay for.
export type MyPass = PassHolder & {
  club_name: string;
  charge_cents: number;
  currency: string;
  standing_order: StandingOrder | null;
};

/// A group fee: a bill not tied to a session.
export type GroupFee = {
  id: string;
  event_id: string | null;
  club_id: string;
  title: string;
  event_start_at: string;
  mode: CostMode;
  amount_cents: number;
  total_cents: number;
  currency: string;
  /// `issued` or `void`.
  status: string;
  note: string | null;
  issued_at: string;
  void_reason: string | null;
  due_on: string | null;
  paid_cents: number;
  waiting_cents: number;
  owed_cents: number;
  people: number;
  /// Everyone's for an admin; empty in the list.
  shares: Share[];
};

/// `POST /clubs/{id}/payments/for-others`.
export type ForOthers = { payments: Payment[]; total_cents: number; reference: string | null };

/// One club's money: yours, and that of anybody you pay for there. A parent
/// who was never billed themselves still gets the club, for their juniors.
export type ClubBlock = {
  club_id: string;
  club_name: string;
  currency: string;
  mine: ClubDues | null;
  people: PersonDues[];
};

export function clubBlocks(dues: Dues): ClubBlock[] {
  const out = new Map<string, ClubBlock>();
  for (const c of dues.clubs) {
    out.set(c.club_id, { club_id: c.club_id, club_name: c.club_name, currency: c.currency, mine: c, people: [] });
  }
  for (const p of dues.people ?? []) {
    const block = out.get(p.club_id) ?? {
      club_id: p.club_id,
      club_name: p.dues.club_name,
      currency: p.dues.currency,
      mine: null,
      people: [],
    };
    block.people.push(p);
    out.set(p.club_id, block);
  }
  return [...out.values()];
}

/// What a club block comes to: yours plus everyone you pay for there.
export function blockOwed(b: ClubBlock): number {
  return (b.mine?.owed_cents ?? 0) + b.people.reduce((sum, p) => sum + Math.max(0, p.dues.owed_cents), 0);
}

const COVERS: Record<string, Key> = {
  nets: "pw3.kind_nets",
  training: "pw3.kind_training",
  friendly: "pw3.kind_friendly",
  league_match: "pw3.kind_league_match",
  tournament: "pw3.kind_tournament",
  social: "pw3.kind_social",
};

/// "nets and training", "nets, friendlies and league matches".
export function listWords(items: string[], t: T): string {
  if (items.length <= 1) return items[0] ?? "";
  return t("pw3.list_and", { a: items.slice(0, -1).join(", "), b: items[items.length - 1] });
}

export function kindWord(kind: string, t: T): string {
  return COVERS[kind] ? t(COVERS[kind]) : kind.replaceAll("_", " ");
}

/// "£20.00 a month", "£60.00 once", "£120.00 in 3 parts of £40.00".
export function passPrice(p: Pick<PassPlan, "billing" | "price_cents" | "charge_cents" | "instalments" | "currency">, t: T): string {
  const amount = money(p.price_cents, p.currency);
  if (p.billing === "monthly") return t("pw3.price_month", { amount: money(p.charge_cents, p.currency) });
  if (p.billing === "instalments" && p.instalments) {
    return t("pw3.price_parts", { amount, n: p.instalments, part: money(p.charge_cents, p.currency) });
  }
  return t("pw3.price_once", { amount });
}

/// "Covers nets and training", "Covers nets until 31 Mar 2027", "Covers
/// nets, for 10 sessions", or "Club membership" when it covers no sessions.
export function passCovers(p: Pick<PassPlan, "covers" | "valid_until" | "sessions">, t: T): string {
  if (p.covers.length === 0) {
    return p.valid_until ? t("pw3.membership_until", { date: longDay(p.valid_until) }) : t("pw3.membership_only");
  }
  const what = listWords(p.covers.map((c) => kindWord(c, t)), t);
  if (p.sessions) return t("pw3.covers_sessions", { what, count: p.sessions, n: p.sessions });
  if (p.valid_until) return t("pw3.covers_until", { what, date: longDay(p.valid_until) });
  return t("pw3.covers", { what });
}

/// How a pass stands, to the club's money admins.
export function standingWord(standing: PassStanding, t: T): string {
  if (standing === "up_to_date") return t("pw3.standing_up_to_date");
  if (standing === "behind") return t("pw3.standing_behind");
  if (standing === "suspended") return t("pw3.standing_suspended");
  return standing.replaceAll("_", " ");
}

/// "Pay Aman Gill, the club secretary": who the money goes to, by name and
/// what they are to the club.
export function payeeLine(account: BankDetails, t: T): string {
  const name = account.holder_name;
  switch (account.payee_role) {
    case "secretary":
      return t("pw2.pay_name_secretary", { name });
    case "treasurer":
      return t("pw2.pay_name_treasurer", { name });
    case "owner":
      return t("pw2.pay_name_owner", { name });
    default:
      return t("pw2.pay_name", { name });
  }
}

/// The first name of the person who checks the money arrived, where the
/// details are somebody's own: "waiting for Aman to check". Null for a club
/// account, which says "the club" instead.
export function checker(account: BankDetails | null | undefined): string | null {
  return account?.is_personal && account.payee_role ? firstName(account.holder_name) : null;
}

/// "You've paid these details before": kept as a fingerprint, so the
/// browser's storage never holds an account number. Changed details make a
/// different fingerprint, and the first-time guide comes back — which is
/// right, because the player has a new payee to add.
const paidBeforeKey = (a: BankDetails) =>
  `fishers:paid-before:${fingerprint(`${a.holder_name}|${a.sort_code}|${a.account_number}`)}`;

export function paidBefore(a: BankDetails): boolean {
  try {
    return localStorage.getItem(paidBeforeKey(a)) === "1";
  } catch {
    return false;
  }
}

export function markPaidBefore(a: BankDetails) {
  try {
    localStorage.setItem(paidBeforeKey(a), "1");
  } catch {
    /* a private window: the guide shows again next time, which is harmless */
  }
}

/// A call to the public pay link. It never needs a sign-in, but sends one
/// when this browser has one so the page can open on the person's own name.
///
/// Not `api()`: that sends anybody whose session has lapsed to the sign-in
/// screen, which is the one place a pay link must never take somebody.
export async function linkApi<R>(
  method: string,
  path: string,
  body?: unknown,
  extra?: Record<string, string>,
): Promise<R> {
  const headers: Record<string, string> = { ...extra };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const token = await usableToken().catch(() => null);
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${apiV1()}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store",
    referrerPolicy: "no-referrer",
  });
  return answer<R>(res);
}

async function answer<R>(res: Response): Promise<R> {
  if (!res.ok) {
    const error = new Error((await res.text()) || `HTTP ${res.status}`);
    (error as Error & { status?: number }).status = res.status;
    throw error;
  }
  if (res.status === 204) return undefined as R;
  return (await res.json()) as R;
}

/// Send a picture as the raw bytes the API wants. `link` calls go without
/// needing a sign-in; the others are the signed-in payer's own.
export async function postImage(path: string, image: Blob, link = false): Promise<void> {
  const headers: Record<string, string> = { "Content-Type": image.type || "image/jpeg" };
  const token = await usableToken().catch(() => null);
  if (token) headers.Authorization = `Bearer ${token}`;
  else if (!link) throw Object.assign(new Error("signed out"), { status: 401 });
  const res = await fetch(`${apiV1()}${path}`, { method: "POST", headers, body: image, cache: "no-store" });
  await answer<void>(res);
}

/// A picture only a signed-in money admin may see, as a blob for an
/// object URL — an `<img src>` cannot carry the sign-in.
export async function getImage(path: string): Promise<Blob> {
  const token = await usableToken();
  const res = await fetch(`${apiV1()}${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    cache: "no-store",
  });
  if (!res.ok) {
    const error = new Error((await res.text()) || `HTTP ${res.status}`);
    (error as Error & { status?: number }).status = res.status;
    throw error;
  }
  return res.blob();
}

/// The picture could not be opened in this browser — a format it cannot
/// draw, or not a picture at all.
export class UnreadablePicture extends Error {}

/// The API takes at most a megabyte. A phone screenshot is several, so it is
/// drawn again here: at most 1600 px on its long side, as a JPEG, a little
/// rougher each time until it fits.
const MAX_SIDE = 1600;
const MAX_BYTES = 1_000_000;

export async function shrinkScreenshot(file: File): Promise<Blob> {
  const picture = await decode(file);
  let side = MAX_SIDE;
  for (let round = 0; round < 4; round++) {
    const { width, height } = fitWithin(picture.width, picture.height, side);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new UnreadablePicture();
    // A PNG with see-through parts would turn black as a JPEG.
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(picture.source, 0, 0, width, height);
    for (const quality of [0.7, 0.55, 0.4]) {
      const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/jpeg", quality));
      if (!blob) throw new UnreadablePicture();
      if (blob.size <= MAX_BYTES) {
        picture.close();
        return blob;
      }
    }
    side = Math.round(side * 0.7);
  }
  picture.close();
  throw new UnreadablePicture();
}

type Decoded = { source: CanvasImageSource; width: number; height: number; close: () => void };

async function decode(file: File): Promise<Decoded> {
  if (typeof createImageBitmap === "function") {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
      return { source: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() };
    } catch {
      /* older Safari: try an <img> below */
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    return { source: img, width: img.naturalWidth, height: img.naturalHeight, close: () => URL.revokeObjectURL(url) };
  } catch {
    URL.revokeObjectURL(url);
    throw new UnreadablePicture();
  }
}
