"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, readErr } from "@/lib/api";
import {
  byGroup,
  difference,
  FORMAT_LABEL,
  type ScheduleRow,
  type SchedulePreview,
  type Slot,
  type Standing,
  type TournamentEntrant,
  type TournamentFormat,
} from "@/lib/tournament";
import { Icon } from "@/components/Icon";

type Tab = "entrants" | "grid" | "fixtures" | "table";

/// Running one tournament.
///
/// Four steps in the order an organiser works: who is in, when and where they
/// can play, the fixtures generated into that grid, and the table. Each is a
/// tab because they are done at different times — entrants in the week before,
/// the grid the night before, fixtures on the morning, the table all day.
export default function TournamentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [tab, setTab] = useState<Tab>("entrants");
  const [entrants, setEntrants] = useState<TournamentEntrant[]>([]);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [fixtures, setFixtures] = useState<ScheduleRow[]>([]);
  const [table, setTable] = useState<Standing[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const [e, s, f, t] = await Promise.all([
        api<TournamentEntrant[]>("GET", `/fixture-blocks/${id}/entrants`),
        api<{ free: Slot[] }>("GET", `/fixture-blocks/${id}/slots`).catch(() => ({ free: [] })),
        api<ScheduleRow[]>("GET", `/fixture-blocks/${id}/schedule`).catch(() => []),
        api<Standing[]>("GET", `/fixture-blocks/${id}/standings`).catch(() => []),
      ]);
      setEntrants(e);
      setSlots(s.free);
      setFixtures(f);
      setTable(t);
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load this tournament"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to run this tournament.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  if (error && entrants.length === 0)
    return <main id="main"><p className="error">{error}</p></main>;
  if (loading)
    return <main id="main"><div className="skeleton" style={{ height: 300 }} /></main>;

  const playing = entrants.filter((e) => !e.withdrawn);

  return (
    <main id="main">
      <section className="hero">
        <h1>Tournament</h1>
        <div className="hero-tags">
          <span className="tag">{playing.length} in</span>
          <span className="tag grey">{slots.length} free slots</span>
          <span className="tag grey">{fixtures.length} fixtures</span>
        </div>
      </section>

      <div className="people-tabs" role="tablist" aria-label="Tournament">
        {(["entrants", "grid", "fixtures", "table"] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            role="tab"
            aria-selected={tab === t}
            className={tab === t ? "on" : undefined}
            onClick={() => setTab(t)}
          >
            {{ entrants: "Who is in", grid: "Pitches & times", fixtures: "Fixtures", table: "Table" }[t]}
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

  const add = async () => {
    // One per line: pasting a list out of an email is how entries actually
    // arrive, and re-typing them into a form one at a time is the reason
    // organisers keep using a spreadsheet.
    const rows = names.split("\n").map((n) => n.trim()).filter(Boolean);
    if (rows.length === 0) return;
    setBusy("add");
    setError(null);
    try {
      await api("POST", `/fixture-blocks/${blockId}/entrants`, {
        entrants: rows.map((name) => ({ name })),
      });
      setNames("");
      onChanged();
    } catch (err) {
      setError(readErr(err, "Could not add those"));
    } finally {
      setBusy(null);
    }
  };

  const withdraw = async (entrantId: string) => {
    setBusy(entrantId);
    setError(null);
    try {
      await api("POST", `/entrants/${entrantId}/withdraw`, {});
      onChanged();
    } catch (err) {
      setError(readErr(err, "Could not withdraw them"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <div className="panel">
        <h2>The sides</h2>
        {entrants.length === 0 ? (
          <p className="muted">Nobody entered yet.</p>
        ) : (
          <ul className="pick-list">
            {entrants.map((e) => (
              <li key={e.id} className={e.withdrawn ? "reserve" : undefined}>
                <span className="thread-mark" aria-hidden>
                  {e.group_label ?? (e.seed ? `#${e.seed}` : "–")}
                </span>
                <div className="pick-who">
                  <strong>{e.name}</strong>
                  {e.withdrawn && <span className="subtle">withdrawn</span>}
                </div>
                {!e.withdrawn && (
                  <div className="pick-actions">
                    <button
                      className="btn ghost sm"
                      type="button"
                      disabled={busy === e.id}
                      onClick={() => withdraw(e.id)}
                    >
                      Withdraw
                    </button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="panel">
        <h2>Add sides</h2>
        <label>
          One per line
          <textarea
            rows={5}
            value={names}
            onChange={(e) => setNames(e.target.value)}
            placeholder={"Hemel CC\nWatford Wanderers\nSt Albans 2nd XI"}
          />
        </label>
        {error && <p className="error">{error}</p>}
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn primary" type="button" disabled={busy !== null || !names.trim()}
                  onClick={add}>
            {busy === "add" ? "Adding…" : "Add them"}
          </button>
        </div>
      </div>
    </>
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
