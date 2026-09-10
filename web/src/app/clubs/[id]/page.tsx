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
  NO_ICON_PLAYER,
  SPORTS,
  type Club,
  type ClubMemberRow,
  type Invite,
  type MyRole,
  type QrCode,
  type ClubPageSettings,
  type Team,
} from "@/lib/api";
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
        meId={me?.id}
        onChanged={load}
      />

      <Teams clubId={id} teams={teams} isSecretary={isSecretary} onChanged={load} />

      {isSecretary && <PublicPage clubId={id} clubName={club.name} members={members} />}

      <Codes clubId={id} teams={teams} />
    </main>
  );
}

function Members({
  clubId,
  members,
  isSecretary,
  meId,
  onChanged,
}: {
  clubId: string;
  members: ClubMemberRow[];
  isSecretary: boolean;
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
    <div className="panel">
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
                    <span className="person">
                      <Avatar name={m.name} url={m.avatar_url} size={30} />
                      {m.name}
                      {m.user_id === meId && <span className="tag grey">you</span>}
                    </span>
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
    <div className="panel">
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
      {teams.map((t) => (
        <div className="row" key={t.id}>
          <div>
            <div style={{ fontWeight: 600 }}>{t.name}</div>
            <span className="tag">{t.sport}</span>
          </div>
        </div>
      ))}
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

