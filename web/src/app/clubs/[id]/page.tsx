"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  api,
  readErr,
  getStoredUser,
  roleLabel,
  roleChoice,
  CLUB_ROLES,
  ROLE_CHOICES,
  money,
  NO_ICON_PLAYER,
  SPORTS,
  type Club,
  type ClubMemberRow,
  type Invite,
  type MyRole,
  type QrCode,
  type ClubPageSettings,
  type ClubSettings,
  type OutstandingFees,
  type TeamMemberRow,
  type Venue,
  type Team,
} from "@/lib/api";
import { AddByLink } from "@/components/AddByLink";
import { ClubSetup } from "@/components/ClubSetup";
import { MessageButton } from "@/components/MessageButton";
import { Icon } from "@/components/Icon";
import { Avatar } from "@/components/Avatar";
import { QrCard } from "@/components/QrCard";
import { copyText } from "@/lib/clipboard";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

export default function ClubPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
  const { id } = use(params);
  const authed = useRequireAuth();
  const [club, setClub] = useState<Club | null>(null);
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [venues, setVenues] = useState<Venue[]>([]);
  // Set by the redirect from t("lc.create_club"): the welcome shows once, and the
  // flag comes off the address so a refresh does not show it again.
  const [welcome, setWelcome] = useState(false);
  const [myRole, setMyRole] = useState<MyRole | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const me = getStoredUser();
  // The API decides; the page only asks. Everyone else sees the roster
  // read-only.
  const isSecretary = myRole?.is_secretary ?? false;

  const load = useCallback(async () => {
    try {
      const [c, m, t, v, role] = await Promise.all([
        api<Club>("GET", `/clubs/${id}`),
        api<ClubMemberRow[]>("GET", `/clubs/${id}/members`),
        api<Team[]>("GET", `/clubs/${id}/teams`).catch(() => []),
        api<Venue[]>("GET", `/clubs/${id}/venues`).catch(() => []),
        api<MyRole>("GET", `/clubs/${id}/my-role`),
      ]);
      setClub(c);
      setMembers(m);
      setTeams(t);
      setVenues(v);
      setMyRole(role);
    } catch (err) {
      setError(readErr(err, t("lc.could_not_load_the_club")));
    } finally {
      setLoading(false);
    }
  }, [id, t]);

  useEffect(() => {
    const url = new URL(window.location.href);
    if (url.searchParams.get("welcome") === "1") {
      setWelcome(true);
      url.searchParams.delete("welcome");
      window.history.replaceState(null, "", url.pathname + url.search + url.hash);
    }
  }, []);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  // A link to a section (#members, #public-page) arrives before the section
  // exists: this page and the panels below it each load their own data. So
  // go to it once it is there, and again if a panel above pushes it down,
  // until it holds still.
  useEffect(() => {
    const target = window.location.hash.slice(1);
    if (loading || !target) return;
    let last: number | null = null;
    let ticks = 0;
    const timer = window.setInterval(() => {
      const el = document.getElementById(target);
      const top = el ? Math.round(el.getBoundingClientRect().top) : null;
      if (el && top !== last) el.scrollIntoView({ block: "start" });
      if ((el && top === last) || ++ticks > 20) window.clearInterval(timer);
      last = el ? Math.round(el.getBoundingClientRect().top) : null;
    }, 150);
    return () => window.clearInterval(timer);
  }, [loading]);

  if (!authed) return <main id="main" />;
  if (error) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !club)
    return <main id="main"><div className="panel"><div className="skeleton" style={{ height: 80 }} /></div></main>;

  return (
    <main id="main">
      <section className="hero">
        <p className="muted"><Link href="/clubs">{t("cl.all_clubs_back")}</Link></p>
        <h1>{club.name}</h1>
        <p>{club.description || t("lc.no_description_yet")}</p>
        <div className="hero-tags">
          {club.sport_types.map((s) => <span className="tag" key={s}>{s}</span>)}
          {myRole && (
            <span className="tag gold">
              {myRole.display_name}
              {members.find((m) => m.user_id === me?.id)?.is_captain && myRole.is_secretary ? " & captain" : ""}
            </span>
          )}
        </div>
      </section>

      {/* What the club is for: a match, as soon as there is anyone to play. */}
      {club.sport_types.includes("cricket") &&
        (isSecretary || myRole?.permissions.includes("score_match")) && (
          <div className="panel instant-start">
            <div>
              <h2>{t("cl.start_a_match")}</h2>
              <p className="muted">{t("cl.name_the_opposition_and_start_scoring")}</p>
            </div>
            <Link className="btn primary" href={`/score?new=1&club=${id}`}>
              <Icon name="bat" size={16} /> {t("cl.start_a_match")}
            </Link>
          </div>
        )}

      {isSecretary && (
        <ClubSetup
          clubId={id}
          clubName={club.name}
          members={members}
          venues={venues}
          welcome={welcome}
        />
      )}

      <Members
        clubId={id}
        members={members}
        isSecretary={isSecretary}
        // A captain can bring a player into their team from a shared link,
        // as a secretary can into the club.
        canAddByLink={
          !!myRole && (myRole.permissions.includes("invite_to_club") || myRole.permissions.includes("invite_to_team"))
        }
        meId={me?.id}
        onChanged={load}
      />

      <Teams clubId={id} teams={teams} isSecretary={isSecretary} onChanged={load} />

      <Venues clubId={id} venues={venues} canEdit={isSecretary} onChanged={load} />

      {isSecretary && <Settings clubId={id} />}

      {isSecretary && <Fees clubId={id} />}

      {isSecretary && <PublicPage clubId={id} clubName={club.name} members={members} />}

      <Codes clubId={id} teams={teams} />
    </main>
  );
}

function Members({
  clubId,
  members,
  isSecretary,
  canAddByLink,
  meId,
  onChanged,
}: {
  clubId: string;
  members: ClubMemberRow[];
  isSecretary: boolean;
  canAddByLink: boolean;
  meId?: string;
  onChanged: () => void;
}) {
  const t = useT();
  const [filter, setFilter] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // A big club's roster is long, so it is searchable rather than scrolled.
  const shown = useMemo(() => {
    const term = filter.trim().toLowerCase();
    if (!term) return members;
    return members.filter(
      (m) =>
        m.name.toLowerCase().includes(term) ||
        (m.email ?? "").toLowerCase().includes(term) ||
        (m.phone ?? "").includes(term)
    );
  }, [members, filter]);

  // The API refuses to strip the last one; the page greys it out first so
  // nobody has to read an error to find that out.
  const secretaries = members.filter(
    (m) => m.role === "club_admin" || m.role === "super_admin"
  ).length;

  /// `choice` is a role, or "club_admin+captain" for a secretary who captains.
  const setRole = async (userId: string, choice: string) => {
    setBusy(userId);
    setError(null);
    const [role, captain] = choice.split("+");
    try {
      await api("PATCH", `/clubs/${clubId}/members/${userId}`, { role, captain: captain === "captain" });
      onChanged();
    } catch (err) {
      setError(readErr(err, t("lc.could_not_change_that_role")));
    } finally {
      setBusy(null);
    }
  };

  const remove = async (userId: string, name: string) => {
    if (!confirm(t("cl.remove_from_the_club", { name }))) return;
    setBusy(userId);
    setError(null);
    try {
      await api("DELETE", `/clubs/${clubId}/members/${userId}`);
      onChanged();
    } catch (err) {
      setError(readErr(err, t("lc.could_not_remove_them")));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel" id="members">
      <div className="panel-head">
        <h2>{t("cl.members")}</h2>
        <span className="tag grey">{members.length}</span>
        {isSecretary && (
          <Link className="btn ghost sm" href={`/clubs/${clubId}/people`} style={{ marginLeft: "auto" }}>
            Bulk invite &amp; roles →
          </Link>
        )}
      </div>
      <p className="muted">
        {t("cl.role_explainer", {
          allowed: t("cl.a_role_is_what_somebody_is_allowed_to"),
          run: t("cl.run"),
          both: t("cl.secretary_and_captain"),
        })}
      </p>

      {isSecretary && <AddMember clubId={clubId} onAdded={onChanged} />}
      {canAddByLink && <AddByLink clubId={clubId} />}

      {members.length > 8 && (
        <label>
          {t("cl.find_someone")}
          <input
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder={t("cl.name_email_or_number")}
          />
        </label>
      )}

      {error && <p className="error">{error}</p>}

      <div className="table-wrap" id="members-table">
        <table className="table">
          <thead>
            <tr>
              <th>{t("cl.name")}</th>
              <th>{t("cl.contact")}</th>
              <th>{t("cl.role")}</th>
              {isSecretary && <th></th>}
            </tr>
          </thead>
          <tbody>
            {shown.map((m) => {
              // A club must never lose its last secretary.
              const lastSecretary =
                (m.role === "club_admin" || m.role === "super_admin") && secretaries <= 1;
              return (
                <tr key={m.user_id}>
                  <td>
                    <div className="member-cell">
                      <Link className="person" href={`/players/${m.user_id}`}>
                        <Avatar name={m.name} url={m.avatar_url} size={30} />
                        {m.name}
                        {m.user_id === meId && <span className="tag grey">{t("cl.you")}</span>}
                      </Link>
                      {m.user_id !== meId && <MessageButton userId={m.user_id} name={m.name} compact />}
                    </div>
                  </td>
                  <td className="subtle">{m.email || m.phone || "—"}</td>
                  <td>
                    {isSecretary ? (
                      <select
                        value={roleChoice(m)}
                        disabled={busy === m.user_id}
                        onChange={(e) => setRole(m.user_id, e.target.value)}
                        aria-label={t("cl.role_for", { name: m.name })}
                      >
                        {/* The last secretary can still captain, or stop
                            captaining — just not stop being secretary. */}
                        {ROLE_CHOICES.filter(
                          (r) => !lastSecretary || r.value.startsWith("club_admin")
                        ).map((r) => (
                          <option key={r.value} value={r.value} title={t(r.can)}>
                            {t(r.label)}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <span className="tag grey">{roleLabel(m.role, !!m.is_captain, t)}</span>
                    )}
                  </td>
                  {isSecretary && (
                    <td className="n">
                      <button
                        className="btn ghost sm"
                        type="button"
                        disabled={busy === m.user_id || lastSecretary}
                        title={lastSecretary ? t("lc.a_club_needs_a_secretary") : undefined}
                        onClick={() => remove(m.user_id, m.name)}
                      >
                        Remove
                      </button>
                    </td>
                  )}
                </tr>
              );
            })}
            {shown.length === 0 && (
              <tr>
                <td colSpan={4} className="muted">{t("cl.nobody_matches_that")}</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/// Two ways in, because most people a club wants are not signed up yet.
function AddMember({ clubId, onAdded }: { clubId: string; onAdded: () => void }) {
  const t = useT();
  const [identifier, setIdentifier] = useState("");
  const [role, setRole] = useState("member");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [invite, setInvite] = useState<string | null>(null);

  const add = async () => {
    setBusy(true);
    setNote(null);
    setInvite(null);
    try {
      await api("POST", `/clubs/${clubId}/members`, {
        identifier: identifier.trim(),
        role,
      });
      setIdentifier("");
      setNote(t("lc.added"));
      onAdded();
    } catch (err) {
      setNote(readErr(err, t("lc.could_not_add_them")));
    } finally {
      setBusy(false);
    }
  };

  const sendInvite = async () => {
    setBusy(true);
    setNote(null);
    try {
      const created = await api<Invite>("POST", "/invites", {
        target_type: "club",
        target_id: clubId,
        invited_email: identifier.trim(),
      });
      setInvite(`${window.location.origin}/invite/${created.token}`);
      setNote(null);
    } catch (err) {
      setNote(readErr(err, t("lc.could_not_create_the_invite")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="add-member" id="add-players">
      <div className="field-row">
        <label>
          {t("cl.email_or_mobile_number")}
          <input
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder={t("cl.them_club_test_or_07700_900123")}
          />
        </label>
        <label>
          {t("cl.role")}
          <select value={role} onChange={(e) => setRole(e.target.value)}>
            {CLUB_ROLES.map((r) => (
              <option key={r.value} value={r.value}>{t(r.label)}</option>
            ))}
          </select>
        </label>
        <button className="btn primary" type="button" disabled={!identifier.trim() || busy} onClick={add}>
          <Icon name="plus" size={16} /> Add
        </button>
        <button className="btn" type="button" disabled={!identifier.trim() || busy} onClick={sendInvite}>
          {t("cl.invite_instead")}
        </button>
      </div>
      <p className="subtle">
        {t("cl.add_works_for_somebody_who_already_has")}
      </p>
      {note && <p className="muted">{note}</p>}
      {invite && (
        <div className="invite-link">
          <code>{invite}</code>
          <button
            className="btn sm"
            type="button"
            onClick={() => void copyText(invite)}
          >
            {t("cl.copy")}
          </button>
        </div>
      )}
    </div>
  );
}

function Teams({
  clubId,
  teams,
  isSecretary,
  onChanged,
}: {
  clubId: string;
  teams: Team[];
  isSecretary: boolean;
  onChanged: () => void;
}) {
  const t = useT();
  const [name, setName] = useState("");
  const [sport, setSport] = useState("cricket");
  const [busy, setBusy] = useState(false);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("POST", `/clubs/${clubId}/teams`, { name: name.trim(), sport });
      setName("");
      setAdding(false);
      onChanged();
    } catch (err) {
      setError(readErr(err, t("lc.could_not_create_the_team")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel" id="teams">
      <div className="panel-head">
        <h2>{t("cl.teams")}</h2>
        {/* "optional" rather than a count of nought, which read as something
            missing. A club is already a side; this is only for a club that
            runs two of them. */}
        <span className="tag grey">{teams.length || t("cl.teams_optional")}</span>
      </div>
      {teams.length === 0 && <p className="muted">{t("cl.club_plays_as_one_side")}</p>}
      {teams.map((team) => <TeamRow key={team.id} team={team} />)}
      {isSecretary && !adding && (
        // A button, not a form standing open. An empty form with a label and a
        // dropdown in it is a thing somebody has not finished; a button is an
        // offer, which is what a team actually is.
        <button
          className="btn"
          type="button"
          id="add-team"
          style={{ marginTop: "var(--s3)" }}
          onClick={() => setAdding(true)}
        >
          <Icon name="plus" size={16} /> {t("ld.add_a_team")}
        </button>
      )}
      {isSecretary && adding && (
        <div className="field-row team-add" id="add-team" style={{ marginTop: "var(--s3)" }}>
          <label className="team-add-name">
            {t("cl.new_team")}
            <input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("cl.1st_xi")}
            />
          </label>
          <label className="team-add-sport">
            {t("cl.sport")}
            <select value={sport} onChange={(e) => setSport(e.target.value)}>
              {SPORTS.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
          <button className="btn primary" type="button" disabled={!name.trim() || busy} onClick={create}>
            <Icon name="plus" size={16} /> {t("cl.create")}
          </button>
          <button
            className="btn ghost"
            type="button"
            onClick={() => {
              setAdding(false);
              setName("");
              setError(null);
            }}
          >
            {t("sc.cancel")}
          </button>
        </div>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}

/// One team, and who is in it.
///
/// Collapsed by default: a club with four teams should not fetch four rosters
/// to show a list of four names. Open one and it loads.
function TeamRow({ team }: { team: Team }) {
  const t = useT();
  const [open, setOpen] = useState(false);
  const [members, setMembers] = useState<TeamMemberRow[] | null>(null);

  useEffect(() => {
    if (!open || members) return;
    api<TeamMemberRow[]>("GET", `/teams/${team.id}/members`)
      .then(setMembers)
      .catch(() => setMembers([]));
  }, [open, members, team.id]);

  return (
    <div className="team-row">
      <button
        type="button"
        className="team-head"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span>
          <strong>{team.name}</strong>
          <span className="tag grey">{team.sport}</span>
        </span>
        <span className="subtle">
          {members ? `${members.length} in` : ""} {open ? "▴" : "▾"}
        </span>
      </button>

      {open && (
        members === null ? (
          <div className="skeleton" style={{ height: 48 }} />
        ) : members.length === 0 ? (
          <p className="muted">
            {t("cl.nobody_in_this_team_yet_a_secretary_or")}
          </p>
        ) : (
          <ul className="pick-list">
            {members.map((m) => (
              <li key={m.user_id}>
                <Avatar name={m.name} url={m.avatar_url} size={30} />
                <div className="pick-who">
                  <strong>
                    <Link href={`/players/${m.user_id}`}>{m.name}</Link>
                  </strong>
                  <span className="pick-signals">
                    {m.role !== "member" && (
                      <span className="tag">{roleLabel(m.role, false, t)}</span>
                    )}
                    {m.position_role && <span className="subtle">{m.position_role}</span>}
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )
      )}
    </div>
  );
}

/// Where the club plays.
///
/// A fixture carries a venue, and until somebody has entered one there is
/// nothing to carry — which is why "where are we playing?" ends up in the
/// group chat every Saturday morning.
function Venues({
  clubId,
  venues,
  canEdit,
  onChanged,
}: {
  clubId: string;
  venues: Venue[];
  canEdit: boolean;
  onChanged: () => Promise<void>;
}) {
  const t = useT();
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const add = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("POST", `/clubs/${clubId}/venues`, {
        name: name.trim(),
        address: address.trim() || null,
      });
      setName("");
      setAddress("");
      setAdding(false);
      await onChanged();
    } catch (err) {
      setError(readErr(err, t("cl.could_not_add_that_ground")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel" id="grounds">
      <div className="panel-head">
        <h2>{t("cl.grounds")}</h2>
        <span className="tag grey">{venues.length}</span>
      </div>
      {canEdit && (
        <p className="muted" style={{ marginBottom: 12 }}>
          <Link href={`/clubs/${clubId}/hire`}>{t("cl.hireable_spaces_and_rates")}</Link>
        </p>
      )}

      {venues.length === 0 ? (
        <p className="muted">
          {t("cl.no_grounds_yet_add_the_ones_you_play_a")}
        </p>
      ) : (
        <ul className="pick-list">
          {venues.map((v) => (
            <li key={v.id}>
              <span className="thread-mark" aria-hidden>
                <Icon name="pin" size={18} />
              </span>
              <div className="pick-who">
                <strong>{v.name}</strong>
                {v.address && <span className="subtle">{v.address}</span>}
              </div>
              {v.address && (
                <div className="pick-actions">
                  {/* Somebody standing in a car park wants the map, not the
                      address as text. */}
                  <a
                    className="btn ghost sm"
                    href={`https://maps.google.com/?q=${encodeURIComponent(`${v.name} ${v.address}`)}`}
                    target="_blank"
                    rel="noreferrer noopener"
                  >
                    {t("cl.map")}
                  </a>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      {canEdit && !adding && (
        <button className="btn" type="button" onClick={() => setAdding(true)}
                style={{ marginTop: "var(--s3)" }}>
          <Icon name="plus" size={16} /> {t("cl.add_a_ground")}
        </button>
      )}

      {canEdit && adding && (
        <>
          <div className="setup-fields">
            <label>
              {t("cl.name")}
              <input value={name} onChange={(e) => setName(e.target.value)}
                     placeholder={t("cl.highbury_fields")} maxLength={160} />
            </label>
            <label>
              {t("cl.address")}
              <input value={address} onChange={(e) => setAddress(e.target.value)}
                     placeholder={t("cl.highbury_fields_london_n5_1ar")} />
            </label>
          </div>
          {error && <p className="error">{error}</p>}
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn primary" type="button" disabled={busy || !name.trim()}
                    onClick={add}>
              {busy ? t("cl.adding") : t("cl.add_it")}
            </button>
            <button className="btn" type="button" onClick={() => setAdding(false)}>{t("sc.cancel")}</button>
          </div>
        </>
      )}
    </div>
  );
}

/// How much the club wants done for it.
///
/// These are the deadlines the scheduler works to, so they are written in the
/// units a secretary thinks in — hours before the start — rather than as cron
/// settings. Nothing here changes what a captain *can* do; it changes what
/// happens when nobody does anything.
function Settings({ clubId }: { clubId: string }) {
  const t = useT();
  const [settings, setSettings] = useState<ClubSettings | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<ClubSettings>("GET", `/clubs/${clubId}/settings`).then(setSettings).catch(() => {});
  }, [clubId]);

  if (!settings) return null;

  const set = (patch: Partial<ClubSettings>) => {
    setSettings({ ...settings, ...patch });
    setSaved(false);
  };

  const save = async () => {
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      setSettings(await api<ClubSettings>("PATCH", `/clubs/${clubId}/settings`, settings));
      setSaved(true);
    } catch (err) {
      setError(readErr(err, t("lc.could_not_save_those_settings")));
    } finally {
      setBusy(false);
    }
  };

  const hours = (
    label: string,
    key: keyof ClubSettings,
    hint: string
  ) => (
    <label>
      {label}
      <input
        type="number"
        min={0}
        value={settings[key] as number}
        onChange={(e) => set({ [key]: Number(e.target.value) } as Partial<ClubSettings>)}
      />
      <span className="subtle">{hint}</span>
    </label>
  );

  return (
    <div className="panel">
      <h2>{t("cl.how_the_club_runs_itself")}</h2>

      <label>
        {t("cl.picking_a_side")}
        <select
          value={settings.selection_autonomy}
          onChange={(e) => set({ selection_autonomy: e.target.value })}
        >
          <option value="off">{t("cl.captains_do_it_no_help_offered")}</option>
          <option value="suggest">{t("cl.offer_a_squad_and_wait_for_the_captain")}</option>
          <option value="auto_publish">{t("cl.announce_a_squad_without_asking")}</option>
        </select>
        <span className="subtle">
          {settings.selection_autonomy === "auto_publish"
            ? t("lc.sides_go_out_on_their_own_a_captain_ca")
            : settings.selection_autonomy === "suggest"
            ? t("lc.nothing_is_announced_until_a_captain_s")
            : t("lc.nothing_is_suggested_at_all")}
        </span>
      </label>

      <div className="setup-fields">
        {hours(t("lc.ask_for_confirmation"), "confirm_lead_hours",
               t("cl.hours_before_the_start"))}
        {hours(t("lc.drop_anyone_who_has_not_confirmed"), "drop_lead_hours",
               t("cl.hours_before_reserves_move_up"))}
        {hours(t("lc.chase_an_unpaid_fee_after"), "fee_chase_after_hours",
               t("cl.hours_from_the_fixture"))}
        {hours(t("lc.stop_chasing_after"), "fee_chase_max_reminders",
               t("cl.reminders_so_nobody_is_nagged"))}
      </div>

      {error && <p className="error">{error}</p>}
      {saved && !error && <p className="muted">{t("cl.saved")}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy} onClick={save}>
          {busy ? "Saving…" : t("lc.save")}
        </button>
      </div>
    </div>
  );
}

/// Who has not paid for what.
///
/// One row per person per fixture, because that is how anybody actually
/// chases: "you owe for the Watford game", not "you owe £24". The scheduler
/// sends reminders on its own — this is the button for doing it now, and it
/// says how many have already gone so nobody gets nagged twice in a morning.
function Fees({ clubId }: { clubId: string }) {
  const t = useT();
  const [fees, setFees] = useState<OutstandingFees | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setFees(await api<OutstandingFees>("GET", `/clubs/${clubId}/fees/outstanding`));
    } catch {
      // A member without the selector role simply does not see this panel.
      setFees(null);
    }
  }, [clubId]);

  useEffect(() => { load(); }, [load]);

  if (!fees) return null;

  const chase = async () => {
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      await api("POST", `/clubs/${clubId}/fees/chase`, {});
      setNote(t("lc.reminders_sent"));
      await load();
    } catch (err) {
      setError(readErr(err, t("lc.could_not_send_those_reminders")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("cl.match_fees_owed")}</h2>
        <span className={fees.count > 0 ? "tag gold" : "tag"}>
          {money(fees.total_cents)}
        </span>
      </div>

      {fees.count === 0 ? (
        <p className="muted">{t("cl.everybody_is_square_nothing_outstandin")}</p>
      ) : (
        <>
          <p className="muted">
            {fees.count} unpaid {fees.count === 1 ? "fee" : "fees"} across your fixtures.
          </p>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>{t("cl.who")}</th><th>{t("cl.fixture")}</th><th>{t("cl.when")}</th>
                  <th className="n">{t("cl.owes")}</th><th className="n">{t("cl.chased")}</th>
                </tr>
              </thead>
              <tbody>
                {fees.owed.map((row) => (
                  <tr key={`${row.user_id}-${row.event_id}`}>
                    <td>
                      <span className="person">
                        <Avatar name={row.name} size={28} />
                        {row.name}
                      </span>
                    </td>
                    <td>{row.fixture}</td>
                    <td className="subtle">
                      {new Date(row.start_at).toLocaleDateString("en-GB", {
                        day: "numeric", month: "short",
                      })}
                    </td>
                    <td className="n num">{money(row.amount_cents ?? 0, row.currency)}</td>
                    <td className="n num">{row.reminders_sent || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {error && <p className="error">{error}</p>}
          {note && !error && <p className="muted">{note}</p>}
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn primary" type="button" disabled={busy} onClick={chase}>
              {busy ? t("lc.sending") : t("lc.remind_everybody_now")}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

/// The club's own public site, without them having to build one.
function PublicPage({
  clubId,
  clubName,
  members,
}: {
  clubId: string;
  clubName: string;
  members: ClubMemberRow[];
}) {
  const t = useT();
  const [page, setPage] = useState<ClubPageSettings | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    api<ClubPageSettings>("GET", `/clubs/${clubId}/page`).then(setPage).catch(() => {});
  }, [clubId]);

  if (!page) return null;

  const set = (patch: Partial<ClubPageSettings>) => setPage({ ...page, ...patch });

  const save = async (patch: Partial<ClubPageSettings>) => {
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      setPage(await api<ClubPageSettings>("PATCH", `/clubs/${clubId}/page`, patch));
      setSaved(true);
    } catch (err) {
      setError(readErr(err, t("lc.could_not_save_the_page")));
    } finally {
      setBusy(false);
    }
  };

  // A default anyone can live with, from the name they already chose.
  const suggested = clubName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  const address = page.slug ?? suggested;

  return (
    <div className="panel" id="public-page">
      <div className="panel-head">
        <h2>{t("cl.your_public_page")}</h2>
        {page.public_page && page.slug && (
          <a className="btn ghost sm" href={`/c/${page.slug}`} target="_blank" rel="noreferrer">
            {t("cl.view_it")}
          </a>
        )}
      </div>
      <p className="muted">
        A page anyone can open — no login. Your record and top players are worked out from
        the matches you have played; the rest is yours to write.
      </p>

      <div className="setup-fields">
        <label>
          {t("cl.web_address")}
          <input
            value={address}
            onChange={(e) => set({ slug: e.target.value })}
            placeholder={suggested}
          />
          <span className="subtle">{t("cl.public_url_preview", { slug: address || suggested })}</span>
        </label>
        <label>
          {t("cl.ground")}
          <input
            value={page.ground ?? ""}
            onChange={(e) => set({ ground: e.target.value })}
            placeholder={t("cl.highbury_fields_london_n5")}
          />
        </label>
        <label>
          {t("cl.founded")}
          <input
            type="number"
            inputMode="numeric"
            value={page.founded_year ?? ""}
            onChange={(e) =>
              set({ founded_year: e.target.value === "" ? null : Number(e.target.value) })
            }
            placeholder={t("cl.1974")}
          />
        </label>
        <label>
          {t("cl.email_for_new_players")}
          <input
            type="email"
            value={page.contact_email ?? ""}
            onChange={(e) => set({ contact_email: e.target.value })}
            placeholder={t("cl.hello_yourclub_test")}
          />
        </label>
      </div>

      <IconPlayerPicker
        members={members}
        chosen={page.icon_player_id ?? null}
        onPick={(id) => set({ icon_player_id: id })}
      />

      <label>
        {t("cl.one_line_about_the_club")}
        <input
          value={page.tagline ?? ""}
          onChange={(e) => set({ tagline: e.target.value })}
          placeholder={t("cl.sunday_cricket_in_north_london_since_1")}
        />
      </label>

      <label>
        {t("cl.the_longer_version")}
        <textarea
          rows={4}
          value={page.about ?? ""}
          onChange={(e) => set({ about: e.target.value })}
          placeholder={t("cl.who_you_are_where_you_play_who_you_are")}
        />
      </label>

      {error && <p className="error">{error}</p>}
      {saved && !error && <p className="muted">{t("cl.saved")}</p>}

      <div className="field-row">
        <button
          className="btn primary"
          type="button"
          disabled={busy}
          onClick={() => save({ ...page, slug: address })}
        >
          {busy ? "Saving…" : t("lc.save")}
        </button>
        <button
          className="btn"
          type="button"
          disabled={busy}
          onClick={() => save({ slug: address, public_page: !page.public_page })}
        >
          {page.public_page ? t("lc.take_it_offline") : t("lc.publish_it")}
        </button>
        <span className={`tag ${page.public_page ? "" : "grey"}`}>
          {page.public_page ? "Live" : "Not published"}
        </span>
      </div>
    </div>
  );
}

/// The one player the club leads with — a face on the front page.
///
/// Optional by design: a club with no photos on file still gets a page, and
/// "Nobody for now" is a real answer rather than a stuck field.
function IconPlayerPicker({
  members,
  chosen,
  onPick,
}: {
  members: ClubMemberRow[];
  chosen: string | null;
  onPick: (id: string) => void;
}) {
  const t = useT();
  const [filter, setFilter] = useState("");
  const term = filter.trim().toLowerCase();
  const shown = term
    ? members.filter((m) => m.name.toLowerCase().includes(term))
    : members;

  return (
    <fieldset className="icon-pick">
      <legend>{t("cl.your_icon_player")}</legend>
      <p className="muted">
        {t("cl.their_photo_leads_the_public_page_they")}
      </p>
      {members.length > 6 && (
        <input
          className="icon-pick-search"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder={t("cl.search_the_squad")}
          aria-label={t("cl.search_the_squad")}
        />
      )}
      <div className="icon-pick-grid">
        {/* NO_ICON_PLAYER, not an empty string: the API reads a null as
            "field untouched", so clearing needs a value of its own. */}
        <button
          type="button"
          className={`icon-pick-card${chosen ? "" : " on"}`}
          aria-pressed={!chosen}
          onClick={() => onPick(NO_ICON_PLAYER)}
        >
          <span className="icon-pick-face none">—</span>
          <span className="icon-pick-name">{t("cl.nobody_for_now")}</span>
        </button>
        {shown.map((m) => (
          <button
            key={m.user_id}
            type="button"
            className={`icon-pick-card${chosen === m.user_id ? " on" : ""}`}
            aria-pressed={chosen === m.user_id}
            onClick={() => onPick(m.user_id)}
          >
            <Avatar name={m.name} url={m.avatar_url} size={56} />
            <span className="icon-pick-name">{m.name}</span>
            {m.position_role && <span className="icon-pick-role">{m.position_role}</span>}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function Codes({ clubId, teams }: { clubId: string; teams: Team[] }) {
  const t = useT();
  const [codes, setCodes] = useState<QrCode[]>([]);

  useEffect(() => {
    (async () => {
      const found: QrCode[] = [];
      try {
        found.push(await api<QrCode>("GET", `/clubs/${clubId}/qr`));
      } catch {
        // A club with no code yet simply has none to show.
      }
      for (const team of teams) {
        try {
          found.push(await api<QrCode>("GET", `/teams/${team.id}/qr`));
        } catch {
          // Likewise per team.
        }
      }
      setCodes(found);
    })();
  }, [clubId, teams]);

  if (codes.length === 0) return null;
  return (
    <div className="panel">
      <h2>{t("cl.codes")}</h2>
      <p className="muted">{t("cl.show_these_to_an_opposition_captain_so")}</p>
      <div className="qr-grid">
        {codes.map((qr) => (
          <QrCard key={`${qr.kind}-${qr.id}`} qr={qr} />
        ))}
      </div>
    </div>
  );
}

