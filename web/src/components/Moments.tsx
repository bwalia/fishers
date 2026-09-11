"use client";

import { useEffect, useRef, useState } from "react";
import { howOut, type MatchState } from "@/lib/cricket";

type Kind = "four" | "six" | "wicket";
type Moment = { key: number; kind: Kind; who: string; detail?: string };

const LASTS: Record<Kind, number> = { four: 1900, six: 2100, wicket: 2500 };
const WORD: Record<Kind, string> = { four: "FOUR", six: "SIX", wicket: "OUT!" };

/// A beat of celebration when the ball that just happened was a four, a six
/// or a wicket — for the scorer, the players watching, and anyone on the
/// shared link.
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
  const before = useRef<MatchState | null>(null);
  const [moment, setMoment] = useState<Moment | null>(null);

  useEffect(() => {
    const prev = before.current;
    before.current = state ?? null;
    if (!state || !prev) return;
    const found = detect(prev, state, nameOf);
    if (found) setMoment({ ...found, key: Date.now() });
  }, [state]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!moment) return;
    const t = setTimeout(() => setMoment(null), LASTS[moment.kind]);
    return () => clearTimeout(t);
  }, [moment]);

  return (
    <>
      {/* Said once, politely, for anyone who cannot see the banner. */}
      <p className="sr-only" aria-live="polite">
        {moment ? `${moment.kind === "wicket" ? "Wicket" : moment.kind === "six" ? "Six" : "Four"} — ${moment.who}` : ""}
      </p>
      {moment && (
        <div className="moment" key={moment.key} aria-hidden="true">
          <div className={`moment-card ${moment.kind}`}>
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
            <span className="moment-word">{WORD[moment.kind]}</span>
            <span className="moment-who">{moment.who}</span>
            {moment.detail && <span className="moment-detail">{moment.detail}</span>}
          </div>
        </div>
      )}
    </>
  );
}

function detect(
  a: MatchState,
  b: MatchState,
  nameOf: (id?: string | null) => string
): Omit<Moment, "key"> | null {
  const now = b.innings[b.innings.length - 1];
  if (!now) return null;
  const then = a.innings.find((i) => i.index === now.index);
  // A new innings, or no new ball (including an undo): nothing to celebrate.
  if (!then || (now.deliveries?.length ?? 0) <= (then.deliveries?.length ?? 0)) return null;

  if (now.wickets > then.wickets) {
    const out = now.batters.find(
      (x) => x.out && !then.batters.find((y) => y.player_id === x.player_id)?.out
    );
    return {
      kind: "wicket",
      who: out ? nameOf(out.player_id) : "Wicket",
      detail: out ? howOut(out, nameOf) : undefined,
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
