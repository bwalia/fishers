"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  api,
  readErr,
  getAccessToken,
  getStoredUser,
  roleLabel,
  CLUB_ROLES,
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
import { MessageButton } from "@/components/MessageButton";
import { Icon } from "@/components/Icon";
import { Avatar } from "@/components/Avatar";
import { QrCard } from "@/components/QrCard";
import { copyText } from "@/lib/clipboard";

export default function ClubPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [club, setClub] = useState<Club | null>(null);
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [myRole, setMyRole] = useState<MyRole | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const me = getStoredUser();
  // The API decides; the page only asks. Everyone else sees the roster
  // read-only.
  const isSecretary = myRole?.is_secretary ?? false;

  const load = useCallback(async () => {
    try {
      const [c, m, t, role] = await Promise.all([
        api<Club>("GET", `/clubs/${id}`),
        api<ClubMemberRow[]>("GET", `/clubs/${id}/members`),
        api<Team[]>("GET", `/clubs/${id}/teams`).catch(() => []),
        api<MyRole>("GET", `/clubs/${id}/my-role`),
      ]);
      setClub(c);
      setMembers(m);
      setTeams(t);
      setMyRole(role);
    } catch (err) {
      setError(readErr(err, "Could not load the club"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view this club.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  if (error) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !club)
    return <main id="main"><div className="panel"><div className="skeleton" style={{ height: 80 }} /></div></main>;

  return (
    <main id="main">
      <section className="hero">
        <p className="muted"><Link href="/clubs">← All clubs</Link></p>
        <h1>{club.name}</h1>
        <p>{club.description || "No description yet."}</p>
        <div className="hero-tags">
          {club.sport_types.map((s) => <span className="tag" key={s}>{s}</span>)}
          {myRole && <span className="tag gold">{myRole.display_name}</span>}
        </div>
      </section>

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

      <Venues clubId={id} canEdit={isSecretary} />

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

  const setRole = async (userId: string, role: string) => {
    setBusy(userId);
    setError(null);
    try {
      await api("PATCH", `/clubs/${clubId}/members/${userId}`, { role });
      onChanged();
    } catch (err) {
      setError(readErr(err, "Could not change that role"));
    } finally {
      setBusy(null);
    }
  };

  const remove = async (userId: string, name: string) => {
    if (!confirm(`Remove ${name} from the club?`)) return;
    setBusy(userId);
    setError(null);
    try {
      await api("DELETE", `/clubs/${clubId}/members/${userId}`);
      onChanged();
    } catch (err) {
      setError(readErr(err, "Could not remove them"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel" id="members">
      <div className="panel-head">
        <h2>Members</h2>
        <span className="tag grey">{members.length}</span>
      </div>
      <p className="muted">
        A role is what somebody is allowed to <em>run</em>, not whether they play.
        Everybody here is picked from for a side, the secretary included — and the
        levels stack, so a secretary already has a captain&rsquo;s powers.
      </p>

      {isSecretary && <AddMember clubId={clubId} onAdded={onChanged} />}
      {canAddByLink && <AddByLink clubId={clubId} />}

      {members.length > 8 && (
        <label>
          Find someone
          <input
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Name, email or number"
          />
        </label>
      )}

      {error && <p className="error">{error}</p>}

      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Contact</th>
              <th>Role</th>
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
                        {m.user_id === meId && <span className="tag grey">you</span>}
                      </Link>
                      {m.user_id !== meId && <MessageButton userId={m.user_id} name={m.name} compact />}
                    </div>
                  </td>
                  <td className="subtle">{m.email || m.phone || "—"}</td>
                  <td>
                    {isSecretary && !lastSecretary ? (
                      <select
                        value={m.role}
                        disabled={busy === m.user_id}
                        onChange={(e) => setRole(m.user_id, e.target.value)}
                        aria-label={`Role for ${m.name}`}
                      >
                        {CLUB_ROLES.map((r) => (
                          <option key={r.value} value={r.value} title={r.can}>
                            {r.label}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <span className="tag grey">{roleLabel(m.role)}</span>
                    )}
                  </td>
                  {isSecretary && (
                    <td className="n">
                      <button
                        className="btn ghost sm"
                        type="button"
                        disabled={busy === m.user_id || lastSecretary}
                        title={lastSecretary ? "A club needs a secretary" : undefined}
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
                <td colSpan={4} className="muted">Nobody matches that.</td>
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
      setNote("Added.");
      onAdded();
    } catch (err) {
      setNote(readErr(err, "Could not add them"));
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
      setNote(readErr(err, "Could not create the invite"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="add-member">
      <div className="field-row">
        <label>
          Email or mobile number
          <input
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="them@club.test or 07700 900123"
          />
        </label>
        <label>
          Role
          <select value={role} onChange={(e) => setRole(e.target.value)}>
            {CLUB_ROLES.map((r) => (
              <option key={r.value} value={r.value}>{r.label}</option>
            ))}
          </select>
        </label>
        <button className="btn primary" type="button" disabled={!identifier.trim() || busy} onClick={add}>
          <Icon name="plus" size={16} /> Add
        </button>
        <button className="btn" type="button" disabled={!identifier.trim() || busy} onClick={sendInvite}>
          Invite instead
        </button>
      </div>
      <p className="subtle">
        Add works for somebody who already has an account. Invite makes a link for
        anyone who does not.
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
            Copy
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
  const [name, setName] = useState("");
  const [sport, setSport] = useState("cricket");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("POST", `/clubs/${clubId}/teams`, { name: name.trim(), sport });
      setName("");
      onChanged();
    } catch (err) {
      setError(readErr(err, "Could not create the team"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel" id="teams">
      <div className="panel-head">
        <h2>Teams</h2>
        <span className="tag grey">{teams.length}</span>
      </div>
      {teams.length === 0 && (
        <p className="muted">
          No teams yet. A club can run without them — teams are for a 1st XI and a 2nd XI
          keeping separate squads.
        </p>
      )}
      {teams.map((t) => <TeamRow key={t.id} team={t} />)}
      {isSecretary && (
        <div className="field-row" style={{ marginTop: "var(--s3)" }}>
          <label>
            New team
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="1st XI" />
          </label>
          <label>
            Sport
            <select value={sport} onChange={(e) => setSport(e.target.value)}>
              {SPORTS.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
          <button className="btn" type="button" disabled={!name.trim() || busy} onClick={create}>
            <Icon name="plus" size={16} /> Create
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
            Nobody in this team yet. A secretary or the team captain adds people.
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
                      <span className="tag">{roleLabel(m.role)}</span>
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
function Venues({ clubId, canEdit }: { clubId: string; canEdit: boolean }) {
  const [venues, setVenues] = useState<Venue[] | null>(null);
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setVenues(await api<Venue[]>("GET", `/clubs/${clubId}/venues`).catch(() => []));
  }, [clubId]);

  useEffect(() => { load(); }, [load]);

  if (venues === null) return null;

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
      await load();
    } catch (err) {
      setError(readErr(err, "Could not add that ground"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>Grounds</h2>
        <span className="tag grey">{venues.length}</span>
      </div>

      {venues.length === 0 ? (
        <p className="muted">
          No grounds yet. Add the ones you play at and they can be picked when a fixture is
          scheduled.
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
                    Map
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
          <Icon name="plus" size={16} /> Add a ground
        </button>
      )}

      {canEdit && adding && (
        <>
          <div className="setup-fields">
            <label>
              Name
              <input value={name} onChange={(e) => setName(e.target.value)}
                     placeholder="Highbury Fields" maxLength={160} />
            </label>
            <label>
              Address
              <input value={address} onChange={(e) => setAddress(e.target.value)}
                     placeholder="Highbury Fields, London N5 1AR" />
            </label>
          </div>
          {error && <p className="error">{error}</p>}
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn primary" type="button" disabled={busy || !name.trim()}
                    onClick={add}>
              {busy ? "Adding…" : "Add it"}
            </button>
            <button className="btn" type="button" onClick={() => setAdding(false)}>Cancel</button>
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
      setError(readErr(err, "Could not save those settings"));
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
      <h2>How the club runs itself</h2>

      <label>
        Picking a side
        <select
          value={settings.selection_autonomy}
          onChange={(e) => set({ selection_autonomy: e.target.value })}
        >
          <option value="off">Captains do it — no help offered</option>
          <option value="suggest">Offer a squad and wait for the captain</option>
          <option value="auto_publish">Announce a squad without asking</option>
        </select>
        <span className="subtle">
          {settings.selection_autonomy === "auto_publish"
            ? "Sides go out on their own. A captain can still change one afterwards."
            : settings.selection_autonomy === "suggest"
            ? "Nothing is announced until a captain says so."
            : "Nothing is suggested at all."}
        </span>
      </label>

      <div className="setup-fields">
        {hours("Ask for confirmation", "confirm_lead_hours",
               "hours before the start")}
        {hours("Drop anyone who has not confirmed", "drop_lead_hours",
               "hours before the start — reserves move up")}
        {hours("Chase an unpaid fee after", "fee_chase_after_hours",
               "hours from the fixture")}
        {hours("Stop chasing after", "fee_chase_max_reminders",
               "reminders, so nobody is nagged forever")}
      </div>

      {error && <p className="error">{error}</p>}
      {saved && !error && <p className="muted">Saved.</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy} onClick={save}>
          {busy ? "Saving…" : "Save"}
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
      setNote("Reminders sent.");
      await load();
    } catch (err) {
      setError(readErr(err, "Could not send those reminders"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>Match fees owed</h2>
        <span className={fees.count > 0 ? "tag gold" : "tag"}>
          {money(fees.total_cents)}
        </span>
      </div>

      {fees.count === 0 ? (
        <p className="muted">Everybody is square. Nothing outstanding.</p>
      ) : (
        <>
          <p className="muted">
            {fees.count} unpaid {fees.count === 1 ? "fee" : "fees"} across your fixtures.
          </p>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Who</th><th>Fixture</th><th>When</th>
                  <th className="n">Owes</th><th className="n">Chased</th>
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
              {busy ? "Sending…" : "Remind everybody now"}
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
      setError(readErr(err, "Could not save the page"));
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
    <div className="panel">
      <div className="panel-head">
        <h2>Your public page</h2>
        {page.public_page && page.slug && (
          <a className="btn ghost sm" href={`/c/${page.slug}`} target="_blank" rel="noreferrer">
            View it
          </a>
        )}
      </div>
      <p className="muted">
        A page anyone can open — no login. Your record and top players are worked out from
        the matches you have played; the rest is yours to write.
      </p>

      <div className="setup-fields">
        <label>
          Web address
          <input
            value={address}
            onChange={(e) => set({ slug: e.target.value })}
            placeholder={suggested}
          />
          <span className="subtle">fishers.cloud/c/{address || suggested}</span>
        </label>
        <label>
          Ground
          <input
            value={page.ground ?? ""}
            onChange={(e) => set({ ground: e.target.value })}
            placeholder="Highbury Fields, London N5"
          />
        </label>
        <label>
          Founded
          <input
            type="number"
            inputMode="numeric"
            value={page.founded_year ?? ""}
            onChange={(e) =>
              set({ founded_year: e.target.value === "" ? null : Number(e.target.value) })
            }
            placeholder="1974"
          />
        </label>
        <label>
          Email for new players
          <input
            type="email"
            value={page.contact_email ?? ""}
            onChange={(e) => set({ contact_email: e.target.value })}
            placeholder="hello@yourclub.test"
          />
        </label>
      </div>

      <IconPlayerPicker
        members={members}
        chosen={page.icon_player_id ?? null}
        onPick={(id) => set({ icon_player_id: id })}
      />

      <label>
        One line about the club
        <input
          value={page.tagline ?? ""}
          onChange={(e) => set({ tagline: e.target.value })}
          placeholder="Sunday cricket in north London since 1974."
        />
      </label>

      <label>
        The longer version
        <textarea
          rows={4}
          value={page.about ?? ""}
          onChange={(e) => set({ about: e.target.value })}
          placeholder="Who you are, where you play, who you are looking for."
        />
      </label>

      {error && <p className="error">{error}</p>}
      {saved && !error && <p className="muted">Saved.</p>}

      <div className="field-row">
        <button
          className="btn primary"
          type="button"
          disabled={busy}
          onClick={() => save({ ...page, slug: address })}
        >
          {busy ? "Saving…" : "Save"}
        </button>
        <button
          className="btn"
          type="button"
          disabled={busy}
          onClick={() => save({ slug: address, public_page: !page.public_page })}
        >
          {page.public_page ? "Take it offline" : "Publish it"}
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
  const [filter, setFilter] = useState("");
  const term = filter.trim().toLowerCase();
  const shown = term
    ? members.filter((m) => m.name.toLowerCase().includes(term))
    : members;

  return (
    <fieldset className="icon-pick">
      <legend>Your icon player</legend>
      <p className="muted">
        Their photo leads the public page. They upload it themselves from their profile —
        anyone without one still shows, just as initials.
      </p>
      {members.length > 6 && (
        <input
          className="icon-pick-search"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Search the squad"
          aria-label="Search the squad"
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
          <span className="icon-pick-name">Nobody for now</span>
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
      <h2>Codes</h2>
      <p className="muted">Show these to an opposition captain so they can find you.</p>
      <div className="qr-grid">
        {codes.map((qr) => (
          <QrCard key={`${qr.kind}-${qr.id}`} qr={qr} />
        ))}
      </div>
    </div>
  );
}

