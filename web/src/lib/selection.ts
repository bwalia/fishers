/// Picking a side (`backend/domain/src/selection.rs`).
///
/// Two signals about whether somebody can play, and they mean different
/// things: `availability` is their standing calendar — "I'm generally around on
/// Sundays" — and `rsvp` is their answer to *this* fixture. The direct answer
/// is the one a captain picks off; the calendar is a weaker, standing hint.

export type SelectionState =
  | "pool"
  | "selected"
  | "reserve"
  | "not_selected"
  | "confirmed"
  | "declined"
  | "dropped";

export type AvailabilityStatus = "available" | "maybe" | "unavailable";
export type RsvpStatus = "going" | "not_going" | "maybe" | "invited";

export type Candidate = {
  user_id: string;
  name: string;
  position: string | null;
  skill_level: string | null;
  /// Their general calendar for that date, if they keep one.
  availability: AvailabilityStatus | null;
  /// Their answer to this fixture.
  rsvp: RsvpStatus | null;
  reliability_score: number;
  reliability_band: string;
  /// Fixtures they were available for but left out of, last 60 days.
  games_missed_out: number;
  state: SelectionState;
  is_confirmed: boolean;
};

export type RankedCandidate = {
  user_id: string;
  name: string;
  score: number;
  /// Plain-English reasons, in the order they were applied.
  reasons: string[];
};

export type PositionQuota = { position: string; minimum: number };

export type SquadRequirements = {
  size: number;
  reserves: number;
  /// Advisory: quotas are filled first, then the best remaining players.
  position_quotas: PositionQuota[];
};

export type SelectionBoard = {
  event_id: string;
  title: string;
  sport: string;
  starts_at: string;
  status: string;
  status_note: string | null;
  requirements: SquadRequirements;
  /// `off` | `suggest` | `auto_publish`
  autonomy: string;
  confirm_lead_hours: number;
  drop_lead_hours: number;
  candidates: Candidate[];
  ranked: RankedCandidate[];
  selected_count: number;
  confirmed_count: number;
};

/// A squad waiting on a captain, from the ranking or from the assistant.
export type SquadProposal = {
  /// `ranking` when the deterministic model produced it, `assistant` when the
  /// model did.
  source: string;
  selected: RankedCandidate[];
  reserves: RankedCandidate[];
  unmet_quotas: string[];
  announcement: string | null;
  concerns: string | null;
  confidence: string | null;
  /// True when club policy had it published immediately.
  published: boolean;
};

export const STATE_LABEL: Record<SelectionState, string> = {
  pool: "In the pool",
  selected: "Picked",
  reserve: "Reserve",
  not_selected: "Left out",
  confirmed: "Confirmed",
  declined: "Declined",
  dropped: "Dropped",
};

export const RSVP_LABEL: Record<RsvpStatus, string> = {
  going: "Said yes",
  not_going: "Said no",
  maybe: "Maybe",
  invited: "Not answered",
};

export const AVAILABILITY_LABEL: Record<AvailabilityStatus, string> = {
  available: "Free that day",
  maybe: "Might be free",
  unavailable: "Busy that day",
};

/// In the XI or on the bench — everyone the captain has committed to.
export function inSquad(state: SelectionState): boolean {
  return state === "selected" || state === "reserve" || state === "confirmed";
}

/// The order a captain reads the pool in: who said yes first, then who is
/// probably free, then everybody else — and within each, whoever has been left
/// out most often. Somebody available every week and never picked is the thing
/// a captain most needs pushed under their nose.
export function pickingOrder(a: Candidate, b: Candidate): number {
  const rank = (c: Candidate) =>
    c.rsvp === "going" ? 0
    : c.availability === "available" ? 1
    : c.rsvp === "maybe" || c.availability === "maybe" ? 2
    : c.rsvp === "not_going" || c.availability === "unavailable" ? 4
    : 3;
  const byRank = rank(a) - rank(b);
  if (byRank !== 0) return byRank;
  const byMissed = b.games_missed_out - a.games_missed_out;
  if (byMissed !== 0) return byMissed;
  return b.reliability_score - a.reliability_score;
}
