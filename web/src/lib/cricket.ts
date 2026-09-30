/// Cricket types and helpers shared by the public scoreboard and the scorer.
///
/// The engine lives in the API (`backend/domain/src/cricket`). Nothing here
/// decides anything about a game — the browser posts events and renders the
/// state the server replies with, so the web can never disagree with the app.
///
/// Anything that produces words takes a `t`. It is required rather than
/// defaulted to English: a default is a silent way to ship an English
/// scorecard inside a Punjabi page, and making it required turns the compiler
/// into the list of places still to do.

import type { Key } from "@/lib/i18n/en";
import type { T } from "@/lib/i18n";

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
  dismissal?: string | null;
  retired_hurt?: boolean;
  /// Who bowled the dismissal, for "c Smith b Jones".
  bowler_id?: string | null;
  fielder_id?: string | null;
};

export type FallOfWicket = {
  score: number;
  wickets: number;
  batter_id: string;
  over_ball: string;
  partnership_runs: number;
  partnership_balls: number;
};

export type Bowler = {
  player_id: string;
  balls: number;
  runs: number;
  wickets: number;
  maidens: number;
  /// Wickets on consecutive deliveries. Two means the next legitimate ball is
  /// a hat-trick ball; three is the hat-trick. Counted by the engine, which is
  /// the only thing that knows whose wicket each one was.
  wickets_in_a_row?: number;
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
  /// Taken off for the rest of this innings under Law 41.
  suspended_bowlers?: string[];
  /// Law 15: the batting captain closed it. "350/4 dec", not "350 all out".
  declared?: boolean;
  /// Law 15.2: given up without being played.
  forfeited?: boolean;
  fall?: FallOfWicket[];
  partnership_runs?: number;
  partnership_balls?: number;
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
  /// Innings each side bats. One for limited-overs; two for a declaration
  /// game, which is won on aggregate and can be drawn.
  innings_per_side?: number;
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
  /// Called off with no result. `winner` is null either way, so this is what
  /// separates abandoned from a tie that still needs a super over.
  abandoned?: boolean;
  last_seq: number;
  player_names: Record<string, string>;
  left_handers?: string[];
  /// Fielding substitutes, by id. Named, but on no team sheet.
  substitutes?: string[];
  conditions?: MatchConditions;
  conditions_proposed_by?: string | null;
  /// The captain's name once they have agreed, not a flag.
  agreed_home?: string | null;
  agreed_away?: string | null;
  officials?: { umpires: MatchPlayer[]; scorers: MatchPlayer[] };
  player_of_the_match?: string | null;
  super_overs?: number;
};

export type Side = "home" | "away";

/// One player's match, weighed up. The server ranks these; the browser only
/// renders them in the order they arrive.
export type PlayerImpact = {
  player_id: string;
  name: string;
  side: Side;
  /// Higher is better. Runs-flavoured, but not runs — never show it as one.
  score: number;
  /// "75* (45) · 2-18 (4.0) · 1 ct" — why they are on the list.
  line: string;
};

/// What `GET/POST /cricket/matches/{id}` replies with.
export type MatchResponse = {
  id: string;
  event_id: string;
  club_id: string;
  /// The visiting club, when they are on Fishers — their captain comes from
  /// their roster, not ours.
  opponent_club_id?: string | null;
  status: string;
  overs_limit: number;
  home_name: string;
  away_name: string;
  last_seq: number;
  active_scorer_user_id?: string | null;
  active_scorer_device_id?: string | null;
  can_score: boolean;
  /// When the fixture is. Two clubs play each other several times a season, so
  /// the sides alone do not say which match you have opened.
  start_at?: string | null;
  /// The side this viewer actually plays for, when they are in one of the
  /// clubs. A scorer may act for both but belongs to one.
  my_club_side?: Side | null;
  /// The sides this viewer may propose or agree terms for. A scorer gets both;
  /// a captain on their own phone gets their own.
  my_sides: Side[];
  dls?: { par: number; ahead_by: number; target: number; method: string };
  /// Who had the biggest game, best first. Only sent once the match is over.
  awards?: PlayerImpact[];
  /// The best game in the losing side, when there was one worth naming.
  fighter?: PlayerImpact | null;
  /// Both sides totalled up, from the second innings on.
  insights?: MatchInsights | null;
  state: MatchState;
};

/// One stretch of an innings — powerplay, middle, death.
export type PhaseScore = {
  name: string;
  /// The overs it covers, as a scorer would say them: "1-6".
  overs: string;
  runs: number;
  wickets: number;
  balls: number;
};

/// One side's innings, totalled every way a post-match chat asks about.
export type SideInsights = {
  side: Side;
  name: string;
  runs: number;
  wickets: number;
  balls: number;
  overs: string;
  run_rate: number;
  dots: number;
  dot_percent: number;
  fours: number;
  sixes: number;
  boundary_runs: number;
  boundary_percent: number;
  extras: number;
  phases: PhaseScore[];
  top_order: number;
  middle_order: number;
  lower_order: number;
  best_partnership: number;
};

export type MatchInsights = { home: SideInsights; away: SideInsights };

export const GROUNDS = ["open", "boxed", "indoor"] as const;
export const BALLS = ["red", "white", "pink", "tennis", "tape"] as const;
export const EXTRA_KINDS = ["wide", "no_ball", "bye", "leg_bye"] as const;

export const SHOT_KINDS = [
  "drive", "cut", "pull", "hook", "sweep", "reverse_sweep", "glance",
  "flick", "loft", "defence", "edge", "leave", "other",
] as const;

export const DISMISSALS = [
  "bowled", "caught", "lbw", "run_out", "stumped", "hit_wicket",
  "retired", "retired_hurt",
  // The rarities the Laws still name, which used to go down as "other" and
  // print that way on the card.
  "obstructing_the_field", "hit_the_ball_twice", "timed_out",
  "other",
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
  innings_per_side: 1,
};

/// "182-4", or "350-4 dec" when the captain closed it. A declared innings is
/// not an all-out one and a scorebook has always drawn the distinction; a
/// forfeited one was never played at all.
export function inningsScore(i: Innings): string {
  if (i.forfeited) return "forfeited";
  return `${i.runs}-${i.wickets}${i.declared ? " dec" : ""}`;
}

export function titleCase(s: string) {
  return s.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
}

export function overs(balls: number) {
  return `${Math.floor(balls / 6)}.${balls % 6}`;
}

/// The eight sectors, in bearing order from straight down the ground. The
/// boundaries between them are the API's and the app's too, so this list and
/// the 45-degree steps below are one fact written once.
const REGION_KEYS = [
  "region.long_on",
  "region.mid_wicket",
  "region.square_leg",
  "region.fine_leg",
  "region.third_man",
  "region.point",
  "region.cover",
  "region.long_off",
] as const satisfies readonly Key[];

/// Which sector a bearing falls in, mirrored for a left-hander.
///
/// Returns the key rather than a name, so the caller decides what language to
/// say it in — and so the sector maths stays in one place instead of being
/// duplicated by anything that needs the untranslated form.
export function regionKeyFor(angle: number, batsLeft: boolean): Key {
  const raw = ((angle % 360) + 360) % 360;
  const a = batsLeft ? (360 - raw) % 360 : raw;
  // Eight equal 45-degree sectors; `min` catches a == 360 exactly.
  return REGION_KEYS[Math.min(7, Math.floor(a / 45))];
}

/// The sector's name, in the reader's language.
export function regionFor(angle: number, batsLeft: boolean, t: T): string {
  return t(regionKeyFor(angle, batsLeft));
}

/// The verb commentary uses for a stroke, in the reader's language.
export function shotVerb(kind: string, t: T): string {
  const key = `verb.${kind}` as Key;
  return t(key);
}

export function outcomeOf(ball: Delivery, t: T): string {
  if (ball.is_wicket) {
    return ball.runs > 0 ? t("outcome.out_with_runs", { runs: ball.runs }) : t("outcome.out");
  }
  if (!ball.is_legal) {
    if (ball.label.startsWith("wd")) {
      return ball.runs > 1 ? t("outcome.wide_runs", { runs: ball.runs }) : t("outcome.wide");
    }
    if (ball.label.startsWith("nb")) {
      return ball.runs > 1 ? t("outcome.no_ball_runs", { runs: ball.runs }) : t("outcome.no_ball");
    }
    if (ball.label.endsWith("p")) return t("outcome.penalty", { runs: ball.runs });
    // A label the engine wrote that nothing above recognised. Left as it
    // stands rather than guessed at — a scorer's own shorthand is better than
    // a wrong translation of it.
    return ball.label;
  }
  if (ball.label.endsWith("lb")) return t("outcome.leg_byes", { runs: ball.runs });
  if (ball.label.endsWith("b")) return t("outcome.byes", { runs: ball.runs });
  if (ball.runs === 0) return t("outcome.dot");
  if (ball.runs === 4) return t("outcome.four");
  if (ball.runs === 6) return t("outcome.six");
  return t("outcome.runs", { runs: ball.runs, count: ball.runs });
}

/// The same line the app writes, generated from the same log.
///
/// Built from pieces handed to a template per language rather than
/// concatenated here, because where the pieces go is a fact about the
/// language — see `ball.with_shot` in the dictionaries.
export function commentaryFor(
  ball: Delivery,
  nameOf: (id?: string | null) => string,
  leftHanders: string[] = [],
  t: T
): string {
  const bowler = ball.bowler_id ? nameOf(ball.bowler_id) : null;
  const batter = ball.batter_id ? nameOf(ball.batter_id) : null;
  const who =
    bowler && batter
      ? t("ball.bowler_to_batter", { bowler, batter })
      : batter
        ? t("ball.batter_only", { batter })
        : "";
  const outcome = outcomeOf(ball, t);

  if (!ball.shot) return t("ball.without_shot", { who, outcome }).trim();

  const left = leftHanders.includes((ball.batter_id || "").toLowerCase());
  const regionKey = regionKeyFor(ball.shot.angle, left);
  const region = t(regionKey);
  const verb = shotVerb(ball.shot.kind, t);

  // Which phrasing the stroke gets. Chosen from the *key*, not the
  // translated name, so it keeps working in every language — comparing
  // against "long on" would silently fall through to "through" the moment
  // the page was not in English.
  const phrase =
    ball.shot.kind === "leave" || ball.shot.kind === "defence"
      ? t("shot.phrase.plain", { verb, region })
      : regionKey === "region.long_on" || regionKey === "region.long_off"
        ? t("shot.phrase.down_ground", { verb, region })
        : regionKey === "region.fine_leg" || regionKey === "region.third_man"
          ? t("shot.phrase.down_to", { verb, region })
          : t("shot.phrase.through", { verb, region });

  return t("ball.with_shot", { who, outcome, shot: phrase }).trim();
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

/// "c Smith b Jones", "lbw b Jones", "not out" — read the way a scorebook reads.
///
/// The abbreviations stay Latin in every language: "c" and "b" are what a
/// scorebook prints worldwide, and a scorer reading a Punjabi page still
/// expects to recognise their own card.
export function howOut(
  b: Batter,
  nameOf: (id?: string | null) => string,
  substitutes: string[] = [],
  t: T
): string {
  if (!b.out) return b.retired_hurt ? t("out.retired_hurt") : t("out.not_out");
  const bowler = b.bowler_id ? nameOf(b.bowler_id) : null;
  // A substitute is named as one: "c sub (Patel) b Jones" is not the same
  // claim as "c Patel b Jones", and the card has always said so.
  const fielder = b.fielder_id
    ? substitutes.includes(b.fielder_id)
      ? `sub (${nameOf(b.fielder_id)})`
      : nameOf(b.fielder_id)
    : null;
  switch (b.dismissal) {
    case "bowled":
      return bowler ? `b ${bowler}` : t("out.bowled");
    case "caught":
      if (fielder && bowler) return fielder === bowler ? `c & b ${bowler}` : `c ${fielder} b ${bowler}`;
      return bowler ? `c & b ${bowler}` : t("out.caught");
    case "lbw":
      return bowler ? `lbw b ${bowler}` : t("out.lbw");
    case "run_out":
      return fielder ? `${t("out.run_out")} (${fielder})` : t("out.run_out");
    case "stumped":
      return fielder && bowler ? `st ${fielder} b ${bowler}` : t("out.stumped");
    case "hit_wicket":
      return bowler ? `${t("out.hit_wicket")} b ${bowler}` : t("out.hit_wicket");
    case "retired":
      return t("out.retired");
    case "retired_hurt":
      return t("out.retired_hurt");
    case "obstructing_the_field":
      return t("out.obstructing_the_field");
    case "hit_the_ball_twice":
      return t("out.hit_the_ball_twice");
    case "timed_out":
      return t("out.timed_out");
    default:
      return t("out.other");
  }
}

export function strikeRate(runs: number, balls: number): string {
  return balls ? ((runs / balls) * 100).toFixed(2) : "—";
}

export function economy(runs: number, balls: number): string {
  return balls ? ((runs * 6) / balls).toFixed(2) : "—";
}

/// The extras breakdown, the way a scorecard prints it.
export function extrasLine(inn: Innings): string {
  const parts: string[] = [];
  if (inn.byes) parts.push(`b ${inn.byes}`);
  if (inn.leg_byes) parts.push(`lb ${inn.leg_byes}`);
  if (inn.wides) parts.push(`w ${inn.wides}`);
  if (inn.no_balls) parts.push(`nb ${inn.no_balls}`);
  if (inn.penalties) parts.push(`p ${inn.penalties}`);
  return parts.length ? `(${parts.join(", ")})` : "";
}

/// What `GET /cricket/matches/{id}/squad` returns: who each captain picks from.
export type SquadPlayer = {
  id: string;
  name: string;
  /// Captains this side, so the sheet can start with them marked.
  is_captain?: boolean;
  /// "selected" | "reserve" | "available" | "unavailable" | "member"
  standing: string;
  bats_left: boolean;
};

export type SideSquad = {
  side: "home" | "away";
  team_name: string;
  /// Null when this side is not a club in Fishers — the scorer names them.
  club_id: string | null;
  can_pick: boolean;
  submitted: boolean;
  players: SquadPlayer[];
};

export type SquadResponse = { home: SideSquad; away: SideSquad };

/// Somebody appointed to this match. `role` is "umpire" or "scorer"; either
/// may keep the book.
export type MatchOfficial = { user_id: string; name: string; role: string };

export const STANDING_LABEL: Record<string, string> = {
  selected: "picked",
  reserve: "reserve",
  available: "available",
  unavailable: "said no",
  member: "member",
};
