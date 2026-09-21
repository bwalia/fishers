/// The club's man-of-the-match vote (`backend/domain/src/motm.rs`).
///
/// Distinct from the scorer's award, which one person gives from the scoring
/// screen. This one opens on its own when the game ends and everybody in
/// either club votes in it — including the people who watched rather than
/// played, which on most Saturdays is most of the club.

import { api } from "@/lib/api";

export type MotmCandidate = {
  user_id: string;
  display_name: string;
  /// `home` | `away`
  side: string;
  /// Zero for everybody until `tally_visible`.
  votes: number;
};

/// The poll's own fields are flattened into the same object by the API, so
/// this is one type rather than a poll nested inside a view.
export type MotmPollView = {
  id: string;
  club_id: string;
  event_id: string;
  match_id: string | null;
  conversation_id: string | null;
  message_id: string | null;
  title: string;
  /// The match result as it stood when the card went up. A later completion —
  /// a super over settling a tie — moves it, and the thread is told.
  result: string | null;
  /// `open` | `closed`
  status: string;
  closes_at: string;
  winner_user_id: string | null;
  created_at: string;
  closed_at: string | null;
  candidates: MotmCandidate[];
  my_vote: string | null;
  total_votes: number;
  /// False until you have voted, so a running tally cannot nudge you towards
  /// whoever is already ahead.
  tally_visible: boolean;
  can_vote: boolean;
  /// The scorer's own award, when one was given.
  scorer_award_user_id: string | null;
};

/// The server decides whether a vote counts; this is only for the label. A
/// poll past its closing time is over whether or not the sweeper has been
/// round yet.
export function isOpen(poll: MotmPollView): boolean {
  return poll.status === "open" && Date.parse(poll.closes_at) > Date.now();
}

/// Everybody level at the top of a closed vote with no winner — which is how
/// a tie is recorded, because a captain picks between them.
export function tiedAtTheTop(poll: MotmPollView): MotmCandidate[] {
  if (isOpen(poll) || poll.winner_user_id || !poll.tally_visible) return [];
  const best = Math.max(0, ...poll.candidates.map((c) => c.votes));
  return best > 0 ? poll.candidates.filter((c) => c.votes === best) : [];
}

/// "Hemel Hempstead" and "Chesham" out of "Hemel Hempstead vs Chesham",
/// falling back to Home and Away for a fixture titled some other way.
export function sideNames(poll: MotmPollView): { home: string; away: string } {
  for (const separator of [" vs ", " v ", " V "]) {
    const parts = poll.title.split(separator);
    if (parts.length === 2) return { home: parts[0], away: parts[1] };
  }
  return { home: "Home", away: "Away" };
}

export function closingLabel(closesAt: string): string {
  const remaining = Date.parse(closesAt) - Date.now();
  if (remaining <= 0) return "Closing";
  if (remaining < 3_600_000) return `${Math.max(1, Math.round(remaining / 60_000))}m left`;
  if (remaining < 86_400_000) return `${Math.floor(remaining / 3_600_000)}h left`;
  return `${Math.floor(remaining / 86_400_000)}d left`;
}

export const getPoll = (id: string) => api<MotmPollView>("GET", `/motm/polls/${id}`);

export const castVote = (id: string, candidate: string) =>
  api<MotmPollView>("POST", `/motm/polls/${id}/vote`, { candidate_user_id: candidate });

export const withdrawVote = (id: string) =>
  api<MotmPollView>("DELETE", `/motm/polls/${id}/vote`);

export const closeVote = (id: string) =>
  api<MotmPollView>("POST", `/motm/polls/${id}/close`, {});
