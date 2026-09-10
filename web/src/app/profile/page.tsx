"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import {
  api,
  readErr,
  getAccessToken,
  saveUser,
  skillLabel,
  upload,
  SKILL_LEVELS,
  SPORTS,
  SPORT_POSITIONS,
  type PublicUser,
  type SportProfile,
} from "@/lib/api";
import { economy, num, type MeStats, type PlayerSeasonStats } from "@/lib/stats";
import { Icon } from "@/components/Icon";
import { Avatar } from "@/components/Avatar";

type Tab = "overview" | "batting" | "bowling";

/// A player's own page — the face, the numbers, the details.
///
/// Laid out the way a cricket profile is read rather than the way the record
/// is stored: the identity fills a band across the top, and everything below
/// is one of three tabs. The numbers come from the scoring log, so the batting
/// and bowling tabs are computed; the overview is what the player told us.
export default function ProfilePage() {
  const [me, setMe] = useState<PublicUser | null>(null);
  const [stats, setStats] = useState<MeStats | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const user = await api<PublicUser>("GET", "/me");
      setMe(user);
      // The nav reads the cached copy, so keep it honest after an edit.
      saveUser(user);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load your profile");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see your profile.");
      setLoading(false);
      return;
    }
    load();
    // A player with no season on record is not an error — the tabs say so.
    api<MeStats>("GET", "/me/stats").then(setStats).catch(() => setStats(null));
  }, [load]);

  if (error) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !me)
    return (
      <main id="main">
        <div className="skeleton" style={{ height: 220, borderRadius: "var(--radius)" }} />
      </main>
    );

  const seasons = stats?.seasons ?? [];

  return (
    <main id="main" className="pro">
      <ProfileHero me={me} seasons={seasons} tab={tab} onTab={setTab} onSaved={load} />

      {tab === "overview" && <Overview me={me} stats={stats} onSaved={load} />}
      {tab !== "overview" && (
        <CareerStats seasons={seasons} discipline={tab} name={me.name} />
      )}
    </main>
  );
}

/* ---------- The band across the top ---------- */

function ProfileHero({
  me,
  seasons,
  tab,
  onTab,
  onSaved,
}: {
  me: PublicUser;
  seasons: PlayerSeasonStats[];
  tab: Tab;
  onTab: (t: Tab) => void;
  onSaved: () => void;
}) {
  const main = (me.sport_profiles ?? []).find((p) => p.sport === me.primary_sport)
    ?? (me.sport_profiles ?? [])[0];
  // Whichever club they have played the most for — the one to name here.
  const club = useMemo(() => {
    const tally = new Map<string, number>();
    for (const s of seasons) {
      if (s.club_name) tally.set(s.club_name, (tally.get(s.club_name) ?? 0) + s.matches);
    }
    return [...tally.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? main?.team_name ?? null;
  }, [seasons, main]);

  const parts = me.name.trim().split(/\s+/);
  const first = parts.length > 1 ? parts.slice(0, -1).join(" ") : "";
  const last = parts[parts.length - 1] ?? me.name;

  return (
    <header className="pro-hero">
      <div className="pro-hero-body">
        <AvatarUploader me={me} onSaved={onSaved} />
        <div className="pro-id">
          {first && <p className="pro-first">{first}</p>}
          <h1 className="pro-last">{last}</h1>
          <div className="pro-meta">
            {club && <span>{club}</span>}
            {main?.skill_level && <span>{skillLabel(main.skill_level)}</span>}
            {main?.position && <span className="pro-role">{main.position}</span>}
          </div>
        </div>
      </div>
      <nav className="pro-tabs" aria-label="Profile sections">
        {(["overview", "batting", "bowling"] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            className={tab === t ? "on" : ""}
            aria-current={tab === t ? "page" : undefined}
            onClick={() => onTab(t)}
          >
            {t === "overview" ? "Overview" : t === "batting" ? "Batting" : "Bowling"}
          </button>
        ))}
      </nav>
    </header>
  );
}

/// The face, and the way to change it.
function AvatarUploader({ me, onSaved }: { me: PublicUser; onSaved: () => void }) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pick = async (file: File | undefined) => {
    if (!file) return;
    setBusy(true);
    setError(null);
    try {
      const user = await upload<PublicUser>("/me/avatar", file);
      saveUser(user);
      onSaved();
    } catch (err) {
      setError(readErr(err, "That picture would not upload"));
    } finally {
      setBusy(false);
      // Let the same file be chosen again after a failure.
      if (input.current) input.current.value = "";
    }
  };

  return (
    <div className="pro-face">
      <Avatar name={me.name} url={me.avatar_url} size={150} className="pro-face-img" />
      <button
        type="button"
        className="pro-face-btn"
        disabled={busy}
        onClick={() => input.current?.click()}
        aria-label={me.avatar_url ? "Change your photo" : "Add a photo"}
      >
        {busy ? <span className="spinner" /> : <Icon name="camera" size={16} />}
      </button>
      <input
        ref={input}
        type="file"
        // The server sniffs the real bytes; this only filters the picker.
        accept="image/jpeg,image/png,image/webp"
        hidden
        onChange={(e) => pick(e.target.files?.[0])}
      />
      {error && <p className="pro-face-error">{error}</p>}
    </div>
  );
}

/* ---------- Overview ---------- */

function Overview({
  me,
  stats,
  onSaved,
}: {
  me: PublicUser;
  stats: MeStats | null;
  onSaved: () => void;
}) {
  const profiles = me.sport_profiles ?? [];
  const seasons = stats?.seasons ?? [];
  const career = totals(seasons);

  return (
    <div className="pro-cols">
      <div className="pro-main">
        <Details me={me} onSaved={onSaved} />

        <div className="panel">
          <div className="panel-head">
            <h2>Sports you play</h2>
            <span className="tag grey">{profiles.length}</span>
          </div>
          <p className="muted">
            One card per sport. Each keeps its own position, standard and numbers, so
            adding a sport never disturbs the others.
          </p>
          {profiles.length === 0 && (
            <div className="empty">
              <Icon name="bat" size={28} />
              <p>No sports set up yet. Add the one you play most.</p>
            </div>
          )}
          {profiles.map((p) => (
            <SportCard
              key={p.sport}
              profile={p}
              isPrimary={p.sport === me.primary_sport}
              me={me}
              onSaved={onSaved}
            />
          ))}
          <AddSport me={me} onSaved={onSaved} />
        </div>
      </div>

      <aside className="pro-rail">
        <div className="panel">
          <h2>Career</h2>
          {seasons.length === 0 ? (
            <p className="muted">
              Nothing scored yet. Your numbers appear here as soon as you play a match
              somebody scored on Fishers.
            </p>
          ) : (
            <>
              <dl className="pro-figures">
                <div><dt>Matches</dt><dd className="num">{career.matches}</dd></div>
                <div><dt>Runs</dt><dd className="num">{career.runs}</dd></div>
                <div><dt>Wickets</dt><dd className="num">{career.wickets}</dd></div>
                <div><dt>Catches</dt><dd className="num">{career.catches}</dd></div>
              </dl>
              <p className="subtle">
                Across {seasons.length} season{seasons.length === 1 ? "" : "s"}, worked out
                from the ball-by-ball log.
              </p>
            </>
          )}
        </div>

        <div className="panel">
          <h2>Honours</h2>
          {(stats?.achievements ?? []).length === 0 ? (
            <div className="empty">
              <Icon name="trophy" size={24} />
              <p>Fifties, five-fors and the rest land here when you earn them.</p>
            </div>
          ) : (
            <ul className="pro-honours">
              {stats!.achievements.map((a) => (
                <li key={a.id}>
                  <span className="pro-honour-mark" aria-hidden>{a.icon ?? "★"}</span>
                  <span>
                    <strong>{a.title}</strong>
                    {a.description && <small>{a.description}</small>}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="panel">
          <h2>Season boards</h2>
          <p className="muted">Where you sit in your club&apos;s table, season by season.</p>
          <Link className="btn" href="/stats">
            <Icon name="chart" size={16} /> Season stats
          </Link>
        </div>
      </aside>
    </div>
  );
}

/* ---------- Batting and bowling ---------- */

/// Every season on record, filtered to one discipline.
///
/// Kept whole and separate on purpose: if these numbers ever sit behind a
/// subscription, this component is the thing to wrap.
function CareerStats({
  seasons,
  discipline,
  name,
}: {
  seasons: PlayerSeasonStats[];
  discipline: "batting" | "bowling";
  name: string;
}) {
  const years = useMemo(
    () => [...new Set(seasons.map((s) => s.season_year))].sort((a, b) => b - a),
    [seasons]
  );
  const [year, setYear] = useState<number | "all">("all");
  const shown = year === "all" ? seasons : seasons.filter((s) => s.season_year === year);
  const t = totals(shown);

  if (seasons.length === 0)
    return (
      <div className="panel pro-blank">
        <Icon name={discipline === "batting" ? "bat" : "ball"} size={32} />
        <h2>No {discipline} figures yet</h2>
        <p className="muted">
          These are worked out from matches scored on Fishers. Play one — or ask your
          scorer to record it here — and it shows up the same evening.
        </p>
        <Link className="btn primary" href="/matches">Find a match</Link>
      </div>
    );

  return (
    <div className="pro-stats">
      <div className="pro-stats-head">
        <h2>
          {name}&apos;s {discipline}
        </h2>
        {years.length > 1 && (
          <div className="chips" role="group" aria-label="Season">
            <button
              type="button"
              className={year === "all" ? "chip on" : "chip"}
              onClick={() => setYear("all")}
            >
              All
            </button>
            {years.map((y) => (
              <button
                key={y}
                type="button"
                className={year === y ? "chip on" : "chip"}
                onClick={() => setYear(y)}
              >
                {y}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* The four figures a player quotes, before any table. */}
      <dl className="pro-strip">
        {(discipline === "batting"
          ? [
              ["Runs", String(t.runs)],
              ["Innings", String(t.battingInnings)],
              ["Average", num(battingAverage(t), 2)],
              ["Strike rate", num(strikeRate(t), 2)],
            ]
          : [
              ["Wickets", String(t.wickets)],
              ["Overs", num(t.overs, 1)],
              ["Average", num(bowlingAverage(t), 2)],
              ["Economy", num(t.overs ? t.bowlingRuns / t.overs : null, 2)],
            ]
        ).map(([label, value]) => (
          <div key={label}>
            <dd className="num">{value}</dd>
            <dt>{label}</dt>
          </div>
        ))}
      </dl>

      <div className="pro-cols">
        <div className="panel pro-table">
        <div className="table-wrap">
        <table className="table">
          <thead>
            {discipline === "batting" ? (
              <tr>
                <th>Season</th><th>Club</th><th className="n">M</th><th className="n">Inns</th>
                <th className="n">NO</th><th className="n">Runs</th><th className="n">HS</th>
                <th className="n">Avg</th><th className="n">SR</th>
                <th className="n">4s</th><th className="n">6s</th>
              </tr>
            ) : (
              <tr>
                <th>Season</th><th>Club</th><th className="n">M</th><th className="n">Ov</th>
                <th className="n">Mdns</th><th className="n">Runs</th><th className="n">Wkts</th>
                <th className="n">Avg</th><th className="n">Econ</th>
              </tr>
            )}
          </thead>
          <tbody>
            {shown.map((s) => (
              <tr key={s.id}>
                <td className="num">{s.season_year}</td>
                <td>{s.club_name ?? "—"}</td>
                <td className="n num">{s.matches}</td>
                {discipline === "batting" ? (
                  <>
                    <td className="n num">{s.batting_innings}</td>
                    <td className="n num">{s.not_outs}</td>
                    <td className="n num">{s.runs}</td>
                    <td className="n num">{s.high_score ?? "—"}</td>
                    <td className="n num">{num(s.batting_average)}</td>
                    <td className="n num">{num(s.strike_rate)}</td>
                    <td className="n num">{s.fours}</td>
                    <td className="n num">{s.sixes}</td>
                  </>
                ) : (
                  <>
                    <td className="n num">{num(s.overs_bowled, 1)}</td>
                    <td className="n num">{s.maidens}</td>
                    <td className="n num">{s.bowling_runs}</td>
                    <td className="n num">{s.wickets}</td>
                    <td className="n num">{num(s.bowling_average)}</td>
                    <td className="n num">{num(economy(s))}</td>
                  </>
                )}
              </tr>
            ))}
          </tbody>
        </table>
        </div>
        </div>
        <Highlights rows={shown} discipline={discipline} />
      </div>
    </div>
  );
}

/// What a player actually remembers about their seasons — the best of them,
/// beside the table rather than buried in a column of it.
function Highlights({
  rows,
  discipline,
}: {
  rows: PlayerSeasonStats[];
  discipline: "batting" | "bowling";
}) {
  const t = totals(rows);
  const best = (pick: (s: PlayerSeasonStats) => number | null) =>
    rows.reduce<PlayerSeasonStats | null>((won, s) => {
      const v = pick(s);
      if (v === null) return won;
      return won === null || v > (pick(won) ?? -Infinity) ? s : won;
    }, null);

  const items =
    discipline === "batting"
      ? [
          ["Highest score", best((s) => s.high_score ?? null), (s: PlayerSeasonStats) => String(s.high_score)],
          ["Most runs in a season", best((s) => s.runs), (s: PlayerSeasonStats) => String(s.runs)],
          ["Best average", best((s) => s.batting_average ?? null), (s: PlayerSeasonStats) => num(s.batting_average)],
        ]
      : [
          ["Most wickets in a season", best((s) => s.wickets), (s: PlayerSeasonStats) => String(s.wickets)],
          // Lowest wins, so the ranking is inverted rather than a second helper.
          ["Best economy", best((s) => (economy(s) === null ? null : -economy(s)!)), (s: PlayerSeasonStats) => num(economy(s))],
          ["Most maidens", best((s) => s.maidens), (s: PlayerSeasonStats) => String(s.maidens)],
        ];

  return (
    <aside className="pro-rail">
      <div className="panel">
        <h2>Best of it</h2>
        <ul className="pro-best">
          {items.map(([label, row, show]) => (
            <li key={label as string}>
              <span>
                <strong>{label as string}</strong>
                {row ? <small>{(row as PlayerSeasonStats).season_year} season</small> : null}
              </span>
              <span className="num">
                {row ? (show as (s: PlayerSeasonStats) => string)(row as PlayerSeasonStats) : "—"}
              </span>
            </li>
          ))}
        </ul>
      </div>

      <div className="panel">
        <h2>{discipline === "batting" ? "Boundaries" : "In the field"}</h2>
        <dl className="pro-figures">
          {discipline === "batting" ? (
            <>
              <div><dt>Fours</dt><dd className="num">{rows.reduce((n, s) => n + s.fours, 0)}</dd></div>
              <div><dt>Sixes</dt><dd className="num">{rows.reduce((n, s) => n + s.sixes, 0)}</dd></div>
            </>
          ) : (
            <>
              <div><dt>Overs</dt><dd className="num">{num(t.overs, 1)}</dd></div>
              <div><dt>Maidens</dt><dd className="num">{rows.reduce((n, s) => n + s.maidens, 0)}</dd></div>
            </>
          )}
          <div><dt>Catches</dt><dd className="num">{t.catches}</dd></div>
          <div><dt>Matches</dt><dd className="num">{t.matches}</dd></div>
        </dl>
      </div>
    </aside>
  );
}

type Totals = ReturnType<typeof totals>;

/// Career figures are the sum of the seasons — averages are worked out from
/// those sums, never averaged from the seasons' own averages.
function totals(seasons: PlayerSeasonStats[]) {
  const add = (f: (s: PlayerSeasonStats) => number) => seasons.reduce((n, s) => n + f(s), 0);
  return {
    matches: add((s) => s.matches),
    runs: add((s) => s.runs),
    wickets: add((s) => s.wickets),
    catches: add((s) => s.catches + s.stumpings),
    battingInnings: add((s) => s.batting_innings),
    notOuts: add((s) => s.not_outs),
    ballsFaced: add((s) => s.balls_faced),
    overs: add((s) => s.overs_bowled),
    bowlingRuns: add((s) => s.bowling_runs),
  };
}

function battingAverage(t: Totals): number | null {
  const outs = t.battingInnings - t.notOuts;
  return outs > 0 ? t.runs / outs : null;
}

function strikeRate(t: Totals): number | null {
  return t.ballsFaced > 0 ? (t.runs / t.ballsFaced) * 100 : null;
}

function bowlingAverage(t: Totals): number | null {
  return t.wickets > 0 ? t.bowlingRuns / t.wickets : null;
}

/* ---------- Editing ---------- */

function Details({ me, onSaved }: { me: PublicUser; onSaved: () => void }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(me.name);
  const [phone, setPhone] = useState(me.phone ?? "");
  const [emergency, setEmergency] = useState(me.emergency_contact ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("PATCH", "/me", {
        name: name.trim(),
        phone: phone.trim() || null,
        emergency_contact: emergency.trim() || null,
      });
      setEditing(false);
      onSaved();
    } catch (err) {
      setError(readErr(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  if (!editing) {
    return (
      <div className="panel">
        <div className="panel-head">
          <h2>About {me.name.split(" ")[0]}</h2>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            Edit
          </button>
        </div>
        <dl className="pro-about">
          <div><dt>Name</dt><dd>{me.name}</dd></div>
          <div><dt>Email</dt><dd>{me.email || "—"}</dd></div>
          <div><dt>Mobile</dt><dd>{me.phone || "—"}</dd></div>
          <div><dt>Main sport</dt><dd>{me.primary_sport ? titleOf(me.primary_sport) : "—"}</dd></div>
          <div><dt>In an emergency</dt><dd>{me.emergency_contact || "—"}</dd></div>
        </dl>
      </div>
    );
  }

  return (
    <div className="panel">
      <h2>Your details</h2>
      <div className="setup-fields">
        <label>
          Name
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          Mobile
          <input
            type="tel"
            inputMode="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="07700 900123"
          />
        </label>
        <label>
          In an emergency
          <input
            value={emergency}
            onChange={(e) => setEmergency(e.target.value)}
            placeholder="Name and number"
          />
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !name.trim()} onClick={save}>
          {busy ? "Saving…" : "Save"}
        </button>
        <button className="btn" type="button" onClick={() => setEditing(false)}>Cancel</button>
      </div>
    </div>
  );
}

function SportCard({
  profile,
  isPrimary,
  me,
  onSaved,
}: {
  profile: SportProfile;
  isPrimary: boolean;
  me: PublicUser;
  onSaved: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<SportProfile>(profile);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const positions = SPORT_POSITIONS[profile.sport] ?? [];

  const write = async (profiles: SportProfile[], primary?: string) => {
    setBusy(true);
    setError(null);
    try {
      await api("PATCH", "/me", {
        sport_profiles: profiles,
        ...(primary ? { primary_sport: primary } : {}),
      });
      setEditing(false);
      onSaved();
    } catch (err) {
      setError(readErr(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  const others = (me.sport_profiles ?? []).filter((p) => p.sport !== profile.sport);

  if (!editing) {
    return (
      <div className="sport-card">
        <div className="sheet-head">
          <h3>
            {titleOf(profile.sport)}
            {isPrimary && <span className="tag gold">Main sport</span>}
          </h3>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            Edit
          </button>
        </div>
        <dl className="terms-summary">
          <div><dt>Position</dt><dd>{profile.position || "—"}</dd></div>
          <div><dt>Standard</dt><dd>{skillLabel(profile.skill_level)}</dd></div>
          {profile.team_name && <div><dt>Team</dt><dd>{profile.team_name}</dd></div>}
          {profile.years_playing != null && (
            <div><dt>Playing for</dt><dd className="num">{profile.years_playing} years</dd></div>
          )}
          {/* Whatever this sport measures, shown as it was stored. */}
          {Object.entries(profile.stats ?? {}).map(([k, v]) => (
            <div key={k}><dt>{k.replaceAll("_", " ")}</dt><dd className="num">{v}</dd></div>
          ))}
        </dl>
      </div>
    );
  }

  return (
    <div className="sport-card">
      <h3>{titleOf(profile.sport)}</h3>
      <div className="setup-fields">
        <label>
          Position
          {positions.length > 0 ? (
            <select
              value={draft.position ?? ""}
              onChange={(e) => setDraft({ ...draft, position: e.target.value })}
            >
              <option value="">—</option>
              {positions.map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          ) : (
            <input
              value={draft.position ?? ""}
              onChange={(e) => setDraft({ ...draft, position: e.target.value })}
              placeholder="However you'd describe it"
            />
          )}
        </label>
        <label>
          Standard
          <select
            value={draft.skill_level ?? ""}
            onChange={(e) => setDraft({ ...draft, skill_level: e.target.value })}
          >
            <option value="">—</option>
            {SKILL_LEVELS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
        </label>
        <label>
          Team
          <input
            value={draft.team_name ?? ""}
            onChange={(e) => setDraft({ ...draft, team_name: e.target.value })}
            placeholder="1st XI"
          />
        </label>
        <label>
          Years playing
          <input
            type="number"
            inputMode="numeric"
            value={draft.years_playing ?? ""}
            onChange={(e) =>
              setDraft({
                ...draft,
                years_playing: e.target.value === "" ? null : Number(e.target.value),
              })
            }
          />
        </label>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button
          className="btn primary"
          type="button"
          disabled={busy}
          onClick={() => write([...others, draft])}
        >
          {busy ? "Saving…" : "Save"}
        </button>
        {!isPrimary && (
          <button
            className="btn"
            type="button"
            disabled={busy}
            onClick={() => write([...others, draft], profile.sport)}
          >
            Save and make it my main sport
          </button>
        )}
        <button className="btn ghost" type="button" onClick={() => setEditing(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}

function AddSport({ me, onSaved }: { me: PublicUser; onSaved: () => void }) {
  const existing = (me.sport_profiles ?? []).map((p) => p.sport);
  const spare = SPORTS.filter((s) => !existing.includes(s));
  const [busy, setBusy] = useState(false);

  if (spare.length === 0) return null;

  const add = async (sport: string) => {
    setBusy(true);
    try {
      await api("PATCH", "/me", {
        sport_profiles: [...(me.sport_profiles ?? []), { sport }],
        // The first sport somebody adds is the one they lead with.
        ...(me.primary_sport ? {} : { primary_sport: sport }),
      });
      onSaved();
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <h3 className="sheet-sub">Add a sport</h3>
      <div className="squad-grid">
        {spare.map((s) => (
          <button
            key={s}
            type="button"
            className="squad-chip"
            disabled={busy}
            onClick={() => add(s)}
          >
            <Icon name="plus" size={14} />
            <span>{titleOf(s)}</span>
          </button>
        ))}
      </div>
    </>
  );
}

function titleOf(sport: string) {
  return sport.charAt(0).toUpperCase() + sport.slice(1);
}

