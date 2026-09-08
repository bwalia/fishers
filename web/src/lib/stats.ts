/// Season stats as the API serves them (`backend/domain/src/stats.rs`).
/// `PlayerSeasonStatsView` flattens `PlayerSeasonStats`, so the fields sit at
/// the top level alongside the derived averages.

export type PlayerSeasonStats = {
  id: string;
  user_id: string;
  club_id?: string | null;
  season_year: number;
  sport: string;
  source: string;
  matches: number;
  runs: number;
  wickets: number;
  batting_innings: number;
  not_outs: number;
  balls_faced: number;
  fours: number;
  sixes: number;
  high_score?: number | null;
  overs_bowled: number;
  bowling_runs: number;
  maidens: number;
  catches: number;
  stumpings: number;
  player_name?: string | null;
  club_name?: string | null;
  play_cricket_profile_url?: string | null;
  batting_average?: number | null;
  bowling_average?: number | null;
  strike_rate?: number | null;
};

export type ClubSeasonStats = {
  club_id: string;
  season_year: number;
  source: string;
  matches_played: number;
  wins: number;
  losses: number;
  draws: number;
  no_results: number;
  runs_for: number;
  runs_against: number;
  wickets_taken: number;
  wickets_lost: number;
};

export type ClubSeasonBoard = {
  club: ClubSeasonStats;
  play_cricket?: { site_url?: string | null; name?: string | null } | null;
  top_batters: PlayerSeasonStats[];
  top_bowlers: PlayerSeasonStats[];
};

export type Achievement = {
  id: string;
  title: string;
  description?: string | null;
  icon?: string | null;
  awarded_at?: string | null;
};

export type MeStats = {
  links: unknown[];
  seasons: PlayerSeasonStats[];
  achievements: Achievement[];
};

/// Runs conceded per over. Not sent by the API — it is two of its fields.
export function economy(p: PlayerSeasonStats): number | null {
  if (!p.overs_bowled) return null;
  return p.bowling_runs / p.overs_bowled;
}

export function num(v: number | null | undefined, dp = 2): string {
  if (v === null || v === undefined || Number.isNaN(v)) return "—";
  return v.toFixed(dp);
}

/// Win percentage over completed games — draws and no-results excluded.
export function winRate(c: ClubSeasonStats): number | null {
  const decided = c.wins + c.losses;
  return decided ? (c.wins / decided) * 100 : null;
}
