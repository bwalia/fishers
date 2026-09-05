"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { API_V1 } from "@/lib/api";

type Batter = {
  player_id: string;
  runs: number;
  balls: number;
  fours: number;
  sixes: number;
  out: boolean;
};

type Bowler = {
  player_id: string;
  balls: number;
  runs: number;
  wickets: number;
  maidens: number;
};

type Innings = {
  index: number;
  batting: string;
  runs: number;
  wickets: number;
  legal_balls: number;
  extras: number;
  complete: boolean;
  striker_id?: string | null;
  non_striker_id?: string | null;
  bowler_id?: string | null;
  batters: Batter[];
  bowlers: Bowler[];
};

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
  expires_at: string;
  refreshed_at: string;
  state: {
    status: string;
    overs_limit: number;
    home_name: string;
    away_name: string;
    target?: number | null;
    margin?: string | null;
    innings: Innings[];
  };
};

function overs(balls: number) {
  return `${Math.floor(balls / 6)}.${balls % 6}`;
}

function nameOf(board: PublicScoreboard, id?: string | null) {
  if (!id) return "—";
  return board.player_names[id] || id.slice(0, 8);
}

export default function LiveScoreboardPage({
  params,
}: {
  params: { token: string };
}) {
  const token = params.token;
  const [board, setBoard] = useState<PublicScoreboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await fetch(`${API_V1}/public/scoreboard/${token}`, {
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

          {board.state.innings.map((inn) => (
            <section key={inn.index} className="panel">
              <h2>
                Innings {inn.index + 1} · {inn.runs}/{inn.wickets} (
                {overs(inn.legal_balls)})
              </h2>
              <h3>Batting</h3>
              <table className="score-table">
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
                  {inn.batters.map((b) => (
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
              </table>
              <h3>Bowling</h3>
              <table className="score-table">
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
              </table>
            </section>
          ))}
        </>
      )}
    </main>
  );
}
