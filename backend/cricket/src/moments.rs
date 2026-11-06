//! Magic moments: the balls a match turned on, and the players who made them.
//!
//! Everyone leaves a game talking about a ball — the six that brought it back,
//! the catch that ended it — and about a player. The ball-by-ball log already
//! says who was batting, who was bowling and who took the catch, so both can be
//! read straight back out. Nothing more for the scorer to record.
//!
//! # How a moment is found
//!
//! After each ball of the chase, the chasing side's chance is estimated from
//! what is left: runs needed, balls left, wickets in hand. "How much batting is
//! left" comes from the DLS resource curve, so a reduced-overs game works
//! without a second model. It is a small, honest model — good enough to say
//! which balls swung things, not to price a bet — and every surface labels the
//! percentages as an estimate.
//!
//! A ball's swing is credited to the player who made it: the batter for runs
//! off the bat, the bowler for a wicket they are credited with or a ball that
//! cost the chase, the fielder for a run-out. Extras belong to nobody, so a
//! wide never becomes somebody's moment.
//!
//! The **turning point** is one of them:
//!
//! - **Comeback** — if the winners were ever behind (under 50%), the biggest
//!   swing a winner made during the stretch in which they were still behind,
//!   up to the ball that put them level.
//! - **Decider** — if they were never behind, the biggest swing a winner made
//!   anywhere: where it was put out of reach.
//!
//! The rest are simply the biggest swings, with room kept for the losing side's
//! best — the moment that nearly won it. Nothing under [`MIN_SWING`] is named:
//! a quiet game gets no moments rather than three balls chosen to fill slots.
//! First innings are not modelled — with no target there is nothing to measure
//! a ball against — but [`Feat`]s are read from every innings.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::dls::ResourceTable;
use super::types::*;

/// The smallest swing worth naming, as a fraction of certainty.
const MIN_SWING: f64 = 0.05;
/// How many moments a match gets at most.
const MAX_MOMENTS: usize = 3;
/// A stand worth celebrating the end of.
const BIG_STAND: u16 = 50;
/// What a last over has to be defending for it to count: two a ball or fewer.
const DEFENDABLE: i32 = 12;

/// How the winners got there.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TurningKind {
    /// They were behind, and this is the ball that brought them back.
    Comeback,
    /// They were never behind; this is where it was put out of reach.
    Decider,
}

/// What the player was doing when they made the moment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MomentRole {
    Batting,
    Bowling,
    Fielding,
}

/// One ball that swung the match, and who made it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MagicMoment {
    pub player_id: Uuid,
    /// The catcher or the keeper, when the bowler's wicket needed one.
    pub helper_id: Option<Uuid>,
    pub role: MomentRole,
    /// The side it helped — the player's side.
    pub side: MatchSide,
    /// Whether that side went on to win. A losing side's moment is the one
    /// that nearly won it.
    pub won: bool,
    /// Set on the ball the match turned on. At most one moment has it.
    pub turning: Option<TurningKind>,
    pub dismissal: Option<DismissalKind>,
    pub shot: Option<ShotKind>,
    /// Which innings of the match, 0-indexed. Always the chase.
    pub innings: u8,
    /// As a scorer says it: "14.3".
    pub over: String,
    /// What the scorebook shows: "6", "W".
    pub label: String,
    pub runs: u8,
    pub is_wicket: bool,
    /// The chance of `side` winning, in whole percent, just before and after.
    pub before_percent: u8,
    pub after_percent: u8,
    /// What the chase still needed once the ball was done, and from how many.
    pub runs_needed: u16,
    pub balls_left: u16,
}

/// A recognised piece of cricket, read off the log.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeatKind {
    /// Three or more wickets in consecutive balls by one bowler. `value` is
    /// how many.
    HatTrick,
    /// Two wickets in two balls, and no third.
    TwoInTwo,
    /// One batter hitting three or more sixes in an over. `value` is how many.
    SixesInAnOver,
    /// Fifty, a hundred, or more, brought up with a six. `value` is the mark.
    MilestoneWithASix,
    /// The wicket that ended the innings' biggest stand of fifty or more.
    /// `value` is the stand.
    PartnershipBreaker,
    /// A maiden in the last fifth of the innings. `value` is the wickets in it.
    DeathMaiden,
    /// The winning runs off the last ball the chase had. `value` is the runs.
    LastBallFinish,
    /// Twelve or fewer to defend in the last over, defended. `value` is what
    /// they needed.
    LastOverDefence,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feat {
    pub kind: FeatKind,
    pub player_id: Uuid,
    pub side: MatchSide,
    pub innings: u8,
    /// The ball that completed it: "17.4".
    pub over: String,
    pub value: u16,
}

/// "14.3", the way a scorer says it.
fn ball_display(d: &DeliveryRecord) -> String {
    format!("{}.{}", d.over, d.ball_in_over.max(1))
}

/// Runs off the bat, when the label says so plainly. Anything with an extra or
/// a wicket in it is somebody else's or nobody's.
fn bat_runs(label: &str) -> Option<u8> {
    let digits = label.strip_suffix('s').unwrap_or(label);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    digits.parse().ok()
}

/// How the wicket on a wicket-ball was taken, from the batter it removed.
#[derive(Debug, Clone, Copy)]
struct Dismissal {
    kind: Option<DismissalKind>,
    bowler: Option<Uuid>,
    fielder: Option<Uuid>,
    partnership: u16,
}

/// One entry per wicket-ball, in order. The engine pushes a fall of wicket and
/// a wicket delivery together, so the two lists line up.
fn dismissals(inn: &InningsState) -> Vec<Dismissal> {
    inn.fall
        .iter()
        .map(|f| {
            let batter = inn.batters.iter().find(|b| b.player_id == f.batter_id);
            Dismissal {
                kind: batter.and_then(|b| b.dismissal),
                bowler: batter.and_then(|b| b.bowler_id),
                fielder: batter.and_then(|b| b.fielder_id),
                partnership: f.partnership_runs,
            }
        })
        .collect()
}

/// Who gets the wicket as a moment: the bowler when it is theirs, the fielder
/// for a run-out, nobody for retiring or timing out.
fn wicket_credit(
    d: &DeliveryRecord,
    w: &Dismissal,
) -> Option<(Uuid, Option<Uuid>, MomentRole)> {
    match w.kind? {
        DismissalKind::RunOut => Some((w.fielder?, None, MomentRole::Fielding)),
        k if k.credits_bowler() => {
            let helper = matches!(k, DismissalKind::Caught | DismissalKind::Stumped)
                .then_some(w.fielder)
                .flatten();
            Some((w.bowler.or(d.bowler_id)?, helper, MomentRole::Bowling))
        }
        _ => None,
    }
}

/// Chance the side batting second wins, `0.0..=1.0`.
fn chase_chance(
    table: &ResourceTable,
    base: f64,
    start_resource: f64,
    needed: i32,
    balls_left: u16,
    wickets: u8,
    wickets_allowed: u8,
) -> f64 {
    if needed <= 0 {
        return 1.0;
    }
    if balls_left == 0 || wickets >= wickets_allowed {
        return 0.0;
    }
    let left = table.resource(balls_left as f64 / 6.0, wickets);
    if start_resource <= 0.0 || left <= 0.0 {
        return 0.0;
    }
    let share = left / start_resource;
    // A side with all its resources is expected to make what the first
    // innings made; the same side with half of them, half of it.
    let expected = base * share;
    let margin = expected - needed as f64;
    // Uncertainty shrinks as the innings runs out — a hundred to get off six
    // balls is not 50-50 because the maths straddles zero.
    let spread = 0.30 * base * share.sqrt() + 3.0;
    1.0 / (1.0 + (-1.7 * margin / spread).exp())
}

fn percent(p: f64) -> u8 {
    (p * 100.0).round().clamp(0.0, 100.0) as u8
}

/// The chase, ball by ball.
struct Chase<'a> {
    inn: &'a InningsState,
    /// The chasing side's chance before the first ball, then after each.
    chances: Vec<f64>,
    /// Runs still needed and balls still left after each delivery.
    needed_after: Vec<i32>,
    balls_left_after: Vec<u16>,
    total_balls: u16,
}

/// A ball, credited.
struct Candidate {
    index: usize,
    player_id: Uuid,
    helper_id: Option<Uuid>,
    role: MomentRole,
    dismissal: Option<DismissalKind>,
    helped: MatchSide,
    swing: f64,
}

impl MatchState {
    /// The two innings of a limited-overs game, when that is what this was.
    fn regular_innings(&self) -> Option<(&InningsState, &InningsState)> {
        let innings: Vec<&InningsState> =
            self.innings.iter().filter(|i| !i.super_over).collect();
        match innings[..] {
            [first, chase] => Some((first, chase)),
            _ => None,
        }
    }

    fn chase(&self) -> Option<Chase<'_>> {
        let (first, inn) = self.regular_innings()?;
        let overs = if inn.overs_available > 0 {
            inn.overs_available
        } else {
            self.overs_limit
        };
        if overs == 0 || inn.deliveries.is_empty() {
            return None;
        }
        let target = self.target.unwrap_or(first.runs.saturating_add(1)) as i32;
        let table = ResourceTable::default();
        let base = (target - 1).max(1) as f64;
        let start = table.resource(overs as f64, 0);
        let total_balls = overs as u16 * 6;
        let allowed = inn.wickets_allowed.max(1);

        let mut chances = vec![chase_chance(&table, base, start, target, total_balls, 0, allowed)];
        let mut needed_after = Vec::with_capacity(inn.deliveries.len());
        let mut balls_left_after = Vec::with_capacity(inn.deliveries.len());
        let (mut runs, mut legal, mut wickets) = (0i32, 0u16, 0u8);
        for d in &inn.deliveries {
            runs += d.runs as i32;
            legal += d.is_legal as u16;
            wickets += d.is_wicket as u8;
            let needed = target - runs;
            let left = total_balls.saturating_sub(legal);
            chances.push(chase_chance(&table, base, start, needed, left, wickets, allowed));
            needed_after.push(needed);
            balls_left_after.push(left);
        }
        Some(Chase { inn, chances, needed_after, balls_left_after, total_balls })
    }

    /// Every ball of the chase that moved it, with the player it belongs to.
    fn candidates(&self, chase: &Chase) -> Vec<Candidate> {
        let falls = dismissals(chase.inn);
        let mut next_fall = falls.iter();
        let mut out = Vec::new();
        for (i, d) in chase.inn.deliveries.iter().enumerate() {
            let fall = if d.is_wicket { next_fall.next() } else { None };
            let delta = chase.chances[i + 1] - chase.chances[i];
            if delta == 0.0 {
                continue;
            }
            let helped = if delta > 0.0 { chase.inn.batting } else { chase.inn.bowling };
            let credit = if let Some(w) = fall {
                // A wicket can only ever help the fielding side.
                wicket_credit(d, w).map(|(p, h, r)| (p, h, r, w.kind))
            } else if helped == chase.inn.batting {
                match (bat_runs(&d.label), d.batter_id) {
                    (Some(r), Some(b)) if r > 0 => Some((b, None, MomentRole::Batting, None)),
                    _ => None,
                }
            } else if d.is_legal {
                // A dot, or a single when a boundary was needed: the bowler's.
                d.bowler_id.map(|b| (b, None, MomentRole::Bowling, None))
            } else {
                None
            };
            if let Some((player_id, helper_id, role, dismissal)) = credit {
                out.push(Candidate {
                    index: i,
                    player_id,
                    helper_id,
                    role,
                    dismissal,
                    helped,
                    swing: delta.abs(),
                });
            }
        }
        out
    }

    /// The balls the match turned on, best first, each with the player who made
    /// it. The turning point, when there is one, leads. Empty when there was no
    /// winner, no chase, or nothing that moved it.
    pub fn magic_moments(&self) -> Vec<MagicMoment> {
        let Some(winner) = self.winner else { return Vec::new() };
        let Some(chase) = self.chase() else { return Vec::new() };
        let candidates = self.candidates(&chase);
        let loser = winner.opposite();

        // The winner's chance before the first ball, then after each.
        let w: Vec<f64> = chase
            .chances
            .iter()
            .map(|&p| if chase.inn.batting == winner { p } else { 1.0 - p })
            .collect();
        let n = chase.inn.deliveries.len();
        let (kind, range) = match (1..=n).rev().find(|&i| w[i] < 0.5) {
            Some(last) => {
                let mut first = last;
                while first > 1 && w[first - 1] < 0.5 {
                    first -= 1;
                }
                // Deliveries are 0-indexed; the series is one longer. The
                // stretch runs from the first behind-state to the ball that
                // levelled.
                (TurningKind::Comeback, (first - 1)..(last + 1).min(n))
            }
            None => (TurningKind::Decider, 0..n),
        };
        let turning = candidates
            .iter()
            .filter(|c| c.helped == winner && range.contains(&c.index) && c.swing >= MIN_SWING)
            .max_by(|a, b| a.swing.total_cmp(&b.swing));

        let mut picked: Vec<&Candidate> = turning.into_iter().collect();
        let mut rest: Vec<&Candidate> = candidates.iter().filter(|c| c.swing >= MIN_SWING).collect();
        rest.sort_by(|a, b| b.swing.total_cmp(&a.swing));
        for c in &rest {
            if picked.len() == MAX_MOMENTS {
                break;
            }
            if !picked.iter().any(|p| p.index == c.index) {
                picked.push(c);
            }
        }
        // Keep room for the losing side's best, if they had one.
        if !picked.iter().any(|c| c.helped == loser) {
            if let Some(best) = rest.iter().find(|c| c.helped == loser) {
                if picked.len() == MAX_MOMENTS {
                    picked.pop();
                }
                picked.push(best);
            }
        }

        let turning_index = turning.map(|t| t.index);
        picked
            .into_iter()
            .map(|c| {
                let d = &chase.inn.deliveries[c.index];
                let side_chance = |p: f64| if c.helped == chase.inn.batting { p } else { 1.0 - p };
                MagicMoment {
                    player_id: c.player_id,
                    helper_id: c.helper_id,
                    role: c.role,
                    side: c.helped,
                    won: c.helped == winner,
                    turning: (Some(c.index) == turning_index).then_some(kind),
                    dismissal: c.dismissal,
                    shot: d.shot.as_ref().map(|s| s.kind),
                    innings: chase.inn.index,
                    over: ball_display(d),
                    label: d.label.clone(),
                    runs: d.runs,
                    is_wicket: d.is_wicket,
                    before_percent: percent(side_chance(chase.chances[c.index])),
                    after_percent: percent(side_chance(chase.chances[c.index + 1])),
                    runs_needed: chase.needed_after[c.index].max(0) as u16,
                    balls_left: chase.balls_left_after[c.index],
                }
            })
            .collect()
    }

    /// The ball the match turned on, if there was one.
    pub fn turning_point(&self) -> Option<MagicMoment> {
        self.magic_moments().into_iter().find(|m| m.turning.is_some())
    }

    /// Recognised feats from every innings except super overs, in the order
    /// they happened.
    pub fn feats(&self) -> Vec<Feat> {
        let mut out = Vec::new();
        for inn in self.innings.iter().filter(|i| !i.super_over) {
            wicket_streaks(inn, &mut out);
            sixes_in_an_over(inn, &mut out);
            milestones_with_a_six(inn, &mut out);
            partnership_breaker(inn, &mut out);
            death_maidens(inn, self.overs_limit, &mut out);
        }
        if let (Some(winner), Some(chase)) = (self.winner, self.chase()) {
            finishes(winner, &chase, &mut out);
        }
        out
    }
}

/// Hat-tricks and two-in-twos. A wide or a no ball does not break a streak and
/// a bye does — the same rule the engine keeps for the live hat-trick ball.
fn wicket_streaks(inn: &InningsState, out: &mut Vec<Feat>) {
    let falls = dismissals(inn);
    let mut next_fall = falls.iter();
    let mut streak: BTreeMap<Uuid, (u16, String)> = BTreeMap::new();
    let flush = |bowler: Uuid, run: u16, at: String, out: &mut Vec<Feat>| {
        let kind = match run {
            3.. => FeatKind::HatTrick,
            2 => FeatKind::TwoInTwo,
            _ => return,
        };
        out.push(Feat { kind, player_id: bowler, side: inn.bowling, innings: inn.index, over: at, value: run });
    };
    for d in &inn.deliveries {
        let fall = if d.is_wicket { next_fall.next() } else { None };
        let Some(bowler) = d.bowler_id else { continue };
        let credited = fall.and_then(|w| w.kind).is_some_and(|k| k.credits_bowler());
        if credited {
            let e = streak.entry(bowler).or_insert((0, String::new()));
            e.0 += 1;
            e.1 = ball_display(d);
        } else if d.is_legal {
            if let Some((run, at)) = streak.remove(&bowler) {
                flush(bowler, run, at, out);
            }
        }
    }
    for (bowler, (run, at)) in streak {
        flush(bowler, run, at, out);
    }
}

fn sixes_in_an_over(inn: &InningsState, out: &mut Vec<Feat>) {
    let mut count: BTreeMap<(u16, Uuid), (u16, String)> = BTreeMap::new();
    for d in inn.deliveries.iter().filter(|d| d.label == "6") {
        if let Some(b) = d.batter_id {
            let e = count.entry((d.over, b)).or_insert((0, String::new()));
            e.0 += 1;
            e.1 = ball_display(d);
        }
    }
    for ((_, batter), (sixes, at)) in count {
        if sixes >= 3 {
            out.push(Feat {
                kind: FeatKind::SixesInAnOver,
                player_id: batter,
                side: inn.batting,
                innings: inn.index,
                over: at,
                value: sixes,
            });
        }
    }
}

/// Fifty or a hundred brought up with a six. Only for batters whose runs the
/// log accounts for exactly — a no ball's runs do not say whose they were, and
/// guessing would put a milestone on the wrong ball.
fn milestones_with_a_six(inn: &InningsState, out: &mut Vec<Feat>) {
    let mut total: BTreeMap<Uuid, u16> = BTreeMap::new();
    let mut untidy: BTreeSet<Uuid> = BTreeSet::new();
    for d in &inn.deliveries {
        let Some(b) = d.batter_id else { continue };
        match bat_runs(&d.label) {
            Some(r) => *total.entry(b).or_default() += r as u16,
            None if d.label.starts_with("nb") || d.label.ends_with('W') && d.label != "W" => {
                untidy.insert(b);
            }
            None => {}
        }
    }
    let exact: BTreeSet<Uuid> = inn
        .batters
        .iter()
        .filter(|s| !untidy.contains(&s.player_id) && total.get(&s.player_id) == Some(&s.runs))
        .map(|s| s.player_id)
        .collect();

    let mut running: BTreeMap<Uuid, u16> = BTreeMap::new();
    for d in &inn.deliveries {
        let (Some(b), Some(r)) = (d.batter_id, bat_runs(&d.label)) else { continue };
        let before = *running.get(&b).unwrap_or(&0);
        let after = before + r as u16;
        running.insert(b, after);
        if d.label == "6" && exact.contains(&b) && after / 50 > before / 50 {
            out.push(Feat {
                kind: FeatKind::MilestoneWithASix,
                player_id: b,
                side: inn.batting,
                innings: inn.index,
                over: ball_display(d),
                value: after / 50 * 50,
            });
        }
    }
}

/// The wicket that ended the innings' biggest stand, if it was fifty or more.
fn partnership_breaker(inn: &InningsState, out: &mut Vec<Feat>) {
    let falls = dismissals(inn);
    let wicket_balls: Vec<&DeliveryRecord> = inn.deliveries.iter().filter(|d| d.is_wicket).collect();
    let Some((i, w)) = falls
        .iter()
        .enumerate()
        .filter(|(_, w)| w.partnership >= BIG_STAND)
        .max_by_key(|(_, w)| w.partnership)
    else {
        return;
    };
    let Some(d) = wicket_balls.get(i) else { return };
    if let Some((player, _, _)) = wicket_credit(d, w) {
        out.push(Feat {
            kind: FeatKind::PartnershipBreaker,
            player_id: player,
            side: inn.bowling,
            innings: inn.index,
            over: ball_display(d),
            value: w.partnership,
        });
    }
}

/// Maidens in the last fifth of the innings — the death overs, which is where
/// a maiden is rare enough to celebrate. Byes and leg byes do not spoil one.
fn death_maidens(inn: &InningsState, overs_limit: u8, out: &mut Vec<Feat>) {
    let total = if inn.overs_available > 0 { inn.overs_available } else { overs_limit } as u16;
    if total < 10 {
        return;
    }
    let death_start = total - (total / 5).max(1);
    let mut overs: BTreeMap<u16, Vec<&DeliveryRecord>> = BTreeMap::new();
    for d in inn.deliveries.iter().filter(|d| d.over >= death_start) {
        overs.entry(d.over).or_default().push(d);
    }
    for balls in overs.values() {
        let legal = balls.iter().filter(|d| d.is_legal).count();
        let bowler = balls.first().and_then(|d| d.bowler_id);
        let one_bowler = balls.iter().all(|d| d.bowler_id == bowler);
        let conceded: u16 = balls
            .iter()
            .filter(|d| !d.label.ends_with('b') && !d.label.ends_with("lb") && !d.label.ends_with('p'))
            .map(|d| d.runs as u16)
            .sum();
        if let (6, true, 0, Some(bowler)) = (legal, one_bowler, conceded, bowler) {
            let last = balls.last().expect("six legal balls");
            out.push(Feat {
                kind: FeatKind::DeathMaiden,
                player_id: bowler,
                side: inn.bowling,
                innings: inn.index,
                over: ball_display(last),
                value: balls.iter().filter(|d| d.is_wicket).count() as u16,
            });
        }
    }
}

/// How the chase ended: won off the last ball it had, or a small total
/// defended in the last over.
fn finishes(winner: MatchSide, chase: &Chase, out: &mut Vec<Feat>) {
    let inn = chase.inn;
    let Some(last) = inn.deliveries.last() else { return };
    let used_every_ball = *chase.balls_left_after.last().unwrap_or(&1) == 0;

    if winner == inn.batting && used_every_ball {
        if let (Some(b), Some(r)) = (last.batter_id, bat_runs(&last.label)) {
            if r > 0 {
                out.push(Feat {
                    kind: FeatKind::LastBallFinish,
                    player_id: b,
                    side: inn.batting,
                    innings: inn.index,
                    over: ball_display(last),
                    value: r as u16,
                });
            }
        }
    }

    if winner == inn.bowling && used_every_ball {
        let final_over = chase.total_balls / 6 - 1;
        let Some(first) = inn.deliveries.iter().position(|d| d.over == final_over) else { return };
        let needed = if first == 0 {
            // The whole chase was one over.
            chase.needed_after.first().copied().unwrap_or(0) + inn.deliveries[0].runs as i32
        } else {
            chase.needed_after[first - 1]
        };
        let balls = &inn.deliveries[first..];
        let bowler = balls[0].bowler_id;
        if needed <= DEFENDABLE && balls.iter().all(|d| d.bowler_id == bowler) {
            if let Some(bowler) = bowler {
                out.push(Feat {
                    kind: FeatKind::LastOverDefence,
                    player_id: bowler,
                    side: inn.bowling,
                    innings: inn.index,
                    over: ball_display(last),
                    value: needed.max(0) as u16,
                });
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An innings built ball by ball, the way the engine records one.
    struct Inn {
        inn: InningsState,
    }

    impl Inn {
        fn new(index: u8, batting: MatchSide) -> Self {
            Self {
                inn: InningsState {
                    index,
                    batting,
                    bowling: batting.opposite(),
                    complete: true,
                    ..InningsState::default()
                },
            }
        }

        fn push(&mut self, label: &str, runs: u8, legal: bool, batter: Uuid, bowler: Uuid) {
            let inn = &mut self.inn;
            let over = inn.legal_balls / 6;
            let ball = (inn.legal_balls % 6) as u8 + legal as u8;
            inn.deliveries.push(DeliveryRecord {
                over,
                ball_in_over: ball,
                label: label.into(),
                runs,
                is_legal: legal,
                is_wicket: false,
                batter_id: Some(batter),
                bowler_id: Some(bowler),
                shot: None,
            });
            inn.runs += runs as u16;
            inn.partnership_runs += runs as u16;
            inn.legal_balls += legal as u16;
            if bat_runs(label).is_some() {
                let b = self.batter(batter);
                b.runs += runs as u16;
            }
        }

        fn batter(&mut self, id: Uuid) -> &mut BatterStats {
            if !self.inn.batters.iter().any(|b| b.player_id == id) {
                self.inn.batters.push(BatterStats::new(id));
            }
            self.inn.batters.iter_mut().find(|b| b.player_id == id).unwrap()
        }

        fn runs(&mut self, n: usize, runs: u8, batter: Uuid, bowler: Uuid) -> &mut Self {
            for _ in 0..n {
                self.push(&runs.to_string(), runs, true, batter, bowler);
            }
            self
        }

        fn wide(&mut self, batter: Uuid, bowler: Uuid) -> &mut Self {
            self.push("wd", 1, false, batter, bowler);
            self
        }

        fn out(
            &mut self,
            kind: DismissalKind,
            batter: Uuid,
            bowler: Uuid,
            fielder: Option<Uuid>,
        ) -> &mut Self {
            self.push("W", 0, true, batter, bowler);
            self.inn.deliveries.last_mut().unwrap().is_wicket = true;
            self.inn.wickets += 1;
            let (score, wickets, stand) = (self.inn.runs, self.inn.wickets, self.inn.partnership_runs);
            self.inn.fall.push(FallOfWicket {
                score,
                wickets,
                batter_id: batter,
                over_ball: String::new(),
                partnership_runs: stand,
                partnership_balls: 0,
            });
            self.inn.partnership_runs = 0;
            let b = self.batter(batter);
            b.out = true;
            b.dismissal = Some(kind);
            b.bowler_id = kind.credits_bowler().then_some(bowler);
            b.fielder_id = fielder;
            self
        }
    }

    fn id() -> Uuid {
        Uuid::new_v4()
    }

    /// Whether `losers` made any ball big enough to name.
    fn losers_had_a_moment(state: &MatchState, losers: MatchSide) -> bool {
        let chase = state.chase().expect("a chase");
        state
            .candidates(&chase)
            .iter()
            .any(|c| c.helped == losers && c.swing >= MIN_SWING)
    }

    /// A twenty-over game: Home made `first`, Away chased with `chase`.
    fn game(first: u16, chase: Inn, winner: Option<MatchSide>) -> MatchState {
        MatchState {
            status: MatchStatus::Complete,
            winner,
            overs_limit: 20,
            target: Some(first + 1),
            innings: vec![
                InningsState {
                    index: 0,
                    batting: MatchSide::Home,
                    bowling: MatchSide::Away,
                    runs: first,
                    legal_balls: 120,
                    complete: true,
                    ..InningsState::default()
                },
                chase.inn,
            ],
            ..MatchState::default()
        }
    }

    /// Five down for nothing, then a batter hits sixes: the turning point is
    /// the hitter's, and it is a comeback.
    #[test]
    fn a_comeback_belongs_to_the_batter_who_made_it() {
        let (hitter, seamer) = (id(), id());
        let mut c = Inn::new(1, MatchSide::Away);
        for _ in 0..5 {
            c.runs(5, 0, id(), seamer).out(DismissalKind::Bowled, id(), seamer, None);
        }
        c.runs(17, 6, hitter, seamer);
        let state = game(100, c, Some(MatchSide::Away));

        let moments = state.magic_moments();
        let turn = &moments[0];
        assert_eq!(turn.turning, Some(TurningKind::Comeback));
        assert_eq!(turn.player_id, hitter);
        assert_eq!(turn.role, MomentRole::Batting);
        assert!(turn.won && turn.after_percent > turn.before_percent);
        assert!(moments.len() <= MAX_MOMENTS);
        assert_eq!(state.turning_point().unwrap().player_id, hitter);
        // The bowlers who had them five down made the losers' moment.
        assert!(losers_had_a_moment(&state, MatchSide::Home));
        let theirs = moments.iter().find(|m| !m.won).expect("the losers keep their best");
        assert_eq!((theirs.player_id, theirs.role), (seamer, MomentRole::Bowling));
    }

    /// A coin-toss chase collapses. The wickets are the bowler's moments, the
    /// catcher is named with them, and the losing side still gets its best.
    #[test]
    fn a_collapse_belongs_to_the_bowler_and_the_losers_keep_one() {
        let (opener, quick, keeper) = (id(), id(), id());
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(40, 2, opener, id()).runs(20, 0, opener, id());
        for i in 0..5 {
            let kind = if i % 2 == 0 { DismissalKind::Caught } else { DismissalKind::Bowled };
            c.out(kind, id(), quick, (kind == DismissalKind::Caught).then_some(keeper));
        }
        c.runs(35, 0, id(), quick);
        let state = game(150, c, Some(MatchSide::Home));

        let moments = state.magic_moments();
        let turn = moments.iter().find(|m| m.turning.is_some()).expect("it turned");
        assert_eq!(turn.player_id, quick);
        assert_eq!(turn.role, MomentRole::Bowling);
        assert!(turn.is_wicket && turn.won);
        if turn.dismissal == Some(DismissalKind::Caught) {
            assert_eq!(turn.helper_id, Some(keeper));
        }
        assert_eq!(
            moments.iter().any(|m| !m.won),
            losers_had_a_moment(&state, MatchSide::Away),
            "the losers' best is kept when they had one"
        );
        assert!(moments.iter().all(|m| m.after_percent > m.before_percent));
    }

    #[test]
    fn a_run_out_is_the_fielders_moment() {
        let (fielder, bowler) = (id(), id());
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(40, 2, id(), bowler).runs(20, 0, id(), bowler);
        // At a coin toss the first few wickets each move it a little; five in
        // a row move it a lot.
        for _ in 0..5 {
            c.out(DismissalKind::RunOut, id(), bowler, Some(fielder));
        }
        c.runs(35, 0, id(), bowler);
        let state = game(150, c, Some(MatchSide::Home));

        let fielding: Vec<_> =
            state.magic_moments().into_iter().filter(|m| m.role == MomentRole::Fielding).collect();
        assert!(!fielding.is_empty());
        assert!(fielding.iter().all(|m| m.player_id == fielder));
        assert!(
            !state.feats().iter().any(|f| f.kind == FeatKind::HatTrick),
            "run-outs are not the bowler's hat-trick"
        );
    }

    #[test]
    fn extras_are_nobodys_moment() {
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(30, 0, id(), id());
        for _ in 0..40 {
            c.wide(id(), id());
        }
        let state = game(30, c, Some(MatchSide::Away));
        assert!(state.magic_moments().iter().all(|m| m.role != MomentRole::Batting || m.runs > 0));
        assert!(state.magic_moments().iter().all(|m| m.label != "wd"));
    }

    #[test]
    fn no_winner_no_moments() {
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(17, 6, id(), id());
        let state = game(100, c, None);
        assert!(state.magic_moments().is_empty());
        assert!(MatchState::default().magic_moments().is_empty());
    }

    #[test]
    fn a_hat_trick_survives_a_wide_but_not_a_dot() {
        let spinner = id();
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(6, 1, id(), id());
        c.out(DismissalKind::Bowled, id(), spinner, None).wide(id(), spinner);
        c.out(DismissalKind::Lbw, id(), spinner, None);
        c.out(DismissalKind::Stumped, id(), spinner, Some(id()));
        c.runs(1, 0, id(), spinner);
        c.out(DismissalKind::Bowled, id(), spinner, None);
        c.out(DismissalKind::Bowled, id(), spinner, None);
        let state = game(100, c, Some(MatchSide::Home));

        let feats = state.feats();
        let hat = feats.iter().find(|f| f.kind == FeatKind::HatTrick).expect("three in a row");
        assert_eq!((hat.player_id, hat.value), (spinner, 3));
        assert!(feats.iter().any(|f| f.kind == FeatKind::TwoInTwo && f.player_id == spinner));
    }

    #[test]
    fn three_sixes_in_an_over_and_a_fifty_with_one() {
        let slogger = id();
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(11, 4, slogger, id()); // 44 off 11
        c.runs(1, 6, slogger, id()); // 50 with a six, the last ball of the second over
        c.runs(3, 6, slogger, id()); // three sixes in the third
        let state = game(200, c, Some(MatchSide::Home));

        let feats = state.feats();
        let fifty = feats.iter().find(|f| f.kind == FeatKind::MilestoneWithASix).expect("fifty");
        assert_eq!((fifty.player_id, fifty.value, fifty.over.as_str()), (slogger, 50, "1.6"));
        let sixes = feats.iter().find(|f| f.kind == FeatKind::SixesInAnOver).expect("sixes");
        assert_eq!(sixes.value, 3);
    }

    #[test]
    fn the_big_stand_is_broken_by_someone() {
        let (bowler, catcher) = (id(), id());
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(30, 2, id(), id()); // a stand of 60
        c.out(DismissalKind::Caught, id(), bowler, Some(catcher));
        let state = game(200, c, Some(MatchSide::Home));
        let f = state.feats().into_iter().find(|f| f.kind == FeatKind::PartnershipBreaker).unwrap();
        assert_eq!((f.player_id, f.value), (bowler, 60));
    }

    #[test]
    fn a_maiden_at_the_death() {
        let miser = id();
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(96, 1, id(), id()); // sixteen overs
        c.runs(5, 0, id(), miser).out(DismissalKind::Bowled, id(), miser, None);
        c.runs(18, 1, id(), id());
        let state = game(200, c, Some(MatchSide::Home));
        let f = state.feats().into_iter().find(|f| f.kind == FeatKind::DeathMaiden).unwrap();
        assert_eq!((f.player_id, f.value), (miser, 1));
    }

    #[test]
    fn a_last_ball_finish_and_a_last_over_defence() {
        let finisher = id();
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(119, 1, id(), id()).runs(1, 2, finisher, id()); // 121 off 120
        let state = game(120, c, Some(MatchSide::Away));
        let f = state.feats().into_iter().find(|f| f.kind == FeatKind::LastBallFinish).unwrap();
        assert_eq!((f.player_id, f.value), (finisher, 2));

        let closer = id();
        let mut c = Inn::new(1, MatchSide::Away);
        c.runs(114, 1, id(), id()).runs(6, 1, id(), closer); // needed 7 off the last
        let state = game(120, c, Some(MatchSide::Home));
        let f = state.feats().into_iter().find(|f| f.kind == FeatKind::LastOverDefence).unwrap();
        assert_eq!((f.player_id, f.value), (closer, 7));
    }

    #[test]
    fn the_chance_is_monotone_in_what_is_needed() {
        let t = ResourceTable::default();
        let start = t.resource(20.0, 0);
        let easy = chase_chance(&t, 150.0, start, 20, 60, 2, 10);
        let hard = chase_chance(&t, 150.0, start, 90, 60, 2, 10);
        assert!(easy > 0.5 && hard < 0.5 && easy > hard);
        assert_eq!(chase_chance(&t, 150.0, start, 0, 0, 10, 10), 1.0);
        assert_eq!(chase_chance(&t, 150.0, start, 5, 0, 3, 10), 0.0);
    }
}
