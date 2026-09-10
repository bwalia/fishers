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
  withdrawn: boolean;
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
