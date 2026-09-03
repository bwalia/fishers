use crate::rows::{ClubMemberRow, ClubRow, TeamRow};
use sqlx::PgPool;
use uuid::Uuid;

const CLUB_COLS: &str = "id, name, sport_types, visibility, owner_id, created_at";
const TEAM_COLS: &str = "id, club_id, sport, name, division, age_group";

/// Create a club and enrol the owner as an active admin member.
pub async fn create(
    pool: &PgPool,
    name: &str,
    sport_types: &[String],
    visibility: &str,
    owner_id: Uuid,
) -> Result<ClubRow, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let club = sqlx::query_as::<_, ClubRow>(&format!(
        "INSERT INTO clubs (name, sport_types, visibility, owner_id)
         VALUES ($1, $2, $3, $4) RETURNING {CLUB_COLS}"
    ))
    .bind(name)
    .bind(sport_types)
    .bind(visibility)
    .bind(owner_id)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(
        "INSERT INTO club_members (club_id, user_id, role, status) VALUES ($1, $2, 'admin', 'active')",
    )
    .bind(club.id)
    .bind(owner_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(club)
}

/// Clubs the user is an active member of.
pub async fn for_member(pool: &PgPool, user_id: Uuid) -> Result<Vec<ClubRow>, sqlx::Error> {
    sqlx::query_as::<_, ClubRow>(&format!(
        "SELECT c.{} FROM clubs c
         JOIN club_members m ON m.club_id = c.id
         WHERE m.user_id = $1 AND m.status = 'active'
         ORDER BY c.name",
        CLUB_COLS.replace(", ", ", c.")
    ))
    .bind(user_id)
    .fetch_all(pool)
    .await
}

/// Public clubs, for discovery.
pub async fn public_clubs(pool: &PgPool) -> Result<Vec<ClubRow>, sqlx::Error> {
    sqlx::query_as::<_, ClubRow>(&format!(
        "SELECT {CLUB_COLS} FROM clubs WHERE visibility = 'public' ORDER BY name LIMIT 200"
    ))
    .fetch_all(pool)
    .await
}

pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<Option<ClubRow>, sqlx::Error> {
    sqlx::query_as::<_, ClubRow>(&format!("SELECT {CLUB_COLS} FROM clubs WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

/// The user's active role in a club, if any.
pub async fn membership_role(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<Option<String>, sqlx::Error> {
    sqlx::query_scalar::<_, String>(
        "SELECT role FROM club_members WHERE club_id = $1 AND user_id = $2 AND status = 'active'",
    )
    .bind(club_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

pub async fn members(pool: &PgPool, club_id: Uuid) -> Result<Vec<ClubMemberRow>, sqlx::Error> {
    sqlx::query_as::<_, ClubMemberRow>(
        "SELECT m.user_id, u.name, u.avatar_url, m.role, m.status, m.joined_at
         FROM club_members m JOIN users u ON u.id = m.user_id
         WHERE m.club_id = $1 AND m.status <> 'removed'
         ORDER BY u.name",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Add (or re-activate) a member. Idempotent.
pub async fn add_member(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
    role: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO club_members (club_id, user_id, role, status) VALUES ($1, $2, $3, 'active')
         ON CONFLICT (club_id, user_id)
         DO UPDATE SET role = EXCLUDED.role, status = 'active'",
    )
    .bind(club_id)
    .bind(user_id)
    .bind(role)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn teams(pool: &PgPool, club_id: Uuid) -> Result<Vec<TeamRow>, sqlx::Error> {
    sqlx::query_as::<_, TeamRow>(
        &format!("SELECT {TEAM_COLS} FROM teams WHERE club_id = $1 ORDER BY name"),
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// `division` and `age_group` grade the side, e.g. `division3` / `senior`.
/// Both are optional — social sides carry neither.
pub async fn create_team(
    pool: &PgPool,
    club_id: Uuid,
    sport: &str,
    name: &str,
    division: Option<&str>,
    age_group: Option<&str>,
) -> Result<TeamRow, sqlx::Error> {
    sqlx::query_as::<_, TeamRow>(&format!(
        "INSERT INTO teams (club_id, sport, name, division, age_group)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING {TEAM_COLS}"
    ))
    .bind(club_id)
    .bind(sport)
    .bind(name)
    .bind(division)
    .bind(age_group)
    .fetch_one(pool)
    .await
}

pub async fn find_team(pool: &PgPool, team_id: Uuid) -> Result<Option<TeamRow>, sqlx::Error> {
    sqlx::query_as::<_, TeamRow>(&format!("SELECT {TEAM_COLS} FROM teams WHERE id = $1"))
        .bind(team_id)
        .fetch_optional(pool)
        .await
}

/// Add (or keep) a team member. Idempotent.
pub async fn add_team_member(
    pool: &PgPool,
    team_id: Uuid,
    user_id: Uuid,
    role: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO team_members (team_id, user_id, role) VALUES ($1, $2, $3)
         ON CONFLICT (team_id, user_id) DO NOTHING",
    )
    .bind(team_id)
    .bind(user_id)
    .bind(role)
    .execute(pool)
    .await?;
    Ok(())
}
