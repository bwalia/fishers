"use client";

import { useCallback, useEffect, useState } from "react";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import {
  matchUmpires,
  pendingUmpireReviews,
  reviewUmpire,
  withdrawReview,
  type MatchUmpire,
} from "@/lib/umpire";
import { useT } from "@/lib/i18n/provider";

/// After the match: say how the umpiring went.
///
/// Shown on a finished match to the people who were in it. The API decides
/// who that is — this only stops asking when there is nobody to ask about.
///
/// It opens with whatever the player said last time rather than blank, because
/// the common reason to come back is to change a three to a four, not to
/// discover you have already voted.
export function RateUmpires({ matchId }: { matchId: string }) {
  const t = useT();
  const [umpires, setUmpires] = useState<MatchUmpire[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setUmpires(await matchUmpires(matchId));
    } catch (err) {
      setError(readErr(err, t("le.could_not_load_the_umpires")));
    }
  }, [matchId, t]);

  useEffect(() => {
    load();
  }, [load]);

  if (error) return <p className="error">{error}</p>;
  // No umpire was named, so there is nothing to ask about. Saying "no umpires
  // to rate" would be noise on every match a club scores without naming one.
  if (!umpires || umpires.length === 0) return null;

  return (
    <section className="panel ump-rate" aria-labelledby="ump-rate-h">
      <h2 id="ump-rate-h">
        <Icon name="shield" size={18} /> {t("sr.how_was_the_umpiring")}
      </h2>
      <p className="muted">
        {t("sr.it_goes_on_their_profile_with_your_nam")}
      </p>
      <ul className="ump-rate-list">
        {umpires.map((u) => (
          <li key={u.user_id}>
            <One matchId={matchId} umpire={u} onDone={load} />
          </li>
        ))}
      </ul>
    </section>
  );
}

function One({
  matchId,
  umpire,
  onDone,
}: {
  matchId: string;
  umpire: MatchUmpire;
  onDone: () => void;
}) {
  const t = useT();
  const [rating, setRating] = useState(umpire.my_rating ?? 0);
  const [comment, setComment] = useState(umpire.my_comment ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const submit = async () => {
    if (rating < 1) return setError(t("le.pick_one_to_five_stars_first"));
    setBusy(true);
    setError(null);
    try {
      await reviewUmpire(matchId, umpire.user_id, { rating, comment: comment.trim() || null });
      setSaved(true);
      onDone();
    } catch (err) {
      setError(readErr(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    setError(null);
    try {
      await withdrawReview(matchId, umpire.user_id);
      setRating(0);
      setComment("");
      setSaved(false);
      onDone();
    } catch (err) {
      setError(readErr(err, t("le.could_not_remove_that")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="ump-rate-one">
      <div className="ump-rate-who">
        <strong>{umpire.name}</strong>
        {umpire.my_rating !== null && !saved && <span className="tag">{t("sr.your_review")}</span>}
        {saved && <span className="tag live">{t("sr.saved")}</span>}
      </div>

      <fieldset className="ump-picker">
        <legend className="sr-only">Rate {umpire.name} from 1 to 5</legend>
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            className={n <= rating ? "on" : ""}
            aria-pressed={n <= rating}
            aria-label={`${n} out of 5`}
            disabled={busy}
            onClick={() => {
              setRating(n);
              setSaved(false);
            }}
          >
            <svg width="24" height="24" viewBox="0 0 20 20" aria-hidden="true">
              <path d="M10 1.6l2.5 5.3 5.6.8-4.1 4 1 5.7L10 14.7 4.9 17.4l1-5.7-4.1-4 5.6-.8z" />
            </svg>
          </button>
        ))}
        <span className="muted ump-picker-n">{rating > 0 ? `${rating} / 5` : t("le.not_rated")}</span>
      </fieldset>

      <label className="sr-only" htmlFor={`ump-c-${umpire.user_id}`}>
        Anything to add about {umpire.name}&apos;s umpiring
      </label>
      <textarea
        id={`ump-c-${umpire.user_id}`}
        rows={2}
        maxLength={1000}
        placeholder={t("sr.gave_everything_explained_the_wides")}
        value={comment}
        disabled={busy}
        onChange={(e) => {
          setComment(e.target.value);
          setSaved(false);
        }}
      />

      <div className="ump-rate-actions">
        <button type="button" className="btn primary" onClick={submit} disabled={busy}>
          {busy ? "Saving…" : umpire.my_rating !== null ? t("le.update") : t("le.submit")}
        </button>
        {umpire.my_rating !== null && (
          <button type="button" className="btn" onClick={remove} disabled={busy}>
            {t("sr.remove")}
          </button>
        )}
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}

/// The matches waiting on this player's say, wherever they happen to be.
///
/// The prompt at the end of a match only reaches whoever had that page open.
/// This is the one that finds everybody else — on their own profile, where
/// they can clear three Sundays in a row.
export function PendingUmpireReviews() {
  const t = useT();
  const [pending, setPending] = useState<
    { match_id: string; match_title: string; umpires: MatchUmpire[] }[]
  >([]);

  const load = useCallback(async () => {
    try {
      setPending(await pendingUmpireReviews());
    } catch {
      // A profile that cannot load this is a profile, not an error page.
      setPending([]);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (pending.length === 0) return null;

  return (
    <section className="panel ump-rate" aria-labelledby="ump-pending-h">
      <h2 id="ump-pending-h">
        <Icon name="shield" size={18} /> {t("sr.waiting_on_you")}
      </h2>
      <p className="muted">
        {t("sr.you_played_in_these_say_how_the_umpiri")}
      </p>
      <ul className="ump-rate-list">
        {pending.map((match) => (
          <li key={match.match_id}>
            <p className="ump-rate-match">{match.match_title}</p>
            {match.umpires.map((u) => (
              <One key={u.user_id} matchId={match.match_id} umpire={u} onDone={load} />
            ))}
          </li>
        ))}
      </ul>
    </section>
  );
}
