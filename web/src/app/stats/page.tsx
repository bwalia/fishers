"use client";

import { useCallback, useEffect, useState } from "react";
import { api, type Club } from "@/lib/api";
import { Icon } from "@/components/Icon";
import {
  economy,
  num,
  winRate,
  type ClubSeasonBoard,
  type MeStats,
  type PlayerSeasonStats,
} from "@/lib/stats";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

const SEASONS = [2026, 2025, 2024];

export default function StatsPage() {
  const t = useT();
  const authed = useRequireAuth();
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
    if (!authed) return;
    (async () => {
      try {
        const c = await api<Club[]>("GET", "/clubs");
        setClubs(c);
        if (c[0]) setClubId(c[0].id);
      } catch (err) {
        setError(err instanceof Error ? err.message : t("sh.could_not_load_clubs"));
      }
      try {
        setMine(await api<MeStats>("GET", "/me/stats"));
      } catch {
        // A player with no recorded season is not an error.
      }
    })();
  }, [authed, t]);

  const loadBoard = useCallback(async () => {
    if (!clubId) return;
    setLoading(true);
    setNote(null);
    try {
      setBoard(await api<ClubSeasonBoard>("GET", `/clubs/${clubId}/stats?season=${season}`));
    } catch {
      setBoard(null);
      setNote(t("sh.no_season_board", { season }));
    } finally {
      setLoading(false);
    }
  }, [clubId, season, t]);

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
      setNote(err instanceof Error ? err.message : t("le.sync_failed"));
    } finally {
      setSyncing(false);
    }
  };

  const club = board?.club;

  if (!authed) return <main id="main" />;

  return (
    <main id="main">
      <section className="hero">
        <h1>{t("sh.season_stats")}</h1>
        <p>{t("sh.season_stats_intro", { brand: brand.name })}</p>
      </section>

      {error && <p className="error">{error}</p>}

      {!error && (
        <div className="select-row">
          <label>
            {t("sh.club")}
            <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
              {clubs.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
          <label>
            {t("sh.season")}
            <select value={season} onChange={(e) => setSeason(Number(e.target.value))}>
              {SEASONS.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
          <button className="btn ghost" type="button" onClick={sync} disabled={!clubId || syncing}>
            <Icon name="clock" size={16} />
            {syncing ? t("le.syncing") : t("le.sync_play_cricket")}
          </button>
        </div>
      )}

      {note && <p className="muted">{note}</p>}

      {club && (
        <>
          <div className="grid" style={{ marginBottom: "var(--s4)" }}>
            <Stat label={t("sh.played")} value={club.matches_played} />
            <Stat label={t("sh.won")} value={club.wins} tone="primary" />
            <Stat label={t("sh.lost")} value={club.losses} />
            <Stat
              label={t("sh.win_rate")}
              value={winRate(club) === null ? "—" : `${num(winRate(club), 0)}%`}
              sub={t("sh.drawn_no_result", { drawn: club.draws, nr: club.no_results })}
              tone="accent"
            />
            <Stat label={t("sh.runs_for")} value={club.runs_for} sub={t("sh.runs_against", { n: club.runs_against })} />
            <Stat
              label={t("sh.wickets_taken")}
              value={club.wickets_taken}
              sub={t("sh.wickets_lost", { n: club.wickets_lost })}
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
            <h2>{t("sh.your_record")}</h2>
            <span className="tag grey">{t("sh.all_seasons")}</span>
          </div>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>{t("sh.season")}</th>
                  <th className="n">{t("sh.col_m")}</th>
                  <th className="n">{t("sh.col_runs")}</th>
                  <th className="n">{t("sh.col_hs")}</th>
                  <th className="n">{t("sh.col_avg")}</th>
                  <th className="n">{t("sh.col_sr")}</th>
                  <th className="n">{t("sh.col_wkts")}</th>
                  <th className="n">{t("sh.col_econ")}</th>
                  <th className="n">{t("sh.ct_st")}</th>
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
          <h2>{t("sh.achievements")}</h2>
          <div className="grid cards">
            {mine.achievements.map((a) => (
              <div className="stat accent" key={a.id}>
                <div className="stat-label">
                  <Icon name="trophy" size={14} /> {t("sh.award")}
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
          {t("sh.club_on_play_cricket")}{" "}
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
  const t = useT();
  const name = p.player_name || t("le.unknown_player");
  return p.play_cricket_profile_url ? (
    <a href={p.play_cricket_profile_url} target="_blank" rel="noreferrer">{name}</a>
  ) : (
    <>{name}</>
  );
}

function BattingBoard({ players }: { players: PlayerSeasonStats[] }) {
  const t = useT();
  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("sh.batting")}</h2>
        <span className="tag">
          <Icon name="bat" size={12} /> {t("sh.top_n", { n: players.length })}
        </span>
      </div>
      {players.length === 0 ? (
        <Empty what={t("sh.batting_figures")} />
      ) : (
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>{t("sh.player")}</th>
                <th className="n">{t("sh.col_m")}</th>
                <th className="n">{t("sh.col_inns")}</th>
                <th className="n">{t("sh.col_no")}</th>
                <th className="n">{t("sh.col_runs")}</th>
                <th className="n">{t("sh.col_hs")}</th>
                <th className="n">{t("sh.col_avg")}</th>
                <th className="n">{t("sh.col_sr")}</th>
                <th className="n">{t("sh.col_fours")}</th>
                <th className="n">{t("sh.col_sixes")}</th>
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
  const t = useT();
  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("sh.bowling")}</h2>
        <span className="tag">
          <Icon name="ball" size={12} /> {t("sh.top_n", { n: players.length })}
        </span>
      </div>
      {players.length === 0 ? (
        <Empty what={t("sh.bowling_figures")} />
      ) : (
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>{t("sh.player")}</th>
                <th className="n">{t("sh.col_m")}</th>
                <th className="n">{t("sh.col_overs")}</th>
                <th className="n">{t("sh.col_mdns")}</th>
                <th className="n">{t("sh.col_runs")}</th>
                <th className="n">{t("sh.col_wkts")}</th>
                <th className="n">{t("sh.col_avg")}</th>
                <th className="n">{t("sh.col_econ")}</th>
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
  const t = useT();
  return (
    <div className="empty">
      <Icon name="chart" size={28} />
      <p>{t("sh.no_figures_yet", { what })}</p>
    </div>
  );
}
