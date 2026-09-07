"use client";

import { useCallback, useEffect, useState } from "react";
import { api, getAccessToken, type Club } from "@/lib/api";
import { Icon } from "@/components/Icon";
import {
  economy,
  num,
  winRate,
  type ClubSeasonBoard,
  type MeStats,
  type PlayerSeasonStats,
} from "@/lib/stats";

const SEASONS = [2026, 2025, 2024];

export default function StatsPage() {
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [season, setSeason] = useState(SEASONS[0]);
  const [board, setBoard] = useState<ClubSeasonBoard | null>(null);
  const [mine, setMine] = useState<MeStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [syncing, setSyncing] = useState(false);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view season stats.");
      return;
    }
    (async () => {
      try {
        const c = await api<Club[]>("GET", "/clubs");
        setClubs(c);
        if (c[0]) setClubId(c[0].id);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load clubs");
      }
      try {
        setMine(await api<MeStats>("GET", "/me/stats"));
      } catch {
        // A player with no recorded season is not an error.
      }
    })();
  }, []);

  const loadBoard = useCallback(async () => {
    if (!clubId) return;
    setLoading(true);
    setNote(null);
    try {
      setBoard(await api<ClubSeasonBoard>("GET", `/clubs/${clubId}/stats?season=${season}`));
    } catch {
      setBoard(null);
      setNote(`No ${season} season board for this club yet.`);
    } finally {
      setLoading(false);
    }
  }, [clubId, season]);

  useEffect(() => {
    loadBoard();
  }, [loadBoard]);

  const sync = async () => {
    setSyncing(true);
    setNote(null);
    try {
      // Takes no body, and only a club secretary may run it.
      await api("POST", `/clubs/${clubId}/stats/sync`);
      await loadBoard();
    } catch (err) {
      setNote(err instanceof Error ? err.message : "Sync failed");
    } finally {
      setSyncing(false);
    }
  };

  const club = board?.club;

  return (
    <main id="main">
      <section className="hero">
        <h1>Season stats</h1>
        <p>
          Batting, bowling and results for the club and every player, by season. Figures
          come from matches scored in Fishers and from ECB Play-Cricket where a club is
          linked.
        </p>
      </section>

      {error && <p className="error">{error}</p>}

      {!error && (
        <div className="select-row">
          <label>
            Club
            <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
              {clubs.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
          <label>
            Season
            <select value={season} onChange={(e) => setSeason(Number(e.target.value))}>
              {SEASONS.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
          <button className="btn ghost" type="button" onClick={sync} disabled={!clubId || syncing}>
            <Icon name="clock" size={16} />
            {syncing ? "Syncing…" : "Sync Play-Cricket"}
          </button>
        </div>
      )}

      {note && <p className="muted">{note}</p>}

      {club && (
        <>
          <div className="grid" style={{ marginBottom: "var(--s4)" }}>
            <Stat label="Played" value={club.matches_played} />
            <Stat label="Won" value={club.wins} tone="primary" />
            <Stat label="Lost" value={club.losses} />
            <Stat
              label="Win rate"
              value={winRate(club) === null ? "—" : `${num(winRate(club), 0)}%`}
              sub={`${club.draws} drawn · ${club.no_results} no result`}
              tone="accent"
            />
            <Stat label="Runs for" value={club.runs_for} sub={`${club.runs_against} against`} />
            <Stat
              label="Wickets taken"
              value={club.wickets_taken}
              sub={`${club.wickets_lost} lost`}
            />
          </div>

          <BattingBoard players={board.top_batters} />
          <BowlingBoard players={board.top_bowlers} />
        </>
      )}

      {loading && !club && (
        <div className="panel">
          <div className="skeleton" style={{ height: 80 }} />
        </div>
      )}

      {mine && mine.seasons.length > 0 && (
        <div className="panel">
          <div className="panel-head">
            <h2>Your record</h2>
            <span className="tag grey">All seasons</span>
          </div>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Season</th>
                  <th className="n">M</th>
                  <th className="n">Runs</th>
                  <th className="n">HS</th>
                  <th className="n">Avg</th>
                  <th className="n">SR</th>
                  <th className="n">Wkts</th>
                  <th className="n">Econ</th>
                  <th className="n">Ct/St</th>
                </tr>
              </thead>
              <tbody>
                {mine.seasons.map((s) => (
                  <tr key={s.id}>
                    <td>{s.season_year}</td>
                    <td className="n">{s.matches}</td>
                    <td className="n">{s.runs}</td>
                    <td className="n">{s.high_score ?? "—"}</td>
                    <td className="n">{num(s.batting_average)}</td>
                    <td className="n">{num(s.strike_rate, 1)}</td>
                    <td className="n">{s.wickets}</td>
                    <td className="n">{num(economy(s))}</td>
                    <td className="n">{s.catches}/{s.stumpings}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {mine && mine.achievements.length > 0 && (
        <div className="panel">
          <h2>Achievements</h2>
          <div className="grid cards">
            {mine.achievements.map((a) => (
              <div className="stat accent" key={a.id}>
                <div className="stat-label">
                  <Icon name="trophy" size={14} /> Award
                </div>
                <div style={{ fontWeight: 600, marginTop: "var(--s1)" }}>{a.title}</div>
                {a.description && <div className="subtle">{a.description}</div>}
              </div>
            ))}
          </div>
        </div>
      )}

      {board?.play_cricket?.site_url && (
        <p className="muted">
          Club on Play-Cricket:{" "}
          <a href={board.play_cricket.site_url} target="_blank" rel="noreferrer">
            {board.play_cricket.name || board.play_cricket.site_url}
          </a>
        </p>
      )}
    </main>
  );
}

function Stat({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: number | string;
  sub?: string;
  tone?: "primary" | "accent";
}) {
  return (
    <div className={`stat${tone ? ` ${tone}` : ""}`}>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {sub && <div className="stat-sub">{sub}</div>}
    </div>
  );
}

function PlayerName({ p }: { p: PlayerSeasonStats }) {
  const name = p.player_name || "Unknown player";
  return p.play_cricket_profile_url ? (
    <a href={p.play_cricket_profile_url} target="_blank" rel="noreferrer">{name}</a>
  ) : (
    <>{name}</>
  );
}

function BattingBoard({ players }: { players: PlayerSeasonStats[] }) {
  return (
    <div className="panel">
      <div className="panel-head">
        <h2>Batting</h2>
        <span className="tag">
          <Icon name="bat" size={12} /> Top {players.length}
        </span>
      </div>
      {players.length === 0 ? (
        <Empty what="batting figures" />
      ) : (
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Player</th>
                <th className="n">M</th>
                <th className="n">Inns</th>
                <th className="n">NO</th>
                <th className="n">Runs</th>
                <th className="n">HS</th>
                <th className="n">Avg</th>
                <th className="n">SR</th>
                <th className="n">4s</th>
                <th className="n">6s</th>
              </tr>
            </thead>
            <tbody>
              {players.map((p) => (
                <tr key={p.id}>
                  <td><PlayerName p={p} /></td>
                  <td className="n">{p.matches}</td>
                  <td className="n">{p.batting_innings}</td>
                  <td className="n">{p.not_outs}</td>
                  <td className="n"><strong>{p.runs}</strong></td>
                  <td className="n">{p.high_score ?? "—"}</td>
                  <td className="n">{num(p.batting_average)}</td>
                  <td className="n">{num(p.strike_rate, 1)}</td>
                  <td className="n">{p.fours}</td>
                  <td className="n">{p.sixes}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function BowlingBoard({ players }: { players: PlayerSeasonStats[] }) {
  return (
    <div className="panel">
      <div className="panel-head">
        <h2>Bowling</h2>
        <span className="tag">
          <Icon name="ball" size={12} /> Top {players.length}
        </span>
      </div>
      {players.length === 0 ? (
        <Empty what="bowling figures" />
      ) : (
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Player</th>
                <th className="n">M</th>
                <th className="n">Overs</th>
                <th className="n">Mdns</th>
                <th className="n">Runs</th>
                <th className="n">Wkts</th>
                <th className="n">Avg</th>
                <th className="n">Econ</th>
              </tr>
            </thead>
            <tbody>
              {players.map((p) => (
                <tr key={p.id}>
                  <td><PlayerName p={p} /></td>
                  <td className="n">{p.matches}</td>
                  <td className="n">{num(p.overs_bowled, 1)}</td>
                  <td className="n">{p.maidens}</td>
                  <td className="n">{p.bowling_runs}</td>
                  <td className="n"><strong>{p.wickets}</strong></td>
                  <td className="n">{num(p.bowling_average)}</td>
                  <td className="n">{num(economy(p))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function Empty({ what }: { what: string }) {
  return (
    <div className="empty">
      <Icon name="chart" size={28} />
      <p>No {what} for this season yet. They appear once a match is scored or synced.</p>
    </div>
  );
}
