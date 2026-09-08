"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, getStoredUser, type ClubMemberRow } from "@/lib/api";
import { WagonWheel } from "@/components/WagonWheel";
import { Scorecard } from "@/components/Scorecard";
import { Icon } from "@/components/Icon";
import { ShotIcon, SHOT_SHAPES } from "@/components/ShotIcon";
import {
  BALLS,
  DEFAULT_CONDITIONS,
  DISMISSALS,
  DISMISSALS_WITH_FIELDER,
  EXTRA_KINDS,
  GROUNDS,
  STANDING_LABEL,
  commentaryFor,
  overs,
  requiredRate,
  runRate,
  titleCase,
  type MatchConditions,
  type MatchResponse,
  type MatchState,
  type SideSquad,
  type SquadResponse,
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
  // Two taps landing in the same tick would both number the ball from the same
  // state. `busy` only takes effect after a re-render, so the guard is a ref.
  const sending = useRef(false);

  const send = useCallback(
    async (kind: Record<string, unknown>) => {
      if (!match || sending.current) return;
      sending.current = true;
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
        sending.current = false;
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

      <Stages match={match} send={send} canAct={canAct} nameOf={nameOf} onPicked={setMatch} />

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
  onPicked,
}: {
  match: MatchResponse;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  nameOf: (id?: string | null) => string;
  onPicked: (next: MatchResponse) => void;
}) {
  const st = match.state;
  const agreed = !!st.agreed_home && !!st.agreed_away;
  const current = st.innings[st.innings.length - 1];
  const needsInnings = !current || current.complete;

  if (st.status === "complete") {
    return (
      <div className="panel result-panel">
        <span className="tag gold">Result</span>
        <h2 className="result-line">{st.margin || "Match complete."}</h2>
        <div className="result-innings">
          {st.innings.map((i, n) => (
            <div key={n} className={`result-side${st.winner === i.batting ? " won" : ""}`}>
              <div className="subtle">{i.batting === "home" ? st.home_name : st.away_name}</div>
              <div className="result-score num">
                {i.runs}-{i.wickets}
                <span className="subtle"> ({overs(i.legal_balls)} ov)</span>
              </div>
            </div>
          ))}
        </div>
        {st.player_of_the_match && (
          <p className="muted">Player of the match: {nameOf(st.player_of_the_match)}</p>
        )}
      </div>
    );
  }
  if (!agreed)
    return <ConditionsPanel st={st} send={send} canAct={canAct} clubId={match.club_id} />;
  if (!st.toss_winner) return <TossPanel st={st} send={send} canAct={canAct} />;
  if (st.home_xi.length === 0 || st.away_xi.length === 0)
    return <XiPanel st={st} matchId={match.id} canAct={canAct} onPicked={onPicked} />;
  if (needsInnings) return <OpenersPanel st={st} send={send} canAct={canAct} nameOf={nameOf} />;
  return <LivePanel match={match} send={send} canAct={canAct} nameOf={nameOf} />;
}

function ConditionsPanel({
  st,
  send,
  canAct,
  clubId,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  clubId: string;
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
        <CaptainPicker
          clubId={clubId}
          label="Proposing captain"
          value={name}
          onChange={setName}
        />
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
        <AgreeRow st={st} send={send} canAct={canAct} clubId={clubId} />
      )}
    </div>
  );
}

function AgreeRow({
  st,
  send,
  canAct,
  clubId,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  clubId: string;
}) {
  const pending: Side = st.agreed_home ? "away" : "home";
  const [name, setName] = useState("");
  return (
    <div style={{ marginTop: "1rem" }}>
      <h3>Agreement from {pending === "home" ? st.home_name : st.away_name}</h3>
      <div className="field-row">
        <CaptainPicker
          clubId={clubId}
          label="Their captain"
          value={name}
          onChange={setName}
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

/// Captains come from the club's own members rather than being typed.
///
/// Still allows a name to be written in: the visiting captain is usually not a
/// Fishers member at all, and refusing to record them would stop the match.
function CaptainPicker({
  clubId,
  label,
  value,
  onChange,
}: {
  clubId: string;
  label: string;
  value: string;
  onChange: (name: string) => void;
}) {
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [typing, setTyping] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        setMembers(await api<ClubMemberRow[]>("GET", `/clubs/${clubId}/members`));
      } catch {
        // No members to offer just means typing the name.
        setTyping(true);
      }
    })();
  }, [clubId]);

  if (typing || members.length === 0) {
    return (
      <label>
        {label}
        <input value={value} onChange={(e) => onChange(e.target.value)} placeholder="Their name" />
      </label>
    );
  }

  return (
    <label>
      {label}
      <select
        value={members.some((m) => m.name === value) ? value : ""}
        onChange={(e) => {
          if (e.target.value === "__other") {
            setTyping(true);
            onChange("");
          } else {
            onChange(e.target.value);
          }
        }}
      >
        <option value="">Choose…</option>
        {members.map((m) => (
          <option key={m.user_id} value={m.name}>
            {m.name}
            {m.role !== "member" ? ` — ${m.role.replaceAll("_", " ")}` : ""}
          </option>
        ))}
        <option value="__other">Someone else…</option>
      </select>
    </label>
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

function XiPanel({
  st,
  matchId,
  canAct,
  onPicked,
}: {
  st: MatchState;
  matchId: string;
  canAct: boolean;
  onPicked: (next: MatchResponse) => void;
}) {
  const [squad, setSquad] = useState<SquadResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setSquad(await api<SquadResponse>("GET", `/cricket/matches/${matchId}/squad`));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load the squads");
    }
  }, [matchId]);

  useEffect(() => {
    load();
  }, [load]);

  if (error) return <p className="error">{error}</p>;
  if (!squad) return <div className="panel"><div className="skeleton" style={{ height: 80 }} /></div>;

  return (
    <>
      <div className="panel">
        <h2>Team sheets</h2>
        <p className="muted">
          Each captain names their own side. The match starts once both are in.
        </p>
      </div>
      {(["home", "away"] as const).map((side) => (
        <SideSheet
          key={side}
          side={squad[side]}
          st={st}
          matchId={matchId}
          canAct={canAct}
          onPicked={(next) => {
            onPicked(next);
            load();
          }}
        />
      ))}
    </>
  );
}

function SideSheet({
  side,
  st,
  matchId,
  canAct,
  onPicked,
}: {
  side: SideSquad;
  st: MatchState;
  matchId: string;
  canAct: boolean;
  onPicked: (next: MatchResponse) => void;
}) {
  const already = side.side === "home" ? st.home_xi : st.away_xi;
  const [chosen, setChosen] = useState<string[]>([]);
  const [extras, setExtras] = useState<{ id: string; name: string; bats_left: boolean }[]>([]);
  const [newName, setNewName] = useState("");
  const [newLeft, setNewLeft] = useState(false);
  const [captain, setCaptain] = useState("");
  const [keeper, setKeeper] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (already.length > 0) {
    return (
      <div className="panel">
        <div className="panel-head">
          <h2>{side.team_name}</h2>
          <span className="tag"><Icon name="check" size={12} /> named</span>
        </div>
        <p className="muted">
          {already.length} players — {already.map((id) => st.player_names[id] || "…").join(", ")}
        </p>
      </div>
    );
  }

  if (!side.can_pick) {
    return (
      <div className="panel">
        <div className="panel-head">
          <h2>{side.team_name}</h2>
          <span className="tag grey">waiting</span>
        </div>
        <p className="muted">Their captain has not named a side yet.</p>
      </div>
    );
  }

  const picked = [
    ...side.players.filter((p) => chosen.includes(p.id)).map((p) => ({
      id: p.id,
      name: p.name,
      bats_left: p.bats_left,
    })),
    ...extras,
  ];

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      const next = await api<MatchResponse>("POST", `/cricket/matches/${matchId}/xi`, {
        side: side.side,
        players: picked,
        captain_id: captain || null,
        keeper_id: keeper || null,
      });
      onPicked(next);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save the sheet");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{side.team_name}</h2>
        <span className={picked.length >= 2 ? "tag" : "tag grey"}>{picked.length} picked</span>
      </div>

      {side.players.length === 0 ? (
        <p className="muted">
          Not a Fishers club, so there is no squad to pick from — add them by name below.
        </p>
      ) : (
        <ul className="plain-list">
          {side.players.map((p) => (
            <li key={p.id}>
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked={chosen.includes(p.id)}
                  onChange={(e) =>
                    setChosen((prev) =>
                      e.target.checked ? [...prev, p.id] : prev.filter((x) => x !== p.id)
                    )
                  }
                />
                {p.name}
                <span className="tag grey">{STANDING_LABEL[p.standing] ?? p.standing}</span>
              </label>
            </li>
          ))}
        </ul>
      )}

      {extras.length > 0 && (
        <ul className="plain-list" style={{ marginTop: "var(--s2)" }}>
          {extras.map((p) => (
            <li key={p.id}>
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked
                  onChange={() => setExtras((prev) => prev.filter((x) => x.id !== p.id))}
                />
                {p.name}
                <span className="tag gold">added today</span>
              </label>
            </li>
          ))}
        </ul>
      )}

      <div className="field-row" style={{ marginTop: "var(--s3)" }}>
        <label>
          Someone not on the list
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="Name of whoever turned up"
          />
        </label>
        <label className="checkbox">
          <input type="checkbox" checked={newLeft} onChange={(e) => setNewLeft(e.target.checked)} />
          Left-handed
        </label>
        <button
          className="btn"
          type="button"
          disabled={!newName.trim()}
          onClick={() => {
            setExtras((prev) => [
              ...prev,
              { id: crypto.randomUUID(), name: newName.trim(), bats_left: newLeft },
            ]);
            setNewName("");
            setNewLeft(false);
          }}
        >
          <Icon name="plus" size={16} /> Add
        </button>
      </div>

      {picked.length > 0 && (
        <div className="select-row" style={{ marginTop: "var(--s3)" }}>
          <label>
            Captain
            <select value={captain} onChange={(e) => setCaptain(e.target.value)}>
              <option value="">—</option>
              {picked.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
          <label>
            Keeper
            <select value={keeper} onChange={(e) => setKeeper(e.target.value)}>
              <option value="">—</option>
              {picked.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
        </div>
      )}

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary"
        type="button"
        disabled={!canAct || busy || picked.length < 2}
        onClick={submit}
      >
        {busy ? "Saving…" : `Confirm ${side.team_name} (${picked.length})`}
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
  /// Model-written lines, keyed by ball. The log-written line shows instantly
  /// and is replaced only if a better one arrives.
  const [aiLines, setAiLines] = useState<Record<string, string>>({});

  const ballCount = (inn.deliveries || []).length;
  useEffect(() => {
    const last = (inn.deliveries || [])[ballCount - 1];
    if (!last) return;
    const key = `${last.over}.${last.ball_in_over}.${last.label}`;
    let dropped = false;
    // Fire and forget: a model takes seconds and the ball is already recorded,
    // so nothing waits on this and a failure leaves the written line in place.
    api<{ line: string | null }>("POST", `/cricket/matches/${match.id}/commentary`, {
      over: last.over,
      ball_in_over: last.ball_in_over,
    })
      .then((r) => {
        if (!dropped && r.line) setAiLines((prev) => ({ ...prev, [key]: r.line! }));
      })
      .catch(() => {});
    return () => {
      dropped = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ballCount, match.id]);

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

  // An over has just finished and the same bowler is still marked down for the
  // next one — nobody bowls two in a row, so a new one has to be chosen first.
  const needsBowler =
    inn.legal_balls > 0 &&
    (inn.balls_in_current_over ?? 0) === 0 &&
    !!inn.bowler_id &&
    inn.last_over_bowler === inn.bowler_id &&
    bowlingXi.length > 1;

  const oversAvailable = inn.overs_available ?? st.overs_limit;
  const crr = runRate(inn.runs, inn.legal_balls);
  const rrr = requiredRate(st.target, inn.runs, inn.legal_balls, oversAvailable);
  const currentOver = Math.floor(inn.legal_balls / 6);
  const ballsIn = (over: number) => (inn.deliveries || []).filter((d) => d.over === over);
  const lastOverBalls = currentOver > 0 ? ballsIn(currentOver - 1) : [];
  const lastOverRuns = lastOverBalls.reduce((total, b) => total + b.runs, 0);
  const batterOf = (id?: string | null) =>
    inn.batters.find((b) => b.player_id === id);

  const inPowerplay =
    (inn.powerplay_overs ?? 0) > 0 && inn.legal_balls < (inn.powerplay_overs ?? 0) * 6;
  const allowedOutside = inPowerplay
    ? st.conditions?.fielders_outside_powerplay
    : st.conditions?.fielders_outside_normal;
  const fieldBreach =
    allowedOutside != null &&
    inn.fielders_outside != null &&
    inn.fielders_outside > allowedOutside;

  /// Commentary newest-first, with each over closed off by a summary once its
  /// balls have been listed — so an over reads as a unit rather than a stream.
  const commentaryRows = (() => {
    const balls = inn.deliveries || [];
    // The innings score after each ball, so an over summary can state it.
    let runs = 0;
    let wickets = 0;
    const running = balls.map((b) => {
      runs += b.runs;
      if (b.is_wicket) wickets += 1;
      return { runs, wickets };
    });

    type Row =
      | { kind: "ball"; ball: (typeof balls)[number]; key: string }
      | {
          kind: "over";
          over: number;
          runs: number;
          wickets: number;
          overRuns: number;
          overWickets: number;
        };

    const rows: Row[] = [];
    for (let i = balls.length - 1; i >= 0; i--) {
      const ball = balls[i];
      rows.push({
        kind: "ball",
        ball,
        key: `${ball.over}.${ball.ball_in_over}.${ball.label}`,
      });
      const previous = balls[i - 1];
      // This was the first ball of its over, so the over is now fully listed.
      if (previous && previous.over !== ball.over) {
        const overBalls = balls.filter((b) => b.over === previous.over);
        rows.push({
          kind: "over",
          over: previous.over,
          runs: running[i - 1].runs,
          wickets: running[i - 1].wickets,
          overRuns: overBalls.reduce((sum, b) => sum + b.runs, 0),
          overWickets: overBalls.filter((b) => b.is_wicket).length,
        });
      }
    }
    return rows.slice(0, 40);
  })();

  // Ball-by-ball, grouped into overs and shown as dials.
  const overGroups = (() => {
    const map = new Map<number, NonNullable<typeof inn.deliveries>>();
    for (const d of inn.deliveries || []) {
      const list = map.get(d.over) || [];
      list.push(d);
      map.set(d.over, list);
    }
    return [...map.entries()].sort((a, b) => a[0] - b[0]).slice(-2);
  })();

  return (
    <div className="score-layout">
      <div>
        <div className="matchbar">
          <div>
            <span className="scoreline">
              {inn.runs}/{inn.wickets}
            </span>{" "}
            <span className="muted">
              ({overs(inn.legal_balls)} of {oversAvailable} ov)
            </span>
            <div className="muted">
              CRR {crr === null ? "—" : crr.toFixed(2)}
              {rrr !== null && ` · RRR ${rrr.toFixed(2)}`}
            </div>
          </div>
          {st.target != null && (
            <div style={{ marginLeft: "auto", textAlign: "right" }}>
              <strong className="num">
                {Math.max(0, st.target - inn.runs)} needed
              </strong>
              <div className="subtle">
                from {Math.max(0, oversAvailable * 6 - inn.legal_balls)} balls
              </div>
            </div>
          )}
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
        </div>

        {fieldBreach && (
          <p className="error">
            {inn.fielders_outside} fielders outside the circle — only {allowedOutside} allowed.
          </p>
        )}

        <div className="panel">
          <div className="who">
            <BatterCard id={inn.striker_id} nameOf={nameOf} b={batterOf(inn.striker_id)} onStrike />
            <BatterCard id={inn.non_striker_id} nameOf={nameOf} b={batterOf(inn.non_striker_id)} />
            <div className="card">
              <div className="who-name">{nameOf(inn.bowler_id)}</div>
              <div className="who-figs">
                {(() => {
                  const bowl = inn.bowlers.find((b) => b.player_id === inn.bowler_id);
                  return bowl ? `${bowl.wickets}-${bowl.runs}` : "—";
                })()}
              </div>
              <div className="who-sub">
                bowling ·{" "}
                {(() => {
                  const bowl = inn.bowlers.find((b) => b.player_id === inn.bowler_id);
                  return bowl ? `${overs(bowl.balls)} ov, ${bowl.maidens} mdn` : "first over";
                })()}
              </div>
            </div>
          </div>

          {overGroups.length > 0 && (
            <div className="overs-strip" style={{ marginTop: "var(--s3)" }}>
              {overGroups.map(([over, balls]) => {
                const legal = balls.filter((b) => b.is_legal).length;
                const total = balls.reduce((sum, b) => sum + b.runs, 0);
                return (
                  <div className="over-row" key={over}>
                    <span className="over-label">Over {over + 1}</span>
                    {balls.map((b, i) => (
                      <span key={i} className={`ball-chip ${chipClass(b)}`} title={b.label}>
                        {b.is_wicket ? "W" : b.label}
                      </span>
                    ))}
                    {Array.from({ length: Math.max(0, 6 - legal) }, (_, i) => (
                      <span key={`p${i}`} className="ball-chip pending">
                        ·
                      </span>
                    ))}
                    <span className="over-total">= {total}</span>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <div className="panel">
          <h2>Commentary</h2>
          <ul className="comm-list">
            {commentaryRows.map((row) =>
              row.kind === "over" ? (
                <li className="over-summary" key={`o${row.over}`}>
                  <strong>End of over {row.over + 1}</strong>
                  <span className="muted">
                    {row.overRuns} run{row.overRuns === 1 ? "" : "s"}
                    {row.overWickets > 0 &&
                      `, ${row.overWickets} wicket${row.overWickets === 1 ? "" : "s"}`}
                  </span>
                  <strong className="num">
                    {inn.batting === "home" ? st.home_name : st.away_name} {row.runs}/{row.wickets}
                  </strong>
                </li>
              ) : (
                <li className="comm-ball" key={row.key}>
                  <span className="comm-num">
                    {row.ball.over}.{row.ball.ball_in_over}
                  </span>
                  <span className={`ball-chip ${chipClass(row.ball)}`}>
                    {row.ball.is_wicket ? "W" : row.ball.label}
                  </span>
                  <span className="comm-text">
                    {aiLines[row.key] || commentaryFor(row.ball, nameOf, st.left_handers || [])}
                    {aiLines[row.key] && (
                      <span className="tag grey" style={{ marginLeft: "var(--s2)" }}>AI</span>
                    )}
                  </span>
                </li>
              )
            )}
            {(inn.deliveries || []).length === 0 && <li className="muted">No balls yet.</li>}
          </ul>
        </div>
      </div>

      {/* ---- controls ---- */}
      <div className="controls">
        {needsBowler && (
          <div className="panel" style={{ borderColor: "var(--accent)" }}>
            <div className="panel-head">
              <h2>Over {currentOver} done — who bowls next?</h2>
              <span className="tag gold">{lastOverRuns} off it</span>
            </div>
            <p className="muted">
              {nameOf(inn.last_over_bowler)} bowled it, and nobody bowls two in a row.
            </p>
            <div className="actions bowler-options">
              {bowlingXi
                .filter((id) => id !== inn.last_over_bowler)
                .map((id) => {
                  const b = inn.bowlers.find((x) => x.player_id === id);
                  const bowled = b ? Math.floor(b.balls / 6) : 0;
                  const limit = st.conditions?.overs_per_bowler ?? 0;
                  const spent = limit > 0 && bowled >= limit;
                  return (
                    <button
                      key={id}
                      className="btn"
                      type="button"
                      disabled={!canAct || spent}
                      title={spent ? `${nameOf(id)} has bowled their ${limit}` : undefined}
                      onClick={() => send({ type: "bowler_changed", bowler_id: id })}
                    >
                      {nameOf(id)}
                      {b && b.balls > 0 && (
                        <span className="subtle">
                          {overs(b.balls)}-{b.maidens}-{b.runs}-{b.wickets}
                        </span>
                      )}
                    </button>
                  );
                })}
            </div>
          </div>
        )}

        <div className="panel">
          <div className="panel-head">
            <h2>Runs</h2>
            <label className="checkbox" style={{ fontSize: "0.85rem" }}>
              <input type="checkbox" checked={askShot} onChange={(e) => toggleAsk(e.target.checked)} />
              Ask for the shot
            </label>
          </div>
          <div className="dial">
            {[0, 1, 2, 3, 4, 5, 6].map((n) => (
              <button
                key={n}
                className={`btn${n === 4 ? " four" : ""}${n === 6 ? " six" : ""}`}
                type="button"
                disabled={!canAct || needsBowler}
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
              <button key={k} className="btn" type="button" disabled={!canAct || needsBowler} onClick={() => startExtra(k)}>
                {titleCase(k)}
              </button>
            ))}
            <button className="btn danger" type="button" disabled={!canAct || needsBowler} onClick={() => setSheet("wicket")}>
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
      </div>

      {/* ---- the guided ball flow ---- */}
      {draft && draft.step === "detail" && (
        <Sheet title={`${titleCase(draft.extra || "Extra")}`} step={1} of={2} onClose={() => setDraft(null)}>
          <p className="muted">
            How many did they run on top of the {titleCase(draft.extra || "extra").toLowerCase()}?
          </p>
          <div className="dial">
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
            <button className="btn ghost" type="button" onClick={() => setDraft(null)}>Cancel</button>
            <button
              className="btn primary"
              type="button"
              onClick={() =>
                draft.offTheBat && askShot ? setDraft({ ...draft, step: "shot" }) : record(draft)
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
            {SHOT_SHAPES.map((sh) => (
              <button
                key={sh.kind}
                className="shot-option"
                type="button"
                aria-pressed={draft.shotKind === sh.kind}
                onClick={() => pickShot(sh.kind)}
              >
                <ShotIcon shape={sh} />
                {sh.label}
                <span className="hint">{sh.hint}</span>
              </button>
            ))}
          </div>
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft(null)}>Cancel</button>
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
            Tap the field. Nearer the rope means it carried further — the commentary reads from
            this.
          </p>
          <div style={{ display: "flex", justifyContent: "center" }}>
            {/* Only the ball being scored: the innings so far would be noise
                when the question is where this one went. */}
            <WagonWheel
              deliveries={[]}
              batsLeft={batsLeft}
              size={300}
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
              onClick={() => record(draft, { angle: 0, kind: draft.shotKind || "other", reach: 0.5 })}
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
    </div>
  );
}

/// Which dial a ball gets on the over strip.
function chipClass(b: { runs: number; is_wicket: boolean; is_legal: boolean }) {
  if (b.is_wicket) return "wicket";
  if (!b.is_legal) return "extra";
  if (b.runs >= 6) return "six";
  if (b.runs >= 4) return "four";
  return "";
}

function BatterCard({
  id,
  nameOf,
  b,
  onStrike,
}: {
  id?: string | null;
  nameOf: (id?: string | null) => string;
  b?: { runs: number; balls: number; fours: number; sixes: number };
  onStrike?: boolean;
}) {
  const sr = b && b.balls ? ((b.runs / b.balls) * 100).toFixed(0) : null;
  return (
    <div className={`card${onStrike ? " on-strike" : ""}`}>
      <div className="who-name">
        {nameOf(id)}
        {onStrike && <span className="tag">on strike</span>}
      </div>
      <div className="who-figs">
        {b ? b.runs : 0}
        <span className="subtle" style={{ fontSize: "0.9rem" }}> ({b ? b.balls : 0})</span>
      </div>
      <div className="who-sub">
        {b ? `${b.fours}x4 · ${b.sixes}x6` : "yet to face"}
        {sr && ` · SR ${sr}`}
      </div>
    </div>
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

