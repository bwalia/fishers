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
     location, profile_completed_at, email_verified_at, phone_verified_at, role_intent, \
     profile_share_token, password_hash, created_at, updated_at";

/// Find somebody by an email or a mobile number, whichever they signed up with.
///
/// Case and stray spaces are the two things people reliably get wrong typing an
/// address on a phone, so neither is allowed to stop them signing in.
pub async fn find_by_identifier(
    pool: &PgPool,
    identifier: &str,
) -> Result<Option<User>, sqlx::Error> {
    let trimmed = identifier.trim();
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users
         WHERE (LOWER(email) = LOWER($1) OR phone = $1) AND deleted_at IS NULL
         LIMIT 1"
    ))
    .bind(trimmed)
    .fetch_optional(pool)
    .await
}

pub async fn find_by_phone(pool: &PgPool, phone: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE phone = $1 AND deleted_at IS NULL"
    ))
    .bind(phone.trim())
    .fetch_optional(pool)
    .await
}

pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE lower(email) = lower($1) AND deleted_at IS NULL"
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
    email: Option<&str>,
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
    let role_intent = req.role_intent.clone().or(current.role_intent);
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
             updated_at = $13,
             role_intent = $14,
             -- A verified number stays verified only while it is the same
             -- number. SET's right-hand side reads the old row, so `phone`
             -- here is the number before this update.
             phone_verified_at = CASE WHEN phone IS DISTINCT FROM $3
                                      THEN NULL ELSE phone_verified_at END
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
    .bind(role_intent)
    .fetch_one(pool)
    .await
}

/// The account a Google sign-in has been used on before.
pub async fn find_by_google_sub(pool: &PgPool, sub: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE google_sub = $1 AND deleted_at IS NULL"
    ))
    .bind(sub)
    .fetch_optional(pool)
    .await
}

/// A Google account signing in to an existing account with the same address.
///
/// Google has confirmed the address, so it counts as verified from now on.
/// If it was not verified before, somebody else may have registered it with a
/// password of their own, waiting for the real owner to arrive — so that
/// password goes, and so does every session signed in with it. The owner
/// keeps signing in with Google.
pub async fn link_google(pool: &PgPool, user_id: Uuid, sub: &str) -> Result<User, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let unverified: bool = sqlx::query_scalar(
        "SELECT email_verified_at IS NULL FROM users WHERE id = $1 FOR UPDATE",
    )
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await?;
    if unverified {
        sqlx::query(
            "UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL",
        )
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    }
    let user = sqlx::query_as::<_, User>(&format!(
        "UPDATE users SET google_sub = $2,
                password_hash = CASE WHEN email_verified_at IS NULL THEN NULL ELSE password_hash END,
                email_verified_at = COALESCE(email_verified_at, now()),
                updated_at = now()
         WHERE id = $1
         RETURNING {USER_COLUMNS}"
    ))
    .bind(user_id)
    .bind(sub)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(user)
}

/// A new account from a Google sign-in: no password, address already confirmed.
pub async fn create_google_user(
    pool: &PgPool,
    name: &str,
    email: &str,
    sub: &str,
    avatar_url: Option<&str>,
) -> Result<User, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "INSERT INTO users (name, email, google_sub, avatar_url, email_verified_at)
         VALUES ($1, $2, $3, $4, now())
         RETURNING {USER_COLUMNS}"
    ))
    .bind(name)
    .bind(email)
    .bind(sub)
    .bind(avatar_url)
    .fetch_one(pool)
    .await
}

/// The account a Sign in with Apple has been used on before.
pub async fn find_by_apple_id(pool: &PgPool, apple_id: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE apple_id = $1 AND deleted_at IS NULL"
    ))
    .bind(apple_id)
    .fetch_optional(pool)
    .await
}

/// Link Sign in with Apple to an existing account with the same address.
pub async fn link_apple(pool: &PgPool, user_id: Uuid, apple_id: &str) -> Result<User, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let unverified: bool = sqlx::query_scalar(
        "SELECT email_verified_at IS NULL FROM users WHERE id = $1 FOR UPDATE",
    )
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await?;
    if unverified {
        sqlx::query(
            "UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL",
        )
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    }
    let user = sqlx::query_as::<_, User>(&format!(
        "UPDATE users SET apple_id = $2,
                password_hash = CASE WHEN email_verified_at IS NULL THEN NULL ELSE password_hash END,
                email_verified_at = COALESCE(email_verified_at, now()),
                updated_at = now()
         WHERE id = $1
         RETURNING {USER_COLUMNS}"
    ))
    .bind(user_id)
    .bind(apple_id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(user)
}

/// A new account from Sign in with Apple. Email may be absent when the user
/// hid it and Apple already handed it over on a previous device.
pub async fn create_apple_user(
    pool: &PgPool,
    name: &str,
    email: Option<&str>,
    apple_id: &str,
) -> Result<User, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "INSERT INTO users (name, email, apple_id, email_verified_at)
         VALUES ($1, $2, $3, CASE WHEN $2 IS NULL THEN NULL ELSE now() END)
         RETURNING {USER_COLUMNS}"
    ))
    .bind(name)
    .bind(email)
    .bind(apple_id)
    .fetch_one(pool)
    .await
}

/// Marks the address a code was sent to as verified — but only if it is still
/// the user's address. Returns false when it has changed since, so a code sent
/// to an old number cannot verify a new one.
pub async fn mark_verified(
    pool: &PgPool,
    user_id: Uuid,
    channel: &str,
    target: &str,
) -> Result<bool, sqlx::Error> {
    let sql = match channel {
        "email" => "UPDATE users SET email_verified_at = now(), updated_at = now()
                    WHERE id = $1 AND lower(email) = lower($2)",
        "phone" => "UPDATE users SET phone_verified_at = now(), updated_at = now()
                    WHERE id = $1 AND phone = $2",
        _ => return Ok(false),
    };
    let done = sqlx::query(sql).bind(user_id).bind(target).execute(pool).await?;
    Ok(done.rows_affected() == 1)
}

/// The player's share token, minted on first use. `COALESCE` keeps an existing
/// token, so asking twice never breaks a link already sent.
pub async fn share_token(pool: &PgPool, user_id: Uuid, fresh: &str) -> Result<String, sqlx::Error> {
    sqlx::query_scalar(
        "UPDATE users SET profile_share_token = COALESCE(profile_share_token, $2)
         WHERE id = $1 RETURNING profile_share_token",
    )
    .bind(user_id)
    .bind(fresh)
    .fetch_one(pool)
    .await
}

pub async fn find_by_share_token(pool: &PgPool, token: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(&format!(
        "SELECT {USER_COLUMNS} FROM users WHERE profile_share_token = $1 AND deleted_at IS NULL"
    ))
    .bind(token)
    .fetch_optional(pool)
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

/// Delete the person; keep the fixtures they played in.
///
/// App Store Review 5.1.1(v) requires an in-app account deletion. A hard DELETE
/// is not open to us — see `20260917000001_delete_my_account.sql` — so this
/// clears every column that says who somebody is, closes every route back into
/// the account, and stamps the row. Scorecards, club history and the averages
/// built on them keep their shape; the player on them becomes nobody.
///
/// Returns false when the account was already gone, so asking twice is quiet.
pub async fn delete_account(pool: &PgPool, user_id: Uuid) -> Result<bool, sqlx::Error> {
    let mut tx = pool.begin().await?;

    // Sessions first. An access token already issued outlives this by its own
    // fifteen minutes and nothing can call it back; a refresh token would have
    // carried on minting them for a month.
    sqlx::query(
        "UPDATE refresh_tokens SET revoked_at = now()
         WHERE user_id = $1 AND revoked_at IS NULL",
    )
    .bind(user_id)
    .execute(&mut *tx)
    .await?;

    // ponytail: the avatar object itself stays in the bucket — Storage can put
    // but not delete, and the key is unguessable, so clearing the reference is
    // most of it. Add Storage::delete when somebody can test it against MinIO.

    // Nothing should still be able to buzz a phone that has left.
    sqlx::query("DELETE FROM device_tokens WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    let done = sqlx::query(
        "UPDATE users SET
            name                 = 'Deleted member',
            email                = NULL,
            phone                = NULL,
            apple_id             = NULL,
            google_sub           = NULL,
            avatar_url           = NULL,
            password_hash        = NULL,
            emergency_contact    = NULL,
            position_role        = NULL,
            skill_level          = NULL,
            primary_sport        = NULL,
            sports_played        = '{}',
            sport_profiles       = '[]',
            location             = NULL,
            profile_share_token  = NULL,
            profile_completed_at = NULL,
            email_verified_at    = NULL,
            phone_verified_at    = NULL,
            role_intent          = NULL,
            deleted_at           = now(),
            updated_at           = now()
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(done.rows_affected() == 1)
}
