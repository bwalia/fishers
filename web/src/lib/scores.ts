/// Scores from the wider game — internationals and domestic competitions.
///
/// Nothing here talks to the score provider. The API reads that on a budget of
/// a hundred requests a day for the whole deployment and serves everyone from
/// its own database, so this is an ordinary endpoint like any other and the
/// number of people watching costs nothing.

import { api } from "./api";

export type WorldMatch = {
  id: string;
  league_name: string;
  league_season?: number | null;
  home_team_name: string;
  home_team_short?: string | null;
  home_team_logo?: string | null;
  away_team_name: string;
  away_team_short?: string | null;
  away_team_logo?: string | null;
  country_code?: string | null;
  country_name?: string | null;
  /// `T20`, `ODI` or `TEST`.
  format?: string | null;
  /// `SINGLE` or `MULTI`.
  day_type?: string | null;
  start_time?: string | null;
  start_date: string;
  end_date?: string | null;
  /// The feed's own words: "In play", "Tea", "Stumps", "Finished".
  state: string;
  /// "live", "pending" or "done" — decided by the API so that web, iOS and
  /// Android cannot disagree about what counts as being played.
  phase: string;
  report?: string | null;
  /// Strings rather than numbers: a Test innings reads "128 & 59/5".
  home_score?: string | null;
  home_info?: string | null;
  away_score?: string | null;
  away_info?: string | null;
};

export type WorldScores = {
  /// False where no feed is configured. The section is hidden rather than
  /// shown empty — an empty panel reads as breakage.
  enabled: boolean;
  /// When the feed was last read. Shown, because on the free allowance this is
  /// minutes rather than seconds old, and a score that is quietly stale is
  /// worse than one that admits its age.
  as_of?: string | null;
  live: WorldMatch[];
  upcoming: WorldMatch[];
  recent: WorldMatch[];
};

export const worldScores = () => api<WorldScores>("GET", "/cricket/world-scores");

/// "T20", "ODI", "Test" — the feed shouts TEST and a scorecard should not.
export const formatLabel = (format?: string | null) => {
  if (!format) return null;
  return format.toUpperCase() === "TEST" ? "Test" : format.toUpperCase();
};

/// When it starts, in the reader's own timezone: "16:00" today, "Tue 16:00"
/// otherwise. A fixture list in UTC is a fixture list nobody can use.
export const startLabel = (iso?: string | null) => {
  if (!iso) return null;
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return null;
  const today = new Date().toDateString() === at.toDateString();
  return at.toLocaleString("en-GB", {
    weekday: today ? undefined : "short",
    hour: "2-digit",
    minute: "2-digit",
  });
};

/// How old the scores are, said plainly. Anything under a minute is "just
/// now" rather than "0 minutes ago", which reads like a bug.
export const freshness = (iso?: string | null) => {
  if (!iso) return "not loaded yet";
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (!Number.isFinite(mins) || mins < 0) return "just now";
  if (mins < 1) return "just now";
  if (mins === 1) return "1 minute ago";
  if (mins < 60) return `${mins} minutes ago`;
  const hours = Math.round(mins / 60);
  return hours === 1 ? "1 hour ago" : `${hours} hours ago`;
};

/// One batter's line on the card.
export type BattingRow = {
  name: string;
  runs?: number | null;
  balls?: number | null;
  fours?: number | null;
  sixes?: number | null;
  strike_rate?: number | null;
  /// Composed by the API: "c Kotian b Mulani", "not out", "did not bat".
  /// The conventions are fiddly enough that three clients would get them three
  /// different kinds of wrong.
  how_out: string;
  not_out: boolean;
};

export type BowlingRow = {
  name: string;
  overs?: number | null;
  maidens?: number | null;
  runs?: number | null;
  wickets?: number | null;
  economy?: number | null;
};

export type FallOfWicket = {
  /// Already counted from one; the feed counts from zero.
  wicket: number;
  runs?: number | null;
  overs?: number | null;
  batter?: string | null;
};

export type Extras = {
  total?: number | null;
  byes?: number | null;
  leg_byes?: number | null;
  wides?: number | null;
  no_balls?: number | null;
};

export type Innings = {
  team_name: string;
  /// "AUS-A" — what a tab is labelled with. "Australia A 1st Innings" does not
  /// fit across a phone four times.
  team_short?: string | null;
  team_logo?: string | null;
  /// Computed by the API: runs off the bat plus extras, which is cricket's own
  /// identity for a total.
  total_runs?: number | null;
  wickets?: number | null;
  batting: BattingRow[];
  bowling: BowlingRow[];
  fall_of_wickets: FallOfWicket[];
  extras: Extras;
};

/// Somebody at the crease or bowling right now. `line` is composed server-side
/// — "101 (153b, 7x4, 3x6)" for a batter, "1/19 (11.6 ov)" for a bowler.
export type CurrentPlayer = { name: string; team_name?: string | null; line: string };

export type WorldMatchDetail = {
  venue?: string | null;
  batting_now: CurrentPlayer[];
  bowling_now: CurrentPlayer[];
  innings: Innings[];
};

export type WorldMatchDetailView = {
  summary: WorldMatch;
  /// Absent when no scorecard has been fetched for this match — the page shows
  /// the summary and says so rather than rendering empty tables.
  detail?: WorldMatchDetail | null;
  detail_as_of?: string | null;
};

/// One match in full.
///
/// Costs the server a request *per match* rather than one for all of them, so
/// it is guarded: a finished card is fetched once and never again, and several
/// people opening the same match at once cost one request between them.
export const worldMatch = (id: string) =>
  api<WorldMatchDetailView>("GET", `/cricket/world-scores/${id}`);

/// "Maiwand Champions · 2nd innings" — the heading over the open card.
///
/// The tab is abbreviated because four of them have to fit across a phone; the
/// heading has the room, so it says the name in full.
export const inningsTitle = (innings: Innings[], at: number) => {
  const inn = innings[at];
  const nth = innings.slice(0, at + 1).filter((i) => i.team_name === inn.team_name).length;
  const twice = innings.filter((i) => i.team_name === inn.team_name).length > 1;
  if (!twice) return inn.team_name;
  const ordinal = nth === 1 ? "1st" : nth === 2 ? "2nd" : nth === 3 ? "3rd" : `${nth}th`;
  return `${inn.team_name} · ${ordinal} innings`;
};

/// "AUS-A 1st Innings" — a tab's label.
///
/// A Test has four innings and two of them belong to each side, so the team
/// name alone will not tell them apart.
export const inningsLabel = (innings: Innings[], at: number) => {
  const inn = innings[at];
  const name = inn.team_short || inn.team_name;
  const nth = innings.slice(0, at + 1).filter((i) => i.team_name === inn.team_name).length;
  const twice = innings.filter((i) => i.team_name === inn.team_name).length > 1;
  return twice ? `${name} ${nth === 1 ? "1st" : nth === 2 ? "2nd" : `${nth}th`}` : name;
};

/// "282-7", or "282" where nobody is out yet.
export const inningsScore = (inn: Innings) =>
  inn.total_runs == null ? null : inn.wickets ? `${inn.total_runs}-${inn.wickets}` : `${inn.total_runs}`;

/// A side's score as cricket writes it across a whole match: "103 & 99/6".
///
/// An innings that is all out shows just the runs; one still going shows the
/// wickets too. Derived from the card rather than taken from the summary
/// because the two are fetched separately — the summary comes from the list
/// poll, which can be a quarter of an hour behind the card somebody has just
/// opened. Two different numbers for the same thing on one screen reads as a
/// bug, and the card is the fresher of the two.
export const sideScore = (innings: Innings[], teamName: string): string | null => {
  const mine = innings.filter((i) => i.team_name === teamName && i.total_runs != null);
  if (mine.length === 0) return null;
  return mine
    .map((i) => ((i.wickets ?? 0) >= 10 ? `${i.total_runs}` : `${i.total_runs}/${i.wickets ?? 0}`))
    .join(" & ");
};
