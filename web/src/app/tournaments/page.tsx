"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, readErr, type Club } from "@/lib/api";
import { type EntryInvitation, type FixtureBlock } from "@/lib/tournament";
import { Icon } from "@/components/Icon";
import { useRequireAuth } from "@/lib/require-auth";

/// Blocks of fixtures: a tournament, a tour, a season.
///
/// A block is the thing that holds entrants, a grid of pitches and times, and
/// a table. A one-off fixture needs none of that, which is why it is a separate
/// idea rather than a flag on an event.
export default function TournamentsPage() {
  const authed = useRequireAuth();
  const [clubs, setClubs] = useState<Club[]>([]);
  const [blocks, setBlocks] = useState<Record<string, FixtureBlock[]>>({});
  const [invites, setInvites] = useState<EntryInvitation[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    try {
      const mine = await api<Club[]>("GET", "/clubs");
      setClubs(mine);
      const found = await Promise.all(
        mine.map(async (c) => [
          c.id,
          await api<FixtureBlock[]>("GET", `/clubs/${c.id}/fixture-blocks`).catch(() => []),
        ] as const)
      );
      setBlocks(Object.fromEntries(found));

      // Tournaments other clubs have asked yours into. They belong at the top
      // of this screen rather than buried in a club page: an invitation nobody
      // answers is a tournament your side does not play in.
      const asked = await Promise.all(
        mine.map((c) =>
          api<EntryInvitation[]>("GET", `/clubs/${c.id}/tournament-invites?pending=1`)
            .catch(() => [] as EntryInvitation[])
        )
      );
      setInvites(asked.flat());
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load your tournaments"));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  const total = Object.values(blocks).reduce((n, list) => n + list.length, 0);

  if (!authed) return <main id="main" />;

  return (
    <main id="main">
      <section className="hero">
        <h1>Tournaments</h1>
        <p>A block holds the sides, the pitches and times, the fixtures and the table.</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setCreating(true)}>
            <Icon name="plus" size={16} /> New tournament
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}
      {loading && <div className="skeleton" style={{ height: 180 }} />}

      {invites.length > 0 && <Invitations invites={invites} onAnswered={load} />}

      {!loading && !error && total === 0 && (
        <div className="panel empty">
          <Icon name="trophy" size={28} />
          <p>Nothing running. Start one and add the sides.</p>
        </div>
      )}

      {clubs.map((club) => {
        const list = blocks[club.id] ?? [];
        if (list.length === 0) return null;
        return (
          <div className="panel" key={club.id}>
            <h2>{club.name}</h2>
            <ul className="thread-list">
              {list.map((b) => (
                <li key={b.id}>
                  <Link href={`/tournaments/${b.id}`} className="thread-row">
                    <span className="thread-mark" aria-hidden>
                      <Icon name="trophy" size={18} />
                    </span>
                    <span className="thread-body">
                      <span className="thread-head">
                        <strong>{b.name}</strong>
                        <span className="subtle">{dates(b)}</span>
                      </span>
                      <span className="thread-last">{b.kind}</span>
                    </span>
                    <span className="thread-badges">
                      <Icon name="arrowLeft" size={14} className="flip" />
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        );
      })}

      {creating && (
        <NewBlock clubs={clubs} onClose={() => setCreating(false)} onCreated={load} />
      )}
    </main>
  );
}

/// Tournaments your club has been asked into and has not answered.
///
/// The host is waiting on this to make the draw, so it is the first thing on
/// the page and it says who asked — an invitation from a club you have never
/// heard of is answered differently from one from your league rivals.
function Invitations({
  invites,
  onAnswered,
}: {
  invites: EntryInvitation[];
  onAnswered: () => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const answer = async (invite: EntryInvitation, status: "accepted" | "declined") => {
    setBusy(invite.entrant_id);
    setError(null);
    try {
      await api("POST", `/entrants/${invite.entrant_id}/respond`, { status });
      onAnswered();
    } catch (err) {
      setError(readErr(err, "Could not send that answer"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>You have been asked</h2>
        <span className="tag gold">{invites.length}</span>
      </div>
      {error && <p className="error">{error}</p>}
      <ul className="pick-list">
        {invites.map((i) => (
          <li key={i.entrant_id}>
            <span className="thread-mark" aria-hidden>
              <Icon name="trophy" size={18} />
            </span>
            <div className="pick-who">
              <strong>{i.block_name}</strong>
              <span className="pick-signals">
                <span className="subtle">
                  {i.host_club_name}
                  {i.invited_by_name ? ` · ${i.invited_by_name}` : ""}
                </span>
                {blockDates(i) && <span className="subtle">{blockDates(i)}</span>}
                <span className="subtle">entering as {i.entrant_name}</span>
              </span>
            </div>
            <div className="pick-actions">
              <button
                className="btn primary sm"
                type="button"
                disabled={busy !== null}
                onClick={() => answer(i, "accepted")}
              >
                {busy === i.entrant_id ? "…" : "Accept"}
              </button>
              <button
                className="btn ghost sm"
                type="button"
                disabled={busy !== null}
                onClick={() => answer(i, "declined")}
              >
                Decline
              </button>
            </div>
          </li>
        ))}
      </ul>
      <p className="subtle" style={{ marginTop: "var(--s3)" }}>
        Accepting puts your side in the draw. Declining tells them now, while
        they can still find somebody else.
      </p>
    </div>
  );
}

function blockDates(i: EntryInvitation): string {
  const fmt = (d: string) =>
    new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  if (i.starts_on && i.ends_on) return `${fmt(i.starts_on)} – ${fmt(i.ends_on)}`;
  if (i.starts_on) return `from ${fmt(i.starts_on)}`;
  return "";
}

function dates(b: FixtureBlock): string {
  const fmt = (d: string) =>
    new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  if (b.starts_on && b.ends_on) return `${fmt(b.starts_on)} – ${fmt(b.ends_on)}`;
  if (b.starts_on) return `from ${fmt(b.starts_on)}`;
  return "";
}

function NewBlock({
  clubs,
  onClose,
  onCreated,
}: {
  clubs: Club[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const [clubId, setClubId] = useState(clubs[0]?.id ?? "");
  const [name, setName] = useState("");
  const [kind, setKind] = useState("tournament");
  const [startsOn, setStartsOn] = useState("");
  const [endsOn, setEndsOn] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("POST", "/fixture-blocks", {
        club_id: clubId,
        name: name.trim(),
        kind,
        starts_on: startsOn || null,
        ends_on: endsOn || null,
      });
      onCreated();
      onClose();
    } catch (err) {
      setError(readErr(err, "Could not create that"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <h2>New tournament</h2>
      <div className="setup-fields">
        <label>
          Club
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        <label>
          Name
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Summer Sixes"
            maxLength={120}
          />
        </label>
        <label>
          What is it
          <select value={kind} onChange={(e) => setKind(e.target.value)}>
            <option value="tournament">Tournament</option>
            <option value="tour">Tour</option>
            <option value="season">Season</option>
            <option value="block">Block of fixtures</option>
          </select>
        </label>
        <label>
          First day
          <input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} />
        </label>
        <label>
          Last day
          <input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !name.trim() || !clubId}
                onClick={create}>
          {busy ? "Creating…" : "Create it"}
        </button>
        <button className="btn" type="button" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}
