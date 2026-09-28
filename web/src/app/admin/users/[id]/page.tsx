"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { adminUser, career, type AdminUserDetail } from "@/lib/admin";

/// Everything held about one person.
///
/// Laid out for the call: who they are and whether they can get in, first,
/// because that is what they have written in about. The cricket is further
/// down — interesting, rarely urgent.
export default function AdminUserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const authed = useRequireAuth();
  const [d, setD] = useState<AdminUserDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setD(await adminUser(id));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load this person"));
    }
  }, [id]);

  useEffect(() => {
    if (authed) load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;
  if (error)
    return (
      <main id="main" className="adm">
        <p className="error">{error}</p>
      </main>
    );
  if (!d) return <main id="main" className="adm"><div className="skeleton" style={{ height: 300 }} /></main>;

  const u = d.user;
  const c = career(d.seasons);
  const answered = d.availability.invited - d.availability.never_answered;

  return (
    <main id="main" className="adm">
      <header className="adm-head">
        <div>
          <h1>{u.name}</h1>
          <p className="muted">
            <Link href="/admin/users">← People</Link> · joined{" "}
            {new Date(u.created_at).toLocaleDateString()}
            {u.deleted_at && ` · deleted ${new Date(u.deleted_at).toLocaleDateString()}`}
          </p>
        </div>
        {u.deleted_at && <span className="tag warn">Deleted</span>}
      </header>

      {/* Getting in comes first: it is why somebody writes in. */}
      <section className="panel">
        <h2><Icon name="lock" size={18} /> Getting in</h2>
        <div className="adm-cols">
          <div>
            <Field label="Email" value={u.email ?? "—"} note={u.email && !u.email_verified ? "not confirmed" : undefined} />
            <Field label="Phone" value={u.phone ?? "—"} note={u.phone && !u.phone_verified ? "not confirmed" : undefined} />
          </div>
          <div>
            <Field label="Password set" value={d.has_password ? "yes" : "no"} />
            <Field label="Google linked" value={d.has_google ? "yes" : "no"} />
            <Field label="Apple linked" value={d.has_apple ? "yes" : "no"} />
          </div>
          <div>
            <Field label="Signed in now" value={String(u.clubs >= 0 ? d.active_sessions : 0)} />
            <Field label="Devices on push" value={String(d.push_devices)} />
            <Field
              label="Last seen"
              value={u.last_seen ? new Date(u.last_seen).toLocaleString() : "never"}
            />
          </div>
        </div>
        {!d.has_password && !d.has_google && !d.has_apple && (
          <p className="error">
            No password and no linked account — this person has no way to sign in at all.
          </p>
        )}
      </section>

      <section className="panel">
        <h2><Icon name="book" size={18} /> Profile</h2>
        <div className="adm-cols">
          <div>
            <Field label="Primary sport" value={u.primary_sport ?? "—"} />
            <Field label="Position" value={u.position_role ?? "—"} />
            <Field label="Standard" value={u.skill_level ?? "—"} />
          </div>
          <div>
            <Field label="Came to" value={d.role_intent ?? "—"} />
            <Field
              label="Profile finished"
              value={d.profile_completed_at ? new Date(d.profile_completed_at).toLocaleDateString() : "not yet"}
            />
            <Field label="Honours" value={String(d.achievements)} />
          </div>
          <div>
            <Field label="Umpires" value={d.umpires ? "yes" : "no"} note={d.umpire_note ?? undefined} />
            <Field label="Matches umpired" value={String(d.umpired)} />
            <Field
              label="Umpire rating"
              value={d.umpire_rating !== null ? `${d.umpire_rating.toFixed(1)} from ${d.umpire_reviews}` : "not rated"}
            />
          </div>
        </div>
        <Sports profiles={d.sport_profiles} />
      </section>

      <section className="panel">
        <h2><Icon name="users" size={18} /> Clubs</h2>
        {d.clubs.length === 0 ? (
          <p className="muted">Not in any club.</p>
        ) : (
          <div className="adm-table-wrap">
            <table className="adm-table">
              <thead>
                <tr><th scope="col">Club</th><th scope="col">Role</th><th scope="col">Status</th><th scope="col">Joined</th></tr>
              </thead>
              <tbody>
                {d.clubs.map((club) => (
                  <tr key={club.club_id}>
                    <th scope="row">{club.club_name}</th>
                    <td>{club.role}{club.is_captain && " · captain"}</td>
                    <td>{club.status}</td>
                    <td>{club.joined_at ? new Date(club.joined_at).toLocaleDateString() : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Their own answer and what happened, side by side: somebody who always
          says yes and never turns up looks reliable until both are read. */}
      <section className="panel">
        <h2><Icon name="clock" size={18} /> Turning up</h2>
        {d.availability.invited === 0 ? (
          <p className="muted">Never been asked to a fixture.</p>
        ) : (
          <div className="adm-grid">
            <Figure label="Asked" value={d.availability.invited} />
            <Figure label="Said yes" value={d.availability.said_yes} of={answered} />
            <Figure label="Said no" value={d.availability.said_no} of={answered} />
            <Figure label="Never answered" value={d.availability.never_answered} of={d.availability.invited} />
            <Figure label="Selected" value={d.availability.selected} />
            <Figure label="Turned up" value={d.availability.attended} of={d.availability.selected} />
          </div>
        )}
      </section>

      <section className="panel">
        <h2><Icon name="bat" size={18} /> Cricket</h2>
        {d.seasons.length === 0 ? (
          <p className="muted">No scorecard has their name on it yet.</p>
        ) : (
          <>
            <div className="adm-grid">
              <Figure label="Matches" value={c.matches} />
              <Figure label="Runs" value={c.runs} />
              <Figure label="Average" text={c.average === null ? "—" : c.average.toFixed(2)} />
              <Figure label="Strike rate" text={c.strikeRate === null ? "—" : c.strikeRate.toFixed(1)} />
              <Figure label="High score" text={c.innings > 0 ? String(c.high) : "—"} />
              <Figure label="Wickets" value={c.wickets} />
              <Figure label="Economy" text={c.economy === null ? "—" : c.economy.toFixed(2)} />
              <Figure label="Catches" value={c.catches + c.stumpings} />
            </div>
            <div className="adm-table-wrap">
              <table className="adm-table">
                <thead>
                  <tr>
                    <th scope="col">Season</th><th scope="col">Club</th>
                    <th scope="col" className="num">M</th><th scope="col" className="num">Runs</th>
                    <th scope="col" className="num">HS</th><th scope="col" className="num">4s</th>
                    <th scope="col" className="num">6s</th><th scope="col" className="num">Wkts</th>
                    <th scope="col" className="num">Overs</th><th scope="col" className="num">Ct</th>
                  </tr>
                </thead>
                <tbody>
                  {d.seasons.map((s, i) => (
                    <tr key={`${s.season_year}-${s.sport}-${i}`}>
                      <th scope="row">{s.season_year}</th>
                      <td>{s.club_name ?? "—"}</td>
                      <td className="num">{s.matches}</td>
                      <td className="num">{s.runs}</td>
                      <td className="num">{s.high_score ?? "—"}</td>
                      <td className="num">{s.fours}</td>
                      <td className="num">{s.sixes}</td>
                      <td className="num">{s.wickets}</td>
                      <td className="num">{s.overs_bowled.toFixed(1)}</td>
                      <td className="num">{s.catches + s.stumpings}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </section>
    </main>
  );
}

function Field({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <p className="adm-row">
      <span>{label}</span>
      <b>
        {value}
        {note && <em className="adm-note"> {note}</em>}
      </b>
    </p>
  );
}

function Figure({ label, value, text, of }: { label: string; value?: number; text?: string; of?: number }) {
  const pct = of && of > 0 && value !== undefined ? Math.round((value / of) * 100) : null;
  return (
    <div className="adm-figure">
      <strong>{text ?? value?.toLocaleString()}</strong>
      <span className="muted">{label}</span>
      {pct !== null && <span className="adm-delta">{pct}% of {of}</span>}
    </div>
  );
}

/// The sport profiles as they filled them in. Shape is the app's, not this
/// page's, so anything unexpected is shown rather than dropped.
function Sports({ profiles }: { profiles: unknown }) {
  if (!Array.isArray(profiles) || profiles.length === 0) return null;
  return (
    <div className="adm-chips">
      {profiles.map((p, i) => {
        const o = (p ?? {}) as Record<string, unknown>;
        const bits = [o.sport, o.position, o.skill_level, o.team_name]
          .filter((v) => typeof v === "string" && v)
          .join(" · ");
        return <span key={i} className="chip">{bits || JSON.stringify(o)}</span>;
      })}
    </div>
  );
}
