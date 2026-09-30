"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { api, money, readErr } from "@/lib/api";
import {
  AGE_LABEL,
  BALL_LABEL,
  byGroup,
  defaultConditions,
  difference,
  ENTRY_LABEL,
  FORMAT_LABEL,
  GENDER_LABEL,
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
import {
  emptyRules,
  pence,
  rulesPayload,
  rulesSummary,
  TournamentRuleFields,
  type Rules,
  type Venue,
} from "@/components/TournamentRules";
import { type OpponentIdentity } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

type Tab = "entrants" | "grid" | "fixtures" | "table" | "rules";

/// Running one tournament.
///
/// Four steps in the order an organiser works: who is in, when and where they
/// can play, the fixtures generated into that grid, and the table. Each is a
/// tab because they are done at different times — entrants in the week before,
/// the grid the night before, fixtures on the morning, the table all day.
export default function TournamentPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
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
      setError(readErr(err, t("la.could_not_load_this_tournament")));
    } finally {
      setLoading(false);
    }
  }, [id, t]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;
  if (error && entrants.length === 0)
    return <main id="main"><p className="error">{error}</p></main>;
  if (loading)
    return <main id="main"><div className="skeleton" style={{ height: 300 }} /></main>;

  // "In" means confirmed: accepted, and — where the tournament charges — paid.
  // The server draws from exactly this set, so the count on the screen and the
  // sides in the fixture list cannot disagree.
  const fee = block?.entry_fee_cents ?? 0;
  const confirmed = (e: TournamentEntrant) =>
    e.status === "accepted" && (fee === 0 || !!e.entry_paid_at);
  const playing = entrants.filter(confirmed);
  const waiting = entrants.filter((e) => e.status === "invited");
  // Said yes, owes the fee. Chasing them is the organiser's next job, and a
  // single "in" count would hide it.
  const owing = entrants.filter((e) => e.status === "accepted" && fee > 0 && !e.entry_paid_at);

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
          {owing.length > 0 && (
            <span className="tag danger">{owing.length} owe the entry fee</span>
          )}
          <span className="tag grey">{slots.length} free slots</span>
          <span className="tag grey">{fixtures.length} fixtures</span>
        </div>
      </section>

      <div className="people-tabs" role="tablist" aria-label={t("tn.tournament")}>
        {(["entrants", "grid", "fixtures", "table", "rules"] as Tab[]).map((each) => (
          <button
            key={each}
            type="button"
            role="tab"
            aria-selected={tab === each}
            className={tab === each ? "on" : undefined}
            onClick={() => setTab(each)}
          >
            {
              {
                entrants: t("la.who_is_in"),
                grid: t("la.pitches_times"),
                fixtures: t("nav.fixtures"),
                table: t("la.table"),
                rules: t("la.rules"),
              }[each]
            }
          </button>
        ))}
      </div>

      {error && <p className="error">{error}</p>}

      {tab === "entrants" && (
        <Entrants blockId={id} entrants={entrants} entryFee={fee} onChanged={load} />
      )}
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
  entryFee,
  onChanged,
}: {
  blockId: string;
  entrants: TournamentEntrant[];
  /// What a side pays to enter. Zero means nobody owes anything.
  entryFee: number;
  onChanged: () => void;
}) {
  const t = useT();
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
      setError(readErr(err, t("la.that_did_not_work")));
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
  const owing = entrants.filter(
    (e) => e.status === "accepted" && entryFee > 0 && !e.entry_paid_at
  );

  return (
    <>
      <div className="panel">
        <div className="panel-head">
          <h2>{t("tn.the_sides")}</h2>
          {waiting.length > 0 && (
            <span className="tag gold">{waiting.length} yet to answer</span>
          )}
          {owing.length > 0 && (
            <span className="tag danger">{owing.length} owe the entry fee</span>
          )}
        </div>
        {entrants.length === 0 ? (
          <p className="muted">{t("tn.nobody_entered_yet")}</p>
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
                    {e.club_id && <span className="subtle">on {brand.name}</span>}
                    {e.contact_email && !e.club_id && (
                      <span className="subtle">{e.contact_email}</span>
                    )}
                  </span>
                </div>
                <div className="pick-actions">
                  {/* Accepted and owing reads as "in" from the status alone,
                      which is exactly the side the organiser must not build a
                      fixture around. */}
                  {e.status === "accepted" && entryFee > 0 && !e.entry_paid_at ? (
                    <span className="tag danger">Owes {money(entryFee)}</span>
                  ) : (
                    <EntryTag status={e.status} />
                  )}
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
                      {t("tn.withdraw")}
                    </button>
                  )}
                  {e.status === "accepted" && entryFee > 0 && !e.entry_paid_at && (
                    <button
                      className="btn ghost sm"
                      type="button"
                      disabled={busy !== null}
                      onClick={() =>
                        run(
                          e.id,
                          () =>
                            api("POST", `/entrants/${e.id}/mark-entry-paid`, {
                              method: "transfer",
                            }),
                          `${e.name}'s entry fee recorded.`
                        )
                      }
                    >
                      {t("tn.mark_paid")}
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
                      {t("tn.ask_again")}
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
        {error && <p className="error">{error}</p>}
        {note && <p className="notice">{note}</p>}
        {(waiting.length > 0 || owing.length > 0) && (
          <p className="subtle" style={{ marginTop: "var(--s3)" }}>
            {entryFee > 0
              ? t("la.a_side_is_in_the_draw_once_it_has_acce")
              : t("la.only_sides_that_have_accepted_go_into")}
          </p>
        )}
      </div>

      <InviteClub blockId={blockId} onInvited={onChanged} />

      <div className="panel">
        <h2>{t("tn.enter_sides_yourself")}</h2>
        <p className="subtle">
          {t("tn.for_a_side_you_are_entering_on_their_b")}
        </p>
        <label>
          {t("tn.one_per_line")}
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
            {busy === "add" ? t("la.entering") : t("la.enter_them")}
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
  const t = useT();
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
      setError(readErr(err, t("la.could_not_send_that_invitation")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <h2>{t("tn.invite_a_club")}</h2>
      <p className="subtle">
        {t("tn.they_accept_or_decline_themselves_and")}
      </p>

      <OppositionPicker
        onPick={(identity, name) => {
          setPicked(identity);
          setTyped(identity ? "" : name);
        }}
      />

      {offPlatform && (
        <label>
          {t("tn.where_to_send_it")}
          <span className="subtle">
            {typed.trim()} is not on {brand.name}, so they answer by following a link.
          </span>
          <input
            type="email"
            inputMode="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder={t("tn.secretary_theirclub_example")}
          />
        </label>
      )}

      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}
      {link && (
        // Shown because club email goes to a shared inbox somebody checks on
        // Sundays. Passing the link on by hand is often how this actually lands.
        <p className="subtle">
          {t("tn.their_link_if_you_would_rather_send_it")} <code>{link}</code>
        </p>
      )}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !ready} onClick={send}>
          {busy ? t("la.asking") : t("la.send_the_invitation")}
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
  const t = useT();
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
      setError(readErr(err, t("la.could_not_lay_out_the_grid")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <div className="panel">
        <h2>{t("tn.lay_out_the_day")}</h2>
        <p className="muted">
          {t("tn.one_slot_per_pitch_per_round_fixtures")}
        </p>
        <label>
          {t("tn.pitches_one_per_line")}
          <textarea rows={3} value={courts} onChange={(e) => setCourts(e.target.value)} />
        </label>
        <div className="setup-fields">
          <label>
            {t("tn.first_game_starts")}
            <input
              type="datetime-local"
              value={firstStart}
              onChange={(e) => setFirstStart(e.target.value)}
            />
          </label>
          <label>
            {t("tn.each_game_minutes")}
            <input type="number" min={5} value={minutes}
                   onChange={(e) => setMinutes(Number(e.target.value))} />
          </label>
          <label>
            {t("tn.gap_between_minutes")}
            <input type="number" min={0} value={gap}
                   onChange={(e) => setGap(Number(e.target.value))} />
          </label>
          <label>
            {t("tn.rounds")}
            <input type="number" min={1} value={rounds}
                   onChange={(e) => setRounds(Number(e.target.value))} />
          </label>
        </div>
        <label className="field-inline">
          <input type="checkbox" checked={replace} onChange={(e) => setReplace(e.target.checked)} />
          {t("tn.replace_the_grid_rather_than_adding_to")}
        </label>
        {error && <p className="error">{error}</p>}
        {note && !error && <p className="muted">{note}</p>}
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn primary" type="button" disabled={busy || !firstStart}
                  onClick={generate}>
            {busy ? t("la.laying_out") : t("la.lay_out_the_grid")}
          </button>
        </div>
      </div>

      <div className="panel">
        <div className="panel-head">
          <h2>{t("tn.free_slots")}</h2>
          <span className="tag grey">{slots.length}</span>
        </div>
        {slots.length === 0 ? (
          <p className="muted">{t("tn.none_yet_or_every_one_is_taken_by_a_fi")}</p>
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>{t("tn.pitch")}</th><th>{t("tn.starts")}</th><th>{t("tn.ends")}</th></tr></thead>
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
  const t = useT();
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
      setError(readErr(err, t("la.could_not_build_the_fixtures")));
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <div className="panel">
        <h2>{t("tn.build_the_fixtures")}</h2>
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
              {t("tn.how_many_groups")}
              <input type="number" min={2} value={groups}
                     onChange={(e) => setGroups(Number(e.target.value))} />
            </label>
          )}
          <label>
            {t("tn.rest_between_games_minutes")}
            <input type="number" min={0} value={rest}
                   onChange={(e) => setRest(Number(e.target.value))} />
          </label>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button className="btn" type="button" disabled={busy !== null} onClick={() => run(false)}>
            {busy === "preview" ? t("la.working") : t("la.preview_it")}
          </button>
          <button
            className="btn primary"
            type="button"
            disabled={busy !== null || !preview}
            onClick={() => run(true)}
          >
            {busy === "commit" ? t("la.writing") : t("la.commit_these_fixtures")}
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
          <h2>{t("tn.the_fixture_list")}</h2>
          <span className="tag grey">{fixtures.length}</span>
        </div>
        {fixtures.length === 0 ? (
          <p className="muted">{t("tn.nothing_committed_yet")}</p>
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>When</th><th>{t("tn.pitch")}</th><th>{t("tn.match")}</th>
                  <th>{t("tn.stage")}</th><th className="n">Result</th><th></th>
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
                        {f.home_score != null ? t("la.change") : "Result"}
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
  const t = useT();
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
      setError(t("la.this_fixture_is_not_between_two_known"));
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
      setError(readErr(err, t("la.could_not_record_that")));
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
        {t("tn.abandoned_no_result")}
      </label>
      <label>
        {t("tn.anything_worth_remembering")}
        <input
          value={summary}
          onChange={(e) => setSummary(e.target.value)}
          placeholder={t("tn.won_off_the_last_ball")}
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
          {busy ? t("la.recording") : t("la.record_it")}
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
  const t = useT();
  if (rows.length === 0) {
    return (
      <div className="panel empty">
        <Icon name="chart" size={28} />
        <p>{t("tn.no_results_yet_the_table_fills_in_as_g")}</p>
      </div>
    );
  }

  const grouped = byGroup(rows);

  return (
    <>
      {grouped.map((group) => (
        <div className="panel" key={group.label ?? "all"}>
          <h2>{group.label ? `Group ${group.label}` : t("la.table")}</h2>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>{t("tn.side")}</th>
                  <th className="n">P</th><th className="n">W</th>
                  <th className="n">L</th><th className="n">D</th>
                  <th className="n">{t("tn.nr")}</th><th className="n">{t("tn.diff")}</th>
                  <th className="n">{t("tn.pts")}</th>
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
  const t = useT();
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
      setError(readErr(err, t("la.could_not_build_the_knockout")));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel">
      <h2>{t("tn.into_the_knockout")}</h2>
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
          {busy === "preview" ? t("la.working") : t("la.preview_the_bracket")}
        </button>
        <button
          className="btn primary"
          type="button"
          disabled={busy !== null}
          onClick={() => run(true)}
        >
          {busy === "commit" ? t("la.writing") : t("la.build_it")}
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
  const t = useT();
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
          <h2>{t("tn.entry")}</h2>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            {t("tn.change_the_rules")}
          </button>
        </div>
        <dl className="pro-about">
          <div>
            <dt>{t("tn.sides")}</dt>
            <dd>{block.max_entrants ? `Up to ${block.max_entrants}` : t("la.no_limit")}</dd>
          </div>
          <div>
            <dt>{t("tn.entries_close")}</dt>
            <dd>{block.entry_deadline ? when(block.entry_deadline) : t("la.no_deadline")}</dd>
          </div>
          <div>
            <dt>{t("tn.entry_fee")}</dt>
            <dd>{block.entry_fee_cents ? money(block.entry_fee_cents) : t("la.free_to_enter")}</dd>
          </div>
        </dl>
      </div>

      <div className="panel">
        <h2>{t("tn.who_may_play")}</h2>
        <dl className="pro-about">
          <div><dt>{t("tn.players_a_side")}</dt><dd className="num">{block.players_per_side}</dd></div>
          <div>
            <dt>{t("tn.guest_players")}</dt>
            <dd>
              {block.guest_players_allowed === 0
                ? t("la.none_every_player_must_be_a_club_membe")
                : `Up to ${block.guest_players_allowed} from outside the club`}
            </dd>
          </div>
          <div><dt>{t("tn.age_group")}</dt><dd>{t(AGE_LABEL[block.age_group])}</dd></div>
          <div><dt>{t("tn.who_it_is_for")}</dt><dd>{t(GENDER_LABEL[block.gender])}</dd></div>
        </dl>
      </div>

      <div className="panel">
        <h2>{t("tn.playing_conditions")}</h2>
        {c ? (
          <>
            <dl className="pro-about">
              <div><dt>{t("tn.overs_an_innings")}</dt><dd className="num">{c.overs_limit}</dd></div>
              <div>
                <dt>{t("tn.most_overs_one_bowler")}</dt>
                <dd className="num">{c.overs_per_bowler === 0 ? t("la.no_limit") : c.overs_per_bowler}</dd>
              </div>
              <div><dt>Ball</dt><dd>{t(BALL_LABEL[c.ball])}</dd></div>
              <div><dt>Ground</dt><dd>{t(GROUND_LABEL[c.ground])}</dd></div>
              <div>
                <dt>Powerplay</dt>
                <dd>{c.powerplay_overs === 0 ? t("la.none") : `${c.powerplay_overs} overs`}</dd>
              </div>
            </dl>
            <p className="subtle">
              {t("tn.every_match_in_this_tournament_starts")}
            </p>
          </>
        ) : (
          <p className="muted">
            {t("tn.not_set_each_match_is_agreed_between_i")}
          </p>
        )}
        {block.rules_notes && (
          <>
            <h3 style={{ marginTop: "var(--s4)" }}>{t("tn.anything_else")}</h3>
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
  const t = useT();
  const existing = block.conditions ?? defaultConditions();
  // Seeded from what is already stored, so the same fields that created the
  // tournament are the ones that change it — one component, no drift.
  const [rules, setRules] = useState<Rules>(() => ({
    ...emptyRules(),
    description: block.description ?? "",
    maxEntrants: block.max_entrants?.toString() ?? "",
    // datetime-local wants local wall-clock, not an ISO instant.
    entryDeadline: block.entry_deadline ? toLocalInput(block.entry_deadline) : "",
    entryFee: block.entry_fee_cents != null ? (block.entry_fee_cents / 100).toFixed(2) : "",
    venueId: block.venue_id ?? "",
    playersPerSide: block.players_per_side,
    guests: block.guest_players_allowed,
    ageGroup: block.age_group,
    gender: block.gender,
    overs: existing.overs_limit,
    perBowler: existing.overs_per_bowler,
    ball: existing.ball,
    ground: existing.ground,
    powerplay: existing.powerplay_overs,
    rulesNotes: block.rules_notes ?? "",
  }));
  const [venues, setVenues] = useState<Venue[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = (patch: Partial<Rules>) => setRules((r) => ({ ...r, ...patch }));

  useEffect(() => {
    api<Venue[]>("GET", `/clubs/${block.club_id}/venues`)
      .then(setVenues)
      .catch(() => setVenues([]));
  }, [block.club_id]);

  const fee = pence(rules.entryFee);
  const feeOk = fee === null || Number.isFinite(fee);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("PATCH", `/fixture-blocks/${blockId}`, rulesPayload(rules, existing));
      onSaved();
      onClose();
    } catch (err) {
      setError(readErr(err, t("la.could_not_save_the_rules")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>{t("tn.the_rules")}</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
      </div>

      <label>
        {t("tn.what_to_tell_the_clubs_you_invite")}
        <textarea
          rows={2}
          value={rules.description}
          onChange={(e) => set({ description: e.target.value })}
        />
      </label>

      <div style={{ marginTop: "var(--s5)" }}>
        <TournamentRuleFields
          rules={rules}
          set={set}
          venues={venues}
          clubId={block.club_id}
          onVenueAdded={(v) => setVenues((all) => [...all, v])}
        />
      </div>

      <div className="form-summary">
        <Icon name="check" size={16} />
        <span className="form-summary-body">
          <span className="form-summary-title">{t("tn.what_this_tournament_will_be")}</span>
          <span className="form-summary-text">{rulesSummary(rules, t)}</span>
        </span>
      </div>

      <p className="subtle" style={{ marginTop: "var(--s3)" }}>
        {t("tn.changing_these_does_not_re_open_matche")}
      </p>

      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !feeOk} onClick={save}>
          {busy ? t("la.saving") : t("la.save_the_rules")}
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
