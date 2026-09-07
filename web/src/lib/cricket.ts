/// Cricket types and helpers shared by the public scoreboard and the scorer.
///
/// The engine lives in the API (`backend/domain/src/cricket`). Nothing here
/// decides anything about a game — the browser posts events and renders the
/// state the server replies with, so the web can never disagree with the app.

export type Shot = {
  angle: number;
  kind: string;
  reach: number;
};

export type Delivery = {
  over: number;
  ball_in_over: number;
  label: string;
  runs: number;
  is_legal: boolean;
  is_wicket: boolean;
  batter_id?: string | null;
  bowler_id?: string | null;
  shot?: Shot | null;
};

export type Batter = {
  player_id: string;
  runs: number;
  balls: number;
  fours: number;
  sixes: number;
  out: boolean;
};

export type Bowler = {
  player_id: string;
  balls: number;
  runs: number;
  wickets: number;
  maidens: number;
};

export type Innings = {
  index: number;
  batting: string;
  bowling?: string;
  runs: number;
  wickets: number;
  legal_balls: number;
  extras: number;
  complete: boolean;
  striker_id?: string | null;
  non_striker_id?: string | null;
  bowler_id?: string | null;
  batters: Batter[];
  bowlers: Bowler[];
  super_over?: boolean;
  powerplay_overs?: number;
  free_hit?: boolean;
  deliveries?: Delivery[];
  fielders_outside?: number;
  fielders_behind_square_leg?: number;
  wides?: number;
  no_balls?: number;
  byes?: number;
  leg_byes?: number;
  penalties?: number;
  overs_available?: number;
  balls_in_current_over?: number;
  last_over_bowler?: string | null;
};

export type MatchConditions = {
  overs_limit: number;
  overs_per_bowler: number;
  ground: string;
  ball: string;
  powerplay_overs: number;
  fielders_outside_powerplay: number;
  fielders_outside_normal: number;
  fielders_behind_square_leg: number;
  target_overs_per_hour: number;
};

export type MatchPlayer = {
  id: string;
  name: string;
  bats_left: boolean;
};

export type MatchState = {
  status: string;
  overs_limit: number;
  home_name: string;
  away_name: string;
  toss_winner?: string | null;
  toss_decision?: string | null;
  home_xi: string[];
  away_xi: string[];
  home_captain?: string | null;
  away_captain?: string | null;
  home_keeper?: string | null;
  away_keeper?: string | null;
  innings: Innings[];
  target?: number | null;
  winner?: string | null;
  margin?: string | null;
  last_seq: number;
  player_names: Record<string, string>;
  left_handers?: string[];
  conditions?: MatchConditions;
  conditions_proposed_by?: string | null;
  /// The captain's name once they have agreed, not a flag.
  agreed_home?: string | null;
  agreed_away?: string | null;
  officials?: { umpires: MatchPlayer[]; scorers: MatchPlayer[] };
  player_of_the_match?: string | null;
  super_overs?: number;
};

/// What `GET/POST /cricket/matches/{id}` replies with.
export type MatchResponse = {
  id: string;
  event_id: string;
  club_id: string;
  status: string;
  overs_limit: number;
  home_name: string;
  away_name: string;
  last_seq: number;
  active_scorer_user_id?: string | null;
  active_scorer_device_id?: string | null;
  can_score: boolean;
  dls?: { par: number; ahead_by: number; target: number; method: string };
  state: MatchState;
};

export const GROUNDS = ["open", "boxed", "indoor"] as const;
export const BALLS = ["red", "white", "pink", "tennis", "tape"] as const;
export const EXTRA_KINDS = ["wide", "no_ball", "bye", "leg_bye"] as const;

export const SHOT_KINDS = [
  "drive", "cut", "pull", "hook", "sweep", "reverse_sweep", "glance",
  "flick", "loft", "defence", "edge", "leave", "other",
] as const;

export const DISMISSALS = [
  "bowled", "caught", "lbw", "run_out", "stumped", "hit_wicket",
  "retired", "retired_hurt", "other",
] as const;

/// Dismissals where somebody other than the bowler did the work.
export const DISMISSALS_WITH_FIELDER = ["caught", "run_out", "stumped"];

export const DEFAULT_CONDITIONS: MatchConditions = {
  overs_limit: 20,
  overs_per_bowler: 4,
  ground: "open",
  ball: "white",
  powerplay_overs: 6,
  fielders_outside_powerplay: 2,
  fielders_outside_normal: 5,
  fielders_behind_square_leg: 2,
  target_overs_per_hour: 14,
};

export function titleCase(s: string) {
  return s.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
}

export function overs(balls: number) {
  return `${Math.floor(balls / 6)}.${balls % 6}`;
}

/// The eight sectors of a wagon wheel, mirrored for a left-hander — the same
/// function the app and the API use.
export function regionFor(angle: number, batsLeft: boolean) {
  const raw = ((angle % 360) + 360) % 360;
  const a = batsLeft ? (360 - raw) % 360 : raw;
  if (a <= 44) return "long on";
  if (a <= 89) return "mid-wicket";
  if (a <= 134) return "square leg";
  if (a <= 179) return "fine leg";
  if (a <= 224) return "third man";
  if (a <= 269) return "point";
  if (a <= 314) return "cover";
  return "long off";
}

export const SHOT_VERBS: Record<string, string> = {
  drive: "driven",
  cut: "cut",
  pull: "pulled",
  hook: "hooked",
  sweep: "swept",
  reverse_sweep: "reverse-swept",
  glance: "glanced",
  flick: "flicked",
  loft: "lofted",
  defence: "defended",
  edge: "edged",
  leave: "left alone",
  other: "worked away",
};

export function outcomeOf(ball: Delivery) {
  if (ball.is_wicket) return ball.runs > 0 ? `OUT (${ball.runs} run)` : "OUT";
  if (!ball.is_legal) {
    if (ball.label.startsWith("wd")) return ball.runs > 1 ? `wide, ${ball.runs} runs` : "wide";
    if (ball.label.startsWith("nb")) return ball.runs > 1 ? `no ball, ${ball.runs} runs` : "no ball";
    if (ball.label.endsWith("p")) return `${ball.runs} penalty runs`;
    return ball.label;
  }
  if (ball.label.endsWith("lb")) return `${ball.runs} leg byes`;
  if (ball.label.endsWith("b")) return `${ball.runs} byes`;
  if (ball.runs === 0) return "no run";
  if (ball.runs === 4) return "FOUR";
  if (ball.runs === 6) return "SIX";
  return `${ball.runs} run${ball.runs === 1 ? "" : "s"}`;
}

/// The same line the app writes, generated from the same log.
export function commentaryFor(
  ball: Delivery,
  nameOf: (id?: string | null) => string,
  leftHanders: string[] = []
) {
  const bowler = ball.bowler_id ? nameOf(ball.bowler_id) : null;
  const batter = ball.batter_id ? nameOf(ball.batter_id) : null;
  const parts: string[] = [];
  if (bowler && batter) parts.push(`${bowler} to ${batter},`);
  else if (batter) parts.push(`${batter},`);
  parts.push(outcomeOf(ball));
  if (ball.shot) {
    const left = leftHanders.includes((ball.batter_id || "").toLowerCase());
    const region = regionFor(ball.shot.angle, left);
    const verb = SHOT_VERBS[ball.shot.kind] || "played";
    if (ball.shot.kind === "leave" || ball.shot.kind === "defence") {
      parts.push(`— ${verb}`);
    } else {
      const preposition =
        region === "long on" || region === "long off"
          ? "down the ground to"
          : region === "fine leg" || region === "third man"
            ? "down to"
            : "through";
      parts.push(`— ${verb} ${preposition} ${region}`);
    }
  }
  return parts.join(" ");
}


/// Runs per over so far. Null before a ball is bowled.
export function runRate(runs: number, legalBalls: number): number | null {
  if (!legalBalls) return null;
  return (runs * 6) / legalBalls;
}

/// What the chase now needs per over, or null when there is nothing to chase
/// or no balls left to chase it in.
export function requiredRate(
  target: number | null | undefined,
  runs: number,
  legalBalls: number,
  oversAvailable: number
): number | null {
  if (target == null) return null;
  const ballsLeft = oversAvailable * 6 - legalBalls;
  if (ballsLeft <= 0) return null;
  return ((target - runs) * 6) / ballsLeft;
}
