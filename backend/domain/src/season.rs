//! A player's season, built from what they did match by match.
//!
//! The season tables hold totals, and a total cannot tell somebody whether
//! they are getting better. Everything here works from one line per player
//! per match (`player_match_lines`), so it can say *when* a best came, what
//! the last five innings looked like, and how this summer compares with the
//! last one.
//!
//! The highlights are written to build confidence without inventing it: each
//! one is a true statement about something that went well, chosen from what
//! the numbers actually show. A season with nothing to celebrate in the
//! figures still gets one honest line — turning up counts.

use std::collections::HashMap;

use chrono::{DateTime, Datelike, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{DismissalKind, MatchSide, MatchState};

/// What one player did in one match: the figures half of a
/// `player_match_lines` row, before it is told which match it was.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct MatchFigures {
    pub side: Option<MatchSide>,
    pub batting_innings: i32,
    pub not_outs: i32,
    pub runs: i32,
    pub balls_faced: i32,
    pub fours: i32,
    pub sixes: i32,
    pub high_score: Option<i32>,
    pub high_score_not_out: bool,
    pub fifties: i32,
    pub hundreds: i32,
    pub ducks: i32,
    pub bowling_balls: i32,
    pub bowling_runs: i32,
    pub wickets: i32,
    pub maidens: i32,
    pub catches: i32,
    pub stumpings: i32,
    pub player_of_match: bool,
}

/// One set of figures per player who took part: everybody in either XI, and
/// any substitute fielder who took a catch.
pub fn match_figures(state: &MatchState) -> HashMap<Uuid, MatchFigures> {
    let mut out: HashMap<Uuid, MatchFigures> = HashMap::new();
    for id in &state.home_xi {
        out.entry(*id).or_default().side = Some(MatchSide::Home);
    }
    for id in &state.away_xi {
        out.entry(*id).or_default().side = Some(MatchSide::Away);
    }

    for innings in &state.innings {
        for b in &innings.batters {
            if !b.has_batted() {
                continue;
            }
            let f = out.entry(b.player_id).or_default();
            let runs = b.runs as i32;
            f.batting_innings += 1;
            f.runs += runs;
            f.balls_faced += b.balls as i32;
            f.fours += b.fours as i32;
            f.sixes += b.sixes as i32;
            if !b.out {
                f.not_outs += 1;
            }
            // The better innings: more runs, or the same runs unbeaten.
            let better = match f.high_score {
                None => true,
                Some(h) => runs > h || (runs == h && !b.out && !f.high_score_not_out),
            };
            if better {
                f.high_score = Some(runs);
                f.high_score_not_out = !b.out;
            }
            if runs >= 100 {
                f.hundreds += 1;
            } else if runs >= 50 {
                f.fifties += 1;
            }
            if b.out && runs == 0 {
                f.ducks += 1;
            }
            if let (Some(fielder), Some(kind)) = (b.fielder_id, b.dismissal) {
                let fielding = out.entry(fielder).or_default();
                match kind {
                    DismissalKind::Caught => fielding.catches += 1,
                    DismissalKind::Stumped => fielding.stumpings += 1,
                    _ => {}
                }
            }
        }
        for b in &innings.bowlers {
            if b.balls == 0 && b.runs == 0 {
                continue;
            }
            let f = out.entry(b.player_id).or_default();
            f.bowling_balls += b.balls as i32;
            f.bowling_runs += b.runs as i32;
            f.wickets += b.wickets as i32;
            f.maidens += b.maidens as i32;
        }
    }
    if let Some(potm) = state.player_of_the_match {
        if let Some(f) = out.get_mut(&potm) {
            f.player_of_match = true;
        }
    }
    out
}

/// A `player_match_lines` row as it is read back.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MatchLine {
    pub match_id: Uuid,
    pub event_id: Uuid,
    pub club_id: Option<Uuid>,
    #[sqlx(default)]
    pub club_name: Option<String>,
    pub season_year: i32,
    pub played_at: DateTime<Utc>,
    pub opposition: String,
    pub won: Option<bool>,
    pub batting_innings: i32,
    pub not_outs: i32,
    pub runs: i32,
    pub balls_faced: i32,
    pub fours: i32,
    pub sixes: i32,
    pub high_score: Option<i32>,
    pub high_score_not_out: bool,
    pub fifties: i32,
    pub hundreds: i32,
    pub ducks: i32,
    pub bowling_balls: i32,
    pub bowling_runs: i32,
    pub wickets: i32,
    pub maidens: i32,
    pub catches: i32,
    pub stumpings: i32,
    pub player_of_match: bool,
}

impl MatchLine {
    fn batted(&self) -> bool {
        self.batting_innings > 0
    }
    fn bowled(&self) -> bool {
        self.bowling_balls > 0
    }
}

/// Wickets for runs, the way a scorebook writes it: "4/23".
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub struct Figures {
    pub wickets: i32,
    pub runs: i32,
}

impl Figures {
    /// More wickets is better; for the same wickets, fewer runs.
    fn beats(&self, other: &Figures) -> bool {
        self.wickets > other.wickets || (self.wickets == other.wickets && self.runs < other.runs)
    }
}

/// Overs as cricket writes them: 13 balls is "2.1", not 2.17.
pub fn overs(balls: i32) -> String {
    format!("{}.{}", balls / 6, balls % 6)
}

fn ratio(a: i32, b: i32) -> Option<f64> {
    (b > 0).then(|| a as f64 / b as f64)
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

/// A season, or a career, added up.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Totals {
    pub matches: i32,
    pub won: i32,
    pub batting_innings: i32,
    pub not_outs: i32,
    pub runs: i32,
    pub balls_faced: i32,
    pub fours: i32,
    pub sixes: i32,
    pub high_score: Option<i32>,
    pub high_score_not_out: bool,
    pub fifties: i32,
    pub hundreds: i32,
    pub ducks: i32,
    /// Innings of ten or more: the line between getting in and getting out.
    pub double_figures: i32,
    pub batting_average: Option<f64>,
    pub strike_rate: Option<f64>,
    pub bowling_balls: i32,
    pub overs: String,
    pub bowling_runs: i32,
    pub wickets: i32,
    pub maidens: i32,
    pub economy: Option<f64>,
    pub bowling_average: Option<f64>,
    pub bowling_strike_rate: Option<f64>,
    pub best_bowling: Option<Figures>,
    pub catches: i32,
    pub stumpings: i32,
    pub player_of_match: i32,
}

impl Totals {
    pub fn of<'a>(lines: impl IntoIterator<Item = &'a MatchLine>) -> Totals {
        let mut t = Totals::default();
        for l in lines {
            t.matches += 1;
            if l.won == Some(true) {
                t.won += 1;
            }
            t.batting_innings += l.batting_innings;
            t.not_outs += l.not_outs;
            t.runs += l.runs;
            t.balls_faced += l.balls_faced;
            t.fours += l.fours;
            t.sixes += l.sixes;
            if let Some(h) = l.high_score {
                let better = match t.high_score {
                    None => true,
                    Some(c) => h > c || (h == c && l.high_score_not_out && !t.high_score_not_out),
                };
                if better {
                    t.high_score = Some(h);
                    t.high_score_not_out = l.high_score_not_out;
                }
                if h >= 10 {
                    t.double_figures += 1;
                }
            }
            t.fifties += l.fifties;
            t.hundreds += l.hundreds;
            t.ducks += l.ducks;
            t.bowling_balls += l.bowling_balls;
            t.bowling_runs += l.bowling_runs;
            t.wickets += l.wickets;
            t.maidens += l.maidens;
            if l.bowled() {
                let f = Figures { wickets: l.wickets, runs: l.bowling_runs };
                if t.best_bowling.is_none_or(|b| f.beats(&b)) {
                    t.best_bowling = Some(f);
                }
            }
            t.catches += l.catches;
            t.stumpings += l.stumpings;
            if l.player_of_match {
                t.player_of_match += 1;
            }
        }
        t.batting_average = ratio(t.runs, t.batting_innings - t.not_outs).map(round1);
        t.strike_rate = ratio(t.runs * 100, t.balls_faced).map(round1);
        t.overs = overs(t.bowling_balls);
        t.economy = ratio(t.bowling_runs * 6, t.bowling_balls).map(|x| (x * 100.0).round() / 100.0);
        t.bowling_average = ratio(t.bowling_runs, t.wickets).map(round1);
        t.bowling_strike_rate = ratio(t.bowling_balls, t.wickets).map(round1);
        t
    }
}

/// One match on the form guide.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormEntry {
    pub match_id: Uuid,
    pub event_id: Uuid,
    pub played_at: DateTime<Utc>,
    pub opposition: String,
    pub won: Option<bool>,
    pub batted: bool,
    pub runs: i32,
    pub balls: i32,
    pub not_out: bool,
    pub bowled: bool,
    pub wickets: i32,
    pub runs_conceded: i32,
    pub overs: String,
    pub catches: i32,
    pub player_of_match: bool,
}

impl From<&MatchLine> for FormEntry {
    fn from(l: &MatchLine) -> Self {
        FormEntry {
            match_id: l.match_id,
            event_id: l.event_id,
            played_at: l.played_at,
            opposition: l.opposition.clone(),
            won: l.won,
            batted: l.batted(),
            runs: l.runs,
            balls: l.balls_faced,
            not_out: l.batted() && l.not_outs >= l.batting_innings,
            bowled: l.bowled(),
            wickets: l.wickets,
            runs_conceded: l.bowling_runs,
            overs: overs(l.bowling_balls),
            catches: l.catches + l.stumpings,
            player_of_match: l.player_of_match,
        }
    }
}

/// Which way the recent innings are heading, against the season so far.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Trend {
    Rising,
    Steady,
    /// Never said as "falling": the page says "a quieter patch", and only
    /// alongside the season figures that put it in proportion.
    Quieter,
}

/// The last few matches, and what they add up to.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Form {
    /// Newest first, at most ten.
    pub matches: Vec<FormEntry>,
    /// Runs per innings over the last five innings.
    pub recent_batting_average: Option<f64>,
    pub batting_trend: Option<Trend>,
    /// Wickets per match over the last five matches they bowled in.
    pub recent_wickets_per_match: Option<f64>,
    pub bowling_trend: Option<Trend>,
}

fn trend(recent: f64, overall: f64) -> Trend {
    if overall <= 0.0 {
        return if recent > 0.0 { Trend::Rising } else { Trend::Steady };
    }
    let change = (recent - overall) / overall;
    if change >= 0.15 {
        Trend::Rising
    } else if change <= -0.15 {
        Trend::Quieter
    } else {
        Trend::Steady
    }
}

/// `lines` newest first.
fn form(lines: &[&MatchLine], season: &Totals) -> Form {
    let batted: Vec<&&MatchLine> = lines.iter().filter(|l| l.batted()).take(5).collect();
    let bowled: Vec<&&MatchLine> = lines.iter().filter(|l| l.bowled()).take(5).collect();
    // Per innings, not per dismissal: five innings is too few for not-outs
    // to give an average that means anything.
    let recent_bat = (batted.len() >= 3).then(|| {
        let runs: i32 = batted.iter().map(|l| l.runs).sum();
        let inns: i32 = batted.iter().map(|l| l.batting_innings).sum();
        round1(runs as f64 / inns.max(1) as f64)
    });
    let season_per_innings = ratio(season.runs, season.batting_innings).unwrap_or(0.0);
    let recent_bowl = (bowled.len() >= 3).then(|| {
        let w: i32 = bowled.iter().map(|l| l.wickets).sum();
        round1(w as f64 / bowled.len() as f64)
    });
    let bowled_matches = lines.iter().filter(|l| l.bowled()).count() as i32;
    let season_wpm = ratio(season.wickets, bowled_matches).unwrap_or(0.0);
    // A trend needs something to be a trend against: more matches than the
    // recent window itself.
    Form {
        matches: lines.iter().take(10).map(|l| FormEntry::from(*l)).collect(),
        recent_batting_average: recent_bat,
        batting_trend: recent_bat
            .filter(|_| season.batting_innings > batted.len() as i32)
            .map(|r| trend(r, season_per_innings)),
        recent_wickets_per_match: recent_bowl,
        bowling_trend: recent_bowl
            .filter(|_| bowled_matches > bowled.len() as i32)
            .map(|r| trend(r, season_wpm)),
    }
}

/// A best, with where and when it came.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Best {
    pub code: String,
    /// "78*", "5/23", "6", "412".
    pub value: String,
    pub opposition: Option<String>,
    pub played_at: Option<DateTime<Utc>>,
    pub season_year: Option<i32>,
    /// Set in the season being looked at — a new best is the best news there is.
    pub this_season: bool,
}

fn score(runs: i32, not_out: bool) -> String {
    if not_out {
        format!("{runs}*")
    } else {
        runs.to_string()
    }
}

/// Career bests. `lines` oldest first; ties go to the earlier one, which is
/// when the record was actually set.
fn bests(lines: &[MatchLine], season: i32) -> Vec<Best> {
    let mut out = Vec::new();
    let mut best_score: Option<&MatchLine> = None;
    let mut best_bowl: Option<&MatchLine> = None;
    let mut most_sixes: Option<&MatchLine> = None;
    let mut most_catches: Option<&MatchLine> = None;
    for l in lines {
        if let Some(h) = l.high_score {
            let better = match best_score.and_then(|b| b.high_score.map(|s| (s, b.high_score_not_out))) {
                None => true,
                Some((s, no)) => h > s || (h == s && l.high_score_not_out && !no),
            };
            if better {
                best_score = Some(l);
            }
        }
        if l.bowled() && l.wickets > 0 {
            let f = Figures { wickets: l.wickets, runs: l.bowling_runs };
            if best_bowl.is_none_or(|b| f.beats(&Figures { wickets: b.wickets, runs: b.bowling_runs })) {
                best_bowl = Some(l);
            }
        }
        if l.sixes > 0 && most_sixes.is_none_or(|b| l.sixes > b.sixes) {
            most_sixes = Some(l);
        }
        let held = l.catches + l.stumpings;
        if held > 0 && most_catches.is_none_or(|b| held > b.catches + b.stumpings) {
            most_catches = Some(l);
        }
    }
    let from = |code: &str, value: String, l: &MatchLine| Best {
        code: code.into(),
        value,
        opposition: Some(l.opposition.clone()),
        played_at: Some(l.played_at),
        season_year: Some(l.season_year),
        this_season: l.season_year == season,
    };
    if let Some(l) = best_score {
        out.push(from("best_score", score(l.high_score.unwrap_or(0), l.high_score_not_out), l));
    }
    if let Some(l) = best_bowl {
        out.push(from("best_bowling", format!("{}/{}", l.wickets, l.bowling_runs), l));
    }
    if let Some(l) = most_sixes {
        out.push(from("most_sixes", l.sixes.to_string(), l));
    }
    if let Some(l) = most_catches {
        out.push(from("most_catches", (l.catches + l.stumpings).to_string(), l));
    }

    // Best seasons: only worth saying once there is more than one season.
    let mut by_season: HashMap<i32, (i32, i32)> = HashMap::new();
    for l in lines {
        let e = by_season.entry(l.season_year).or_default();
        e.0 += l.runs;
        e.1 += l.wickets;
    }
    if by_season.len() > 1 {
        let season_best = |pick: fn(&(i32, i32)) -> i32, code: &str| {
            by_season
                .iter()
                .filter(|(_, v)| pick(v) > 0)
                // The highest; on a tie, the earlier season set it first.
                .max_by_key(|(y, v)| (pick(v), -**y))
                .map(|(y, v)| Best {
                    code: code.into(),
                    value: pick(v).to_string(),
                    opposition: None,
                    played_at: None,
                    season_year: Some(*y),
                    this_season: *y == season,
                })
        };
        out.extend(season_best(|v| v.0, "best_season_runs"));
        out.extend(season_best(|v| v.1, "best_season_wickets"));
    }
    out
}

/// A first, or a round number, and the day it came.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Milestone {
    pub code: String,
    pub reached_at: DateTime<Utc>,
    pub opposition: String,
    pub this_season: bool,
}

/// Thresholds a career passes once. Matches, runs, wickets.
const MATCHES: [i32; 4] = [10, 25, 50, 100];
const RUNS: [i32; 6] = [100, 250, 500, 1000, 2500, 5000];
const WICKETS: [i32; 5] = [10, 25, 50, 100, 200];

/// `lines` oldest first.
fn milestones(lines: &[MatchLine], season: i32) -> Vec<Milestone> {
    let mut out = Vec::new();
    let (mut matches, mut runs, mut wickets) = (0, 0, 0);
    let mut seen: std::collections::HashSet<String> = Default::default();
    let mut hit = |code: String, l: &MatchLine, out: &mut Vec<Milestone>| {
        if seen.insert(code.clone()) {
            out.push(Milestone {
                code,
                reached_at: l.played_at,
                opposition: l.opposition.clone(),
                this_season: l.season_year == season,
            });
        }
    };
    for l in lines {
        let (m0, r0, w0) = (matches, runs, wickets);
        matches += 1;
        runs += l.runs;
        wickets += l.wickets;
        if m0 == 0 {
            hit("first_match".into(), l, &mut out);
        }
        if l.sixes > 0 {
            hit("first_six".into(), l, &mut out);
        }
        if l.fifties > 0 || l.hundreds > 0 {
            hit("first_fifty".into(), l, &mut out);
        }
        if l.hundreds > 0 {
            hit("first_hundred".into(), l, &mut out);
        }
        if l.wickets > 0 {
            hit("first_wicket".into(), l, &mut out);
        }
        if l.wickets >= 3 {
            hit("first_three_wickets".into(), l, &mut out);
        }
        if l.wickets >= 5 {
            hit("first_five_wickets".into(), l, &mut out);
        }
        if l.catches + l.stumpings > 0 {
            hit("first_catch".into(), l, &mut out);
        }
        if l.player_of_match {
            hit("first_player_of_match".into(), l, &mut out);
        }
        if l.won == Some(true) {
            hit("first_win".into(), l, &mut out);
        }
        for n in MATCHES {
            if m0 < n && matches >= n {
                hit(format!("matches_{n}"), l, &mut out);
            }
        }
        for n in RUNS {
            if r0 < n && runs >= n {
                hit(format!("runs_{n}"), l, &mut out);
            }
        }
        for n in WICKETS {
            if w0 < n && wickets >= n {
                hit(format!("wickets_{n}"), l, &mut out);
            }
        }
    }
    out
}

/// Where the player stands in their club this season.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ClubRank {
    pub club_id: Uuid,
    pub club_name: String,
    /// 1-based; None when they have none of that thing.
    pub runs: Option<i32>,
    pub wickets: Option<i32>,
    pub catches: Option<i32>,
    /// How many players in the club scored or bowled this season.
    pub players: i32,
}

/// One true, good thing to say. `code` is for the apps to put into their own
/// words and language; `text` is the English, for the email and as a fallback.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Highlight {
    pub code: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

fn hl(code: &str, text: String, value: Option<String>, detail: Option<String>) -> Highlight {
    Highlight { code: code.into(), text, value, detail }
}

fn pct_up(now: f64, then: f64) -> Option<i32> {
    (then > 0.0 && now > then).then(|| ((now - then) / then * 100.0).round() as i32)
}

/// English names for milestones, for the email and the fallback text.
pub fn milestone_label(code: &str) -> String {
    let n = |p: &str| code.strip_prefix(p).unwrap_or("");
    match code {
        "first_match" => "First match".into(),
        "first_six" => "First six".into(),
        "first_fifty" => "First fifty".into(),
        "first_hundred" => "First hundred".into(),
        "first_wicket" => "First wicket".into(),
        "first_three_wickets" => "First three-wicket haul".into(),
        "first_five_wickets" => "First five-wicket haul".into(),
        "first_catch" => "First catch".into(),
        "first_player_of_match" => "First player of the match".into(),
        "first_win" => "First win".into(),
        c if c.starts_with("matches_") => format!("{} matches", n("matches_")),
        c if c.starts_with("runs_") => format!("{} career runs", n("runs_")),
        c if c.starts_with("wickets_") => format!("{} career wickets", n("wickets_")),
        other => other.replace('_', " "),
    }
}

/// At most four, best news first.
fn highlights(
    season: &Totals,
    previous: Option<&Totals>,
    // Played before this season: without that, every best is "new".
    has_history: bool,
    bests: &[Best],
    milestones: &[Milestone],
    rank: Option<&ClubRank>,
) -> Vec<Highlight> {
    let mut out = Vec::new();
    if season.matches == 0 {
        return out;
    }

    for b in bests.iter().filter(|b| b.this_season) {
        let against = b.opposition.as_deref().map(|o| format!(" against {o}")).unwrap_or_default();
        match b.code.as_str() {
            "best_score" if has_history => out.push(hl(
                "new_best_score",
                format!("A new best score: {}{against}.", b.value),
                Some(b.value.clone()),
                b.opposition.clone(),
            )),
            "best_score" => out.push(hl(
                "season_best_score",
                format!("Best score of the season: {}{against}.", b.value),
                Some(b.value.clone()),
                b.opposition.clone(),
            )),
            "best_bowling" if has_history => out.push(hl(
                "new_best_bowling",
                format!("Your best bowling yet: {}{against}.", b.value),
                Some(b.value.clone()),
                b.opposition.clone(),
            )),
            "best_bowling" => out.push(hl(
                "season_best_bowling",
                format!("Best bowling of the season: {}{against}.", b.value),
                Some(b.value.clone()),
                b.opposition.clone(),
            )),
            _ => {}
        }
    }

    // The biggest milestone this season, not every first.
    if let Some(m) = milestones.iter().rev().find(|m| m.this_season && m.code != "first_match") {
        out.push(hl(
            "milestone",
            format!("Milestone reached: {}.", milestone_label(&m.code)),
            Some(milestone_label(&m.code)),
            Some(m.code.clone()),
        ));
    }

    if let Some(prev) = previous {
        // Only against a season with enough in it to compare.
        if season.batting_innings >= 3 && prev.batting_innings >= 3 {
            if let Some(p) = season
                .batting_average
                .zip(prev.batting_average)
                .and_then(|(a, b)| pct_up(a, b))
                .filter(|p| *p >= 5)
            {
                out.push(hl(
                    "average_up",
                    format!("Your batting average is up {p}% on last season."),
                    Some(p.to_string()),
                    None,
                ));
            } else if let Some(p) = season
                .strike_rate
                .zip(prev.strike_rate)
                .and_then(|(a, b)| pct_up(a, b))
                .filter(|p| *p >= 5)
            {
                out.push(hl(
                    "strike_rate_up",
                    format!("You're scoring {p}% quicker than last season."),
                    Some(p.to_string()),
                    None,
                ));
            }
        }
        if season.bowling_balls >= 36 && prev.bowling_balls >= 36 {
            if let Some((now, then)) = season.economy.zip(prev.economy).filter(|(n, t)| n < t) {
                let p = ((then - now) / then * 100.0).round() as i32;
                if p >= 5 {
                    out.push(hl(
                        "economy_down",
                        format!("You're conceding {p}% fewer runs an over than last season."),
                        Some(p.to_string()),
                        None,
                    ));
                }
            }
        }
        if season.runs > prev.runs && prev.runs > 0 {
            out.push(hl(
                "more_runs",
                format!("{} runs this season, up from {} last season.", season.runs, prev.runs),
                Some(season.runs.to_string()),
                Some(prev.runs.to_string()),
            ));
        }
        if season.wickets > prev.wickets && prev.wickets > 0 {
            out.push(hl(
                "more_wickets",
                format!("{} wickets this season, up from {}.", season.wickets, prev.wickets),
                Some(season.wickets.to_string()),
                Some(prev.wickets.to_string()),
            ));
        }
    }

    if let Some(r) = rank {
        if let Some(n @ 1..=3) = r.runs {
            out.push(hl(
                "club_top_runs",
                format!("{} for runs at {} this season.", place(n), r.club_name),
                Some(n.to_string()),
                Some(r.club_name.clone()),
            ));
        }
        if let Some(n @ 1..=3) = r.wickets {
            out.push(hl(
                "club_top_wickets",
                format!("{} for wickets at {} this season.", place(n), r.club_name),
                Some(n.to_string()),
                Some(r.club_name.clone()),
            ));
        }
    }

    if season.batting_innings >= 4 && season.double_figures * 2 >= season.batting_innings {
        out.push(hl(
            "consistent",
            format!(
                "You reached double figures in {} of {} innings.",
                season.double_figures, season.batting_innings
            ),
            Some(season.double_figures.to_string()),
            Some(season.batting_innings.to_string()),
        ));
    }
    if season.player_of_match > 0 {
        out.push(hl(
            "player_of_match",
            if season.player_of_match == 1 {
                "Player of the match once this season.".into()
            } else {
                format!("Player of the match {} times this season.", season.player_of_match)
            },
            Some(season.player_of_match.to_string()),
            None,
        ));
    }
    let held = season.catches + season.stumpings;
    if held >= 3 {
        out.push(hl(
            "safe_hands",
            format!("{held} catches and stumpings — runs saved count too."),
            Some(held.to_string()),
            None,
        ));
    }
    if season.matches >= 3 && season.won * 2 > season.matches {
        out.push(hl(
            "winning_side",
            format!("On the winning side in {} of {} matches.", season.won, season.matches),
            Some(season.won.to_string()),
            Some(season.matches.to_string()),
        ));
    }

    if out.is_empty() {
        out.push(hl(
            "turned_up",
            if season.matches == 1 {
                "You played a match this season — every game counts towards the next.".into()
            } else {
                format!(
                    "You played {} matches this season — every game counts towards the next.",
                    season.matches
                )
            },
            Some(season.matches.to_string()),
            None,
        ));
    }
    out.truncate(4);
    out
}

fn place(n: i32) -> &'static str {
    match n {
        1 => "Top",
        2 => "Second",
        _ => "Third",
    }
}

/// Everything the "My game" page and the season email say.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerGame {
    pub user_id: Uuid,
    pub name: String,
    pub season: i32,
    /// Seasons they have played in, newest first.
    pub seasons: Vec<i32>,
    pub totals: Totals,
    /// The season before, when they played in it.
    pub previous: Option<Totals>,
    pub career: Totals,
    pub form: Form,
    pub bests: Vec<Best>,
    pub milestones: Vec<Milestone>,
    pub club_rank: Option<ClubRank>,
    pub highlights: Vec<Highlight>,
}

impl PlayerGame {
    /// `lines` is every line the player has, in any order. `rank` is for the
    /// season being looked at.
    pub fn build(
        user_id: Uuid,
        name: String,
        season: i32,
        mut lines: Vec<MatchLine>,
        rank: Option<ClubRank>,
    ) -> PlayerGame {
        lines.sort_by_key(|l| l.played_at);
        let mut seasons: Vec<i32> = lines.iter().map(|l| l.season_year).collect();
        seasons.sort_unstable_by(|a, b| b.cmp(a));
        seasons.dedup();

        // The career up to and including this season: looking back at 2025
        // should not show bests set in 2026.
        let upto: Vec<MatchLine> = lines.iter().filter(|l| l.season_year <= season).cloned().collect();
        let this: Vec<&MatchLine> = upto.iter().filter(|l| l.season_year == season).collect();
        let totals = Totals::of(this.iter().copied());
        let prev_lines: Vec<&MatchLine> = upto.iter().filter(|l| l.season_year == season - 1).collect();
        let previous = (!prev_lines.is_empty()).then(|| Totals::of(prev_lines.iter().copied()));
        let newest_first: Vec<&MatchLine> = this.iter().rev().copied().collect();
        let form = form(&newest_first, &totals);
        let bests = bests(&upto, season);
        let milestones = milestones(&upto, season);
        let has_history = upto.iter().any(|l| l.season_year < season);
        let highlights =
            highlights(&totals, previous.as_ref(), has_history, &bests, &milestones, rank.as_ref());
        PlayerGame {
            user_id,
            name,
            season,
            seasons,
            career: Totals::of(upto.iter()),
            totals,
            previous,
            form,
            bests,
            milestones,
            club_rank: rank,
            highlights,
        }
    }
}

/// The year a fixture on this date counts towards. Calendar years, as the
/// season tables have always used.
pub fn season_of(at: DateTime<Utc>) -> i32 {
    at.year()
}

// MARK: The club's season

/// One line on a club leaderboard.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Leader {
    pub user_id: Uuid,
    pub name: String,
    /// What the board is ranked by, as it reads: "412", "38.5", "5/23".
    pub value: String,
    /// The context underneath: "11 inns", "at 18.2".
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Leaderboard {
    pub code: String,
    pub leaders: Vec<Leader>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, sqlx::FromRow)]
pub struct SeasonRecordLine {
    pub played: i64,
    pub won: i64,
    pub lost: i64,
    pub tied_or_no_result: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClubSeason {
    pub club_id: Uuid,
    pub club_name: String,
    pub season: i32,
    /// When the secretary closed it, and the season emails went.
    pub closed_at: Option<DateTime<Utc>>,
    pub seasons: Vec<i32>,
    pub record: SeasonRecordLine,
    pub players: i64,
    pub boards: Vec<Leaderboard>,
}

/// What closing the season will do, shown before the secretary confirms.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ClosePreview {
    pub season: i32,
    pub closed_at: Option<DateTime<Utc>>,
    /// Active members of the club.
    pub members: i64,
    /// Of those, who will get an email: an address on file, not opted out —
    /// and none at all while this server cannot send mail.
    pub will_email: i64,
    /// Of those, who played this season and gets their figures; the rest
    /// get a thank-you.
    pub played: i64,
    /// Whether this server can send mail at all. When it cannot, closing still
    /// notifies everyone in the app, and the emails wait until mail is on.
    #[sqlx(default)]
    pub email_on: bool,
}

/// One season email waiting to go.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct DueSeasonEmail {
    pub club_id: Uuid,
    pub club_name: String,
    pub season_year: i32,
    pub user_id: Uuid,
    pub email: Option<String>,
    pub season_emails_off: bool,
    pub email_prefs_token: String,
    pub attempts: i32,
    /// The "season closed" push, which goes once whatever the email does.
    pub pushed_at: Option<DateTime<Utc>>,
    /// Sent, or settled as not sending (no address, opted out, failed).
    pub email_done: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn line(year: i32, month: u32, f: impl FnOnce(&mut MatchLine)) -> MatchLine {
        let mut l = MatchLine {
            match_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            club_id: None,
            club_name: None,
            season_year: year,
            played_at: Utc.with_ymd_and_hms(year, month, 1, 13, 0, 0).unwrap(),
            opposition: format!("Opp {month}"),
            won: None,
            batting_innings: 0,
            not_outs: 0,
            runs: 0,
            balls_faced: 0,
            fours: 0,
            sixes: 0,
            high_score: None,
            high_score_not_out: false,
            fifties: 0,
            hundreds: 0,
            ducks: 0,
            bowling_balls: 0,
            bowling_runs: 0,
            wickets: 0,
            maidens: 0,
            catches: 0,
            stumpings: 0,
            player_of_match: false,
        };
        f(&mut l);
        l
    }

    fn bat(runs: i32, balls: i32, out: bool) -> impl FnOnce(&mut MatchLine) {
        move |l| {
            l.batting_innings = 1;
            l.not_outs = if out { 0 } else { 1 };
            l.runs = runs;
            l.balls_faced = balls;
            l.high_score = Some(runs);
            l.high_score_not_out = !out;
            if runs >= 100 {
                l.hundreds = 1;
            } else if runs >= 50 {
                l.fifties = 1;
            }
            if out && runs == 0 {
                l.ducks = 1;
            }
        }
    }

    #[test]
    fn overs_are_written_as_cricket_writes_them() {
        assert_eq!(overs(13), "2.1");
        assert_eq!(overs(24), "4.0");
        assert_eq!(overs(0), "0.0");
    }

    #[test]
    fn totals_add_up_and_average_by_dismissals() {
        let ls = [line(2026, 5, bat(40, 30, true)), line(2026, 6, bat(20, 10, false)), line(2026, 7, bat(0, 3, true))];
        let t = Totals::of(ls.iter());
        assert_eq!(t.runs, 60);
        assert_eq!(t.batting_innings, 3);
        assert_eq!(t.batting_average, Some(30.0)); // 60 / 2 dismissals
        assert_eq!(t.strike_rate, Some(139.5)); // 6000 / 43
        assert_eq!(t.ducks, 1);
        assert_eq!(t.double_figures, 2);
        assert_eq!(t.high_score, Some(40));
    }

    #[test]
    fn an_unbeaten_score_beats_the_same_score_out() {
        let ls = [line(2026, 5, bat(50, 40, true)), line(2026, 6, bat(50, 45, false))];
        let t = Totals::of(ls.iter());
        assert_eq!((t.high_score, t.high_score_not_out), (Some(50), true));
    }

    #[test]
    fn best_bowling_is_most_wickets_then_fewest_runs() {
        let ls = [
            line(2026, 5, |l| { l.bowling_balls = 24; l.wickets = 3; l.bowling_runs = 30; }),
            line(2026, 6, |l| { l.bowling_balls = 24; l.wickets = 3; l.bowling_runs = 12; }),
            line(2026, 7, |l| { l.bowling_balls = 24; l.wickets = 2; l.bowling_runs = 5; }),
        ];
        let t = Totals::of(ls.iter());
        assert_eq!(t.best_bowling, Some(Figures { wickets: 3, runs: 12 }));
        assert_eq!(t.economy, Some(3.92)); // 47 runs off 12 overs
    }

    #[test]
    fn a_new_best_this_season_leads_the_highlights() {
        let ls = vec![
            line(2025, 6, bat(30, 25, true)),
            line(2026, 5, bat(12, 10, true)),
            line(2026, 6, bat(78, 50, false)),
        ];
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, None);
        assert_eq!(g.highlights[0].code, "new_best_score");
        assert_eq!(g.highlights[0].value.as_deref(), Some("78*"));
        let best = g.bests.iter().find(|b| b.code == "best_score").unwrap();
        assert!(best.this_season);
        assert!(g.milestones.iter().any(|m| m.code == "first_fifty" && m.this_season));
        assert_eq!(g.seasons, vec![2026, 2025]);
        assert!(g.previous.is_some());
    }

    #[test]
    fn a_first_season_best_is_not_called_new() {
        let ls = vec![line(2026, 5, bat(12, 10, true)), line(2026, 6, bat(44, 30, true))];
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, None);
        assert_eq!(g.highlights[0].code, "season_best_score");
        assert_eq!(g.highlights[0].text, "Best score of the season: 44 against Opp 6.");
    }

    #[test]
    fn looking_back_ignores_what_came_later() {
        let ls = vec![line(2025, 6, bat(30, 25, true)), line(2026, 6, bat(99, 60, true))];
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2025, ls, None);
        let best = g.bests.iter().find(|b| b.code == "best_score").unwrap();
        assert_eq!(best.value, "30");
        assert_eq!(g.career.runs, 30);
    }

    #[test]
    fn a_quiet_season_still_gets_an_honest_line() {
        let ls = vec![line(2026, 5, |l| l.won = Some(false)), line(2026, 6, |l| l.won = Some(false))];
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, None);
        // First match is a milestone but not a highlight on its own.
        assert_eq!(g.highlights.len(), 1);
        assert_eq!(g.highlights[0].code, "turned_up");
        assert!(g.highlights[0].text.contains("2 matches"));
    }

    #[test]
    fn improvement_on_last_season_is_measured_fairly() {
        let mut ls = vec![];
        for m in 4..=7 {
            ls.push(line(2025, m, bat(10, 20, true)));
        }
        for m in 4..=7 {
            ls.push(line(2026, m, bat(20, 20, true)));
        }
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, None);
        let codes: Vec<&str> = g.highlights.iter().map(|h| h.code.as_str()).collect();
        assert!(codes.contains(&"average_up"), "{codes:?}");
        let up = g.highlights.iter().find(|h| h.code == "average_up").unwrap();
        assert_eq!(up.value.as_deref(), Some("100"));
    }

    #[test]
    fn form_trends_need_more_than_the_window() {
        let mut ls = vec![];
        for (m, r) in [(4, 5), (5, 5), (6, 5), (7, 30), (8, 30), (9, 30), (10, 30), (11, 30)] {
            ls.push(line(2026, m, bat(r, 20, true)));
        }
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, None);
        assert_eq!(g.form.matches.len(), 8);
        assert_eq!(g.form.matches[0].runs, 30, "newest first");
        assert_eq!(g.form.recent_batting_average, Some(30.0));
        assert_eq!(g.form.batting_trend, Some(Trend::Rising));
    }

    #[test]
    fn career_thresholds_are_passed_once() {
        let ls: Vec<MatchLine> = (1..=12).map(|m| line(2026, (m % 12) + 1, bat(10, 10, true))).collect();
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, None);
        let codes: Vec<&str> = g.milestones.iter().map(|m| m.code.as_str()).collect();
        assert_eq!(codes.iter().filter(|c| **c == "matches_10").count(), 1);
        assert!(codes.contains(&"runs_100"));
    }

    #[test]
    fn club_rank_makes_a_highlight_only_in_the_top_three() {
        let ls = vec![line(2026, 5, bat(5, 5, true))];
        let rank = ClubRank { club_id: Uuid::nil(), club_name: "Southall".into(), runs: Some(2), wickets: Some(9), catches: None, players: 12 };
        let g = PlayerGame::build(Uuid::new_v4(), "A".into(), 2026, ls, Some(rank));
        let codes: Vec<&str> = g.highlights.iter().map(|h| h.code.as_str()).collect();
        assert!(codes.contains(&"club_top_runs"));
        assert!(!codes.contains(&"club_top_wickets"));
    }
}
