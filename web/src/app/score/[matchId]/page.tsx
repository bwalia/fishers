"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, getAccessToken, getStoredUser, roleLabel, type ClubMemberRow } from "@/lib/api";
import { randomUUID } from "@/lib/uuid";
import { WagonWheel } from "@/components/WagonWheel";
import { Scorecard } from "@/components/Scorecard";
import { Icon } from "@/components/Icon";
import { PersonPicker, type Person } from "@/components/PersonPicker";
import { PlayerPicker } from "@/components/PlayerPicker";
import { ShotIcon, SHOT_SHAPES } from "@/components/ShotIcon";
import { ShareScoreboardButton } from "@/components/ShareScoreboardButton";
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
  type Innings,
  type MatchConditions,
  type MatchResponse,
  type MatchState,
  type Side,
  type SideSquad,
  type SquadResponse,
} from "@/lib/cricket";

/// The device the book is held on. The API ties the scoring lock to it, so it
/// has to survive a refresh or the scorer loses their own claim.
function deviceId() {
  const KEY = "fishers_device_id";
  let id = localStorage.getItem(KEY);
  if (!id) {
    id = randomUUID();
    localStorage.setItem(KEY, id);
  }
  return id;
}

/// A full side. Not enforced — the engine happily plays nine a side — but it
/// is the number a captain is counting towards, so the screen says so.
const XI_SIZE = 11;

function ballClass(ball: { runs: number; is_wicket: boolean }) {
  if (ball.is_wicket) return "wicket";
  if (ball.runs >= 6) return "six";
  if (ball.runs >= 4) return "boundary";
  return undefined;
}


const other = (s: Side): Side => (s === "home" ? "away" : "home");

export default function ScorerPage({
  params,
}: {
  params: Promise<{ matchId: string }>;
}) {
  const { matchId } = use(params);
  const router = useRouter();
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
          client_event_id: randomUUID(),
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
      events.push({ client_event_id: randomUUID(), seq: ++seq, kind, at });

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

  // Before the first ball the screen is a setup flow, and saying which step
  // you are on is most of what makes it feel like one.
  const isSetup = st.status !== "complete" && st.innings.length === 0;

  return (
    <main>
      <section className="match-head">
        <div className="match-head-sides">
          <span className="match-head-side">{st.home_name}</span>
          <span className="match-head-v">v</span>
          <span className="match-head-side away">{st.away_name}</span>
        </div>
        <div className="match-head-meta">
          <span className={`status-pill ${st.status}`}>{titleCase(st.status)}</span>
          {/* Which fixture. A club plays the same side more than once a season,
              and following an old notification lands you in the wrong one. */}
          {match.start_at && (
            <span className="tag gold">
              {new Date(match.start_at).toLocaleString("en-GB", {
                weekday: "short",
                day: "numeric",
                month: "short",
                hour: "2-digit",
                minute: "2-digit",
              })}
            </span>
          )}
          {st.conditions && (
            <>
              <span className="tag">{st.conditions.overs_limit} overs</span>
              <span className="tag">{titleCase(st.conditions.ball)} ball</span>
              <span className="tag">{titleCase(st.conditions.ground)} ground</span>
            </>
          )}
        </div>
        {/* Anyone signed in can mint a public live link — not only the scorer. */}
        {getAccessToken() ? (
          <ShareScoreboardButton
            matchId={matchId}
            homeName={st.home_name}
            awayName={st.away_name}
          />
        ) : (
          <p className="muted share-hint" style={{ marginTop: "1rem" }}>
            Sign in to share a live scoreboard link for WhatsApp or email.
          </p>
        )}
      </section>

      {isSetup && <SetupRail st={st} hasScorer={!!match.active_scorer_user_id} />}

      {isSetup && st.toss_winner && <TossResult st={st} />}

      {error && <p className="error">{error}</p>}

      {/* Two red boxes about the book are noise for a visiting captain who came
          here to say yes to the terms. Whoever cannot score is only told so
          once the match actually needs a scorer. */}
      {/* A spectator is not doing anything wrong by watching, so this is a
          note about the page, not an error about them. */}
      {!match.can_score && !isSetup && (
        <div className="waiting-note">
          <Icon name="radio" size={18} />
          <span>
            Following along. {match.active_scorer_user_id ? "Someone else is" : "Nobody is"}{" "}
            scoring this match — the scorecard below updates as they do.
          </span>
        </div>
      )}

      {match.can_score && !match.active_scorer_user_id && (
        <div className="panel claim-panel">
          <div>
            <h2>Nobody is scoring yet</h2>
            <p className="muted">
              Whoever takes the book records every ball. It can be handed over later.
            </p>
          </div>
          <button
            className="btn primary lg"
            type="button"
            disabled={busy}
            onClick={() => claim(false)}
          >
            <Icon name="book" size={18} /> Take the book
          </button>
        </div>
      )}

      {heldBySomeoneElse && match.can_score && (
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

      {heldByMe && <HandOver match={match} onChanged={setMatch} />}

      <CallItOff match={match} onChanged={setMatch} onGone={() => router.push("/score")} />

      <Scorecard st={st} nameOf={nameOf} />

      <p className="muted" style={{ marginTop: "1rem" }}>
        <Link href="/score">← All fixtures</Link>
      </p>
    </main>
  );
}

/// Passing the book to somebody else.
///
/// Whoever holds it records every ball, so it has to be handed over on
/// purpose: a scorer going for tea, a phone about to die. Only people who may
/// score this match are offered, because the server refuses anyone else and a
/// list of names that will be rejected is worse than no list.
function HandOver({
  match,
  onChanged,
}: {
  match: MatchResponse;
  onChanged: (next: MatchResponse) => void;
}) {
  const [open, setOpen] = useState(false);
  const [candidates, setCandidates] = useState<ClubMemberRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [choice, setChoice] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const me = getStoredUser();

  useEffect(() => {
    if (!open || candidates.length > 0) return;
    setLoading(true);
    (async () => {
      // The book belongs to the side running the match, so its members are
      // who can take it. Anyone else needs appointing as an official first.
      const rows = await api<ClubMemberRow[]>("GET", `/clubs/${match.club_id}/members`).catch(
        () => [] as ClubMemberRow[]
      );
      setCandidates(
        rows.filter((r) => r.user_id !== me?.id && r.role !== "member" && r.role !== "guest")
      );
      setLoading(false);
    })();
  }, [open, candidates.length, match.club_id, me?.id]);

  const hand = async () => {
    setBusy(true);
    setError(null);
    try {
      onChanged(
        await api<MatchResponse>("POST", `/cricket/matches/${match.id}/handover`, {
          to_user_id: choice,
        })
      );
      setOpen(false);
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "Could not hand it over");
      } catch {
        setError(raw || "Could not hand it over");
      }
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button className="btn ghost sm call-off" type="button" onClick={() => setOpen(true)}>
        <Icon name="book" size={14} /> Hand the book to somebody else
      </button>
    );
  }

  return (
    <div className="panel">
      <h2>Hand over the book</h2>
      <p className="muted">
        They take over recording every ball from the next one. You keep watching, and can
        be handed it back.
      </p>

      {loading && <div className="skeleton" style={{ height: 48 }} />}

      {!loading && candidates.length === 0 && (
        <p className="muted">
          Nobody else at {match.state.home_name} can score this match. A secretary can
          appoint them, or make them a captain.
        </p>
      )}

      {candidates.length > 0 && (
        <div className="squad-grid">
          {candidates.map((c) => (
            <button
              key={c.user_id}
              type="button"
              className={`squad-chip${choice === c.user_id ? " on" : ""}`}
              aria-pressed={choice === c.user_id}
              onClick={() => setChoice(c.user_id)}
            >
              <span>{c.name}</span>
              <span className="tag grey">{roleLabel(c.role)}</span>
            </button>
          ))}
        </div>
      )}

      {error && <p className="error">{error}</p>}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={!choice || busy} onClick={hand}>
          {busy ? "Handing over…" : "Hand it over"}
        </button>
        <button className="btn" type="button" onClick={() => setOpen(false)}>
          Keep the book
        </button>
      </div>
    </div>
  );
}

/// Calling the match off.
///
/// Two different things, and the difference matters: a match with balls in it
/// is abandoned — the scorecard survives, the averages count, and it goes down
/// as no result. One nobody has scored in was a mistake, and is deleted. The
/// server enforces the line; this only offers the one that applies.
function CallItOff({
  match,
  onChanged,
  onGone,
}: {
  match: MatchResponse;
  onChanged: (next: MatchResponse) => void;
  onGone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const st = match.state;
  const bowled = st.innings.some((i) => i.legal_balls > 0 || i.runs > 0);
  // Only somebody who can run the fixture sees this at all. `my_sides` is the
  // closest the client has; the server has the final say either way.
  const mayManage = (match.my_sides ?? []).length > 0;
  if (st.status === "complete" || !mayManage) return null;

  const run = async (what: "abandon" | "delete") => {
    setBusy(true);
    setError(null);
    try {
      if (what === "abandon") {
        onChanged(
          await api<MatchResponse>("POST", `/cricket/matches/${match.id}/abandon`, {
            reason: reason.trim(),
          })
        );
        setOpen(false);
      } else {
        await api("DELETE", `/cricket/matches/${match.id}`);
        onGone();
      }
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "That did not work");
      } catch {
        setError(raw || "That did not work");
      }
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button className="btn ghost sm call-off" type="button" onClick={() => setOpen(true)}>
        {bowled ? "Abandon this match" : "Call this match off"}
      </button>
    );
  }

  return (
    <div className="panel danger-panel">
      <h2>{bowled ? "Abandon this match" : "Call this match off"}</h2>
      {bowled ? (
        <>
          <p className="muted">
            It goes down as no result. The scorecard and everything scored so far stay —
            they happened, and the averages count. This cannot be undone.
          </p>
          <label>
            Why (goes on the scorecard)
            <input
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Rain, bad light, ground unfit…"
              autoFocus
            />
          </label>
        </>
      ) : (
        <p className="muted">
          Nothing has been scored, so the match is removed entirely and the fixture stays.
          If a ball has been bowled you would abandon it instead, and keep the scorecard.
        </p>
      )}

      {error && <p className="error">{error}</p>}

      <div className="field-row">
        <button
          className="btn danger"
          type="button"
          disabled={busy}
          onClick={() => run(bowled ? "abandon" : "delete")}
        >
          {busy ? "Working…" : bowled ? "Abandon — no result" : "Delete the match"}
        </button>
        <button className="btn" type="button" onClick={() => setOpen(false)}>
          Keep playing
        </button>
      </div>
    </div>
  );
}

/// Who won the toss and what they did with it — the thing both sides ask about
/// the moment it happens.
function TossResult({ st }: { st: MatchState }) {
  const winner = st.toss_winner === "home" ? st.home_name : st.away_name;
  const loser = st.toss_winner === "home" ? st.away_name : st.home_name;
  const batting =
    st.toss_decision === "bat"
      ? winner
      : st.toss_decision === "bowl"
        ? loser
        : null;
  return (
    <div className="toss-result">
      <Icon name="trophy" size={18} />
      <p>
        <strong>{winner}</strong> won the toss and chose to{" "}
        <strong>{st.toss_decision === "bat" ? "bat" : "bowl"}</strong>.
        {batting && <> {batting} bat first.</>}
      </p>
    </div>
  );
}

/// Where the setup has got to. Reads the same state `Stages` switches on, so
/// the two can never disagree about which step you are on.
function SetupRail({ st, hasScorer }: { st: MatchState; hasScorer: boolean }) {
  const steps = [
    { label: "Scorer", done: hasScorer },
    { label: "Terms", done: !!st.agreed_home && !!st.agreed_away },
    { label: "Toss", done: !!st.toss_winner },
    { label: "Team sheets", done: st.home_xi.length > 0 && st.away_xi.length > 0 },
  ];
  const current = steps.findIndex((s) => !s.done);

  return (
    <ol className="setup-rail" aria-label="Match setup">
      {steps.map((step, i) => (
        <li
          key={step.label}
          className={`rail-step${step.done ? " done" : ""}${i === current ? " now" : ""}`}
          aria-current={i === current ? "step" : undefined}
        >
          <span className="rail-dot">{step.done ? <Icon name="check" size={12} /> : i + 1}</span>
          <span className="rail-label">{step.label}</span>
        </li>
      ))}
    </ol>
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
    return (
      <ConditionsPanel
        st={st}
        send={send}
        canAct={canAct}
        matchId={match.id}
        mySides={match.my_sides ?? []}
        myClubSide={match.my_club_side ?? null}
        theirClub={
          (match.my_club_side ?? "home") === "home"
            ? !!match.opponent_club_id
            : true
        }
        onAgreed={onPicked}
      />
    );
  if (!st.toss_winner)
    return canAct ? (
      <TossPanel st={st} send={send} canAct={canAct} />
    ) : (
      <ScorersTurn
        title="Waiting on the toss"
        note="Whoever is scoring records the toss. This page updates when they do."
      />
    );
  if (st.home_xi.length === 0 || st.away_xi.length === 0)
    return (
      <XiPanel
        st={st}
        matchId={match.id}
        myClubSide={match.my_club_side ?? null}
        onPicked={onPicked}
      />
    );
  if (needsInnings)
    return canAct ? (
      <OpenersPanel st={st} send={send} canAct={canAct} nameOf={nameOf} />
    ) : (
      <ScorersTurn
        title="Waiting for the first ball"
        note="The scorer names the openers and the bowler. This page updates when they do."
      />
    );
  return <LivePanel match={match} send={send} canAct={canAct} nameOf={nameOf} />;
}

/// Somebody else's move. Said once, quietly — not as an error, and not as a
/// form that will be refused.
function ScorersTurn({ title, note }: { title: string; note: string }) {
  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>{title}</h2>
      </div>
      <div className="waiting-note">
        <Icon name="clock" size={18} />
        <span>{note}</span>
      </div>
    </div>
  );
}

function ConditionsPanel({
  st,
  send,
  canAct,
  matchId,
  mySides,
  myClubSide,
  theirClub,
  onAgreed,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  matchId: string;
  mySides: Side[];
  myClubSide: Side | null;
  /// True when the other side is a Fishers club with a captain of their own.
  theirClub: boolean;
  onAgreed: (next: MatchResponse) => void;
}) {
  const squad = useSquad(matchId);
  const [editing, setEditing] = useState(false);

  // Two screens, not one. Once terms are on the table the form has done its
  // job, and leaving it up next to the agreement asks the reader to work out
  // which half applies to them.
  const proposed = !!st.conditions_proposed_by;
  if (proposed && !editing) {
    return (
      <WaitingPanel
        st={st}
        canAct={canAct}
        matchId={matchId}
        mySides={mySides}
        myClubSide={myClubSide}
        theirClub={theirClub}
        squad={squad}
        onChange={() => setEditing(true)}
        onAgreed={onAgreed}
      />
    );
  }

  return (
    <ProposePanel
      st={st}
      matchId={matchId}
      squad={squad}
      mySides={mySides}
      myClubSide={myClubSide}
      onProposed={onAgreed}
      onDone={() => setEditing(false)}
      onCancel={proposed ? () => setEditing(false) : undefined}
    />
  );
}

function ProposePanel({
  st,
  matchId,
  squad,
  mySides,
  myClubSide,
  onProposed,
  onDone,
  onCancel,
}: {
  st: MatchState;
  matchId: string;
  squad: ReturnType<typeof useSquad>;
  mySides: Side[];
  myClubSide: Side | null;
  onProposed: (next: MatchResponse) => void;
  onDone: () => void;
  onCancel?: () => void;
}) {
  const [c, setC] = useState<MatchConditions>(st.conditions ?? DEFAULT_CONDITIONS);
  // You propose for your own side. There is no choice here on purpose:
  // proposing counts as that side agreeing, so offering the opposition as an
  // option meant one wrong tap signed for them and left them nothing to
  // accept. Recording the other captain's agreement is a real thing scorers
  // do — but it is an agreement, and it belongs on the next screen.
  const [by, setBy] = useState<Side>(myClubSide ?? mySides[0] ?? "home");
  // Only somebody in neither club has a genuine question to answer.
  const mustChooseSide = myClubSide === null && mySides.length > 1;
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const propose = async () => {
    setBusy(true);
    setError(null);
    try {
      onProposed(
        await api<MatchResponse>("POST", `/cricket/matches/${matchId}/propose`, {
          conditions: c,
          by,
          by_name: name.trim(),
        })
      );
      onDone();
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "Could not propose those terms");
      } catch {
        setError(raw || "Could not propose those terms");
      }
    } finally {
      setBusy(false);
    }
  };

  const num = (k: keyof MatchConditions) => ({
    type: "number" as const,
    inputMode: "numeric" as const,
    value: c[k] as number,
    onChange: (e: React.ChangeEvent<HTMLInputElement>) =>
      setC({ ...c, [k]: Number(e.target.value) }),
  });

  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>Agree the terms</h2>
        <p className="muted">
          Set how the game is being played, then say who is proposing it. The other
          captain gets asked to agree.
        </p>
      </div>

      <fieldset className="setup-group">
        <legend>Format</legend>
        <div className="setup-fields">
          <label>Overs <input {...num("overs_limit")} /></label>
          <label>
            Ball
            <select value={c.ball} onChange={(e) => setC({ ...c, ball: e.target.value })}>
              {BALLS.map((b) => <option key={b} value={b}>{titleCase(b)}</option>)}
            </select>
          </label>
          <label>
            Ground
            <select value={c.ground} onChange={(e) => setC({ ...c, ground: e.target.value })}>
              {GROUNDS.map((g) => <option key={g} value={g}>{titleCase(g)}</option>)}
            </select>
          </label>
        </div>
      </fieldset>

      <fieldset className="setup-group">
        <legend>Bowling and fielding</legend>
        <div className="setup-fields">
          <label>
            Overs per bowler
            <input {...num("overs_per_bowler")} />
            <span className="subtle">0 for no limit</span>
          </label>
          <label>Powerplay overs <input {...num("powerplay_overs")} /></label>
          <label>
            Fielders out, powerplay
            <input {...num("fielders_outside_powerplay")} />
          </label>
          <label>
            Fielders out, after
            <input {...num("fielders_outside_normal")} />
          </label>
          <label>
            Overs per hour
            <input {...num("target_overs_per_hour")} />
            <span className="subtle">0 to not count it</span>
          </label>
        </div>
      </fieldset>

      <fieldset className="setup-group">
        <legend>Your captain</legend>
        {mustChooseSide && (
          <div className="side-choice">
            {mySides.map((side) => (
              <button
                key={side}
                type="button"
                className={`side-card${by === side ? " on" : ""}`}
                aria-pressed={by === side}
                onClick={() => {
                  setBy(side);
                  // The name belonged to the other club's list.
                  setName("");
                }}
              >
                <span className="side-card-name">
                  {side === "home" ? st.home_name : st.away_name}
                </span>
                <span className="side-card-role">
                  {side === "home" ? "Home" : "Away"}
                </span>
              </button>
            ))}
          </div>
        )}
        <p className="muted">
          Proposing on behalf of <strong>{by === "home" ? st.home_name : st.away_name}</strong>.{" "}
          {other(by) === "home" ? st.home_name : st.away_name} will be asked to accept.
        </p>
        <PersonPicker
          label={`Captain of ${by === "home" ? st.home_name : st.away_name}`}
          people={squad.people(by)}
          value={name}
          onChange={setName}
          loading={squad.loading}
          emptyHint="Nobody on Fishers for that side — type their captain's name."
        />
      </fieldset>

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !name.trim()}
        onClick={propose}
      >
        {busy ? "Proposing…" : "Propose these terms"}
      </button>
      {onCancel && (
        <button className="btn" type="button" onClick={onCancel} style={{ width: "100%" }}>
          Keep the terms as they were
        </button>
      )}
    </div>
  );
}

/// Terms are on the table. One thing to do, said in one sentence.
function WaitingPanel({
  st,
  canAct,
  matchId,
  mySides,
  myClubSide,
  theirClub,
  squad,
  onChange,
  onAgreed,
}: {
  st: MatchState;
  canAct: boolean;
  matchId: string;
  mySides: Side[];
  myClubSide: Side | null;
  theirClub: boolean;
  squad: ReturnType<typeof useSquad>;
  onChange: () => void;
  onAgreed: (next: MatchResponse) => void;
}) {
  const pending: Side = st.agreed_home ? "away" : "home";
  const pendingName = pending === "home" ? st.home_name : st.away_name;
  // The one that caused "only this side's captain or the scorer can agree
  // these terms": the form was shown to whoever was looking, but only the
  // pending side's own captain — or the scorer — can submit it.
  const canAgree = mySides.includes(pending);
  // Accepting your own side's match reads differently to a scorer writing
  // down what the two captains just said to each other.
  const isMine = pending === myClubSide;
  // Their captain answers for them. A scorer with both captains in front of
  // them can still write it down — but that is asked for, not the default,
  // or one tap agrees on behalf of a club that has not seen the terms.
  const theirsToAnswer = canAgree && !isMine && theirClub;
  const [recording, setRecording] = useState(false);
  const proposer = st.agreed_home ?? st.agreed_away ?? "";
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const c = st.conditions ?? DEFAULT_CONDITIONS;

  const agree = async () => {
    setBusy(true);
    setError(null);
    try {
      onAgreed(
        await api<MatchResponse>("POST", `/cricket/matches/${matchId}/agree`, {
          side: pending,
          captain_name: name.trim(),
        })
      );
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "Could not record that agreement");
      } catch {
        setError(raw || "Could not record that agreement");
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>
          {isMine && canAgree
            ? "Do you accept these terms?"
            : recording
              ? `${pendingName}, do you agree?`
              : `Waiting on ${pendingName}`}
        </h2>
        <p className="muted">
          {isMine && canAgree
            ? `${proposer} has proposed this match. Check it over — once you accept, the toss is next.`
            : recording
              ? `Record ${pendingName}'s captain agreeing and the toss is next.`
              : `${proposer} has proposed these terms. ${pendingName} has to accept before the toss.`}
        </p>
      </div>

      <dl className="terms-summary">
        <div><dt>Overs</dt><dd className="num">{c.overs_limit}</dd></div>
        <div><dt>Ball</dt><dd>{titleCase(c.ball)}</dd></div>
        <div><dt>Ground</dt><dd>{titleCase(c.ground)}</dd></div>
        <div>
          <dt>Overs per bowler</dt>
          <dd className="num">{c.overs_per_bowler || "No limit"}</dd>
        </div>
        <div><dt>Powerplay</dt><dd className="num">{c.powerplay_overs} overs</dd></div>
        <div>
          <dt>Fielders out</dt>
          <dd className="num">
            {c.fielders_outside_powerplay} then {c.fielders_outside_normal}
          </dd>
        </div>
      </dl>

      <div className="agree-strip">
        {(["home", "away"] as const).map((side) => {
          const who = side === "home" ? st.agreed_home : st.agreed_away;
          return (
            <div key={side} className={`agree-card${who ? " done" : ""}`}>
              <div className="agree-side">{side === "home" ? st.home_name : st.away_name}</div>
              <div className="agree-state">
                {who ? <><Icon name="check" size={14} /> {who}</> : "Not yet"}
              </div>
            </div>
          );
        })}
      </div>

      {canAgree && (!theirsToAnswer || recording) ? (
        <>
          <fieldset className="setup-group">
            <legend>{isMine ? "Accepted by" : `${pendingName} agrees`}</legend>
            <PersonPicker
              label={isMine ? "Your captain's name" : `Captain of ${pendingName}`}
              people={squad.people(pending)}
              value={name}
              onChange={setName}
              loading={squad.loading}
              emptyHint="Type their captain's name."
            />
          </fieldset>

          {error && <p className="error">{error}</p>}

          <button
            className="btn primary lg"
            type="button"
            disabled={busy || !name.trim()}
            onClick={agree}
          >
            {busy
              ? "Saving…"
              : isMine
                ? `Accept — ${name.trim() || "name your captain"}`
                : name.trim()
                  ? `${name.trim()} agrees`
                  : "Agree the terms"}
          </button>
        </>
      ) : (
        <>
          <div className="waiting-note">
            <Icon name="clock" size={18} />
            <span>
              {pendingName}&rsquo;s captain accepts from their own phone — they have been
              told. This page updates when they do.
            </span>
          </div>
          {theirsToAnswer && (
            <button
              className="btn ghost sm"
              type="button"
              style={{ marginTop: "var(--s3)" }}
              onClick={() => setRecording(true)}
            >
              Their captain is here — record it
            </button>
          )}
        </>
      )}

      {canAct && (
        <>
          <button className="btn" type="button" onClick={onChange} style={{ width: "100%" }}>
            Change the terms
          </button>
          <p className="subtle">Changing anything asks both captains again.</p>
        </>
      )}
    </div>
  );
}

/// Both squads, from the match rather than from the clubs.
///
/// `/clubs/{id}/members` is the obvious place to look and the wrong one: a
/// scorer is normally in the home club only, so reading the opposition's
/// roster 403s and their captain list comes back empty. The match knows who is
/// playing in it and is already permissioned for whoever is scoring, so it
/// answers for both sides in one request.
function useSquad(matchId: string) {
  const [squad, setSquad] = useState<SquadResponse | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const found = await api<SquadResponse>("GET", `/cricket/matches/${matchId}/squad`);
        if (live) setSquad(found);
      } catch {
        // No squad to offer just means the names get typed.
      } finally {
        if (live) setLoading(false);
      }
    })();
    return () => {
      live = false;
    };
  }, [matchId]);

  return {
    loading,
    people: (side: Side): Person[] =>
      (squad?.[side].players ?? []).map((p) => ({
        id: p.id,
        name: p.name,
        // "member" only means nobody has said whether they are coming.
        note: p.standing === "member" ? undefined : STANDING_LABEL[p.standing],
      })),
  };
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
  const [winner, setWinner] = useState<Side | null>(null);
  const [decision, setDecision] = useState<"bat" | "bowl" | null>(null);

  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>The toss</h2>
        <p className="muted">Who called it, and what they did with it.</p>
      </div>

      <fieldset className="setup-group">
        <legend>Won the toss</legend>
        <div className="side-choice">
          {(["home", "away"] as const).map((side) => (
            <button
              key={side}
              type="button"
              className={`side-card${winner === side ? " on" : ""}`}
              aria-pressed={winner === side}
              onClick={() => setWinner(side)}
            >
              <span className="side-card-name">
                {side === "home" ? st.home_name : st.away_name}
              </span>
              <span className="side-card-role">{side === "home" ? "Home" : "Away"}</span>
            </button>
          ))}
        </div>
      </fieldset>

      <fieldset className="setup-group" disabled={!winner}>
        <legend>And chose to</legend>
        <div className="side-choice">
          {(["bat", "bowl"] as const).map((d) => (
            <button
              key={d}
              type="button"
              className={`side-card${decision === d ? " on" : ""}`}
              aria-pressed={decision === d}
              onClick={() => setDecision(d)}
            >
              <Icon name={d === "bat" ? "bat" : "ball"} size={22} />
              <span className="side-card-name">{d === "bat" ? "Bat" : "Bowl"}</span>
            </button>
          ))}
        </div>
      </fieldset>

      <button
        className="btn primary lg"
        type="button"
        disabled={!canAct || !winner || !decision}
        onClick={() => send({ type: "toss_recorded", winner, decision })}
      >
        {winner && decision
          ? `${winner === "home" ? st.home_name : st.away_name} chose to ${decision}`
          : "Record the toss"}
      </button>
    </div>
  );
}

function XiPanel({
  st,
  matchId,
  myClubSide,
  onPicked,
}: {
  st: MatchState;
  matchId: string;
  myClubSide: Side | null;
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

  const mine = myClubSide !== null;
  // Your own side first — it is the one you came here to fill in.
  const order: Side[] =
    myClubSide === "away" ? ["away", "home"] : ["home", "away"];

  return (
    <>
      <div className="panel">
        <h2>{mine ? "Pick your side" : "Team sheets"}</h2>
        <p className="muted">
          {mine
            ? "Name the eleven who turned up. The match starts once both captains have."
            : "Each captain names their own side. The match starts once both are in."}
        </p>
      </div>
      {order.map((side) => (
        <SideSheet
          key={side}
          side={squad[side]}
          st={st}
          matchId={matchId}
          isMine={side === myClubSide}
          onPicked={(next) => {
            onPicked(next);
            load();
          }}
        />
      ))}
    </>
  );
}

/// Naming one side.
///
/// Built around what a captain actually does: read down the squad, tap the
/// eleven who turned up, mark the skipper and the keeper. Picked players move
/// to a numbered list so the batting order is visible while it is being made,
/// rather than being inferred from checkbox positions.
function SideSheet({
  side,
  st,
  matchId,
  isMine,
  onPicked,
}: {
  side: SideSquad;
  st: MatchState;
  matchId: string;
  isMine: boolean;
  onPicked: (next: MatchResponse) => void;
}) {
  const already = side.side === "home" ? st.home_xi : st.away_xi;
  // Their captain names their own side. The scorer *can* do it for them, and
  // sometimes has to — a captain who has not turned up, a phone with no
  // signal — but doing it by default means naming eleven strangers off a list,
  // which is slower and more likely to be wrong than waiting a minute.
  const theirsToName = !isMine && side.club_id !== null;
  const [namingForThem, setNamingForThem] = useState(false);
  const [chosen, setChosen] = useState<string[]>([]);
  const [extras, setExtras] = useState<{ id: string; name: string; bats_left: boolean }[]>([]);
  const [addingGuest, setAddingGuest] = useState(false);
  const [newName, setNewName] = useState("");
  const [newLeft, setNewLeft] = useState(false);
  const [captain, setCaptain] = useState("");
  const [keeper, setKeeper] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const named = already.length > 0;

  // Order matters: it is the batting order, so picks keep the order they were
  // tapped in rather than the order the squad happens to be listed in.
  const picked = useMemo(
    () => [
      ...chosen.flatMap((id) => {
        const p = side.players.find((q) => q.id === id);
        return p ? [{ id: p.id, name: p.name, bats_left: p.bats_left }] : [];
      }),
      ...extras,
    ],
    [chosen, extras, side.players]
  );

  const toggle = (id: string) =>
    setChosen((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));

  const drop = (id: string) => {
    setChosen((prev) => prev.filter((x) => x !== id));
    setExtras((prev) => prev.filter((x) => x.id !== id));
    if (captain === id) setCaptain("");
    if (keeper === id) setKeeper("");
  };

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      onPicked(
        await api<MatchResponse>("POST", `/cricket/matches/${matchId}/xi`, {
          side: side.side,
          players: picked,
          captain_id: captain || null,
          keeper_id: keeper || null,
        })
      );
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "Could not save the sheet");
      } catch {
        setError(raw || "Could not save the sheet");
      }
    } finally {
      setBusy(false);
    }
  };

  if (named) {
    return (
      <div className="panel sheet-panel done">
        <div className="sheet-head">
          <h2>{side.team_name}</h2>
          <span className="tag"><Icon name="check" size={12} /> Named</span>
        </div>
        <ol className="named-xi">
          {already.map((id) => (
            <li key={id}>
              {st.player_names[id] || "…"}
              {id === (side.side === "home" ? st.home_captain : st.away_captain) && (
                <span className="role-badge c">C</span>
              )}
              {id === (side.side === "home" ? st.home_keeper : st.away_keeper) && (
                <span className="role-badge wk">WK</span>
              )}
            </li>
          ))}
        </ol>
      </div>
    );
  }

  if (!side.can_pick || (theirsToName && !namingForThem)) {
    return (
      <div className="panel sheet-panel">
        <div className="sheet-head">
          <h2>{side.team_name}</h2>
          <span className="tag grey">Waiting</span>
        </div>
        <div className="waiting-note">
          <Icon name="clock" size={18} />
          <span>
            Their captain names this side from their own phone. They have been told it is
            their turn.
          </span>
        </div>
        {side.can_pick && (
          <button
            className="btn ghost sm"
            type="button"
            style={{ marginTop: "var(--s3)" }}
            onClick={() => setNamingForThem(true)}
          >
            Name them myself
          </button>
        )}
      </div>
    );
  }

  const available = side.players.filter((p) => !chosen.includes(p.id));
  const short = XI_SIZE - picked.length;

  return (
    <div className="panel sheet-panel">
      <div className="sheet-head">
        <h2>{side.team_name}</h2>
        <span className={`count-pill${picked.length >= XI_SIZE ? " full" : ""}`}>
          <strong className="num">{picked.length}</strong> of {XI_SIZE}
        </span>
      </div>

      {namingForThem && (
        <div className="waiting-note" style={{ marginBottom: "var(--s4)" }}>
          <Icon name="clock" size={18} />
          <span>
            You are naming {side.team_name} for them. Their captain can still do it
            themselves until you confirm.{" "}
            <button className="link-button" type="button" onClick={() => setNamingForThem(false)}>
              Leave it to them
            </button>
          </span>
        </div>
      )}

      {picked.length > 0 ? (
        <ol className="picked-xi">
          {picked.map((p, i) => (
            <li key={p.id}>
              <span className="pick-no num">{i + 1}</span>
              <span className="pick-name">{p.name}</span>
              <button
                type="button"
                className={`role-toggle${captain === p.id ? " on" : ""}`}
                aria-pressed={captain === p.id}
                title="Captain"
                onClick={() => setCaptain(captain === p.id ? "" : p.id)}
              >
                C
              </button>
              <button
                type="button"
                className={`role-toggle${keeper === p.id ? " on" : ""}`}
                aria-pressed={keeper === p.id}
                title="Wicketkeeper"
                onClick={() => setKeeper(keeper === p.id ? "" : p.id)}
              >
                WK
              </button>
              <button
                type="button"
                className="pick-remove"
                aria-label={`Take ${p.name} out`}
                onClick={() => drop(p.id)}
              >
                ×
              </button>
            </li>
          ))}
        </ol>
      ) : (
        <p className="muted">Tap the players who turned up. They go in batting order.</p>
      )}

      {available.length > 0 && (
        <>
          <h3 className="sheet-sub">Squad</h3>
          <div className="squad-grid">
            {available.map((p) => (
              <button
                key={p.id}
                type="button"
                className="squad-chip"
                onClick={() => toggle(p.id)}
              >
                <Icon name="plus" size={14} />
                <span>{p.name}</span>
                {p.standing !== "member" && (
                  <span className={`tag ${p.standing === "selected" ? "gold" : "grey"}`}>
                    {STANDING_LABEL[p.standing] ?? p.standing}
                  </span>
                )}
              </button>
            ))}
          </div>
        </>
      )}

      {side.players.length === 0 && (
        <p className="muted">
          Not a Fishers club, so there is no squad to pick from. Add whoever turned up.
        </p>
      )}

      {addingGuest ? (
        <div className="field-row guest-row">
          <label>
            Their name
            <input
              value={newName}
              autoFocus
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Whoever turned up"
              onKeyDown={(e) => {
                if (e.key === "Enter" && newName.trim()) {
                  e.preventDefault();
                  addGuest();
                }
              }}
            />
          </label>
          <label className="checkbox">
            <input type="checkbox" checked={newLeft} onChange={(e) => setNewLeft(e.target.checked)} />
            Left-handed
          </label>
          <button className="btn" type="button" disabled={!newName.trim()} onClick={addGuest}>
            Add
          </button>
          <button className="btn ghost" type="button" onClick={() => setAddingGuest(false)}>
            Cancel
          </button>
        </div>
      ) : (
        <button className="btn ghost sm add-guest" type="button" onClick={() => setAddingGuest(true)}>
          <Icon name="plus" size={14} /> Someone not in the squad
        </button>
      )}

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || picked.length < 2}
        onClick={submit}
      >
        {busy ? "Saving…" : `Confirm ${side.team_name}`}
      </button>
      {/* Say what is missing rather than leaving a dead button. */}
      <p className="subtle">
        {picked.length < 2
          ? "Pick at least two players."
          : short > 0
            ? `${short} short of a full XI — you can still confirm if that is the side.`
            : "A full XI. Confirm when you are happy."}
      </p>
    </div>
  );

  function addGuest() {
    setExtras((prev) => [
      ...prev,
      { id: randomUUID(), name: newName.trim(), bats_left: newLeft },
    ]);
    setNewName("");
    setNewLeft(false);
    setAddingGuest(false);
  }
}

/// Naming the two batters and the bowler who starts.
///
/// Laid out the way they actually stand: a striker at one end, a non-striker
/// at the other, the bowler running in. A scorer looking up from the pitch is
/// matching the screen to what is in front of them, and three identical
/// dropdowns in a row do not help with that.
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
  const battingName = batting === "home" ? st.home_name : st.away_name;
  const bowlingName = batting === "home" ? st.away_name : st.home_name;

  const [striker, setStriker] = useState(battingXi[0] ?? "");
  const [nonStriker, setNonStriker] = useState(battingXi[1] ?? "");
  const [bowler, setBowler] = useState(bowlingXi[0] ?? "");
  const [busy, setBusy] = useState(false);

  const listFor = (xi: string[], taken: Record<string, string>) =>
    xi.map((id, i) => ({
      id,
      name: nameOf(id),
      position: i + 1,
      takenBy: taken[id],
    }));

  const swap = () => {
    setStriker(nonStriker);
    setNonStriker(striker);
  };

  const ready = !!striker && !!nonStriker && striker !== nonStriker && !!bowler;

  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>{index === 0 ? "Who is opening?" : `Innings ${index + 1}`}</h2>
        <p className="muted">
          <strong>{battingName}</strong> batting, <strong>{bowlingName}</strong> in the field
          {st.target ? ` · chasing ${st.target}` : ""}.
        </p>
      </div>

      <div className="crease">
        <div className="crease-end">
          <span className="crease-role on-strike">On strike</span>
          <PlayerPicker
            label="Striker"
            hint="Faces the first ball"
            players={listFor(battingXi, nonStriker ? { [nonStriker]: "at the other end" } : {})}
            value={striker}
            onChange={setStriker}
          />
        </div>

        {/* The pitch between them, and the one correction scorers make most. */}
        <div className="crease-pitch">
          <button
            className="swap-ends"
            type="button"
            onClick={swap}
            disabled={!striker || !nonStriker}
            aria-label="Swap the batters over"
            title="Swap ends"
          >
            ⇄
          </button>
          <span className="crease-label">22 yards</span>
        </div>

        <div className="crease-end">
          <span className="crease-role">Other end</span>
          <PlayerPicker
            label="Non-striker"
            hint="Backing up"
            players={listFor(battingXi, striker ? { [striker]: "on strike" } : {})}
            value={nonStriker}
            onChange={setNonStriker}
          />
        </div>
      </div>

      <div className="bowling-end">
        <PlayerPicker
          label="Opening bowler"
          hint={`${bowlingName} — bowls the first over`}
          players={listFor(bowlingXi, {})}
          value={bowler}
          onChange={setBowler}
        />
      </div>

      <button
        className="btn primary lg"
        type="button"
        disabled={!canAct || busy || !ready}
        onClick={async () => {
          setBusy(true);
          try {
            await send({
              type: "innings_started",
              innings_index: index,
              batting,
              striker_id: striker,
              non_striker_id: nonStriker,
              bowler_id: bowler,
              super_over: false,
            });
          } finally {
            setBusy(false);
          }
        }}
      >
        {busy ? "Starting…" : "Start the innings"}
      </button>
      <p className="subtle">
        {!striker || !nonStriker
          ? "Name both batters."
          : striker === nonStriker
            ? "The same player cannot be at both ends."
            : !bowler
              ? "Name the bowler taking the first over."
              : `${nameOf(bowler)} to ${nameOf(striker)}, first ball.`}
      </p>
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

      {/* ---- controls ----
           Only for whoever is actually scoring. Somebody following the match
           came to watch it, and a dial they cannot press is furniture — but
           the column should not just be left empty either. */}
      {!canAct && <Following st={st} inn={inn} nameOf={nameOf} />}
      {canAct && <div className="controls">
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
      </div>}

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

/// What the right column holds for somebody watching rather than scoring.
///
/// Not a repeat of the scorecard below — the live things a spectator keeps
/// looking back at: how the partnership is going, who is bowling well, what is
/// needed, and who is next in.
function Following({
  st,
  inn,
  nameOf,
}: {
  st: MatchState;
  inn: Innings;
  nameOf: (id?: string | null) => string;
}) {
  const balls = inn.legal_balls || 0;
  const rr = balls > 0 ? (inn.runs * 6) / balls : 0;
  const target = st.target ?? null;
  const ballsLeft = (inn.overs_available ?? st.overs_limit) * 6 - balls;
  const need = target != null ? target - inn.runs : null;
  const req = need != null && ballsLeft > 0 ? (need * 6) / ballsLeft : null;

  // Best figures first: a spectator scans for who is doing the damage.
  const bowlers = [...(inn.bowlers ?? [])]
    .filter((b) => b.balls > 0)
    .sort((a, b) => b.wickets - a.wickets || a.runs - b.runs)
    .slice(0, 3);

  // The engine lists the whole XI as batters from the start, so "has a row"
  // is not "has batted" — everybody looked already in, and nobody was ever
  // yet to bat. The scorecard draws the same line.
  const faced = new Set(
    (inn.batters ?? []).filter((b) => b.balls > 0 || b.out).map((b) => b.player_id)
  );
  const atCrease = new Set([inn.striker_id, inn.non_striker_id].filter(Boolean) as string[]);
  const battingXi = inn.batting === "home" ? st.home_xi : st.away_xi;
  const toBat = battingXi.filter((id) => !faced.has(id) && !atCrease.has(id));
  const lastWicket = (inn.fall ?? [])[(inn.fall ?? []).length - 1];

  return (
    <div className="following">
      {need != null && (
        <div className="panel chase-panel">
          <h2>The chase</h2>
          <p className="chase-line">
            <strong className="num">{Math.max(need, 0)}</strong> to win from{" "}
            <strong className="num">{Math.max(ballsLeft, 0)}</strong> balls
          </p>
          <dl className="terms-summary">
            <div><dt>Run rate</dt><dd className="num">{rr.toFixed(2)}</dd></div>
            <div>
              <dt>Required</dt>
              <dd className="num">{req != null ? req.toFixed(2) : "—"}</dd>
            </div>
          </dl>
        </div>
      )}

      <div className="panel">
        <h2>At the crease</h2>
        <dl className="terms-summary">
          <div>
            <dt>Partnership</dt>
            <dd className="num">
              {inn.partnership_runs ?? 0}
              <span className="subtle"> ({inn.partnership_balls ?? 0})</span>
            </dd>
          </div>
          <div><dt>Run rate</dt><dd className="num">{rr.toFixed(2)}</dd></div>
          <div>
            <dt>Overs</dt>
            <dd className="num">
              {overs(balls)}
              <span className="subtle"> of {inn.overs_available ?? st.overs_limit}</span>
            </dd>
          </div>
          <div><dt>Extras</dt><dd className="num">{inn.extras ?? 0}</dd></div>
        </dl>
        {lastWicket && (
          <p className="subtle">
            Last out: {nameOf(lastWicket.batter_id)} at {lastWicket.score}-{lastWicket.wickets}{" "}
            ({lastWicket.over_ball})
          </p>
        )}
      </div>

      {bowlers.length > 0 && (
        <div className="panel">
          {/* The full figures are on the scorecard below; this is the pair
              doing the damage right now. */}
          <h2>Leading the attack</h2>
          <ul className="figures">
            {bowlers.map((b) => (
              <li key={b.player_id} className={b.player_id === inn.bowler_id ? "on" : ""}>
                <span className="figure-name">
                  {nameOf(b.player_id)}
                  {b.player_id === inn.bowler_id && <span className="tag grey">bowling</span>}
                </span>
                <span className="figure-figs num">
                  {b.wickets}-{b.runs}
                  <span className="subtle"> ({overs(b.balls)})</span>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {toBat.length > 0 && (
        <div className="panel">
          {/* Who walks in on the next wicket. The whole list is on the
              scorecard; here it is only the next few. */}
          <h2>Next in</h2>
          <ol className="named-xi">
            {toBat.slice(0, 3).map((id) => <li key={id}>{nameOf(id)}</li>)}
          </ol>
          {toBat.length > 3 && (
            <p className="subtle">and {toBat.length - 3} more on the scorecard</p>
          )}
        </div>
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

