use chrono::{DateTime, Utc};
use fishers_domain::{
    ChatMessage, Conversation, ConversationSummary, CreateConversationRequest,
};
use sqlx::types::JsonValue;
use sqlx::PgPool;
use uuid::Uuid;

const CONVERSATION_COLS: &str =
    "id, club_id, team_id, event_id, kind, title, created_by, created_at, updated_at";

/// Creates the thread and enrols the creator as owner. A club thread with no
/// explicit member list gets the whole active roster.
pub async fn create_conversation(
    pool: &PgPool,
    creator: Uuid,
    req: &CreateConversationRequest,
) -> Result<Conversation, sqlx::Error> {
    let kind = req.kind.clone().unwrap_or_else(|| {
        if req.event_id.is_some() {
            "event".to_string()
        } else if req.team_id.is_some() {
            "team".to_string()
        } else {
            "club".to_string()
        }
    });

    let mut tx = pool.begin().await?;

    let conversation = sqlx::query_as::<_, Conversation>(&format!(
        "INSERT INTO conversations (club_id, team_id, event_id, kind, title, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING {CONVERSATION_COLS}"
    ))
    .bind(req.club_id)
    .bind(req.team_id)
    .bind(req.event_id)
    .bind(&kind)
    .bind(&req.title)
    .bind(creator)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(
        "INSERT INTO conversation_members (conversation_id, user_id, role)
         VALUES ($1, $2, 'owner')
         ON CONFLICT DO NOTHING",
    )
    .bind(conversation.id)
    .bind(creator)
    .execute(&mut *tx)
    .await?;

    if req.member_ids.is_empty() {
        if let Some(club_id) = req.club_id {
            sqlx::query(
                "INSERT INTO conversation_members (conversation_id, user_id)
                 SELECT $1, user_id FROM club_members
                 WHERE club_id = $2 AND status = 'active'
                 ON CONFLICT DO NOTHING",
            )
            .bind(conversation.id)
            .bind(club_id)
            .execute(&mut *tx)
            .await?;
        }
    } else {
        sqlx::query(
            "INSERT INTO conversation_members (conversation_id, user_id)
             SELECT $1, unnest($2::uuid[])
             ON CONFLICT DO NOTHING",
        )
        .bind(conversation.id)
        .bind(&req.member_ids)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;
    Ok(conversation)
}

pub async fn add_members(
    pool: &PgPool,
    conversation_id: Uuid,
    user_ids: &[Uuid],
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO conversation_members (conversation_id, user_id)
         SELECT $1, unnest($2::uuid[])
         ON CONFLICT DO NOTHING",
    )
    .bind(conversation_id)
    .bind(user_ids)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_conversation(
    pool: &PgPool,
    id: Uuid,
) -> Result<Option<Conversation>, sqlx::Error> {
    sqlx::query_as::<_, Conversation>(&format!(
        "SELECT {CONVERSATION_COLS} FROM conversations WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn is_member(
    pool: &PgPool,
    conversation_id: Uuid,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let found: Option<(i32,)> = sqlx::query_as(
        "SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
    )
    .bind(conversation_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;
    Ok(found.is_some())
}

/// Threads the user belongs to, newest activity first, with the unread count
/// and how many agent proposals are waiting on a decision.
pub async fn list_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<ConversationSummary>, sqlx::Error> {
    sqlx::query_as::<_, ConversationSummary>(
        r#"
        SELECT c.id, c.club_id, c.team_id, c.event_id, c.kind, c.title, c.updated_at,
               last.body AS last_message_body,
               last.created_at AS last_message_at,
               COALESCE((
                   SELECT COUNT(*) FROM messages m
                   WHERE m.conversation_id = c.id
                     AND m.created_at > COALESCE(cm.last_read_at, TIMESTAMPTZ '-infinity')
                     AND (m.sender_id IS DISTINCT FROM $1)
               ), 0) AS unread_count,
               COALESCE((
                   SELECT COUNT(*) FROM agent_proposals p
                   WHERE p.conversation_id = c.id AND p.status = 'pending'
               ), 0) AS pending_proposals
        FROM conversations c
        JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $1
        LEFT JOIN LATERAL (
            SELECT m.body, m.created_at FROM messages m
            WHERE m.conversation_id = c.id
            ORDER BY m.created_at DESC LIMIT 1
        ) last ON TRUE
        ORDER BY COALESCE(last.created_at, c.updated_at) DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

/// Newest-first page of messages; pass the oldest `created_at` you hold as
/// `before` to page backwards.
pub async fn list_messages(
    pool: &PgPool,
    conversation_id: Uuid,
    before: Option<DateTime<Utc>>,
    limit: i64,
) -> Result<Vec<ChatMessage>, sqlx::Error> {
    sqlx::query_as::<_, ChatMessage>(
        r#"
        SELECT m.id, m.conversation_id, m.sender_id, u.name AS sender_name,
               m.kind, m.body, m.metadata, m.created_at, m.edited_at
        FROM messages m
        LEFT JOIN users u ON u.id = m.sender_id
        WHERE m.conversation_id = $1
          AND ($2::timestamptz IS NULL OR m.created_at < $2)
        ORDER BY m.created_at DESC
        LIMIT $3
        "#,
    )
    .bind(conversation_id)
    .bind(before)
    .bind(limit.clamp(1, 200))
    .fetch_all(pool)
    .await
}

/// `sender` is `None` for agent messages. Also bumps the thread so it sorts to
/// the top of everyone's list.
pub async fn post_message(
    pool: &PgPool,
    conversation_id: Uuid,
    sender: Option<Uuid>,
    kind: &str,
    body: &str,
    metadata: JsonValue,
) -> Result<ChatMessage, sqlx::Error> {
    let mut tx = pool.begin().await?;

    let id: (Uuid,) = sqlx::query_as(
        "INSERT INTO messages (conversation_id, sender_id, kind, body, metadata)
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
    )
    .bind(conversation_id)
    .bind(sender)
    .bind(kind)
    .bind(body)
    .bind(metadata)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query("UPDATE conversations SET updated_at = NOW() WHERE id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;

    sqlx::query_as::<_, ChatMessage>(
        r#"
        SELECT m.id, m.conversation_id, m.sender_id, u.name AS sender_name,
               m.kind, m.body, m.metadata, m.created_at, m.edited_at
        FROM messages m
        LEFT JOIN users u ON u.id = m.sender_id
        WHERE m.id = $1
        "#,
    )
    .bind(id.0)
    .fetch_one(pool)
    .await
}

pub async fn mark_read(
    pool: &PgPool,
    conversation_id: Uuid,
    user_id: Uuid,
    read_at: DateTime<Utc>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE conversation_members SET last_read_at = $3
         WHERE conversation_id = $1 AND user_id = $2",
    )
    .bind(conversation_id)
    .bind(user_id)
    .bind(read_at)
    .execute(pool)
    .await?;
    Ok(())
}

/// Members of the thread, used to fan out push notifications.
pub async fn member_ids(
    pool: &PgPool,
    conversation_id: Uuid,
) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND NOT muted",
    )
    .bind(conversation_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}

/// Where an announcement about a fixture should go: its own thread if one
/// exists, otherwise the club's most recently active thread.
pub async fn conversation_for_announcement(
    pool: &PgPool,
    club_id: Uuid,
    event_id: Option<Uuid>,
) -> Result<Option<Uuid>, sqlx::Error> {
    let row: Option<(Uuid,)> = sqlx::query_as(
        r#"
        SELECT id FROM conversations
        WHERE club_id = $1
        ORDER BY (event_id IS NOT DISTINCT FROM $2) DESC, updated_at DESC
        LIMIT 1
        "#,
    )
    .bind(club_id)
    .bind(event_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0))
}
