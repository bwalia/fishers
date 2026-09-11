"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import { apiV1 } from "@/lib/api";
import { watchScoreboard } from "@/lib/live";
import { WagonWheel } from "@/components/WagonWheel";
import { Scorecard } from "@/components/Scorecard";
import { ReshareLiveLink } from "@/components/ReshareLiveLink";
import {
  commentaryFor,
  overs,
  type MatchConditions,
  type MatchState,
} from "@/lib/cricket";

type PublicScoreboard = {
  match_id: string;
  event_id: string;
  club_id: string;
  club_name?: string | null;
  home_name: string;
  away_name: string;
  status: string;
  overs_limit: number;
  last_seq: number;
  player_names: Record<string, string>;
  conditions?: MatchConditions;
  dls?: {
    par: number;
    ahead_by: number;
    target: number;
    method: string;
  };
  expires_at: string;
  refreshed_at: string;
  state: MatchState;
};

function ballClass(ball: { runs: number; is_wicket: boolean }) {
  if (ball.is_wicket) return "wicket";
  if (ball.runs >= 6) return "six";
  if (ball.runs >= 4) return "boundary";
  return undefined;
}

function nameOf(board: PublicScoreboard, id?: string | null) {
  if (!id) return "—";
  return board.player_names[id] || id.slice(0, 8);
}

/// A share token is hex; anything from the first non-hex character on was
/// never part of it. See `clean_token` in the API, which does the same.
function cleanToken(segment: string): string {
  return /^[0-9a-f]*/i.exec(segment)?.[0] ?? "";
}

export default function LiveScoreboardPage({
  params,
}: {
  // Next.js 15 hands route params to a client component as a promise. This is
  // a catch-all so that a link with the share message stuck to it — which
  // splits across several segments — still lands here rather than on a 404.
  params: Promise<{ token: string[] }>;
}) {
  const raw = use(params).token;
  const token = cleanToken(raw[0] ?? "");

  // Put the honest address in the bar, so a bookmark, a re-share and a copy
  // all carry the link rather than the wreckage of one.
  useEffect(() => {
    if (token && raw.join("/") !== token) {
      window.history.replaceState(null, "", `/live/${token}`);
    }
  }, [token, raw]);
  const [board, setBoard] = useState<PublicScoreboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await fetch(`${apiV1()}/public/scoreboard/${token}`, {
        cache: "no-store",
      });
      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || `HTTP ${res.status}`);
      }
      const data = (await res.json()) as PublicScoreboard;
      setBoard(data);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load scoreboard");
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    void load();
    // Live, ball by ball: the link's own stream says when the match changed.
    // No sign-in — the link is the permission, and it hears about this match
    // only. The slow poll is a safety net for when the stream is down.
    const stop = watchScoreboard(token, (e) => {
      if (e.type === "match" || e.type === "resync") void load();
    });
    const id = window.setInterval(() => void load(), 60_000);
    return () => {
      stop();
      window.clearInterval(id);
    };
  }, [load, token]);

  const current = useMemo(() => board?.state.innings.at(-1) ?? null, [board]);

  const fullState: MatchState | null = useMemo(() => {
    if (!board) return null;
    return {
      ...board.state,
      home_name: board.state.home_name || board.home_name,
      away_name: board.state.away_name || board.away_name,
    };
  }, [board]);

  return (
    <main id="main" className="shell live-board">
      <header className="live-hero">
        <p className="tag">Live scoreboard</p>
        <h1>Fishers</h1>
        <p className="muted">
          Full match scoreboard — updates live, ball by ball. No sign-in required.
        </p>
      </header>

      {loading && !board && <p className="muted">Loading live score…</p>}
      {error && !board && (
        <div className="panel">
          <h2>Link unavailable</h2>
          <p className="error">{error}</p>
          <p className="muted">
            Ask the scorer to share a fresh scoreboard link.
          </p>
        </div>
      )}

      {board && (
        <>
          <section className="panel score-panel">
            <div className="select-row">
              <span className="tag">{board.status}</span>
              {board.club_name && <span className="muted">{board.club_name}</span>}
            </div>
            <h2>
              {board.home_name} <span className="muted">vs</span> {board.away_name}
            </h2>
            {current ? (
              <p className="scoreline">
                {current.runs}/{current.wickets}{" "}
                <span className="muted">({overs(current.legal_balls)} ov)</span>
              </p>
            ) : (
              <p className="scoreline muted">Waiting for first ball…</p>
            )}
            {board.state.target != null && (
              <p className="muted">Target {board.state.target}</p>
            )}
            {board.state.margin && <p>{board.state.margin}</p>}
            {board.dls && (
              <p className={board.dls.ahead_by >= 0 ? "tag" : "muted"}>
                {board.dls.ahead_by === 0
                  ? `Level with the DLS par of ${board.dls.par}`
                  : board.dls.ahead_by > 0
                    ? `${board.dls.ahead_by} ahead of the DLS par of ${board.dls.par}`
                    : `${-board.dls.ahead_by} behind the DLS par of ${board.dls.par}`}
                {" · "}
                <span className="muted">
                  target {board.dls.target}
                  {board.dls.method === "standard_approximation"
                    ? " (Standard Edition approximation)"
                    : ""}
                </span>
              </p>
            )}
            {board.conditions && (
              <p className="muted">
                {board.conditions.overs_limit} overs ·{" "}
                {board.conditions.overs_per_bowler > 0
                  ? `${board.conditions.overs_per_bowler} per bowler`
                  : "no bowler limit"}{" "}
                · {board.conditions.ball} ball · {board.conditions.ground}
              </p>
            )}
            {current && (
              <div className="live-pair">
                <div>
                  <strong>{nameOf(board, current.striker_id)}</strong>
                  <span className="muted"> striker</span>
                </div>
                <div>
                  <strong>{nameOf(board, current.non_striker_id)}</strong>
                  <span className="muted"> non-striker</span>
                </div>
                <div>
                  <strong>{nameOf(board, current.bowler_id)}</strong>
                  <span className="muted"> bowling</span>
                </div>
              </div>
            )}
            <p className="muted" style={{ fontSize: "0.8rem", marginTop: 12 }}>
              Updated {new Date(board.refreshed_at).toLocaleTimeString()} · link
              expires {new Date(board.expires_at).toLocaleString()}
            </p>
            {error && <p className="muted">Refresh issue: {error}</p>}
          </section>

          <ReshareLiveLink homeName={board.home_name} awayName={board.away_name} />

          {board.state.player_of_the_match && (
            <p className="tag">
              Player of the match: {nameOf(board, board.state.player_of_the_match)}
            </p>
          )}

          {fullState && (
            <Scorecard st={fullState} nameOf={(id) => nameOf(board, id)} />
          )}

          {board.state.innings.map((inn) => (
            <section key={inn.index} className="panel">
              <h2>
                {inn.super_over ? "Super over" : `Innings ${inn.index + 1}`} · wagon
                wheel &amp; commentary
              </h2>
              {inn.free_hit && <p className="tag">Free hit</p>}
              <h3>Wagon wheel</h3>
              <WagonWheel deliveries={inn.deliveries || []} />

              {(inn.deliveries || []).length > 0 && (
                <>
                  <h3>Commentary</h3>
                  <ul className="commentary">
                    {(inn.deliveries || [])
                      .slice(-40)
                      .reverse()
                      .map((ball, index) => (
                        <li key={index} className={ballClass(ball)}>
                          <span className="ball">
                            {ball.over}.{ball.ball_in_over}
                          </span>
                          <span>
                            {commentaryFor(
                              ball,
                              (id) => nameOf(board, id),
                              board.state.left_handers || []
                            )}
                          </span>
                        </li>
                      ))}
                  </ul>
                </>
              )}
            </section>
          ))}
        </>
      )}
    </main>
  );
}
