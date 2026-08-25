use chrono::Utc;
use fishers_domain::{PublicUser, UpdateProfileRequest, User};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT id, name, email, phone, apple_id, avatar_url, sports_played,
               position_role, skill_level, emergency_contact, password_hash,
               created_at, updated_at
        FROM users WHERE lower(email) = lower($1)
        "#,
    )
    .bind(email)
    .fetch_optional(pool)
    .await
}

pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT id, name, email, phone, apple_id, avatar_url, sports_played,
               position_role, skill_level, emergency_contact, password_hash,
               created_at, updated_at
        FROM users WHERE id = $1
        "#,
    )
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
    sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (name, email, password_hash, phone)
        VALUES ($1, $2, $3, $4)
        RETURNING id, name, email, phone, apple_id, avatar_url, sports_played,
                  position_role, skill_level, emergency_contact, password_hash,
                  created_at, updated_at
        "#,
    )
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

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users SET
            name = $2,
            phone = $3,
            avatar_url = $4,
            sports_played = $5,
            position_role = $6,
            skill_level = $7,
            emergency_contact = $8,
            updated_at = $9
        WHERE id = $1
        RETURNING id, name, email, phone, apple_id, avatar_url, sports_played,
                  position_role, skill_level, emergency_contact, password_hash,
                  created_at, updated_at
        "#,
    )
    .bind(user_id)
    .bind(name)
    .bind(phone)
    .bind(avatar_url)
    .bind(sports_played)
    .bind(position_role)
    .bind(skill_level)
    .bind(emergency_contact)
    .bind(Utc::now())
    .fetch_one(pool)
    .await
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
