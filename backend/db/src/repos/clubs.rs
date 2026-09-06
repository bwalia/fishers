use fishers_domain::{
    AddMemberRequest, Club, ClubMember, ClubVisibility, CreateClubRequest, CreateTeamRequest,
    CreateVenueRequest, MembershipStatus, Team, TeamMember, UserRole, Venue,
};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_club(
    pool: &PgPool,
    owner_id: Uuid,
    req: &CreateClubRequest,
) -> Result<Club, sqlx::Error> {
    let visibility = req.visibility.unwrap_or(ClubVisibility::InviteOnly);
    let is_informal = req.is_informal_group.unwrap_or(false);
    let sport_types: Vec<String> = req
        .sport_types
        .iter()
        .filter_map(|s| serde_json::to_value(s).ok())
        .filter_map(|v| v.as_str().map(str::to_string))
        .collect();

    let mut tx = pool.begin().await?;

    let club = sqlx::query_as::<_, Club>(
        r#"
        INSERT INTO clubs (name, sport_types, visibility, owner_id, description, is_informal_group)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, name, sport_types, visibility, owner_id, description,
                  is_informal_group, created_at, updated_at
        "#,
    )
    .bind(&req.name)
    .bind(&sport_types)
    .bind(visibility)
    .bind(owner_id)
    .bind(&req.description)
    .bind(is_informal)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO club_members (club_id, user_id, role, status)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(club.id)
    .bind(owner_id)
    .bind(UserRole::ClubAdmin)
    .bind(MembershipStatus::Active)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(club)
}

pub async fn list_clubs_for_user(pool: &PgPool, user_id: Uuid) -> Result<Vec<Club>, sqlx::Error> {
    sqlx::query_as::<_, Club>(
        r#"
        SELECT c.id, c.name, c.sport_types, c.visibility, c.owner_id, c.description,
               c.is_informal_group, c.created_at, c.updated_at
        FROM clubs c
        INNER JOIN club_members m ON m.club_id = c.id
        WHERE m.user_id = $1 AND m.status = 'active'
        ORDER BY c.name
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

pub async fn get_club(pool: &PgPool, club_id: Uuid) -> Result<Option<Club>, sqlx::Error> {
    sqlx::query_as::<_, Club>(
        r#"
        SELECT id, name, sport_types, visibility, owner_id, description,
               is_informal_group, created_at, updated_at
        FROM clubs WHERE id = $1
        "#,
    )
    .bind(club_id)
    .fetch_optional(pool)
    .await
}

pub async fn list_members(pool: &PgPool, club_id: Uuid) -> Result<Vec<ClubMember>, sqlx::Error> {
    sqlx::query_as::<_, ClubMember>(
        r#"
        SELECT club_id, user_id, role, status, joined_at
        FROM club_members WHERE club_id = $1
        ORDER BY joined_at
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn add_member(
    pool: &PgPool,
    club_id: Uuid,
    req: &AddMemberRequest,
) -> Result<ClubMember, sqlx::Error> {
    let role = req.role.unwrap_or(UserRole::Member);
    sqlx::query_as::<_, ClubMember>(
        r#"
        INSERT INTO club_members (club_id, user_id, role, status)
        VALUES ($1, $2, $3, 'active')
        ON CONFLICT (club_id, user_id) DO UPDATE
          SET role = EXCLUDED.role, status = 'active'
        RETURNING club_id, user_id, role, status, joined_at
        "#,
    )
    .bind(club_id)
    .bind(req.user_id)
    .bind(role)
    .fetch_one(pool)
    .await
}

pub async fn create_team(
    pool: &PgPool,
    club_id: Uuid,
    req: &CreateTeamRequest,
) -> Result<Team, sqlx::Error> {
    sqlx::query_as::<_, Team>(
        r#"
        INSERT INTO teams (club_id, sport, name)
        VALUES ($1, $2, $3)
        RETURNING id, club_id, sport, name, created_at
        "#,
    )
    .bind(club_id)
    .bind(req.sport)
    .bind(&req.name)
    .fetch_one(pool)
    .await
}

pub async fn list_teams(pool: &PgPool, club_id: Uuid) -> Result<Vec<Team>, sqlx::Error> {
    sqlx::query_as::<_, Team>(
        r#"
        SELECT id, club_id, sport, name, created_at
        FROM teams WHERE club_id = $1 ORDER BY name
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn add_team_member(
    pool: &PgPool,
    team_id: Uuid,
    user_id: Uuid,
    role: UserRole,
) -> Result<TeamMember, sqlx::Error> {
    sqlx::query_as::<_, TeamMember>(
        r#"
        INSERT INTO team_members (team_id, user_id, role)
        VALUES ($1, $2, $3)
        ON CONFLICT (team_id, user_id) DO UPDATE SET role = EXCLUDED.role
        RETURNING team_id, user_id, role, joined_at
        "#,
    )
    .bind(team_id)
    .bind(user_id)
    .bind(role)
    .fetch_one(pool)
    .await
}

pub async fn create_venue(
    pool: &PgPool,
    club_id: Uuid,
    req: &CreateVenueRequest,
) -> Result<Venue, sqlx::Error> {
    sqlx::query_as::<_, Venue>(
        r#"
        INSERT INTO venues (club_id, name, address, lat, lng)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, club_id, name, address, lat, lng, created_at
        "#,
    )
    .bind(club_id)
    .bind(&req.name)
    .bind(&req.address)
    .bind(req.lat)
    .bind(req.lng)
    .fetch_one(pool)
    .await
}

pub async fn list_venues(pool: &PgPool, club_id: Uuid) -> Result<Vec<Venue>, sqlx::Error> {
    sqlx::query_as::<_, Venue>(
        r#"
        SELECT id, club_id, name, address, lat, lng, created_at
        FROM venues WHERE club_id = $1 ORDER BY name
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Active club role for RBAC (`club_admin` = secretary, `team_captain`, …).
pub async fn club_role(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<Option<UserRole>, sqlx::Error> {
    sqlx::query_scalar::<_, UserRole>(
        r#"
        SELECT role FROM club_members
        WHERE club_id = $1 AND user_id = $2 AND status = 'active'
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

pub async fn is_club_member(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let row: (bool,) = sqlx::query_as(
        r#"
        SELECT EXISTS(
          SELECT 1 FROM club_members
          WHERE club_id = $1 AND user_id = $2 AND status = 'active'
        )
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

pub async fn team_role(
    pool: &PgPool,
    team_id: Uuid,
    user_id: Uuid,
) -> Result<Option<UserRole>, sqlx::Error> {
    sqlx::query_scalar::<_, UserRole>(
        r#"
        SELECT role FROM team_members
        WHERE team_id = $1 AND user_id = $2
        "#,
    )
    .bind(team_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

pub async fn get_team(pool: &PgPool, team_id: Uuid) -> Result<Option<Team>, sqlx::Error> {
    sqlx::query_as::<_, Team>(
        r#"
        SELECT id, club_id, sport, name, created_at
        FROM teams WHERE id = $1
        "#,
    )
    .bind(team_id)
    .fetch_optional(pool)
    .await
}

/// Highest of club role and (optional) team role for permission checks.
pub async fn effective_membership_role(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
    team_id: Option<Uuid>,
) -> Result<Option<UserRole>, sqlx::Error> {
    let club = club_role(pool, club_id, user_id).await?;
    let team = if let Some(tid) = team_id {
        team_role(pool, tid, user_id).await?
    } else {
        None
    };
    Ok(fishers_domain::effective_role(club, team))
}

/// True when the two users are active members of at least one club together.
/// The gate for "may I see this person's availability".
pub async fn shares_a_club(
    pool: &PgPool,
    a: Uuid,
    b: Uuid,
) -> Result<bool, sqlx::Error> {
    let row: (bool,) = sqlx::query_as(
        r#"
        SELECT EXISTS(
          SELECT 1
          FROM club_members ma
          JOIN club_members mb ON mb.club_id = ma.club_id
          WHERE ma.user_id = $1 AND mb.user_id = $2
            AND ma.status = 'active' AND mb.status = 'active'
        )
        "#,
    )
    .bind(a)
    .bind(b)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

/// Clubs the user is an active member of — the scope for anything not asked
/// for by club id.
pub async fn club_ids_for_user(pool: &PgPool, user_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT club_id FROM club_members WHERE user_id = $1 AND status = 'active'",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}

/// Remove someone from a club. Their history stays; only the membership goes.
pub async fn remove_member(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let result = sqlx::query(
        "UPDATE club_members SET status = 'left' WHERE club_id = $1 AND user_id = $2",
    )
    .bind(club_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// The roster as an admin screen needs it: who, what role, and how to reach them.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct ClubMemberDetail {
    pub user_id: Uuid,
    pub name: String,
    pub email: String,
    pub phone: Option<String>,
    pub role: UserRole,
    pub status: MembershipStatus,
    pub joined_at: chrono::DateTime<chrono::Utc>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
}

pub async fn list_member_details(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<ClubMemberDetail>, sqlx::Error> {
    sqlx::query_as::<_, ClubMemberDetail>(
        r#"
        SELECT cm.user_id, u.name, u.email, u.phone, cm.role, cm.status, cm.joined_at,
               u.position_role, u.skill_level
        FROM club_members cm
        JOIN users u ON u.id = cm.user_id
        WHERE cm.club_id = $1
        ORDER BY
          CASE cm.role
            WHEN 'super_admin' THEN 0 WHEN 'club_admin' THEN 1
            WHEN 'team_captain' THEN 2 WHEN 'team_vice_captain' THEN 3
            ELSE 4 END,
          u.name
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Find someone by email so a secretary can add them without knowing their id.
pub async fn find_user_by_email(
    pool: &PgPool,
    email: &str,
) -> Result<Option<(Uuid, String, String)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String, String)>(
        "SELECT id, name, email FROM users WHERE lower(email) = lower($1)",
    )
    .bind(email)
    .fetch_optional(pool)
    .await
}

/// How many club secretaries are left — a club must never lose its last one.
pub async fn count_secretaries(pool: &PgPool, club_id: Uuid) -> Result<i64, sqlx::Error> {
    let row: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*) FROM club_members
        WHERE club_id = $1 AND status = 'active'
          AND role IN ('club_admin', 'super_admin')
        "#,
    )
    .bind(club_id)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

/// Change someone's role. Returns `None` when they are not in the club.
pub async fn update_member_role(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
    role: UserRole,
) -> Result<Option<ClubMember>, sqlx::Error> {
    sqlx::query_as::<_, ClubMember>(
        r#"
        UPDATE club_members SET role = $3
        WHERE club_id = $1 AND user_id = $2
        RETURNING club_id, user_id, role, status, joined_at
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .bind(role)
    .fetch_optional(pool)
    .await
}

/// The knobs a club secretary can turn: how much the assistant may do, when
/// players are chased, and how hard fees are pursued.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct ClubSettings {
    pub selection_autonomy: String,
    pub confirm_lead_hours: i32,
    pub drop_lead_hours: i32,
    pub fee_chase_after_hours: i32,
    pub fee_chase_max_reminders: i32,
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
pub struct UpdateClubSettings {
    /// `off` | `suggest` | `auto_publish`
    pub selection_autonomy: Option<String>,
    pub confirm_lead_hours: Option<i32>,
    pub drop_lead_hours: Option<i32>,
    pub fee_chase_after_hours: Option<i32>,
    pub fee_chase_max_reminders: Option<i32>,
}

pub async fn get_settings(pool: &PgPool, club_id: Uuid) -> Result<ClubSettings, sqlx::Error> {
    sqlx::query_as::<_, ClubSettings>(
        "SELECT selection_autonomy, confirm_lead_hours, drop_lead_hours,
                fee_chase_after_hours, fee_chase_max_reminders
         FROM clubs WHERE id = $1",
    )
    .bind(club_id)
    .fetch_one(pool)
    .await
}

pub async fn update_settings(
    pool: &PgPool,
    club_id: Uuid,
    req: &UpdateClubSettings,
) -> Result<ClubSettings, sqlx::Error> {
    sqlx::query_as::<_, ClubSettings>(
        r#"
        UPDATE clubs SET
            selection_autonomy      = COALESCE($2, selection_autonomy),
            confirm_lead_hours      = COALESCE($3, confirm_lead_hours),
            drop_lead_hours         = COALESCE($4, drop_lead_hours),
            fee_chase_after_hours   = COALESCE($5, fee_chase_after_hours),
            fee_chase_max_reminders = COALESCE($6, fee_chase_max_reminders),
            updated_at = NOW()
        WHERE id = $1
        RETURNING selection_autonomy, confirm_lead_hours, drop_lead_hours,
                  fee_chase_after_hours, fee_chase_max_reminders
        "#,
    )
    .bind(club_id)
    .bind(&req.selection_autonomy)
    .bind(req.confirm_lead_hours)
    .bind(req.drop_lead_hours)
    .bind(req.fee_chase_after_hours)
    .bind(req.fee_chase_max_reminders)
    .fetch_one(pool)
    .await
}
