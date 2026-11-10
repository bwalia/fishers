use fishers_domain::{
    AttendeeSummary, CreateInviteRequest, EventInvite, Invite, InvitePreview, InviteTarget,
    RsvpStatus,
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
                   invited_by, token, status, created_at, accepted_at, open, uses
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
                  invited_by, token, status, created_at, accepted_at, open, uses
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

/// The live open link for a club or team, if it has one.
pub async fn current_open_link(
    pool: &PgPool,
    target_type: InviteTarget,
    target_id: Uuid,
) -> Result<Option<Invite>, sqlx::Error> {
    sqlx::query_as::<_, Invite>(
        r#"
        SELECT id, target_type, target_id, invited_user_id, invited_email,
               invited_by, token, status, created_at, accepted_at, open, uses
        FROM invites
        WHERE target_type = $1 AND target_id = $2 AND open AND status = 'pending'
        "#,
    )
    .bind(target_type)
    .bind(target_id)
    .fetch_optional(pool)
    .await
}

/// The open link, made if there is none. Asking twice hands back the same
/// link, so a secretary who opens the page again shares what they shared
/// before rather than silently breaking it.
///
/// `fresh` turns the current one off first and makes a new one: for a link
/// that has got out to people it should not have.
pub async fn open_link(
    pool: &PgPool,
    target_type: InviteTarget,
    target_id: Uuid,
    by: Uuid,
    fresh: bool,
) -> Result<Invite, sqlx::Error> {
    let mut tx = pool.begin().await?;
    if fresh {
        revoke_open_link_in(&mut tx, target_type, target_id).await?;
    }
    // ON CONFLICT against the one-live-link index: two secretaries pressing
    // the button at once both get the one link.
    sqlx::query(
        r#"
        INSERT INTO invites (target_type, target_id, invited_by, token, open)
        VALUES ($1, $2, $3, $4, TRUE)
        ON CONFLICT (target_type, target_id) WHERE open AND status = 'pending' DO NOTHING
        "#,
    )
    .bind(target_type)
    .bind(target_id)
    .bind(by)
    .bind(invite_token())
    .execute(&mut *tx)
    .await?;
    let link = sqlx::query_as::<_, Invite>(
        r#"
        SELECT id, target_type, target_id, invited_user_id, invited_email,
               invited_by, token, status, created_at, accepted_at, open, uses
        FROM invites
        WHERE target_type = $1 AND target_id = $2 AND open AND status = 'pending'
        "#,
    )
    .bind(target_type)
    .bind(target_id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(link)
}

/// Turn the open link off. Anyone who already joined stays in; the link just
/// stops letting new people through. True when there was one to turn off.
pub async fn revoke_open_link(
    pool: &PgPool,
    target_type: InviteTarget,
    target_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let revoked = revoke_open_link_in(&mut tx, target_type, target_id).await?;
    tx.commit().await?;
    Ok(revoked)
}

async fn revoke_open_link_in(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    target_type: InviteTarget,
    target_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let done = sqlx::query(
        r#"
        UPDATE invites SET status = 'revoked'
        WHERE target_type = $1 AND target_id = $2 AND open AND status = 'pending'
        "#,
    )
    .bind(target_type)
    .bind(target_id)
    .execute(&mut **tx)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// What a link is to, for the page somebody lands on before signing in.
pub async fn preview(pool: &PgPool, token: &str) -> Result<Option<InvitePreview>, sqlx::Error> {
    sqlx::query_as::<_, InvitePreview>(
        r#"
        SELECT i.target_type, i.target_id,
               c.id AS club_id, c.name AS club_name,
               t.name AS team_name, e.title AS event_title,
               u.name AS invited_by_name,
               i.open,
               (i.status = 'pending' AND c.id IS NOT NULL) AS usable
        FROM invites i
        LEFT JOIN teams t ON i.target_type = 'team' AND t.id = i.target_id
        LEFT JOIN events e ON i.target_type = 'event' AND e.id = i.target_id
        LEFT JOIN clubs c ON c.id = CASE i.target_type
                                        WHEN 'club' THEN i.target_id
                                        WHEN 'team' THEN t.club_id
                                        WHEN 'event' THEN e.club_id
                                    END
        LEFT JOIN users u ON u.id = i.invited_by
        WHERE i.token = $1
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await
}

pub async fn list_my_invites(pool: &PgPool, user_id: Uuid) -> Result<Vec<Invite>, sqlx::Error> {
    sqlx::query_as::<_, Invite>(
        r#"
        SELECT i.id, i.target_type, i.target_id, i.invited_user_id, i.invited_email,
               i.invited_by, i.token, i.status, i.created_at, i.accepted_at, i.open, i.uses,
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
    type Row = (
        Uuid,
        String,
        RsvpStatus,
        Option<fishers_domain::AvailabilityStatus>,
        bool,
        Option<Uuid>,
        Option<String>,
        Option<chrono::DateTime<chrono::Utc>>,
    );
    let rows = sqlx::query_as::<_, Row>(
        r#"
        SELECT
            u.id,
            u.name,
            ei.status,
            a.status AS availability,
            EXISTS(
              SELECT 1 FROM payments p
              WHERE p.user_id = u.id AND p.event_id = ei.event_id AND p.status = 'succeeded'
            ) AS paid,
            side.club_id,
            c.name AS club_name,
            last_out.start_at AS last_played_at
        FROM event_invites ei
        JOIN users u ON u.id = ei.user_id
        JOIN events e ON e.id = ei.event_id
        LEFT JOIN availability a ON a.user_id = u.id AND a.date = (e.start_at AT TIME ZONE 'UTC')::date
        -- Which of the two sides they belong to. Somebody in both clubs plays
        -- for the one staging the fixture, which is what the ground would say.
        LEFT JOIN LATERAL (
            SELECT m.club_id
              FROM club_members m
             WHERE m.user_id = u.id
               AND m.status = 'active'
               AND m.club_id IN (e.club_id, e.opponent_club_id)
             ORDER BY (m.club_id = e.club_id) DESC
             LIMIT 1
        ) side ON TRUE
        LEFT JOIN clubs c ON c.id = side.club_id
        -- When they last turned out for that side. Said "going" and the
        -- fixture happened: the app's own record of somebody being there.
        LEFT JOIN LATERAL (
            SELECT pe.start_at
              FROM event_invites pi
              JOIN events pe ON pe.id = pi.event_id
             WHERE pi.user_id = u.id
               AND pi.status = 'going'
               AND pe.club_id = side.club_id
               AND pe.id <> e.id
               AND pe.start_at < e.start_at
               AND pe.status <> 'cancelled'
             ORDER BY pe.start_at DESC
             LIMIT 1
        ) last_out ON TRUE
        WHERE ei.event_id = $1
        ORDER BY (side.club_id = e.club_id) DESC, c.name, u.name
        "#,
    )
    .bind(event_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(
            |(user_id, name, status, availability, paid, club_id, club_name, last_played_at)| {
                AttendeeSummary {
                    user_id,
                    name,
                    status,
                    availability,
                    paid,
                    club_id,
                    club_name,
                    last_played_at,
                }
            },
        )
        .collect())
}

/// One transaction: the invite is spent only if the membership it promised is
/// actually written. As separate statements, a failed insert left an invite
/// marked accepted with nobody added, and no way to use it again.
///
/// An invite addressed to a person can only be accepted by that person. A link
/// invite (to an email, or to nobody in particular) can be accepted by whoever
/// holds the link — that is what the link is for.
///
/// `None` when there is no usable invite with that token.
pub async fn accept_invite(
    pool: &PgPool,
    token: &str,
    user_id: Uuid,
) -> Result<Option<Accepted>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let invite = sqlx::query_as::<_, Invite>(
        r#"
        UPDATE invites SET status = 'accepted', accepted_at = NOW(), invited_user_id = $2
        WHERE token = $1 AND status = 'pending' AND NOT open
          AND (invited_user_id IS NULL OR invited_user_id = $2)
        RETURNING id, target_type, target_id, invited_user_id, invited_email,
                  invited_by, token, status, created_at, accepted_at, open, uses
        "#,
    )
    .bind(token)
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;

    // Not a one-use invite: perhaps the club's open link, which stays
    // pending for the next person. Locked so the count below is exact.
    let invite = match invite {
        Some(inv) => Some(inv),
        None => {
            sqlx::query_as::<_, Invite>(
                r#"
                SELECT id, target_type, target_id, invited_user_id, invited_email,
                       invited_by, token, status, created_at, accepted_at, open, uses
                FROM invites
                WHERE token = $1 AND status = 'pending' AND open
                FOR UPDATE
                "#,
            )
            .bind(token)
            .fetch_optional(&mut *tx)
            .await?
        }
    };

    let Some(mut inv) = invite else {
        return Ok(None);
    };

    // Following the open link again — a reload, a second tap in the WhatsApp
    // group — when already in is not somebody new joining: it counts nobody
    // and tells the secretary nothing.
    let mut joined = true;
    if inv.open {
        let already: bool = sqlx::query_scalar(
            r#"
            SELECT CASE $1::invite_target
                WHEN 'club' THEN EXISTS (SELECT 1 FROM club_members
                                         WHERE club_id = $2 AND user_id = $3 AND status = 'active')
                WHEN 'team' THEN EXISTS (SELECT 1 FROM team_members
                                         WHERE team_id = $2 AND user_id = $3)
                ELSE FALSE
            END
            "#,
        )
        .bind(inv.target_type)
        .bind(inv.target_id)
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await?;
        joined = !already;

        // The open link is for anybody — except somebody this club removed.
        // The link is still in their WhatsApp; following it must not undo the
        // secretary's decision. A secretary's own invitation still can.
        if !already && removed_from_club(&mut tx, &inv, user_id).await? {
            return Ok(Some(Accepted::RemovedByClub));
        }
        if joined {
            inv.uses = sqlx::query_scalar("UPDATE invites SET uses = uses + 1 WHERE id = $1 RETURNING uses")
                .bind(inv.id)
                .fetch_one(&mut *tx)
                .await?;
        }
    }

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
            return Ok(Some(Accepted::Joined(inv, joined)));
        }
    }
    tx.commit().await?;
    Ok(Some(Accepted::Joined(inv, joined)))
}

/// What following an invite came to.
#[derive(Debug)]
pub enum Accepted {
    /// In. The bool is false when this changed nothing: somebody already in
    /// the club following its open link again.
    Joined(Invite, bool),
    /// The club removed them, and this was its open link.
    RemovedByClub,
}

/// Whether the club an invite leads into removed this person.
async fn removed_from_club(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    inv: &Invite,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM club_members m
            WHERE m.user_id = $3 AND m.removed_at IS NOT NULL AND m.status <> 'active'
              AND m.club_id = CASE $1::invite_target
                                  WHEN 'club' THEN $2
                                  WHEN 'team' THEN (SELECT club_id FROM teams WHERE id = $2)
                              END
        )
        "#,
    )
    .bind(inv.target_type)
    .bind(inv.target_id)
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await
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
        ON CONFLICT (club_id, user_id) DO UPDATE
            SET status = 'active', removed_at = NULL, removed_by = NULL
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
