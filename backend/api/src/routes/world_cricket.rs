//! Scores from the wider game.
//!
//!   GET /api/v1/cricket/world-scores   what is on, what is next, what just ended
//!
//! Answered entirely from Postgres. The feed these rows come from allows a
//! hundred requests a day for the whole deployment, so it is read by a
//! background job (see `fishers-jobs`) and never by a request — which is what
//! makes the number of people reading this irrelevant to the number of
//! requests we owe.

use axum::extract::{Path, State};
use axum::routing::get;
use axum::{Json, Router};
use fishers_db::repos::world_cricket as repo;
use fishers_domain::world_cricket::WorldScores;
use fishers_domain::world_cricket_detail::WorldMatchDetailView;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// Enough to fill a screen and scroll a little. The home page strip shows the
/// first two or three of these; sending a few more costs nothing and saves the
/// scores page a second request.
const LIVE: i64 = 30;
const UPCOMING: i64 = 20;
const RECENT: i64 = 20;

/// How stale a live match's scorecard may be before the page refetches it.
/// The feed itself only moves once a minute, and this costs a request for one
/// match where the list costs one for all of them.
const LIVE_DETAIL_SECS: i64 = 180;

/// A match that has not started has nothing to refresh but the team sheet.
const PENDING_DETAIL_SECS: i64 = 60 * 60;

/// Scorecards stop being fetched while fewer than this many requests remain.
///
/// The list is what everybody sees; a scorecard is what one person opened. When
/// the day is running out the list has to keep working, so this gives way
/// first — the page then shows the summary and says the card is not available.
const DETAIL_FLOOR: i32 = 30;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/cricket/world-scores", get(world_scores))
        .route("/cricket/world-scores/{id}", get(world_match))
}

async fn world_scores(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> ApiResult<Json<WorldScores>> {
    if !state.world_scores {
        return Ok(Json(WorldScores {
            enabled: false,
            as_of: None,
            live: Vec::new(),
            upcoming: Vec::new(),
            recent: Vec::new(),
        }));
    }

    // Tell the poller somebody is watching. This is the whole reason the
    // refresh runs every few minutes during a match and barely at all
    // overnight, so it is worth a write — throttled to one a minute inside.
    if let Err(error) = repo::note_watched(&state.pool).await {
        // Not worth failing the page over: the cost of missing it is a
        // slightly staler score, and the scores themselves are right here.
        tracing::warn!(%error, "could not record a scores view");
    }

    let (as_of, live, upcoming, recent) = tokio::try_join!(
        repo::as_of(&state.pool),
        repo::live(&state.pool, LIVE),
        repo::upcoming(&state.pool, UPCOMING),
        repo::recent(&state.pool, RECENT),
    )?;

    Ok(Json(WorldScores { enabled: true, as_of, live, upcoming, recent }))
}

/// One match in full.
///
/// Unlike the list, this costs a request *per match*, so it is guarded three
/// ways: a finished card is fetched once and never again, ten people opening
/// the same match at once cost one request rather than ten, and none of it
/// happens at all when the day's allowance is nearly gone.
///
/// Whatever we already hold is returned either way. A scorecard a few minutes
/// old is worth far more than an error.
async fn world_match(
    State(state): State<AppState>,
    Path(id): Path<String>,
    _auth: AuthUser,
) -> ApiResult<Json<WorldMatchDetailView>> {
    let Some(summary) = repo::find(&state.pool, &id).await? else {
        return Err(ApiError::not_found("no such match"));
    };

    if let Err(error) = repo::note_watched(&state.pool).await {
        tracing::warn!(%error, "could not record a scores view");
    }

    let mut held = repo::detail(&state.pool, &id).await?;

    if state.feed.enabled() && wants_refresh(&summary, &held) {
        match refresh_detail(&state, &summary).await {
            Ok(Some(fresh)) => held = Some(fresh),
            Ok(None) => {}
            // A scorecard we could not refresh is not a page we cannot draw.
            Err(error) => tracing::warn!(%error, match_id = %id, "scorecard refresh failed"),
        }
    }

    let (detail, detail_as_of) = match held {
        Some((d, at, _)) => (Some(d), Some(at)),
        None => (None, None),
    };
    Ok(Json(WorldMatchDetailView { summary, detail, detail_as_of }))
}

/// Whether the card we hold is worth replacing.
fn wants_refresh(
    summary: &fishers_domain::world_cricket::WorldMatch,
    held: &Option<(fishers_domain::world_cricket_detail::WorldMatchDetail, chrono::DateTime<chrono::Utc>, bool)>,
) -> bool {
    let Some((_, at, final_)) = held else {
        // Nothing at all: worth one request whatever the match is doing.
        return true;
    };
    // The match is over and we have the last word on it. This is what stops a
    // finished match costing a request every time somebody looks at it, which
    // over a season is most of the looking.
    if *final_ {
        return false;
    }
    let age = chrono::Utc::now().signed_duration_since(*at).num_seconds();
    match summary.phase.as_str() {
        fishers_domain::world_cricket::PHASE_LIVE => age > LIVE_DETAIL_SECS,
        fishers_domain::world_cricket::PHASE_PENDING => age > PENDING_DETAIL_SECS,
        // Done, but not yet stored as final: fetch once more to capture the
        // closing card, and it will be marked final on the way in.
        _ => true,
    }
}

/// Claim the allowance, take the per-match lock, fetch, store.
async fn refresh_detail(
    state: &AppState,
    summary: &fishers_domain::world_cricket::WorldMatch,
) -> anyhow::Result<Option<(fishers_domain::world_cricket_detail::WorldMatchDetail, chrono::DateTime<chrono::Utc>, bool)>> {
    let (spent, _, _) = repo::budget(&state.pool).await?;
    if state.feed.cap() - spent <= DETAIL_FLOOR {
        // The list comes first.
        return Ok(None);
    }

    // Single flight. Whoever gets this fetches; everybody else reads what is
    // already stored rather than queueing behind an upstream call.
    let Some(mut conn) = repo::claim_detail(&state.pool, &summary.id).await? else {
        return Ok(None);
    };
    let out = fetch_and_store(state, summary).await;
    if let Err(error) = repo::release_detail_lock(&mut conn, &summary.id).await {
        tracing::warn!(%error, "could not release a scorecard lock");
    }
    out
}

async fn fetch_and_store(
    state: &AppState,
    summary: &fishers_domain::world_cricket::WorldMatch,
) -> anyhow::Result<Option<(fishers_domain::world_cricket_detail::WorldMatchDetail, chrono::DateTime<chrono::Utc>, bool)>> {
    // Claimed before the call and given back if it never landed, exactly as the
    // list poller does: counting after the fact loses requests that were really
    // made, which is the direction that overspends.
    if repo::try_spend(&state.pool, state.feed.cap()).await?.is_none() {
        return Ok(None);
    }
    let (found, quota) = match state.feed.fetch_detail(&summary.id).await {
        Ok(found) => found,
        Err(e) => {
            repo::refund(&state.pool).await.ok();
            return Err(e);
        }
    };
    if let Some((limit, remaining)) = quota {
        repo::reconcile(&state.pool, limit, remaining).await?;
    }
    let Some(detail) = found else { return Ok(None) };

    // A card for a match that has ended will never change again.
    let final_ = summary.phase == fishers_domain::world_cricket::PHASE_DONE;
    repo::store_detail(&state.pool, &summary.id, &detail, final_).await?;
    Ok(Some((detail, chrono::Utc::now(), final_)))
}
