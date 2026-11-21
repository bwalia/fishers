/// Passes, prices for juniors and the like, and group fees (plan §11): the
/// small pure parts the screens share — dates, the five templates a
/// secretary starts from, and how a pass stands, in words a player reads.
///
/// Kept free of the API client and the dictionary so `npm test` can import
/// it directly; only types come from elsewhere, and those are erased.

import type { PassHolder, PassPlan, PriceType } from "./payments";

/// A calendar day from the API ("2026-12-06") as a local date. `new Date()`
/// reads a bare date as midnight UTC, which is the evening before anywhere
/// west of London — "by Sat 5 Dec" for a fee due on the 6th.
export function dayDate(day: string): Date {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(day);
}

/// Today as the API writes a day, in this browser's own time zone.
export function todayDay(now: Date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/// "Sun 6 Dec": the way the server's own WhatsApp messages say a due date.
export function shortDay(day: string): string {
  return dayDate(day).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
}

/// "31 Mar 2027": a date far enough off to need its year.
export function longDay(day: string): string {
  return dayDate(day).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

/// The next 31 March on or after today: when a winter nets pass ends.
export function nextMarch31(now: Date = new Date()): string {
  const year = now.getMonth() > 2 ? now.getFullYear() + 1 : now.getFullYear();
  return `${year}-03-31`;
}

/// Session kinds a pass can cover, in the order the form offers them.
export const COVERABLE = ["nets", "training", "friendly", "league_match", "tournament", "social"] as const;

/// What a secretary is filling in to make a pass. Text boxes hold text; the
/// body sent is worked out from it by `passBody`.
export type PassDraft = {
  name: string;
  price: string;
  /// `once`, `monthly` or `instalments`.
  billing: string;
  instalments: string;
  covers: string[];
  /// `date` (until a day), `sessions` (a number of them) or `none` (while
  /// it runs; a monthly pass always runs until it is cancelled).
  lasts: string;
  valid_until: string;
  sessions: string;
  /// Only for one group's members (juniors, say), or "" for anyone.
  price_type_id: string;
  open_to_join: boolean;
};

export type TemplateId = "winter" | "card10" | "monthly" | "season" | "junior";
export const TEMPLATE_IDS: TemplateId[] = ["winter", "card10", "monthly", "season", "junior"];

/// The group a "junior" pass is for: the club's own Junior group, by name.
export function juniorGroup(types: PriceType[]): PriceType | undefined {
  const live = types.filter((p) => !p.archived_at && !p.for_guests);
  return live.find((p) => /junior|under|u1\d/i.test(p.name));
}

/// A pass with nothing filled in: paid once, covering nothing yet.
export function blankDraft(name = ""): PassDraft {
  return {
    name,
    price: "",
    billing: "once",
    instalments: "3",
    covers: [],
    lasts: "none",
    valid_until: "",
    sessions: "",
    price_type_id: "",
    open_to_join: true,
  };
}

/// One of the five starting points (plan §3), as a draft to change. `name`
/// is the template's own name in the reader's language.
export function templateDraft(id: TemplateId, name: string, types: PriceType[], now: Date = new Date()): PassDraft {
  const base = blankDraft(name);
  switch (id) {
    case "winter":
      return { ...base, price: "60.00", covers: ["nets"], lasts: "date", valid_until: nextMarch31(now) };
    case "card10":
      return { ...base, price: "40.00", covers: ["nets"], lasts: "sessions", sessions: "10" };
    case "monthly":
      return { ...base, price: "20.00", billing: "monthly", covers: ["nets"] };
    case "season":
      return { ...base, price: "120.00", billing: "instalments", instalments: "3" };
    case "junior":
      return { ...base, price: "50.00", price_type_id: juniorGroup(types)?.id ?? "" };
  }
}

/// What is wrong with a draft, as a dictionary key, or the body to send.
/// `cents` is the price already read by `parseAmount`.
export function passBody(
  d: PassDraft,
  cents: number | null,
):
  | { problem: "pw3.need_name" | "pay.not_an_amount" | "pw3.parts_range" | "pw3.sessions_range" | "pw3.need_date" }
  | { body: Record<string, unknown> } {
  if (!d.name.trim()) return { problem: "pw3.need_name" };
  if (cents == null || cents <= 0) return { problem: "pay.not_an_amount" };
  const parts = Number(d.instalments);
  if (d.billing === "instalments" && !(Number.isInteger(parts) && parts >= 2 && parts <= 12)) {
    return { problem: "pw3.parts_range" };
  }
  const monthly = d.billing === "monthly";
  const sessions = Number(d.sessions);
  if (!monthly && d.lasts === "sessions" && !(Number.isInteger(sessions) && sessions >= 1 && sessions <= 500)) {
    return { problem: "pw3.sessions_range" };
  }
  if (!monthly && d.lasts === "date" && !/^\d{4}-\d{2}-\d{2}$/.test(d.valid_until)) return { problem: "pw3.need_date" };
  return {
    body: {
      name: d.name.trim(),
      price_cents: cents,
      billing: d.billing,
      instalments: d.billing === "instalments" ? parts : undefined,
      covers: d.covers,
      valid_until: !monthly && d.lasts === "date" ? d.valid_until : undefined,
      sessions: !monthly && d.lasts === "sessions" ? sessions : undefined,
      price_type_id: d.price_type_id || undefined,
      open_to_join: d.open_to_join,
    },
  };
}

/// How a pass stands, for the player who has it (or the parent who pays for
/// it). The one thing that matters most comes first: not covering at all,
/// then late, then how much is left.
export type PassState =
  | { kind: "suspended" }
  | { kind: "cancelled"; until: string }
  | { kind: "starts"; on: string }
  | { kind: "behind" }
  | { kind: "sessions"; left: number }
  | { kind: "until"; on: string }
  | { kind: "monthly" }
  | { kind: "running" }
  | { kind: "stopped" };

export function passState(
  h: Pick<PassHolder, "standing" | "cancelled_at" | "ends_on" | "started_on" | "sessions_left" | "running" | "billing">,
  plan: Pick<PassPlan, "valid_until"> | undefined,
  today: string = todayDay(),
): PassState {
  if (h.standing === "suspended") return { kind: "suspended" };
  if (h.cancelled_at && h.ends_on) return { kind: "cancelled", until: h.ends_on };
  if (h.started_on > today) return { kind: "starts", on: h.started_on };
  if (h.standing === "behind") return { kind: "behind" };
  if (h.sessions_left != null) return { kind: "sessions", left: h.sessions_left };
  if (plan?.valid_until) return { kind: "until", on: plan.valid_until };
  if (h.billing === "monthly") return { kind: "monthly" };
  return h.running ? { kind: "running" } : { kind: "stopped" };
}
