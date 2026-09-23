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
        INSERT INTO clubs (name, sport_types, visibility, owner_id, description, is_informal_group, qr_token)
        VALUES ($1, $2, $3, $4, $5, $6, encode(gen_random_bytes(12), 'hex'))
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

/// A club's own public page: what they write about themselves, plus the
/// record and the players worked out from what they have played.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct ClubPage {
    pub id: Uuid,
    pub name: String,
    pub slug: Option<String>,
    pub sport_types: Vec<String>,
    pub tagline: Option<String>,
    pub about: Option<String>,
    pub ground: Option<String>,
    pub founded_year: Option<i32>,
    pub contact_email: Option<String>,
    pub website: Option<String>,
    pub public_page: bool,
    /// The one player the club puts on its own front page.
    pub icon_player_id: Option<Uuid>,
}

const PAGE_COLS: &str = "id, name, slug, sport_types, tagline, about, ground, \
     founded_year, contact_email, website, public_page, icon_player_id";

/// By the address in the URL. Only a club that has switched its page on is
/// reachable — a page nobody published is not a page.
pub async fn page_by_slug(pool: &PgPool, slug: &str) -> Result<Option<ClubPage>, sqlx::Error> {
    sqlx::query_as::<_, ClubPage>(&format!(
        "SELECT {PAGE_COLS} FROM clubs WHERE LOWER(slug) = LOWER($1) AND public_page"
    ))
    .bind(slug.trim())
    .fetch_optional(pool)
    .await
}

pub async fn page_for(pool: &PgPool, club_id: Uuid) -> Result<Option<ClubPage>, sqlx::Error> {
    sqlx::query_as::<_, ClubPage>(&format!("SELECT {PAGE_COLS} FROM clubs WHERE id = $1"))
        .bind(club_id)
        .fetch_optional(pool)
        .await
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
pub struct UpdateClubPage {
    pub slug: Option<String>,
    pub public_page: Option<bool>,
    pub tagline: Option<String>,
    pub about: Option<String>,
    pub ground: Option<String>,
    pub founded_year: Option<i32>,
    pub contact_email: Option<String>,
    pub website: Option<String>,
    pub icon_player_id: Option<Uuid>,
}

/// COALESCE throughout: the editor sends only the fields it changed.
pub async fn update_page(
    pool: &PgPool,
    club_id: Uuid,
    req: &UpdateClubPage,
) -> Result<ClubPage, sqlx::Error> {
    sqlx::query_as::<_, ClubPage>(&format!(
        "UPDATE clubs SET
            slug = COALESCE($2, slug),
            public_page = COALESCE($3, public_page),
            tagline = COALESCE($4, tagline),
            about = COALESCE($5, about),
            ground = COALESCE($6, ground),
            founded_year = COALESCE($7, founded_year),
            contact_email = COALESCE($8, contact_email),
            website = COALESCE($9, website),
            -- A null means the editor did not touch the field, so COALESCE
            -- has no way to say none. The nil uuid is that way.
            icon_player_id = CASE
                WHEN $10::uuid IS NULL THEN icon_player_id
                WHEN $10 = '00000000-0000-0000-0000-000000000000'::uuid THEN NULL
                ELSE $10 END,
            updated_at = NOW()
         WHERE id = $1
         RETURNING {PAGE_COLS}"
    ))
    .bind(club_id)
    .bind(req.slug.as_deref().map(str::trim))
    .bind(req.public_page)
    .bind(req.tagline.as_deref())
    .bind(req.about.as_deref())
    .bind(req.ground.as_deref())
    .bind(req.founded_year)
    .bind(req.contact_email.as_deref())
    .bind(req.website.as_deref())
    .bind(req.icon_player_id)
    .fetch_one(pool)
    .await
}

/// A club plus what the asker is in it — the list is only ever read by
/// somebody who is in them, and the role is the first thing they look for.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct ClubMembership {
    #[serde(flatten)]
    #[sqlx(flatten)]
    pub club: Club,
    pub role: UserRole,
    /// Captains the side — by role, or as a secretary who captains too.
    pub is_captain: bool,
    /// Active members and teams, for the card on the clubs list.
    pub member_count: i64,
    pub team_count: i64,
    /// The public page's address, only once the club has switched it on.
    pub public_slug: Option<String>,
}

/// Whether the membership `m` is a captain: by role, or a secretary who
/// captains the side too. Every query that asks "who is captain" uses this.
const IS_CAPTAIN: &str =
    "(m.role = 'team_captain' OR (m.is_captain AND m.role IN ('club_admin', 'super_admin')))";

/// One membership row as the clubs screen shows it, shared by the full list
/// and the paged one so the two cannot drift.
const MEMBERSHIP_SELECT: &str = r#"
        SELECT c.id, c.name, c.sport_types, c.visibility, c.owner_id, c.description,
               c.is_informal_group, c.created_at, c.updated_at, m.role,
               (m.role = 'team_captain' OR (m.is_captain AND m.role IN ('club_admin', 'super_admin'))) AS is_captain,
               (SELECT COUNT(*) FROM club_members cm
                 WHERE cm.club_id = c.id AND cm.status = 'active') AS member_count,
               (SELECT COUNT(*) FROM teams t WHERE t.club_id = c.id) AS team_count,
               CASE WHEN c.public_page THEN c.slug END AS public_slug
        FROM clubs c
        INNER JOIN club_members m ON m.club_id = c.id
        WHERE m.user_id = $1 AND m.status = 'active'
"#;

pub async fn list_clubs_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<ClubMembership>, sqlx::Error> {
    sqlx::query_as::<_, ClubMembership>(&format!("{MEMBERSHIP_SELECT} ORDER BY c.name"))
        .bind(user_id)
        .fetch_all(pool)
        .await
}

/// Which of your roles to show. Grouped the way people say it: a super admin
/// runs the club like a secretary does.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RoleFilter {
    Secretary,
    Captain,
    ViceCaptain,
    Member,
}

impl RoleFilter {
    /// A condition on the membership `m`. Fixed strings, so nothing to bind.
    fn condition(self) -> String {
        match self {
            Self::Secretary => "m.role IN ('club_admin', 'super_admin')".into(),
            // A secretary who captains the side is a captain too.
            Self::Captain => IS_CAPTAIN.into(),
            Self::ViceCaptain => "m.role = 'team_vice_captain'".into(),
            Self::Member => "m.role IN ('member', 'guest')".into(),
        }
    }
}

/// An enum, so no column name ever comes from the caller.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClubSort {
    #[default]
    Name,
    /// Most recently joined first.
    Recent,
    /// Biggest first.
    Members,
}

#[derive(Debug, Clone, Default)]
pub struct ClubFilter {
    /// Matched against the name and description.
    pub search: Option<String>,
    pub role: Option<RoleFilter>,
    /// A sport_types value, e.g. "cricket".
    pub sport: Option<String>,
    /// Only clubs whose public page is (true) or is not (false) switched on.
    pub public_page: Option<bool>,
    pub sort: ClubSort,
    /// 1-based.
    pub page: i64,
    pub per_page: i64,
}

/// Your clubs, filtered, sorted and paged in the database — somebody in a
/// hundred clubs gets twenty rows and a count, not a hundred to sift.
pub async fn list_my_clubs(
    pool: &PgPool,
    user_id: Uuid,
    filter: &ClubFilter,
) -> Result<super::events::Page<ClubMembership>, sqlx::Error> {
    let mut where_sql = String::new();
    // $1 is the user; each filter present takes the next number.
    let mut last = 1;
    let mut param = || {
        last += 1;
        last
    };
    if filter.search.is_some() {
        let p = param();
        where_sql.push_str(&format!(
            " AND (c.name ILIKE '%' || ${p} || '%' OR COALESCE(c.description, '') ILIKE '%' || ${p} || '%')"
        ));
    }
    if let Some(role) = filter.role {
        where_sql.push_str(&format!(" AND {}", role.condition()));
    }
    if filter.sport.is_some() {
        where_sql.push_str(&format!(" AND ${} = ANY(c.sport_types)", param()));
    }
    if let Some(on) = filter.public_page {
        // A page switched on without an address is not reachable, so it
        // does not count as published.
        where_sql.push_str(if on {
            " AND c.public_page AND c.slug IS NOT NULL"
        } else {
            " AND NOT (c.public_page AND c.slug IS NOT NULL)"
        });
    }

    /// Both queries bind the same filters in the same order.
    macro_rules! bind_filters {
        ($q:expr) => {{
            let mut q = $q.bind(user_id);
            if let Some(v) = filter.search.as_deref() {
                q = q.bind(v.to_string());
            }
            if let Some(v) = filter.sport.as_deref() {
                q = q.bind(v.to_string());
            }
            q
        }};
    }

    let count_sql = format!(
        "SELECT COUNT(*) FROM clubs c INNER JOIN club_members m ON m.club_id = c.id \
         WHERE m.user_id = $1 AND m.status = 'active' {where_sql}"
    );
    let total: i64 = bind_filters!(sqlx::query_scalar::<_, i64>(&count_sql))
        .fetch_one(pool)
        .await?;

    let per_page = filter.per_page.clamp(1, 100);
    let page = filter.page.max(1);
    let order = match filter.sort {
        ClubSort::Name => "LOWER(c.name) ASC",
        ClubSort::Recent => "m.joined_at DESC",
        ClubSort::Members => "member_count DESC, LOWER(c.name) ASC",
    };
    // `c.id` breaks ties, or two rows can swap between pages and one is never seen.
    let sql = format!("{MEMBERSHIP_SELECT} {where_sql} ORDER BY {order}, c.id LIMIT {per_page} OFFSET {}", (page - 1) * per_page);
    let items = bind_filters!(sqlx::query_as::<_, ClubMembership>(&sql))
        .fetch_all(pool)
        .await?;

    Ok(super::events::Page {
        has_more: page * per_page < total,
        items,
        total,
        page,
        per_page,
    })
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
        FROM club_members WHERE club_id = $1 AND status = 'active'
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
        INSERT INTO teams (club_id, sport, name, qr_token)
        VALUES ($1, $2, $3, encode(gen_random_bytes(12), 'hex'))
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

/// Who is in a team, with their name — the caller wants a roster, not a list
/// of uuids to look up one at a time.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct TeamMemberDetail {
    pub user_id: Uuid,
    pub name: String,
    pub role: UserRole,
    pub avatar_url: Option<String>,
    pub position_role: Option<String>,
    pub joined_at: chrono::DateTime<chrono::Utc>,
}

pub async fn list_team_members(
    pool: &PgPool,
    team_id: Uuid,
) -> Result<Vec<TeamMemberDetail>, sqlx::Error> {
    sqlx::query_as::<_, TeamMemberDetail>(
        r#"
        SELECT tm.user_id, u.name, tm.role, u.avatar_url, u.position_role, tm.joined_at
        FROM team_members tm
        JOIN users u ON u.id = tm.user_id
        WHERE tm.team_id = $1
        ORDER BY
            -- Captain first: a roster is read to find out who runs it.
            CASE WHEN tm.role = 'team_captain' THEN 0 ELSE 1 END,
            u.name
        "#,
    )
    .bind(team_id)
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
    /// Absent for anyone who registered with a mobile number instead.
    pub email: Option<String>,
    pub phone: Option<String>,
    pub role: UserRole,
    /// Captains the side — by role, or as a secretary who captains too.
    pub is_captain: bool,
    pub status: MembershipStatus,
    pub joined_at: chrono::DateTime<chrono::Utc>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub avatar_url: Option<String>,
}

pub async fn list_member_details(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<ClubMemberDetail>, sqlx::Error> {
    sqlx::query_as::<_, ClubMemberDetail>(
        r#"
        SELECT m.user_id, u.name, u.email, u.phone, m.role,
               (m.role = 'team_captain' OR (m.is_captain AND m.role IN ('club_admin', 'super_admin'))) AS is_captain,
               m.status, m.joined_at, u.position_role, u.skill_level, u.avatar_url
        FROM club_members m
        JOIN users u ON u.id = m.user_id
        WHERE m.club_id = $1 AND m.status = 'active'
        ORDER BY
          CASE m.role
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

/// Find somebody to add to a club by whatever the secretary was given.
///
/// An email or a mobile number: since a member can register with either, being
/// asked for an address they never had would make them impossible to add.
pub async fn find_user_by_identifier(
    pool: &PgPool,
    identifier: &str,
) -> Result<Option<(Uuid, String, Option<String>)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String, Option<String>)>(
        "SELECT id, name, email FROM users
         WHERE LOWER(email) = LOWER($1) OR phone = $1
         LIMIT 1",
    )
    .bind(identifier.trim())
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
///
/// `captain` is kept only for a secretary — the one role that can also
/// captain the side — and any other role clears it. `None` leaves it as it
/// was, so a client that only knows about roles cannot drop it by accident.
pub async fn update_member_role(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
    role: UserRole,
    captain: Option<bool>,
) -> Result<Option<ClubMember>, sqlx::Error> {
    let secretary = matches!(role, UserRole::ClubAdmin | UserRole::SuperAdmin);
    sqlx::query_as::<_, ClubMember>(
        r#"
        UPDATE club_members SET role = $3, is_captain = $4 AND COALESCE($5, is_captain)
        WHERE club_id = $1 AND user_id = $2
        RETURNING club_id, user_id, role, status, joined_at
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .bind(role)
    .bind(secretary)
    .bind(captain)
    .fetch_optional(pool)
    .await
}

/// Who captains a side: the club's captains and, for a fixture played by one
/// of its teams, that team's captains. The team sheet starts with one of them
/// marked. Several is normal in a big club; the sheet takes the first picked.
pub async fn captain_ids(
    pool: &PgPool,
    club_id: Uuid,
    team_id: Option<Uuid>,
) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(&format!(
        r#"
        SELECT m.user_id FROM club_members m
        WHERE m.club_id = $1 AND m.status = 'active' AND {IS_CAPTAIN}
        UNION
        SELECT tm.user_id FROM team_members tm
        WHERE $2::uuid IS NOT NULL AND tm.team_id = $2 AND tm.role = 'team_captain'
        "#
    ))
    .bind(club_id)
    .bind(team_id)
    .fetch_all(pool)
    .await
}

/// Who may answer for the club — the roles that hold `ManageEvents` in
/// `domain::rbac`. Kept in step with that matrix by hand: the roles are stored
/// as an enum in the database and the matrix is Rust, so neither can read the
/// other.
pub async fn event_managers(pool: &PgPool, club_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT user_id FROM club_members
        WHERE club_id = $1 AND status = 'active'
          AND role IN ('super_admin', 'club_admin', 'team_captain')
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
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


/// A club's QR code, as the app renders it and another club scans it.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct QrIdentity {
    pub id: Uuid,
    pub name: String,
    pub qr_token: String,
    /// `club` or `team`.
    pub kind: String,
    pub club_id: Uuid,
    pub club_name: String,
    pub sport: Option<String>,
}

pub async fn club_qr(pool: &PgPool, club_id: Uuid) -> Result<Option<QrIdentity>, sqlx::Error> {
    sqlx::query_as::<_, QrIdentity>(
        r#"
        SELECT c.id, c.name, c.qr_token, 'club' AS kind, c.id AS club_id,
               c.name AS club_name, NULL::TEXT AS sport
        FROM clubs c WHERE c.id = $1
        "#,
    )
    .bind(club_id)
    .fetch_optional(pool)
    .await
}

pub async fn team_qr(pool: &PgPool, team_id: Uuid) -> Result<Option<QrIdentity>, sqlx::Error> {
    sqlx::query_as::<_, QrIdentity>(
        r#"
        SELECT t.id, t.name, t.qr_token, 'team' AS kind, t.club_id,
               c.name AS club_name, t.sport::TEXT AS sport
        FROM teams t JOIN clubs c ON c.id = t.club_id
        WHERE t.id = $1
        "#,
    )
    .bind(team_id)
    .fetch_optional(pool)
    .await
}

/// Resolve a scanned token to whoever it belongs to.
///
/// Deliberately not gated on membership: the whole point is that a side you
/// have never played can scan your code at the ground. The token is the secret,
/// and it only ever returns a name — never a roster, fixtures or contacts.
pub async fn resolve_qr(pool: &PgPool, token: &str) -> Result<Option<QrIdentity>, sqlx::Error> {
    if let Some(team) = sqlx::query_as::<_, QrIdentity>(
        r#"
        SELECT t.id, t.name, t.qr_token, 'team' AS kind, t.club_id,
               c.name AS club_name, t.sport::TEXT AS sport
        FROM teams t JOIN clubs c ON c.id = t.club_id
        WHERE t.qr_token = $1
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?
    {
        return Ok(Some(team));
    }

    sqlx::query_as::<_, QrIdentity>(
        r#"
        SELECT c.id, c.name, c.qr_token, 'club' AS kind, c.id AS club_id,
               c.name AS club_name, NULL::TEXT AS sport
        FROM clubs c WHERE c.qr_token = $1
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await
}

/// Mint a new code, so a club can retire one it has handed out too widely.
pub async fn rotate_club_qr(pool: &PgPool, club_id: Uuid) -> Result<String, sqlx::Error> {
    let row: (String,) = sqlx::query_as(
        "UPDATE clubs SET qr_token = encode(gen_random_bytes(12), 'hex')
         WHERE id = $1 RETURNING qr_token",
    )
    .bind(club_id)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

/// Clubs whose name matches, for picking an opposition without a QR code.
/// Find an opposition by name.
///
/// Three things this has to get right, none of which it used to:
///
/// * An invite-only club is not discoverable. That is what the setting means,
///   and the QR code is how those sides are found instead. Your own clubs stay
///   visible to you whatever their setting, or you could not find your own 2nd XI.
/// * Teams are searchable too. They already resolve by QR, so being unfindable
///   by name was an inconsistency a scorer would hit the moment they typed.
/// * A name that starts with what you typed sorts above one that merely
///   contains it — "Hemel Hempstead CC" before "Old Hemelians".
///
/// The `ILIKE '%x%'` is backed by the trigram indexes in
/// `20260908000002_searchable_clubs_and_teams.sql`; without them this is a
/// sequential scan of every club on every keystroke.
pub async fn search_opponents(
    pool: &PgPool,
    query: &str,
    viewer: Uuid,
    limit: i64,
) -> Result<Vec<QrIdentity>, sqlx::Error> {
    sqlx::query_as::<_, QrIdentity>(
        r#"
        WITH mine AS (
            SELECT club_id FROM club_members
            WHERE user_id = $2 AND status = 'active'
        )
        SELECT id, name, qr_token, kind, club_id, club_name, sport
        FROM (
            SELECT c.id, c.name, c.qr_token, 'club' AS kind, c.id AS club_id,
                   c.name AS club_name, NULL::TEXT AS sport,
                   (c.name ILIKE $1 || '%') AS starts_with
            FROM clubs c
            WHERE c.name ILIKE '%' || $1 || '%'
              AND (c.visibility = 'public' OR c.id IN (SELECT club_id FROM mine))

            UNION ALL

            SELECT t.id, t.name, t.qr_token, 'team' AS kind, t.club_id,
                   c.name AS club_name, t.sport::TEXT AS sport,
                   ((t.name ILIKE $1 || '%') OR (c.name ILIKE $1 || '%')) AS starts_with
            FROM teams t
            JOIN clubs c ON c.id = t.club_id
            WHERE (t.name ILIKE '%' || $1 || '%' OR c.name ILIKE '%' || $1 || '%')
              AND (c.visibility = 'public' OR c.id IN (SELECT club_id FROM mine))
        ) hits
        ORDER BY starts_with DESC, length(name), name
        LIMIT $3
        "#,
    )
    .bind(query)
    .bind(viewer)
    .bind(limit.clamp(1, 25))
    .fetch_all(pool)
    .await
}
