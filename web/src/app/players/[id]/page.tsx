"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  getStoredUser,
  readErr,
  skillLabel,
  type TeammateProfile,
} from "@/lib/api";
import { num, type PlayerSeasonStats } from "@/lib/stats";
import { Avatar } from "@/components/Avatar";
import { Umpiring } from "@/components/Umpiring";
import { Icon } from "@/components/Icon";
import { MessageButton } from "@/components/MessageButton";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

type Achievement = {
  id: string;
  title: string;
  description?: string | null;
  icon?: string | null;
};

/// Somebody else's record.
///
/// The same figures as your own profile, worked out the same way — career
/// totals are the sum of the seasons and averages come from those sums, never
/// from averaging the seasons' averages. What is *not* here is their contact
/// details: the API does not send them, because being in the same club is not
/// consent to hand over a phone number.
export default function PlayerPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
  const { id } = use(params);
  const authed = useRequireAuth();
  const [player, setPlayer] = useState<TeammateProfile | null>(null);
  const [seasons, setSeasons] = useState<PlayerSeasonStats[]>([]);
  const [honours, setHonours] = useState<Achievement[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!authed) return;
    (async () => {
      try {
        const who = await api<TeammateProfile>("GET", `/users/${id}`);
        setPlayer(who);
        // A player with nothing scored is not an error, and neither is one
        // with no honours — the page just says so.
        const [s, a] = await Promise.all([
          api<PlayerSeasonStats[]>("GET", `/users/${id}/stats`).catch(() => []),
          api<Achievement[]>("GET", `/users/${id}/achievements`).catch(() => []),
        ]);
        setSeasons(s);
        setHonours(a);
        setError(null);
      } catch (err) {
        setError(readErr(err, t("le.could_not_load_this_player")));
      } finally {
        setLoading(false);
      }
    })();
  }, [authed, id, t]);

  if (!authed) return <main id="main" />;
  if (error) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !player)
    return <main id="main"><div className="skeleton" style={{ height: 260 }} /></main>;

  const total = (pick: (s: PlayerSeasonStats) => number) =>
    seasons.reduce((n, s) => n + pick(s), 0);
  const runs = total((s) => s.runs);
  const outs = total((s) => s.batting_innings) - total((s) => s.not_outs);
  const wickets = total((s) => s.wickets);
  const bowlingRuns = total((s) => s.bowling_runs);
  const overs = total((s) => s.overs_bowled);

  const parts = player.name.trim().split(/\s+/);
  const first = parts.length > 1 ? parts.slice(0, -1).join(" ") : "";
  const last = parts[parts.length - 1] ?? player.name;
  const main =
    player.sport_profiles.find((p) => p.sport === player.primary_sport)
    ?? player.sport_profiles[0];

  return (
    <main id="main" className="pro">
      <header className="pro-hero">
        <div className="pro-hero-body">
          <Avatar
            name={player.name}
            url={player.avatar_url}
            size={120}
            className="pro-face-img"
          />
          <div className="pro-id">
            {first && <p className="pro-first">{first}</p>}
            <h1 className="pro-last">{last}</h1>
            <div className="pro-meta">
              {player.shared_clubs[0] && <span>{player.shared_clubs[0]}</span>}
              {main?.skill_level && <span>{skillLabel(main.skill_level, t)}</span>}
              {(main?.position ?? player.position_role) && (
                <span className="pro-role">{main?.position ?? player.position_role}</span>
              )}
            </div>
            {player.id !== getStoredUser()?.id && (
              <div className="pro-actions">
                <MessageButton userId={player.id} name={player.name} />
              </div>
            )}
          </div>
        </div>
      </header>

      <div className="pro-cols">
        <div className="pro-main">
          {seasons.length === 0 ? (
            <div className="panel pro-blank">
              <Icon name="bat" size={32} />
              <h2>{t("cl.nothing_scored_yet")}</h2>
              <p className="muted">
                {player.name.split(" ")[0]}&apos;s figures appear here once they play a
                match somebody scored on {brand.name}.
              </p>
            </div>
          ) : (
            <>
              <div className="panel">
                <h2>{t("cl.career")}</h2>
                <dl className="pro-strip">
                  <div><dd className="num">{total((s) => s.matches)}</dd><dt>{t("cl.matches")}</dt></div>
                  <div><dd className="num">{runs}</dd><dt>Runs</dt></div>
                  <div>
                    <dd className="num">{outs > 0 ? num(runs / outs) : "—"}</dd>
                    <dt>{t("cl.average")}</dt>
                  </div>
                  <div><dd className="num">{wickets}</dd><dt>{t("cl.wickets")}</dt></div>
                </dl>
              </div>

              <div className="panel pro-table">
                <h2>{t("cl.season_by_season")}</h2>
                <div className="table-wrap">
                  <table className="table">
                    <thead>
                      <tr>
                        <th>{t("cl.season")}</th><th>{t("cl.club")}</th>
                        <th className="n">{t("cl.m")}</th><th className="n">{t("cl.runs")}</th>
                        <th className="n">{t("cl.hs")}</th><th className="n">{t("cl.avg")}</th>
                        <th className="n">{t("cl.wkts")}</th><th className="n">Econ</th>
                      </tr>
                    </thead>
                    <tbody>
                      {seasons.map((s) => (
                        <tr key={s.id}>
                          <td className="num">{s.season_year}</td>
                          <td>{s.club_name ?? "—"}</td>
                          <td className="n num">{s.matches}</td>
                          <td className="n num">{s.runs}</td>
                          <td className="n num">{s.high_score ?? "—"}</td>
                          <td className="n num">{num(s.batting_average)}</td>
                          <td className="n num">{s.wickets}</td>
                          <td className="n num">
                            {num(s.overs_bowled ? s.bowling_runs / s.overs_bowled : null)}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </>
          )}
        </div>

        <aside className="pro-rail">
          {seasons.length > 0 && (
            <div className="panel">
              <h2>{t("cl.with_the_ball")}</h2>
              <dl className="pro-figures">
                <div><dt>{t("cl.wickets")}</dt><dd className="num">{wickets}</dd></div>
                <div><dt>Overs</dt><dd className="num">{num(overs, 1)}</dd></div>
                <div>
                  <dt>{t("cl.average")}</dt>
                  <dd className="num">{wickets ? num(bowlingRuns / wickets) : "—"}</dd>
                </div>
                <div>
                  <dt>{t("cl.economy")}</dt>
                  <dd className="num">{overs ? num(bowlingRuns / overs) : "—"}</dd>
                </div>
              </dl>
            </div>
          )}

          <div className="panel">
            <h2>{t("cl.honours")}</h2>
            {honours.length === 0 ? (
              <p className="muted">{t("cl.none_yet")}</p>
            ) : (
              <ul className="pro-honours">
                {honours.map((a) => (
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
            <Umpiring userId={player.id} name={player.name} />
          </div>

          <div className="panel">
            <h2>{t("cl.you_both_play_for")}</h2>
            <p className="muted">
              {player.shared_clubs.length > 0
                ? player.shared_clubs.join(", ")
                : t("le.this_is_your_own_profile")}
            </p>
            <Link className="btn" href="/clubs">
              <Icon name="users" size={16} /> {t("cl.your_clubs")}
            </Link>
          </div>
        </aside>
      </div>
    </main>
  );
}
