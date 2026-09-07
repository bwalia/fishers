"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
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
  super_over?: boolean;
  powerplay_overs?: number;
  free_hit?: boolean;
  deliveries?: Delivery[];
};

type Shot = {
  angle: number;
  kind: string;
  reach: number;
};

type Delivery = {
  over: number;
  ball_in_over: number;
  label: string;
  runs: number;
  is_legal: boolean;
  is_wicket: boolean;
  batter_id?: string | null;
  bowler_id?: string | null;
  shot?: Shot | null;
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
  conditions?: {
    overs_limit: number;
    overs_per_bowler: number;
    ground: string;
    ball: string;
    powerplay_overs?: number;
  };
  dls?: {
    par: number;
    ahead_by: number;
    target: number;
    method: string;
  };
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
    left_handers?: string[];
    player_of_the_match?: string | null;
    super_overs?: number;
  };
};

/// The eight sectors of a wagon wheel, mirrored for a left-hander — the same
/// function the app and the API use.
function regionFor(angle: number, batsLeft: boolean) {
  const raw = ((angle % 360) + 360) % 360;
  const a = batsLeft ? (360 - raw) % 360 : raw;
  if (a <= 44) return "long on";
  if (a <= 89) return "mid-wicket";
  if (a <= 134) return "square leg";
  if (a <= 179) return "fine leg";
  if (a <= 224) return "third man";
  if (a <= 269) return "point";
  if (a <= 314) return "cover";
  return "long off";
}

const SHOT_VERBS: Record<string, string> = {
  drive: "driven",
  cut: "cut",
  pull: "pulled",
  hook: "hooked",
  sweep: "swept",
  reverse_sweep: "reverse-swept",
  glance: "glanced",
  flick: "flicked",
  loft: "lofted",
  defence: "defended",
  edge: "edged",
  leave: "left alone",
  other: "worked away",
};

function outcomeOf(ball: Delivery) {
  if (ball.is_wicket) return ball.runs > 0 ? `OUT (${ball.runs} run)` : "OUT";
  if (!ball.is_legal) {
    if (ball.label.startsWith("wd")) return ball.runs > 1 ? `wide, ${ball.runs} runs` : "wide";
    if (ball.label.startsWith("nb")) return ball.runs > 1 ? `no ball, ${ball.runs} runs` : "no ball";
    if (ball.label.endsWith("p")) return `${ball.runs} penalty runs`;
    return ball.label;
  }
  if (ball.label.endsWith("lb")) return `${ball.runs} leg byes`;
  if (ball.label.endsWith("b")) return `${ball.runs} byes`;
  if (ball.runs === 0) return "no run";
  if (ball.runs === 4) return "FOUR";
  if (ball.runs === 6) return "SIX";
  return `${ball.runs} run${ball.runs === 1 ? "" : "s"}`;
}

/// The same line the app writes, generated from the same log.
function commentaryFor(board: PublicScoreboard, ball: Delivery) {
  const bowler = ball.bowler_id ? nameOf(board, ball.bowler_id) : null;
  const batter = ball.batter_id ? nameOf(board, ball.batter_id) : null;
  const parts: string[] = [];
  if (bowler && batter) parts.push(`${bowler} to ${batter},`);
  else if (batter) parts.push(`${batter},`);
  parts.push(outcomeOf(ball));
  if (ball.shot) {
    const left = (board.state.left_handers || []).includes(
      (ball.batter_id || "").toLowerCase()
    );
    const region = regionFor(ball.shot.angle, left);
    const verb = SHOT_VERBS[ball.shot.kind] || "played";
    if (ball.shot.kind === "leave" || ball.shot.kind === "defence") {
      parts.push(`— ${verb}`);
    } else {
      const preposition =
        region === "long on" || region === "long off"
          ? "down the ground to"
          : region === "fine leg" || region === "third man"
            ? "down to"
            : "through";
      parts.push(`— ${verb} ${preposition} ${region}`);
    }
  }
  return parts.join(" ");
}

/// Every plotted shot in one innings, drawn as lines from the middle.
function WagonWheel({
  board,
  innings,
}: {
  board: PublicScoreboard;
  innings: Innings;
}) {
  const shots = (innings.deliveries || []).filter((d) => d.shot);
  const size = 260;
  const centre = size / 2;
  const radius = size / 2 - 6;

  if (shots.length === 0) {
    return <p className="muted">No shots plotted for this innings.</p>;
  }

  const colour = (ball: Delivery) =>
    ball.runs >= 6 ? "#c62828" : ball.runs >= 4 ? "#1b7f4c" : "#8a8f98";

  return (
    <div>
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        role="img"
        aria-label={`Wagon wheel: ${shots.length} shots, ${
          shots.filter((s) => s.runs >= 4).length
        } boundaries`}
      >
        <circle cx={centre} cy={centre} r={radius} fill="#1b7f4c11" stroke="#1b7f4c55" />
        <circle
          cx={centre}
          cy={centre}
          r={radius * 0.55}
          fill="none"
          stroke="#1b7f4c33"
          strokeDasharray="4 4"
        />
        <rect
          x={centre - size * 0.035}
          y={centre - size * 0.14}
          width={size * 0.07}
          height={size * 0.28}
          rx={2}
          fill="#d8a13a55"
        />
        {shots.map((ball, index) => {
          const shot = ball.shot!;
          const radians = ((shot.angle - 90) * Math.PI) / 180;
          const length = radius * Math.max(0.15, shot.reach ?? 0.6);
          return (
            <line
              key={index}
              x1={centre}
              y1={centre}
              x2={centre + length * Math.cos(radians)}
              y2={centre + length * Math.sin(radians)}
              stroke={colour(ball)}
              strokeWidth={2}
              strokeLinecap="round"
            />
          );
        })}
      </svg>
      <p className="muted" style={{ fontSize: "0.8rem" }}>
        {shots.length} shots plotted · {shots.filter((s) => s.runs >= 4).length}{" "}
        boundaries
      </p>
    </div>
  );
}

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
  // Next.js 15 hands route params to a client component as a promise.
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
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
              <h3>Wagon wheel</h3>
              <WagonWheel board={board} innings={inn} />

              {(inn.deliveries || []).length > 0 && (
                <>
                  <h3>Commentary</h3>
                  <ul className="commentary">
                    {(inn.deliveries || [])
                      .slice(-40)
                      .reverse()
                      .map((ball, index) => (
                        <li key={index}>
                          <span className="muted">
                            {ball.over}.{ball.ball_in_over}
                          </span>{" "}
                          {commentaryFor(board, ball)}
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
