//! Fetching and parsing one match's scorecard.
//!
//! Separate from the list poller next door because it is costed differently.
//! One request to the list refreshes every match being played anywhere; one
//! request here refreshes a single match. So this never runs on a timer — it
//! runs when somebody opens a match, and only if what we have is stale.

use fishers_domain::world_cricket_detail::{
    dismissal_line, BattingRow, BowlingRow, CurrentPlayer, Extras, FallOfWicket, Innings,
    WorldMatchDetail,
};
use serde::Deserialize;

use crate::world_cricket::Feed;

impl Feed {
    /// One match in full, and what the provider's headers then said about the
    /// allowance. `Ok((None, _))` where the feed has no such match.
    ///
    /// The caller claims the day's allowance before calling and gives it back
    /// if this fails, exactly as the list poller does — there is one pool and
    /// this spends from it.
    pub async fn fetch_detail(
        &self,
        id: &str,
    ) -> anyhow::Result<(Option<WorldMatchDetail>, Option<(i32, i32)>)> {
        let key = self
            .key
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("no feed key"))?;
        let url = format!("{}/matches/{}", self.base, id);
        let response = self
            .http
            .get(&url)
            .header("x-rapidapi-key", key)
            .send()
            .await?;
        let status = response.status();
        let quota = crate::world_cricket::quota_of(response.headers());
        let body = response.text().await?;
        if !status.is_success() {
            anyhow::bail!(
                "feed returned {status}: {}",
                body.chars().take(200).collect::<String>()
            );
        }
        Ok((parse_detail(&body)?, quota))
    }
}

// ---------------------------------------------------------------------------
// The feed's shapes.
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct FeedDetail {
    #[serde(default)]
    venue: Option<Venue>,
    #[serde(rename = "inplayData", default)]
    inplay: Option<InplayData>,
    #[serde(default)]
    statistics: Vec<InningsEntry>,
}

#[derive(Deserialize)]
struct Venue {
    name: Option<String>,
    city: Option<String>,
}

#[derive(Deserialize)]
struct InplayData {
    #[serde(default)]
    batsmen: Vec<InplayPlayer>,
    #[serde(default)]
    bowlers: Vec<InplayPlayer>,
}

#[derive(Deserialize)]
struct InplayPlayer {
    #[serde(default)]
    team: Option<NamedTeam>,
    player: InplayInner,
}

#[derive(Deserialize)]
struct NamedTeam {
    name: Option<String>,
}

#[derive(Deserialize)]
struct InplayInner {
    name: String,
    #[serde(default)]
    statistics: Option<InplayStats>,
}

#[derive(Deserialize, Default)]
struct InplayStats {
    runs: Option<i32>,
    balls: Option<i32>,
    fours: Option<i32>,
    sixes: Option<i32>,
    overs: Option<f64>,
    wickets: Option<i32>,
    #[serde(rename = "runsConceded")]
    runs_conceded: Option<i32>,
}

#[derive(Deserialize)]
struct InningsEntry {
    team: InningsTeam,
}

#[derive(Deserialize)]
struct InningsTeam {
    name: String,
    abbreviation: Option<String>,
    logo: Option<String>,
    extras: Option<i32>,
    byes: Option<i32>,
    #[serde(rename = "legByes")]
    leg_byes: Option<i32>,
    wides: Option<i32>,
    #[serde(rename = "noBalls")]
    no_balls: Option<i32>,
    #[serde(rename = "fallOfWickets", default)]
    fall_of_wickets: Vec<FowEntry>,
    #[serde(rename = "inningBatsmen", default)]
    batting: Vec<BatEntry>,
    #[serde(rename = "inningBowlers", default)]
    bowling: Vec<BowlEntry>,
}

#[derive(Deserialize)]
struct FowEntry {
    runs: Option<i32>,
    overs: Option<f64>,
    /// Zero-based at the feed's end. A scorecard counts from one.
    order: Option<i32>,
    #[serde(rename = "dismissalBatsman", default)]
    batsman: Option<NamedPlayer>,
}

#[derive(Deserialize)]
struct NamedPlayer {
    name: Option<String>,
}

#[derive(Deserialize)]
struct BatEntry {
    player: NamedPlayer,
    runs: Option<i32>,
    balls: Option<i32>,
    fours: Option<i32>,
    sixes: Option<i32>,
    #[serde(rename = "battingStrikeRate")]
    strike_rate: Option<f64>,
    #[serde(rename = "dismissalStatus")]
    status: Option<String>,
    #[serde(rename = "dismissalBowler", default)]
    bowler: Option<NamedPlayer>,
    #[serde(rename = "dismissalFielders", default)]
    fielders: Vec<NamedPlayer>,
}

#[derive(Deserialize)]
struct BowlEntry {
    player: NamedPlayer,
    overs: Option<f64>,
    maidens: Option<i32>,
    wickets: Option<i32>,
    economy: Option<f64>,
    #[serde(rename = "concededRuns")]
    conceded: Option<i32>,
}

// ---------------------------------------------------------------------------
// Into ours.
// ---------------------------------------------------------------------------

/// "101 (153b, 7x4, 3x6)" — what a batter has made, as a live score reads it.
fn batter_line(s: &InplayStats) -> String {
    let runs = s.runs.unwrap_or(0);
    let mut parts = Vec::new();
    if let Some(b) = s.balls {
        parts.push(format!("{b}b"));
    }
    if let Some(f) = s.fours.filter(|f| *f > 0) {
        parts.push(format!("{f}x4"));
    }
    if let Some(six) = s.sixes.filter(|s| *s > 0) {
        parts.push(format!("{six}x6"));
    }
    if parts.is_empty() {
        runs.to_string()
    } else {
        format!("{runs} ({})", parts.join(", "))
    }
}

/// "1/19 (11.6 ov)" — the way a bowler's current spell is read out.
fn bowler_line(s: &InplayStats) -> String {
    let wickets = s.wickets.unwrap_or(0);
    let runs = s.runs_conceded.unwrap_or(0);
    match s.overs {
        Some(overs) => format!("{wickets}/{runs} ({} ov)", trim_overs(overs)),
        None => format!("{wickets}/{runs}"),
    }
}

/// Overs are 11.6, not 11.60 — and a whole number of overs is 12, not 12.0.
fn trim_overs(overs: f64) -> String {
    if (overs.fract()).abs() < f64::EPSILON {
        format!("{}", overs.trunc() as i64)
    } else {
        format!("{overs}")
    }
}

fn current(players: &[InplayPlayer], batting: bool) -> Vec<CurrentPlayer> {
    players
        .iter()
        .map(|p| {
            let stats = p.player.statistics.as_ref();
            let empty = InplayStats::default();
            let s = stats.unwrap_or(&empty);
            CurrentPlayer {
                name: p.player.name.clone(),
                team_name: p.team.as_ref().and_then(|t| t.name.clone()),
                line: if batting { batter_line(s) } else { bowler_line(s) },
            }
        })
        .collect()
}

/// Parse a `GET /matches/{id}` response.
///
/// The feed answers with a list holding one match, not with the match. That is
/// the sort of thing that is obvious until somebody writes `serde_json::from_str::<Match>`
/// and gets an error about expecting a map, so it is pinned by a test.
pub fn parse_detail(body: &str) -> anyhow::Result<Option<WorldMatchDetail>> {
    let found: Vec<FeedDetail> = serde_json::from_str(body)?;
    let Some(d) = found.into_iter().next() else {
        return Ok(None);
    };

    let venue = d.venue.and_then(|v| {
        let parts: Vec<String> = [v.name, v.city].into_iter().flatten()
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect();
        (!parts.is_empty()).then(|| parts.join(", "))
    });

    let (batting_now, bowling_now) = match &d.inplay {
        Some(i) => (current(&i.batsmen, true), current(&i.bowlers, false)),
        None => (Vec::new(), Vec::new()),
    };

    let innings = d
        .statistics
        .into_iter()
        .map(|entry| {
            let t = entry.team;
            let batting: Vec<BattingRow> = t
                    .batting
                    .into_iter()
                    .map(|b| {
                        // Somebody who has faced a ball or scored has batted;
                        // the rest of the eleven are "did not bat", which is a
                        // different thing from being not out.
                        let batted = b.runs.is_some() || b.balls.is_some();
                        let fielders: Vec<&str> = b
                            .fielders
                            .iter()
                            .filter_map(|f| f.name.as_deref())
                            .collect();
                        let status = b.status.as_deref();
                        let bowler = b.bowler.as_ref().and_then(|x| x.name.as_deref());
                        BattingRow {
                            name: b.player.name.unwrap_or_default(),
                            runs: b.runs,
                            balls: b.balls,
                            fours: b.fours,
                            sixes: b.sixes,
                            strike_rate: b.strike_rate,
                            how_out: dismissal_line(status, bowler, &fielders, batted),
                            not_out: batted
                                && matches!(
                                    status.map(str::to_ascii_lowercase).as_deref(),
                                    None | Some("not out") | Some("notout")
                                ),
                        }
                    })
                    .collect();
            // Runs off the bat plus extras is the total; batters who went in
            // and are not still there are the wickets. Computed once, here,
            // rather than three times on three clients.
            let scored = !batting.is_empty();
            let total_runs = scored.then(|| {
                batting.iter().filter_map(|b| b.runs).sum::<i32>() + t.extras.unwrap_or(0)
            });
            let wickets = scored.then(|| {
                batting
                    .iter()
                    .filter(|b| (b.runs.is_some() || b.balls.is_some()) && !b.not_out)
                    .count() as i32
            });
            Innings {
                team_name: t.name,
                team_short: t.abbreviation,
                team_logo: t.logo,
                total_runs,
                wickets,
                batting,
                bowling: t
                    .bowling
                    .into_iter()
                    .map(|b| BowlingRow {
                        name: b.player.name.unwrap_or_default(),
                        overs: b.overs,
                        maidens: b.maidens,
                        runs: b.conceded,
                        wickets: b.wickets,
                        economy: b.economy,
                    })
                    .collect(),
                fall_of_wickets: t
                    .fall_of_wickets
                    .into_iter()
                    .map(|f| FallOfWicket {
                        // The feed counts from zero. Nobody says "the nought-th
                        // wicket fell".
                        wicket: f.order.unwrap_or(0) + 1,
                        runs: f.runs,
                        overs: f.overs,
                        batter: f.batsman.and_then(|b| b.name),
                    })
                    .collect(),
                extras: Extras {
                    total: t.extras,
                    byes: t.byes,
                    leg_byes: t.leg_byes,
                    wides: t.wides,
                    no_balls: t.no_balls,
                },
            }
        })
        .collect();

    Ok(Some(WorldMatchDetail { venue, batting_now, bowling_now, innings }))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Trimmed from a real `GET https://cricket.highlightly.net/matches/53748697`
    /// on the free plan: one batter caught, one not out, one bowled, and one
    /// who never went in.
    const CAPTURED: &str = r##"[
  {
    "id": "53748697",
    "venue": {
      "city": null,
      "name": null,
      "country": null,
      "capacity": null
    },
    "inplayData": {
      "batsmen": [
        {
          "team": {
            "id": "1857",
            "logo": "https://highlightly.net/cricket/images/teams/1857.png",
            "name": "Australia A",
            "abbreviation": "AUS-A"
          },
          "player": {
            "name": "Sam Harper",
            "roles": [
              "wicketkeeper batter"
            ],
            "inning": 1,
            "statistics": {
              "runs": 101,
              "balls": 153,
              "fours": 7,
              "sixes": 3,
              "strikeRate": 66.01
            },
            "battingStyles": [
              "rhb"
            ],
            "bowlingStyles": []
          }
        }
      ],
      "bowlers": [
        {
          "team": {
            "id": "62477",
            "logo": "https://highlightly.net/cricket/images/teams/62477.png",
            "name": "India A",
            "abbreviation": "IND-A"
          },
          "player": {
            "name": "Anshul Kamboj",
            "roles": [
              "bowling allrounder"
            ],
            "statistics": {
              "balls": 72,
              "overs": 11.6,
              "economy": 1.58,
              "wickets": 1,
              "runsConceded": 19
            },
            "battingStyles": [
              "rhb"
            ],
            "bowlingStyles": [
              "rm"
            ]
          }
        }
      ]
    },
    "statistics": [
      {
        "team": {
          "name": "Australia A",
          "logo": "https://highlightly.net/cricket/images/teams/1857.png",
          "extras": 27,
          "byes": 4,
          "legByes": 2,
          "wides": 0,
          "noBalls": 21,
          "fallOfWickets": [
            {
              "runs": 8,
              "order": 0,
              "overs": 7.1,
              "dismissalBatsman": {
                "name": "Josh Philippe"
              }
            },
            {
              "runs": 8,
              "order": 1,
              "overs": 8.3,
              "dismissalBatsman": {
                "name": "Sam Konstas"
              }
            }
          ],
          "inningBatsmen": [
            {
              "runs": 2,
              "balls": 25,
              "fours": 0,
              "sixes": 0,
              "player": {
                "id": "fd8e9c0d-db2f-443a-a9a3-680fa4119206",
                "name": "Sam Konstas",
                "roles": [
                  "top-order batter"
                ],
                "battingStyles": [
                  "right-hand bat"
                ],
                "bowlingStyles": [
                  "right-arm offbreak"
                ]
              },
              "dismissalBowler": {
                "name": "Shams Mulani"
              },
              "dismissalStatus": "caught",
              "battingStrikeRate": 8,
              "dismissalFielders": [
                {
                  "name": "Tanush Kotian",
                  "isKeeper": false,
                  "isSubstitute": false
                }
              ]
            },
            {
              "runs": 101,
              "balls": 153,
              "fours": 7,
              "sixes": 3,
              "player": {
                "id": "a6ab775b-ce00-4a2f-be8e-b0a760145c52",
                "name": "Sam Harper",
                "roles": [
                  "wicketkeeper batter"
                ],
                "battingStyles": [
                  "right-hand bat"
                ],
                "bowlingStyles": []
              },
              "dismissalBowler": null,
              "dismissalStatus": "not out",
              "battingStrikeRate": 66.01,
              "dismissalFielders": []
            },
            {
              "runs": 33,
              "balls": 91,
              "fours": 2,
              "sixes": 1,
              "player": {
                "id": "56a60623-0826-472b-a044-fff977dfcb22",
                "name": "Todd Murphy",
                "roles": [
                  "bowler"
                ],
                "battingStyles": [
                  "left-hand bat"
                ],
                "bowlingStyles": [
                  "right-arm offbreak"
                ]
              },
              "dismissalBowler": {
                "name": "Anshul Kamboj"
              },
              "dismissalStatus": "bowled",
              "battingStrikeRate": 36.26,
              "dismissalFielders": []
            },
            {
              "runs": null,
              "balls": null,
              "fours": null,
              "sixes": null,
              "player": {
                "id": "835f3698-47b7-421c-b8f9-5c7424da36d1",
                "name": "Liam Hatcher",
                "roles": [
                  "bowler"
                ],
                "battingStyles": [
                  "right-hand bat"
                ],
                "bowlingStyles": [
                  "right-arm fast-medium"
                ]
              },
              "dismissalBowler": null,
              "dismissalStatus": null,
              "battingStrikeRate": null,
              "dismissalFielders": []
            }
          ],
          "inningBowlers": [
            {
              "overs": 12,
              "player": {
                "name": "Anshul Kamboj",
                "roles": [
                  "bowling allrounder"
                ],
                "battingStyles": [
                  "right-hand bat"
                ],
                "bowlingStyles": [
                  "right-arm medium"
                ]
              },
              "economy": 1.58,
              "maidens": 6,
              "wickets": 1,
              "concededRuns": 19
            }
          ],
          "abbreviation": "AUS-A"
        }
      }
    ]
  }
]"##;

    fn parsed() -> WorldMatchDetail {
        parse_detail(CAPTURED).expect("captured payload should parse").expect("a match")
    }

    /// The feed answers with a *list* holding one match, not with the match.
    /// Obvious until somebody writes `from_str::<Match>` and gets an error
    /// about expecting a map.
    #[test]
    fn the_response_is_a_list_of_one() {
        assert!(parse_detail("[]").unwrap().is_none());
        assert!(parse_detail(CAPTURED).unwrap().is_some());
    }

    #[test]
    fn rubbish_is_an_error_rather_than_an_empty_card() {
        assert!(parse_detail("<html>502</html>").is_err());
    }

    #[test]
    fn the_batting_card_reads_like_a_scorecard() {
        let d = parsed();
        let innings = &d.innings[0];
        let by = |n: &str| innings.batting.iter().find(|b| b.name == n).unwrap().clone();

        let konstas = by("Sam Konstas");
        assert_eq!(konstas.runs, Some(2));
        assert_eq!(konstas.how_out, "c Tanush Kotian b Shams Mulani");
        assert!(!konstas.not_out);

        let harper = by("Sam Harper");
        assert_eq!(harper.runs, Some(101));
        assert_eq!(harper.how_out, "not out");
        assert!(harper.not_out);

        assert_eq!(by("Todd Murphy").how_out, "b Anshul Kamboj");
    }

    /// Somebody who never went in is "did not bat", which is a different thing
    /// from being not out — and the difference is the whole point of the
    /// bottom of a card.
    #[test]
    fn a_player_who_never_batted_is_not_not_out() {
        let d = parsed();
        let hatcher = d.innings[0].batting.iter().find(|b| b.name == "Liam Hatcher").unwrap();
        assert_eq!(hatcher.how_out, "did not bat");
        assert!(!hatcher.not_out);
        assert_eq!(hatcher.runs, None);
    }

    /// The feed numbers wickets from zero. Nobody says "the nought-th wicket".
    #[test]
    fn wickets_are_numbered_from_one() {
        let d = parsed();
        let fow = &d.innings[0].fall_of_wickets;
        assert_eq!(fow[0].wicket, 1);
        assert_eq!(fow[1].wicket, 2);
    }

    #[test]
    fn the_bowling_figures_carry_maidens() {
        let d = parsed();
        let b = &d.innings[0].bowling[0];
        assert_eq!(b.name, "Anshul Kamboj");
        assert_eq!(b.maidens, Some(6));
        assert_eq!(b.wickets, Some(1));
        assert_eq!(b.runs, Some(19));
    }

    /// Cricket's own identity: runs off the bat plus extras is the total, and
    /// the batters who went in and are not still there are the wickets. Checked
    /// against the real match this fixture came from, whose summary read 282/7
    /// — this trimmed copy holds only part of the card, so the arithmetic is
    /// what is asserted, not the figure.
    #[test]
    fn the_innings_total_is_the_bat_plus_the_extras() {
        let innings = &parsed().innings[0];
        let off_the_bat: i32 = innings.batting.iter().filter_map(|b| b.runs).sum();
        let extras = innings.extras.total.unwrap();
        assert_eq!(innings.total_runs, Some(off_the_bat + extras));

        // Sam Harper is not out; Liam Hatcher never batted. Neither is a wicket.
        let down = innings.wickets.unwrap();
        assert_eq!(down, 2, "Konstas caught and Murphy bowled, and nobody else");
    }

    #[test]
    fn an_innings_carries_the_abbreviation_a_tab_is_labelled_with() {
        assert_eq!(parsed().innings[0].team_short.as_deref(), Some("AUS-A"));
    }

    #[test]
    fn extras_are_broken_down() {
        let d = parsed();
        let e = &d.innings[0].extras;
        assert_eq!(e.total, Some(27));
        assert_eq!(e.byes, Some(4));
        assert_eq!(e.no_balls, Some(21));
    }

    #[test]
    fn who_is_in_reads_as_a_live_score() {
        let d = parsed();
        assert_eq!(d.batting_now[0].name, "Sam Harper");
        assert_eq!(d.batting_now[0].line, "101 (153b, 7x4, 3x6)");
        assert_eq!(d.bowling_now[0].name, "Anshul Kamboj");
        assert_eq!(d.bowling_now[0].line, "1/19 (11.6 ov)");
    }

    /// Every field on this match's venue was null. A card that prints
    /// ", " for a ground nobody named is worse than one that prints nothing.
    #[test]
    fn an_empty_venue_is_none_not_an_empty_string() {
        assert_eq!(parsed().venue, None);
    }

    #[test]
    fn a_whole_number_of_overs_loses_its_decimal() {
        assert_eq!(trim_overs(12.0), "12");
        assert_eq!(trim_overs(11.6), "11.6");
    }

    #[test]
    fn a_scorecard_with_batting_counts_as_one() {
        assert!(parsed().has_scorecard());
    }
}
