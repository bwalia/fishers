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
import { api, apiV1, usableToken } from "./api";
import type { T } from "./i18n";
import type { Key } from "./i18n/en";
import { firstName, fingerprint, fitWithin } from "./pay-link";
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

export type Dues = { clubs: ClubDues[] };

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
