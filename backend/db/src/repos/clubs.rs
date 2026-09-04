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

/// The member's role in the club (`club_admin`, `team_captain`, `member`, ...),
/// or `None` when they are not an active member.
pub async fn club_role(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<Option<String>, sqlx::Error> {
    let row: Option<(String,)> = sqlx::query_as(
        r#"
        SELECT role::TEXT FROM club_members
        WHERE club_id = $1 AND user_id = $2 AND status = 'active'
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0))
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
