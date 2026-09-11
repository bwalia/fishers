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

/// A second "Invite" for the same person to the same club or team hands back
/// the one already waiting, rather than stacking up duplicates for them to
/// wade through. The bool says whether this call made it — the caller only
/// notifies them once.
pub async fn create_invite(
    pool: &PgPool,
    invited_by: Uuid,
    req: &CreateInviteRequest,
) -> Result<(Invite, bool), sqlx::Error> {
    if let Some(user) = req.invited_user_id {
        let existing = sqlx::query_as::<_, Invite>(
            r#"
            SELECT id, target_type, target_id, invited_user_id, invited_email,
                   invited_by, token, status, created_at, accepted_at
            FROM invites
            WHERE target_type = $1 AND target_id = $2 AND invited_user_id = $3
              AND status = 'pending'
            ORDER BY created_at DESC LIMIT 1
            "#,
        )
        .bind(req.target_type)
        .bind(req.target_id)
        .bind(user)
        .fetch_optional(pool)
        .await?;
        if let Some(invite) = existing {
            return Ok((invite, false));
        }
    }
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
    .map(|invite| (invite, true))
}

pub async fn list_my_invites(pool: &PgPool, user_id: Uuid) -> Result<Vec<Invite>, sqlx::Error> {
    sqlx::query_as::<_, Invite>(
        r#"
        SELECT i.id, i.target_type, i.target_id, i.invited_user_id, i.invited_email,
               i.invited_by, i.token, i.status, i.created_at, i.accepted_at,
               CASE i.target_type
                   WHEN 'club' THEN (SELECT name FROM clubs WHERE id = i.target_id)
                   WHEN 'team' THEN (SELECT t.name || ' · ' || c.name
                                     FROM teams t JOIN clubs c ON c.id = t.club_id
                                     WHERE t.id = i.target_id)
                   WHEN 'event' THEN (SELECT title FROM events WHERE id = i.target_id)
               END AS target_name,
               (SELECT name FROM users WHERE id = i.invited_by) AS invited_by_name
        FROM invites i
        WHERE i.invited_user_id = $1 OR i.invited_email = (SELECT email FROM users WHERE id = $1)
        ORDER BY i.created_at DESC
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

/// One transaction: the invite is spent only if the membership it promised is
/// actually written. As separate statements, a failed insert left an invite
/// marked accepted with nobody added, and no way to use it again.
///
/// An invite addressed to a person can only be accepted by that person. A link
/// invite (to an email, or to nobody in particular) can be accepted by whoever
/// holds the link — that is what the link is for.
pub async fn accept_invite(
    pool: &PgPool,
    token: &str,
    user_id: Uuid,
) -> Result<Option<Invite>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let invite = sqlx::query_as::<_, Invite>(
        r#"
        UPDATE invites SET status = 'accepted', accepted_at = NOW(), invited_user_id = $2
        WHERE token = $1 AND status = 'pending'
          AND (invited_user_id IS NULL OR invited_user_id = $2)
        RETURNING id, target_type, target_id, invited_user_id, invited_email,
                  invited_by, token, status, created_at, accepted_at
        "#,
    )
    .bind(token)
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;

    let Some(inv) = invite else {
        return Ok(None);
    };

    match inv.target_type {
        InviteTarget::Club => {
            join_club(&mut tx, inv.target_id, user_id).await?;
        }
        InviteTarget::Team => {
            // A team is inside a club. Joining only the team left a player
            // on a side in a club they were not a member of — so they could
            // not see its fixtures, its chat, or the club itself.
            let club_id: Uuid = sqlx::query_scalar("SELECT club_id FROM teams WHERE id = $1")
                .bind(inv.target_id)
                .fetch_one(&mut *tx)
                .await?;
            join_club(&mut tx, club_id, user_id).await?;
            sqlx::query(
                r#"
                INSERT INTO team_members (team_id, user_id, role)
                VALUES ($1, $2, 'member')
                ON CONFLICT DO NOTHING
                "#,
            )
            .bind(inv.target_id)
            .bind(user_id)
            .execute(&mut *tx)
            .await?;
        }
        InviteTarget::Event => {
            tx.commit().await?;
            invite_to_event(pool, inv.target_id, user_id, inv.invited_by).await?;
            return Ok(Some(inv));
        }
    }
    tx.commit().await?;
    Ok(Some(inv))
}

/// Active member, keeping any role they already hold — accepting an invite
/// must never demote a captain back to member.
async fn join_club(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO club_members (club_id, user_id, role, status)
        VALUES ($1, $2, 'member', 'active')
        ON CONFLICT (club_id, user_id) DO UPDATE SET status = 'active'
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
