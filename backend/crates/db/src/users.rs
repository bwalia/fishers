use crate::rows::{ProfileUpdate, ReliabilityCountsRow, UserAuthRow, UserRow};
use sqlx::PgPool;
use uuid::Uuid;

// `position` is quoted throughout: it is a keyword in Postgres' grammar.
const USER_COLS: &str = "id, name, email, phone, avatar_url, emergency_contact, \
     primary_sport, sports, \"position\", skill_level, sport_profiles, location, \
     profile_completed_at, created_at";

pub async fn create(
    pool: &PgPool,
    name: &str,
    email: &str,
    password_hash: &str,
) -> Result<UserRow, sqlx::Error> {
    sqlx::query_as::<_, UserRow>(&format!(
        "INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING {USER_COLS}"
    ))
    .bind(name)
    .bind(email)
    .bind(password_hash)
    .fetch_one(pool)
    .await
}

pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<Option<UserRow>, sqlx::Error> {
    sqlx::query_as::<_, UserRow>(&format!("SELECT {USER_COLS} FROM users WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<Option<UserRow>, sqlx::Error> {
    sqlx::query_as::<_, UserRow>(&format!("SELECT {USER_COLS} FROM users WHERE email = $1"))
        .bind(email)
        .fetch_optional(pool)
        .await
}

pub async fn find_auth_by_email(
    pool: &PgPool,
    email: &str,
) -> Result<Option<UserAuthRow>, sqlx::Error> {
    sqlx::query_as::<_, UserAuthRow>("SELECT id, password_hash FROM users WHERE email = $1")
        .bind(email)
        .fetch_optional(pool)
        .await
}

/// Overwrite the player's profile with what the app holds. Marks the profile
/// as set up the first time a standard is supplied, which is what the app uses
/// to decide whether to run first-run setup.
pub async fn update_profile(
    pool: &PgPool,
    user_id: Uuid,
    update: &ProfileUpdate,
) -> Result<Option<UserRow>, sqlx::Error> {
    sqlx::query_as::<_, UserRow>(&format!(
        "UPDATE users SET
             name = $2,
             phone = $3,
             avatar_url = $4,
             emergency_contact = $5,
             primary_sport = $6,
             sports = $7,
             \"position\" = $8,
             skill_level = $9,
             sport_profiles = $10,
             location = $11,
             profile_completed_at = CASE
                 WHEN profile_completed_at IS NOT NULL THEN profile_completed_at
                 WHEN $9 IS NULL THEN NULL
                 ELSE now()
             END
         WHERE id = $1
         RETURNING {USER_COLS}"
    ))
    .bind(user_id)
    .bind(&update.name)
    .bind(&update.phone)
    .bind(&update.avatar_url)
    .bind(&update.emergency_contact)
    .bind(&update.primary_sport)
    .bind(update.sports.as_slice())
    .bind(&update.position)
    .bind(&update.skill_level)
    .bind(update.sport_profiles.clone())
    .bind(update.location.clone())
    .fetch_optional(pool)
    .await
}

/// Attendance and payment counters for one player. Feed the result to
/// `fishers_domain::reliability::score` to get the number the app shows.
pub async fn reliability_counts(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Option<ReliabilityCountsRow>, sqlx::Error> {
    sqlx::query_as::<_, ReliabilityCountsRow>(
        "SELECT user_id, invites_received, responded, said_going, turned_up,
                late_cancellations, fees_due, fees_paid
         FROM player_reliability_counts
         WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Same counters for a whole squad in one round trip — the squad picker scores
/// every candidate at once.
pub async fn reliability_counts_for(
    pool: &PgPool,
    user_ids: &[Uuid],
) -> Result<Vec<ReliabilityCountsRow>, sqlx::Error> {
    sqlx::query_as::<_, ReliabilityCountsRow>(
        "SELECT user_id, invites_received, responded, said_going, turned_up,
                late_cancellations, fees_due, fees_paid
         FROM player_reliability_counts
         WHERE user_id = ANY($1)",
    )
    .bind(user_ids)
    .fetch_all(pool)
    .await
}

/// Record whether a player actually turned up, and when they pulled out — the
/// two facts RSVP status alone can't supply to the reliability score.
pub async fn record_attendance(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    attended: bool,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE event_invites SET attended = $3 WHERE event_id = $1 AND user_id = $2",
    )
    .bind(event_id)
    .bind(user_id)
    .bind(attended)
    .execute(pool)
    .await
    .map(|_| ())
}

/// Called when someone who said "going" drops out; `cancelled_at` is what makes
/// a drop-out count as late.
pub async fn record_cancellation(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE event_invites
         SET status = 'not_going', cancelled_at = now(), responded_at = now()
         WHERE event_id = $1 AND user_id = $2",
    )
    .bind(event_id)
    .bind(user_id)
    .execute(pool)
    .await
    .map(|_| ())
}
