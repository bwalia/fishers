use axum::extract::{Path, State};
use axum::routing::{get, patch, post};
use axum::{Json, Router};
use fishers_db::repos::clubs as clubs_repo;
use fishers_db::repos::users as users_repo;
use fishers_db::repos::clubs::{
    ClubMemberDetail, ClubMembership, ClubSettings, QrIdentity, UpdateClubSettings,
};
use fishers_domain::{
    parse_role, permissions_for, AddMemberRequest, Club, ClubMember, CreateClubRequest,
    CreateTeamRequest, CreateVenueRequest, Permission, Team, TeamMember, UserRole, Venue,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_club_permission, require_secretary};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs", get(list_clubs).post(create_club))
        .route("/clubs/{id}", get(get_club))
        .route("/clubs/{id}/my-role", get(my_role))
        .route("/clubs/{id}/members", get(list_members).post(add_member))
        .route(
            "/clubs/{id}/members/{user_id}",
            patch(update_member_role).delete(remove_member),
        )
        .route("/clubs/{id}/settings", get(get_settings).patch(update_settings))
        .route("/clubs/{id}/teams", get(list_teams).post(create_team))
        .route("/clubs/{id}/venues", get(list_venues).post(create_venue))
        .route(
            "/teams/{id}/members",
            get(list_team_members).post(add_team_member),
        )
        .route("/clubs/{id}/qr", get(club_qr).post(rotate_qr))
        .route("/teams/{id}/qr", get(team_qr))
        .route("/opponents/lookup", post(lookup_opponent))
        .route("/opponents/search", get(search_opponents))
        .route("/clubs/{id}/page", get(get_page).patch(update_page))
        // No auth: this is the club's shop window.
        .route("/public/clubs/{slug}", get(public_page))
}

#[derive(Serialize)]
struct PublicClubPage {
    club: clubs_repo::ClubPage,
    /// Played, won, lost — and the percentage every club leads with.
    record: Option<SeasonRecord>,
    top_batters: Vec<fishers_domain::PlayerSeasonStatsView>,
    top_bowlers: Vec<fishers_domain::PlayerSeasonStatsView>,
    fixtures: Vec<PublicFixture>,
    /// The player the club chose to lead with.
    icon_player: Option<IconPlayer>,
}

#[derive(Serialize)]
struct IconPlayer {
    name: String,
    avatar_url: Option<String>,
    position: Option<String>,
}

#[derive(Serialize)]
struct SeasonRecord {
    season: i32,
    played: i32,
    won: i32,
    lost: i32,
    drawn: i32,
    no_result: i32,
    /// Of the matches that produced a result — a rained-off game is not a loss.
    win_percent: Option<i32>,
}

#[derive(Serialize)]
struct PublicFixture {
    title: String,
    start_at: chrono::DateTime<chrono::Utc>,
}

/// A club's public page, for anybody at all.
///
/// Deliberately unauthenticated and deliberately narrow: the club's own words,
/// the record they have played to, the players at the top of it, and when they
/// are next out. No rosters, no contact details for members, nothing a club
/// would not put on a noticeboard.
async fn public_page(
    State(state): State<AppState>,
    Path(slug): Path<String>,
) -> ApiResult<Json<PublicClubPage>> {
    let club = clubs_repo::page_by_slug(&state.pool, &slug)
        .await?
        .ok_or_else(|| ApiError::not_found("no club has that address"))?;

    let season = chrono::Utc::now().format("%Y").to_string().parse().unwrap_or(2026);
    let board = fishers_db::repos::stats::club_board(&state.pool, club.id, season)
        .await
        .ok()
        .flatten();

    let record = board.as_ref().map(|b| {
        let c = &b.club;
        let decided = c.wins + c.losses + c.draws;
        SeasonRecord {
            season: c.season_year,
            played: c.matches_played,
            won: c.wins,
            lost: c.losses,
            drawn: c.draws,
            no_result: c.no_results,
            // A no-result is not a loss, so it is out of the sum entirely.
            win_percent: (decided > 0).then(|| (c.wins * 100) / decided),
        }
    });

    let fixtures = fishers_db::repos::events::upcoming_for_club(&state.pool, club.id, 5)
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|e| PublicFixture {
            title: e.title,
            start_at: e.start_at,
        })
        .collect();

    // Only what a club would put on a poster: a name, a face, a position.
    let icon_player = match club.icon_player_id {
        Some(id) => users_repo::find_by_id(&state.pool, id).await.ok().flatten().map(|u| {
            // Their position for the sport they lead with. `position_role` is
            // the single-sport column this replaced, kept as the fallback for
            // anyone who has not filled a sport profile in.
            let position = u
                .sport_profiles
                .0
                .iter()
                .find(|p| Some(&p.sport) == u.primary_sport.as_ref())
                .or_else(|| u.sport_profiles.0.first())
                .and_then(|p| p.position.clone())
                .or(u.position_role);
            IconPlayer {
                name: u.name,
                avatar_url: u.avatar_url,
                position,
            }
        }),
        None => None,
    };

    Ok(Json(PublicClubPage {
        icon_player,
        club,
        record,
        top_batters: board.as_ref().map(|b| b.top_batters.clone()).unwrap_or_default(),
        top_bowlers: board.as_ref().map(|b| b.top_bowlers.clone()).unwrap_or_default(),
        fixtures,
    }))
}

async fn get_page(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<clubs_repo::ClubPage>> {
    require_club_member(&state, id, auth.user_id).await?;
    clubs_repo::page_for(&state.pool, id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("club not found"))
}

async fn update_page(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<clubs_repo::UpdateClubPage>,
) -> ApiResult<Json<clubs_repo::ClubPage>> {
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;

    if let Some(slug) = body.slug.as_deref() {
        let clean = slug.trim().to_lowercase();
        // It goes in a URL, so keep it to what survives one.
        if clean.len() < 3
            || !clean
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-')
        {
            return Err(ApiError::bad_request(
                "the address needs at least three letters, numbers or hyphens",
            ));
        }
    }

    clubs_repo::update_page(&state.pool, id, &body)
        .await
        .map(Json)
        .map_err(|e| {
            if e.to_string().contains("clubs_slug_key") {
                ApiError::conflict("another club already has that address")
            } else {
                ApiError::from(e)
            }
        })
}

async fn create_club(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreateClubRequest>,
) -> ApiResult<Json<Club>> {
    body.validate()?;
    // Whoever starts a club runs it, so it must be a real, reachable person.
    super::verification::require_verified(&state, auth.user_id).await?;
    let club = clubs_repo::create_club(&state.pool, auth.user_id, &body).await?;
    Ok(Json(club))
}

async fn list_clubs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<ClubMembership>>> {
    Ok(Json(
        clubs_repo::list_clubs_for_user(&state.pool, auth.user_id).await?,
    ))
}

async fn get_club(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Club>> {
    require_club_member(&state, id, auth.user_id).await?;
    let club = clubs_repo::get_club(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))?;
    Ok(Json(club))
}

#[derive(Serialize)]
struct MyRoleResponse {
    role: UserRole,
    display_name: &'static str,
    /// Product alias — club_admin is the club secretary.
    is_secretary: bool,
    is_captain: bool,
    can_invite_to_play: bool,
    can_score_match: bool,
    permissions: Vec<&'static str>,
}

async fn my_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MyRoleResponse>> {
    let role = require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(MyRoleResponse {
        role,
        display_name: role.display_name(),
        is_secretary: matches!(role, UserRole::ClubAdmin | UserRole::SuperAdmin),
        is_captain: matches!(
            role,
            UserRole::TeamCaptain
                | UserRole::TeamViceCaptain
                | UserRole::ClubAdmin
                | UserRole::SuperAdmin
        ),
        can_invite_to_play: role.can_invite_to_play(),
        can_score_match: role.can_score_match(),
        permissions: permissions_for(role)
            .iter()
            .map(|p| p.as_str())
            .collect(),
    }))
}

async fn list_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<ClubMemberDetail>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_member_details(&state.pool, id).await?))
}

#[derive(serde::Deserialize)]
struct AddMemberBody {
    /// Every field is optional because a secretary supplies exactly one of an
    /// id or an identifier — flattening `AddMemberRequest` here would demand
    /// the id they came to look up.
    user_id: Option<Uuid>,
    role: Option<UserRole>,
    /// Add by email or mobile number when the secretary does not know the id.
    identifier: Option<String>,
    /// The old name for the same thing, so existing callers keep working.
    email: Option<String>,
}

async fn add_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AddMemberBody>,
) -> ApiResult<Json<ClubMember>> {
    // Only a secretary adds members, and only a secretary appoints captains.
    require_secretary(&state, id, auth.user_id).await?;

    // An email or a mobile number: a member who registered with a number has no
    // address to be looked up by, and asking for one would make them
    // impossible to add.
    let given = body
        .identifier
        .as_deref()
        .or(body.email.as_deref())
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let user_id = match given {
        Some(identifier) => clubs_repo::find_user_by_identifier(&state.pool, identifier)
            .await?
            .map(|(id, _, _)| id)
            .ok_or_else(|| {
                ApiError::not_found("nobody with that email or number has a Fishers account yet")
            })?,
        None => body.user_id.ok_or_else(|| {
            ApiError::bad_request("give a user_id, an email address or a mobile number")
        })?,
    };

    let request = AddMemberRequest {
        user_id,
        role: body.role,
    };
    Ok(Json(clubs_repo::add_member(&state.pool, id, &request).await?))
}

#[derive(serde::Deserialize)]
struct RoleBody {
    /// Accepts the product words too: `secretary`, `captain`, `vice_captain`.
    role: String,
}

/// Appoint a captain, a vice captain, or stand someone down.
async fn update_member_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, user_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<RoleBody>,
) -> ApiResult<Json<ClubMember>> {
    require_secretary(&state, club_id, auth.user_id).await?;
    let role = parse_role(&body.role)
        .ok_or_else(|| ApiError::bad_request(format!("unknown role: {}", body.role)))?;
    if role == UserRole::SuperAdmin {
        return Err(ApiError::forbidden(
            "platform administrators are not appointed from inside a club",
        ));
    }

    // A club without a secretary cannot appoint one, so never remove the last.
    let current = clubs_repo::club_role(&state.pool, club_id, user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("that person is not in this club"))?;
    let losing_a_secretary = matches!(current, UserRole::ClubAdmin | UserRole::SuperAdmin)
        && !matches!(role, UserRole::ClubAdmin | UserRole::SuperAdmin);
    if losing_a_secretary && clubs_repo::count_secretaries(&state.pool, club_id).await? <= 1 {
        return Err(ApiError::conflict(
            "this is the club's last secretary — appoint another one first",
        ));
    }

    clubs_repo::update_member_role(&state.pool, club_id, user_id, role)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("that person is not in this club"))
}

async fn remove_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, user_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<serde_json::Value>> {
    require_secretary(&state, club_id, auth.user_id).await?;
    let current = clubs_repo::club_role(&state.pool, club_id, user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("that person is not in this club"))?;
    if matches!(current, UserRole::ClubAdmin | UserRole::SuperAdmin)
        && clubs_repo::count_secretaries(&state.pool, club_id).await? <= 1
    {
        return Err(ApiError::conflict(
            "this is the club's last secretary — appoint another one first",
        ));
    }
    let removed = clubs_repo::remove_member(&state.pool, club_id, user_id).await?;
    Ok(Json(serde_json::json!({ "removed": removed })))
}

/// Club policy: how much the assistant may do, when players are chased for a
/// reconfirmation, and how hard match fees are pursued.
async fn get_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<ClubSettings>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::get_settings(&state.pool, id).await?))
}

async fn update_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateClubSettings>,
) -> ApiResult<Json<ClubSettings>> {
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;

    if let Some(autonomy) = body.selection_autonomy.as_deref() {
        if !matches!(autonomy, "off" | "suggest" | "auto_publish") {
            return Err(ApiError::bad_request(
                "autonomy must be off, suggest or auto_publish",
            ));
        }
    }
    for (label, value) in [
        ("confirm_lead_hours", body.confirm_lead_hours),
        ("drop_lead_hours", body.drop_lead_hours),
        ("fee_chase_after_hours", body.fee_chase_after_hours),
    ] {
        if let Some(hours) = value {
            if !(0..=336).contains(&hours) {
                return Err(ApiError::bad_request(format!(
                    "{label} must be between 0 and 336 hours"
                )));
            }
        }
    }
    if let Some(max) = body.fee_chase_max_reminders {
        if !(0..=10).contains(&max) {
            return Err(ApiError::bad_request("at most ten reminders"));
        }
    }

    Ok(Json(
        clubs_repo::update_settings(&state.pool, id, &body).await?,
    ))
}

async fn create_team(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateTeamRequest>,
) -> ApiResult<Json<Team>> {
    body.validate()?;
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    Ok(Json(
        clubs_repo::create_team(&state.pool, id, &body).await?,
    ))
}

async fn list_teams(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Team>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_teams(&state.pool, id).await?))
}

async fn create_venue(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateVenueRequest>,
) -> ApiResult<Json<Venue>> {
    body.validate()?;
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    Ok(Json(
        clubs_repo::create_venue(&state.pool, id, &body).await?,
    ))
}

async fn list_venues(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Venue>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_venues(&state.pool, id).await?))
}

#[derive(serde::Deserialize)]
struct TeamMemberBody {
    user_id: Uuid,
    role: Option<UserRole>,
}

/// A team's roster. Any club member may read it — knowing who is in the 2nd XI
/// is not privileged information inside a club.
async fn list_team_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<clubs_repo::TeamMemberDetail>>> {
    let team = clubs_repo::get_team(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("team not found"))?;
    require_club_member(&state, team.club_id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_team_members(&state.pool, id).await?))
}

async fn add_team_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<TeamMemberBody>,
) -> ApiResult<Json<TeamMember>> {
    let team = clubs_repo::get_team(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("team not found"))?;
    // Secretary can always add; team captain can invite onto their team.
    require_club_permission(
        &state,
        team.club_id,
        auth.user_id,
        Permission::InviteToTeam,
    )
    .await?;
    // Only secretary may appoint another captain.
    if matches!(body.role, Some(UserRole::TeamCaptain | UserRole::ClubAdmin)) {
        require_secretary(&state, team.club_id, auth.user_id).await?;
    }
    let role = body.role.unwrap_or(UserRole::Member);
    Ok(Json(
        clubs_repo::add_team_member(&state.pool, id, body.user_id, role).await?,
    ))
}


/// What a QR code carries, and what the app draws.
#[derive(Serialize)]
struct QrResponse {
    #[serde(flatten)]
    identity: QrIdentity,
    /// Encoded into the QR image. A phone camera that is not Fishers opens the
    /// club's page; the app pulls the token out of it.
    payload: String,
    /// The code already drawn, so a browser can show it without carrying a QR
    /// encoder of its own — error correction is not a few lines of JavaScript.
    svg: String,
}

/// The payload as a scannable square.
fn qr_svg(payload: &str) -> String {
    use qrcode::render::svg;
    match qrcode::QrCode::new(payload.as_bytes()) {
        Ok(code) => {
            let drawn = code
                .render()
                .min_dimensions(220, 220)
                .dark_color(svg::Color("#0b2f1e"))
                .light_color(svg::Color("#ffffff"))
                .build();
            // Drop the XML declaration so a client can drop this straight into
            // a page rather than having to parse it out.
            match drawn.find("<svg") {
                Some(at) => drawn[at..].to_string(),
                None => drawn,
            }
        }
        // A code that will not encode is not worth failing the request over —
        // the payload is still shown and can be typed in.
        Err(_) => String::new(),
    }
}

fn qr_payload(identity: &QrIdentity) -> String {
    let base = std::env::var("PUBLIC_WEB_BASE")
        .unwrap_or_else(|_| "https://fishers.app".into());
    let base = base.trim_end_matches('/');
    format!("{base}/play/{}", identity.qr_token)
}

/// The club's own code, to show an opposition captain at the ground.
async fn club_qr(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<QrResponse>> {
    require_club_member(&state, id, auth.user_id).await?;
    let identity = clubs_repo::club_qr(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))?;
    let payload = qr_payload(&identity);
    let svg = qr_svg(&payload);
    Ok(Json(QrResponse { identity, payload, svg }))
}

async fn team_qr(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<QrResponse>> {
    let team = clubs_repo::get_team(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("team not found"))?;
    require_club_member(&state, team.club_id, auth.user_id).await?;
    let identity = clubs_repo::team_qr(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("team not found"))?;
    let payload = qr_payload(&identity);
    let svg = qr_svg(&payload);
    Ok(Json(QrResponse { identity, payload, svg }))
}

/// Retire a code that has been handed out too widely.
async fn rotate_qr(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<QrResponse>> {
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    clubs_repo::rotate_club_qr(&state.pool, id).await?;
    let identity = clubs_repo::club_qr(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))?;
    let payload = qr_payload(&identity);
    let svg = qr_svg(&payload);
    Ok(Json(QrResponse { identity, payload, svg }))
}

#[derive(Deserialize)]
struct LookupBody {
    /// The scanned token, or the whole URL the camera read.
    token: String,
}

/// Resolve a scanned code to the side it belongs to.
///
/// Not gated on membership — the point is that a club you have never played can
/// scan your code at the ground. The token is the secret, and this only ever
/// returns a name: no roster, no fixtures, no contact details.
async fn lookup_opponent(
    State(state): State<AppState>,
    _auth: AuthUser,
    Json(body): Json<LookupBody>,
) -> ApiResult<Json<QrIdentity>> {
    let token = body
        .token
        .trim()
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_string();
    if token.is_empty() {
        return Err(ApiError::bad_request("that code is empty"));
    }
    clubs_repo::resolve_qr(&state.pool, &token)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("no club or team has that code"))
}

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
}

/// Find an opposition by name, for when nobody has a code to scan.
async fn search_opponents(
    State(state): State<AppState>,
    auth: AuthUser,
    axum::extract::Query(query): axum::extract::Query<SearchQuery>,
) -> ApiResult<Json<Vec<QrIdentity>>> {
    let q = query.q.trim();
    if q.len() < 2 {
        return Err(ApiError::bad_request("give at least two letters to search on"));
    }
    // Who is asking decides what they can see: their own clubs are findable
    // even when invite-only.
    Ok(Json(
        clubs_repo::search_opponents(&state.pool, q, auth.user_id, 25).await?,
    ))
}
