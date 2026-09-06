//! Secure live scoreboard share links — minted by scorers, posted into chat, viewed without login.

use axum::extract::{Path, State};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use fishers_db::repos::{
    chat as chat_repo, clubs as clubs_repo, cricket as cricket_repo,
    scoreboard_shares as share_repo, users as users_repo,
};
use fishers_domain::{MatchState, Permission};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{HashMap, HashSet};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_permission};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/cricket/matches/{id}/share", post(create_share))
        .route("/cricket/matches/{id}/share", delete(revoke_share))
        .route("/public/scoreboard/{token}", get(public_scoreboard))
}

#[derive(Debug, Deserialize)]
pub struct CreateShareBody {
    /// When true (default), post the live link into the fixture/club chat thread.
    #[serde(default = "default_true")]
    pub post_to_chat: bool,
    /// Share lifetime in hours (default 48, max 168).
    #[serde(default = "default_ttl")]
    pub ttl_hours: i64,
}

fn default_true() -> bool {
    true
}
fn default_ttl() -> i64 {
    48
}

#[derive(Debug, Serialize)]
pub struct ShareResponse {
    pub token: String,
    pub url: String,
    pub expires_at: chrono::DateTime<chrono::Utc>,
    pub conversation_id: Option<Uuid>,
    pub message_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
struct RevokeBody {
    token: String,
}

#[derive(Debug, Serialize)]
pub struct PublicScoreboard {
    pub match_id: Uuid,
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub club_name: Option<String>,
    pub home_name: String,
    pub away_name: String,
    pub status: String,
    pub overs_limit: i32,
    pub last_seq: i64,
    pub state: MatchState,
    pub player_names: HashMap<String, String>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
    pub refreshed_at: chrono::DateTime<chrono::Utc>,
}

fn public_web_base() -> String {
    std::env::var("PUBLIC_WEB_BASE")
        .or_else(|_| std::env::var("WEB_BASE_URL"))
        .unwrap_or_else(|_| "http://127.0.0.1:3000".into())
        .trim_end_matches('/')
        .to_string()
}

fn share_url(token: &str) -> String {
    format!("{}/live/{}", public_web_base(), token)
}

async fn create_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(match_id): Path<Uuid>,
    Json(body): Json<CreateShareBody>,
) -> ApiResult<Json<ShareResponse>> {
    let row = cricket_repo::get_match(&state.pool, match_id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    let can_score = require_permission(
        &state,
        row.club_id,
        auth.user_id,
        None,
        Permission::ScoreMatch,
    )
    .await
    .is_ok()
        || cricket_repo::is_official(&state.pool, row.id, auth.user_id).await?;

    if !can_score {
        require_club_member(&state, row.club_id, auth.user_id).await?;
    }

    let ttl = body.ttl_hours.clamp(1, 168);
    let share = share_repo::create_or_reuse(&state.pool, match_id, auth.user_id, ttl).await?;
    let url = share_url(&share.token);

    let mut conversation_id = share.conversation_id;
    let mut message_id = None;

    if body.post_to_chat {
        if let Some(cid) =
            chat_repo::conversation_for_announcement(&state.pool, row.club_id, Some(row.event_id))
                .await?
        {
            let body_text = format!(
                "Live scoreboard: {} vs {}\n{}",
                row.home_name, row.away_name, url
            );
            let msg = chat_repo::post_message(
                &state.pool,
                cid,
                Some(auth.user_id),
                "system",
                &body_text,
                json!({
                    "kind": "scoreboard_share",
                    "match_id": match_id,
                    "token": share.token,
                    "url": url,
                }),
            )
            .await?;
            share_repo::attach_conversation(&state.pool, share.id, cid).await?;
            conversation_id = Some(cid);
            message_id = Some(msg.id);

            if let Ok(recipients) = chat_repo::member_ids(&state.pool, cid).await {
                for uid in recipients.into_iter().filter(|u| *u != auth.user_id) {
                    let _ = state
                        .push
                        .send(
                            uid,
                            "scoreboard_share",
                            "Live scoreboard",
                            &format!(
                                "{} vs {} — open the link in chat",
                                row.home_name, row.away_name
                            ),
                            json!({ "type": "scoreboard_share", "token": share.token }),
                        )
                        .await;
                }
            }
        }
    }

    Ok(Json(ShareResponse {
        token: share.token,
        url,
        expires_at: share.expires_at,
        conversation_id,
        message_id,
    }))
}

async fn revoke_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(match_id): Path<Uuid>,
    Json(body): Json<RevokeBody>,
) -> ApiResult<Json<serde_json::Value>> {
    let row = cricket_repo::get_match(&state.pool, match_id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_permission(
        &state,
        row.club_id,
        auth.user_id,
        None,
        Permission::ScoreMatch,
    )
    .await?;
    let n = share_repo::revoke(&state.pool, match_id, &body.token).await?;
    if n == 0 {
        return Err(ApiError::not_found("share not found"));
    }
    Ok(Json(json!({ "ok": true })))
}

async fn public_scoreboard(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> ApiResult<Json<PublicScoreboard>> {
    let share = share_repo::find_valid_by_token(&state.pool, &token)
        .await?
        .ok_or_else(|| ApiError::not_found("scoreboard link invalid or expired"))?;

    let row = cricket_repo::get_match(&state.pool, share.match_id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    let match_state = cricket_repo::parse_state(&row);
    let club_name = clubs_repo::get_club(&state.pool, row.club_id)
        .await?
        .map(|c| c.name);

    let mut ids = HashSet::new();
    ids.extend(match_state.home_xi.iter().copied());
    ids.extend(match_state.away_xi.iter().copied());
    for inn in &match_state.innings {
        for b in &inn.batters {
            ids.insert(b.player_id);
        }
        for b in &inn.bowlers {
            ids.insert(b.player_id);
        }
        if let Some(id) = inn.striker_id {
            ids.insert(id);
        }
        if let Some(id) = inn.non_striker_id {
            ids.insert(id);
        }
        if let Some(id) = inn.bowler_id {
            ids.insert(id);
        }
    }
    let id_list: Vec<Uuid> = ids.into_iter().collect();
    let names = users_repo::names_for(&state.pool, &id_list)
        .await
        .unwrap_or_default();
    let player_names = names
        .into_iter()
        .map(|(id, name)| (id.to_string(), name))
        .collect();

    Ok(Json(PublicScoreboard {
        match_id: row.id,
        event_id: row.event_id,
        club_id: row.club_id,
        club_name,
        home_name: row.home_name,
        away_name: row.away_name,
        status: row.status,
        overs_limit: row.overs_limit,
        last_seq: row.last_seq,
        state: match_state,
        player_names,
        expires_at: share.expires_at,
        refreshed_at: chrono::Utc::now(),
    }))
}
