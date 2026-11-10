/// A player's season, match by match, as `/me/game` and `/users/{id}/game`
/// return it, and a club's season from `/clubs/{id}/season`. The arithmetic
/// is the API's (`backend/domain/src/season.rs`); this is the shape and the
/// words.

import type { AnyKey, T } from "@/lib/i18n";

export type Figures = { wickets: number; runs: number };

export type Totals = {
  matches: number;
  won: number;
  batting_innings: number;
  not_outs: number;
  runs: number;
  balls_faced: number;
  fours: number;
  sixes: number;
  high_score: number | null;
  high_score_not_out: boolean;
  fifties: number;
  hundreds: number;
  ducks: number;
  double_figures: number;
  batting_average: number | null;
  strike_rate: number | null;
  bowling_balls: number;
  overs: string;
  bowling_runs: number;
  wickets: number;
  maidens: number;
  economy: number | null;
  bowling_average: number | null;
  bowling_strike_rate: number | null;
  best_bowling: Figures | null;
  catches: number;
  stumpings: number;
  player_of_match: number;
};

export type FormEntry = {
  match_id: string;
  event_id: string;
  played_at: string;
  opposition: string;
  won: boolean | null;
  batted: boolean;
  runs: number;
  balls: number;
  not_out: boolean;
  bowled: boolean;
  wickets: number;
  runs_conceded: number;
  overs: string;
  catches: number;
  player_of_match: boolean;
};

export type Trend = "rising" | "steady" | "quieter";

export type Form = {
  matches: FormEntry[];
  recent_batting_average: number | null;
  batting_trend: Trend | null;
  recent_wickets_per_match: number | null;
  bowling_trend: Trend | null;
};

export type Best = {
  code: string;
  value: string;
  opposition: string | null;
  played_at: string | null;
  season_year: number | null;
  this_season: boolean;
};

export type Milestone = {
  code: string;
  reached_at: string;
  opposition: string;
  this_season: boolean;
};

export type ClubRank = {
  club_id: string;
  club_name: string;
  runs: number | null;
  wickets: number | null;
  catches: number | null;
  players: number;
};

export type Highlight = {
  code: string;
  text: string;
  value?: string;
  detail?: string;
};

export type PlayerGame = {
  user_id: string;
  name: string;
  season: number;
  seasons: number[];
  totals: Totals;
  previous: Totals | null;
  career: Totals;
  form: Form;
  bests: Best[];
  milestones: Milestone[];
  club_rank: ClubRank | null;
  highlights: Highlight[];
};

export type Leader = { user_id: string; name: string; value: string; detail: string | null };
export type Leaderboard = { code: string; leaders: Leader[] };

export type ClubSeason = {
  club_id: string;
  club_name: string;
  season: number;
  closed_at: string | null;
  seasons: number[];
  record: { played: number; won: number; lost: number; tied_or_no_result: number };
  players: number;
  boards: Leaderboard[];
};

export type ClosePreview = {
  season: number;
  closed_at: string | null;
  members: number;
  will_email: number;
  played: number;
  /// False when this server cannot send mail: nobody is emailed until it can.
  email_on?: boolean;
};

export function fmt(v: number | null | undefined, dp = 1): string {
  return v === null || v === undefined ? "–" : v.toFixed(dp);
}

export function score(runs: number | null, notOut: boolean): string {
  return runs === null ? "–" : `${runs}${notOut ? "*" : ""}`;
}

/// "Top", "Second", "Third", then "No. 7" — ordinals do not pluralise, so
/// they are words for the three that matter and a number after that.
export function place(t: T, n: number): string {
  if (n === 1) return t("ss.place.1");
  if (n === 2) return t("ss.place.2");
  if (n === 3) return t("ss.place.3");
  return t("ss.place.n", { n });
}

/// A milestone code as words: "first_fifty", "runs_250".
export function milestoneLabel(t: T, code: string): string {
  const m = /^(matches|runs|wickets)_(\d+)$/.exec(code);
  if (m) {
    const key = { matches: "ss.ms.matches", runs: "ss.ms.runs", wickets: "ss.ms.wickets" }[
      m[1] as "matches" | "runs" | "wickets"
    ] as AnyKey;
    return t(key, { n: m[2] });
  }
  const key = MILESTONES[code];
  return key ? t(key) : code.replaceAll("_", " ");
}

const MILESTONES: Record<string, AnyKey> = {
  first_match: "ss.ms.first_match",
  first_six: "ss.ms.first_six",
  first_fifty: "ss.ms.first_fifty",
  first_hundred: "ss.ms.first_hundred",
  first_wicket: "ss.ms.first_wicket",
  first_three_wickets: "ss.ms.first_three_wickets",
  first_five_wickets: "ss.ms.first_five_wickets",
  first_catch: "ss.ms.first_catch",
  first_player_of_match: "ss.ms.first_player_of_match",
  first_win: "ss.ms.first_win",
};

/// A highlight in the reader's language, from its code. The API's English
/// is the fallback for a code this build does not know yet.
export function highlightText(t: T, h: Highlight): string {
  const v = h.value ?? "";
  const d = h.detail ?? "";
  const n = Number(v);
  switch (h.code) {
    case "new_best_score":
      return d ? t("ss.hl.new_best_score", { value: v, opposition: d }) : h.text;
    case "season_best_score":
      return d ? t("ss.hl.season_best_score", { value: v, opposition: d }) : h.text;
    case "new_best_bowling":
      return d ? t("ss.hl.new_best_bowling", { value: v, opposition: d }) : h.text;
    case "season_best_bowling":
      return d ? t("ss.hl.season_best_bowling", { value: v, opposition: d }) : h.text;
    case "milestone":
      return t("ss.hl.milestone", { label: milestoneLabel(t, d) });
    case "average_up":
      return t("ss.hl.average_up", { value: v });
    case "strike_rate_up":
      return t("ss.hl.strike_rate_up", { value: v });
    case "economy_down":
      return t("ss.hl.economy_down", { value: v });
    case "more_runs":
      return t("ss.hl.more_runs", { value: v, before: d });
    case "more_wickets":
      return t("ss.hl.more_wickets", { value: v, before: d });
    case "club_top_runs":
      return t("ss.hl.club_top_runs", { place: place(t, n), club: d });
    case "club_top_wickets":
      return t("ss.hl.club_top_wickets", { place: place(t, n), club: d });
    case "consistent":
      return t("ss.hl.consistent", { value: v, of: d });
    case "player_of_match":
      return t("ss.hl.player_of_match", { count: n, n });
    case "safe_hands":
      return t("ss.hl.safe_hands", { value: v });
    case "winning_side":
      return t("ss.hl.winning_side", { value: v, of: d });
    case "turned_up":
      return t("ss.hl.turned_up", { count: n, n });
    default:
      return h.text;
  }
}

export const BEST_LABELS: Record<string, AnyKey> = {
  best_score: "ss.best.best_score",
  best_bowling: "ss.best.best_bowling",
  most_sixes: "ss.best.most_sixes",
  most_catches: "ss.best.most_catches",
  best_season_runs: "ss.best.best_season_runs",
  best_season_wickets: "ss.best.best_season_wickets",
};

export const BOARD_LABELS: Record<string, AnyKey> = {
  runs: "ss.board.runs",
  wickets: "ss.board.wickets",
  batting_average: "ss.board.batting_average",
  strike_rate: "ss.board.strike_rate",
  economy: "ss.board.economy",
  best_innings: "ss.board.best_innings",
  best_bowling: "ss.board.best_bowling",
  catches: "ss.board.catches",
  sixes: "ss.board.sixes",
  player_of_match: "ss.board.player_of_match",
};

export function shortDate(iso: string, locale?: string): string {
  return new Date(iso).toLocaleDateString(locale, { day: "numeric", month: "short" });
}
