"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { api, type Club, type MyRole, readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";
import type { T } from "@/lib/i18n";
import {
  BEST_LABELS,
  BOARD_LABELS,
  fmt,
  highlightText,
  milestoneLabel,
  place,
  score,
  shortDate,
  type ClosePreview,
  type ClubSeason,
  type FormEntry,
  type PlayerGame,
  type Totals,
  type Trend,
} from "@/lib/season";

type Tab = "mine" | "club";

/// Stats, for players first.
///
/// "My game" opens on the good news in the season — a best, a milestone, a
/// number that went up — then the handful of figures that describe it, the
/// last ten matches, and the bests and milestones of a whole career. A lower
/// number than last season is shown as plain context, never in red: the page
/// is for knowing your game, not for being marked down by it.
///
/// "Club" is the season's record and its leaderboards, and for a secretary
/// the button that closes the season and sends every member theirs.
///
/// Arrives from the season email as /stats?season=2026&club=<id>.
export default function StatsPage() {
  const t = useT();
  const authed = useRequireAuth();
  const thisYear = new Date().getFullYear();
  const [tab, setTab] = useState<Tab>("mine");
  const [season, setSeason] = useState<number | null>(null);
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [game, setGame] = useState<PlayerGame | null>(null);
  const [clubSeason, setClubSeason] = useState<ClubSeason | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // The link from the email says which season and club. Read after the first
  // render, as the register page does: the server render has no query string.
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const s = Number(q.get("season"));
    if (s >= 2000 && s <= thisYear + 1) setSeason(s);
    const c = q.get("club");
    if (c) setClubId(c);
    if (q.get("tab") === "club") setTab("club");
  }, [thisYear]);

  useEffect(() => {
    if (!authed) return;
    api<Club[]>("GET", "/clubs")
      .then((c) => {
        setClubs(c);
        setClubId((cur) => cur || c[0]?.id || "");
      })
      .catch(() => setClubs([]));
  }, [authed]);

  // Keep the address in step, so a refresh or a shared link lands here.
  useEffect(() => {
    if (!authed) return;
    const q = new URLSearchParams();
    if (season) q.set("season", String(season));
    if (clubId) q.set("club", clubId);
    if (tab === "club") q.set("tab", "club");
    window.history.replaceState(null, "", `/stats${q.size ? `?${q}` : ""}`);
  }, [authed, season, clubId, tab]);

  const loadGame = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const q = season ? `?season=${season}` : "";
      const g = await api<PlayerGame>("GET", `/me/game${q}`);
      setGame(g);
      if (!season) setSeason(g.season);
    } catch (err) {
      setError(readErr(err, t("ss.could_not_load")));
    } finally {
      setLoading(false);
    }
  }, [season, t]);

  const loadClub = useCallback(async () => {
    if (!clubId) return;
    setLoading(true);
    setError(null);
    try {
      const q = season ? `?season=${season}` : "";
      const c = await api<ClubSeason>("GET", `/clubs/${clubId}/season${q}`);
      setClubSeason(c);
      if (!season) setSeason(c.season);
    } catch (err) {
      setClubSeason(null);
      setError(readErr(err, t("ss.could_not_load")));
    } finally {
      setLoading(false);
    }
  }, [clubId, season, t]);

  useEffect(() => {
    if (!authed) return;
    if (tab === "mine") void loadGame();
    else void loadClub();
  }, [authed, tab, loadGame, loadClub]);

  const seasons = useMemo(() => {
    const all = new Set<number>([thisYear, ...(game?.seasons ?? []), ...(clubSeason?.seasons ?? [])]);
    if (season) all.add(season);
    return [...all].sort((a, b) => b - a);
  }, [game, clubSeason, season, thisYear]);

  if (!authed) return <main id="main" />;

  return (
    <main id="main" className="season-page">
      <section className="hero">
        <h1>{tab === "mine" ? t("ss.my_game") : t("ss.club_season")}</h1>
        <p>{tab === "mine" ? t("ss.my_game_intro") : t("ss.club_intro", { brand: brand.name })}</p>
      </section>

      <div className="season-controls">
        <div className="tabs" role="tablist" aria-label={t("ss.view")}>
          {(["mine", "club"] as Tab[]).map((v) => (
            <button
              key={v}
              role="tab"
              aria-selected={tab === v}
              className={`tab${tab === v ? " active" : ""}`}
              onClick={() => setTab(v)}
              type="button"
            >
              {v === "mine" ? t("ss.tab_mine") : t("ss.tab_club")}
            </button>
          ))}
        </div>
        <div className="select-row">
          <label>
            {t("sh.season")}
            <select value={season ?? ""} onChange={(e) => setSeason(Number(e.target.value))}>
              {seasons.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </label>
          {tab === "club" && clubs.length > 0 && (
            <label>
              {t("sh.club")}
              <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
                {clubs.map((c) => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </select>
            </label>
          )}
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {loading && !error && <div className="skeleton" style={{ height: 160 }} />}

      {!loading && !error && tab === "mine" && game && <MyGame t={t} game={game} />}
      {!loading && !error && tab === "club" && clubSeason && (
        <ClubTab t={t} season={clubSeason} meId={game?.user_id} onClosed={loadClub} />
      )}
      {!loading && !error && tab === "club" && !clubId && (
        <div className="panel empty">
          <Icon name="users" size={28} />
          <p>{t("ss.no_club")}</p>
          <Link className="btn" href="/clubs">{t("rest.your_clubs")}</Link>
        </div>
      )}
    </main>
  );
}

// MARK: My game

function MyGame({ t, game }: { t: T; game: PlayerGame }) {
  const s = game.totals;
  if (s.matches === 0) {
    return (
      <div className="panel empty">
        <Icon name="bat" size={28} />
        <h2>{t("ss.empty_title", { season: game.season })}</h2>
        <p className="muted">{t("ss.empty_body")}</p>
        {game.career.matches > 0 && <p className="muted">{t("ss.empty_career", { n: game.career.matches, count: game.career.matches })}</p>}
        <Link className="btn primary" href="/events">{t("ss.see_fixtures")}</Link>
      </div>
    );
  }
  return (
    <>
      <Highlights t={t} game={game} />
      <Headline t={t} now={s} before={game.previous} season={game.season} />
      <FormPanel t={t} game={game} />
      <div className="season-two">
        <Bests t={t} game={game} />
        <Milestones t={t} game={game} />
      </div>
      {game.club_rank && <Rank t={t} game={game} />}
    </>
  );
}

function Highlights({ t, game }: { t: T; game: PlayerGame }) {
  if (!game.highlights.length) return null;
  return (
    <section className="panel season-highlights" aria-labelledby="hl-head">
      <h2 id="hl-head">{t("ss.highlights_title", { season: game.season })}</h2>
      <ul>
        {game.highlights.map((h, i) => (
          <li key={`${h.code}-${i}`}>
            <span className="season-hl-icon" aria-hidden="true">
              <Icon name={h.code.startsWith("club_top") || h.code.includes("best") ? "trophy" : "check"} size={18} />
            </span>
            <span>{highlightText(t, h)}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

/// The numbers that describe the season, each with last season beside it.
/// Better than last time gets a green arrow; anything else is plain context.
function Headline({ t, now, before, season }: { t: T; now: Totals; before: Totals | null; season: number }) {
  const tiles: { key: string; label: string; value: string; sub?: string; up?: boolean | null; was?: string }[] = [];
  const cmp = (a: number | null, b: number | null | undefined, higherIsBetter = true) =>
    a === null || b === null || b === undefined ? null : higherIsBetter ? a > b : a < b;

  tiles.push({
    key: "matches",
    label: t("ss.matches"),
    value: String(now.matches),
    sub: t("ss.won_n", { n: now.won }),
  });
  if (now.batting_innings > 0) {
    tiles.push({
      key: "runs",
      label: t("ss.runs"),
      value: String(now.runs),
      sub: t("ss.innings_n", { n: now.batting_innings, count: now.batting_innings }),
      up: before && before.batting_innings > 0 ? cmp(now.runs, before.runs) : null,
      was: before && before.batting_innings > 0 ? String(before.runs) : undefined,
    });
    tiles.push({
      key: "avg",
      label: t("ss.average"),
      value: fmt(now.batting_average),
      sub: t("ss.best_n", { score: score(now.high_score, now.high_score_not_out) }),
      up: before ? cmp(now.batting_average, before.batting_average) : null,
      was: before?.batting_average != null ? fmt(before.batting_average) : undefined,
    });
    tiles.push({
      key: "sr",
      label: t("ss.strike_rate"),
      value: fmt(now.strike_rate),
      sub: t("ss.fours_sixes", { fours: now.fours, sixes: now.sixes }),
      up: before ? cmp(now.strike_rate, before.strike_rate) : null,
      was: before?.strike_rate != null ? fmt(before.strike_rate) : undefined,
    });
  }
  if (now.bowling_balls > 0) {
    tiles.push({
      key: "wkts",
      label: t("ss.wickets"),
      value: String(now.wickets),
      sub: now.best_bowling && now.best_bowling.wickets > 0
        ? t("ss.best_n", { score: `${now.best_bowling.wickets}/${now.best_bowling.runs}` })
        : t("ss.overs_n", { overs: now.overs }),
      up: before && before.bowling_balls > 0 ? cmp(now.wickets, before.wickets) : null,
      was: before && before.bowling_balls > 0 ? String(before.wickets) : undefined,
    });
    tiles.push({
      key: "econ",
      label: t("ss.economy"),
      value: fmt(now.economy, 2),
      sub: t("ss.overs_n", { overs: now.overs }),
      up: before ? cmp(now.economy, before.economy, false) : null,
      was: before?.economy != null ? fmt(before.economy, 2) : undefined,
    });
  }
  const held = now.catches + now.stumpings;
  if (held > 0 || now.batting_innings === 0) {
    tiles.push({
      key: "field",
      label: t("ss.catches"),
      value: String(held),
      up: before ? cmp(held, before.catches + before.stumpings) : null,
      was: before ? String(before.catches + before.stumpings) : undefined,
    });
  }

  return (
    <section className="season-tiles" aria-label={t("ss.season_numbers", { season })}>
      {tiles.map((tile) => (
        <div className={`stat${tile.up ? " primary" : ""}`} key={tile.key}>
          <div className="stat-label">{tile.label}</div>
          <div className="stat-value">{tile.value}</div>
          {tile.sub && <div className="stat-sub">{tile.sub}</div>}
          {tile.was !== undefined && (
            <div className={`season-delta${tile.up ? " up" : ""}`}>
              {tile.up ? "▲ " : ""}
              {t("ss.last_season", { value: tile.was })}
            </div>
          )}
        </div>
      ))}
    </section>
  );
}

function trendText(t: T, trend: Trend | null, recent: number | null, kind: "bat" | "bowl"): string | null {
  if (!trend || recent === null) return null;
  const value = fmt(recent);
  if (kind === "bat") {
    return {
      rising: t("ss.trend.bat_rising", { value }),
      steady: t("ss.trend.bat_steady", { value }),
      quieter: t("ss.trend.bat_quieter", { value }),
    }[trend];
  }
  return {
    rising: t("ss.trend.bowl_rising", { value }),
    steady: t("ss.trend.bowl_steady", { value }),
    quieter: t("ss.trend.bowl_quieter", { value }),
  }[trend];
}

function FormPanel({ t, game }: { t: T; game: PlayerGame }) {
  const f = game.form;
  const bat = trendText(t, f.batting_trend, f.recent_batting_average, "bat");
  const bowl = trendText(t, f.bowling_trend, f.recent_wickets_per_match, "bowl");
  // Oldest on the left, so it reads the way the season went.
  const matches = [...f.matches].reverse();
  const batted = matches.some((m) => m.batted);
  // A column with nothing in it is a column of dashes: leave it out.
  const bowled = matches.some((m) => m.bowled);
  return (
    <section className="panel" aria-labelledby="form-head">
      <div className="panel-head">
        <h2 id="form-head">{t("ss.form_title")}</h2>
        <span className="subtle">{t("ss.last_n_matches", { n: matches.length, count: matches.length })}</span>
      </div>
      {(bat || bowl) && (
        <div className="season-trends">
          {bat && <p className={`season-trend ${f.batting_trend}`}>{bat}</p>}
          {bowl && <p className={`season-trend ${f.bowling_trend}`}>{bowl}</p>}
        </div>
      )}
      {batted && <RunsChart t={t} matches={matches} />}
      <table className="season-form-table">
        <caption className="sr-only">{t("ss.form_table")}</caption>
        <thead>
          <tr>
            <th scope="col">{t("ss.date")}</th>
            <th scope="col">{t("ss.against")}</th>
            {batted && <th scope="col" className="num">{t("ss.batting")}</th>}
            {bowled && <th scope="col" className="num">{t("ss.bowling")}</th>}
            <th scope="col" className="season-result">{t("ss.result")}</th>
          </tr>
        </thead>
        <tbody>
          {f.matches.map((m) => (
            <tr key={m.match_id}>
              <td>{shortDate(m.played_at)}</td>
              <td>
                {m.opposition || "–"}
                {m.player_of_match && <span className="tag gold" style={{ marginLeft: 6 }}>{t("ss.potm")}</span>}
              </td>
              {batted && (
                <td className="num">{m.batted ? `${score(m.runs, m.not_out)} (${m.balls})` : <span className="subtle">{t("ss.dnb")}</span>}</td>
              )}
              {bowled && <td className="num">{m.bowled ? `${m.wickets}/${m.runs_conceded} (${m.overs})` : "–"}</td>}
              <td className="season-result">
                {m.won === true && <span className="tag">{t("ss.won")}</span>}
                {m.won === false && <span className="tag grey">{t("ss.lost")}</span>}
                {m.won === null && <span className="tag grey">{t("ss.tied_nr")}</span>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

/// Runs in each match, one bar each, oldest first. One series, so no legend:
/// the heading names it. Only the best bar carries its number; the rest show
/// theirs on hover, and the table underneath has every one.
function RunsChart({ t, matches }: { t: T; matches: FormEntry[] }) {
  const [hover, setHover] = useState<number | null>(null);
  // Drawn at the width it is shown at, so a date is the same size on a phone
  // as on a monitor rather than scaled with the page.
  const box = useRef<HTMLDivElement>(null);
  const [W, setW] = useState(640);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setW(Math.max(260, Math.round(e.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const H = 190;
  const pad = { top: 22, bottom: 24, left: 8, right: 8 };
  const max = Math.max(10, ...matches.map((m) => m.runs));
  const slot = (W - pad.left - pad.right) / matches.length;
  const barW = Math.min(36, slot - 6);
  const y = (v: number) => H - pad.bottom - (v / max) * (H - pad.top - pad.bottom);
  const best = matches.reduce((b, m, i) => (m.batted && m.runs > (matches[b]?.runs ?? -1) ? i : b), 0);
  const h = hover !== null ? matches[hover] : null;
  // Dates only where they fit; every other one when the bars are tight.
  const every = slot >= 52 ? 1 : 2;
  return (
    <div className="season-chart" ref={box}>
      <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={t("ss.runs_chart")} onMouseLeave={() => setHover(null)}>
        <line x1={pad.left} x2={W - pad.right} y1={H - pad.bottom} y2={H - pad.bottom} className="season-axis" />
        {matches.map((m, i) => {
          const cx = pad.left + slot * i + slot / 2;
          const top = y(m.runs);
          const height = Math.max(0, H - pad.bottom - top);
          return (
            <g key={m.match_id}>
              {m.batted ? (
                <path
                  className={`season-bar${hover === i ? " hover" : ""}`}
                  d={roundedTop(cx - barW / 2, top, barW, height, Math.min(4, height))}
                />
              ) : (
                <text x={cx} y={H - pad.bottom - 6} textAnchor="middle" className="season-dnb">–</text>
              )}
              {i === best && m.batted && (
                <text x={cx} y={top - 6} textAnchor="middle" className="season-bar-label">
                  {score(m.runs, m.not_out)}
                </text>
              )}
              {(matches.length - 1 - i) % every === 0 && (
                <text x={cx} y={H - 6} textAnchor="middle" className="season-tick">
                  {shortDate(m.played_at)}
                </text>
              )}
              {/* The hit target is the whole column, not the bar. */}
              <rect
                x={pad.left + slot * i}
                y={0}
                width={slot}
                height={H}
                fill="transparent"
                onMouseEnter={() => setHover(i)}
                onFocus={() => setHover(i)}
                onBlur={() => setHover(null)}
                tabIndex={0}
                aria-label={`${shortDate(m.played_at)} ${m.opposition}: ${m.batted ? score(m.runs, m.not_out) : t("ss.dnb")}`}
              />
            </g>
          );
        })}
      </svg>
      {h && hover !== null && (
        <div
          className="season-tooltip"
          style={{ left: `${((pad.left + slot * hover + slot / 2) / W) * 100}%` }}
          role="status"
        >
          <strong>{h.batted ? `${score(h.runs, h.not_out)} (${h.balls})` : t("ss.dnb")}</strong>
          {h.bowled && <span> · {h.wickets}/{h.runs_conceded}</span>}
          <div className="subtle">
            {t("ss.v_opposition", { opposition: h.opposition })} · {shortDate(h.played_at)}
          </div>
        </div>
      )}
    </div>
  );
}

function roundedTop(x: number, y: number, w: number, h: number, r: number): string {
  if (h <= 0) return "";
  return `M${x},${y + h} V${y + r} Q${x},${y} ${x + r},${y} H${x + w - r} Q${x + w},${y} ${x + w},${y + r} V${y + h} Z`;
}

function Bests({ t, game }: { t: T; game: PlayerGame }) {
  if (!game.bests.length) return null;
  return (
    <section className="panel" aria-labelledby="bests-head">
      <h2 id="bests-head">{t("ss.bests_title")}</h2>
      <ul className="season-list">
        {game.bests.map((b) => (
          <li key={b.code}>
            <div>
              <div className="season-list-label">{BEST_LABELS[b.code] ? t(BEST_LABELS[b.code]) : b.code}</div>
              <div className="subtle">
                {b.opposition
                  ? `${t("ss.v_opposition", { opposition: b.opposition })}${b.played_at ? ` · ${shortDate(b.played_at)} ${b.season_year ?? ""}` : ""}`
                  : b.season_year}
              </div>
            </div>
            <div className="season-list-value">
              {b.value}
              {b.this_season && <span className="tag gold">{t("ss.new_this_season")}</span>}
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}

function Milestones({ t, game }: { t: T; game: PlayerGame }) {
  if (!game.milestones.length) return null;
  // Newest first: what just happened is what matters.
  const list = [...game.milestones].reverse();
  return (
    <section className="panel" aria-labelledby="ms-head">
      <h2 id="ms-head">{t("ss.milestones_title")}</h2>
      <ul className="season-list">
        {list.map((m) => (
          <li key={m.code} className={m.this_season ? "fresh" : undefined}>
            <div>
              <div className="season-list-label">{milestoneLabel(t, m.code)}</div>
              <div className="subtle">
                {shortDate(m.reached_at)} {new Date(m.reached_at).getFullYear()}
                {m.opposition ? ` · ${t("ss.v_opposition", { opposition: m.opposition })}` : ""}
              </div>
            </div>
            {m.this_season && <span className="tag gold">{t("ss.new_this_season")}</span>}
          </li>
        ))}
      </ul>
    </section>
  );
}

function Rank({ t, game }: { t: T; game: PlayerGame }) {
  const r = game.club_rank!;
  const rows: [string, number | null][] = [
    [t("ss.board.runs"), r.runs],
    [t("ss.board.wickets"), r.wickets],
    [t("ss.board.catches"), r.catches],
  ];
  const shown = rows.filter(([, n]) => n !== null);
  if (!shown.length) return null;
  return (
    <section className="panel" aria-labelledby="rank-head">
      <h2 id="rank-head">{t("ss.rank_title", { club: r.club_name })}</h2>
      <div className="season-tiles">
        {shown.map(([label, n]) => (
          <div className="stat" key={label}>
            <div className="stat-label">{label}</div>
            <div className="stat-value">{place(t, n!)}</div>
            <div className="stat-sub">{t("ss.of_players", { n: r.players })}</div>
          </div>
        ))}
      </div>
      <Link className="btn ghost sm" href={`/stats?tab=club&club=${r.club_id}&season=${game.season}`}>
        {t("ss.see_leaderboards")}
      </Link>
    </section>
  );
}

// MARK: The club

function ClubTab({ t, season, meId, onClosed }: { t: T; season: ClubSeason; meId?: string; onClosed: () => void }) {
  const r = season.record;
  const winPct = r.played ? Math.round((r.won / r.played) * 100) : null;
  return (
    <>
      <section className="season-tiles" aria-label={t("ss.club_record")}>
        <div className="stat"><div className="stat-label">{t("sh.played")}</div><div className="stat-value">{r.played}</div></div>
        <div className="stat primary">
          <div className="stat-label">{t("sh.won")}</div>
          <div className="stat-value">{r.won}</div>
          {winPct !== null && <div className="stat-sub">{t("ss.win_pct", { n: winPct })}</div>}
        </div>
        <div className="stat"><div className="stat-label">{t("sh.lost")}</div><div className="stat-value">{r.lost}</div></div>
        <div className="stat"><div className="stat-label">{t("ss.tied_nr")}</div><div className="stat-value">{r.tied_or_no_result}</div></div>
        <div className="stat"><div className="stat-label">{t("ss.players")}</div><div className="stat-value">{season.players}</div></div>
      </section>

      <CloseSeason t={t} season={season} onClosed={onClosed} />

      {season.boards.length === 0 ? (
        <div className="panel empty">
          <Icon name="chart" size={28} />
          <p>{t("ss.no_boards", { season: season.season })}</p>
        </div>
      ) : (
        <div className="season-boards">
          {season.boards.map((b) => (
            <section className="panel" key={b.code} aria-labelledby={`board-${b.code}`}>
              <h3 id={`board-${b.code}`}>{BOARD_LABELS[b.code] ? t(BOARD_LABELS[b.code]) : b.code}</h3>
              <ol className="season-board">
                {b.leaders.map((l, i) => (
                  <li key={`${l.user_id}-${i}`} className={l.user_id === meId ? "me" : undefined}>
                    <span className="season-board-pos">{i + 1}</span>
                    <span className="season-board-name">
                      {l.user_id === meId ? (
                        <strong>{l.name} · {t("ss.you")}</strong>
                      ) : (
                        <Link href={`/players/${l.user_id}`}>{l.name}</Link>
                      )}
                      {l.detail && <span className="subtle"> {l.detail}</span>}
                    </span>
                    <span className="season-board-value">{l.value}</span>
                  </li>
                ))}
              </ol>
            </section>
          ))}
        </div>
      )}
    </>
  );
}

/// For a secretary: close the season, once, and every member gets theirs by
/// email. The preview says who before anything is sent, because it cannot be
/// taken back. Players never see this — the preview is refused for them.
function CloseSeason({ t, season, onClosed }: { t: T; season: ClubSeason; onClosed: () => void }) {
  const [preview, setPreview] = useState<ClosePreview | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const url = `/clubs/${season.club_id}/seasons/${season.season}/close`;

  useEffect(() => {
    setPreview(null);
    setNote(null);
    (async () => {
      // Ask what we may do first, as the club page does: only somebody who
      // runs the club's operations is shown the button at all.
      const role = await api<MyRole>("GET", `/clubs/${season.club_id}/my-role`).catch(() => null);
      if (!role?.permissions.includes("manage_club_ops")) return;
      setPreview(await api<ClosePreview>("GET", url).catch(() => null));
    })();
  }, [url, season.club_id]);

  if (season.closed_at) {
    return (
      <p className="muted season-closed">
        <Icon name="check" size={16} /> {t("ss.closed_on", { date: new Date(season.closed_at).toLocaleDateString() })}
      </p>
    );
  }
  if (!preview) return null;

  const close = async () => {
    if (!confirm(t("ss.close_confirm", { season: season.season, n: preview.will_email }))) return;
    setBusy(true);
    setNote(null);
    try {
      const done = await api<{ queued: number }>("POST", url);
      setNote(t("ss.closed_now", { n: done.queued }));
      onClosed();
    } catch (err) {
      setNote(readErr(err, t("ss.could_not_close")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel season-close" aria-labelledby="close-head">
      <h2 id="close-head">{t("ss.close_title", { season: season.season })}</h2>
      <p className="muted">{t("ss.close_explainer")}</p>
      <ul className="season-close-facts">
        <li>{t("ss.close_will_email", { n: preview.will_email, members: preview.members })}</li>
        <li>{t("ss.close_played", { n: preview.played })}</li>
        <li>{t("ss.close_thanks")}</li>
      </ul>
      <button className="btn primary" type="button" disabled={busy} onClick={() => void close()}>
        <Icon name="mail" size={16} /> {t("ss.close_button", { season: season.season })}
      </button>
      {note && <p className="muted">{note}</p>}
    </section>
  );
}
