"use client";

import { useCallback, useEffect, useState } from "react";
import { isForbidden, readErr } from "@/lib/api";
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
import { useT } from "@/lib/i18n/provider";

/// The man-of-the-match vote, in the thread where it was announced.
///
/// Both team sheets are on the ballot — a man of the match is quite often the
/// opposition's opening bowler — and anybody in either club may vote, whether
/// they played or watched from the boundary. The running total stays hidden
/// until you have voted, so nobody is nudged towards whoever is already ahead.
export function ManOfTheMatch({ pollId }: { pollId: string }) {
  const t = useT();
  const [poll, setPoll] = useState<MotmPollView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setPoll(await getPoll(pollId));
      setError(null);
    } catch (err) {
      setError(readErr(err, t("le.could_not_load_the_vote")));
    }
  }, [pollId, t]);

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
      setError(readErr(err, t("le.could_not_record_that_vote")));
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
      // Most of a club cannot close a vote, so a refusal is ordinary and is
      // said plainly. The shared RBAC error answers with the permission's own
      // name ("cannot manage_events") — the right sentence for an API and the
      // wrong one for a card every member is going to click once.
      setError(
        isForbidden(err)
          ? t("le.only_a_captain_or_club_secretary_can_c")
          : readErr(err, t("le.could_not_close_the_vote"))
      );
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
                  <span className="tag grey" title={t("sr.the_scorer_s_pick")}>
                    {t("sr.scorer")}
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
          <h3>{t("sr.man_of_the_match")}</h3>
          <p className="subtle">{poll.title}</p>
        </div>
        <span className={`tag ${open ? "gold" : "grey"}`}>
          {open ? closingLabel(poll.closes_at) : t("le.closed")}
        </span>
      </header>

      {open ? (
        <>
          <p className="subtle">
            {!poll.can_vote
              ? t("le.only_the_two_clubs_who_played_can_vote")
              : poll.my_vote
                ? t("le.your_vote_is_in_pick_another_name_to_c")
                : t("le.who_was_your_man_of_the_match_pick_a_n")}
          </p>
          <div className="motm-sheets">
            {sheet("home", names.home)}
            {sheet("away", names.away)}
          </div>
          <p className="subtle sm">
            {poll.tally_visible
              ? `${poll.total_votes} vote${poll.total_votes === 1 ? "" : "s"} so far.`
              : t("le.votes_are_hidden_until_you_have_voted")}
          </p>
          {/* Offered to everybody: most people get a 403, which is shown as
              the sentence the API sent rather than hidden behind a guess at
              their role. */}
          <button className="btn ghost sm" type="button" disabled={busy} onClick={() => void end()}>
            {t("sr.close_the_vote_now")}
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
        <p className="subtle">{t("sr.voting_closed_with_nobody_voted_for")}</p>
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
