//! Reading the outside scores feed, inside a hundred requests a day.
//!
//! The feed is free and allows 100 requests a day for the whole deployment —
//! not per person. So no request anybody makes ever reaches it. This job reads
//! it a few times an hour, writes what it finds to Postgres, and the API
//! serves every reader from there.
//!
//! Three things make a hundred requests enough:
//!
//! * **One request covers everything being played.** Asking the feed for a
//!   date returns every match in progress on it, four-day Tests included, so a
//!   refresh of the whole world's cricket costs one request, not one per match.
//! * **Finished cricket is never asked about twice.** A day whose matches have
//!   all ended is marked settled and skipped for good.
//! * **The rate follows the audience.** Fast while somebody is watching play,
//!   slow while they are not, barely at all overnight — and slower still as the
//!   day's allowance runs down, so it degrades rather than stopping dead at
//!   teatime.
//!
//! Above all of that sits a hard limit that cannot be talked round: the
//! allowance is claimed in Postgres before the request is made, so two pods
//! cannot both spend the last one.

use chrono::{DateTime, NaiveDate, Utc};
use fishers_db::repos::world_cricket as repo;
use fishers_domain::world_cricket::WorldMatch;
use serde::Deserialize;
use sqlx::PgPool;
use tracing::{debug, info, warn};

/// This job's own advisory lock, so it competes with its copies on other pods
/// but not with the five-minute scheduler next door.
const POLL_LOCK: i64 = 0x_6669_7368_6572_7302;

/// How often the loop wakes to think. Thinking is a couple of cheap local
/// queries; whether it then spends a request is the whole question below.
const TICK: std::time::Duration = std::time::Duration::from_secs(60);

/// Days either side of today kept populated, so the screen can show what is
/// coming as well as what is on.
const WINDOW_AHEAD: i64 = 7;
const WINDOW_BEHIND: i64 = 2;

/// A fixture list does not move much. Once a day per date is plenty, and it
/// leaves the allowance for play.
const WINDOW_MAX_AGE_MINS: i32 = 6 * 60;

/// Below this many requests left, only live play is refreshed — filling in
/// next week's fixtures must never be the reason today's score is stale.
const LIVE_RESERVE: i32 = 25;

/// Matches older than this are dropped. Long enough to look back over a
/// tournament, short enough that the table never becomes a problem.
const KEEP_DAYS: i32 = 45;

/// The outside feed. Absent a key it is simply off — which is what int and
/// test want, so their traffic cannot spend prod's allowance.
#[derive(Clone)]
pub struct Feed {
    // Crate-visible so `world_cricket_detail` can reuse the one client and the
    // one key rather than building a second of each.
    pub(crate) key: Option<String>,
    pub(crate) base: String,
    pub(crate) http: reqwest::Client,
    /// Requests we will make in a day. Deliberately under the provider's own
    /// 100 so that anything we have not thought of has room.
    cap: i32,
    /// Seconds between refreshes while play is on and somebody is watching.
    live_secs: i64,
}

impl Feed {
    pub fn from_env() -> Self {
        let key = std::env::var("CRICKET_FEED_KEY")
            .ok()
            .map(|k| k.trim().to_string())
            .filter(|k| !k.is_empty());
        Self {
            key,
            base: std::env::var("CRICKET_FEED_URL")
                .unwrap_or_else(|_| "https://cricket.highlightly.net".into()),
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(20))
                .build()
                .unwrap_or_default(),
            // The free plan allows 100. Five held back covers a miscount and
            // the odd retry. Raise it with the plan.
            cap: env_num("CRICKET_FEED_CAP", 95),
            live_secs: env_num("CRICKET_FEED_LIVE_SECS", 180),
        }
    }

    pub fn enabled(&self) -> bool {
        self.key.is_some()
    }

    /// The day's allowance. One pool: the scorecard page claims from the same
    /// number the list poller does.
    pub fn cap(&self) -> i32 {
        self.cap
    }

    /// One day's matches, and what the provider's headers said about the
    /// allowance afterwards.
    async fn fetch(&self, day: NaiveDate) -> anyhow::Result<(Vec<WorldMatch>, Option<(i32, i32)>)> {
        let key = self
            .key
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("no feed key"))?;
        // limit=100 is the maximum page. More than a hundred matches on one
        // date has not been seen; paging for them would double the cost of
        // every refresh, so the count is checked and logged instead.
        let url = format!("{}/matches?date={}&limit=100", self.base, day);
        let response = self
            .http
            .get(&url)
            .header("x-rapidapi-key", key)
            .send()
            .await?;

        let status = response.status();
        let quota = quota_of(response.headers());
        let body = response.text().await?;
        if !status.is_success() {
            anyhow::bail!("feed returned {status}: {}", body.chars().take(200).collect::<String>());
        }
        Ok((parse_matches(&body)?, quota))
    }
}

fn env_num<T: std::str::FromStr>(name: &str, fallback: T) -> T {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(fallback)
}

pub(crate) fn quota_of(headers: &reqwest::header::HeaderMap) -> Option<(i32, i32)> {
    let get = |name: &str| -> Option<i32> {
        headers.get(name)?.to_str().ok()?.trim().parse().ok()
    };
    Some((
        get("x-ratelimit-requests-limit")?,
        get("x-ratelimit-requests-remaining")?,
    ))
}

/// How long to wait between refreshes.
///
/// The shape of this is the whole budget strategy. A hundred requests cannot
/// give a two-minute refresh all day, so they are spent where they are worth
/// something — on play that somebody is actually watching — and the rest of
/// the time the feed is read just often enough to notice that a match has
/// started.
///
/// The brake underneath is what makes the limit survivable rather than
/// abrupt. Without it a long evening of watching would spend the lot by nine
/// o'clock and the scores would simply stop; with it the refresh stretches as
/// the allowance runs down, and there is always something left to catch the
/// end of a match.
fn interval_secs(live: bool, watched: bool, left: i32, live_secs: i64) -> i64 {
    let base = match (live, watched) {
        // Play, and somebody looking at it.
        (true, true) => live_secs,
        // Play, nobody looking. Kept warm so the first person to open it sees
        // something recent, but not at the price of the evening's refreshes.
        (true, false) => 15 * 60,
        // Nothing on, but somebody is looking — so notice promptly when
        // something starts.
        (false, true) => 10 * 60,
        // The small hours.
        (false, false) => 60 * 60,
    };
    let floor = match left {
        i32::MIN..=10 => 60 * 60,
        11..=25 => 15 * 60,
        _ => 0,
    };
    base.max(floor)
}

/// Somebody counts as watching for a few minutes after they look, so a person
/// reading a scorecard keeps the fast refresh alive without having to reload.
fn watched_recently(watched_at: Option<DateTime<Utc>>) -> bool {
    watched_at.is_some_and(|at| Utc::now().signed_duration_since(at).num_minutes() < 10)
}

pub fn spawn(pool: PgPool) {
    let feed = Feed::from_env();
    if !feed.enabled() {
        info!("world cricket scores are off (no CRICKET_FEED_KEY)");
        return;
    }
    info!(cap = feed.cap, "world cricket scores are on");
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(TICK);
        loop {
            interval.tick().await;
            if let Err(e) = locked_tick(&pool, &feed).await {
                warn!(error = %e, "world cricket poll failed");
            }
        }
    });
}

/// One pod polls; the rest skip. Same reasoning as the scheduler next door,
/// and here it is also what stops two pods spending two requests for the one
/// refresh.
async fn locked_tick(pool: &PgPool, feed: &Feed) -> anyhow::Result<()> {
    let mut conn = pool.acquire().await?;
    let held: bool = sqlx::query_scalar("SELECT pg_try_advisory_lock($1)")
        .bind(POLL_LOCK)
        .fetch_one(&mut *conn)
        .await?;
    if !held {
        return Ok(());
    }
    let result = tick(pool, feed).await;
    if let Err(e) = sqlx::query("SELECT pg_advisory_unlock($1)")
        .bind(POLL_LOCK)
        .execute(&mut *conn)
        .await
    {
        warn!(error = %e, "could not release the poll lock");
    }
    result
}

/// At most one request per tick, and only if it is worth making.
async fn tick(pool: &PgPool, feed: &Feed) -> anyhow::Result<()> {
    let (spent, _, watched_at) = repo::budget(pool).await?;
    let left = feed.cap - spent;
    if left <= 0 {
        debug!("the day's feed allowance is gone");
        return Ok(());
    }

    let live = repo::live_count(pool).await? > 0;
    let wait = interval_secs(live, watched_recently(watched_at), left, feed.live_secs);

    // Play first: a stale score is the thing a reader actually notices.
    if let Some(day) = repo::due_refresh(pool, (wait / 60).max(1) as i32).await? {
        refresh(pool, feed, day).await?;
        return Ok(());
    }

    // Then keep the fixture window filled — but never out of the reserve that
    // live play depends on.
    if left > LIVE_RESERVE {
        let today = Utc::now().date_naive();
        let from = today - chrono::Duration::days(WINDOW_BEHIND);
        let to = today + chrono::Duration::days(WINDOW_AHEAD);
        if let Some(day) = repo::stale_day(pool, from, to, WINDOW_MAX_AGE_MINS).await? {
            refresh(pool, feed, day).await?;
        }
    }
    Ok(())
}

/// Claim an allowance, make the call, store what came back.
///
/// The claim happens first and is given back if the call never landed. Doing
/// it the other way round — call, then count — means a crash between the two
/// loses count of a request that was really made, which is the direction that
/// overspends.
async fn refresh(pool: &PgPool, feed: &Feed, day: NaiveDate) -> anyhow::Result<()> {
    let Some(spent) = repo::try_spend(pool, feed.cap).await? else {
        debug!("the day's feed allowance is gone");
        return Ok(());
    };

    let (matches, quota) = match feed.fetch(day).await {
        Ok(found) => found,
        Err(e) => {
            // Nothing was served to us, so nothing should be charged for it.
            // Without this a bad half-hour of networking would quietly eat the
            // day's cricket.
            repo::refund(pool).await.ok();
            return Err(e);
        }
    };

    if let Some((limit, remaining)) = quota {
        // Their count beats ours: it starts when their day does and it sees
        // anything else using the same key.
        repo::reconcile(pool, limit, remaining).await?;
        if remaining <= 0 {
            warn!("the feed says the allowance is spent");
        }
    }

    let count = matches.len();
    let settled = repo::store_day(pool, day, &matches, Utc::now().date_naive()).await?;
    info!(%day, count, settled, spent, "read the scores feed");

    // Cheap, and only worth doing on a day we were going to write anyway.
    if settled {
        match repo::prune(pool, KEEP_DAYS).await {
            Ok(n) if n > 0 => debug!(removed = n, "pruned old world matches"),
            Err(e) => warn!(error = %e, "pruning old world matches failed"),
            _ => {}
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// The feed's own shapes, and the translation into ours.
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct Envelope {
    #[serde(default)]
    data: Vec<FeedMatch>,
    #[serde(default)]
    pagination: Option<Pagination>,
}

#[derive(Deserialize)]
struct Pagination {
    #[serde(rename = "totalCount")]
    total_count: i64,
}

#[derive(Deserialize)]
struct FeedMatch {
    id: String,
    #[serde(rename = "startDate")]
    start_date: DateTime<Utc>,
    #[serde(rename = "endDate")]
    end_date: Option<DateTime<Utc>>,
    #[serde(rename = "startTime")]
    start_time: Option<DateTime<Utc>>,
    #[serde(default)]
    country: Option<Country>,
    #[serde(rename = "dayType")]
    day_type: Option<String>,
    format: Option<String>,
    state: FeedState,
    #[serde(rename = "homeTeam")]
    home_team: Team,
    #[serde(rename = "awayTeam")]
    away_team: Team,
    league: League,
}

#[derive(Deserialize)]
struct Country {
    code: Option<String>,
    name: Option<String>,
}

#[derive(Deserialize)]
struct Team {
    name: String,
    abbreviation: Option<String>,
    logo: Option<String>,
}

#[derive(Deserialize)]
struct League {
    name: String,
    season: Option<i32>,
}

#[derive(Deserialize)]
struct FeedState {
    description: String,
    report: Option<String>,
    #[serde(default)]
    teams: Option<FeedTeams>,
}

#[derive(Deserialize)]
struct FeedTeams {
    home: FeedScore,
    away: FeedScore,
}

#[derive(Deserialize, Default)]
struct FeedScore {
    score: Option<String>,
    info: Option<String>,
}

/// The feed serves country flags over plain `http`, which iOS refuses to load
/// at all and a browser blocks as mixed content. The same files are served
/// over `https`, so the scheme is corrected on the way in rather than every
/// client having to know.
fn secure(url: Option<String>) -> Option<String> {
    url.map(|u| {
        if let Some(rest) = u.strip_prefix("http://") {
            format!("https://{rest}")
        } else {
            u
        }
    })
    .filter(|u| !u.is_empty())
}

/// Parse a feed response. Kept separate from the HTTP so it can be tested
/// against a captured payload — a response shape that changes underneath us
/// should fail a test, not quietly empty the screen.
fn parse_matches(body: &str) -> anyhow::Result<Vec<WorldMatch>> {
    let envelope: Envelope = serde_json::from_str(body)?;
    if let Some(p) = &envelope.pagination {
        if p.total_count > envelope.data.len() as i64 {
            // Paging would cost a request per page on an allowance of a
            // hundred a day. Worth knowing about; not worth paying for unless
            // it actually happens.
            warn!(
                total = p.total_count,
                got = envelope.data.len(),
                "more matches on this date than one page holds"
            );
        }
    }
    Ok(envelope.data.into_iter().map(Into::into).collect())
}

impl From<FeedMatch> for WorldMatch {
    fn from(m: FeedMatch) -> Self {
        let (home, away) = match m.state.teams {
            Some(t) => (t.home, t.away),
            None => (FeedScore::default(), FeedScore::default()),
        };
        let country = m.country.unwrap_or(Country { code: None, name: None });
        WorldMatch {
            phase: fishers_domain::world_cricket::phase_for(&m.state.description).to_string(),
            id: m.id,
            league_name: m.league.name,
            league_season: m.league.season,
            home_team_name: m.home_team.name,
            home_team_short: m.home_team.abbreviation,
            home_team_logo: secure(m.home_team.logo),
            away_team_name: m.away_team.name,
            away_team_short: m.away_team.abbreviation,
            away_team_logo: secure(m.away_team.logo),
            country_code: country.code,
            country_name: country.name,
            format: m.format,
            day_type: m.day_type,
            start_time: m.start_time,
            start_date: m.start_date.date_naive(),
            end_date: m.end_date.map(|d| d.date_naive()),
            state: m.state.description,
            report: m.state.report,
            home_score: home.score,
            home_info: home.info,
            away_score: away.score,
            away_info: away.info,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fishers_domain::world_cricket::{PHASE_DONE, PHASE_LIVE, PHASE_PENDING};

    /// Captured from `GET https://cricket.highlightly.net/matches?date=2026-09-29`
    /// on the free plan. Trimmed to one match of each interesting kind.
    const CAPTURED: &str = r#"
    {
      "data": [
        {
          "id": "54321087",
          "startDate": "2026-09-29T00:00:00.000Z",
          "endDate": "2026-10-02T00:00:00.000Z",
          "country": {"code": "IN", "name": "India", "logo": "http://highlightly.net/cricket/images/countries/IN.svg"},
          "dayType": "MULTI",
          "format": "TEST",
          "startTime": "2026-09-29T04:00:00.000Z",
          "state": {
            "teams": {"away": {"info": null, "score": null}, "home": {"info": "84.4 ov", "score": "307/5"}},
            "report": "Day 1 - IND-A Women chose to bat.",
            "description": "In play"
          },
          "awayTeam": {"id": "7737", "logo": "https://highlightly.net/cricket/images/teams/7737.png", "name": "Australia A Women", "abbreviation": "AU-AW"},
          "homeTeam": {"id": "63597", "logo": "https://highlightly.net/cricket/images/teams/63597.png", "name": "India A Women", "abbreviation": "IN-AW"},
          "league": {"id": "54320737", "logo": null, "name": "Australia A Women in India", "season": 2026}
        },
        {
          "id": "53749082",
          "startDate": "2026-09-27T00:00:00.000Z",
          "endDate": "2026-09-30T00:00:00.000Z",
          "country": {"code": "IN", "name": "India", "logo": "http://highlightly.net/cricket/images/countries/IN.svg"},
          "dayType": "MULTI",
          "format": "TEST",
          "startTime": "2026-09-27T04:00:00.000Z",
          "state": {
            "teams": {"away": {"info": null, "score": "217 & 229"}, "home": {"info": null, "score": "494"}},
            "report": "IND Under-19 won by an innings and 48 runs",
            "description": "Finished"
          },
          "awayTeam": {"id": "1", "logo": null, "name": "Australia U19", "abbreviation": "AU-19"},
          "homeTeam": {"id": "2", "logo": null, "name": "India U19", "abbreviation": "IN-19"},
          "league": {"id": "9", "logo": null, "name": "Australia U19 in India", "season": 2026}
        },
        {
          "id": "54314542",
          "startDate": "2026-09-29T00:00:00.000Z",
          "endDate": "2026-09-29T00:00:00.000Z",
          "country": {"code": "AU", "name": "Australia", "logo": "http://highlightly.net/cricket/images/countries/AU.svg"},
          "dayType": "SINGLE",
          "format": "T20",
          "startTime": "2026-09-29T16:00:00.000Z",
          "state": {
            "teams": {"away": {"info": null, "score": null}, "home": {"info": null, "score": null}},
            "report": null,
            "description": "Scheduled"
          },
          "awayTeam": {"id": "3", "logo": null, "name": "Melbourne Stars", "abbreviation": "MS"},
          "homeTeam": {"id": "4", "logo": null, "name": "Melbourne Renegades", "abbreviation": "MR"},
          "league": {"id": "48513362", "logo": null, "name": "Big Bash League", "season": 2026}
        }
      ],
      "pagination": {"totalCount": 3, "offset": 0, "limit": 100},
      "plan": {"tier": "BASIC", "message": "All data available with current plan."}
    }
    "#;

    #[test]
    fn parses_the_captured_payload() {
        let matches = parse_matches(CAPTURED).expect("captured payload should parse");
        assert_eq!(matches.len(), 3);

        let m = &matches[0];
        assert_eq!(m.id, "54321087");
        assert_eq!(m.home_team_name, "India A Women");
        assert_eq!(m.home_score.as_deref(), Some("307/5"));
        assert_eq!(m.home_info.as_deref(), Some("84.4 ov"));
        assert_eq!(m.format.as_deref(), Some("TEST"));
        assert_eq!(m.day_type.as_deref(), Some("MULTI"));
        assert_eq!(m.league_name, "Australia A Women in India");
        assert_eq!(m.country_code.as_deref(), Some("IN"));
        assert_eq!(m.phase, PHASE_LIVE);
        // The date query returns matches active on that date; the row is filed
        // under the day the match began.
        assert_eq!(m.start_date.to_string(), "2026-09-29");
        assert_eq!(m.end_date.map(|d| d.to_string()).as_deref(), Some("2026-10-02"));
    }

    /// A four-day Test that started two days earlier still comes back under
    /// today's date. This is the fact the whole budget rests on: one request
    /// refreshes every match in progress, not one per match.
    #[test]
    fn a_multi_day_test_is_filed_under_the_day_it_started() {
        let matches = parse_matches(CAPTURED).unwrap();
        let test = matches.iter().find(|m| m.id == "53749082").unwrap();
        assert_eq!(test.start_date.to_string(), "2026-09-27");
        assert_eq!(test.phase, PHASE_DONE);
        assert_eq!(test.away_score.as_deref(), Some("217 & 229"));
    }

    #[test]
    fn a_scheduled_match_has_no_score_yet() {
        let matches = parse_matches(CAPTURED).unwrap();
        let next = matches.iter().find(|m| m.id == "54314542").unwrap();
        assert_eq!(next.phase, PHASE_PENDING);
        assert!(next.home_score.is_none());
        assert!(next.report.is_none());
    }

    /// Team logos arrive over https and are kept; a missing one stays missing
    /// rather than becoming an empty string the clients would try to load.
    #[test]
    fn logos_are_https_or_absent() {
        let matches = parse_matches(CAPTURED).unwrap();
        assert!(matches[0].home_team_logo.as_deref().unwrap().starts_with("https://"));
        assert!(matches[1].home_team_logo.is_none());
    }

    #[test]
    fn an_http_url_is_rewritten_not_dropped() {
        assert_eq!(
            secure(Some("http://highlightly.net/a.svg".into())).as_deref(),
            Some("https://highlightly.net/a.svg")
        );
        assert_eq!(secure(Some(String::new())), None);
        assert_eq!(secure(None), None);
    }

    /// An empty day is a normal answer, not a failure.
    #[test]
    fn an_empty_day_parses() {
        assert!(parse_matches(r#"{"data":[],"pagination":{"totalCount":0,"offset":0,"limit":100}}"#)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn rubbish_is_an_error_rather_than_an_empty_day() {
        // The distinction matters: an empty day gets stored and marks the day
        // fetched, so a parse failure must not look like one.
        assert!(parse_matches("<html>502 Bad Gateway</html>").is_err());
    }

    #[test]
    fn watching_play_refreshes_fastest() {
        assert_eq!(interval_secs(true, true, 90, 180), 180);
        // Play on but nobody looking: keep it warm, do not spend the evening.
        assert_eq!(interval_secs(true, false, 90, 180), 900);
        // Nothing on at all, in the middle of the night.
        assert_eq!(interval_secs(false, false, 90, 180), 3600);
    }

    /// The brake. A long evening must not spend the lot by nine o'clock and
    /// leave the last hour of a match frozen.
    #[test]
    fn the_refresh_stretches_as_the_allowance_runs_down() {
        assert_eq!(interval_secs(true, true, 90, 180), 180);
        assert_eq!(interval_secs(true, true, 20, 180), 900);
        assert_eq!(interval_secs(true, true, 5, 180), 3600);
        // And never gets faster as it runs down, whatever else is true.
        for left in [0, 5, 11, 25, 26, 100] {
            assert!(interval_secs(true, true, left, 180) >= 180);
        }
    }

    #[test]
    fn a_reader_keeps_the_fast_refresh_alive_for_a_few_minutes() {
        assert!(!watched_recently(None));
        assert!(watched_recently(Some(Utc::now() - chrono::Duration::minutes(2))));
        assert!(!watched_recently(Some(Utc::now() - chrono::Duration::minutes(30))));
    }
}
