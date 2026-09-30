"use client";

import { useEffect, useRef, useState } from "react";
import { howOut, type Batter, type MatchState } from "@/lib/cricket";
import type { Key } from "@/lib/i18n/en";
import { useT } from "@/lib/i18n/provider";

type Kind =
  | "four"
  | "six"
  | "wicket"
  | "golden_duck"
  | "silver_duck"
  | "diamond_duck"
  | "hat_trick";

type Moment = { key: number; kind: Kind; who: string; detail?: string };

/// How long each one holds. The rarer the thing, the longer it is worth
/// looking at — a four happens six times an over, a hat-trick once a season.
const LASTS: Record<Kind, number> = {
  four: 1900,
  six: 2100,
  wicket: 2500,
  golden_duck: 2800,
  silver_duck: 2600,
  diamond_duck: 2800,
  hat_trick: 3600,
};

/// Dismissals that did not happen to a ball being bowled. A batter given out
/// for arriving late has not been dismissed for a duck in any sense a
/// scoreboard should celebrate.
const NOT_A_DUCK = new Set(["timed_out", "retired", "retired_hurt"]);

/// A beat of celebration when the ball that just happened was worth one — and
/// a standing warning while a bowler is on a hat-trick.
///
/// Worked out by comparing the match before and after, never guessed from a
/// run total: a four is the striker's `fours` going up, which a four RUN does
/// not do; a six is `sixes`; a wicket is the innings' count. Only a new ball
/// can set one off — the first load, a new innings and an undo never do.
///
/// A banner under the top bar, so it never covers the run dial, and taps go
/// straight through it. With reduced motion on it is a plain fade.
export function Moments({
  state,
  nameOf,
}: {
  state: MatchState | null | undefined;
  nameOf: (id?: string | null) => string;
}) {
  const t = useT();
  const before = useRef<MatchState | null>(null);
  const [moment, setMoment] = useState<Moment | null>(null);

  useEffect(() => {
    const prev = before.current;
    before.current = state ?? null;
    if (!state || !prev) return;
    const found = detect(prev, state, nameOf, t);
    if (found) setMoment({ ...found, key: Date.now() });
  }, [state]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!moment) return;
    const timer = setTimeout(() => setMoment(null), LASTS[moment.kind]);
    return () => clearTimeout(timer);
  }, [moment]);

  // Anticipation, not celebration: it stands for as long as it is true rather
  // than flashing for two seconds, because the thing it is about has not
  // happened yet and the next ball is when it will.
  const onAHatTrick = hatTrickBall(state);

  return (
    <>
      {/* Said once, politely, for anyone who cannot see the banner. */}
      <p className="sr-only" aria-live="polite">
        {moment ? t(`moment.said.${moment.kind}` as Key, { who: moment.who }) : ""}
      </p>
      {onAHatTrick && (
        <div className="hat-trick-ball" role="status">
          <span className="htb-balls" aria-hidden="true">
            <i />
            <i />
            <i className="htb-next" />
          </span>
          <span className="htb-text">
            <strong>{t("moment.hat_trick_ball")}</strong>
            <span>{t("moment.hat_trick_ball_detail", { bowler: nameOf(onAHatTrick) })}</span>
          </span>
        </div>
      )}
      {moment && (
        <div className="moment" key={moment.key} aria-hidden="true">
          <div className={`moment-card ${moment.kind.replaceAll("_", "-")}`}>
            {moment.kind === "wicket" && <Stumps />}
            {moment.kind === "six" && (
              <>
                <span className="moment-arc">
                  <span className="moment-ball" />
                </span>
                {Array.from({ length: 10 }, (_, i) => (
                  <span key={i} className="moment-spark" style={{ ["--a" as string]: `${i * 36}deg` }} />
                ))}
              </>
            )}
            {moment.kind === "four" && <span className="moment-rope" />}
            {moment.kind.endsWith("duck") && <Duck />}
            {moment.kind === "hat_trick" && (
              <span className="ht-balls" aria-hidden="true">
                <i />
                <i />
                <i />
              </span>
            )}
            <span className="moment-word">{t(`moment.${moment.kind}` as Key)}</span>
            <span className="moment-who">{moment.who}</span>
            {moment.detail && <span className="moment-detail">{moment.detail}</span>}
          </div>
        </div>
      )}
    </>
  );
}

/// The bowler who is on a hat-trick right now, if anyone is.
///
/// Only the bowler with the ball counts. A bowler left on two at the end of
/// their spell is still on a hat-trick in the record books, but the next ball
/// is not theirs and a banner promising one would be wrong.
function hatTrickBall(state: MatchState | null | undefined): string | null {
  const inn = state?.innings[state.innings.length - 1];
  if (!inn || inn.complete || !inn.bowler_id) return null;
  const bowler = inn.bowlers.find((b) => b.player_id === inn.bowler_id);
  return bowler && (bowler.wickets_in_a_row ?? 0) === 2 ? bowler.player_id : null;
}

/// Which duck, if the dismissal was one.
///
/// A duck is nought; which duck is how few balls it took. Balls faced is the
/// striker's count, so a non-striker run out before facing anything is nought
/// off nothing — a diamond duck, and the rarest of the three.
function duckKind(b: Batter): Kind | null {
  if (b.runs !== 0 || NOT_A_DUCK.has(b.dismissal ?? "")) return null;
  if (b.balls === 0) return "diamond_duck";
  if (b.balls === 1) return "golden_duck";
  if (b.balls === 2) return "silver_duck";
  return null;
}

function detect(
  a: MatchState,
  b: MatchState,
  nameOf: (id?: string | null) => string,
  t: ReturnType<typeof useT>
): Omit<Moment, "key"> | null {
  const now = b.innings[b.innings.length - 1];
  if (!now) return null;
  const then = a.innings.find((i) => i.index === now.index);
  // A new innings, or no new ball (including an undo): nothing to celebrate.
  if (!then || (now.deliveries?.length ?? 0) <= (then.deliveries?.length ?? 0)) return null;

  // A hat-trick outranks the wicket that completed it, and outranks a duck:
  // it is the rarest thing on the field, and it belongs to the bowler.
  const trick = now.bowlers.find((x) => {
    const was = then.bowlers.find((y) => y.player_id === x.player_id);
    return (x.wickets_in_a_row ?? 0) >= 3 && (was?.wickets_in_a_row ?? 0) < 3;
  });
  if (trick) {
    return {
      kind: "hat_trick",
      who: nameOf(trick.player_id),
      detail: t("moment.hat_trick_detail"),
    };
  }

  if (now.wickets > then.wickets) {
    const out = now.batters.find(
      (x) => x.out && !then.batters.find((y) => y.player_id === x.player_id)?.out
    );
    if (!out) return { kind: "wicket", who: t("moment.wicket") };
    const duck = duckKind(out);
    return {
      kind: duck ?? "wicket",
      who: nameOf(out.player_id),
      // A duck says how it happened in its own words; a wicket says how they
      // were out, which for a duck is on the card a line below anyway.
      detail: duck ? t(`moment.${duck}_detail` as Key) : howOut(out, nameOf, [], t),
    };
  }

  for (const x of now.batters) {
    const y = then.batters.find((z) => z.player_id === x.player_id);
    if (x.sixes > (y?.sixes ?? 0)) return { kind: "six", who: nameOf(x.player_id) };
    if (x.fours > (y?.fours ?? 0)) return { kind: "four", who: nameOf(x.player_id) };
  }
  return null;
}

/// Three stumps and two bails; the bails are what fly.
function Stumps() {
  return (
    <svg className="moment-stumps" viewBox="0 0 64 72" width="64" height="72">
      <g className="stumps-set">
        <rect x="14" y="16" width="6" height="54" rx="2" />
        <rect x="29" y="16" width="6" height="54" rx="2" />
        <rect x="44" y="16" width="6" height="54" rx="2" />
      </g>
      <rect className="bail bail-l" x="14" y="10" width="21" height="5" rx="2.5" />
      <rect className="bail bail-r" x="29" y="10" width="21" height="5" rx="2.5" />
    </svg>
  );
}

/// The duck itself, side on. A nought is the number; the bird is what the
/// dressing room actually says, in every language this product speaks.
function Duck() {
  return (
    <svg className="moment-duck" viewBox="0 0 72 56" width="72" height="56" aria-hidden="true">
      {/* body and tail */}
      <path
        className="duck-body"
        d="M20 40c-8 0-13-5-13-11 0-7 6-12 15-12 4 0 7 1 10 3l6-9c1-2 4-1 4 1v10c6 3 10 8 10 13 0 3-2 5-5 5Z"
      />
      {/* head, on its own so it can bob */}
      <g className="duck-head">
        <circle cx="47" cy="15" r="8" />
        <path className="duck-beak" d="M55 14h11l-4 5h-7Z" />
        <circle className="duck-eye" cx="49" cy="13" r="1.6" />
      </g>
      {/* the water it sits on */}
      <path className="duck-water" d="M4 44h64" />
    </svg>
  );
}
