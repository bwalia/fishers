//! Umpiring: who will stand, who has stood, and how it went.
//!
//! Club cricket umpires itself. The batting side gives two, or it is whoever
//! is next in — and the person who does it well every week has had nothing to
//! show for it. These endpoints are that record: a player says they will
//! stand, the app counts the matches, and the people who played say how it
//! went afterwards.

use axum::extract::{Path, State};
use axum::routing::{get, patch, put};
use axum::{Json, Router};
use fishers_db::repos::umpire as umpire_repo;
use fishers_domain::{
    AvailableUmpire, MatchUmpire, PendingUmpireReview, UmpireProfile, UmpireReview,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_club_member;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/umpiring", get(my_profile).patch(set_willing))
        .route("/me/umpiring/pending", get(pending))
        .route("/users/{id}/umpiring", get(their_profile))
        .route("/clubs/{id}/umpires", get(club_umpires))
        .route("/cricket/matches/{id}/umpires", get(match_umpires))
        .route(
            "/cricket/matches/{id}/umpires/{user_id}/review",
            put(leave_review).delete(withdraw_review),
        )
        // Kept separate from the PUT so a client that only wants the flag does
        // not have to send a rating it has no business sending.
        .route("/me/umpiring/note", patch(set_willing))
}

/// The matches waiting on this player's say.
///
/// A review gets left when the app asks for it, not when somebody navigates
/// back to a match from three Sundays ago.
async fn pending(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<PendingUmpireReview>>> {
    Ok(Json(
        umpire_repo::pending_reviews(&state.pool, auth.user_id).await?,
    ))
}

async fn my_profile(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<UmpireProfile>> {
    Ok(Json(umpire_repo::profile(&state.pool, auth.user_id).await?))
}

/// Somebody else's record.
///
/// Gated on a shared club, like every other view of another player. An
/// umpiring record is more public than a phone number and less public than a
/// scoreboard: it is about how somebody did their job in front of two teams,
/// and those two teams are who should see it.
async fn their_profile(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<UmpireProfile>> {
    if id != auth.user_id {
        share_a_club(&state, auth.user_id, id).await?;
    }
    Ok(Json(umpire_repo::profile(&state.pool, id).await?))
}

#[derive(Debug, Deserialize)]
struct Willing {
    /// Absent leaves it alone, so a client can set the note without answering
    /// the question again.
    umpires: Option<bool>,
    /// `Some(None)` clears it; absent leaves it.
    #[serde(default, deserialize_with = "double_option")]
    note: Option<Option<String>>,
}

async fn set_willing(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<Willing>,
) -> ApiResult<Json<UmpireProfile>> {
    let note = body.note.map(|n| {
        n.and_then(|text| {
            let trimmed = text.trim().to_string();
            (!trimmed.is_empty()).then_some(trimmed)
        })
    });
    if let Some(Some(text)) = &note {
        if text.chars().count() > 200 {
            return Err(ApiError::bad_request(
                "keep the umpiring note under 200 characters — it goes on a team sheet",
            ));
        }
    }
    umpire_repo::set_willing(&state.pool, auth.user_id, body.umpires, note).await?;
    Ok(Json(umpire_repo::profile(&state.pool, auth.user_id).await?))
}

async fn club_umpires(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<AvailableUmpire>>> {
    require_club_member(&state, auth.user_id, club_id).await?;
    Ok(Json(
        umpire_repo::available_in_club(&state.pool, club_id).await?,
    ))
}

async fn match_umpires(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(match_id): Path<Uuid>,
) -> ApiResult<Json<Vec<MatchUmpire>>> {
    Ok(Json(
        umpire_repo::match_umpires(&state.pool, match_id, auth.user_id).await?,
    ))
}

#[derive(Debug, Deserialize)]
struct ReviewBody {
    rating: i16,
    comment: Option<String>,
}

/// Rate the umpire, or change the rating already left.
///
/// Three gates, in the order they can be answered cheaply. The match has to be
/// over — rating the umpire at the halfway drinks is not a review of the
/// afternoon. The person has to have been there. And the umpire has to be an
/// umpire of *this* match, so a uuid from another fixture cannot be used to
/// drop a one onto somebody who never stood in front of the reviewer.
async fn leave_review(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((match_id, umpire_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<ReviewBody>,
) -> ApiResult<Json<UmpireReview>> {
    if !(1..=5).contains(&body.rating) {
        return Err(ApiError::bad_request("a rating is one to five"));
    }
    if umpire_id == auth.user_id {
        return Err(ApiError::bad_request("you cannot review your own umpiring"));
    }

    let status = umpire_repo::match_status(&state.pool, match_id)
        .await?
        .ok_or_else(|| ApiError::not_found("no such match"))?;
    // `published` is complete with the scorecard sent out, so it counts.
    if !matches!(status.as_str(), "complete" | "published") {
        return Err(ApiError::bad_request(
            "the match is not over yet — review the umpiring afterwards",
        ));
    }

    if !umpire_repo::took_part(&state.pool, match_id, auth.user_id).await? {
        return Err(ApiError::forbidden(
            "only the people who were in the match can review its umpiring",
        ));
    }
    if !umpire_repo::stood_in(&state.pool, match_id, umpire_id).await? {
        return Err(ApiError::bad_request("they did not umpire this match"));
    }

    let comment = body.comment.and_then(|c| {
        let trimmed = c.trim().to_string();
        (!trimmed.is_empty()).then_some(trimmed)
    });
    if comment.as_deref().is_some_and(|c| c.chars().count() > 1000) {
        return Err(ApiError::bad_request("keep the comment under 1000 characters"));
    }

    Ok(Json(
        umpire_repo::review(
            &state.pool,
            match_id,
            umpire_id,
            auth.user_id,
            body.rating,
            comment.as_deref(),
        )
        .await?,
    ))
}

async fn withdraw_review(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((match_id, umpire_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<serde_json::Value>> {
    let gone = umpire_repo::withdraw_review(&state.pool, match_id, umpire_id, auth.user_id).await?;
    if !gone {
        return Err(ApiError::not_found("you have not reviewed this umpire"));
    }
    Ok(Json(serde_json::json!({ "withdrawn": true })))
}

/// The same gate `stats.rs` puts on looking at another player.
async fn share_a_club(state: &AppState, me: Uuid, them: Uuid) -> ApiResult<()> {
    let mine = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, me).await?;
    let theirs = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, them).await?;
    let shared = mine
        .iter()
        .any(|c| theirs.iter().any(|t| t.club.id == c.club.id));
    if !shared {
        return Err(ApiError::forbidden("not in a shared club"));
    }
    Ok(())
}

/// `null` and absent are different things in a PATCH: one clears the note, the
/// other leaves it alone. serde collapses them unless asked not to.
fn double_option<'de, D, T>(de: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::Deserialize<'de>,
{
    serde::Deserialize::deserialize(de).map(Some)
}
