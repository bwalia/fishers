"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  api,
  getAccessToken,
  type Club,
} from "@/lib/api";

type SeasonRow = {
  id: string;
  season_year: number;
  matches: number;
  runs: number;
  wickets: number;
  high_score?: number | null;
  club_name?: string | null;
  player_name?: string | null;
  batting_average?: number | null;
  bowling_average?: number | null;
  play_cricket_profile_url?: string | null;
};

type Achievement = {
  id: string;
  title: string;
  description?: string | null;
  icon?: string | null;
  season_year?: number | null;
  achievement_code: string;
};

type MeStats = {
  seasons: SeasonRow[];
  achievements: Achievement[];
  links: { profile_url?: string | null; display_name?: string | null }[];
};

type ClubBoard = {
  club: {
    season_year: number;
    matches_played: number;
    wins: number;
    losses: number;
    draws: number;
    runs_for: number;
    runs_against: number;
    wickets_taken: number;
  };
  play_cricket?: {
    site_id: string;
    site_name?: string | null;
    public_url?: string | null;
  } | null;
  top_batters: SeasonRow[];
  top_bowlers: SeasonRow[];
};

export default function StatsPage() {
  const [me, setMe] = useState<MeStats | null>(null);
  const [clubs, setClubs] = useState<Club[]>([]);
  const [boards, setBoards] = useState<Record<string, ClubBoard>>({});
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view season stats.");
      return;
    }
    (async () => {
      try {
        const stats = await api<MeStats>("GET", "/me/stats?season=2026");
        setMe(stats);
        const list = await api<Club[]>("GET", "/clubs");
        setClubs(list);
        const entries = await Promise.all(
          list.map(async (c) => {
            try {
              const board = await api<ClubBoard>(
                "GET",
                `/clubs/${c.id}/stats?season=2026`
              );
              return [c.id, board] as const;
            } catch {
              return null;
            }
          })
        );
        setBoards(
          Object.fromEntries(
            entries.filter((e): e is readonly [string, ClubBoard] => e !== null)
          )
        );
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      }
    })();
  }, []);

  const season = me?.seasons?.[0];

  return (
    <main>
      <section className="hero">
        <h1>Season stats</h1>
        <p>
          Runs, wickets and achievements from ECB Play-Cricket sample data —
          deep-linked to play-cricket.com.
        </p>
      </section>
      {error && <p className="error">{error}</p>}

      {season && (
        <section className="panel" style={{ marginBottom: 24 }}>
          <h2>
            Your {season.season_year} season
            {season.club_name ? ` · ${season.club_name}` : ""}
          </h2>
          <div className="grid cards" style={{ marginTop: 12 }}>
            <article className="panel">
              <p className="muted">Runs</p>
              <p style={{ fontSize: "2rem", fontWeight: 700 }}>{season.runs}</p>
            </article>
            <article className="panel">
              <p className="muted">Wickets</p>
              <p style={{ fontSize: "2rem", fontWeight: 700 }}>{season.wickets}</p>
            </article>
            <article className="panel">
              <p className="muted">Matches</p>
              <p style={{ fontSize: "2rem", fontWeight: 700 }}>{season.matches}</p>
            </article>
            <article className="panel">
              <p className="muted">High score</p>
              <p style={{ fontSize: "2rem", fontWeight: 700 }}>
                {season.high_score ?? "—"}
              </p>
            </article>
          </div>
          <p className="muted" style={{ marginTop: 12 }}>
            Avg{" "}
            {season.batting_average != null
              ? season.batting_average.toFixed(1)
              : "—"}{" "}
            · Bowl avg{" "}
            {season.bowling_average != null
              ? season.bowling_average.toFixed(1)
              : "—"}
          </p>
          {season.play_cricket_profile_url && (
            <p style={{ marginTop: 8 }}>
              <a href={season.play_cricket_profile_url} target="_blank" rel="noreferrer">
                View on Play-Cricket →
              </a>
            </p>
          )}
        </section>
      )}

      {me && me.achievements.length > 0 && (
        <section style={{ marginBottom: 24 }}>
          <h2>Achievements</h2>
          <div className="grid cards" style={{ marginTop: 12 }}>
            {me.achievements.map((a) => (
              <article key={a.id} className="panel">
                <p className="tag">{a.icon || "★"}</p>
                <h3>{a.title}</h3>
                {a.description && <p className="muted">{a.description}</p>}
                {a.season_year != null && (
                  <p className="muted">Season {a.season_year}</p>
                )}
              </article>
            ))}
          </div>
        </section>
      )}

      <section>
        <h2>Club boards</h2>
        <div className="grid cards" style={{ marginTop: 12 }}>
          {clubs.map((c) => {
            const board = boards[c.id];
            return (
              <article key={c.id} className="panel">
                <h3>{c.name}</h3>
                {!board && <p className="muted">No cricket season board</p>}
                {board && (
                  <>
                    <p className="tag">
                      {board.club.season_year} · {board.club.wins}–
                      {board.club.losses}–{board.club.draws}
                    </p>
                    <p>
                      {board.club.matches_played} played · {board.club.runs_for}{" "}
                      runs for · {board.club.wickets_taken} wickets
                    </p>
                    {board.play_cricket?.public_url && (
                      <p style={{ marginTop: 8 }}>
                        <a
                          href={board.play_cricket.public_url}
                          target="_blank"
                          rel="noreferrer"
                        >
                          {board.play_cricket.site_name || "Play-Cricket"} →
                        </a>
                      </p>
                    )}
                    <h4 style={{ marginTop: 16 }}>Top batters</h4>
                    <ul>
                      {board.top_batters.slice(0, 5).map((p) => (
                        <li key={p.id}>
                          {p.player_name || "Player"} — {p.runs} runs
                        </li>
                      ))}
                    </ul>
                    <h4 style={{ marginTop: 12 }}>Top bowlers</h4>
                    <ul>
                      {board.top_bowlers.slice(0, 5).map((p) => (
                        <li key={p.id}>
                          {p.player_name || "Player"} — {p.wickets} wkts
                        </li>
                      ))}
                    </ul>
                  </>
                )}
              </article>
            );
          })}
        </div>
      </section>

      <p className="muted" style={{ marginTop: 32 }}>
        Docs: <Link href="/docs">API</Link> ·{" "}
        <code>docs/PLAY_CRICKET_STATS.md</code>
      </p>
    </main>
  );
}
