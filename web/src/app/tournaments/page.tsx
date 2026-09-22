"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, readErr, type Club, type Venue } from "@/lib/api";
import {
  AGE_GROUPS,
  AGE_LABEL,
  BALLS,
  BALL_LABEL,
  defaultConditions,
  GENDERS,
  GENDER_LABEL,
  GROUNDS,
  GROUND_LABEL,
  standardOversPerBowler,
  type EntryInvitation,
  type FixtureBlock,
} from "@/lib/tournament";
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
  const [description, setDescription] = useState("");

  // Entry
  const [maxEntrants, setMaxEntrants] = useState("");
  const [entryDeadline, setEntryDeadline] = useState("");
  const [entryFee, setEntryFee] = useState("");

  // Who may play
  const [playersPerSide, setPlayersPerSide] = useState(11);
  const [guests, setGuests] = useState(0);
  const [ageGroup, setAgeGroup] = useState("open");
  const [gender, setGender] = useState("open");

  // Playing conditions
  const [venueId, setVenueId] = useState("");
  const [venues, setVenues] = useState<Venue[]>([]);
  const [overs, setOvers] = useState(20);
  const [perBowler, setPerBowler] = useState(standardOversPerBowler(20));
  const [ball, setBall] = useState("white");
  const [ground, setGround] = useState("open");
  const [powerplay, setPowerplay] = useState(0);
  const [rulesNotes, setRulesNotes] = useState("");

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Only a tournament has entrants, a draw and a table. A tour or a plain block
  // of fixtures is a name and two dates, so it is not asked for the rest.
  const isTournament = kind === "tournament";

  // The grounds belong to whichever club is hosting, so they follow the club.
  useEffect(() => {
    if (!clubId) return;
    setVenueId("");
    api<Venue[]>("GET", `/clubs/${clubId}/venues`).then(setVenues).catch(() => setVenues([]));
  }, [clubId]);

  // A bowler's allocation follows the innings until somebody sets it
  // themselves — four overs of twenty, ten of fifty.
  const [bowlerTouched, setBowlerTouched] = useState(false);
  useEffect(() => {
    if (!bowlerTouched) setPerBowler(standardOversPerBowler(overs));
  }, [overs, bowlerTouched]);

  const pence = (v: string) => {
    const t = v.trim().replace(/^£/, "");
    if (t === "") return null;
    return /^\d+(\.\d{1,2})?$/.test(t) ? Math.round(Number(t) * 100) : NaN;
  };
  const feePence = pence(entryFee);
  const feeOk = feePence === null || Number.isFinite(feePence);

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
        description: description.trim() || null,
        // Only a tournament carries entry and playing rules. Sending them for
        // a tour would put a ball colour on a coach trip.
        ...(isTournament
          ? {
              venue_id: venueId || null,
              max_entrants: maxEntrants.trim() === "" ? null : Number(maxEntrants),
              entry_deadline: entryDeadline ? new Date(entryDeadline).toISOString() : null,
              entry_fee_cents: feePence,
              players_per_side: playersPerSide,
              guest_players_allowed: guests,
              age_group: ageGroup,
              gender,
              conditions: {
                ...defaultConditions(overs),
                overs_limit: overs,
                overs_per_bowler: perBowler,
                ball,
                ground,
                powerplay_overs: powerplay,
              },
              rules_notes: rulesNotes.trim() || null,
            }
          : {}),
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
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>New tournament</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
      </div>

      <fieldset className="setup-group">
        <legend>What it is</legend>
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
        <label>
          What to tell the clubs you invite
          <textarea
            rows={2}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Eight sides, two groups, finals in the afternoon. Teas included."
          />
        </label>
      </fieldset>

      {isTournament && (
        <>
          <fieldset className="setup-group">
            <legend>Entry</legend>
            <div className="setup-fields">
              <label>
                How many sides
                <span className="subtle">Leave empty for no limit.</span>
                <input
                  type="number"
                  min={2}
                  value={maxEntrants}
                  onChange={(e) => setMaxEntrants(e.target.value)}
                  placeholder="8"
                />
              </label>
              <label>
                Entries close
                <span className="subtle">After this, nobody else can be asked in.</span>
                <input
                  type="datetime-local"
                  value={entryDeadline}
                  onChange={(e) => setEntryDeadline(e.target.value)}
                />
              </label>
              <label>
                Entry fee per side
                <span className="subtle">What a club pays to enter.</span>
                <input
                  inputMode="decimal"
                  value={entryFee}
                  onChange={(e) => setEntryFee(e.target.value)}
                  placeholder="50.00"
                />
              </label>
              <label>
                Main ground
                <select value={venueId} onChange={(e) => setVenueId(e.target.value)}>
                  <option value="">Not decided</option>
                  {venues.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
                </select>
              </label>
            </div>
            {!feeOk && <p className="error">Give the entry fee as an amount, like 50.00.</p>}
          </fieldset>

          <fieldset className="setup-group">
            <legend>Who may play</legend>
            <div className="setup-fields">
              <label>
                Players a side
                <input
                  type="number"
                  min={2}
                  max={15}
                  value={playersPerSide}
                  onChange={(e) =>
                    setPlayersPerSide(Math.max(2, Math.min(15, Number(e.target.value) || 11)))
                  }
                />
              </label>
              <label>
                Guest players allowed
                <span className="subtle">
                  {guests === 0
                    ? "Every player must be a member of the entering club."
                    : `A side may borrow up to ${guests} from outside the club.`}
                </span>
                <input
                  type="number"
                  min={0}
                  max={playersPerSide}
                  value={guests}
                  onChange={(e) =>
                    setGuests(Math.max(0, Math.min(playersPerSide, Number(e.target.value) || 0)))
                  }
                />
              </label>
              <label>
                Age group
                <select value={ageGroup} onChange={(e) => setAgeGroup(e.target.value)}>
                  {AGE_GROUPS.map((a) => (
                    <option key={a} value={a}>{AGE_LABEL[a]}</option>
                  ))}
                </select>
              </label>
              <label>
                Who it is for
                <select value={gender} onChange={(e) => setGender(e.target.value)}>
                  {GENDERS.map((g) => (
                    <option key={g} value={g}>{GENDER_LABEL[g]}</option>
                  ))}
                </select>
              </label>
            </div>
          </fieldset>

          <fieldset className="setup-group">
            <legend>Playing conditions</legend>
            <p className="subtle">
              Every fixture in this tournament starts on these terms, so no
              scorer has to type them again.
            </p>
            <div className="setup-fields">
              <label>
                Overs an innings
                <input
                  type="number"
                  min={1}
                  max={100}
                  value={overs}
                  onChange={(e) => setOvers(Math.max(1, Math.min(100, Number(e.target.value) || 1)))}
                />
              </label>
              <label>
                Most overs one bowler
                <span className="subtle">
                  {bowlerTouched ? "Set by you." : `A fifth of the innings — ${perBowler}.`}
                </span>
                <input
                  type="number"
                  min={1}
                  max={overs}
                  value={perBowler}
                  onChange={(e) => {
                    setBowlerTouched(true);
                    setPerBowler(Math.max(1, Math.min(overs, Number(e.target.value) || 1)));
                  }}
                />
              </label>
              <label>
                Ball
                <select value={ball} onChange={(e) => setBall(e.target.value)}>
                  {BALLS.map((b) => <option key={b} value={b}>{BALL_LABEL[b]}</option>)}
                </select>
              </label>
              <label>
                Ground
                <select value={ground} onChange={(e) => setGround(e.target.value)}>
                  {GROUNDS.map((g) => <option key={g} value={g}>{GROUND_LABEL[g]}</option>)}
                </select>
              </label>
              <label>
                Powerplay overs
                <span className="subtle">Zero for none.</span>
                <input
                  type="number"
                  min={0}
                  max={overs}
                  value={powerplay}
                  onChange={(e) =>
                    setPowerplay(Math.max(0, Math.min(overs, Number(e.target.value) || 0)))
                  }
                />
              </label>
            </div>
            <label>
              Anything else in the rules
              <textarea
                rows={2}
                value={rulesNotes}
                onChange={(e) => setRulesNotes(e.target.value)}
                placeholder="Last man bats with a runner. Ties settled on wickets lost, then boundaries."
              />
            </label>
          </fieldset>
        </>
      )}

      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button
          className="btn primary"
          type="button"
          disabled={busy || !name.trim() || !clubId || !feeOk}
          onClick={create}
        >
          {busy ? "Creating…" : "Create it"}
        </button>
        <button className="btn" type="button" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}
