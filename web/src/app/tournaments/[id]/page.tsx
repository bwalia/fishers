"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { api, readErr } from "@/lib/api";
import {
  AGE_GROUPS,
  AGE_LABEL,
  BALLS,
  BALL_LABEL,
  byGroup,
  defaultConditions,
  difference,
  ENTRY_LABEL,
  FORMAT_LABEL,
  GENDERS,
  GENDER_LABEL,
  GROUNDS,
  GROUND_LABEL,
  type EntryStatus,
  type FixtureBlock,
  type ScheduleRow,
  type SchedulePreview,
  type Slot,
  type Standing,
  type TournamentEntrant,
  type TournamentFormat,
} from "@/lib/tournament";
import { Icon } from "@/components/Icon";
import { OppositionPicker } from "@/components/OppositionPicker";
import { type OpponentIdentity } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";

type Tab = "entrants" | "grid" | "fixtures" | "table" | "rules";

/// Running one tournament.
///
/// Four steps in the order an organiser works: who is in, when and where they
/// can play, the fixtures generated into that grid, and the table. Each is a
/// tab because they are done at different times — entrants in the week before,
/// the grid the night before, fixtures on the morning, the table all day.
export default function TournamentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const authed = useRequireAuth();
  const [tab, setTab] = useState<Tab>("entrants");
  const [entrants, setEntrants] = useState<TournamentEntrant[]>([]);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [fixtures, setFixtures] = useState<ScheduleRow[]>([]);
  const [table, setTable] = useState<Standing[]>([]);
  const [block, setBlock] = useState<FixtureBlock | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const [e, s, f, t, b] = await Promise.all([
        api<TournamentEntrant[]>("GET", `/fixture-blocks/${id}/entrants`),
        api<{ free: Slot[] }>("GET", `/fixture-blocks/${id}/slots`).catch(() => ({ free: [] })),
        api<ScheduleRow[]>("GET", `/fixture-blocks/${id}/schedule`).catch(() => []),
        api<Standing[]>("GET", `/fixture-blocks/${id}/standings`).catch(() => []),
        api<FixtureBlock>("GET", `/fixture-blocks/${id}`).catch(() => null),
      ]);
      setEntrants(e);
      setSlots(s.free);
      setFixtures(f);
      setTable(t);
      setBlock(b);
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load this tournament"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;
  if (error && entrants.length === 0)
    return <main id="main"><p className="error">{error}</p></main>;
  if (loading)
    return <main id="main"><div className="skeleton" style={{ height: 300 }} /></main>;

  // Only accepted sides are in the tournament. A club that has been asked and
  // not answered is counted separately, because chasing them is the organiser's
  // next job and a single "12 in" hides it.
  const playing = entrants.filter((e) => e.status === "accepted");
  const waiting = entrants.filter((e) => e.status === "invited");

  return (
    <main id="main">
      <section className="hero">
        <h1>{block?.name ?? "Tournament"}</h1>
        {block?.description && <p>{block.description}</p>}
        <div className="hero-tags">
          <span className="tag">
            {/* "6 of 8 in" rather than "6 in": how many places are left is the
                thing an organiser is counting. */}
            {playing.length}
            {block?.max_entrants ? ` of ${block.max_entrants}` : ""} in
          </span>
          {waiting.length > 0 && (
            <span className="tag gold">{waiting.length} yet to answer</span>
          )}
          <span className="tag grey">{slots.length} free slots</span>
          <span className="tag grey">{fixtures.length} fixtures</span>
        </div>
      </section>

      <div className="people-tabs" role="tablist" aria-label="Tournament">
        {(["entrants", "grid", "fixtures", "table", "rules"] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            role="tab"
            aria-selected={tab === t}
            className={tab === t ? "on" : undefined}
            onClick={() => setTab(t)}
          >
            {
              {
                entrants: "Who is in",
                grid: "Pitches & times",
                fixtures: "Fixtures",
                table: "Table",
                rules: "Rules",
              }[t]
            }
          </button>
        ))}
      </div>

      {error && <p className="error">{error}</p>}

      {tab === "entrants" && <Entrants blockId={id} entrants={entrants} onChanged={load} />}
      {tab === "grid" && <Grid blockId={id} slots={slots} onChanged={load} />}
      {tab === "fixtures" && (
        <Fixtures
          blockId={id}
          fixtures={fixtures}
          slots={slots}
          entrants={entrants}
          onChanged={load}
        />
      )}
      {tab === "table" && <Table blockId={id} rows={table} onChanged={load} />}
      {tab === "rules" && <Rules blockId={id} block={block} onChanged={load} />}

      <p className="muted" style={{ marginTop: "var(--s5)" }}>
        <Link href="/tournaments">← All tournaments</Link>
      </p>
    </main>
  );
}

/* ---------- Who is in ---------- */

function Entrants({
  blockId,
  entrants,
  onChanged,
}: {
  blockId: string;
  entrants: TournamentEntrant[];
  onChanged: () => void;
}) {
  const [names, setNames] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  const run = async (what: string, job: () => Promise<unknown>, said?: string) => {
    setBusy(what);
    setError(null);
    setNote(null);
    try {
      await job();
      if (said) setNote(said);
      onChanged();
    } catch (err) {
      setError(readErr(err, "That did not work"));
    } finally {
      setBusy(null);
    }
  };

  const add = () => {
    // One per line: pasting a list out of an email is how entries actually
    // arrive, and re-typing them into a form one at a time is the reason
    // organisers keep using a spreadsheet.
    const rows = names.split("\n").map((n) => n.trim()).filter(Boolean);
    if (rows.length === 0) return;
    return run(
      "add",
      () =>
        api("POST", `/fixture-blocks/${blockId}/entrants`, {
          entrants: rows.map((name) => ({ name })),
        }).then(() => setNames("")),
      `Entered ${rows.length} ${rows.length === 1 ? "side" : "sides"}.`
    );
  };

  const waiting = entrants.filter((e) => e.status === "invited");

  return (
    <>
      <div className="panel">
        <div className="panel-head">
          <h2>The sides</h2>
          {waiting.length > 0 && (
            <span className="tag gold">{waiting.length} yet to answer</span>
          )}
        </div>
        {entrants.length === 0 ? (
          <p className="muted">Nobody entered yet.</p>
        ) : (
          <ul className="pick-list">
            {entrants.map((e) => (
              <li key={e.id} className={e.status === "accepted" ? undefined : "reserve"}>
                <span className="thread-mark" aria-hidden>
                  {e.group_label ?? (e.seed ? `#${e.seed}` : "–")}
                </span>
                <div className="pick-who">
                  <strong>{e.name}</strong>
                  <span className="pick-signals">
                    {e.club_id && <span className="subtle">on Fishers</span>}
                    {e.contact_email && !e.club_id && (
                      <span className="subtle">{e.contact_email}</span>
                    )}
                  </span>
                </div>
                <div className="pick-actions">
                  <EntryTag status={e.status} />
                  {e.status === "accepted" && (
                    <button
                      className="btn ghost sm"
                      type="button"
                      disabled={busy !== null}
                      onClick={() =>
                        run(
                          e.id,
                          () => api("POST", `/entrants/${e.id}/withdraw`, {}),
                          `${e.name} withdrawn.`
                        )
                      }
                    >
                      Withdraw
                    </button>
                  )}
                  {(e.status === "declined" || e.status === "withdrawn") && e.club_id && (
                    <button
                      className="btn ghost sm"
                      type="button"
                      disabled={busy !== null}
                      onClick={() =>
                        run(
                          e.id,
                          () =>
                            api("POST", `/fixture-blocks/${blockId}/invite`, {
                              club_id: e.club_id,
                            }),
                          `Asked ${e.name} again.`
                        )
                      }
                    >
                      Ask again
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
        {error && <p className="error">{error}</p>}
        {note && <p className="notice">{note}</p>}
        {waiting.length > 0 && (
          <p className="subtle" style={{ marginTop: "var(--s3)" }}>
            Only sides that have accepted go into the draw.
          </p>
        )}
      </div>

      <InviteClub blockId={blockId} onInvited={onChanged} />

      <div className="panel">
        <h2>Enter sides yourself</h2>
        <p className="subtle">
          For a side you are entering on their behalf — they are in straight away
          and are never asked.
        </p>
        <label>
          One per line
          <textarea
            rows={4}
            value={names}
            onChange={(e) => setNames(e.target.value)}
            placeholder={"Hemel CC\nWatford Wanderers\nSt Albans 2nd XI"}
          />
        </label>
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn" type="button" disabled={busy !== null || !names.trim()}
                  onClick={add}>
            {busy === "add" ? "Entering…" : "Enter them"}
          </button>
        </div>
      </div>
    </>
  );
}

function EntryTag({ status }: { status: EntryStatus }) {
  const tone =
    status === "accepted" ? "" : status === "invited" ? "gold" : "grey";
  return <span className={`tag ${tone}`.trim()}>{ENTRY_LABEL[status]}</span>;
}

/// Ask a club into the tournament.
///
/// Two kinds of side, and the difference matters: a club on Fishers answers in
/// its own app, and one that is not gets a link by email. Either way they
/// decide — an organiser cannot enter somebody else's club for them.
function InviteClub({ blockId, onInvited }: { blockId: string; onInvited: () => void }) {
  const [picked, setPicked] = useState<OpponentIdentity | null>(null);
  const [typed, setTyped] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [link, setLink] = useState<string | null>(null);

  const offPlatform = !picked && typed.trim().length > 0;
  const ready = picked ? true : offPlatform && email.trim().length > 0;

  const send = async () => {
    setBusy(true);
    setError(null);
    setNote(null);
    setLink(null);
    try {
      const body = picked
        ? { club_id: picked.club_id, team_id: picked.kind === "team" ? picked.id : null,
            name: picked.kind === "team" ? picked.name : null }
        : { name: typed.trim(), contact_email: email.trim() };
      const out = await api<{ invite_link: string | null }>(
        "POST",
        `/fixture-blocks/${blockId}/invite`,
        body
      );
      setNote(`Asked ${picked?.name ?? typed.trim()}. They decide whether to enter.`);
      setLink(out.invite_link);
      setPicked(null);
      setTyped("");
      setEmail("");
      onInvited();
    } catch (err) {
      setError(readErr(err, "Could not send that invitation"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <h2>Invite a club</h2>
      <p className="subtle">
        They accept or decline themselves, and only then are they in the draw.
      </p>

      <OppositionPicker
        onPick={(identity, name) => {
          setPicked(identity);
          setTyped(identity ? "" : name);
        }}
      />

      {offPlatform && (
        <label>
          Where to send it
          <span className="subtle">
            {typed.trim()} is not on Fishers, so they answer by following a link.
          </span>
          <input
            type="email"
            inputMode="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="secretary@theirclub.example"
          />
        </label>
      )}

      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}
      {link && (
        // Shown because club email goes to a shared inbox somebody checks on
        // Sundays. Passing the link on by hand is often how this actually lands.
        <p className="subtle">
          Their link, if you would rather send it yourself: <code>{link}</code>
        </p>
      )}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !ready} onClick={send}>
          {busy ? "Asking…" : "Send the invitation"}
        </button>
      </div>
    </div>
  );
}

/* ---------- Pitches and times ---------- */

function Grid({
  blockId,
  slots,
  onChanged,
}: {
  blockId: string;
  slots: Slot[];
  onChanged: () => void;
}) {
  const [courts, setCourts] = useState("Pitch 1\nPitch 2");
  const [firstStart, setFirstStart] = useState("");
  const [minutes, setMinutes] = useState(45);
  const [gap, setGap] = useState(15);
  const [rounds, setRounds] = useState(6);
  const [replace, setReplace] = useState(false);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const generate = async () => {
    const list = courts.split("\n").map((c) => c.trim()).filter(Boolean);
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      const out = await api<{ created: number }>("POST", `/fixture-blocks/${blockId}/slots`, {
        courts: list,
        first_start: new Date(firstStart).toISOString(),
        match_minutes: minutes,
        gap_minutes: gap,
        rounds,
        replace,
      });
      setNote(`${out.created} slots laid out.`);
      onChanged();
    } catch (err) {
      setError(readErr(err, "Could not lay out the grid"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <div className="panel">
        <h2>Lay out the day</h2>
        <p className="muted">
          One slot per pitch per round. Fixtures are dropped into these, so lay out more
          than you think you need — spare slots cost nothing.
        </p>
        <label>
          Pitches, one per line
          <textarea rows={3} value={courts} onChange={(e) => setCourts(e.target.value)} />
        </label>
        <div className="setup-fields">
          <label>
            First game starts
            <input
              type="datetime-local"
              value={firstStart}
              onChange={(e) => setFirstStart(e.target.value)}
            />
          </label>
          <label>
            Each game (minutes)
            <input type="number" min={5} value={minutes}
                   onChange={(e) => setMinutes(Number(e.target.value))} />
          </label>
          <label>
            Gap between (minutes)
            <input type="number" min={0} value={gap}
                   onChange={(e) => setGap(Number(e.target.value))} />
          </label>
          <label>
            Rounds
            <input type="number" min={1} value={rounds}
                   onChange={(e) => setRounds(Number(e.target.value))} />
          </label>
        </div>
        <label className="field-inline">
          <input type="checkbox" checked={replace} onChange={(e) => setReplace(e.target.checked)} />
          Replace the grid rather than adding to it
        </label>
        {error && <p className="error">{error}</p>}
        {note && !error && <p className="muted">{note}</p>}
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn primary" type="button" disabled={busy || !firstStart}
                  onClick={generate}>
            {busy ? "Laying out…" : "Lay out the grid"}
          </button>
        </div>
      </div>

      <div className="panel">
        <div className="panel-head">
          <h2>Free slots</h2>
          <span className="tag grey">{slots.length}</span>
        </div>
        {slots.length === 0 ? (
          <p className="muted">None yet — or every one is taken by a fixture.</p>
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Pitch</th><th>Starts</th><th>Ends</th></tr></thead>
              <tbody>
                {slots.map((s) => (
                  <tr key={s.id}>
                    <td>{s.court_label}</td>
                    <td className="num">{clock(s.starts_at)}</td>
                    <td className="num">{clock(s.ends_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

/* ---------- Fixtures ---------- */

function Fixtures({
  blockId,
  fixtures,
  slots,
  entrants,
  onChanged,
}: {
  blockId: string;
  fixtures: ScheduleRow[];
  slots: Slot[];
  entrants: TournamentEntrant[];
  onChanged: () => void;
}) {
  const [scoring, setScoring] = useState<ScheduleRow | null>(null);
  const [format, setFormat] = useState<TournamentFormat>("round_robin");
  const [groups, setGroups] = useState(2);
  const [rest, setRest] = useState(30);
  const [preview, setPreview] = useState<SchedulePreview | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const run = async (commit: boolean) => {
    setBusy(commit ? "commit" : "preview");
    setError(null);
    try {
      const out = await api<SchedulePreview>("POST", `/fixture-blocks/${blockId}/schedule`, {
        format,
        group_count: format === "groups_knockout" ? groups : null,
        min_rest_minutes: rest,
        commit,
      });
      setPreview(out);
      if (commit) onChanged();
    } catch (err) {
      setError(readErr(err, "Could not build the fixtures"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <div className="panel">
        <h2>Build the fixtures</h2>
        <p className="muted">
          A preview until you commit it. Nothing is written to anybody&apos;s calendar
          until you say so.
        </p>
        <div className="setup-fields">
          <label>
            Format
            <select value={format} onChange={(e) => setFormat(e.target.value as TournamentFormat)}>
              <option value="round_robin">{FORMAT_LABEL.round_robin}</option>
              <option value="groups_knockout">{FORMAT_LABEL.groups_knockout}</option>
              <option value="knockout">{FORMAT_LABEL.knockout}</option>
            </select>
          </label>
          {format === "groups_knockout" && (
            <label>
              How many groups
              <input type="number" min={2} value={groups}
                     onChange={(e) => setGroups(Number(e.target.value))} />
            </label>
          )}
          <label>
            Rest between games (minutes)
            <input type="number" min={0} value={rest}
                   onChange={(e) => setRest(Number(e.target.value))} />
          </label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn" type="button" disabled={busy !== null} onClick={() => run(false)}>
            {busy === "preview" ? "Working…" : "Preview it"}
          </button>
          <button
            className="btn primary"
            type="button"
            disabled={busy !== null || !preview}
            onClick={() => run(true)}
          >
            {busy === "commit" ? "Writing…" : "Commit these fixtures"}
          </button>
        </div>

        {preview && (
          <div className="proposal" style={{ marginTop: "var(--s4)" }}>
            <header>
              <span className="tag gold">{preview.scheduled.length} scheduled</span>
              {preview.byes.length > 0 && (
                <span className="tag grey">{preview.byes.length} byes</span>
              )}
              {preview.committed > 0 && (
                <span className="tag">{preview.committed} written</span>
              )}
            </header>
            {preview.needs_more_slots > 0 && (
              <p className="error">
                {preview.needs_more_slots} fixtures had nowhere to go — lay out more slots,
                or shorten the rest between games. There are {slots.length} free.
              </p>
            )}
          </div>
        )}
      </div>

      <div className="panel">
        <div className="panel-head">
          <h2>The fixture list</h2>
          <span className="tag grey">{fixtures.length}</span>
        </div>
        {fixtures.length === 0 ? (
          <p className="muted">Nothing committed yet.</p>
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>When</th><th>Pitch</th><th>Match</th>
                  <th>Stage</th><th className="n">Result</th><th></th>
                </tr>
              </thead>
              <tbody>
                {fixtures.map((f) => (
                  <tr key={f.event_id}>
                    <td className="num">{clock(f.starts_at)}</td>
                    <td>{f.court_label ?? "—"}</td>
                    <td>{f.home_name ?? "TBC"} v {f.away_name ?? "TBC"}</td>
                    <td className="subtle">
                      {f.group_label ? `Group ${f.group_label}` : f.stage ?? "—"}
                    </td>
                    <td className="n num">
                      {f.home_score != null && f.away_score != null
                        ? `${f.home_score}–${f.away_score}`
                        : "—"}
                    </td>
                    <td className="n">
                      <button
                        className="btn ghost sm"
                        type="button"
                        onClick={() => setScoring(f)}
                      >
                        {f.home_score != null ? "Change" : "Result"}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {scoring && (
        <RecordResult
          row={scoring}
          entrants={entrants}
          onClose={() => setScoring(null)}
          onSaved={() => { setScoring(null); onChanged(); }}
        />
      )}
    </>
  );
}

/// What happened in one game.
///
/// Two scores and who won — and a no-result, because rain does not care that
/// the fixture list said otherwise. Recording this is what moves the table, so
/// it lives on the fixture row rather than behind another screen.
function RecordResult({
  row,
  entrants,
  onClose,
  onSaved,
}: {
  row: ScheduleRow;
  entrants: TournamentEntrant[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const panel = useRef<HTMLDivElement>(null);

  // Below a full fixture list this opens off-screen, and the button looks
  // like it did nothing.
  useEffect(() => {
    panel.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [row.event_id]);

  const find = (name: string | null) => entrants.find((e) => e.name === name);
  const home = find(row.home_name);
  const away = find(row.away_name);

  const [homeScore, setHomeScore] = useState(row.home_score?.toString() ?? "");
  const [awayScore, setAwayScore] = useState(row.away_score?.toString() ?? "");
  const [washout, setWashout] = useState(false);
  const [summary, setSummary] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    if (!home || !away) {
      setError("This fixture is not between two known sides yet.");
      return;
    }
    setBusy(true);
    setError(null);
    const h = Number(homeScore);
    const a = Number(awayScore);
    // Whoever scored more won; equal is a draw. Worked out here rather than
    // asked, because a scorer who types the scores has already said it.
    const outcome = (mine: number, theirs: number) =>
      washout ? "no_result" : mine > theirs ? "win" : mine < theirs ? "loss" : "draw";

    try {
      await api("POST", `/events/${row.event_id}/result`, {
        entrants: [
          { entrant_id: home.id, score: washout ? null : h, result: outcome(h, a) },
          { entrant_id: away.id, score: washout ? null : a, result: outcome(a, h) },
        ],
        summary: summary.trim() || null,
      });
      onSaved();
    } catch (err) {
      setError(readErr(err, "Could not record that"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel" ref={panel}>
      <h2>{row.home_name} v {row.away_name}</h2>
      <div className="setup-fields">
        <label>
          {row.home_name}
          <input
            type="number"
            inputMode="numeric"
            value={homeScore}
            disabled={washout}
            onChange={(e) => setHomeScore(e.target.value)}
          />
        </label>
        <label>
          {row.away_name}
          <input
            type="number"
            inputMode="numeric"
            value={awayScore}
            disabled={washout}
            onChange={(e) => setAwayScore(e.target.value)}
          />
        </label>
      </div>
      <label className="field-inline">
        <input type="checkbox" checked={washout} onChange={(e) => setWashout(e.target.checked)} />
        Abandoned — no result
      </label>
      <label>
        Anything worth remembering
        <input
          value={summary}
          onChange={(e) => setSummary(e.target.value)}
          placeholder="Won off the last ball."
        />
      </label>
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button
          className="btn primary"
          type="button"
          disabled={busy || (!washout && (homeScore === "" || awayScore === ""))}
          onClick={save}
        >
          {busy ? "Recording…" : "Record it"}
        </button>
        <button className="btn" type="button" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}

/* ---------- Table ---------- */

function Table({
  blockId,
  rows,
  onChanged,
}: {
  blockId: string;
  rows: Standing[];
  onChanged: () => void;
}) {
  if (rows.length === 0) {
    return (
      <div className="panel empty">
        <Icon name="chart" size={28} />
        <p>No results yet. The table fills in as games are recorded.</p>
      </div>
    );
  }

  const grouped = byGroup(rows);

  return (
    <>
      {grouped.map((group) => (
        <div className="panel" key={group.label ?? "all"}>
          <h2>{group.label ? `Group ${group.label}` : "Table"}</h2>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Side</th>
                  <th className="n">P</th><th className="n">W</th>
                  <th className="n">L</th><th className="n">D</th>
                  <th className="n">NR</th><th className="n">Diff</th>
                  <th className="n">Pts</th>
                </tr>
              </thead>
              <tbody>
                {group.rows.map((r, i) => (
                  <tr key={r.entrant_id}>
                    <td><span className="num">{i + 1}.</span> {r.name}</td>
                    <td className="n num">{r.played}</td>
                    <td className="n num">{r.won}</td>
                    <td className="n num">{r.lost}</td>
                    <td className="n num">{r.drawn}</td>
                    <td className="n num">{r.no_result}</td>
                    <td className="n num">{difference(r) > 0 ? "+" : ""}{difference(r)}</td>
                    <td className="n num"><strong>{r.points}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ))}

      {/* Offered whenever there is a table to qualify out of — one group of
          eight feeding a semi-final is as real as four groups feeding a
          quarter. The server refuses if the table cannot support it. */}
      <Knockout blockId={blockId} groups={grouped.length} onChanged={onChanged} />
    </>
  );
}

/// Build the knockout from the group tables.
///
/// A preview first, like the group stage — an organiser wants to see who came
/// out of each group before those fixtures land in anybody's calendar.
function Knockout({
  blockId,
  groups,
  onChanged,
}: {
  blockId: string;
  groups: number;
  onChanged: () => void;
}) {
  const [perGroup, setPerGroup] = useState(2);
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const run = async (commit: boolean) => {
    setBusy(commit ? "commit" : "preview");
    setError(null);
    setNote(null);
    try {
      const out = await api<{ committed?: number; scheduled?: unknown[] }>(
        "POST",
        `/fixture-blocks/${blockId}/knockout`,
        { per_group: perGroup, commit }
      );
      const made = out.scheduled?.length ?? 0;
      setNote(
        commit
          ? `${out.committed ?? made} knockout fixtures written.`
          : `${made} knockout fixtures would be created.`
      );
      if (commit) onChanged();
    } catch (err) {
      setError(readErr(err, "Could not build the knockout"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel">
      <h2>Into the knockout</h2>
      <p className="muted">
        Takes the top of {groups === 1 ? "the table" : `each of the ${groups} groups`} as it
        stands now. Run it once the group games are done — running it early builds a bracket
        from an unfinished table.
      </p>
      <label>
        How many go through{groups > 1 ? " from each group" : ""}
        <input
          type="number"
          min={1}
          value={perGroup}
          onChange={(e) => setPerGroup(Number(e.target.value))}
        />
      </label>
      {error && <p className="error">{error}</p>}
      {note && !error && <p className="muted">{note}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn" type="button" disabled={busy !== null} onClick={() => run(false)}>
          {busy === "preview" ? "Working…" : "Preview the bracket"}
        </button>
        <button
          className="btn primary"
          type="button"
          disabled={busy !== null}
          onClick={() => run(true)}
        >
          {busy === "commit" ? "Writing…" : "Build it"}
        </button>
      </div>
    </div>
  );
}

function clock(iso: string): string {
  return new Date(iso).toLocaleString("en-GB", {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

/* ---------- Rules ---------- */

/// What a club is agreeing to when it enters, and what every fixture plays to.
///
/// One screen for three different conversations — entry, who may play, and the
/// playing conditions — because an organiser settles all three in one sitting
/// and a club reading them wants them in one place.
function Rules({
  blockId,
  block,
  onChanged,
}: {
  blockId: string;
  block: FixtureBlock | null;
  onChanged: () => void;
}) {
  const [editing, setEditing] = useState(false);

  if (!block) return <div className="skeleton" style={{ height: 240 }} />;
  if (editing)
    return (
      <RulesForm
        blockId={blockId}
        block={block}
        onClose={() => setEditing(false)}
        onSaved={onChanged}
      />
    );

  const c = block.conditions;
  const money = (p: number) => `£${(p / 100).toFixed(2)}`;
  const when = (iso: string) =>
    new Date(iso).toLocaleString("en-GB", {
      weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
    });

  return (
    <>
      <div className="panel">
        <div className="panel-head">
          <h2>Entry</h2>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            Change the rules
          </button>
        </div>
        <dl className="pro-about">
          <div>
            <dt>Sides</dt>
            <dd>{block.max_entrants ? `Up to ${block.max_entrants}` : "No limit"}</dd>
          </div>
          <div>
            <dt>Entries close</dt>
            <dd>{block.entry_deadline ? when(block.entry_deadline) : "No deadline"}</dd>
          </div>
          <div>
            <dt>Entry fee</dt>
            <dd>{block.entry_fee_cents ? money(block.entry_fee_cents) : "Free to enter"}</dd>
          </div>
        </dl>
      </div>

      <div className="panel">
        <h2>Who may play</h2>
        <dl className="pro-about">
          <div><dt>Players a side</dt><dd className="num">{block.players_per_side}</dd></div>
          <div>
            <dt>Guest players</dt>
            <dd>
              {block.guest_players_allowed === 0
                ? "None — every player must be a club member"
                : `Up to ${block.guest_players_allowed} from outside the club`}
            </dd>
          </div>
          <div><dt>Age group</dt><dd>{AGE_LABEL[block.age_group] ?? block.age_group}</dd></div>
          <div><dt>Who it is for</dt><dd>{GENDER_LABEL[block.gender] ?? block.gender}</dd></div>
        </dl>
      </div>

      <div className="panel">
        <h2>Playing conditions</h2>
        {c ? (
          <>
            <dl className="pro-about">
              <div><dt>Overs an innings</dt><dd className="num">{c.overs_limit}</dd></div>
              <div>
                <dt>Most overs one bowler</dt>
                <dd className="num">{c.overs_per_bowler === 0 ? "No limit" : c.overs_per_bowler}</dd>
              </div>
              <div><dt>Ball</dt><dd>{BALL_LABEL[c.ball] ?? c.ball}</dd></div>
              <div><dt>Ground</dt><dd>{GROUND_LABEL[c.ground] ?? c.ground}</dd></div>
              <div>
                <dt>Powerplay</dt>
                <dd>{c.powerplay_overs === 0 ? "None" : `${c.powerplay_overs} overs`}</dd>
              </div>
            </dl>
            <p className="subtle">
              Every match in this tournament starts on these terms — the scorer
              does not type them again.
            </p>
          </>
        ) : (
          <p className="muted">
            Not set. Each match is agreed between its two captains, as a one-off
            fixture is.
          </p>
        )}
        {block.rules_notes && (
          <>
            <h3 style={{ marginTop: "var(--s4)" }}>Anything else</h3>
            <p style={{ whiteSpace: "pre-wrap" }}>{block.rules_notes}</p>
          </>
        )}
      </div>
    </>
  );
}

function RulesForm({
  blockId,
  block,
  onClose,
  onSaved,
}: {
  blockId: string;
  block: FixtureBlock;
  onClose: () => void;
  onSaved: () => void;
}) {
  const c = block.conditions ?? defaultConditions();
  const [maxEntrants, setMaxEntrants] = useState(block.max_entrants?.toString() ?? "");
  // datetime-local wants "YYYY-MM-DDTHH:mm" in local time, not an ISO instant.
  const [deadline, setDeadline] = useState(
    block.entry_deadline ? toLocalInput(block.entry_deadline) : ""
  );
  const [fee, setFee] = useState(
    block.entry_fee_cents != null ? (block.entry_fee_cents / 100).toFixed(2) : ""
  );
  const [playersPerSide, setPlayersPerSide] = useState(block.players_per_side);
  const [guests, setGuests] = useState(block.guest_players_allowed);
  const [ageGroup, setAgeGroup] = useState(block.age_group);
  const [gender, setGender] = useState(block.gender);
  const [overs, setOvers] = useState(c.overs_limit);
  const [perBowler, setPerBowler] = useState(c.overs_per_bowler);
  const [ball, setBall] = useState(c.ball);
  const [ground, setGround] = useState(c.ground);
  const [powerplay, setPowerplay] = useState(c.powerplay_overs);
  const [notes, setNotes] = useState(block.rules_notes ?? "");
  const [description, setDescription] = useState(block.description ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const feePence =
    fee.trim() === ""
      ? null
      : /^\d+(\.\d{1,2})?$/.test(fee.trim().replace(/^£/, ""))
        ? Math.round(Number(fee.trim().replace(/^£/, "")) * 100)
        : NaN;
  const feeOk = feePence === null || Number.isFinite(feePence);

  const save = async () => {
    setBusy(true);
    setError(null);
    // An emptied box means "remove this", and has to say so: the server
    // leaves alone anything it was not sent, which is what lets one screen
    // edit the entry rules without wiping the playing conditions.
    const clear = [
      maxEntrants.trim() === "" && "max_entrants",
      deadline === "" && "entry_deadline",
      fee.trim() === "" && "entry_fee_cents",
      description.trim() === "" && "description",
      notes.trim() === "" && "rules_notes",
    ].filter((v): v is string => typeof v === "string");

    try {
      await api("PATCH", `/fixture-blocks/${blockId}`, {
        description: description.trim() || null,
        max_entrants: maxEntrants.trim() === "" ? null : Number(maxEntrants),
        entry_deadline: deadline ? new Date(deadline).toISOString() : null,
        entry_fee_cents: feePence,
        players_per_side: playersPerSide,
        guest_players_allowed: guests,
        age_group: ageGroup,
        gender,
        conditions: { ...c, overs_limit: overs, overs_per_bowler: perBowler, ball, ground,
                      powerplay_overs: powerplay },
        rules_notes: notes.trim() || null,
        clear,
      });
      onSaved();
      onClose();
    } catch (err) {
      setError(readErr(err, "Could not save the rules"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>The rules</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
      </div>

      <label>
        What to tell the clubs you invite
        <textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
      </label>

      <fieldset className="setup-group">
        <legend>Entry</legend>
        <div className="setup-fields">
          <label>
            How many sides
            <span className="subtle">Empty for no limit.</span>
            <input type="number" min={2} value={maxEntrants}
                   onChange={(e) => setMaxEntrants(e.target.value)} />
          </label>
          <label>
            Entries close
            <input type="datetime-local" value={deadline}
                   onChange={(e) => setDeadline(e.target.value)} />
          </label>
          <label>
            Entry fee per side
            <input inputMode="decimal" value={fee} onChange={(e) => setFee(e.target.value)}
                   placeholder="50.00" />
          </label>
        </div>
        {!feeOk && <p className="error">Give the entry fee as an amount, like 50.00.</p>}
      </fieldset>

      <fieldset className="setup-group">
        <legend>Who may play</legend>
        <div className="setup-fields">
          <label>
            Players a side
            <input type="number" min={2} max={15} value={playersPerSide}
                   onChange={(e) =>
                     setPlayersPerSide(Math.max(2, Math.min(15, Number(e.target.value) || 11)))} />
          </label>
          <label>
            Guest players allowed
            <span className="subtle">
              {guests === 0
                ? "Every player must be a member of the entering club."
                : `A side may borrow up to ${guests} from outside.`}
            </span>
            <input type="number" min={0} max={playersPerSide} value={guests}
                   onChange={(e) =>
                     setGuests(Math.max(0, Math.min(playersPerSide, Number(e.target.value) || 0)))} />
          </label>
          <label>
            Age group
            <select value={ageGroup} onChange={(e) => setAgeGroup(e.target.value)}>
              {AGE_GROUPS.map((a) => <option key={a} value={a}>{AGE_LABEL[a]}</option>)}
            </select>
          </label>
          <label>
            Who it is for
            <select value={gender} onChange={(e) => setGender(e.target.value)}>
              {GENDERS.map((g) => <option key={g} value={g}>{GENDER_LABEL[g]}</option>)}
            </select>
          </label>
        </div>
      </fieldset>

      <fieldset className="setup-group">
        <legend>Playing conditions</legend>
        <div className="setup-fields">
          <label>
            Overs an innings
            <input type="number" min={1} max={100} value={overs}
                   onChange={(e) => setOvers(Math.max(1, Math.min(100, Number(e.target.value) || 1)))} />
          </label>
          <label>
            Most overs one bowler
            <input type="number" min={1} max={overs} value={perBowler}
                   onChange={(e) =>
                     setPerBowler(Math.max(1, Math.min(overs, Number(e.target.value) || 1)))} />
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
            <input type="number" min={0} max={overs} value={powerplay}
                   onChange={(e) =>
                     setPowerplay(Math.max(0, Math.min(overs, Number(e.target.value) || 0)))} />
          </label>
        </div>
        <label>
          Anything else in the rules
          <textarea rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </label>
        <p className="subtle">
          Changing these does not re-open matches already being scored — they
          keep the terms they started under.
        </p>
      </fieldset>

      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !feeOk} onClick={save}>
          {busy ? "Saving…" : "Save the rules"}
        </button>
        <button className="btn" type="button" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}

/// An instant as `datetime-local` wants it: local wall-clock, no zone.
function toLocalInput(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
