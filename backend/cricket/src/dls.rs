//! Duckworth–Lewis–Stern par scores.
//!
//! # What this is, precisely
//!
//! The ICC's DLS *Standard Edition* resource table is licensed and is not
//! reproduced here. What ships is the published Duckworth–Lewis functional
//! form with parameters fitted to that table:
//!
//! ```text
//! Z(u, w) = F(w) · [1 − exp(−b · u / F(w))]
//! resource%(u, w) = Z(u, w) / Z(50, 0) × 100
//! ```
//!
//! `b = 0.0275` reproduces the published zero-wicket column to within 0.1
//! percentage points at every five-over mark from 5 to 50 overs (the one
//! exception is 10 overs, where it reads 32.2% against a published 34.1%).
//! The wicket factors `F(w)` are solved so the fifty-over column matches the
//! published figures for each number of wickets down.
//!
//! That makes it a faithful *approximation*, good enough for a club deciding
//! whether it is ahead of the rate — and it is labelled as such everywhere it
//! surfaces. A league that holds the official table can call
//! [`ResourceTable::from_rows`] with it and the arithmetic is unchanged; the
//! reported [`DlsPar::method`] then says so.
//!
//! The *arithmetic* around the table is exact, and is the part that decides
//! matches:
//!
//! - par at any point  = S₁ × (resources team 2 has used) / (resources team 1 had)
//! - target, R₂ ≤ R₁   = S₁ × R₂ / R₁, rounded down, plus one
//! - target, R₂ > R₁   = S₁ + G50 × (R₂ − R₁) / 100, plus one

use serde::{Deserialize, Serialize};

/// Average first-innings score in a full 50-over innings, used only when the
/// side batting second has *more* resources than the side batting first.
pub const DEFAULT_G50: f64 = 245.0;

const DECAY: f64 = 0.0275;
const REFERENCE_OVERS: f64 = 50.0;

/// Capacity remaining with `w` wickets down, as a fraction of the zero-wicket
/// figure. Solved so `resource(50, w)` matches the published table.
const WICKET_FACTORS: [f64; 10] = [
    1.0000, 0.8850, 0.7610, 0.6310, 0.5005, 0.3760, 0.2621, 0.1645, 0.0889, 0.0351,
];

/// How resources were looked up, so a scorecard can say what it used.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DlsMethod {
    /// The fitted curve described in this module.
    StandardApproximation,
    /// A table supplied by the operator — presumably the official one.
    SuppliedTable,
}

impl DlsMethod {
    pub fn label(self) -> &'static str {
        match self {
            Self::StandardApproximation => "DLS (Standard Edition approximation)",
            Self::SuppliedTable => "DLS (supplied resource table)",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ResourceTable {
    method: DlsMethod,
    /// `rows[overs][wickets]` as a percentage, when supplied explicitly.
    rows: Option<Vec<[f64; 10]>>,
}

impl Default for ResourceTable {
    fn default() -> Self {
        Self {
            method: DlsMethod::StandardApproximation,
            rows: None,
        }
    }
}

impl ResourceTable {
    /// Use an operator-supplied table. `rows[o]` is the resource percentage
    /// with `o` whole overs remaining and 0..=9 wickets down; index 0 must be
    /// all zeroes. Fractional overs are interpolated linearly.
    pub fn from_rows(rows: Vec<[f64; 10]>) -> Result<Self, String> {
        if rows.len() < 2 {
            return Err("a resource table needs at least two rows".into());
        }
        if rows[0].iter().any(|v| *v != 0.0) {
            return Err("with no overs left, every resource is zero".into());
        }
        Ok(Self {
            method: DlsMethod::SuppliedTable,
            rows: Some(rows),
        })
    }

    pub fn method(&self) -> DlsMethod {
        self.method
    }

    /// Resource percentage with `overs` (possibly fractional) remaining and
    /// `wickets` down. Zero once ten are down or the overs run out.
    pub fn resource(&self, overs: f64, wickets: u8) -> f64 {
        if overs <= 0.0 || wickets >= 10 {
            return 0.0;
        }
        match &self.rows {
            Some(rows) => {
                let w = wickets as usize;
                let max = rows.len() - 1;
                let overs = overs.min(max as f64);
                let lower = overs.floor() as usize;
                let upper = (lower + 1).min(max);
                let fraction = overs - lower as f64;
                rows[lower][w] * (1.0 - fraction) + rows[upper][w] * fraction
            }
            None => {
                let f = WICKET_FACTORS[wickets as usize];
                let z = f * (1.0 - (-DECAY * overs / f).exp());
                let full = 1.0 * (1.0 - (-DECAY * REFERENCE_OVERS).exp());
                z / full * 100.0
            }
        }
    }
}

/// One innings as DLS sees it.
#[derive(Debug, Clone, Copy)]
pub struct InningsResources {
    pub overs_available: f64,
    pub overs_remaining: f64,
    pub wickets_lost: u8,
}

impl InningsResources {
    /// Resources the innings started with.
    pub fn total(&self, table: &ResourceTable) -> f64 {
        table.resource(self.overs_available, 0)
    }

    /// Resources it has spent so far.
    pub fn used(&self, table: &ResourceTable) -> f64 {
        (self.total(table) - table.resource(self.overs_remaining, self.wickets_lost)).max(0.0)
    }
}

/// Where the chase stands: what it should be on now, and what it needs to win.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct DlsPar {
    /// The score the chasing side should be on right now to be level.
    pub par: i32,
    /// Runs ahead of (or behind) par.
    pub ahead_by: i32,
    /// The full target, if the match plays to its revised end.
    pub target: i32,
    /// Resources the side batting first had, as a percentage.
    pub resources_first: f64,
    /// Resources the chasing side started with.
    pub resources_second: f64,
    /// Resources the chasing side has used.
    pub resources_used: f64,
    pub method: DlsMethod,
    /// True when the chase has more resources than the side batting first, so
    /// G50 enters the target rather than a straight ratio.
    pub used_g50: bool,
}

impl DlsPar {
    /// "Lords are 12 ahead of the DLS par of 84" — the line a scoreboard shows.
    pub fn summary(&self) -> String {
        match self.ahead_by {
            0 => format!("Level with the DLS par of {}", self.par),
            n if n > 0 => format!("{n} ahead of the DLS par of {}", self.par),
            n => format!("{} behind the DLS par of {}", -n, self.par),
        }
    }
}

/// Par and target for a side batting second.
///
/// `first_innings_score` is what they are chasing. Both innings are described
/// by their resources; a rain-shortened chase is expressed by a smaller
/// `overs_available` on the second.
pub fn par_score(
    table: &ResourceTable,
    g50: f64,
    first_innings_score: u16,
    first: InningsResources,
    second: InningsResources,
    second_innings_score: u16,
) -> Option<DlsPar> {
    let r1 = first.total(table) - table.resource(first.overs_remaining, first.wickets_lost);
    // A side that batted its overs out used everything it had.
    let r1 = if r1 <= 0.0 { first.total(table) } else { r1 };
    if r1 <= 0.0 {
        return None;
    }
    let r2_total = second.total(table);
    let r2_used = second.used(table);

    let s1 = first_innings_score as f64;
    let par = (s1 * r2_used / r1).floor() as i32;

    let (target, used_g50) = if r2_total <= r1 {
        ((s1 * r2_total / r1).floor() as i32 + 1, false)
    } else {
        ((s1 + g50 * (r2_total - r1) / 100.0).floor() as i32 + 1, true)
    };

    Some(DlsPar {
        par,
        ahead_by: second_innings_score as i32 - par,
        target,
        resources_first: (r1 * 10.0).round() / 10.0,
        resources_second: (r2_total * 10.0).round() / 10.0,
        resources_used: (r2_used * 10.0).round() / 10.0,
        method: table.method(),
        used_g50,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table() -> ResourceTable {
        ResourceTable::default()
    }

    #[test]
    fn a_full_innings_is_all_the_resources_there_are() {
        assert!((table().resource(50.0, 0) - 100.0).abs() < 0.01);
    }

    #[test]
    fn nothing_left_is_no_resource() {
        assert_eq!(table().resource(0.0, 0), 0.0);
        assert_eq!(table().resource(20.0, 10), 0.0);
    }

    /// The published Standard Edition zero-wicket column, to a tenth of a point.
    #[test]
    fn the_zero_wicket_curve_tracks_the_published_table() {
        let t = table();
        for (overs, published) in [
            (5.0, 17.2),
            (15.0, 45.2),
            (20.0, 56.6),
            (25.0, 66.5),
            (30.0, 75.1),
            (35.0, 82.7),
            (40.0, 89.3),
            (45.0, 95.0),
            (50.0, 100.0),
        ] {
            let got = t.resource(overs, 0);
            assert!(
                (got - published).abs() < 0.15,
                "{overs} overs: got {got:.1}, published {published:.1}"
            );
        }
    }

    #[test]
    fn resources_fall_as_wickets_go_and_as_overs_go() {
        let t = table();
        for w in 0..9 {
            assert!(
                t.resource(30.0, w) > t.resource(30.0, w + 1),
                "wicket {w} did not cost resources"
            );
        }
        for overs in 1..50 {
            assert!(
                t.resource(overs as f64, 3) < t.resource((overs + 1) as f64, 3),
                "resources did not grow with overs at {overs}"
            );
        }
    }

    #[test]
    fn a_short_side_cannot_use_a_long_innings() {
        let t = table();
        // Nine down, the last pair can barely use twenty overs.
        let twenty = t.resource(20.0, 9);
        let fifty = t.resource(50.0, 9);
        assert!(fifty - twenty < 2.0, "the tail saturates: {twenty:.1} vs {fifty:.1}");
    }

    fn innings(available: f64, remaining: f64, wickets: u8) -> InningsResources {
        InningsResources {
            overs_available: available,
            overs_remaining: remaining,
            wickets_lost: wickets,
        }
    }

    #[test]
    fn an_uninterrupted_chase_has_par_tracking_the_score() {
        let t = table();
        // 200 off 50; chase 25 overs in, 3 down, on 96.
        let par = par_score(&t, DEFAULT_G50, 200, innings(50.0, 0.0, 6), innings(50.0, 25.0, 3), 96)
            .unwrap();
        assert_eq!(par.target, 201, "an equal-resource chase needs one more");
        assert!(par.par > 0 && par.par < 200);
        assert_eq!(par.ahead_by, 96 - par.par);
    }

    #[test]
    fn a_shortened_chase_gets_a_smaller_target() {
        let t = table();
        let full = par_score(&t, DEFAULT_G50, 250, innings(50.0, 0.0, 8), innings(50.0, 50.0, 0), 0)
            .unwrap();
        let rained_off =
            par_score(&t, DEFAULT_G50, 250, innings(50.0, 0.0, 8), innings(25.0, 25.0, 0), 0)
                .unwrap();
        assert_eq!(full.target, 251);
        assert!(
            rained_off.target < full.target,
            "25 overs should chase less than 50: {} vs {}",
            rained_off.target,
            full.target
        );
        assert!(rained_off.target > 100, "but not trivially less");
    }

    #[test]
    fn more_resources_than_the_first_innings_brings_in_g50() {
        let t = table();
        // Team 1 bowled out in 20 overs of a 50-over game; team 2 has the lot.
        let par = par_score(&t, DEFAULT_G50, 120, innings(20.0, 0.0, 9), innings(50.0, 50.0, 0), 0)
            .unwrap();
        assert!(par.used_g50, "extra resources are paid for with G50");
        assert!(par.target > 120, "and raise the target above the raw score");
    }

    #[test]
    fn par_is_zero_at_the_start_of_the_chase() {
        let t = table();
        let par = par_score(&t, DEFAULT_G50, 180, innings(50.0, 0.0, 10), innings(50.0, 50.0, 0), 0)
            .unwrap();
        assert_eq!(par.par, 0, "no resources used, nothing to be level with");
        assert_eq!(par.ahead_by, 0);
    }

    #[test]
    fn par_climbs_as_the_chase_spends_its_resources() {
        let t = table();
        let early =
            par_score(&t, DEFAULT_G50, 180, innings(50.0, 0.0, 10), innings(50.0, 40.0, 1), 0)
                .unwrap();
        let late =
            par_score(&t, DEFAULT_G50, 180, innings(50.0, 0.0, 10), innings(50.0, 10.0, 5), 0)
                .unwrap();
        assert!(late.par > early.par, "{} should exceed {}", late.par, early.par);
        assert!(late.par < 180, "par only reaches the score at the very end");
    }

    #[test]
    fn a_supplied_table_is_used_and_labelled() {
        let mut rows = vec![[0.0; 10]; 51];
        for (overs, row) in rows.iter_mut().enumerate() {
            for (wickets, cell) in row.iter_mut().enumerate() {
                *cell = (overs as f64 * 2.0) * (1.0 - wickets as f64 / 10.0);
            }
        }
        let supplied = ResourceTable::from_rows(rows).unwrap();
        assert_eq!(supplied.method(), DlsMethod::SuppliedTable);
        assert!((supplied.resource(50.0, 0) - 100.0).abs() < 0.01);
        // Halfway between two rows interpolates.
        assert!((supplied.resource(10.5, 0) - 21.0).abs() < 0.01);
    }

    #[test]
    fn a_table_that_gives_resources_for_no_overs_is_refused() {
        let mut rows = vec![[0.0; 10]; 51];
        rows[0][0] = 1.0;
        assert!(ResourceTable::from_rows(rows).is_err());
    }

    #[test]
    fn the_summary_reads_like_a_scoreboard() {
        let t = table();
        let par = par_score(&t, DEFAULT_G50, 200, innings(50.0, 0.0, 7), innings(50.0, 25.0, 2), 250)
            .unwrap();
        assert!(par.summary().contains("ahead of the DLS par"), "{}", par.summary());
    }
}
