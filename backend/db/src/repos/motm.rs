//! Man-of-the-match polls: open one, vote in it, count it, close it.

use chrono::{DateTime, Utc};
use fishers_domain::{MotmCandidate, MotmPoll, MotmTallyRow};
use sqlx::PgPool;
use uuid::Uuid;

const POLL_COLS: &str = "id, club_id, event_id, match_id, conversation_id, message_id, title, \
     result, status, closes_at, winner_user_id, created_at, closed_at";

/// A name on a team sheet, ready to go on the ballot.
#[derive(Debug, Clone)]
pub struct CandidateInput {
    pub user_id: Uuid,
    pub display_name: String,
    /// `home` | `away`
    pub side: String,
}

/// Open the poll for a fixture, or hand back the one it already has.
///
/// Re-entrant on purpose. A match can reach "complete" more than once — a
/// scorer correcting the last ball, a tie going to a super over — and each
/// arrival calls this. The second one must not start a second poll, so the
/// insert is a no-op conflict on the fixture and the candidates are topped up
/// rather than replaced: somebody who came on as a substitute after the first
/// poll opened joins the list, and nobody who has already been voted for
/// falls off it.
#[allow(clippy::too_many_arguments)]
pub async fn open_poll(
    pool: &PgPool,
    club_id: Uuid,
    event_id: Uuid,
    match_id: Option<Uuid>,
    title: &str,
    result: Option<&str>,
    closes_at: DateTime<Utc>,
    candidates: &[CandidateInput],
) -> Result<(MotmPoll, bool), sqlx::Error> {
    let mut tx = pool.begin().await?;

    let inserted = sqlx::query_as::<_, MotmPoll>(&format!(
        "INSERT INTO motm_polls (club_id, event_id, match_id, title, result, closes_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (event_id) DO NOTHING
         RETURNING {POLL_COLS}"
    ))
    .bind(club_id)
    .bind(event_id)
    .bind(match_id)
    .bind(title)
    .bind(result)
    .bind(closes_at)
    .fetch_optional(&mut *tx)
    .await?;

    let is_new = inserted.is_some();
    let poll = match inserted {
        Some(poll) => poll,
        None => {
            sqlx::query_as::<_, MotmPoll>(&format!(
                "SELECT {POLL_COLS} FROM motm_polls WHERE event_id = $1"
            ))
            .bind(event_id)
            .fetch_one(&mut *tx)
            .await?
        }
    };

    let ids: Vec<Uuid> = candidates.iter().map(|c| c.user_id).collect();
    let names: Vec<String> = candidates.iter().map(|c| c.display_name.clone()).collect();
    let sides: Vec<String> = candidates.iter().map(|c| c.side.clone()).collect();
    sqlx::query(
        "INSERT INTO motm_poll_candidates (poll_id, user_id, display_name, side)
         SELECT $1, * FROM UNNEST($2::uuid[], $3::text[], $4::text[])
         ON CONFLICT (poll_id, user_id) DO UPDATE
            SET display_name = EXCLUDED.display_name, side = EXCLUDED.side",
    )
    .bind(poll.id)
    .bind(&ids)
    .bind(&names)
    .bind(&sides)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok((poll, is_new))
}

/// Record a match result that has moved on, and say whether it actually had.
///
/// The write *is* the check: `IS DISTINCT FROM` means only the caller whose
/// update changed the row gets `true` back, so the follow-up is posted once
/// however many replicas saw the same super over finish. Doing it the other
/// way round — read, compare, write — is two API pods announcing the same
/// result twice to the same thread.
///
/// `NULL` is handled by `IS DISTINCT FROM` rather than `<>`, which would
/// answer NULL (falsy) for a poll opened before a margin was recorded and
/// leave that result silently unannounced.
pub async fn record_result_change(
    pool: &PgPool,
    poll_id: Uuid,
    result: Option<&str>,
) -> Result<bool, sqlx::Error> {
    let done = sqlx::query(
        "UPDATE motm_polls SET result = $2
          WHERE id = $1 AND result IS DISTINCT FROM $2",
    )
    .bind(poll_id)
    .bind(result)
    .execute(pool)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// Remember where the vote card was posted, so a client holding the message
/// can find the poll and a client holding the poll can find the thread.
pub async fn attach_message(
    pool: &PgPool,
    poll_id: Uuid,
    conversation_id: Uuid,
    message_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE motm_polls SET conversation_id = $2, message_id = $3 WHERE id = $1",
    )
    .bind(poll_id)
    .bind(conversation_id)
    .bind(message_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_poll(pool: &PgPool, id: Uuid) -> Result<Option<MotmPoll>, sqlx::Error> {
    sqlx::query_as::<_, MotmPoll>(&format!("SELECT {POLL_COLS} FROM motm_polls WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

pub async fn poll_for_event(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Option<MotmPoll>, sqlx::Error> {
    sqlx::query_as::<_, MotmPoll>(&format!(
        "SELECT {POLL_COLS} FROM motm_polls WHERE event_id = $1"
    ))
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

/// The ballot, with each candidate's count.
///
/// Sorted by votes then name so the card reads as a leaderboard once the
/// tally is out, and alphabetically within a side before anyone has voted.
/// Whether the caller is allowed to *see* those counts is decided above this,
/// in the route — the repo's job is to answer what was asked.
pub async fn candidates(
    pool: &PgPool,
    poll_id: Uuid,
) -> Result<Vec<MotmCandidate>, sqlx::Error> {
    sqlx::query_as::<_, MotmCandidate>(
        r#"
        SELECT c.user_id, c.display_name, c.side,
               COALESCE(COUNT(v.voter_id), 0) AS votes
        FROM motm_poll_candidates c
        LEFT JOIN motm_votes v
               ON v.poll_id = c.poll_id AND v.candidate_user_id = c.user_id
        WHERE c.poll_id = $1
        GROUP BY c.user_id, c.display_name, c.side
        ORDER BY votes DESC, c.side, c.display_name
        "#,
    )
    .bind(poll_id)
    .fetch_all(pool)
    .await
}

/// Cast or move a vote. Returns false when the candidate is not on the ballot.
pub async fn cast_vote(
    pool: &PgPool,
    poll_id: Uuid,
    voter_id: Uuid,
    candidate_user_id: Uuid,
) -> Result<bool, sqlx::Error> {
    // The composite foreign key already refuses a candidate who is not on
    // this ballot, but it refuses it as a database error rather than as an
    // answer. Checking first turns "somebody voted for a player who wasn't
    // playing" into a 400 with a sentence on it.
    let on_ballot: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM motm_poll_candidates WHERE poll_id = $1 AND user_id = $2)",
    )
    .bind(poll_id)
    .bind(candidate_user_id)
    .fetch_one(pool)
    .await?;
    if !on_ballot {
        return Ok(false);
    }

    sqlx::query(
        "INSERT INTO motm_votes (poll_id, voter_id, candidate_user_id)
         VALUES ($1, $2, $3)
         ON CONFLICT (poll_id, voter_id) DO UPDATE
            SET candidate_user_id = EXCLUDED.candidate_user_id, updated_at = NOW()",
    )
    .bind(poll_id)
    .bind(voter_id)
    .bind(candidate_user_id)
    .execute(pool)
    .await?;
    Ok(true)
}

/// Take a vote back. Silent when there was none to take.
pub async fn withdraw_vote(
    pool: &PgPool,
    poll_id: Uuid,
    voter_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let done = sqlx::query("DELETE FROM motm_votes WHERE poll_id = $1 AND voter_id = $2")
        .bind(poll_id)
        .bind(voter_id)
        .execute(pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

pub async fn my_vote(
    pool: &PgPool,
    poll_id: Uuid,
    voter_id: Uuid,
) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar("SELECT candidate_user_id FROM motm_votes WHERE poll_id = $1 AND voter_id = $2")
        .bind(poll_id)
        .bind(voter_id)
        .fetch_optional(pool)
        .await
}

pub async fn total_votes(pool: &PgPool, poll_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar("SELECT COUNT(*) FROM motm_votes WHERE poll_id = $1")
        .bind(poll_id)
        .fetch_one(pool)
        .await
}

/// Who won, and by how much — highest first. Empty when nobody voted.
pub async fn tally(pool: &PgPool, poll_id: Uuid) -> Result<Vec<MotmTallyRow>, sqlx::Error> {
    sqlx::query_as::<_, MotmTallyRow>(
        r#"
        SELECT c.user_id, c.display_name, COUNT(v.voter_id) AS votes
        FROM motm_poll_candidates c
        JOIN motm_votes v ON v.poll_id = c.poll_id AND v.candidate_user_id = c.user_id
        WHERE c.poll_id = $1
        GROUP BY c.user_id, c.display_name
        ORDER BY votes DESC, c.display_name
        "#,
    )
    .bind(poll_id)
    .fetch_all(pool)
    .await
}

/// Close the poll and record the winner.
///
/// Returns `None` when it was already closed, so the caller can tell "I closed
/// it" from "somebody beat me to it" and announce the result only once. A tie
/// is closed with no winner: the app says who tied and a captain gives the
/// award, because a coin toss between two players is not the database's call.
pub async fn close_poll(
    pool: &PgPool,
    poll_id: Uuid,
    winner: Option<Uuid>,
    closed_by: Option<Uuid>,
) -> Result<Option<MotmPoll>, sqlx::Error> {
    sqlx::query_as::<_, MotmPoll>(&format!(
        "UPDATE motm_polls
            SET status = 'closed', winner_user_id = $2, closed_by = $3, closed_at = NOW()
          WHERE id = $1 AND status = 'open'
         RETURNING {POLL_COLS}"
    ))
    .bind(poll_id)
    .bind(winner)
    .bind(closed_by)
    .fetch_optional(pool)
    .await
}

/// Polls whose closing time has passed but which nobody has closed.
///
/// The sweeper reads this; see `fishers_jobs`. Capped because a backlog after
/// an outage should be worked through in batches, not in one transaction.
pub async fn due_to_close(pool: &PgPool, limit: i64) -> Result<Vec<MotmPoll>, sqlx::Error> {
    sqlx::query_as::<_, MotmPoll>(&format!(
        "SELECT {POLL_COLS} FROM motm_polls
          WHERE status = 'open' AND closes_at <= NOW()
          ORDER BY closes_at
          LIMIT $1"
    ))
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Record the club's award on the winner's profile.
///
/// `user_achievements` is unique per user, code and season, so a second man of
/// the match in the same summer is a no-op rather than a duplicate row — the
/// badge says "has been named", not "how many times".
pub async fn award_achievement(
    pool: &PgPool,
    user_id: Uuid,
    club_id: Uuid,
    season_year: i32,
    evidence: serde_json::Value,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO user_achievements (user_id, achievement_code, club_id, season_year, evidence)
         VALUES ($1, 'motm', $2, $3, $4)
         ON CONFLICT (user_id, achievement_code, season_year) DO NOTHING",
    )
    .bind(user_id)
    .bind(club_id)
    .bind(season_year)
    .bind(evidence)
    .execute(pool)
    .await?;
    Ok(())
}
