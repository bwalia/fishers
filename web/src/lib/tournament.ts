/// Running a tournament (`backend/domain/src/tournament.rs`).
///
/// The order an organiser actually works in, which is the order the screen
/// puts it in: enter the sides, lay out the pitches and times, generate the
/// fixtures into that grid, then read the table as results come in.

export type FixtureBlock = {
  id: string;
  club_id: string;
  team_id: string | null;
  name: string;
  /// `block` | `tour` | `tournament` | `season`
  kind: string;
  starts_on: string | null;
  ends_on: string | null;
  created_at: string;
};

/// Where a side is in the entry process.
///
/// A name an organiser typed in is `accepted` straight away — they are
/// entering it, not asking it. `invited` belongs to a real club that answers
/// for itself, and only `accepted` sides go into the draw.
export type EntryStatus = "invited" | "accepted" | "declined" | "withdrawn";

export type TournamentEntrant = {
  id: string;
  block_id: string;
  name: string;
  club_id: string | null;
  team_id: string | null;
  seed: number | null;
  group_label: string | null;
  contact_name: string | null;
  contact_email: string | null;
  status: EntryStatus;
  invited_by: string | null;
  responded_at: string | null;
  /// Derived from `status` by the database. Kept because several screens read it.
  withdrawn: boolean;
};

/// A tournament somebody has asked your club into.
export type EntryInvitation = {
  entrant_id: string;
  block_id: string;
  block_name: string;
  kind: string;
  starts_on: string | null;
  ends_on: string | null;
  host_club_id: string;
  host_club_name: string;
  entrant_name: string;
  club_id: string | null;
  status: EntryStatus;
  invited_by_name: string | null;
  created_at: string;
};

export const ENTRY_LABEL: Record<EntryStatus, string> = {
  invited: "Asked",
  accepted: "In",
  declined: "Declined",
  withdrawn: "Withdrawn",
};

export type TournamentFormat = "round_robin" | "groups_knockout" | "knockout" | "ladder" | "none";

export type Slot = {
  id: string;
  court_label: string;
  starts_at: string;
  ends_at: string;
};

export type GeneratedFixture = {
  home: string | null;
  away: string | null;
  round: number;
  group_label: string | null;
  /// `group` | `knockout`
  stage: string;
};

/// What the generator produced. A preview until `commit` is sent.
export type SchedulePreview = {
  format: string;
  committed: number;
  scheduled: { fixture: GeneratedFixture; slot: Slot }[];
  /// Fixtures the grid could not fit — the organiser needs to be told, not
  /// left to count.
  unscheduled: GeneratedFixture[];
  byes: GeneratedFixture[];
  needs_more_slots: number;
};

export type ScheduleRow = {
  event_id: string;
  title: string;
  starts_at: string;
  court_label: string | null;
  stage: string | null;
  round: number | null;
  group_label: string | null;
  home_name: string | null;
  away_name: string | null;
  home_score: number | null;
  away_score: number | null;
  home_result: string | null;
  status: string;
};

export type Standing = {
  entrant_id: string;
  name: string;
  group_label: string | null;
  played: number;
  won: number;
  lost: number;
  drawn: number;
  no_result: number;
  points: number;
  scored: number;
  conceded: number;
};

/// One line per side. Draws and no-results exist because rain does.
export type EntrantResult = {
  entrant_id: string;
  score: number | null;
  /// `win` | `loss` | `draw` | `no_result`
  result: string;
  score_detail?: Record<string, unknown> | null;
};

/// A ticketed club event — a dinner, a quiz, a presentation night.
export type EventTicket = {
  id: string;
  event_id: string;
  user_id: string;
  name: string | null;
  guests: number;
  guest_names: string | null;
  amount_cents: number;
  currency: string;
  /// `reserved` | `paid` | `cancelled`
  status: string;
  notes: string | null;
  created_at: string;
};

export type TicketSummary = {
  event_id: string;
  title: string;
  ticket_capacity: number | null;
  ticket_price_cents: number | null;
  /// How many guests one member may bring. Zero means members only.
  guests_allowed: number;
  /// Anyone signed in may buy, rather than members of the hosting club only.
  tickets_public: boolean;
  bookings: number;
  headcount: number;
  collected_cents: number;
  outstanding_cents: number;
};

export type TicketBooking = {
  summary: TicketSummary;
  tickets: EventTicket[];
  /// False for a non-member at a public event: they get the headcount and
  /// their own booking, never the guest list.
  can_see_everyone: boolean;
};

export const FORMAT_LABEL: Record<TournamentFormat, string> = {
  round_robin: "Everyone plays everyone",
  groups_knockout: "Groups, then a knockout",
  knockout: "Straight knockout",
  ladder: "Ladder",
  none: "No structure",
};

/// Points, then difference, then scored, then name — the same order the server
/// sorts by, so a table never disagrees with itself between two screens.
export function tableOrder(a: Standing, b: Standing): number {
  return (
    b.points - a.points ||
    difference(b) - difference(a) ||
    b.scored - a.scored ||
    a.name.localeCompare(b.name)
  );
}

export function difference(s: Standing): number {
  return s.scored - s.conceded;
}

/// Groups a table into its groups, or one unnamed group when there are none.
export function byGroup(rows: Standing[]): { label: string | null; rows: Standing[] }[] {
  const groups = new Map<string | null, Standing[]>();
  for (const row of rows) {
    const key = row.group_label ?? null;
    groups.set(key, [...(groups.get(key) ?? []), row]);
  }
  return [...groups.entries()]
    .sort((a, b) => (a[0] ?? "").localeCompare(b[0] ?? ""))
    .map(([label, rows]) => ({ label, rows: [...rows].sort(tableOrder) }));
}
