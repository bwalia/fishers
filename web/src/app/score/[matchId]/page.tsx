"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, getStoredUser } from "@/lib/api";
import { WagonWheel } from "@/components/WagonWheel";
import { Icon } from "@/components/Icon";
import { ShotIcon, SHOT_SHAPES } from "@/components/ShotIcon";
import {
  BALLS,
  DEFAULT_CONDITIONS,
  DISMISSALS,
  DISMISSALS_WITH_FIELDER,
  EXTRA_KINDS,
  GROUNDS,
  commentaryFor,
  overs,
  titleCase,
  type MatchConditions,
  type MatchResponse,
  type MatchState,
} from "@/lib/cricket";

/// The device the book is held on. The API ties the scoring lock to it, so it
/// has to survive a refresh or the scorer loses their own claim.
function deviceId() {
  const KEY = "fishers_device_id";
  let id = localStorage.getItem(KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(KEY, id);
  }
  return id;
}

function ballClass(ball: { runs: number; is_wicket: boolean }) {
  if (ball.is_wicket) return "wicket";
  if (ball.runs >= 6) return "six";
  if (ball.runs >= 4) return "boundary";
  return undefined;
}

type Side = "home" | "away";

const other = (s: Side): Side => (s === "home" ? "away" : "home");

export default function ScorerPage({
  params,
}: {
  params: Promise<{ matchId: string }>;
}) {
  const { matchId } = use(params);
  const [match, setMatch] = useState<MatchResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setMatch(await api<MatchResponse>("GET", `/cricket/matches/${matchId}`));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load the match");
    }
  }, [matchId]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to score a match.");
      return;
    }
    load();
  }, [load]);

  /// Every action is one event appended to the log. The server replays the log,
  /// applies the Laws and hands back the new state — the browser never decides
  /// anything itself, so it cannot disagree with the app.
  const send = useCallback(
    async (kind: Record<string, unknown>) => {
      if (!match) return;
      setBusy(true);
      setError(null);
      const at = new Date().toISOString();
      let seq = match.state.last_seq;
      const events: Record<string, unknown>[] = [];

      // The log is the only lasting record: the server seeds the team names
      // from the fixture row only while nothing has been scored, and replays
      // from the log after that. Without this first event the names would
      // revert to "Home"/"Away" the moment a second batch arrived.
      if (seq === 0 && kind.type !== "match_prepared") {
        events.push({
          client_event_id: crypto.randomUUID(),
          seq: ++seq,
          kind: {
            type: "match_prepared",
            overs_limit: match.overs_limit,
            home_name: match.home_name,
            away_name: match.away_name,
          },
          at,
        });
      }
      // The engine demands the next seq exactly; it is the server's count,
      // never a local one.
      events.push({ client_event_id: crypto.randomUUID(), seq: ++seq, kind, at });

      try {
        const next = await api<MatchResponse>(
          "POST",
          `/cricket/matches/${matchId}/events`,
          { device_id: deviceId(), events }
        );
        setMatch(next);
      } catch (err) {
        setError(err instanceof Error ? err.message : "The API rejected that");
      } finally {
        setBusy(false);
      }
    },
    [match, matchId]
  );

  const claim = async (force: boolean) => {
    setBusy(true);
    setError(null);
    try {
      setMatch(
        await api<MatchResponse>("POST", `/cricket/matches/${matchId}/claim-scorer`, {
          device_id: deviceId(),
          force,
        })
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not claim the book");
    } finally {
      setBusy(false);
    }
  };

  if (error && !match) return <main id="main"><p className="error">{error}</p></main>;
  if (!match) return <main><p className="muted">Loading match…</p></main>;

  const st = match.state;
  const me = getStoredUser();
  const heldByMe = match.active_scorer_user_id === me?.id;
  const heldBySomeoneElse =
    !!match.active_scorer_user_id && !heldByMe;
  const canAct = match.can_score && heldByMe && !busy;

  const nameOf = (id?: string | null) =>
    !id ? "—" : st.player_names[id] || st.player_names[id.toLowerCase()] || id.slice(0, 8);

  return (
    <main>
      <section className="hero">
        <h1>
          {st.home_name} vs {st.away_name}
        </h1>
        <p>
          {titleCase(st.status)}
          {st.conditions &&
            ` · ${st.conditions.overs_limit} overs · ${st.conditions.ball} ball · ${st.conditions.ground} ground`}
        </p>
      </section>

      {error && <p className="error">{error}</p>}

      {!match.can_score && (
        <p className="error">
          You do not have permission to score this match. A captain or club secretary can
          give it to you.
        </p>
      )}

      {match.can_score && !match.active_scorer_user_id && (
        <div className="panel">
          <p>Nobody is scoring this match yet.</p>
          <button className="btn primary" type="button" disabled={busy} onClick={() => claim(false)}>
            Take the book
          </button>
        </div>
      )}

      {heldBySomeoneElse && (
        <div className="panel">
          <p className="error">
            Someone else is scoring this match. Only they can record a ball until they hand
            over.
          </p>
          <button className="btn ghost" type="button" disabled={busy} onClick={() => claim(true)}>
            Take it over (captain or secretary only, and it is logged)
          </button>
          <button className="btn ghost" type="button" onClick={load} style={{ marginLeft: "0.5rem" }}>
            Refresh
          </button>
        </div>
      )}

      <Stages match={match} send={send} canAct={canAct} nameOf={nameOf} />

      <Scorecard st={st} nameOf={nameOf} />

      <p className="muted" style={{ marginTop: "1rem" }}>
        <Link href="/score">← All fixtures</Link>
      </p>
    </main>
  );
}

/// Which panel the scorer needs is decided by the state, not by a wizard step
/// the browser remembers — reopening the page mid-match lands in the right place.
function Stages({
  match,
  send,
  canAct,
  nameOf,
}: {
  match: MatchResponse;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  nameOf: (id?: string | null) => string;
}) {
  const st = match.state;
  const agreed = !!st.agreed_home && !!st.agreed_away;
  const current = st.innings[st.innings.length - 1];
  const needsInnings = !current || current.complete;

  if (st.status === "complete") {
    return (
      <div className="panel">
        <h2>Result</h2>
        <p>{st.margin || "Match complete."}</p>
        {st.player_of_the_match && <p className="muted">Player of the match: {nameOf(st.player_of_the_match)}</p>}
      </div>
    );
  }
  if (!agreed) return <ConditionsPanel st={st} send={send} canAct={canAct} />;
  if (!st.toss_winner) return <TossPanel st={st} send={send} canAct={canAct} />;
  if (st.home_xi.length === 0 || st.away_xi.length === 0)
    return <XiPanel st={st} send={send} canAct={canAct} />;
  if (needsInnings) return <OpenersPanel st={st} send={send} canAct={canAct} nameOf={nameOf} />;
  return <LivePanel match={match} send={send} canAct={canAct} nameOf={nameOf} />;
}

function ConditionsPanel({
  st,
  send,
  canAct,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
}) {
  const [c, setC] = useState<MatchConditions>(st.conditions ?? DEFAULT_CONDITIONS);
  const [by, setBy] = useState<Side>("home");
  const [name, setName] = useState("");

  const num = (k: keyof MatchConditions) => ({
    type: "number",
    value: c[k] as number,
    onChange: (e: React.ChangeEvent<HTMLInputElement>) =>
      setC({ ...c, [k]: Number(e.target.value) }),
  });

  return (
    <div className="panel">
      <h2>Match conditions</h2>
      <p className="muted">
        Both captains have to agree the terms before the toss. Proposing counts as the
        proposer agreeing; changing anything later clears both agreements.
      </p>

      <div className="form">
        <label>Overs <input {...num("overs_limit")} /></label>
        <label>Overs per bowler (0 = no limit) <input {...num("overs_per_bowler")} /></label>
        <label>
          Ground
          <select value={c.ground} onChange={(e) => setC({ ...c, ground: e.target.value })}>
            {GROUNDS.map((g) => <option key={g} value={g}>{titleCase(g)}</option>)}
          </select>
        </label>
        <label>
          Ball
          <select value={c.ball} onChange={(e) => setC({ ...c, ball: e.target.value })}>
            {BALLS.map((b) => <option key={b} value={b}>{titleCase(b)}</option>)}
          </select>
        </label>
        <label>Powerplay overs <input {...num("powerplay_overs")} /></label>
        <label>Fielders outside in the powerplay <input {...num("fielders_outside_powerplay")} /></label>
        <label>Fielders outside after it <input {...num("fielders_outside_normal")} /></label>
        <label>Target overs per hour (0 = not counted) <input {...num("target_overs_per_hour")} /></label>
        <label>
          Proposing captain
          <select value={by} onChange={(e) => setBy(e.target.value as Side)}>
            <option value="home">{st.home_name}</option>
            <option value="away">{st.away_name}</option>
          </select>
        </label>
        <label>
          Captain&apos;s name
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Ravi" />
        </label>
      </div>

      <button
        className="btn primary"
        type="button"
        disabled={!canAct || !name.trim()}
        onClick={() =>
          send({ type: "conditions_proposed", conditions: c, by, by_name: name.trim() })
        }
      >
        Propose these terms
      </button>

      <div className="row" style={{ marginTop: "1rem" }}>
        <div>
          <div>{st.home_name}</div>
          <div className="muted">{st.agreed_home ? `Agreed — ${st.agreed_home}` : "Not agreed"}</div>
        </div>
        <div>
          <div>{st.away_name}</div>
          <div className="muted">{st.agreed_away ? `Agreed — ${st.agreed_away}` : "Not agreed"}</div>
        </div>
      </div>

      {st.conditions_proposed_by && (
        <AgreeRow st={st} send={send} canAct={canAct} />
      )}
    </div>
  );
}

function AgreeRow({
  st,
  send,
  canAct,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
}) {
  const pending: Side = st.agreed_home ? "away" : "home";
  const [name, setName] = useState("");
  return (
    <div style={{ marginTop: "1rem" }}>
      <h3>Agreement from {pending === "home" ? st.home_name : st.away_name}</h3>
      <div className="select-row">
        <input
          placeholder="Their captain's name"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button
          className="btn primary"
          type="button"
          disabled={!canAct || !name.trim()}
          onClick={() =>
            send({ type: "conditions_agreed", side: pending, captain_name: name.trim() })
          }
        >
          Agree the terms
        </button>
      </div>
    </div>
  );
}

function TossPanel({
  st,
  send,
  canAct,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
}) {
  const [winner, setWinner] = useState<Side>("home");
  const [decision, setDecision] = useState<"bat" | "bowl">("bat");
  return (
    <div className="panel">
      <h2>Toss</h2>
      <div className="select-row">
        <select value={winner} onChange={(e) => setWinner(e.target.value as Side)}>
          <option value="home">{st.home_name}</option>
          <option value="away">{st.away_name}</option>
        </select>
        <select value={decision} onChange={(e) => setDecision(e.target.value as "bat" | "bowl")}>
          <option value="bat">chose to bat</option>
          <option value="bowl">chose to bowl</option>
        </select>
        <button
          className="btn primary"
          type="button"
          disabled={!canAct}
          onClick={() => send({ type: "toss_recorded", winner, decision })}
        >
          Record the toss
        </button>
      </div>
    </div>
  );
}

/// One name per line, `(L)` after a left-hander so the wagon wheel mirrors them.
function parseXi(text: string) {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((line) => {
      const batsLeft = /\(l\)\s*$/i.test(line);
      return {
        id: crypto.randomUUID(),
        name: line.replace(/\(l\)\s*$/i, "").trim(),
        bats_left: batsLeft,
      };
    });
}

function XiPanel({
  st,
  send,
  canAct,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
}) {
  const side: Side = st.home_xi.length === 0 ? "home" : "away";
  const label = side === "home" ? st.home_name : st.away_name;
  const [text, setText] = useState("");
  const players = useMemo(() => parseXi(text), [text]);
  const [captain, setCaptain] = useState(0);
  const [keeper, setKeeper] = useState(1);

  return (
    <div className="panel">
      <h2>Team sheet — {label}</h2>
      <p className="muted">
        One name per line, in batting order. Add <code>(L)</code> after a left-hander so
        the wagon wheel mirrors their shots. Two to fifteen players.
      </p>
      <div className="form">
        <label>
          Players
          <textarea
            rows={12}
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={"Ravi Sharma\nSam Blake (L)\n…"}
            style={{ width: "100%", fontFamily: "inherit", padding: "0.5rem" }}
          />
        </label>
      </div>
      {players.length > 0 && (
        <div className="select-row">
          <label>
            Captain{" "}
            <select value={captain} onChange={(e) => setCaptain(Number(e.target.value))}>
              {players.map((p, i) => <option key={p.id} value={i}>{p.name}</option>)}
            </select>
          </label>
          <label>
            Keeper{" "}
            <select value={keeper} onChange={(e) => setKeeper(Number(e.target.value))}>
              {players.map((p, i) => <option key={p.id} value={i}>{p.name}</option>)}
            </select>
          </label>
        </div>
      )}
      <button
        className="btn primary"
        type="button"
        disabled={!canAct || players.length < 2}
        onClick={() =>
          send({
            type: "xi_selected",
            side,
            players,
            captain_id: players[captain]?.id ?? null,
            keeper_id: players[keeper]?.id ?? null,
          })
        }
      >
        Confirm {label} ({players.length})
      </button>
    </div>
  );
}

function OpenersPanel({
  st,
  send,
  canAct,
  nameOf,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  nameOf: (id?: string | null) => string;
}) {
  const index = st.innings.length;
  // Whoever won the toss and chose to bat opens; the sides swap after that.
  const first: Side =
    st.toss_decision === "bat"
      ? (st.toss_winner as Side)
      : other(st.toss_winner as Side);
  const batting: Side = index % 2 === 0 ? first : other(first);
  const battingXi = batting === "home" ? st.home_xi : st.away_xi;
  const bowlingXi = batting === "home" ? st.away_xi : st.home_xi;

  const [striker, setStriker] = useState(battingXi[0] ?? "");
  const [nonStriker, setNonStriker] = useState(battingXi[1] ?? "");
  const [bowler, setBowler] = useState(bowlingXi[0] ?? "");

  return (
    <div className="panel">
      <h2>Start innings {index + 1}</h2>
      <p className="muted">
        {batting === "home" ? st.home_name : st.away_name} batting
        {st.target ? ` · chasing ${st.target}` : ""}
      </p>
      <div className="select-row">
        <label>
          Striker{" "}
          <select value={striker} onChange={(e) => setStriker(e.target.value)}>
            {battingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
        <label>
          Non-striker{" "}
          <select value={nonStriker} onChange={(e) => setNonStriker(e.target.value)}>
            {battingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
        <label>
          Opening bowler{" "}
          <select value={bowler} onChange={(e) => setBowler(e.target.value)}>
            {bowlingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
      </div>
      <button
        className="btn primary"
        type="button"
        disabled={!canAct || !striker || !nonStriker || striker === nonStriker || !bowler}
        onClick={() =>
          send({
            type: "innings_started",
            innings_index: index,
            batting,
            striker_id: striker,
            non_striker_id: nonStriker,
            bowler_id: bowler,
            super_over: false,
          })
        }
      >
        Start the innings
      </button>
    </div>
  );
}

/// The scoring surface.
///
/// One tap records a ball. The detail — which stroke, where it went — is asked
/// *after* the runs, in that order, and every step can be skipped, because a
/// scorer's hands are busy and the ball has already happened.
type Draft = {
  runs: number;
  /// Set when this ball is an extra rather than a delivery off the bat.
  extra?: string;
  boundary?: boolean;
  offTheBat?: boolean;
  shotKind?: string;
  step: "detail" | "shot" | "direction";
};

const ASK_KEY = "fishers_ask_shot";

function LivePanel({
  match,
  send,
  canAct,
  nameOf,
}: {
  match: MatchResponse;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  nameOf: (id?: string | null) => string;
}) {
  const st = match.state;
  const inn = st.innings[st.innings.length - 1];
  const battingSide = inn.batting as Side;
  const battingXi = battingSide === "home" ? st.home_xi : st.away_xi;
  const bowlingXi = battingSide === "home" ? st.away_xi : st.home_xi;
  const outIds = new Set(inn.batters.filter((b) => b.out).map((b) => b.player_id));
  const available = battingXi.filter(
    (id) => !outIds.has(id) && id !== inn.striker_id && id !== inn.non_striker_id
  );
  const batsLeft = (st.left_handers || []).includes((inn.striker_id || "").toLowerCase());

  const [draft, setDraft] = useState<Draft | null>(null);
  const [sheet, setSheet] = useState<null | "wicket" | "more">(null);
  const [askShot, setAskShot] = useState(true);

  useEffect(() => {
    setAskShot(localStorage.getItem(ASK_KEY) !== "0");
  }, []);
  const toggleAsk = (on: boolean) => {
    setAskShot(on);
    localStorage.setItem(ASK_KEY, on ? "1" : "0");
  };

  /// Turn the draft into the one event it represents and send it.
  const record = async (d: Draft, shot?: { angle: number; kind: string; reach: number }) => {
    const kind = d.extra
      ? {
          type: "extras_recorded",
          kind: d.extra,
          runs: d.runs,
          boundary: !!d.boundary,
          off_the_bat: d.extra === "no_ball" ? !!d.offTheBat : false,
          ...(shot ? { shot } : {}),
        }
      : {
          type: "delivery_recorded",
          runs: d.runs,
          is_legal: true,
          is_boundary_four: d.runs === 4,
          is_boundary_six: d.runs === 6,
          ...(shot ? { shot } : {}),
        };
    setDraft(null);
    await send(kind);
  };

  const startRuns = (runs: number) => {
    const d: Draft = { runs, step: "shot" };
    if (!askShot) return record(d);
    setDraft(d);
  };

  const startExtra = (extra: string) => {
    setDraft({ runs: 0, extra, step: "detail" });
  };

  const pickShot = (kindName: string) => {
    if (!draft) return;
    const shape = SHOT_SHAPES.find((s) => s.kind === kindName);
    // A block or a leave has no direction worth plotting.
    if (!shape || shape.angle === null) {
      return record(draft, { angle: 0, kind: kindName, reach: 0.15 });
    }
    setDraft({ ...draft, shotKind: kindName, step: "direction" });
  };

  const inPowerplay =
    (inn.powerplay_overs ?? 0) > 0 && inn.legal_balls < (inn.powerplay_overs ?? 0) * 6;
  const allowedOutside = inPowerplay
    ? st.conditions?.fielders_outside_powerplay
    : st.conditions?.fielders_outside_normal;
  const fieldBreach =
    allowedOutside != null &&
    inn.fielders_outside != null &&
    inn.fielders_outside > allowedOutside;

  const thisOver = (inn.deliveries || []).filter((d) => d.over === Math.floor(inn.legal_balls / 6));

  return (
    <>
      <div className="matchbar">
        <div>
          <span className="scoreline">
            {inn.runs}/{inn.wickets}
          </span>{" "}
          <span className="muted">({overs(inn.legal_balls)} ov)</span>
          {st.target != null && (
            <div className="muted">
              Needs {Math.max(0, st.target - inn.runs)} from{" "}
              {Math.max(0, (inn.overs_available ?? st.overs_limit) * 6 - inn.legal_balls)}
            </div>
          )}
        </div>
        <div className="crease">
          <div>
            <strong>{nameOf(inn.striker_id)}</strong> <span className="muted">striker</span>
          </div>
          <div>
            <strong>{nameOf(inn.non_striker_id)}</strong> <span className="muted">non-striker</span>
          </div>
          <div>
            <strong>{nameOf(inn.bowler_id)}</strong> <span className="muted">bowling</span>
          </div>
        </div>
      </div>

      <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap", marginBottom: "var(--s3)" }}>
        {inn.free_hit && <span className="tag gold">Free hit</span>}
        {inPowerplay && <span className="tag">Powerplay</span>}
        {match.dls && (
          <span className="tag grey">
            DLS par {match.dls.par} · {match.dls.ahead_by >= 0 ? "+" : ""}
            {match.dls.ahead_by}
          </span>
        )}
        {thisOver.length > 0 && (
          <span className="tag grey">
            This over: {thisOver.map((d) => d.label).join(" ")}
          </span>
        )}
      </div>

      {fieldBreach && (
        <p className="error">
          {inn.fielders_outside} fielders outside the circle — only {allowedOutside} allowed.
        </p>
      )}

      <div className="panel">
        <div className="panel-head">
          <h2>Runs off the bat</h2>
          <label className="checkbox" style={{ fontSize: "0.85rem" }}>
            <input
              type="checkbox"
              checked={askShot}
              onChange={(e) => toggleAsk(e.target.checked)}
            />
            Ask for the shot
          </label>
        </div>
        <div className="runs">
          {[0, 1, 2, 3, 4, 5, 6].map((n) => (
            <button
              key={n}
              className={n === 4 || n === 6 ? "btn primary" : "btn"}
              type="button"
              disabled={!canAct}
              onClick={() => startRuns(n)}
            >
              {n}
            </button>
          ))}
        </div>
      </div>

      <div className="panel">
        <h2>Extras, wickets and the rest</h2>
        <div className="actions">
          {EXTRA_KINDS.map((k) => (
            <button key={k} className="btn" type="button" disabled={!canAct} onClick={() => startExtra(k)}>
              {titleCase(k)}
            </button>
          ))}
          <button className="btn danger" type="button" disabled={!canAct} onClick={() => setSheet("wicket")}>
            Wicket
          </button>
          <button className="btn ghost" type="button" disabled={!canAct} onClick={() => send({ type: "undo_last" })}>
            <Icon name="arrowLeft" size={16} /> Undo
          </button>
          <button className="btn ghost" type="button" disabled={!canAct} onClick={() => setSheet("more")}>
            More
          </button>
        </div>
      </div>

      {/* ---- the guided ball flow ---- */}
      {draft && draft.step === "detail" && (
        <Sheet title={`${titleCase(draft.extra || "Extra")}`} step={1} of={2} onClose={() => setDraft(null)}>
          <p className="muted">
            How many did they run on top of the {titleCase(draft.extra || "extra").toLowerCase()}?
          </p>
          <div className="runs">
            {[0, 1, 2, 3, 4].map((n) => (
              <button
                key={n}
                className={draft.runs === n ? "btn primary" : "btn"}
                type="button"
                onClick={() => setDraft({ ...draft, runs: n, boundary: n === 4 })}
              >
                {n}
              </button>
            ))}
          </div>
          {draft.extra === "no_ball" && (
            <label className="checkbox" style={{ marginTop: "var(--s3)" }}>
              <input
                type="checkbox"
                checked={!!draft.offTheBat}
                onChange={(e) => setDraft({ ...draft, offTheBat: e.target.checked })}
              />
              Came off the bat
            </label>
          )}
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft(null)}>
              Cancel
            </button>
            <button
              className="btn primary"
              type="button"
              onClick={() =>
                draft.offTheBat && askShot
                  ? setDraft({ ...draft, step: "shot" })
                  : record(draft)
              }
            >
              Record
            </button>
          </div>
        </Sheet>
      )}

      {draft && draft.step === "shot" && (
        <Sheet
          title={draft.runs === 0 ? "No run — which shot?" : `${draft.runs} — which shot?`}
          step={draft.extra ? 2 : 1}
          of={draft.extra ? 3 : 2}
          onClose={() => setDraft(null)}
        >
          <div className="shot-grid">
            {SHOT_SHAPES.map((s) => (
              <button
                key={s.kind}
                className="shot-option"
                type="button"
                aria-pressed={draft.shotKind === s.kind}
                onClick={() => pickShot(s.kind)}
              >
                <ShotIcon shape={s} />
                {s.label}
                <span className="hint">{s.hint}</span>
              </button>
            ))}
          </div>
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft(null)}>
              Cancel
            </button>
            <button className="btn" type="button" onClick={() => record(draft)}>
              Skip — just the runs
            </button>
          </div>
        </Sheet>
      )}

      {draft && draft.step === "direction" && (
        <Sheet
          title="Where did it go?"
          step={draft.extra ? 3 : 2}
          of={draft.extra ? 3 : 2}
          onClose={() => setDraft(null)}
        >
          <p className="muted">
            Tap the field. Nearer the rope means it carried further — the commentary reads
            from this.
          </p>
          <div style={{ display: "flex", justifyContent: "center" }}>
            <WagonWheel
              deliveries={inn.deliveries || []}
              batsLeft={batsLeft}
              onPick={(angle, reach) =>
                record(draft, { angle, kind: draft.shotKind || "other", reach })
              }
            />
          </div>
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft({ ...draft, step: "shot" })}>
              Back
            </button>
            <button
              className="btn"
              type="button"
              onClick={() =>
                record(draft, { angle: 0, kind: draft.shotKind || "other", reach: 0.5 })
              }
            >
              Skip direction
            </button>
          </div>
        </Sheet>
      )}

      {sheet === "wicket" && (
        <WicketSheet
          key={`${inn.striker_id}-${inn.wickets}`}
          send={send}
          onClose={() => setSheet(null)}
          striker={inn.striker_id ?? ""}
          nonStriker={inn.non_striker_id ?? ""}
          available={available}
          bowlingXi={bowlingXi}
          nameOf={nameOf}
        />
      )}

      {sheet === "more" && (
        <MoreSheet
          send={send}
          onClose={() => setSheet(null)}
          st={st}
          inn={inn}
          bowlingXi={bowlingXi}
          nameOf={nameOf}
        />
      )}

      <div className="panel">
        <h2>Commentary</h2>
        <ul className="commentary">
          {[...(inn.deliveries || [])]
            .reverse()
            .slice(0, 12)
            .map((ball, i) => (
              <li key={i} className={ballClass(ball)}>
                <span className="ball">
                  {ball.over}.{ball.ball_in_over}
                </span>
                <span>{commentaryFor(ball, nameOf, st.left_handers || [])}</span>
              </li>
            ))}
          {(inn.deliveries || []).length === 0 && (
            <li className="muted">No balls yet.</li>
          )}
        </ul>
      </div>
    </>
  );
}

/// A bottom sheet. Escape closes it, and the backdrop is a real button so a
/// keyboard user is never trapped.
function Sheet({
  title,
  step,
  of,
  onClose,
  children,
}: {
  title: string;
  step?: number;
  of?: number;
  onClose: () => void;
  children: React.ReactNode;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="sheet-backdrop"
      role="presentation"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title}>
        <div className="sheet-head">
          <h2>{title}</h2>
          <button className="btn ghost sm" type="button" onClick={onClose} aria-label="Close">
            Close
          </button>
        </div>
        {of && (
          <div className="sheet-steps" aria-hidden="true">
            {Array.from({ length: of }, (_, i) => (
              <span key={i} className={i < (step ?? 0) ? "on" : undefined} />
            ))}
          </div>
        )}
        {children}
      </div>
    </div>
  );
}

function WicketSheet({
  send,
  onClose,
  striker,
  nonStriker,
  available,
  bowlingXi,
  nameOf,
}: {
  send: (kind: Record<string, unknown>) => Promise<void>;
  onClose: () => void;
  striker: string;
  nonStriker: string;
  available: string[];
  bowlingXi: string[];
  nameOf: (id?: string | null) => string;
}) {
  const [kind, setKind] = useState<string>("bowled");
  const [batter, setBatter] = useState(striker);
  const [fielder, setFielder] = useState("");
  const [newBatter, setNewBatter] = useState(available[0] ?? "");
  const [runsBefore, setRunsBefore] = useState(0);
  const [onExtra, setOnExtra] = useState(false);

  return (
    <Sheet title="Wicket" onClose={onClose}>
      <div className="actions" style={{ marginBottom: "var(--s3)" }}>
        {DISMISSALS.map((d) => (
          <button
            key={d}
            className={kind === d ? "btn primary" : "btn"}
            type="button"
            onClick={() => setKind(d)}
          >
            {titleCase(d)}
          </button>
        ))}
      </div>
      <div className="form">
        <label>
          Who is out
          <select value={batter} onChange={(e) => setBatter(e.target.value)}>
            <option value={striker}>{nameOf(striker)} (striker)</option>
            <option value={nonStriker}>{nameOf(nonStriker)} (non-striker)</option>
          </select>
        </label>
        {DISMISSALS_WITH_FIELDER.includes(kind) && (
          <label>
            Fielder
            <select value={fielder} onChange={(e) => setFielder(e.target.value)}>
              <option value="">—</option>
              {bowlingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
            </select>
          </label>
        )}
        <label>
          Next in
          <select value={newBatter} onChange={(e) => setNewBatter(e.target.value)}>
            <option value="">— innings ends —</option>
            {available.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
        <label>
          Runs completed first
          <input
            type="number"
            min={0}
            max={6}
            value={runsBefore}
            onChange={(e) => setRunsBefore(Number(e.target.value))}
          />
        </label>
      </div>
      <label className="checkbox" style={{ marginTop: "var(--s3)" }}>
        <input type="checkbox" checked={onExtra} onChange={(e) => setOnExtra(e.target.checked)} />
        On a ball already recorded as an extra
      </label>
      <div className="sheet-actions">
        <button className="btn ghost" type="button" onClick={onClose}>Cancel</button>
        <button
          className="btn danger"
          type="button"
          onClick={async () => {
            onClose();
            await send({
              type: "wicket_recorded",
              batter_id: batter,
              kind,
              fielder_id: fielder || null,
              new_batter_id: newBatter || null,
              runs: runsBefore,
              on_extra: onExtra,
            });
          }}
        >
          Record wicket
        </button>
      </div>
    </Sheet>
  );
}

function MoreSheet({
  send,
  onClose,
  st,
  inn,
  bowlingXi,
  nameOf,
}: {
  send: (kind: Record<string, unknown>) => Promise<void>;
  onClose: () => void;
  st: MatchState;
  inn: MatchState["innings"][number];
  bowlingXi: string[];
  nameOf: (id?: string | null) => string;
}) {
  const [outside, setOutside] = useState(inn.fielders_outside ?? 0);
  const [penalty, setPenalty] = useState(5);
  const [reason, setReason] = useState("slow over rate");
  const [side, setSide] = useState<Side>("home");

  return (
    <Sheet title="Bowling, field and penalties" onClose={onClose}>
      <div className="form">
        <label>
          Bowler
          <select
            value={inn.bowler_id ?? ""}
            onChange={(e) => send({ type: "bowler_changed", bowler_id: e.target.value })}
          >
            {bowlingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
        <label>
          Fielders outside the circle
          <input
            type="number"
            min={0}
            max={9}
            value={outside}
            onChange={(e) => setOutside(Number(e.target.value))}
            onBlur={() =>
              send({
                type: "field_set",
                outside_circle: outside,
                behind_square_leg: inn.fielders_behind_square_leg ?? 2,
              })
            }
          />
        </label>
      </div>

      <h3 style={{ marginTop: "var(--s4)" }}>Penalty runs</h3>
      <div className="form">
        <label>
          Runs
          <input type="number" min={1} max={10} value={penalty} onChange={(e) => setPenalty(Number(e.target.value))} />
        </label>
        <label>
          Reason
          <input value={reason} onChange={(e) => setReason(e.target.value)} />
        </label>
        <label>
          Awarded to
          <select value={side} onChange={(e) => setSide(e.target.value as Side)}>
            <option value="home">{st.home_name}</option>
            <option value="away">{st.away_name}</option>
          </select>
        </label>
      </div>
      <div className="sheet-actions">
        <button
          className="btn"
          type="button"
          disabled={!reason.trim()}
          onClick={async () => {
            onClose();
            await send({ type: "penalty_runs", runs: penalty, reason: reason.trim(), to_side: side });
          }}
        >
          Award penalty
        </button>
        <button
          className="btn ghost"
          type="button"
          onClick={async () => {
            onClose();
            await send({ type: "innings_completed" });
          }}
        >
          End innings
        </button>
      </div>
    </Sheet>
  );
}

function Scorecard({
  st,
  nameOf,
}: {
  st: MatchState;
  nameOf: (id?: string | null) => string;
}) {
  if (st.innings.length === 0) return null;
  return (
    <>
      {st.innings.map((inn) => (
        <div className="panel" key={inn.index}>
          <h2>
            Innings {inn.index + 1} · {inn.runs}/{inn.wickets} ({overs(inn.legal_balls)})
          </h2>
          <div className="table-wrap"><table className="score-table">
            <thead>
              <tr><th>Batter</th><th>R</th><th>B</th><th>4s</th><th>6s</th></tr>
            </thead>
            <tbody>
              {inn.batters
                .filter(
                  (b) =>
                    b.balls > 0 ||
                    b.out ||
                    b.player_id === inn.striker_id ||
                    b.player_id === inn.non_striker_id
                )
                .map((b) => (
                  <tr key={b.player_id}>
                    <td>{nameOf(b.player_id)}{b.out ? "" : " *"}</td>
                    <td>{b.runs}</td>
                    <td>{b.balls}</td>
                    <td>{b.fours}</td>
                    <td>{b.sixes}</td>
                  </tr>
                ))}
            </tbody>
          </table></div>
          <div className="table-wrap"><table className="score-table">
            <thead>
              <tr><th>Bowler</th><th>O</th><th>M</th><th>R</th><th>W</th></tr>
            </thead>
            <tbody>
              {inn.bowlers.map((b) => (
                <tr key={b.player_id}>
                  <td>{nameOf(b.player_id)}</td>
                  <td>{overs(b.balls)}</td>
                  <td>{b.maidens}</td>
                  <td>{b.runs}</td>
                  <td>{b.wickets}</td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </div>
      ))}
    </>
  );
}
