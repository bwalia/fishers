use fishers_domain::{
    AttendeeSummary, CreateInviteRequest, EventInvite, Invite, InviteTarget, RsvpStatus,
};
use rand::Rng;
use sqlx::PgPool;
use uuid::Uuid;

fn invite_token() -> String {
    let bytes: [u8; 16] = rand::thread_rng().gen();
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub async fn create_invite(
    pool: &PgPool,
    invited_by: Uuid,
    req: &CreateInviteRequest,
) -> Result<Invite, sqlx::Error> {
    let token = invite_token();
    sqlx::query_as::<_, Invite>(
        r#"
        INSERT INTO invites (target_type, target_id, invited_user_id, invited_email, invited_by, token)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, target_type, target_id, invited_user_id, invited_email,
                  invited_by, token, status, created_at, accepted_at
        "#,
    )
    .bind(req.target_type)
    .bind(req.target_id)
    .bind(req.invited_user_id)
    .bind(&req.invited_email)
    .bind(invited_by)
    .bind(token)
    .fetch_one(pool)
    .await
}

pub async fn list_my_invites(pool: &PgPool, user_id: Uuid) -> Result<Vec<Invite>, sqlx::Error> {
    sqlx::query_as::<_, Invite>(
        r#"
        SELECT id, target_type, target_id, invited_user_id, invited_email,
               invited_by, token, status, created_at, accepted_at
        FROM invites
        WHERE invited_user_id = $1 OR invited_email = (SELECT email FROM users WHERE id = $1)
        ORDER BY created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

pub async fn invite_to_event(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    invited_by: Uuid,
) -> Result<EventInvite, sqlx::Error> {
    sqlx::query_as::<_, EventInvite>(
        r#"
        INSERT INTO event_invites (event_id, user_id, invited_by, status)
        VALUES ($1, $2, $3, 'invited')
        ON CONFLICT (event_id, user_id) DO UPDATE SET invited_by = EXCLUDED.invited_by
        RETURNING id, event_id, user_id, invited_by, status, responded_at, created_at
        "#,
    )
    .bind(event_id)
    .bind(user_id)
    .bind(invited_by)
    .fetch_one(pool)
    .await
}

pub async fn rsvp(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    status: RsvpStatus,
) -> Result<EventInvite, sqlx::Error> {
    sqlx::query_as::<_, EventInvite>(
        r#"
        INSERT INTO event_invites (event_id, user_id, invited_by, status, responded_at)
        VALUES ($1, $2, $2, $3, NOW())
        ON CONFLICT (event_id, user_id) DO UPDATE SET
            status = EXCLUDED.status,
            responded_at = NOW()
        RETURNING id, event_id, user_id, invited_by, status, responded_at, created_at
        "#,
    )
    .bind(event_id)
    .bind(user_id)
    .bind(status)
    .fetch_one(pool)
    .await
}

pub async fn list_attendees(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Vec<AttendeeSummary>, sqlx::Error> {
    let rows = sqlx::query_as::<_, (Uuid, String, RsvpStatus, Option<fishers_domain::AvailabilityStatus>, bool)>(
        r#"
        SELECT
            u.id,
            u.name,
            ei.status,
            a.status AS availability,
            EXISTS(
              SELECT 1 FROM payments p
              WHERE p.user_id = u.id AND p.event_id = ei.event_id AND p.status = 'succeeded'
            ) AS paid
        FROM event_invites ei
        JOIN users u ON u.id = ei.user_id
        LEFT JOIN events e ON e.id = ei.event_id
        LEFT JOIN availability a ON a.user_id = u.id AND a.date = (e.start_at AT TIME ZONE 'UTC')::date
        WHERE ei.event_id = $1
        ORDER BY u.name
        "#,
    )
    .bind(event_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(user_id, name, status, availability, paid)| AttendeeSummary {
            user_id,
            name,
            status,
            availability,
            paid,
        })
        .collect())
}

pub async fn accept_invite(
    pool: &PgPool,
    token: &str,
    user_id: Uuid,
) -> Result<Option<Invite>, sqlx::Error> {
    let invite = sqlx::query_as::<_, Invite>(
        r#"
        UPDATE invites SET status = 'accepted', accepted_at = NOW(), invited_user_id = $2
        WHERE token = $1 AND status = 'pending'
        RETURNING id, target_type, target_id, invited_user_id, invited_email,
                  invited_by, token, status, created_at, accepted_at
        "#,
    )
    .bind(token)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    if let Some(ref inv) = invite {
        match inv.target_type {
            InviteTarget::Club => {
                sqlx::query(
                    r#"
                    INSERT INTO club_members (club_id, user_id, role, status)
                    VALUES ($1, $2, 'member', 'active')
                    ON CONFLICT DO NOTHING
                    "#,
                )
                .bind(inv.target_id)
                .bind(user_id)
                .execute(pool)
                .await?;
            }
            InviteTarget::Team => {
                sqlx::query(
                    r#"
                    INSERT INTO team_members (team_id, user_id, role)
                    VALUES ($1, $2, 'member')
                    ON CONFLICT DO NOTHING
                    "#,
                )
                .bind(inv.target_id)
                .bind(user_id)
                .execute(pool)
                .await?;
            }
            InviteTarget::Event => {
                invite_to_event(pool, inv.target_id, user_id, inv.invited_by).await?;
            }
        }
    }

    Ok(invite)
}
