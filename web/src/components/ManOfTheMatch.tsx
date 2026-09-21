"use client";

import { useCallback, useEffect, useState } from "react";
import { readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";
import {
  castVote,
  closeVote,
  closingLabel,
  getPoll,
  isOpen,
  sideNames,
  tiedAtTheTop,
  withdrawVote,
  type MotmCandidate,
  type MotmPollView,
} from "@/lib/motm";

/// The man-of-the-match vote, in the thread where it was announced.
///
/// Both team sheets are on the ballot — a man of the match is quite often the
/// opposition's opening bowler — and anybody in either club may vote, whether
/// they played or watched from the boundary. The running total stays hidden
/// until you have voted, so nobody is nudged towards whoever is already ahead.
export function ManOfTheMatch({ pollId }: { pollId: string }) {
  const [poll, setPoll] = useState<MotmPollView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setPoll(await getPoll(pollId));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load the vote"));
    }
  }, [pollId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!poll) {
    return (
      <article className="motm" aria-busy={!error}>
        {error ? <p className="error">{error}</p> : <div className="skeleton" style={{ height: 80 }} />}
      </article>
    );
  }

  const open = isOpen(poll);
  const tied = tiedAtTheTop(poll);
  const winner = poll.candidates.find((c) => c.user_id === poll.winner_user_id);
  const names = sideNames(poll);

  /// Clicking the person you already voted for takes the vote back, so a
  /// mis-click is undone by the same click that made it.
  const vote = async (candidate: MotmCandidate) => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      setPoll(
        poll.my_vote === candidate.user_id
          ? await withdrawVote(pollId)
          : await castVote(pollId, candidate.user_id)
      );
    } catch (err) {
      setError(readErr(err, "Could not record that vote"));
    } finally {
      setBusy(false);
    }
  };

  const end = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      setPoll(await closeVote(pollId));
    } catch (err) {
      setError(readErr(err, "Could not close the vote"));
    } finally {
      setBusy(false);
    }
  };

  const sheet = (side: string, label: string) => {
    const players = poll.candidates.filter((c) => c.side === side);
    if (players.length === 0) return null;
    return (
      <div className="motm-sheet">
        <p className="motm-sheet-name">{label}</p>
        <ul>
          {players.map((player) => (
            <li key={player.user_id}>
              <button
                type="button"
                className={`motm-pick${poll.my_vote === player.user_id ? " chosen" : ""}`}
                disabled={!poll.can_vote || busy}
                aria-pressed={poll.my_vote === player.user_id}
                onClick={() => void vote(player)}
              >
                {/* The empty span holds the tick's place, so choosing
                    somebody does not shuffle every name along by 14px. */}
                <span className="motm-tick" aria-hidden="true">
                  {poll.my_vote === player.user_id && <Icon name="check" size={14} />}
                </span>
                <span>{player.display_name}</span>
                {player.user_id === poll.scorer_award_user_id && (
                  // The scorer's own award, shown so the two are never
                  // mistaken for each other.
                  <span className="tag grey" title="The scorer's pick">
                    Scorer
                  </span>
                )}
                {poll.tally_visible && <span className="motm-count">{player.votes}</span>}
              </button>
            </li>
          ))}
        </ul>
      </div>
    );
  };

  return (
    <article className="motm">
      <header className="motm-top">
        <Icon name="trophy" size={16} />
        <div>
          <h3>Man of the match</h3>
          <p className="subtle">{poll.title}</p>
        </div>
        <span className={`tag ${open ? "gold" : "grey"}`}>
          {open ? closingLabel(poll.closes_at) : "Closed"}
        </span>
      </header>

      {open ? (
        <>
          <p className="subtle">
            {!poll.can_vote
              ? "Only the two clubs who played can vote."
              : poll.my_vote
                ? "Your vote is in. Pick another name to change it, or the same one to take it back."
                : "Who was your man of the match? Pick a name — you can change it until voting closes."}
          </p>
          <div className="motm-sheets">
            {sheet("home", names.home)}
            {sheet("away", names.away)}
          </div>
          <p className="subtle sm">
            {poll.tally_visible
              ? `${poll.total_votes} vote${poll.total_votes === 1 ? "" : "s"} so far.`
              : "Votes are hidden until you have voted."}
          </p>
          {/* Offered to everybody: most people get a 403, which is shown as
              the sentence the API sent rather than hidden behind a guess at
              their role. */}
          <button className="btn ghost sm" type="button" disabled={busy} onClick={() => void end()}>
            Close the vote now
          </button>
        </>
      ) : winner ? (
        <p className="motm-winner">
          <Icon name="trophy" size={16} /> <strong>{winner.display_name}</strong> —{" "}
          {winner.votes} of {poll.total_votes} vote{poll.total_votes === 1 ? "" : "s"}
        </p>
      ) : tied.length > 0 ? (
        <p className="motm-winner">
          A tie: {tied.map((c) => c.display_name).join(", ")} finished level. A captain picks.
        </p>
      ) : (
        <p className="subtle">Voting closed with nobody voted for.</p>
      )}

      {!open && poll.total_votes > 0 && (
        <details className="motm-all">
          <summary>
            All {poll.total_votes} vote{poll.total_votes === 1 ? "" : "s"}
          </summary>
          <ul>
            {poll.candidates
              .filter((c) => c.votes > 0)
              .map((c) => (
                <li key={c.user_id}>
                  <span>{c.display_name}</span>
                  <span className="motm-count">{c.votes}</span>
                </li>
              ))}
          </ul>
        </details>
      )}

      {error && <p className="error">{error}</p>}
    </article>
  );
}

/// The vote a message opened, if it opened one.
///
/// Only the message that *opened* the vote draws a card. The server also
/// posts the result when voting closes, and that message carries the same
/// poll id — but the card already shows the result, so honouring both would
/// put two identical cards in the thread.
export function motmPollId(metadata: Record<string, unknown> | null | undefined): string | null {
  if (!metadata || metadata.kind !== "motm_poll") return null;
  const id = metadata.motm_poll_id;
  return typeof id === "string" ? id : null;
}
