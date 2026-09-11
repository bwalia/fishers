"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  getStoredUser,
  readErr,
  skillLabel,
  type TeammateProfile,
} from "@/lib/api";
import { num, type PlayerSeasonStats } from "@/lib/stats";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { MessageButton } from "@/components/MessageButton";

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
  const { id } = use(params);
  const [player, setPlayer] = useState<TeammateProfile | null>(null);
  const [seasons, setSeasons] = useState<PlayerSeasonStats[]>([]);
  const [honours, setHonours] = useState<Achievement[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see this player.");
      setLoading(false);
      return;
    }
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
        setError(readErr(err, "Could not load this player"));
      } finally {
        setLoading(false);
      }
    })();
  }, [id]);

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
              {main?.skill_level && <span>{skillLabel(main.skill_level)}</span>}
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
              <h2>Nothing scored yet</h2>
              <p className="muted">
                {player.name.split(" ")[0]}&apos;s figures appear here once they play a
                match somebody scored on Fishers.
              </p>
            </div>
          ) : (
            <>
              <div className="panel">
                <h2>Career</h2>
                <dl className="pro-strip">
                  <div><dd className="num">{total((s) => s.matches)}</dd><dt>Matches</dt></div>
                  <div><dd className="num">{runs}</dd><dt>Runs</dt></div>
                  <div>
                    <dd className="num">{outs > 0 ? num(runs / outs) : "—"}</dd>
                    <dt>Average</dt>
                  </div>
                  <div><dd className="num">{wickets}</dd><dt>Wickets</dt></div>
                </dl>
              </div>

              <div className="panel pro-table">
                <h2>Season by season</h2>
                <div className="table-wrap">
                  <table className="table">
                    <thead>
                      <tr>
                        <th>Season</th><th>Club</th>
                        <th className="n">M</th><th className="n">Runs</th>
                        <th className="n">HS</th><th className="n">Avg</th>
                        <th className="n">Wkts</th><th className="n">Econ</th>
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
              <h2>With the ball</h2>
              <dl className="pro-figures">
                <div><dt>Wickets</dt><dd className="num">{wickets}</dd></div>
                <div><dt>Overs</dt><dd className="num">{num(overs, 1)}</dd></div>
                <div>
                  <dt>Average</dt>
                  <dd className="num">{wickets ? num(bowlingRuns / wickets) : "—"}</dd>
                </div>
                <div>
                  <dt>Economy</dt>
                  <dd className="num">{overs ? num(bowlingRuns / overs) : "—"}</dd>
                </div>
              </dl>
            </div>
          )}

          <div className="panel">
            <h2>Honours</h2>
            {honours.length === 0 ? (
              <p className="muted">None yet.</p>
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
            <h2>You both play for</h2>
            <p className="muted">
              {player.shared_clubs.length > 0
                ? player.shared_clubs.join(", ")
                : "This is your own profile."}
            </p>
            <Link className="btn" href="/clubs">
              <Icon name="users" size={16} /> Your clubs
            </Link>
          </div>
        </aside>
      </div>
    </main>
  );
}
