"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import { apiV1 } from "@/lib/api";
import { WagonWheel } from "@/components/WagonWheel";
import {
  commentaryFor,
  overs,
  type Innings,
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

export default function LiveScoreboardPage({
  params,
}: {
  // Next.js 15 hands route params to a client component as a promise.
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
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
    const id = window.setInterval(() => void load(), 5000);
    return () => window.clearInterval(id);
  }, [load]);

  const current = useMemo(() => board?.state.innings.at(-1) ?? null, [board]);

  return (
    <main className="shell live-board">
      <header className="live-hero">
        <p className="tag">Live scoreboard</p>
        <h1>Fishers</h1>
        <p className="muted">
          Secure match link — refreshes every few seconds. No sign-in required.
        </p>
      </header>

      {loading && !board && <p className="muted">Loading live score…</p>}
      {error && !board && (
        <div className="panel">
          <h2>Link unavailable</h2>
          <p className="error">{error}</p>
          <p className="muted">
            Ask the scorer to share a fresh scoreboard link in chat.
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

          {board.state.player_of_the_match && (
            <p className="tag">
              Player of the match: {nameOf(board, board.state.player_of_the_match)}
            </p>
          )}
          {board.state.innings.map((inn) => (
            <section key={inn.index} className="panel">
              <h2>
                {inn.super_over ? "Super over" : `Innings ${inn.index + 1}`} ·{" "}
                {inn.runs}/{inn.wickets} ({overs(inn.legal_balls)})
              </h2>
              {inn.free_hit && <p className="tag">Free hit</p>}
              <h3>Batting</h3>
              <div className="table-wrap"><table className="score-table">
                <thead>
                  <tr>
                    <th>Batter</th>
                    <th>R</th>
                    <th>B</th>
                    <th>4s</th>
                    <th>6s</th>
                  </tr>
                </thead>
                <tbody>
                  {inn.batters
                    .filter(
                      (b) =>
                        b.balls > 0 ||
                        b.out ||
                        b.player_id === inn.striker_id ||
                        b.player_id === inn.non_striker_id,
                    )
                    .map((b) => (
                      <tr key={b.player_id}>
                        <td>
                          {nameOf(board, b.player_id)}
                          {b.out ? "" : " *"}
                        </td>
                        <td>{b.runs}</td>
                        <td>{b.balls}</td>
                        <td>{b.fours}</td>
                        <td>{b.sixes}</td>
                      </tr>
                    ))}
                </tbody>
              </table></div>
              <h3>Bowling</h3>
              <div className="table-wrap"><table className="score-table">
                <thead>
                  <tr>
                    <th>Bowler</th>
                    <th>O</th>
                    <th>M</th>
                    <th>R</th>
                    <th>W</th>
                  </tr>
                </thead>
                <tbody>
                  {inn.bowlers.map((b) => (
                    <tr key={b.player_id}>
                      <td>{nameOf(board, b.player_id)}</td>
                      <td>{overs(b.balls)}</td>
                      <td>{b.maidens}</td>
                      <td>{b.runs}</td>
                      <td>{b.wickets}</td>
                    </tr>
                  ))}
                </tbody>
              </table></div>
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
                            {commentaryFor(ball, (id) => nameOf(board, id), board.state.left_handers || [])}
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
