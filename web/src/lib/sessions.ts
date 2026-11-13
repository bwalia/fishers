/// Scheduling nets and training, once or every week, and reading one back.
///
/// The server has had both kinds of event all along; what was missing was a
/// way to make one. A weekly series is one `POST /events` per week, sharing a
/// `metadata.series_id`, and only week one (`series_index` 0) notifies
/// anybody — see `ask_who_is_available` in `backend/api/src/routes/events.rs`.
///
/// Pure and import-free on purpose: `sessions.test.mjs` runs it under plain
/// `node --test`, so the date arithmetic that decides what lands in everyone's
/// diary is tested without a browser. Android and iOS build the same bodies.

export type PracticeKind = "nets" | "training";

/// What the schedule panel can make.
export type ScheduleKind = "match" | PracticeKind;

/// The lengths offered, in minutes.
export const SESSION_MINUTES = [60, 90, 120, 180] as const;

/// Nets run to two hours; a training session is usually shorter.
export const DEFAULT_MINUTES: Record<PracticeKind, number> = { nets: 120, training: 90 };

/// How many weeks a series may run when it repeats.
export const MIN_WEEKS = 2;
export const MAX_WEEKS = 12;
export const DEFAULT_WEEKS = 8;

/// Each kind's name in the dictionary. The default title, and the label on a
/// card, are the same word.
export const PRACTICE_LABEL: Record<PracticeKind, "ev.nets" | "ev.training"> = {
  nets: "ev.nets",
  training: "ev.training",
};

/// A session to turn up to, not a side to be picked for: no opposition, no
/// squad, no scorecard. Everything else is a match and shows as before.
export function isPractice(subtype: string): subtype is PracticeKind {
  return subtype === "nets" || subtype === "training";
}

/// What a club plays, for an event's `sport`. Hard-coding cricket filed every
/// fixture as a cricket match, whatever the club actually turns out for.
export function sportOf(sportTypes: readonly string[] | undefined): string {
  return sportTypes?.[0] ?? "cricket";
}

/// A weeks box clamped to what a series may be. Anything unreadable is the
/// default rather than a single week, which the checkbox already means.
export function clampWeeks(value: number): number {
  if (!Number.isFinite(value)) return DEFAULT_WEEKS;
  return Math.min(MAX_WEEKS, Math.max(MIN_WEEKS, Math.round(value)));
}

/// `YYYY-MM-DDTHH:mm` in local time, the format a `datetime-local` input reads
/// and writes. `toISOString` would be UTC and an hour out half the year.
export function toLocalInput(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

/// The start of each week, seven calendar days apart in local time.
///
/// Not seven times 24 hours: across a clock change that lands nets at 18:00
/// or 20:00 instead of the 19:00 everybody agreed. `setDate` on a local Date
/// keeps the wall-clock time and lets the UTC instant move instead.
export function weeklyStarts(first: Date, weeks: number): Date[] {
  const out: Date[] = [];
  const d = new Date(first.getTime());
  for (let i = 0; i < weeks; i++) {
    out.push(new Date(d.getTime()));
    d.setDate(d.getDate() + 7);
  }
  return out;
}

export type SessionMetadata = {
  note?: string;
  series_id?: string;
  series_index?: number;
  series_count?: number;
};

/// One `POST /events` body for a session. No `opponent_club_id` and no
/// `recurrence_rule`: a series is separate events, each answerable on its own.
export type SessionBody = {
  club_id: string;
  team_id?: string;
  sport: string;
  event_subtype: PracticeKind;
  title: string;
  venue_id?: string;
  start_at: string;
  end_at: string;
  metadata: SessionMetadata;
};

export type SessionPlan = {
  kind: PracticeKind;
  clubId: string;
  teamId?: string;
  sport: string;
  title: string;
  venueId?: string;
  /// The first session's local start.
  start: Date;
  minutes: number;
  note?: string;
  /// 1 for a single session.
  weeks: number;
  /// Shared by every week of a series. Needed only when `weeks` is above 1;
  /// passed in, not made here, so this stays pure.
  seriesId?: string;
};

/// Every body to send, first week first.
export function sessionBodies(plan: SessionPlan): SessionBody[] {
  const weeks = Math.max(1, Math.floor(plan.weeks));
  const series = weeks > 1;
  if (series && !plan.seriesId) throw new Error("a weekly series needs a series id");
  const note = plan.note?.trim();

  return weeklyStarts(plan.start, weeks).map((start, i) => {
    const metadata: SessionMetadata = {};
    if (note) metadata.note = note;
    if (series) {
      metadata.series_id = plan.seriesId;
      metadata.series_index = i;
      metadata.series_count = weeks;
    }
    const body: SessionBody = {
      club_id: plan.clubId,
      sport: plan.sport,
      event_subtype: plan.kind,
      title: plan.title,
      start_at: start.toISOString(),
      end_at: new Date(start.getTime() + plan.minutes * 60_000).toISOString(),
      metadata,
    };
    if (plan.teamId) body.team_id = plan.teamId;
    if (plan.venueId) body.venue_id = plan.venueId;
    return body;
  });
}

export type MatchPlan = {
  clubId: string;
  /// The hosting club, when the panel knows it.
  club?: { name: string; sport_types: readonly string[] };
  /// A club on the app, when the opposition is one.
  opponent: { club_id: string; name: string } | null;
  /// What was typed, when the opposition is not on the app.
  oppositionName: string;
  venueId: string;
  start: Date;
};

/// The match body, exactly as the schedule panel has always sent it. Here so
/// a test can hold it still while nets and training are added beside it.
export function matchBody(plan: MatchPlan) {
  // A fixture runs most of an afternoon; nobody wants to type an end time as
  // well.
  const end = new Date(plan.start.getTime() + 5 * 60 * 60 * 1000);
  const us = plan.club?.name ?? "Us";
  return {
    club_id: plan.clubId,
    opponent_club_id: plan.opponent?.club_id ?? null,
    sport: sportOf(plan.club?.sport_types),
    event_subtype: "league_match",
    title: `${us} v ${plan.opponent?.name ?? (plan.oppositionName || "opposition")}`,
    venue_id: plan.venueId || null,
    start_at: plan.start.toISOString(),
    end_at: end.toISOString(),
  };
}

function field(metadata: unknown, name: string): unknown {
  return metadata && typeof metadata === "object" ? (metadata as Record<string, unknown>)[name] : undefined;
}

/// The note a session was scheduled with, if any.
export function sessionNote(metadata: unknown): string | null {
  const note = field(metadata, "note");
  return typeof note === "string" && note.trim() ? note.trim() : null;
}

/// "Week i of n", counted from one, for an event that is part of a series.
export function seriesWeek(metadata: unknown): { i: number; n: number } | null {
  const index = field(metadata, "series_index");
  const count = field(metadata, "series_count");
  if (typeof index !== "number" || typeof count !== "number") return null;
  if (!Number.isInteger(index) || !Number.isInteger(count) || count < 2 || index < 0 || index >= count) return null;
  return { i: index + 1, n: count };
}
