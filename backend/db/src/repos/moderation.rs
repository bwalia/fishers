use fishers_domain::{
    BlockedUser, ContentReport, CreateReportRequest, ReportVerdict, SubjectKind,
};
use sqlx::PgPool;
use uuid::Uuid;

/// Block somebody. Blocking twice is the same as blocking once.
pub async fn block(pool: &PgPool, blocker: Uuid, blocked: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
         ON CONFLICT (blocker_id, blocked_id) DO NOTHING",
    )
    .bind(blocker)
    .bind(blocked)
    .execute(pool)
    .await?;
    Ok(())
}

/// Unblock. Only removes your own block — it cannot lift theirs.
pub async fn unblock(pool: &PgPool, blocker: Uuid, blocked: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2")
        .bind(blocker)
        .bind(blocked)
        .execute(pool)
        .await?;
    Ok(())
}

/// Who *you* have blocked — your list, to review and undo. Deliberately not
/// symmetric: this one is the record of your own decisions, and showing
/// people who blocked you would tell you that they had.
pub async fn list_blocks(pool: &PgPool, blocker: Uuid) -> Result<Vec<BlockedUser>, sqlx::Error> {
    sqlx::query_as::<_, BlockedUser>(
        "SELECT u.id, u.name, u.avatar_url, b.created_at AS blocked_at
         FROM user_blocks b
         JOIN users u ON u.id = b.blocked_id
         WHERE b.blocker_id = $1
         ORDER BY b.created_at DESC",
    )
    .bind(blocker)
    .fetch_all(pool)
    .await
}

/// Everybody hidden from `user`, in either direction — the people they
/// blocked and the people who blocked them. This is the one enforcement
/// primitive; every place that filters by a block goes through it, so the
/// symmetry is decided once rather than per query.
pub async fn hidden_from(pool: &PgPool, user: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT blocked_id FROM user_blocks WHERE blocker_id = $1
         UNION
         SELECT blocker_id FROM user_blocks WHERE blocked_id = $1",
    )
    .bind(user)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|(id,)| id).collect())
}

/// Whether these two are hidden from each other. Used where a list filter
/// would be the wrong shape — refusing to open a direct thread, for instance.
pub async fn blocked_between(pool: &PgPool, a: Uuid, b: Uuid) -> Result<bool, sqlx::Error> {
    let found: Option<(i32,)> = sqlx::query_as(
        "SELECT 1 FROM user_blocks
         WHERE (blocker_id = $1 AND blocked_id = $2)
            OR (blocker_id = $2 AND blocked_id = $1)
         LIMIT 1",
    )
    .bind(a)
    .bind(b)
    .fetch_optional(pool)
    .await?;
    Ok(found.is_some())
}

/// File a report. Reporting the same thing twice while the first is still
/// open returns the report already filed rather than a second row — the
/// unique index says so, and a person tapping twice has not made two
/// complaints.
pub async fn create_report(
    pool: &PgPool,
    reporter: Uuid,
    req: &CreateReportRequest,
) -> Result<ContentReport, sqlx::Error> {
    let note = req.note.as_deref().map(str::trim).filter(|n| !n.is_empty());

    sqlx::query_as::<_, ContentReport>(
        "WITH filed AS (
             INSERT INTO content_reports (reporter_id, subject_kind, subject_id, reason, note)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (reporter_id, subject_kind, subject_id)
                WHERE status = 'open' DO NOTHING
             RETURNING id
         )
         SELECT r.id, r.reporter_id, u.name AS reporter_name, r.subject_kind, r.subject_id,
                r.reason, r.note, r.status, r.created_at, r.reviewed_at
         FROM content_reports r
         LEFT JOIN users u ON u.id = r.reporter_id
         WHERE r.id = COALESCE(
                   (SELECT id FROM filed),
                   (SELECT id FROM content_reports
                     WHERE reporter_id = $1 AND subject_kind = $2 AND subject_id = $3
                       AND status = 'open'
                     LIMIT 1))",
    )
    .bind(reporter)
    .bind(req.subject_kind.as_str())
    .bind(req.subject_id)
    .bind(req.reason.as_str())
    .bind(note)
    .fetch_one(pool)
    .await
}

/// What is still open, oldest first. Oldest first on purpose: the obligation
/// is a timely response, and the oldest one is the one running out of time.
pub async fn list_open_reports(pool: &PgPool, limit: i64) -> Result<Vec<ContentReport>, sqlx::Error> {
    sqlx::query_as::<_, ContentReport>(
        "SELECT r.id, r.reporter_id, u.name AS reporter_name, r.subject_kind, r.subject_id,
                r.reason, r.note, r.status, r.created_at, r.reviewed_at
         FROM content_reports r
         LEFT JOIN users u ON u.id = r.reporter_id
         WHERE r.status = 'open'
         ORDER BY r.created_at
         LIMIT $1",
    )
    .bind(limit.clamp(1, 200))
    .fetch_all(pool)
    .await
}

/// Record what a reviewer decided.
pub async fn resolve_report(
    pool: &PgPool,
    id: Uuid,
    reviewer: Uuid,
    verdict: ReportVerdict,
) -> Result<Option<ContentReport>, sqlx::Error> {
    sqlx::query_as::<_, ContentReport>(
        "WITH decided AS (
             UPDATE content_reports
                SET status = $3, reviewed_at = now(), reviewed_by = $2
              WHERE id = $1 AND status = 'open'
             RETURNING id
         )
         SELECT r.id, r.reporter_id, u.name AS reporter_name, r.subject_kind, r.subject_id,
                r.reason, r.note, r.status, r.created_at, r.reviewed_at
         FROM content_reports r
         LEFT JOIN users u ON u.id = r.reporter_id
         WHERE r.id = (SELECT id FROM decided)",
    )
    .bind(id)
    .bind(reviewer)
    .bind(verdict.as_str())
    .fetch_optional(pool)
    .await
}

/// How many reports name this subject and are still open. Lets a list show
/// "reported" without leaking who reported it.
pub async fn open_report_count(
    pool: &PgPool,
    kind: SubjectKind,
    subject: Uuid,
) -> Result<i64, sqlx::Error> {
    let (count,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM content_reports
          WHERE subject_kind = $1 AND subject_id = $2 AND status = 'open'",
    )
    .bind(kind.as_str())
    .bind(subject)
    .fetch_one(pool)
    .await?;
    Ok(count)
}
