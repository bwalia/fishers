"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  api,
  clearSession,
  readErr,
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
import { Umpiring } from "@/components/Umpiring";
import { PendingUmpireReviews } from "@/components/RateUmpires";
import { Icon } from "@/components/Icon";
import { Avatar } from "@/components/Avatar";
import { ShareProfile } from "@/components/ShareProfile";
import { ProfileStrength } from "@/components/ProfileStrength";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

type Tab = "overview" | "batting" | "bowling" | "umpiring";

/// A player's own page — the face, the numbers, the details.
///
/// Laid out the way a cricket profile is read rather than the way the record
/// is stored: the identity fills a band across the top, and everything below
/// is one of three tabs. The numbers come from the scoring log, so the batting
/// and bowling tabs are computed; the overview is what the player told us.
export default function ProfilePage() {
  const t = useT();
  const authed = useRequireAuth();
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
      setError(readErr(err, t("ld.could_not_load_your_profile")));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    if (!authed) return;
    load();
    // A player with no season on record is not an error — the tabs say so.
    api<MeStats>("GET", "/me/stats").then(setStats).catch(() => setStats(null));
  }, [load, authed]);

  if (!authed) return <main id="main" />;
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
      {tab === "umpiring" && (
        <>
          <PendingUmpireReviews />
          <Umpiring />
        </>
      )}
      {(tab === "batting" || tab === "bowling") && (
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
  const t = useT();
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
            {main?.skill_level && <span>{skillLabel(main.skill_level, t)}</span>}
            {main?.position && <span className="pro-role">{main.position}</span>}
          </div>
        </div>
      </div>
      <nav className="pro-tabs" aria-label={t("cl.profile_sections")}>
        {(["overview", "batting", "bowling", "umpiring"] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            className={tab === t ? "on" : ""}
            aria-current={tab === t ? "page" : undefined}
            onClick={() => onTab(t)}
          >
            {t === "overview"
              ? "Overview"
              : t === "batting"
                ? "Batting"
                : t === "bowling"
                  ? "Bowling"
                  : "Umpiring"}
          </button>
        ))}
      </nav>
    </header>
  );
}

/// The face, and the way to change it.
function AvatarUploader({ me, onSaved }: { me: PublicUser; onSaved: () => void }) {
  const t = useT();
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
      setError(readErr(err, t("ld.that_picture_would_not_upload")));
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
        aria-label={me.avatar_url ? t("ld.change_your_photo") : t("ld.add_a_photo")}
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
  const t = useT();
  const profiles = me.sport_profiles ?? [];
  const seasons = stats?.seasons ?? [];
  const career = totals(seasons);

  return (
    <div className="pro-cols">
      <div className="pro-main">
        <ProfileStrength user={me} onProfilePage />
        <Details me={me} onSaved={onSaved} />

        <PasswordSection />

        <div className="panel" id="share">
          <h2>{t("cl.send_your_profile_to_a_club")}</h2>
          <p className="muted">
            {t("cl.joining_a_new_club_send_the_secretary")}
          </p>
          <ShareProfile userId={me.id} />
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>{t("cl.sports_you_play")}</h2>
            <span className="tag grey">{profiles.length}</span>
          </div>
          <p className="muted">
            {t("cl.one_card_per_sport_each_keeps_its_own")}
          </p>
          {profiles.length === 0 && (
            <div className="empty">
              <Icon name="bat" size={28} />
              <p>{t("cl.no_sports_set_up_yet_add_the_one_you_p")}</p>
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
          <h2>{t("cl.career")}</h2>
          {seasons.length === 0 ? (
            <p className="muted">
              Nothing scored yet. Your numbers appear here as soon as you play a match
              somebody scored on {brand.name}.
            </p>
          ) : (
            <>
              <dl className="pro-figures">
                <div><dt>{t("cl.matches")}</dt><dd className="num">{career.matches}</dd></div>
                <div><dt>{t("cl.runs")}</dt><dd className="num">{career.runs}</dd></div>
                <div><dt>{t("cl.wickets")}</dt><dd className="num">{career.wickets}</dd></div>
                <div><dt>{t("cl.catches")}</dt><dd className="num">{career.catches}</dd></div>
              </dl>
              <p className="subtle">
                Across {seasons.length} season{seasons.length === 1 ? "" : "s"}, worked out
                from the ball-by-ball log.
              </p>
            </>
          )}
        </div>

        <div className="panel">
          <h2>{t("cl.honours")}</h2>
          {(stats?.achievements ?? []).length === 0 ? (
            <div className="empty">
              <Icon name="trophy" size={24} />
              <p>{t("cl.fifties_five_fors_and_the_rest_land_he")}</p>
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
          <h2>{t("cl.season_boards")}</h2>
          <p className="muted">{t("cl.where_you_sit_season_by_season")}</p>
          <Link className="btn" href="/stats">
            <Icon name="chart" size={16} /> {t("cl.season_stats")}
          </Link>
        </div>

        <DeleteAccount />
      </aside>
    </div>
  );
}

/// Leaving, for good.
///
/// Apple requires this to be reachable in the app for anything that lets you
/// create an account (App Store Review 5.1.1(v)), and it is the right thing to
/// offer anyway. Two steps rather than one button: the action cannot be undone
/// and a mis-tap should not end somebody's season.
/// A password, for people who sign in with Google and have none.
///
/// t("ld.sign_in_with_google") is one way in, and on the day Google is unreachable
/// or a client id is rotated wrongly it is no way in at all. This is the
/// second one. It is on everybody's profile rather than hidden behind an admin
/// flag, because everybody has the same problem — whoever runs the service
/// just has more to lose from it.
function PasswordSection() {
  const t = useT();
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api("POST", "/me/password", {
        // Absent rather than empty: the API only accepts a missing one for an
        // account that has no password at all.
        current: current || undefined,
        new_password: next,
      });
      setDone(true);
      setCurrent("");
      setNext("");
    } catch (err) {
      setError(readErr(err, t("ld.could_not_set_that")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel" id="password">
      <h2>{t("cl.password")}</h2>
      <p className="muted">
        {t("cl.a_second_way_in_for_when_google_is_not")}
      </p>
      <form className="pwd-form" onSubmit={submit}>
        <label htmlFor="pwd-current">
          {t("cl.current_password")} <span className="muted">{t("cl.leave_blank_if_never_set")}</span>
        </label>
        <input
          id="pwd-current"
          type="password"
          autoComplete="current-password"
          value={current}
          onChange={(e) => setCurrent(e.target.value)}
        />
        <label htmlFor="pwd-new">{t("cl.new_password")}</label>
        <input
          id="pwd-new"
          type="password"
          autoComplete="new-password"
          minLength={8}
          required
          value={next}
          onChange={(e) => setNext(e.target.value)}
        />
        <button className="btn primary" disabled={busy || next.length < 8}>
          {busy ? t("ld.saving") : t("ld.set_password")}
        </button>
      </form>
      {done && <p className="ok-note">{t("cl.set_other_sessions_have_been_signed_ou")}</p>}
      {error && <p className="error">{error}</p>}
    </div>
  );
}

function DeleteAccount() {
  const t = useT();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const remove = async () => {
    setBusy(true);
    setError(null);
    try {
      await api<void>("POST", "/me/delete", { password: password || null });
      clearSession();
      router.replace("/");
    } catch (err) {
      setError(readErr(err, t("cl.could_not_delete_the_account")));
      setBusy(false);
    }
  };

  // Addressable: the footer and the terms page both link straight here.
  return (
    <div className="panel danger-panel" id="delete">
      <h2>{t("cl.delete_account")}</h2>
      {!open ? (
        <>
          <p className="muted">
            {t("cl.delete_removes")}{" "}
            <Link href="/privacy">{t("cl.what_that_means")}</Link>.
          </p>
          <button className="btn" type="button" onClick={() => setOpen(true)}>
            {t("cl.delete_account")}
          </button>
        </>
      ) : (
        <>
          <p className="muted">
            {t("cl.this_cannot_be_undone_type_your_passwo")}
          </p>
          <input
            type="password"
            autoComplete="current-password"
            placeholder={t("cl.your_password")}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          {error && <p className="error">{error}</p>}
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn danger" type="button" disabled={busy} onClick={remove}>
              {busy ? t("ld.deleting") : t("ld.delete_my_account")}
            </button>
            <button
              className="btn"
              type="button"
              disabled={busy}
              onClick={() => {
                setOpen(false);
                setPassword("");
                setError(null);
              }}
            >
              Cancel
            </button>
          </div>
        </>
      )}
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
  const t = useT();
  const years = useMemo(
    () => [...new Set(seasons.map((s) => s.season_year))].sort((a, b) => b - a),
    [seasons]
  );
  const [year, setYear] = useState<number | "all">("all");
  const shown = year === "all" ? seasons : seasons.filter((s) => s.season_year === year);
  const sum = totals(shown);

  if (seasons.length === 0)
    return (
      <div className="panel pro-blank">
        <Icon name={discipline === "batting" ? "bat" : "ball"} size={32} />
        <h2>{discipline === "batting" ? t("cl.no_batting_figures_yet") : t("cl.no_bowling_figures_yet")}</h2>
        <p className="muted">
          {t("cl.figures_from_matches_scored", { brand: brand.name })}
        </p>
        <Link className="btn primary" href="/matches">{t("cl.find_a_match")}</Link>
      </div>
    );

  return (
    <div className="pro-stats">
      <div className="pro-stats-head">
        <h2>
          {name}&apos;s {discipline}
        </h2>
        {years.length > 1 && (
          <div className="chips" role="group" aria-label={t("cl.season")}>
            <button
              type="button"
              className={year === "all" ? "chip on" : "chip"}
              onClick={() => setYear("all")}
            >
              {t("cl.all")}
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
              [t("cl.runs"), String(sum.runs)],
              [t("cl.innings"), String(sum.battingInnings)],
              [t("cl.average"), num(battingAverage(sum), 2)],
              [t("cl.strike_rate"), num(strikeRate(sum), 2)],
            ]
          : [
              [t("cl.wickets"), String(sum.wickets)],
              [t("cl.overs"), num(sum.overs, 1)],
              [t("cl.average"), num(bowlingAverage(sum), 2)],
              [t("cl.economy"), num(sum.overs ? sum.bowlingRuns / sum.overs : null, 2)],
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
                <th>{t("cl.season")}</th><th>{t("cl.club")}</th><th className="n">{t("cl.m")}</th><th className="n">{t("cl.inns")}</th>
                <th className="n">{t("cl.no")}</th><th className="n">{t("cl.runs")}</th><th className="n">{t("cl.hs")}</th>
                <th className="n">{t("cl.avg")}</th><th className="n">{t("cl.sr")}</th>
                <th className="n">4s</th><th className="n">6s</th>
              </tr>
            ) : (
              <tr>
                <th>{t("cl.season")}</th><th>Club</th><th className="n">M</th><th className="n">{t("cl.ov")}</th>
                <th className="n">{t("cl.mdns")}</th><th className="n">Runs</th><th className="n">{t("cl.wkts")}</th>
                <th className="n">{t("cl.avg")}</th><th className="n">Econ</th>
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
  const t = useT();
  const sum = totals(rows);
  const best = (pick: (s: PlayerSeasonStats) => number | null) =>
    rows.reduce<PlayerSeasonStats | null>((won, s) => {
      const v = pick(s);
      if (v === null) return won;
      return won === null || v > (pick(won) ?? -Infinity) ? s : won;
    }, null);

  const items =
    discipline === "batting"
      ? [
          [t("ld.highest_score"), best((s) => s.high_score ?? null), (s: PlayerSeasonStats) => String(s.high_score)],
          [t("ld.most_runs_in_a_season"), best((s) => s.runs), (s: PlayerSeasonStats) => String(s.runs)],
          [t("ld.best_average"), best((s) => s.batting_average ?? null), (s: PlayerSeasonStats) => num(s.batting_average)],
        ]
      : [
          [t("ld.most_wickets_in_a_season"), best((s) => s.wickets), (s: PlayerSeasonStats) => String(s.wickets)],
          // Lowest wins, so the ranking is inverted rather than a second helper.
          [t("ld.best_economy"), best((s) => (economy(s) === null ? null : -economy(s)!)), (s: PlayerSeasonStats) => num(economy(s))],
          [t("ld.most_maidens"), best((s) => s.maidens), (s: PlayerSeasonStats) => String(s.maidens)],
        ];

  return (
    <aside className="pro-rail">
      <div className="panel">
        <h2>{t("cl.best_of_it")}</h2>
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
        <h2>{discipline === "batting" ? t("ld.boundaries") : t("ld.in_the_field")}</h2>
        <dl className="pro-figures">
          {discipline === "batting" ? (
            <>
              <div><dt>{t("cl.fours")}</dt><dd className="num">{rows.reduce((n, s) => n + s.fours, 0)}</dd></div>
              <div><dt>{t("cl.sixes")}</dt><dd className="num">{rows.reduce((n, s) => n + s.sixes, 0)}</dd></div>
            </>
          ) : (
            <>
              <div><dt>Overs</dt><dd className="num">{num(sum.overs, 1)}</dd></div>
              <div><dt>{t("cl.maidens")}</dt><dd className="num">{rows.reduce((n, s) => n + s.maidens, 0)}</dd></div>
            </>
          )}
          <div><dt>{t("cl.catches")}</dt><dd className="num">{sum.catches}</dd></div>
          <div><dt>{t("cl.matches")}</dt><dd className="num">{sum.matches}</dd></div>
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
  const t = useT();
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
      setError(readErr(err, t("ld.could_not_save_that")));
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
            {t("cl.edit")}
          </button>
        </div>
        <dl className="pro-about">
          <div><dt>{t("cl.name")}</dt><dd>{me.name}</dd></div>
          <div><dt>{t("cl.email")}</dt><dd>{me.email || "—"}</dd></div>
          <div><dt>{t("cl.mobile")}</dt><dd>{me.phone || "—"}</dd></div>
          <div><dt>{t("cl.main_sport")}</dt><dd>{me.primary_sport ? titleOf(me.primary_sport) : "—"}</dd></div>
          <div><dt>{t("cl.in_an_emergency")}</dt><dd>{me.emergency_contact || "—"}</dd></div>
        </dl>
      </div>
    );
  }

  return (
    <div className="panel">
      <h2>{t("cl.your_details")}</h2>
      <div className="setup-fields">
        <label>
          {t("cl.name")}
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          {t("cl.mobile")}
          <input
            type="tel"
            inputMode="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder={t("cl.07700_900123")}
          />
        </label>
        <label>
          {t("cl.in_an_emergency")}
          <input
            value={emergency}
            onChange={(e) => setEmergency(e.target.value)}
            placeholder={t("cl.name_and_number")}
          />
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !name.trim()} onClick={save}>
          {busy ? t("la.saving") : t("lc.save")}
        </button>
        <button className="btn" type="button" onClick={() => setEditing(false)}>{t("sc.cancel")}</button>
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
  const t = useT();
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
      setError(readErr(err, t("ld.could_not_save_that")));
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
            {isPrimary && <span className="tag gold">{t("cl.main_sport")}</span>}
          </h3>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            {t("cl.edit")}
          </button>
        </div>
        <dl className="terms-summary">
          <div><dt>{t("cl.position")}</dt><dd>{profile.position || "—"}</dd></div>
          <div><dt>{t("cl.standard")}</dt><dd>{skillLabel(profile.skill_level, t)}</dd></div>
          {profile.team_name && <div><dt>{t("cl.team")}</dt><dd>{profile.team_name}</dd></div>}
          {profile.years_playing != null && (
            <div><dt>{t("cl.playing_for")}</dt><dd className="num">{t("cl.n_years", { n: profile.years_playing })}</dd></div>
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
              placeholder={t("cl.however_you_d_describe_it")}
            />
          )}
        </label>
        <label>
          {t("cl.standard")}
          <select
            value={draft.skill_level ?? ""}
            onChange={(e) => setDraft({ ...draft, skill_level: e.target.value })}
          >
            <option value="">—</option>
            {SKILL_LEVELS.map((s) => <option key={s.value} value={s.value}>{t(s.label)}</option>)}
          </select>
        </label>
        <label>
          {t("cl.team")}
          <input
            value={draft.team_name ?? ""}
            onChange={(e) => setDraft({ ...draft, team_name: e.target.value })}
            placeholder={t("cl.1st_xi")}
          />
        </label>
        <label>
          {t("cl.years_playing")}
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
          {busy ? t("la.saving") : t("lc.save")}
        </button>
        {!isPrimary && (
          <button
            className="btn"
            type="button"
            disabled={busy}
            onClick={() => write([...others, draft], profile.sport)}
          >
            {t("cl.save_and_make_it_my_main_sport")}
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
  const t = useT();
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
      <h3 className="sheet-sub">{t("cl.add_a_sport")}</h3>
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

