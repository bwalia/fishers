"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { readErr } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { adminUser, career, type AdminUserDetail } from "@/lib/admin";
import { useT } from "@/lib/i18n/provider";

/// Everything held about one person.
///
/// Laid out for the call: who they are and whether they can get in, first,
/// because that is what they have written in about. The cricket is further
/// down — interesting, rarely urgent.
export default function AdminUserPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
  const { id } = use(params);
  const authed = useRequireAuth();
  const [d, setD] = useState<AdminUserDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setD(await adminUser(id));
      setError(null);
    } catch (err) {
      setError(readErr(err, t("le.could_not_load_this_person")));
    }
  }, [id, t]);

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
            <Link href="/admin/users">{t("rest.people_back")}</Link> ·{" "}
            {t("rest.joined_on", { date: new Date(u.created_at).toLocaleDateString() })}
            {u.deleted_at &&
              t("rest.deleted_on", { date: new Date(u.deleted_at).toLocaleDateString() })}
          </p>
        </div>
        {u.deleted_at && <span className="tag warn">{t("rest.deleted")}</span>}
      </header>

      {/* Getting in comes first: it is why somebody writes in. */}
      <section className="panel">
        <h2><Icon name="lock" size={18} /> {t("rest.getting_in")}</h2>
        <div className="adm-cols">
          <div>
            <Field label={t("rest.email")} value={u.email ?? "—"} note={u.email && !u.email_verified ? t("rest.not_confirmed_note") : undefined} />
            <Field label={t("rest.phone")} value={u.phone ?? "—"} note={u.phone && !u.phone_verified ? t("rest.not_confirmed_note") : undefined} />
          </div>
          <div>
            <Field label={t("rest.password_set")} value={d.has_password ? t("rest.yes") : t("rest.no")} />
            <Field label={t("rest.google_linked")} value={d.has_google ? t("rest.yes") : t("rest.no")} />
            <Field label={t("rest.apple_linked")} value={d.has_apple ? t("rest.yes") : t("rest.no")} />
          </div>
          <div>
            <Field label={t("rest.signed_in_now")} value={String(u.clubs >= 0 ? d.active_sessions : 0)} />
            <Field label={t("rest.devices_on_push")} value={String(d.push_devices)} />
            <Field
              label={t("rest.last_seen")}
              value={u.last_seen ? new Date(u.last_seen).toLocaleString() : t("rest.never_lower")}
            />
          </div>
        </div>
        {!d.has_password && !d.has_google && !d.has_apple && (
          <p className="error">
            {t("rest.no_password_and_no_linked_account_this")}
          </p>
        )}
      </section>

      <section className="panel">
        <h2><Icon name="book" size={18} /> {t("rest.profile")}</h2>
        <div className="adm-cols">
          <div>
            <Field label={t("rest.primary_sport")} value={u.primary_sport ?? "—"} />
            <Field label={t("rest.position")} value={u.position_role ?? "—"} />
            <Field label={t("rest.standard")} value={u.skill_level ?? "—"} />
          </div>
          <div>
            <Field label={t("rest.came_to")} value={d.role_intent ?? "—"} />
            <Field
              label={t("rest.profile_finished")}
              value={d.profile_completed_at ? new Date(d.profile_completed_at).toLocaleDateString() : t("rest.not_yet")}
            />
            <Field label={t("rest.honours")} value={String(d.achievements)} />
          </div>
          <div>
            <Field label={t("rest.umpires_label")} value={d.umpires ? t("rest.yes") : t("rest.no")} note={d.umpire_note ?? undefined} />
            <Field label={t("rest.matches_umpired")} value={String(d.umpired)} />
            <Field
              label={t("rest.umpire_rating")}
              value={d.umpire_rating !== null ? t("rest.rating_from_n", { avg: d.umpire_rating.toFixed(1), n: d.umpire_reviews }) : t("rest.not_rated")}
            />
          </div>
        </div>
        <Sports profiles={d.sport_profiles} />
      </section>

      <section className="panel">
        <h2><Icon name="users" size={18} /> {t("rest.clubs")}</h2>
        {d.clubs.length === 0 ? (
          <p className="muted">{t("rest.not_in_any_club")}</p>
        ) : (
          <div className="adm-table-wrap">
            <table className="adm-table">
              <thead>
                <tr><th scope="col">{t("rest.club")}</th><th scope="col">{t("rest.role")}</th><th scope="col">{t("rest.status")}</th><th scope="col">{t("rest.joined")}</th></tr>
              </thead>
              <tbody>
                {d.clubs.map((club) => (
                  <tr key={club.club_id}>
                    <th scope="row">{club.club_name}</th>
                    <td>{club.role}{club.is_captain && t("rest.and_captain")}</td>
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
        <h2><Icon name="clock" size={18} /> {t("rest.turning_up")}</h2>
        {d.availability.invited === 0 ? (
          <p className="muted">{t("rest.never_been_asked_to_a_fixture")}</p>
        ) : (
          <div className="adm-grid">
            <Figure label={t("rest.asked")} value={d.availability.invited} />
            <Figure label={t("rest.said_yes")} value={d.availability.said_yes} of={answered} />
            <Figure label={t("rest.said_no")} value={d.availability.said_no} of={answered} />
            <Figure label={t("rest.never_answered")} value={d.availability.never_answered} of={d.availability.invited} />
            <Figure label={t("rest.selected")} value={d.availability.selected} />
            <Figure label={t("rest.turned_up")} value={d.availability.attended} of={d.availability.selected} />
          </div>
        )}
      </section>

      <section className="panel">
        <h2><Icon name="bat" size={18} /> {t("rest.cricket")}</h2>
        {d.seasons.length === 0 ? (
          <p className="muted">{t("rest.no_scorecard_has_their_name_on_it_yet")}</p>
        ) : (
          <>
            <div className="adm-grid">
              <Figure label={t("rest.matches")} value={c.matches} />
              <Figure label={t("rest.runs")} value={c.runs} />
              <Figure label={t("rest.average")} text={c.average === null ? "—" : c.average.toFixed(2)} />
              <Figure label={t("rest.strike_rate")} text={c.strikeRate === null ? "—" : c.strikeRate.toFixed(1)} />
              <Figure label={t("rest.high_score")} text={c.innings > 0 ? String(c.high) : "—"} />
              <Figure label={t("rest.wickets")} value={c.wickets} />
              <Figure label={t("rest.economy")} text={c.economy === null ? "—" : c.economy.toFixed(2)} />
              <Figure label={t("rest.catches")} value={c.catches + c.stumpings} />
            </div>
            <div className="adm-table-wrap">
              <table className="adm-table">
                <thead>
                  <tr>
                    <th scope="col">{t("sh.season")}</th><th scope="col">{t("rest.club")}</th>
                    <th scope="col" className="num">{t("sh.col_m")}</th><th scope="col" className="num">{t("sh.col_runs")}</th>
                    <th scope="col" className="num">{t("sh.col_hs")}</th><th scope="col" className="num">{t("sh.col_fours")}</th>
                    <th scope="col" className="num">{t("sh.col_sixes")}</th><th scope="col" className="num">{t("sh.col_wkts")}</th>
                    <th scope="col" className="num">{t("sh.col_overs")}</th><th scope="col" className="num">{t("rest.ct")}</th>
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
  const t = useT();
  const pct = of && of > 0 && value !== undefined ? Math.round((value / of) * 100) : null;
  return (
    <div className="adm-figure">
      <strong>{text ?? value?.toLocaleString()}</strong>
      <span className="muted">{label}</span>
      {pct !== null && <span className="adm-delta">{t("rest.pct_of_n", { pct, n: of! })}</span>}
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
