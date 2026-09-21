//! Opening, announcing and closing the club's man-of-the-match vote.
//!
//! The scorer's award (`player_of_the_match` in the scoring log) is one
//! person's call, made by whoever was holding the book. This is the club's:
//! when the last wicket falls the fixture's chat thread gets a vote card, and
//! everyone in the club votes — the eleven who played, the four who were
//! twelfth man, and the people who watched from the boundary, which on most
//! Saturdays is most of the club.

use chrono::{Datelike, Duration, Utc};
use fishers_db::repos::{
    chat as chat_repo, clubs as clubs_repo, cricket as cricket_repo, events as events_repo,
    motm as motm_repo,
};
use fishers_domain::{MatchSide, MatchState, MotmPoll};
use serde_json::json;
use std::collections::BTreeSet;
use tracing::warn;
use uuid::Uuid;

use crate::state::AppState;

/// How long a poll stays open. Long enough that somebody who put their phone
/// away at the ground still gets a vote on Sunday morning; short enough that
/// the result belongs to the game people remember.
const VOTING_WINDOW_HOURS: i64 = 48;

/// Open the vote for a finished cricket match, post the card to the fixture's
/// thread, and tell the club.
///
/// Every part of this is best-effort and logged rather than returned: it is
/// called from the scorer's ball-by-ball endpoint, and a chat thread that
/// cannot be found must never turn the last ball of a match into an error on
/// somebody's phone.
pub async fn open_for_completed_cricket_match(
    state: &AppState,
    club_id: Uuid,
    opponent_club_id: Option<Uuid>,
    event_id: Uuid,
    match_id: Uuid,
    match_state: &MatchState,
) {
    let candidates = candidates_from(match_state);
    if candidates.is_empty() {
        // No team sheet, no ballot. A match scored without an XI — a casual
        // game put in afterwards — has nobody to vote for.
        return;
    }

    let title = poll_title(state, event_id, match_state).await;
    let closes_at = Utc::now() + Duration::hours(VOTING_WINDOW_HOURS);

    let (poll, is_new) = match motm_repo::open_poll(
        &state.pool,
        club_id,
        event_id,
        Some(match_id),
        &title,
        closes_at,
        &candidates,
    )
    .await
    {
        Ok(opened) => opened,
        Err(error) => {
            warn!(%error, %event_id, "could not open the man-of-the-match vote");
            return;
        }
    };

    // A match reaching "complete" a second time — a corrected last ball, a
    // super over — must not repost the card or push everyone again.
    if !is_new {
        return;
    }

    // The margin is already a whole sentence — "Hemel won by 7 wickets (52
    // balls remaining)" — so it is one, rather than the subject of another.
    let result = match match_state.margin.as_deref() {
        Some(margin) => format!("{margin}."),
        None => "The match is over.".to_string(),
    };
    let body = format!(
        "{result} Who was your man of the match? Everyone in the club can vote — \
         voting closes {}.",
        closes_at.format("%a %e %b at %H:%M UTC")
    );

    if let Some(conversation_id) = conversation_for(state, club_id, event_id).await {
        match chat_repo::post_message(
            &state.pool,
            conversation_id,
            None,
            "system",
            &body,
            json!({ "kind": "motm_poll", "motm_poll_id": poll.id, "event_id": event_id }),
        )
        .await
        {
            Ok(message) => {
                if let Err(error) =
                    motm_repo::attach_message(&state.pool, poll.id, conversation_id, message.id)
                        .await
                {
                    warn!(%error, %poll.id, "vote card posted but not linked to the poll");
                }
            }
            Err(error) => warn!(%error, %poll.id, "could not post the vote card"),
        }
    }

    notify_club(
        state,
        club_id,
        opponent_club_id,
        &poll,
        "motm_vote_open",
        "Man of the match",
        &format!("Vote for your man of the match in {title}."),
        None,
    )
    .await;
}

/// Close a poll, announce the result and record the award.
///
/// `closed_by` is the captain who ended it early, or `None` for the sweeper
/// closing one whose time is up. Returns the closed poll, or `None` when
/// somebody else closed it first — which is what stops two callers announcing
/// the same result twice.
pub async fn close_and_announce(
    state: &AppState,
    poll: &MotmPoll,
    closed_by: Option<Uuid>,
) -> Option<MotmPoll> {
    let tally = match motm_repo::tally(&state.pool, poll.id).await {
        Ok(rows) => rows,
        Err(error) => {
            warn!(%error, %poll.id, "could not count the man-of-the-match vote");
            return None;
        }
    };

    let top = tally.first();
    let (winner, tied) = decide_winner(&tally);

    let closed = match motm_repo::close_poll(&state.pool, poll.id, winner, closed_by).await {
        Ok(Some(closed)) => closed,
        // Already closed — somebody got there first, and they announced it.
        Ok(None) => return None,
        Err(error) => {
            warn!(%error, %poll.id, "could not close the man-of-the-match vote");
            return None;
        }
    };

    let body = match (&top, tied) {
        (None, _) => "Nobody voted for a man of the match.".to_string(),
        (Some(first), true) => {
            let names: Vec<&str> = tally
                .iter()
                .filter(|row| row.votes == first.votes)
                .map(|row| row.display_name.as_str())
                .collect();
            format!(
                "The man-of-the-match vote is a tie on {} votes: {}. A captain picks.",
                first.votes,
                names.join(", ")
            )
        }
        (Some(first), false) => format!(
            "{} is your man of the match with {} of {} votes.",
            first.display_name,
            first.votes,
            tally.iter().map(|row| row.votes).sum::<i64>()
        ),
    };

    if let Some(conversation_id) = closed
        .conversation_id
        .or(conversation_for(state, closed.club_id, closed.event_id).await)
    {
        if let Err(error) = chat_repo::post_message(
            &state.pool,
            conversation_id,
            None,
            "system",
            &body,
            json!({ "kind": "motm_result", "motm_poll_id": closed.id, "winner_user_id": winner }),
        )
        .await
        {
            warn!(%error, %closed.id, "could not post the man-of-the-match result");
        }
    }

    if let Some(winner) = winner {
        let evidence = json!({
            "event_id": closed.event_id,
            "match_id": closed.match_id,
            "poll_id": closed.id,
            "votes": top.map(|row| row.votes),
            "source": "club_vote",
        });
        if let Err(error) = motm_repo::award_achievement(
            &state.pool,
            winner,
            closed.club_id,
            Utc::now().year(),
            evidence,
        )
        .await
        {
            warn!(%error, %winner, "could not record the man-of-the-match award");
        }
        // The scorecard carries the award too, so a card read months later
        // says who the club voted for rather than nothing at all. Only when
        // the scorer never named anybody — their own award is theirs, and a
        // vote must not quietly overwrite it.
        write_award_to_scorecard(state, &closed, winner).await;
    }

    notify_club(
        state,
        closed.club_id,
        opponent_of(state, closed.event_id).await,
        &closed,
        "motm_result",
        "Man of the match",
        &body,
        winner,
    )
    .await;

    Some(closed)
}

/// Put the club's winner on the scorecard, unless the scorer already named
/// somebody.
///
/// Written through the scoring log like any other change to a match, so it
/// replays the same on every device and shows up in the scorer's trail rather
/// than appearing in the state from nowhere. The poll's creator is the actor:
/// the server opened the poll, so the server's write is attributed to whoever
/// created the match.
async fn write_award_to_scorecard(state: &AppState, poll: &MotmPoll, winner: Uuid) {
    let Some(match_id) = poll.match_id else {
        return;
    };
    let Ok(Some(row)) = cricket_repo::get_match(&state.pool, match_id).await else {
        return;
    };
    let current = cricket_repo::parse_state(&row);
    if current.player_of_the_match.is_some() {
        return;
    }
    // Only somebody who was on a team sheet can be the player of the match;
    // a vote for a club member who did not play is not a scorecard entry.
    if !current.home_xi.contains(&winner) && !current.away_xi.contains(&winner) {
        return;
    }

    let event = fishers_domain::ScoringEvent {
        client_event_id: Uuid::new_v4(),
        // The log is append-only and numbered: anything at or below the last
        // sequence is treated as already applied and silently dropped.
        seq: current.last_seq + 1,
        kind: fishers_domain::ScoringEventKind::PlayerOfTheMatch { player_id: winner },
        at: Some(Utc::now()),
    };
    if let Err(error) = cricket_repo::apply_event_batch(
        &state.pool,
        match_id,
        std::slice::from_ref(&event),
        row.created_by,
        None,
    )
    .await
    {
        warn!(%error, %match_id, "could not write the voted award to the scorecard");
    }
}

/// Who won, and whether it was a tie.
///
/// `tally` is votes-descending, as the repo returns it. A tie is left
/// undecided on purpose: choosing between two players who drew is a captain's
/// job, not a tiebreak rule nobody voted for. Nobody voting is not a tie —
/// it is simply no winner.
fn decide_winner(tally: &[fishers_domain::MotmTallyRow]) -> (Option<Uuid>, bool) {
    let Some(first) = tally.first() else {
        return (None, false);
    };
    let tied = tally.iter().filter(|row| row.votes == first.votes).count() > 1;
    if tied {
        (None, true)
    } else {
        (Some(first.user_id), false)
    }
}

/// Everyone who could be voted for: both team sheets, named.
fn candidates_from(state: &MatchState) -> Vec<motm_repo::CandidateInput> {
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for (side, xi) in [
        (MatchSide::Home, &state.home_xi),
        (MatchSide::Away, &state.away_xi),
    ] {
        for id in xi {
            // A player listed on both sheets is a data error, not two
            // candidates: the primary key would reject the second insert and
            // take the whole ballot with it.
            if !seen.insert(*id) {
                continue;
            }
            out.push(motm_repo::CandidateInput {
                user_id: *id,
                display_name: state.name_for(*id),
                side: match side {
                    MatchSide::Home => "home".into(),
                    MatchSide::Away => "away".into(),
                },
            });
        }
    }
    out
}

/// "Hemel Hempstead vs Chesham, Saturday" — what the fixture was called, or
/// failing that what the two sides were called.
async fn poll_title(state: &AppState, event_id: Uuid, match_state: &MatchState) -> String {
    match events_repo::get_event(&state.pool, event_id).await {
        Ok(Some(event)) if !event.title.trim().is_empty() => event.title,
        _ => format!("{} v {}", match_state.home_name, match_state.away_name),
    }
}

/// The fixture's own thread if it has one, else the club's busiest.
async fn conversation_for(state: &AppState, club_id: Uuid, event_id: Uuid) -> Option<Uuid> {
    chat_repo::conversation_for_announcement(&state.pool, club_id, Some(event_id))
        .await
        .unwrap_or_default()
}

async fn opponent_of(state: &AppState, event_id: Uuid) -> Option<Uuid> {
    events_repo::get_event(&state.pool, event_id)
        .await
        .ok()
        .flatten()
        .and_then(|event| event.opponent_club_id)
}

/// Tell every active member of both clubs — not just the eleven who played.
///
/// That is the whole point of the feature: the people watching are the ones
/// with an opinion and a free hand. Stored as well as pushed, so somebody
/// whose phone was off still finds it in the bell.
#[allow(clippy::too_many_arguments)]
async fn notify_club(
    state: &AppState,
    club_id: Uuid,
    opponent_club_id: Option<Uuid>,
    poll: &MotmPoll,
    kind: &str,
    title: &str,
    body: &str,
    winner: Option<Uuid>,
) {
    let mut recipients: BTreeSet<Uuid> = BTreeSet::new();
    for club in std::iter::once(club_id).chain(opponent_club_id) {
        match clubs_repo::list_members(&state.pool, club).await {
            Ok(members) => recipients.extend(members.into_iter().map(|m| m.user_id)),
            Err(error) => warn!(%error, %club, "could not read the roster to tell them about the vote"),
        }
    }

    let payload = json!({
        "title": title,
        "body": body,
        "motm_poll_id": poll.id,
        "event_id": poll.event_id,
        "conversation_id": poll.conversation_id,
        "winner_user_id": winner,
        // Where a tap lands. The thread is where the card is, so that is
        // where the notification goes — not a generic notifications page.
        "url": poll
            .conversation_id
            .map(|id| format!("/chat/{id}"))
            .unwrap_or_else(|| "/notifications".into()),
    });

    for recipient in recipients {
        state.notify(recipient, kind, title, body, payload.clone()).await;
    }
}

/// Close polls whose 48 hours are up, once every quarter of an hour.
///
/// Lives here rather than in `fishers_jobs` because closing a poll announces
/// a result, writes the award to the scorecard and tells two rosters — all of
/// which need `AppState`, and none of which the jobs crate can see.
///
/// Safe to run on every replica. `close_poll` only updates a poll that is
/// still open and hands back nothing when it was already closed, so two pods
/// sweeping the same poll means one announcement and one no-op, not two
/// results posted to the same thread.
pub fn spawn_sweeper(state: AppState) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(900));
        loop {
            interval.tick().await;
            let due = match motm_repo::due_to_close(&state.pool, 50).await {
                Ok(due) => due,
                Err(error) => {
                    warn!(%error, "could not look for votes that have run out of time");
                    continue;
                }
            };
            for poll in due {
                close_and_announce(&state, &poll, None).await;
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use fishers_domain::MotmTallyRow;

    fn row(name: &str, votes: i64) -> MotmTallyRow {
        MotmTallyRow {
            user_id: Uuid::new_v4(),
            display_name: name.into(),
            votes,
        }
    }

    #[test]
    fn a_clear_winner_wins() {
        let tally = vec![row("Stokes", 7), row("Root", 3)];
        let (winner, tied) = decide_winner(&tally);
        assert_eq!(winner, Some(tally[0].user_id));
        assert!(!tied);
    }

    #[test]
    fn one_candidate_with_every_vote_still_wins() {
        let tally = vec![row("Stokes", 4)];
        let (winner, tied) = decide_winner(&tally);
        assert_eq!(winner, Some(tally[0].user_id));
        assert!(!tied);
    }

    /// Two players level at the top is a captain's decision, not the
    /// database's — so nobody is recorded as the winner and the app says so.
    #[test]
    fn a_tie_at_the_top_picks_nobody() {
        let tally = vec![row("Stokes", 5), row("Root", 5), row("Bairstow", 1)];
        let (winner, tied) = decide_winner(&tally);
        assert_eq!(winner, None);
        assert!(tied);
    }

    /// A tie further down the list is not a tie for the award.
    #[test]
    fn a_tie_below_the_winner_is_not_a_tie() {
        let tally = vec![row("Stokes", 9), row("Root", 2), row("Bairstow", 2)];
        let (winner, tied) = decide_winner(&tally);
        assert_eq!(winner, Some(tally[0].user_id));
        assert!(!tied);
    }

    #[test]
    fn nobody_voting_is_no_winner_rather_than_a_tie() {
        let (winner, tied) = decide_winner(&[]);
        assert_eq!(winner, None);
        assert!(!tied);
    }

    /// Both elevens go on the ballot — a man of the match can be the
    /// opposition's opening bowler, and often is.
    #[test]
    fn the_ballot_is_both_team_sheets() {
        let mut state = MatchState::default();
        let home = Uuid::new_v4();
        let away = Uuid::new_v4();
        state.home_xi = vec![home];
        state.away_xi = vec![away];
        state.player_names.insert(home, "Stokes".into());
        state.player_names.insert(away, "Cummins".into());

        let candidates = candidates_from(&state);
        assert_eq!(candidates.len(), 2);
        assert_eq!(candidates[0].display_name, "Stokes");
        assert_eq!(candidates[0].side, "home");
        assert_eq!(candidates[1].display_name, "Cummins");
        assert_eq!(candidates[1].side, "away");
    }

    /// A player somehow on both sheets is one candidate. The ballot's primary
    /// key would reject the second row and take the whole poll with it.
    #[test]
    fn a_player_on_both_sheets_appears_once() {
        let mut state = MatchState::default();
        let both = Uuid::new_v4();
        state.home_xi = vec![both];
        state.away_xi = vec![both];
        state.player_names.insert(both, "Twelfth Man".into());

        let candidates = candidates_from(&state);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].side, "home");
    }

    /// A match scored without either team sheet has nobody to vote for, and
    /// must not open an empty poll.
    #[test]
    fn no_team_sheet_is_no_ballot() {
        assert!(candidates_from(&MatchState::default()).is_empty());
    }
}
