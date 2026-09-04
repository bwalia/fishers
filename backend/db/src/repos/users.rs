use chrono::Utc;
use fishers_domain::{
    profile_is_complete, PublicUser, ReliabilityCounts, UpdateProfileRequest, User,
};
use sqlx::types::Json;
use sqlx::PgPool;
use uuid::Uuid;

/// Every user query returns the same shape, including the profile JSONB columns.
const USER_COLUMNS: &str = "id, name, email, phone, apple_id, avatar_url, sports_played, \
     position_role, skill_level, emergency_contact, primary_sport, sport_profiles, \
     location, profile_completed_at, password_hash, created_at, updated_at";

pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE lower(email) = lower($1)"
    ))
    .bind(email)
    .fetch_optional(pool)
    .await
}

pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn create_user(
    pool: &PgPool,
    name: &str,
    email: &str,
    password_hash: &str,
    phone: Option<&str>,
) -> Result<User, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "INSERT INTO users (name, email, password_hash, phone)
         VALUES ($1, $2, $3, $4)
         RETURNING {USER_COLUMNS}"
    ))
    .bind(name)
    .bind(email)
    .bind(password_hash)
    .bind(phone)
    .fetch_one(pool)
    .await
}

pub async fn update_profile(
    pool: &PgPool,
    user_id: Uuid,
    req: &UpdateProfileRequest,
) -> Result<User, sqlx::Error> {
    let current = find_by_id(pool, user_id)
        .await?
        .ok_or(sqlx::Error::RowNotFound)?;

    let name = req.name.clone().unwrap_or(current.name);
    let phone = req.phone.clone().or(current.phone);
    let avatar_url = req.avatar_url.clone().or(current.avatar_url);
    let sports_played = req.sports_played.clone().unwrap_or(current.sports_played);
    let position_role = req.position_role.clone().or(current.position_role);
    let skill_level = req.skill_level.clone().or(current.skill_level);
    let emergency_contact = req
        .emergency_contact
        .clone()
        .or(current.emergency_contact);
    let primary_sport = req.primary_sport.clone().or(current.primary_sport);
    let sport_profiles = req
        .sport_profiles
        .clone()
        .unwrap_or_else(|| current.sport_profiles.0.clone());
    let location = req
        .location
        .clone()
        .or_else(|| current.location.clone().map(|l| l.0));
    // Stamped once, the first time the player states a standard.
    let profile_completed_at = current.profile_completed_at.or_else(|| {
        profile_is_complete(&sport_profiles, primary_sport.as_deref()).then(Utc::now)
    });

    sqlx::query_as::<_, User>(&format!(
        "UPDATE users SET
             name = $2,
             phone = $3,
             avatar_url = $4,
             sports_played = $5,
             position_role = $6,
             skill_level = $7,
             emergency_contact = $8,
             primary_sport = $9,
             sport_profiles = $10,
             location = $11,
             profile_completed_at = $12,
             updated_at = $13
         WHERE id = $1
         RETURNING {USER_COLUMNS}"
    ))
    .bind(user_id)
    .bind(name)
    .bind(phone)
    .bind(avatar_url)
    .bind(sports_played)
    .bind(position_role)
    .bind(skill_level)
    .bind(emergency_contact)
    .bind(primary_sport)
    .bind(Json(sport_profiles))
    .bind(location.map(Json))
    .bind(profile_completed_at)
    .bind(Utc::now())
    .fetch_one(pool)
    .await
}

/// Attendance and payment counters for one player. Pair with
/// `fishers_domain::reliability::score` to get the number the app shows.
pub async fn reliability_counts(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<ReliabilityCounts, sqlx::Error> {
    let counts = sqlx::query_as::<_, ReliabilityCounts>(
        r#"
        SELECT invites_received, responded, said_going, turned_up,
               late_cancellations, fees_due, fees_paid
        FROM player_reliability_counts WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?;
    Ok(counts.unwrap_or_default())
}

/// Same counters for a whole squad in one round trip, so a captain's selection
/// board can score every candidate at once.
pub async fn reliability_counts_for(
    pool: &PgPool,
    user_ids: &[Uuid],
) -> Result<Vec<(Uuid, ReliabilityCounts)>, sqlx::Error> {
    let rows = sqlx::query_as::<_, (Uuid, i64, i64, i64, i64, i64, i64, i64)>(
        r#"
        SELECT user_id, invites_received, responded, said_going, turned_up,
               late_cancellations, fees_due, fees_paid
        FROM player_reliability_counts WHERE user_id = ANY($1)
        "#,
    )
    .bind(user_ids)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(user_id, invites, responded, going, up, late, due, paid)| {
            (
                user_id,
                ReliabilityCounts {
                    invites_received: invites,
                    responded,
                    said_going: going,
                    turned_up: up,
                    late_cancellations: late,
                    fees_due: due,
                    fees_paid: paid,
                },
            )
        })
        .collect())
}

/// Record whether a player actually turned up.
pub async fn record_attendance(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    attended: bool,
) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE event_invites SET attended = $3 WHERE event_id = $1 AND user_id = $2")
        .bind(event_id)
        .bind(user_id)
        .bind(attended)
        .execute(pool)
        .await?;
    Ok(())
}

/// Called when someone who said "going" pulls out; `cancelled_at` is what makes
/// a drop-out count as late.
pub async fn record_cancellation(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE event_invites
        SET status = 'not_going', cancelled_at = NOW(), responded_at = NOW()
        WHERE event_id = $1 AND user_id = $2
        "#,
    )
    .bind(event_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn store_refresh_token(
    pool: &PgPool,
    user_id: Uuid,
    token_hash: &str,
    expires_at: chrono::DateTime<Utc>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
        VALUES ($1, $2, $3)
        "#,
    )
    .bind(user_id)
    .bind(token_hash)
    .bind(expires_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn find_valid_refresh_token(
    pool: &PgPool,
    token_hash: &str,
) -> Result<Option<(Uuid, chrono::DateTime<Utc>)>, sqlx::Error> {
    let row = sqlx::query_as::<_, (Uuid, chrono::DateTime<Utc>)>(
        r#"
        SELECT user_id, expires_at FROM refresh_tokens
        WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > NOW()
        "#,
    )
    .bind(token_hash)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn revoke_refresh_token(pool: &PgPool, token_hash: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE refresh_tokens SET revoked_at = NOW()
        WHERE token_hash = $1 AND revoked_at IS NULL
        "#,
    )
    .bind(token_hash)
    .execute(pool)
    .await?;
    Ok(())
}

pub fn to_public(user: User) -> PublicUser {
    user.into()
}

/// Names for a set of ids, for rendering squad announcements.
pub async fn names_for(
    pool: &PgPool,
    user_ids: &[Uuid],
) -> Result<Vec<(Uuid, String)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String)>("SELECT id, name FROM users WHERE id = ANY($1)")
        .bind(user_ids)
        .fetch_all(pool)
        .await
}
