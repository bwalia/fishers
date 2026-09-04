//! Running a tournament: entrants into groups, groups into a schedule across
//! pitches and time slots, results into a table.
//!
//! All of it is deterministic and unit-tested — a fixture list you cannot
//! reproduce is one nobody trusts.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TournamentFormat {
    /// No structure — just a set of fixtures in a block.
    None,
    /// Everyone plays everyone once.
    RoundRobin,
    /// Group stage, then a knockout between the qualifiers.
    GroupsKnockout,
    /// Straight knockout from seeds.
    Knockout,
    /// Standing ladder — challenges rather than a fixed list.
    Ladder,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entrant {
    pub id: Uuid,
    pub name: String,
    /// 1 is the strongest. Unseeded entrants sort after seeded ones.
    pub seed: Option<i32>,
    pub group_label: Option<String>,
}

/// One fixture the generator produced. `None` on either side is a bye.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct GeneratedFixture {
    pub home: Option<Uuid>,
    pub away: Option<Uuid>,
    /// Group stage round, or knockout round (1 = first round).
    pub round: usize,
    pub group_label: Option<String>,
    /// `group` | `knockout`
    pub stage: String,
}

impl GeneratedFixture {
    pub fn is_bye(&self) -> bool {
        self.home.is_none() || self.away.is_none()
    }
}

/// Snake-seed entrants into groups: 1→A, 2→B, 3→C, 4→C, 5→B, 6→A, so the
/// strong sides are spread rather than stacked.
pub fn allocate_groups(entrants: &[Entrant], group_count: usize) -> Vec<(Uuid, String)> {
    if group_count <= 1 {
        return entrants
            .iter()
            .map(|e| (e.id, "A".to_string()))
            .collect();
    }

    let mut ordered = entrants.to_vec();
    ordered.sort_by(|a, b| {
        a.seed
            .unwrap_or(i32::MAX)
            .cmp(&b.seed.unwrap_or(i32::MAX))
            .then_with(|| a.name.cmp(&b.name))
    });

    ordered
        .into_iter()
        .enumerate()
        .map(|(index, entrant)| {
            let pass = index / group_count;
            let position = index % group_count;
            // Reverse every other pass — that's what makes it a snake.
            let group = if pass % 2 == 0 {
                position
            } else {
                group_count - 1 - position
            };
            (entrant.id, group_letter(group))
        })
        .collect()
}

fn group_letter(index: usize) -> String {
    // A..Z, then A1, B1… for the rare 27-group tournament.
    let letter = (b'A' + (index % 26) as u8) as char;
    if index < 26 {
        letter.to_string()
    } else {
        format!("{letter}{}", index / 26)
    }
}

/// Everyone plays everyone once, by the circle method, so each round pairs the
/// whole field and nobody plays twice in a round. An odd field gives one bye
/// per round.
pub fn round_robin(entrants: &[Uuid], group_label: Option<String>) -> Vec<GeneratedFixture> {
    if entrants.len() < 2 {
        return Vec::new();
    }

    let mut field: Vec<Option<Uuid>> = entrants.iter().copied().map(Some).collect();
    if field.len() % 2 == 1 {
        field.push(None); // the bye
    }

    let teams = field.len();
    let rounds = teams - 1;
    let half = teams / 2;
    let mut fixtures = Vec::with_capacity(rounds * half);

    for round in 0..rounds {
        for pair in 0..half {
            let home = field[pair];
            let away = field[teams - 1 - pair];
            // Alternate home and away so the same side isn't always first.
            let (home, away) = if round % 2 == 0 { (home, away) } else { (away, home) };
            fixtures.push(GeneratedFixture {
                home,
                away,
                round: round + 1,
                group_label: group_label.clone(),
                stage: "group".into(),
            });
        }
        // Rotate all but the first entry.
        let last = field.pop().expect("field is not empty");
        field.insert(1, last);
    }

    fixtures
}

/// A knockout bracket. The field is padded to a power of two with byes, and
/// seeds are paired 1 v last, 2 v second-last, so the top seeds meet late.
pub fn knockout(entrants: &[Entrant]) -> Vec<GeneratedFixture> {
    if entrants.len() < 2 {
        return Vec::new();
    }

    let mut ordered = entrants.to_vec();
    ordered.sort_by(|a, b| {
        a.seed
            .unwrap_or(i32::MAX)
            .cmp(&b.seed.unwrap_or(i32::MAX))
            .then_with(|| a.name.cmp(&b.name))
    });

    let mut size = 1;
    while size < ordered.len() {
        size *= 2;
    }

    let mut slots: Vec<Option<Uuid>> = ordered.iter().map(|e| Some(e.id)).collect();
    slots.resize(size, None);

    let mut fixtures = Vec::with_capacity(size / 2);
    for pair in 0..size / 2 {
        fixtures.push(GeneratedFixture {
            home: slots[pair],
            away: slots[size - 1 - pair],
            round: 1,
            group_label: None,
            stage: "knockout".into(),
        });
    }
    fixtures
}

/// A slot on the grid: a pitch or court, for a window of time.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Slot {
    pub id: Uuid,
    pub court_label: String,
    pub starts_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScheduledFixture {
    pub fixture: GeneratedFixture,
    pub slot: Slot,
}

#[derive(Debug, Clone, Serialize)]
pub struct Schedule {
    pub scheduled: Vec<ScheduledFixture>,
    /// Fixtures the grid couldn't fit — the organiser needs to know, not guess.
    pub unscheduled: Vec<GeneratedFixture>,
    pub byes: Vec<GeneratedFixture>,
}

/// Build the timetable. A side is never in two places at once, and gets
/// `min_rest` between games. Slots are filled earliest first.
pub fn build_schedule(
    fixtures: &[GeneratedFixture],
    slots: &[Slot],
    min_rest: Duration,
) -> Schedule {
    let mut slots: Vec<Slot> = slots.to_vec();
    slots.sort_by(|a, b| {
        a.starts_at
            .cmp(&b.starts_at)
            .then_with(|| a.court_label.cmp(&b.court_label))
    });

    let (byes, playable): (Vec<GeneratedFixture>, Vec<GeneratedFixture>) =
        fixtures.iter().cloned().partition(GeneratedFixture::is_bye);

    // Round order keeps a group stage coherent: round 1 before round 2.
    let mut queue = playable;
    queue.sort_by_key(|f| f.round);

    let mut scheduled: Vec<ScheduledFixture> = Vec::new();
    let mut unscheduled: Vec<GeneratedFixture> = Vec::new();
    let mut used: Vec<bool> = vec![false; slots.len()];
    // When each entrant is next free.
    let mut free_from: std::collections::HashMap<Uuid, DateTime<Utc>> =
        std::collections::HashMap::new();

    for fixture in queue {
        let sides: Vec<Uuid> = [fixture.home, fixture.away].into_iter().flatten().collect();
        let mut placed = false;

        for (index, slot) in slots.iter().enumerate() {
            if used[index] {
                continue;
            }
            let clash = sides.iter().any(|side| {
                free_from
                    .get(side)
                    .is_some_and(|free| *free > slot.starts_at)
            });
            if clash {
                continue;
            }
            used[index] = true;
            for side in &sides {
                free_from.insert(*side, slot.ends_at + min_rest);
            }
            scheduled.push(ScheduledFixture {
                fixture: fixture.clone(),
                slot: slot.clone(),
            });
            placed = true;
            break;
        }

        if !placed {
            unscheduled.push(fixture);
        }
    }

    Schedule {
        scheduled,
        unscheduled,
        byes,
    }
}

/// Generate an evenly spaced grid: `courts` × `count` slots of `minutes`.
pub fn generate_slots(
    courts: &[String],
    first_start: DateTime<Utc>,
    minutes: i64,
    gap_minutes: i64,
    rounds: usize,
) -> Vec<Slot> {
    let mut slots = Vec::with_capacity(courts.len() * rounds);
    for round in 0..rounds {
        let starts_at = first_start + Duration::minutes((minutes + gap_minutes) * round as i64);
        for court in courts {
            slots.push(Slot {
                id: Uuid::new_v4(),
                court_label: court.clone(),
                starts_at,
                ends_at: starts_at + Duration::minutes(minutes),
            });
        }
    }
    slots
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct PointsRules {
    pub win: i32,
    pub draw: i32,
    pub no_result: i32,
}

impl Default for PointsRules {
    fn default() -> Self {
        // Cricket league convention; football clubs set 3/1/0.
        Self { win: 2, draw: 1, no_result: 1 }
    }
}

impl PointsRules {
    pub fn points_for(&self, result: &str) -> i32 {
        match result {
            "win" => self.win,
            "draw" => self.draw,
            "no_result" => self.no_result,
            _ => 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Standing {
    pub entrant_id: Uuid,
    pub name: String,
    pub group_label: Option<String>,
    pub played: i64,
    pub won: i64,
    pub lost: i64,
    pub drawn: i64,
    pub no_result: i64,
    pub points: i64,
    pub scored: i64,
    pub conceded: i64,
}

impl Standing {
    pub fn difference(&self) -> i64 {
        self.scored - self.conceded
    }
}

/// Order a table: points, then difference, then scored, then name.
pub fn order_standings(standings: &mut [Standing]) {
    standings.sort_by(|a, b| {
        b.points
            .cmp(&a.points)
            .then_with(|| b.difference().cmp(&a.difference()))
            .then_with(|| b.scored.cmp(&a.scored))
            .then_with(|| a.name.cmp(&b.name))
    });
}

/// Who goes through from the groups: the top `per_group`, ordered so that
/// group winners are seeded above runners-up for the knockout.
pub fn qualifiers(standings: &[Standing], per_group: usize) -> Vec<Entrant> {
    let mut by_group: std::collections::BTreeMap<String, Vec<Standing>> = Default::default();
    for standing in standings {
        by_group
            .entry(standing.group_label.clone().unwrap_or_else(|| "A".into()))
            .or_default()
            .push(standing.clone());
    }

    let mut placed: Vec<(usize, Standing)> = Vec::new();
    for group in by_group.values_mut() {
        order_standings(group);
        for (position, standing) in group.iter().take(per_group).enumerate() {
            placed.push((position, standing.clone()));
        }
    }

    // All the winners first, then all the runners-up, and so on.
    placed.sort_by(|a, b| {
        a.0.cmp(&b.0)
            .then_with(|| b.1.points.cmp(&a.1.points))
            .then_with(|| a.1.name.cmp(&b.1.name))
    });

    placed
        .into_iter()
        .enumerate()
        .map(|(index, (_, standing))| Entrant {
            id: standing.entrant_id,
            name: standing.name,
            seed: Some(index as i32 + 1),
            group_label: standing.group_label,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn entrant(name: &str, seed: Option<i32>) -> Entrant {
        Entrant {
            id: Uuid::new_v4(),
            name: name.into(),
            seed,
            group_label: None,
        }
    }

    fn field(count: usize) -> Vec<Entrant> {
        (1..=count)
            .map(|i| entrant(&format!("Club {i}"), Some(i as i32)))
            .collect()
    }

    fn start() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 4, 9, 0, 0).unwrap()
    }

    #[test]
    fn round_robin_pairs_everyone_exactly_once() {
        let ids: Vec<Uuid> = field(6).into_iter().map(|e| e.id).collect();
        let fixtures = round_robin(&ids, None);
        assert_eq!(fixtures.len(), 15, "6 entrants play 15 games");

        let mut seen = std::collections::HashSet::new();
        for fixture in &fixtures {
            let (a, b) = (fixture.home.unwrap(), fixture.away.unwrap());
            let key = if a < b { (a, b) } else { (b, a) };
            assert!(seen.insert(key), "no pairing repeats");
        }
        assert_eq!(seen.len(), 15);
    }

    #[test]
    fn round_robin_never_plays_a_side_twice_in_a_round() {
        let ids: Vec<Uuid> = field(8).into_iter().map(|e| e.id).collect();
        let fixtures = round_robin(&ids, None);
        for round in 1..=7 {
            let mut playing = std::collections::HashSet::new();
            for fixture in fixtures.iter().filter(|f| f.round == round) {
                for side in [fixture.home, fixture.away].into_iter().flatten() {
                    assert!(playing.insert(side), "a side appears twice in round {round}");
                }
            }
        }
    }

    #[test]
    fn odd_field_gives_one_bye_per_round() {
        let ids: Vec<Uuid> = field(5).into_iter().map(|e| e.id).collect();
        let fixtures = round_robin(&ids, None);
        for round in 1..=5 {
            let byes = fixtures
                .iter()
                .filter(|f| f.round == round && f.is_bye())
                .count();
            assert_eq!(byes, 1, "round {round} has exactly one bye");
        }
    }

    #[test]
    fn groups_are_snake_seeded_and_evenly_sized() {
        let entrants = field(8);
        let allocation = allocate_groups(&entrants, 2);
        assert_eq!(allocation.len(), 8);

        let group_of = |name: &str| {
            let id = entrants.iter().find(|e| e.name == name).unwrap().id;
            allocation.iter().find(|(a, _)| *a == id).unwrap().1.clone()
        };
        // Seeds 1 and 2 must not share a group.
        assert_ne!(group_of("Club 1"), group_of("Club 2"));
        // Snake: seed 1 and seed 4 land together, 2 with 3.
        assert_eq!(group_of("Club 1"), group_of("Club 4"));
        assert_eq!(group_of("Club 2"), group_of("Club 3"));

        let mut counts: std::collections::HashMap<String, usize> = Default::default();
        for (_, group) in &allocation {
            *counts.entry(group.clone()).or_insert(0) += 1;
        }
        assert_eq!(counts.len(), 2);
        assert!(counts.values().all(|c| *c == 4));
    }

    #[test]
    fn knockout_pads_to_a_power_of_two_and_seeds_top_against_bottom() {
        let entrants = field(6);
        let bracket = knockout(&entrants);
        assert_eq!(bracket.len(), 4, "6 entrants become an 8-slot bracket");
        assert_eq!(bracket.iter().filter(|f| f.is_bye()).count(), 2);

        let top = entrants.iter().find(|e| e.seed == Some(1)).unwrap().id;
        let first = &bracket[0];
        assert_eq!(first.home, Some(top), "top seed opens the bracket");
        assert!(first.is_bye(), "and gets the bye in a 6-side draw");
    }

    #[test]
    fn schedule_never_puts_a_side_in_two_places_at_once() {
        let entrants = field(4);
        let ids: Vec<Uuid> = entrants.iter().map(|e| e.id).collect();
        let fixtures = round_robin(&ids, Some("A".into()));
        let slots = generate_slots(
            &["Pitch 1".into(), "Pitch 2".into()],
            start(),
            60,
            15,
            3,
        );

        let schedule = build_schedule(&fixtures, &slots, Duration::minutes(0));
        assert!(schedule.unscheduled.is_empty(), "all six games fit");

        for entrant in ids {
            let mut windows: Vec<(DateTime<Utc>, DateTime<Utc>)> = schedule
                .scheduled
                .iter()
                .filter(|s| s.fixture.home == Some(entrant) || s.fixture.away == Some(entrant))
                .map(|s| (s.slot.starts_at, s.slot.ends_at))
                .collect();
            windows.sort();
            for pair in windows.windows(2) {
                assert!(pair[0].1 <= pair[1].0, "overlapping games for one side");
            }
        }
    }

    #[test]
    fn schedule_respects_a_rest_gap() {
        let entrants = field(4);
        let ids: Vec<Uuid> = entrants.iter().map(|e| e.id).collect();
        let fixtures = round_robin(&ids, None);
        let slots = generate_slots(&["Pitch 1".into(), "Pitch 2".into()], start(), 60, 0, 6);

        let rest = Duration::minutes(30);
        let schedule = build_schedule(&fixtures, &slots, rest);

        for entrant in ids {
            let mut windows: Vec<(DateTime<Utc>, DateTime<Utc>)> = schedule
                .scheduled
                .iter()
                .filter(|s| s.fixture.home == Some(entrant) || s.fixture.away == Some(entrant))
                .map(|s| (s.slot.starts_at, s.slot.ends_at))
                .collect();
            windows.sort();
            for pair in windows.windows(2) {
                assert!(
                    pair[1].0 - pair[0].1 >= rest,
                    "a side played again without the rest gap"
                );
            }
        }
    }

    #[test]
    fn a_grid_too_small_reports_what_did_not_fit() {
        let ids: Vec<Uuid> = field(6).into_iter().map(|e| e.id).collect();
        let fixtures = round_robin(&ids, None);
        let slots = generate_slots(&["Pitch 1".into()], start(), 60, 0, 3);

        let schedule = build_schedule(&fixtures, &slots, Duration::minutes(0));
        assert_eq!(schedule.scheduled.len(), 3);
        assert_eq!(schedule.unscheduled.len(), 12, "the rest is reported, not dropped");
    }

    #[test]
    fn slot_generation_lays_out_courts_and_times() {
        let slots = generate_slots(&["Court 1".into(), "Court 2".into()], start(), 45, 15, 3);
        assert_eq!(slots.len(), 6);
        assert_eq!(slots[0].starts_at, start());
        assert_eq!(slots[0].ends_at, start() + Duration::minutes(45));
        // Third slot is the second round on court 1: 45 + 15 minutes later.
        assert_eq!(slots[2].starts_at, start() + Duration::minutes(60));
    }

    fn standing(name: &str, group: &str, points: i64, scored: i64, conceded: i64) -> Standing {
        Standing {
            entrant_id: Uuid::new_v4(),
            name: name.into(),
            group_label: Some(group.into()),
            played: 3,
            won: 0,
            lost: 0,
            drawn: 0,
            no_result: 0,
            points,
            scored,
            conceded,
        }
    }

    #[test]
    fn table_orders_by_points_then_difference() {
        let mut table = vec![
            standing("Level on points, worse diff", "A", 4, 100, 90),
            standing("Top", "A", 6, 100, 50),
            standing("Level on points, better diff", "A", 4, 100, 60),
        ];
        order_standings(&mut table);
        assert_eq!(table[0].name, "Top");
        assert_eq!(table[1].name, "Level on points, better diff");
    }

    #[test]
    fn qualifiers_put_group_winners_above_runners_up() {
        let table = vec![
            standing("A winner", "A", 6, 100, 40),
            standing("A second", "A", 4, 80, 60),
            standing("B winner", "B", 6, 90, 50),
            standing("B second", "B", 2, 60, 80),
        ];
        let through = qualifiers(&table, 2);
        assert_eq!(through.len(), 4);
        let names: Vec<&str> = through.iter().map(|e| e.name.as_str()).collect();
        assert!(names[0].contains("winner") && names[1].contains("winner"));
        assert!(names[2].contains("second") && names[3].contains("second"));
        assert_eq!(through[0].seed, Some(1));
    }

    #[test]
    fn points_rules_follow_the_sport() {
        let cricket = PointsRules::default();
        assert_eq!(cricket.points_for("win"), 2);
        assert_eq!(cricket.points_for("no_result"), 1);

        let football = PointsRules { win: 3, draw: 1, no_result: 0 };
        assert_eq!(football.points_for("win"), 3);
        assert_eq!(football.points_for("loss"), 0);
    }
}

// MARK: API shapes

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct TournamentEntrant {
    pub id: Uuid,
    pub block_id: Uuid,
    pub name: String,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub seed: Option<i32>,
    pub group_label: Option<String>,
    pub contact_name: Option<String>,
    pub contact_email: Option<String>,
    pub withdrawn: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AddEntrantsRequest {
    /// Sides entering. A visiting club with no account here is just a name.
    pub entrants: Vec<NewEntrant>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct NewEntrant {
    pub name: String,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub seed: Option<i32>,
    pub contact_name: Option<String>,
    pub contact_email: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GenerateSlotsRequest {
    /// "Pitch 1", "Court 2"… one slot per court per round.
    pub courts: Vec<String>,
    pub first_start: DateTime<Utc>,
    pub match_minutes: i64,
    #[serde(default)]
    pub gap_minutes: i64,
    pub rounds: usize,
    pub venue_id: Option<Uuid>,
    /// Replace the existing grid rather than adding to it.
    #[serde(default)]
    pub replace: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GenerateScheduleRequest {
    /// Overrides the block's stored format for this run.
    pub format: Option<TournamentFormat>,
    pub group_count: Option<usize>,
    #[serde(default = "default_rest")]
    pub min_rest_minutes: i64,
    /// Write the fixtures. Without this it's a preview.
    #[serde(default)]
    pub commit: bool,
}

fn default_rest() -> i64 {
    30
}

#[derive(Debug, Clone, Deserialize)]
pub struct GenerateKnockoutRequest {
    /// How many go through from each group.
    #[serde(default = "default_per_group")]
    pub per_group: usize,
    pub first_start: Option<DateTime<Utc>>,
    #[serde(default)]
    pub commit: bool,
}

fn default_per_group() -> usize {
    2
}

#[derive(Debug, Clone, Deserialize)]
pub struct RecordResultRequest {
    /// One line per entrant. Draws and no-results are supported because rain is.
    pub entrants: Vec<EntrantResult>,
    pub summary: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EntrantResult {
    pub entrant_id: Uuid,
    pub score: Option<i32>,
    /// `win` | `loss` | `draw` | `no_result`
    pub result: String,
    /// Cricket wants more than a number: overs, wickets, a scorecard.
    pub score_detail: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UpdateBlockRequest {
    pub name: Option<String>,
    pub format: Option<TournamentFormat>,
    pub group_count: Option<i32>,
    pub points_win: Option<i32>,
    pub points_draw: Option<i32>,
    pub points_no_result: Option<i32>,
    pub meet_point: Option<String>,
    pub departs_at: Option<DateTime<Utc>>,
    pub travel_notes: Option<String>,
    pub accommodation_notes: Option<String>,
    pub cost_cents: Option<i32>,
}

/// One fixture in a running tournament, as the app displays it.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct ScheduleRow {
    pub event_id: Uuid,
    pub title: String,
    pub starts_at: DateTime<Utc>,
    pub court_label: Option<String>,
    pub stage: Option<String>,
    pub round: Option<i32>,
    pub group_label: Option<String>,
    pub home_name: Option<String>,
    pub away_name: Option<String>,
    pub home_score: Option<i32>,
    pub away_score: Option<i32>,
    pub home_result: Option<String>,
    pub status: String,
}

// MARK: ticketed club events

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct EventTicket {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub name: Option<String>,
    pub guests: i32,
    pub guest_names: Option<String>,
    pub amount_cents: i32,
    pub currency: String,
    /// `reserved` | `paid` | `cancelled`
    pub status: String,
    pub notes: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BookTicketRequest {
    #[serde(default)]
    pub guests: i32,
    pub guest_names: Option<String>,
    pub notes: Option<String>,
}

/// Headcount and money for a ticketed event.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct TicketSummary {
    pub event_id: Uuid,
    pub title: String,
    pub ticket_capacity: Option<i32>,
    pub ticket_price_cents: Option<i32>,
    pub bookings: i64,
    pub headcount: i64,
    pub collected_cents: i64,
    pub outstanding_cents: i64,
}
