/// Running a tournament (`backend/domain/src/tournament.rs`).
///
/// The order an organiser actually works in, which is the order the screen
/// puts it in: enter the sides, lay out the pitches and times, generate the
/// fixtures into that grid, then read the table as results come in.

/// Overs, ball and fielding restrictions — the same terms two captains agree
/// before a one-off match (`backend/domain/src/cricket/types.rs`). A tournament
/// sets them once and every fixture in it inherits the answer.
export type MatchConditions = {
  overs_limit: number;
  overs_per_bowler: number;
  /// `open` | `boxed` | `indoor`
  ground: string;
  /// `red` | `white` | `pink` | `tennis` | `tape`
  ball: string;
  powerplay_overs: number;
  fielders_outside_powerplay: number;
  fielders_outside_normal: number;
  fielders_behind_square_leg: number;
  target_overs_per_hour: number;
};

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

  // What a tournament settles before anybody enters.
  description: string | null;
  venue_id: string | null;
  /// How many sides fit. Null is no limit.
  max_entrants: number | null;
  entry_deadline: string | null;
  /// What a side pays to enter — not a spectator's ticket.
  entry_fee_cents: number | null;
  players_per_side: number;
  /// 0 means every player must belong to the entering club.
  guest_players_allowed: number;
  age_group: string;
  gender: string;
  conditions: MatchConditions | null;
  rules_notes: string | null;
};

/// Everything an organiser can change after the tournament exists. Every field
/// optional and applied only when sent, so editing the entry rules cannot wipe
/// the playing conditions.
export type TournamentSettings = Partial<{
  description: string | null;
  venue_id: string | null;
  max_entrants: number | null;
  entry_deadline: string | null;
  entry_fee_cents: number | null;
  players_per_side: number;
  guest_players_allowed: number;
  age_group: string;
  gender: string;
  conditions: MatchConditions;
  rules_notes: string | null;
  /// Settings to unset, by name. A missing field and a null field look the
  /// same over JSON, and every field here means "leave it alone if not sent" —
  /// so removing a cap has to be said out loud.
  clear: string[];
}>;

export const AGE_GROUPS = ["open", "u11", "u13", "u15", "u17", "u19", "veterans"] as const;
export const GENDERS = ["open", "men", "women", "mixed"] as const;
export const BALLS = ["red", "white", "pink", "tennis", "tape"] as const;
export const GROUNDS = ["open", "boxed", "indoor"] as const;

export const AGE_LABEL: Record<string, string> = {
  open: "Open age",
  u11: "Under 11", u13: "Under 13", u15: "Under 15", u17: "Under 17", u19: "Under 19",
  veterans: "Veterans",
};
export const GENDER_LABEL: Record<string, string> = {
  open: "Open", men: "Men", women: "Women", mixed: "Mixed",
};
export const BALL_LABEL: Record<string, string> = {
  red: "Red leather", white: "White leather", pink: "Pink leather",
  tennis: "Tennis", tape: "Taped tennis",
};
export const GROUND_LABEL: Record<string, string> = {
  open: "Open ground", boxed: "Caged / boxed", indoor: "Indoor",
};

/// The usual allocation: a fifth of the innings each, rounded up — twenty overs
/// gives four, fifty gives ten. The same rule as `MatchConditions::standard`.
export function standardOversPerBowler(overs: number): number {
  return Math.max(1, Math.ceil(overs / 5));
}

export function defaultConditions(overs = 20): MatchConditions {
  return {
    overs_limit: overs,
    overs_per_bowler: standardOversPerBowler(overs),
    ground: "open",
    ball: "white",
    powerplay_overs: 0,
    fielders_outside_powerplay: 2,
    fielders_outside_normal: 5,
    fielders_behind_square_leg: 2,
    target_overs_per_hour: 0,
  };
}

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
