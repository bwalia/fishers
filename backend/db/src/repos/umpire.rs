//! Who umpired, how it went, and who is willing to stand again.

use fishers_domain::{
    AvailableUmpire, MatchUmpire, PendingUmpireReview, UmpireProfile, UmpireReview,
    UmpireReviewView,
};
use sqlx::PgPool;
use uuid::Uuid;

/// The last few reviews shown in full on a profile. The counts above them are
/// over everything; this is the part somebody reads.
const RECENT: i64 = 20;

/// A player's umpiring record.
///
/// Three queries rather than one: the counts are over every review, the
/// breakdown groups them, and the list is only the recent ones. Doing it as a
/// single query means either fetching every review to count them or a window
/// function whose plan nobody will read again.
pub async fn profile(pool: &PgPool, user_id: Uuid) -> Result<UmpireProfile, sqlx::Error> {
    let (umpires, note): (bool, Option<String>) =
        sqlx::query_as("SELECT umpires, umpire_note FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await?;

    // Completed only. Standing in a match that is still being played is not
    // yet a match umpired, and a scheduled one certainly is not.
    let (matches,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM cricket_match_officials o
           JOIN cricket_matches m ON m.id = o.match_id
          WHERE o.user_id = $1 AND o.role = 'umpire' AND m.status = 'complete'",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    let rows: Vec<(i16, i64)> = sqlx::query_as(
        "SELECT rating, COUNT(*) FROM cricket_umpire_reviews
          WHERE umpire_id = $1 GROUP BY rating",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    let mut breakdown = [0i64; 5];
    for (rating, count) in &rows {
        // The column is checked 1..=5, so this cannot be out of range — but a
        // panic in a profile read is not the way to find out if it ever is.
        if let Some(slot) = breakdown.get_mut((*rating as usize).saturating_sub(1)) {
            *slot = *count;
        }
    }
    let rating_count: i64 = breakdown.iter().sum();
    let rating_average = fishers_domain::rating_average(&breakdown);

    let reviews = recent_reviews(pool, user_id, RECENT).await?;

    Ok(UmpireProfile {
        user_id,
        umpires,
        note,
        matches,
        rating_average,
        rating_count,
        rating_breakdown: breakdown,
        reviews,
    })
}

async fn recent_reviews(
    pool: &PgPool,
    umpire_id: Uuid,
    limit: i64,
) -> Result<Vec<UmpireReviewView>, sqlx::Error> {
    sqlx::query_as::<_, UmpireReviewView>(
        "SELECT r.id, r.match_id, r.rating, r.comment, r.created_at,
                u.name AS reviewer_name, u.avatar_url AS reviewer_avatar_url,
                m.home_name || ' v ' || m.away_name AS match_title,
                e.start_at AS played_on
           FROM cricket_umpire_reviews r
           JOIN users u ON u.id = r.reviewer_id
           JOIN cricket_matches m ON m.id = r.match_id
           JOIN events e ON e.id = m.event_id
          WHERE r.umpire_id = $1
          ORDER BY r.created_at DESC
          LIMIT $2",
    )
    .bind(umpire_id)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Leave a review, or change the one already left.
///
/// Upsert rather than insert: a player who rated three at the time and wants
/// to make it a four should not be told they have already voted. The trail of
/// what they first said is not worth keeping — this is a rating, not a ledger.
pub async fn review(
    pool: &PgPool,
    match_id: Uuid,
    umpire_id: Uuid,
    reviewer_id: Uuid,
    rating: i16,
    comment: Option<&str>,
) -> Result<UmpireReview, sqlx::Error> {
    sqlx::query_as::<_, UmpireReview>(
        "INSERT INTO cricket_umpire_reviews (match_id, umpire_id, reviewer_id, rating, comment)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (match_id, umpire_id, reviewer_id)
         DO UPDATE SET rating = EXCLUDED.rating,
                       comment = EXCLUDED.comment,
                       updated_at = NOW()
         RETURNING id, match_id, umpire_id, reviewer_id, rating, comment, created_at, updated_at",
    )
    .bind(match_id)
    .bind(umpire_id)
    .bind(reviewer_id)
    .bind(rating)
    .bind(comment)
    .fetch_one(pool)
    .await
}

pub async fn withdraw_review(
    pool: &PgPool,
    match_id: Uuid,
    umpire_id: Uuid,
    reviewer_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let done = sqlx::query(
        "DELETE FROM cricket_umpire_reviews
          WHERE match_id = $1 AND umpire_id = $2 AND reviewer_id = $3",
    )
    .bind(match_id)
    .bind(umpire_id)
    .bind(reviewer_id)
    .execute(pool)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// The umpires in a match, with whatever the asking player already said.
pub async fn match_umpires(
    pool: &PgPool,
    match_id: Uuid,
    asking: Uuid,
) -> Result<Vec<MatchUmpire>, sqlx::Error> {
    sqlx::query_as::<_, MatchUmpire>(
        "SELECT u.id AS user_id, u.name, u.avatar_url,
                r.rating AS my_rating, r.comment AS my_comment
           FROM cricket_match_officials o
           JOIN users u ON u.id = o.user_id
           LEFT JOIN cricket_umpire_reviews r
                  ON r.match_id = o.match_id
                 AND r.umpire_id = o.user_id
                 AND r.reviewer_id = $2
          WHERE o.match_id = $1 AND o.role = 'umpire'
          ORDER BY u.name",
    )
    .bind(match_id)
    .bind(asking)
    .fetch_all(pool)
    .await
}

/// Everyone in a club who has said they will stand, best-known first.
///
/// Ordered by matches rather than by rating: a five from one review is not
/// better than a 4.3 from thirty, and sorting by average puts it top.
pub async fn available_in_club(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<AvailableUmpire>, sqlx::Error> {
    sqlx::query_as::<_, AvailableUmpire>(
        "SELECT u.id AS user_id, u.name, u.avatar_url, u.umpire_note AS note,
                COALESCE(stood.n, 0) AS matches,
                ROUND(rated.avg, 1)::float8 AS rating_average,
                COALESCE(rated.n, 0) AS rating_count
           FROM users u
           JOIN club_members cm ON cm.user_id = u.id AND cm.club_id = $1
           LEFT JOIN LATERAL (
                SELECT COUNT(*) AS n
                  FROM cricket_match_officials o
                  JOIN cricket_matches m ON m.id = o.match_id
                 WHERE o.user_id = u.id AND o.role = 'umpire' AND m.status = 'complete'
           ) stood ON TRUE
           LEFT JOIN LATERAL (
                SELECT AVG(rating) AS avg, COUNT(*) AS n
                  FROM cricket_umpire_reviews WHERE umpire_id = u.id
           ) rated ON TRUE
          WHERE u.umpires
          ORDER BY matches DESC, u.name",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Whether somebody was part of a match: selected for it, or an official of it.
///
/// The gate on leaving a review. Being in the club is not enough — a review
/// should come from somebody who was there.
pub async fn took_part(pool: &PgPool, match_id: Uuid, user_id: Uuid) -> Result<bool, sqlx::Error> {
    let (yes,): (bool,) = sqlx::query_as(
        "SELECT EXISTS (
            SELECT 1 FROM cricket_matches m
              JOIN event_invites i ON i.event_id = m.event_id
             WHERE m.id = $1 AND i.user_id = $2
               AND i.selection_state IN ('selected', 'confirmed')
         ) OR EXISTS (
            SELECT 1 FROM cricket_match_officials o
             WHERE o.match_id = $1 AND o.user_id = $2
         )",
    )
    .bind(match_id)
    .bind(user_id)
    .fetch_one(pool)
    .await?;
    Ok(yes)
}

/// Set whether somebody will stand, and what they want said about it.
///
/// Both arguments are "leave it alone" when `None`, which is what a PATCH of
/// one field means. The note's inner Option is the difference between clearing
/// it and not mentioning it.
pub async fn set_willing(
    pool: &PgPool,
    user_id: Uuid,
    umpires: Option<bool>,
    note: Option<Option<String>>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE users
            SET umpires = COALESCE($2, umpires),
                umpire_note = CASE WHEN $3 THEN $4 ELSE umpire_note END
          WHERE id = $1",
    )
    .bind(user_id)
    .bind(umpires)
    .bind(note.is_some())
    .bind(note.flatten())
    .execute(pool)
    .await?;
    Ok(())
}

/// Whether this person was a named umpire of this match.
///
/// The check that stops a rating being aimed at somebody who stood in a
/// different fixture, or never stood at all.
pub async fn stood_in(pool: &PgPool, match_id: Uuid, umpire_id: Uuid) -> Result<bool, sqlx::Error> {
    let (yes,): (bool,) = sqlx::query_as(
        "SELECT EXISTS (
            SELECT 1 FROM cricket_match_officials
             WHERE match_id = $1 AND user_id = $2 AND role = 'umpire'
         )",
    )
    .bind(match_id)
    .bind(umpire_id)
    .fetch_one(pool)
    .await?;
    Ok(yes)
}

/// A match's status as text.
///
/// `::TEXT` because the column is a Postgres enum and sqlx would want a type
/// that mirrors all nine of its values to read it as anything else.
pub async fn match_status(pool: &PgPool, match_id: Uuid) -> Result<Option<String>, sqlx::Error> {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT status::TEXT FROM cricket_matches WHERE id = $1")
            .bind(match_id)
            .fetch_optional(pool)
            .await?;
    Ok(row.map(|(s,)| s))
}

/// Rows behind [pending_reviews] — one per umpire still to be rated.
#[derive(sqlx::FromRow)]
struct PendingRow {
    match_id: Uuid,
    match_title: String,
    played_on: Option<chrono::DateTime<chrono::Utc>>,
    user_id: Uuid,
    name: String,
    avatar_url: Option<String>,
}

/// Finished matches this player was in, with the umpires they have not rated.
///
/// Bounded to the last few months on purpose: a review left eighteen months
/// after the afternoon is not a memory of it, and an unbounded list would grow
/// into a page nobody opens.
pub async fn pending_reviews(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<PendingUmpireReview>, sqlx::Error> {
    let rows = sqlx::query_as::<_, PendingRow>(
        "SELECT m.id AS match_id,
                m.home_name || ' v ' || m.away_name AS match_title,
                e.start_at AS played_on,
                u.id AS user_id, u.name, u.avatar_url
           FROM cricket_matches m
           JOIN events e ON e.id = m.event_id
           JOIN cricket_match_officials o ON o.match_id = m.id AND o.role = 'umpire'
           JOIN users u ON u.id = o.user_id
          WHERE m.status IN ('complete', 'published')
            AND e.start_at > NOW() - INTERVAL '120 days'
            -- Somebody else, and somebody they have not already rated.
            AND o.user_id <> $1
            AND NOT EXISTS (
                SELECT 1 FROM cricket_umpire_reviews r
                 WHERE r.match_id = m.id AND r.umpire_id = o.user_id
                   AND r.reviewer_id = $1
            )
            -- And they have to have been there.
            AND (
                EXISTS (
                    SELECT 1 FROM event_invites i
                     WHERE i.event_id = m.event_id AND i.user_id = $1
                       AND i.selection_state IN ('selected', 'confirmed')
                )
                OR EXISTS (
                    SELECT 1 FROM cricket_match_officials mine
                     WHERE mine.match_id = m.id AND mine.user_id = $1
                )
            )
          ORDER BY e.start_at DESC, u.name",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    // Grouped here rather than in SQL: json_agg would need the row type
    // spelled out twice and this is a handful of rows.
    let mut out: Vec<PendingUmpireReview> = Vec::new();
    for row in rows {
        let umpire = MatchUmpire {
            user_id: row.user_id,
            name: row.name,
            avatar_url: row.avatar_url,
            my_rating: None,
            my_comment: None,
        };
        match out.last_mut() {
            Some(last) if last.match_id == row.match_id => last.umpires.push(umpire),
            _ => out.push(PendingUmpireReview {
                match_id: row.match_id,
                match_title: row.match_title,
                played_on: row.played_on,
                umpires: vec![umpire],
            }),
        }
    }
    Ok(out)
}
