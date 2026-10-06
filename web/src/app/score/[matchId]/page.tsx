"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, getAccessToken, getStoredUser, readErr } from "@/lib/api";
import { randomUUID } from "@/lib/uuid";
import { subscribeLive } from "@/lib/live";
import { WagonWheel } from "@/components/WagonWheel";
import { Scorecard } from "@/components/Scorecard";
import { RateUmpires } from "@/components/RateUmpires";
import { Icon } from "@/components/Icon";
import { PeoplePicker, type PeopleTab, type Person as PickPerson } from "@/components/PeoplePicker";
import { PersonPicker, type Person } from "@/components/PersonPicker";
import { PlayerPicker } from "@/components/PlayerPicker";
import { ShotIcon, SHOT_SHAPES } from "@/components/ShotIcon";
import { useLocale, useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";
import type { T } from "@/lib/i18n";
import { ShareScoreboardButton } from "@/components/ShareScoreboardButton";
import { OverflowMenu } from "@/components/OverflowMenu";
import { Sheet } from "@/components/Sheet";
import { Moments } from "@/components/Moments";
import { useRequireAuth } from "@/lib/require-auth";
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
  type Innings,
  type MatchConditions,
  type MatchResponse,
  type MatchInsights,
  type MatchState,
  type PlayerImpact,
  type SideInsights,
  type Side,
  type SideSquad,
  type MatchOfficial,
  type SquadResponse,
  inningsScore,
  titleCase,
} from "@/lib/cricket";
import { brand } from "@/brand.generated";
import { apply as engineApply } from "@/lib/engine";
import {
  clear as clearOutbox,
  load as loadOutbox,
  save as saveOutbox,
  syncLabel,
  type SyncState,
} from "@/lib/outbox";

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


const other = (s: Side): Side => (s === "home" ? "away" : "home");

export default function ScorerPage({
  params,
}: {
  params: Promise<{ matchId: string }>;
}) {
  const t = useT();
  const { matchId } = use(params);
  const authed = useRequireAuth();
  const router = useRouter();
  const [match, setMatch] = useState<MatchResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  /// Handing the book over, opened from the ⋯ menu and from the innings
  /// break, which is where it actually changes hands. Declared here with the
  /// other hooks: below the `if (!match) return` guards the hook count changes
  /// between the loading render and the loaded one, and React blanks the page.
  const [handingOver, setHandingOver] = useState(false);
  const [busy, setBusy] = useState(false);
  /// Balls the server has not acknowledged, oldest first. A ref rather than
  /// state: `send` reads and writes it within one tap, and a re-render in the
  /// middle of that would number the next ball from a stale queue.
  const queued = useRef<Record<string, unknown>[]>([]);
  const [sync, setSync] = useState<SyncState>("saved");
  /// Both team sheets as the clubs hold them, which is the only thing that
  /// says who on the card is a Fishers player. A guest is a name the scorer
  /// typed with an id this browser invented, and their profile does not
  /// exist — so their name on the scorecard stays plain text.
  const squad = useSquad(matchId);

  const load = useCallback(async () => {
    try {
      const next = await api<MatchResponse>("GET", `/cricket/matches/${matchId}`);
      // Never step backwards. A refetch started before the scorer's latest
      // ball can land after it; an older state would briefly undo that ball
      // on screen. Equal is accepted — a handover changes the match without
      // adding a ball. Balls waiting in the queue are ahead of anything the
      // server can send, so the same rule keeps them on screen.
      setMatch((cur) => (cur && next.last_seq < cur.last_seq ? cur : next));
      if (queued.current.length === 0) {
        setSync("saved");
        setError(null);
        saveOutbox({
          matchId,
          match: next,
          pending: [],
          lastSeq: next.last_seq,
          deviceId: deviceId(),
          updatedAt: Date.now(),
        });
      }
    } catch (err) {
      // Offline is not a failure to load — it is a match that carries on from
      // what this device already holds. The error is only worth showing when
      // there is nothing to show instead.
      const kept = await loadOutbox(matchId);
      if (kept) {
        queued.current = kept.pending as Record<string, unknown>[];
        setMatch((cur) => cur ?? (kept.match as MatchResponse));
        setSync(kept.pending.length > 0 ? "offline" : "saved");
        return;
      }
      setError(readErr(err, t("la.could_not_load_the_match")));
    }
  }, [matchId, t]);

  /// Push whatever is queued. Everything goes in one batch: the API takes up
  /// to 500 events and applies a batch it has already seen as nothing, so a
  /// retry after a half-failure cannot double-count a ball.
  // One at a time, and it drains until the queue is empty. Two taps in quick
  // succession used to start two overlapping batches, and whichever answered
  // last won the screen: when that was the older one, the ball the scorer had
  // just recorded vanished from the ground until the next poll, half a minute
  // later. The server had it all along — only this screen had lost it.
  const flushing = useRef(false);
  const flush = useCallback(async () => {
    if (flushing.current) return;
    flushing.current = true;
    try {
      while (queued.current.length > 0) {
        const batch = queued.current;
        setSync("syncing");
        try {
          const next = await api<MatchResponse>(
            "POST",
            `/cricket/matches/${matchId}/events`,
            { device_id: deviceId(), events: batch },
          );
          // Only what this batch carried. A ball tapped while it was in
          // flight is still waiting its turn, and emptying the whole queue
          // would throw that ball away without a word.
          queued.current = queued.current.slice(batch.length);
          // Never step backwards, for the same reason `load` does not.
          setMatch((cur) => (cur && next.last_seq < cur.last_seq ? cur : next));
          setError(null);
          if (queued.current.length === 0) {
            setSync("saved");
            await clearOutbox(matchId);
          }
        } catch (err) {
          setSync("offline");
          // Only worth saying out loud when the server refused on its own
          // terms; a dropped network is what the chip is for. What is queued
          // stays queued — the interval and `online` will try again.
          if (navigator.onLine) {
            setError(readErr(err, t("la.the_api_rejected_that")));
          }
          return;
        }
      }
    } finally {
      flushing.current = false;
    }
  }, [matchId, t]);

  // Coming back to signal is the moment the queue empties. `online` is not
  // wholly reliable — a captive portal fires it while nothing yet resolves —
  // so a slow interval backs it up while anything is still waiting.
  useEffect(() => {
    if (!authed) return;
    const onOnline = () => { flush(); };
    window.addEventListener("online", onOnline);
    const timer = window.setInterval(() => {
      if (queued.current.length > 0) flush();
    }, 20_000);
    return () => {
      window.removeEventListener("online", onOnline);
      window.clearInterval(timer);
    };
  }, [authed, flush]);

  useEffect(() => {
    if (!authed) return;
    load();
    // Live: every ball, the toss, a handover or the result arrives the moment
    // it is recorded — for everyone watching, players included. The event only
    // says the match changed; the refetch goes through the normal endpoint.
    const stop = subscribeLive((e) => {
      if (e.type === "resync" || (e.type === "match" && e.id === matchId)) load();
    });
    // A safety net for when the live stream is down, not the mechanism.
    const timer = window.setInterval(load, 30_000);
    return () => {
      stop();
      window.clearInterval(timer);
    };
  }, [authed, load, matchId]);

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
      // `match` already carries anything queued, because a queued ball was
      // applied to it on screen.
      let seq = match.last_seq;
      const events: Record<string, unknown>[] = [];

      // The log is the only lasting record: the server seeds the team names
      // from the fixture row only while nothing has been scored, and replays
      // from the log after that. Without this first event the names would
      // revert to "Home"/t("la.away") the moment a second batch arrived.
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
      // The engine demands the next seq exactly. It counts from the last ball
      // this device has applied, not from the last the server acknowledged —
      // otherwise a second ball tapped with no signal would reuse the first
      // one's number and the batch would be refused on reconnect.
      events.push({ client_event_id: randomUUID(), seq: ++seq, kind, at });

      // The Laws first, here, before anything is sent or queued. This is the
      // same Rust the server replays with, compiled to WebAssembly, so a ball
      // it accepts is a ball the server will accept — and a ball it refuses is
      // refused at the moment of the tap, in the engine's own words, rather
      // than an hour later when the network comes back and takes the whole
      // over with it.
      let applied: MatchResponse;
      try {
        let state: unknown = match.state;
        for (const event of events) state = await engineApply(state, event);
        applied = {
          ...match,
          state: state as MatchResponse["state"],
          last_seq: seq,
        };
      } catch (err) {
        setError(readErr(err, t("la.the_laws_do_not_allow_that")));
        sending.current = false;
        setBusy(false);
        return;
      }

      // On screen immediately, and on disk before the network is asked for
      // anything: a scorer who loses signal mid-over keeps the over.
      setMatch(applied);
      queued.current = [...queued.current, ...events];
      await saveOutbox({
        matchId,
        match: applied,
        pending: queued.current,
        lastSeq: seq,
        deviceId: deviceId(),
        updatedAt: Date.now(),
      });

      sending.current = false;
      setBusy(false);
      await flush();
    },
    [match, matchId, flush, t]
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
      setError(readErr(err, t("la.could_not_claim_the_book")));
    } finally {
      setBusy(false);
    }
  };

  if (!authed) return <main id="main" />;
  if (error && !match) return <main id="main"><p className="error">{error}</p></main>;
  if (!match) return <main><p className="muted">{t("sc.loading_match")}</p></main>;

  const st = match.state;
  const me = getStoredUser();
  const heldByMe = match.active_scorer_user_id === me?.id;
  const heldBySomeoneElse =
    !!match.active_scorer_user_id && !heldByMe;
  // Whether this is the scorer's screen, and whether it can take a tap right
  // now. Kept apart: while a ball is being sent the controls stay where they
  // are, disabled — they used to vanish for the spectator's view instead, and
  // a send that waited on the network left the scorer with nothing to press.
  const scoring = match.can_score && heldByMe;
  const canAct = scoring && !busy;

  const nameOf = (id?: string | null) =>
    !id ? "—" : st.player_names[id] || st.player_names[id.toLowerCase()] || id.slice(0, 8);

  const onFishers = new Set(
    (["home", "away"] as Side[]).flatMap((side) => squad.people(side).map((p) => p.id))
  );

  // Before the first ball the screen is a setup flow, and saying which step
  // you are on is most of what makes it feel like one.
  const isSetup = st.status !== "complete" && st.innings.length === 0;

  return (
    <main>
      <Moments state={st} nameOf={nameOf} />
      <section className="match-head">
        <div className="match-head-sides">
          <span className="match-head-side">{st.home_name}</span>
          <span className="match-head-v">v</span>
          <span className="match-head-side away">{st.away_name}</span>
        </div>
        <div className="match-head-meta">
          <span className={`status-pill ${st.status}`}>{t(`status.${st.status}` as Key)}</span>
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
              <span className="tag">
                {st.conditions.overs_limit > 0
                  ? t("tn.n_overs", { n: st.conditions.overs_limit })
                  : t("la.no_over_limit")}
              </span>
              <span className="tag">{t("sc.ball_with_type", { type: t(`ball_type.${st.conditions.ball}` as Key) })}</span>
              <span className="tag">{t("sc.ground_with_type", { type: t(`ground_type.${st.conditions.ground}` as Key) })}</span>
            </>
          )}
        </div>
        {/* Anyone signed in can mint a public live link — not only the scorer.
            Behind the ⋯ because it is used once a match, and the top of a
            phone screen belongs to the score and the dial. */}
        {getAccessToken() && (
          <div className="match-head-actions">
            <OverflowMenu label={t("sc.match_options")}>
              <ShareScoreboardButton
                matchId={matchId}
                homeName={st.home_name}
                awayName={st.away_name}
                className="share-in-menu"
              />
              {heldByMe && (
                <button
                  className="overflow-item"
                  type="button"
                  onClick={() => setHandingOver(true)}
                >
                  <Icon name="book" size={16} /> {t("sc.hand_the_book_over")}
                </button>
              )}
            </OverflowMenu>
          </div>
        )}
      </section>

      {isSetup && <SetupRail st={st} hasScorer={!!match.active_scorer_user_id} />}

      {isSetup && st.toss_winner && <TossResult st={st} />}

      {isSetup && match.can_score && <Umpires match={match} onChanged={setMatch} />}

      {/* Where the scorer's work is. It says nothing while everything is
          saved and the network is doing its job — a chip that is always there
          is a chip nobody reads. */}
      {sync !== "saved" && (
        <p className={`sync-chip ${sync}`} role="status" aria-live="polite">
          {syncLabel(sync, queued.current.length, t)}
          {sync === "offline" && (
            <span className="sync-note">
              {t("sc.they_will_go_up_on_their_own_when_ther")}
            </span>
          )}
        </p>
      )}

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
            Following along. {match.active_scorer_user_id ? t("la.someone_else_is") : t("la.nobody_is")}{" "}
            scoring this match — the scorecard below updates as they do.
          </span>
        </div>
      )}

      {match.can_score && !match.active_scorer_user_id && (
        <div className="panel claim-panel">
          <div>
            <h2>{t("sc.nobody_is_scoring_yet")}</h2>
            <p className="muted">
              {t("sc.whoever_takes_the_book_records_every_b")}
            </p>
          </div>
          <button
            className="btn primary lg"
            type="button"
            disabled={busy}
            onClick={() => claim(false)}
          >
            <Icon name="book" size={18} /> {t("sc.take_the_book")}
          </button>
        </div>
      )}

      {heldBySomeoneElse && match.can_score && (
        <div className="panel">
          <p className="error">
            {t("sc.someone_else_is_scoring_this_match_onl")}
          </p>
          <button className="btn ghost" type="button" disabled={busy} onClick={() => claim(true)}>
            {t("sc.take_it_over_captain_or_secretary_only")}
          </button>
          <button className="btn ghost" type="button" onClick={load} style={{ marginLeft: "0.5rem" }}>
            {t("sc.refresh")}
          </button>
        </div>
      )}

      <Stages
        match={match}
        send={send}
        scoring={scoring}
        canAct={canAct}
        // Whether the server has everything this screen has. Commentary is
        // the only thing that asks the server about a particular ball, so it
        // is the only thing that has to wait for one to arrive there.
        synced={sync === "saved"}
        nameOf={nameOf}
        onPicked={setMatch}
        onHandOver={() => setHandingOver(true)}
      />

      {heldByMe && handingOver && (
        <HandOver
          match={match}
          onChanged={(next) => { setMatch(next); setHandingOver(false); }}
          onClose={() => setHandingOver(false)}
        />
      )}

      <CallItOff match={match} onChanged={setMatch} onGone={() => router.push("/score")} />

      <Scorecard
        st={st}
        nameOf={nameOf}
        profile={(id) => (onFishers.has(id) ? `/players/${id}` : null)}
      />

      <p className="muted" style={{ marginTop: "1rem" }}>
        <Link href="/score">{t("ev.all_fixtures_back")}</Link>
      </p>
    </main>
  );
}


/// Naming the umpires, before the toss.
///
/// Optional — plenty of club games have no neutral umpire, and the app should
/// not pretend otherwise. But when one is named the book goes to them, because
/// at this level the square-leg umpire usually keeps it, and they can hand it
/// on to anybody playing.
function Umpires({
  match,
  onChanged,
}: {
  match: MatchResponse;
  onChanged: (next: MatchResponse) => void;
}) {
  const t = useT();
  const [officials, setOfficials] = useState<MatchOfficial[] | null>(null);
  const [squad, setSquad] = useState<SquadResponse | null>(null);
  const [open, setOpen] = useState(false);
  const [choice, setChoice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<MatchOfficial[]>("GET", `/cricket/matches/${match.id}/officials`)
      .then(setOfficials)
      .catch(() => setOfficials([]));
  }, [match.id]);

  useEffect(() => {
    if (!open || squad) return;
    api<SquadResponse>("GET", `/cricket/matches/${match.id}/squad`)
      .then(setSquad)
      .catch(() => {});
  }, [open, squad, match.id]);

  // Only the two sides here: somebody already named is not a candidate.
  const tabs = useMemo(() => {
    const named = new Set((officials ?? []).map((o) => o.user_id));
    const side = (label: string, players: { id: string; name: string }[]): PeopleTab => ({
      label,
      people: players.filter((p) => !named.has(p.id)).map((p) => ({ id: p.id, name: p.name })),
    });
    return [
      side(match.state.home_name || t("la.home"), squad?.home.players ?? []),
      side(match.state.away_name || t("la.away"), squad?.away.players ?? []),
    ];
  }, [officials, squad, match.state.home_name, match.state.away_name, t]);

  const appoint = async () => {
    if (!choice) return;
    setBusy(choice);
    setError(null);
    try {
      setOfficials(
        await api<MatchOfficial[]>("POST", `/cricket/matches/${match.id}/officials`, {
          user_id: choice,
          role: "umpire",
        })
      );
      setOpen(false);
      setChoice(null);
      // Appointing the first umpire may have handed them the book, so the
      // match this page is drawing has changed underneath it.
      onChanged(await api<MatchResponse>("GET", `/cricket/matches/${match.id}`));
    } catch (err) {
      setError(readErr(err, t("la.could_not_appoint_them")));
    } finally {
      setBusy(null);
    }
  };

  const stand = async (userId: string) => {
    setBusy(userId);
    setError(null);
    try {
      setOfficials(
        await api<MatchOfficial[]>(
          "DELETE",
          `/cricket/matches/${match.id}/officials/${userId}`
        )
      );
    } catch (err) {
      setError(readErr(err, t("la.could_not_stand_them_down")));
    } finally {
      setBusy(null);
    }
  };

  if (officials === null) return null;
  const umpires = officials.filter((o) => o.role === "umpire");

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("sc.umpires")}</h2>
        <span className="tag grey">{t("sc.optional")}</span>
      </div>
      <p className="muted">
        {t("sc.name_them_and_the_book_starts_in_their")}
      </p>

      {umpires.length > 0 && (
        <ul className="named-list">
          {umpires.map((u) => (
            <li key={u.user_id}>
              <span className="people-name">{u.name}</span>
              <button
                type="button"
                className="btn ghost sm"
                disabled={busy === u.user_id}
                onClick={() => stand(u.user_id)}
              >
                {t("sc.stand_down")}
              </button>
            </li>
          ))}
        </ul>
      )}

      {!open ? (
        <button className="btn" type="button" onClick={() => setOpen(true)}>
          <Icon name="plus" size={16} /> {umpires.length ? t("la.another_umpire") : t("la.name_an_umpire")}
        </button>
      ) : (
        <>
          {!squad ? (
            <div className="skeleton" style={{ height: 180 }} />
          ) : (
            <PeoplePicker
              tabs={tabs}
              chosen={choice}
              onChoose={setChoice}
              empty={t("la.nobody_left_to_name_pick_the_teams_fir")}
            />
          )}
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button
              className="btn primary"
              type="button"
              disabled={!choice || busy !== null}
              onClick={appoint}
            >
              {busy ? t("la.appointing") : t("la.appoint_as_umpire")}
            </button>
            <button
              className="btn"
              type="button"
              onClick={() => {
                setOpen(false);
                setChoice(null);
              }}
            >
              {t("sc.cancel")}
            </button>
          </div>
        </>
      )}

      {error && <p className="error">{error}</p>}
    </div>
  );
}

/// Passing the book to somebody else.
///
/// Whoever holds it records every ball, so it has to be handed over on
/// purpose: a scorer going for tea, a phone about to die. Anybody playing is
/// offered, from either side — at club level the book crosses between teams
/// all afternoon, and the batter waiting to go in is often the one keeping it.
/// One team per tab, because thirty names in one list is not a choice, it is
/// a search problem.
function HandOver({
  match,
  onChanged,
  onClose,
}: {
  match: MatchResponse;
  onChanged: (next: MatchResponse) => void;
  onClose: () => void;
}) {
  const t = useT();
  const [squad, setSquad] = useState<SquadResponse | null>(null);
  const [officials, setOfficials] = useState<MatchOfficial[]>([]);
  const [loading, setLoading] = useState(false);
  const [choice, setChoice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const me = getStoredUser();

  useEffect(() => {
    if (squad) return;
    setLoading(true);
    (async () => {
      const [sq, offs] = await Promise.all([
        api<SquadResponse>("GET", `/cricket/matches/${match.id}/squad`).catch(() => null),
        api<MatchOfficial[]>("GET", `/cricket/matches/${match.id}/officials`).catch(
          () => [] as MatchOfficial[]
        ),
      ]);
      setSquad(sq);
      setOfficials(offs);
      setLoading(false);
    })();
  }, [squad, match.id]);

  const tabs = useMemo(
    () =>
      sidesAndOfficials(match, squad, officials, me?.id, (o) => o.role, t),
    [match, squad, officials, me?.id, t]
  );

  // Between innings the book nearly always goes to the side about to bat, so
  // open on them rather than making the home tab the answer to every question.
  const last = match.state.innings[match.state.innings.length - 1];
  const openOn =
    last?.complete
      ? other(last.batting as Side) === "home"
        ? match.state.home_name
        : match.state.away_name
      : undefined;

  const hand = async () => {
    if (!choice) return;
    setBusy(true);
    setError(null);
    try {
      onChanged(
        await api<MatchResponse>("POST", `/cricket/matches/${match.id}/handover`, {
          to_user_id: choice,
        })
      );
    } catch (err) {
      setError(readErr(err, t("la.could_not_hand_it_over")));
    } finally {
      setBusy(false);
    }
  };

  // A pop-up, not a panel: rendered in the page flow it landed far below the
  // menu it was opened from, so pressing "Hand the book over" looked like
  // nothing happened.
  return (
    <Sheet title={t("sc.hand_over_the_book")} onClose={onClose}>
      <p className="muted">
        {t("sc.they_take_over_recording_every_ball_fr")}
      </p>

      {loading ? (
        <div className="skeleton" style={{ height: 180 }} />
      ) : (
        <PeoplePicker tabs={tabs} chosen={choice} onChoose={setChoice} keepTabs openOn={openOn} />
      )}

      {error && <p className="error">{error}</p>}

      <div className="sheet-actions">
        <button className="btn" type="button" onClick={onClose}>
          {t("sc.keep_the_book")}
        </button>
        <button className="btn primary" type="button" disabled={!choice || busy} onClick={hand}>
          {busy ? t("la.handing_over") : t("la.hand_it_over")}
        </button>
      </div>
    </Sheet>
  );
}

/// Who the book can go to: each side, then the umpires.
///
/// Both teams always get their own tab, even an empty one, because "Team A,
/// Team B" is how anybody at a ground thinks about it; an empty tab says why.
/// Umpires follow, and only when there are some. Nobody appears twice — an
/// umpire who is also in the XI belongs under Umpires, the more useful thing to
/// know about them — and the person asking is never offered themselves.
function sidesAndOfficials(
  match: MatchResponse,
  squad: SquadResponse | null,
  officials: MatchOfficial[],
  meId: string | undefined,
  noteFor: (o: MatchOfficial) => string | undefined,
  t: T
): PeopleTab[] {
  const seen = new Set<string>(meId ? [meId] : []);
  const take = (rows: PickPerson[]) =>
    rows.filter((r) => {
      if (seen.has(r.id)) return false;
      seen.add(r.id);
      return true;
    });

  // Officials claim their people first, so they are not listed twice.
  const umpires = take(officials.map((o) => ({ id: o.user_id, name: o.name, note: noteFor(o) })));
  const side = (s: SquadResponse["home"] | undefined, name: string): PeopleTab => ({
    label: name,
    people: take((s?.players ?? []).map((p) => ({ id: p.id, name: p.name }))),
    // A side that is not a club on Fishers is names the scorer typed in:
    // nobody there has an account the book could go to.
    emptyText:
      s && !s.club_id
        ? t("fin.side_not_on_brand", { side: name, brand: brand.name })
        : t("fin.nobody_else_from", { side: name }),
  });

  return [
    side(squad?.home, match.state.home_name || t("la.home")),
    side(squad?.away, match.state.away_name || t("la.away")),
    ...(umpires.length > 0 ? [{ label: t("la.umpires"), people: umpires }] : []),
  ];
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
  const t = useT();
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
      setError(readErr(err, t("la.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button className="btn ghost sm call-off" type="button" onClick={() => setOpen(true)}>
        {bowled ? t("la.abandon_this_match") : t("la.call_this_match_off")}
      </button>
    );
  }

  return (
    <div className="panel danger-panel">
      <h2>{bowled ? t("la.abandon_this_match") : t("la.call_this_match_off")}</h2>
      {bowled ? (
        <>
          <p className="muted">
            {t("sc.it_goes_down_as_no_result_the_scorecar")}
          </p>
          <label>
            {t("sc.why_goes_on_the_scorecard")}
            <input
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={t("sc.rain_bad_light_ground_unfit")}
              autoFocus
            />
          </label>
        </>
      ) : (
        <p className="muted">
          {t("sc.nothing_has_been_scored_so_the_match_i")}
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
          {busy ? t("la.working") : bowled ? t("la.abandon_no_result") : t("la.delete_the_match")}
        </button>
        <button className="btn" type="button" onClick={() => setOpen(false)}>
          {t("sc.keep_playing")}
        </button>
      </div>
    </div>
  );
}

/// Who won the toss and what they did with it — the thing both sides ask about
/// the moment it happens.
function TossResult({ st }: { st: MatchState }) {
  const t = useT();
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
        {t("la.won_toss_and_chose", {
          winner,
          decision: st.toss_decision === "bat" ? t("la.bat_lower") : t("la.bowl_lower"),
        })}
        {batting && <> {t("la.side_bats_first", { side: batting })}</>}
      </p>
    </div>
  );
}

/// Where the setup has got to. Reads the same state `Stages` switches on, so
/// the two can never disagree about which step you are on.
function SetupRail({ st, hasScorer }: { st: MatchState; hasScorer: boolean }) {
  const t = useT();
  const steps = [
    { label: t("la.scorer"), done: hasScorer },
    { label: t("la.terms"), done: !!st.agreed_home && !!st.agreed_away },
    { label: t("la.toss"), done: !!st.toss_winner },
    { label: t("la.team_sheets"), done: st.home_xi.length > 0 && st.away_xi.length > 0 },
  ];
  const current = steps.findIndex((s) => !s.done);

  return (
    <ol className="setup-rail" aria-label={t("sc.match_setup")}>
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

/// The two innings read across: value · what · value.
///
/// Columns run in the order the sides batted, so they line up with the scores
/// directly above rather than making the reader check which way round it is.
/// Every figure comes off the ball-by-ball log the scorer was keeping anyway —
/// nobody records dot balls or a powerplay total by hand.
function Comparison({
  insights,
  battedFirst,
}: {
  insights: MatchInsights;
  battedFirst: Side;
}) {
  const t = useT();
  const [left, right] =
    battedFirst === "home"
      ? [insights.home, insights.away]
      : [insights.away, insights.home];

  const rate = (n: number) => n.toFixed(2);
  const pct = (n: number) => `${Math.round(n)}%`;
  const phaseOf = (side: SideInsights, name: string) => {
    const p = side.phases.find((x) => x.name === name);
    return p ? `${p.runs}/${p.wickets}` : "—";
  };
  const phaseNames = ["Powerplay", t("la.middle"), t("la.death")].filter(
    (n) => left.phases.some((p) => p.name === n) || right.phases.some((p) => p.name === n)
  );
  const oversOf = (name: string) =>
    left.phases.find((p) => p.name === name)?.overs ??
    right.phases.find((p) => p.name === name)?.overs;

  /// `better` says which way is good on that line, for the highlight. Dot
  /// balls are the one where fewer wins; "none" is for rows where being ahead
  /// means nothing, like how many overs each side faced.
  type Row = {
    label: string;
    left: string;
    right: string;
    lead?: number;
    better?: "high" | "low";
  };
  const rows: Row[] = [
    { label: t("la.score"), left: `${left.runs}/${left.wickets}`, right: `${right.runs}/${right.wickets}`, lead: left.runs - right.runs, better: "high" },
    { label: t("la.overs"), left: left.overs, right: right.overs },
    { label: t("la.run_rate"), left: rate(left.run_rate), right: rate(right.run_rate), lead: left.run_rate - right.run_rate, better: "high" },
    { label: t("la.dot_balls"), left: `${left.dots} · ${pct(left.dot_percent)}`, right: `${right.dots} · ${pct(right.dot_percent)}`, lead: left.dots - right.dots, better: "low" },
    { label: t("la.fours"), left: `${left.fours}`, right: `${right.fours}`, lead: left.fours - right.fours, better: "high" },
    { label: t("la.sixes"), left: `${left.sixes}`, right: `${right.sixes}`, lead: left.sixes - right.sixes, better: "high" },
    { label: t("la.in_boundaries"), left: `${left.boundary_runs} · ${pct(left.boundary_percent)}`, right: `${right.boundary_runs} · ${pct(right.boundary_percent)}`, lead: left.boundary_runs - right.boundary_runs, better: "high" },
    ...phaseNames.map((n): Row => {
      const l = left.phases.find((p) => p.name === n);
      const r = right.phases.find((p) => p.name === n);
      return {
        label: oversOf(n) ? `${n} ${oversOf(n)}` : n,
        left: phaseOf(left, n),
        right: phaseOf(right, n),
        lead: (l?.runs ?? 0) - (r?.runs ?? 0),
        better: "high",
      };
    }),
    { label: t("la.top_order_1_3"), left: `${left.top_order}`, right: `${right.top_order}`, lead: left.top_order - right.top_order, better: "high" },
    { label: t("la.middle_order_4_7"), left: `${left.middle_order}`, right: `${right.middle_order}`, lead: left.middle_order - right.middle_order, better: "high" },
    { label: t("la.lower_order_8"), left: `${left.lower_order}`, right: `${right.lower_order}`, lead: left.lower_order - right.lower_order, better: "high" },
    { label: t("la.best_stand"), left: `${left.best_partnership}`, right: `${right.best_partnership}`, lead: left.best_partnership - right.best_partnership, better: "high" },
    { label: t("la.extras"), left: `${left.extras}`, right: `${right.extras}`, lead: left.extras - right.extras, better: "low" },
  ];

  const ahead = (row: Row, side: "left" | "right") => {
    if (!row.better || !row.lead) return "";
    const leftWins = row.better === "high" ? row.lead > 0 : row.lead < 0;
    return (side === "left") === leftWins ? " ahead" : "";
  };

  return (
    // Wrapped so a narrow phone scrolls the table, never the page.
    <div className="table-wrap">
    <table className="compare">
      <thead>
        <tr>
          <th scope="col">{left.name}</th>
          <th scope="col">&nbsp;</th>
          <th scope="col">{right.name}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.label}>
            <td className={`num${ahead(row, "left")}`}>{row.left}</td>
            <th scope="row">{row.label}</th>
            <td className={`num${ahead(row, "right")}`}>{row.right}</td>
          </tr>
        ))}
      </tbody>
    </table>
    </div>
  );
}

/// The awards: who had the game, and who made a contest of it.
///
/// Nobody in cricket computes this — an adjudicator watches and picks. So the
/// app names the top of the ranking and says plainly that it worked it out,
/// rather than leaving the headline award blank until somebody remembers to
/// tap it. The scorer's pick, when they make one, replaces it.
function Awards({
  st,
  awards,
  fighter,
  send,
  canAct,
  nameOf,
}: {
  st: MatchState;
  awards: PlayerImpact[];
  fighter?: PlayerImpact | null;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  nameOf: (id?: string | null) => string;
}) {
  const t = useT();
  const [picking, setPicking] = useState(false);
  const given = st.player_of_the_match
    ? awards.find((p) => p.player_id === st.player_of_the_match)
    : undefined;
  const potmName = st.player_of_the_match ? nameOf(st.player_of_the_match) : awards[0]?.name;
  const potmLine = given?.line ?? (st.player_of_the_match ? undefined : awards[0]?.line);
  const awarded = !!st.player_of_the_match;
  // The rest of the ranking, minus whoever already has a card above.
  const named = new Set([st.player_of_the_match ?? awards[0]?.player_id, fighter?.player_id]);
  const rest = awards.filter((p) => !named.has(p.player_id)).slice(0, 5);

  if (!potmName && !fighter) return null;

  return (
    <div>
      {potmName && (
        <div className="award-card">
          <span className="what">{t("sc.player_of_the_match")}</span>
          <div className="who">{potmName}</div>
          {potmLine && <div className="figures">{potmLine}</div>}
          {!awarded && (
            <p className="basis">
              {t("sc.worked_out_from_the_card_runs_and_wick")}
            </p>
          )}
          {canAct && (
            <button
              type="button"
              className="btn sm"
              onClick={() => setPicking((v) => !v)}
            >
              {picking ? "Close" : awarded ? t("la.change_the_award") : t("la.give_the_award")}
            </button>
          )}
          {canAct && picking && (
            <div className="chips" style={{ marginTop: "var(--s3)" }}>
              {awards.map((p) => (
                <button
                  key={p.player_id}
                  type="button"
                  className={`chip${p.player_id === st.player_of_the_match ? " on" : ""}`}
                  onClick={async () => {
                    setPicking(false);
                    await send({ type: "player_of_the_match", player_id: p.player_id });
                  }}
                >
                  {p.name} <span className="subtle num">{p.line}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {fighter && (
        <div className="award-card fight">
          <span className="what">{t("sc.fighter_of_the_match")}</span>
          <div className="who">{fighter.name}</div>
          <div className="figures">{fighter.line}</div>
          <p className="basis">{t("sc.the_best_game_in_the_losing_side")}</p>
        </div>
      )}

      {rest.length > 0 && (
        <details className="fold">
          <summary>{t("sc.who_else_had_a_game")}</summary>
          <ol className="had-the-game">
            {rest.map((p) => (
              <li key={p.player_id}>
                <span className="nm">{p.name}</span>
                <span className="fg">{p.line}</span>
              </li>
            ))}
          </ol>
        </details>
      )}
    </div>
  );
}

/// Which panel the scorer needs is decided by the state, not by a wizard step
/// the browser remembers — reopening the page mid-match lands in the right place.
function Stages({
  match,
  send,
  scoring,
  canAct,
  synced,
  nameOf,
  onPicked,
  onHandOver,
}: {
  match: MatchResponse;
  send: (kind: Record<string, unknown>) => Promise<void>;
  /// This is the scorer's screen: decides which panels show.
  scoring: boolean;
  /// …and it can take a tap right now: decides what is enabled.
  canAct: boolean;
  /// Nothing is waiting to go up: every ball on this screen is also on the
  /// server.
  synced: boolean;
  nameOf: (id?: string | null) => string;
  onPicked: (next: MatchResponse) => void;
  onHandOver: () => void;
}) {
  const t = useT();
  const st = match.state;
  const agreed = !!st.agreed_home && !!st.agreed_away;
  const current = st.innings[st.innings.length - 1];
  const needsInnings = !current || current.complete;

  // At the break the book usually crosses to the side about to bat: they are
  // the ones who know their own order, and whoever just scored ten overs of
  // someone else's innings has done their stint. Offered only when it would
  // actually help — not to somebody already on that side, and not when that
  // side isn't a club on Fishers, where nobody has an account to hand it to.
  const battingNext = current ? other(current.batting as Side) : null;
  const crossesTheFence =
    !!battingNext &&
    match.my_club_side !== battingNext &&
    (battingNext === "home" || !!match.opponent_club_id);

  if (st.status === "complete") {
    // The Laws, and `MatchState::needs_a_super_over` on the server: the scores
    // are level, nobody has won, and every innings bowled so far has a reply.
    const needsSuperOver =
      !st.winner &&
      !st.abandoned &&
      st.innings.length >= 2 &&
      st.innings.length % 2 === 0;

    // One card carries the result: the winners' last innings. Marking every
    // innings they batted lit three of four cards in a super over and read
    // like a bug.
    const decidedBy = st.winner
      ? st.innings.reduce((best, i, n) => (i.batting === st.winner ? n : best), -1)
      : -1;

    return (
      <>
        <div className="panel result-panel">
          <span className="tag gold">{t("sc.result")}</span>
          <h2 className="result-line">{st.margin || t("la.match_complete")}</h2>

          {/* Each innings its own card: a super over is a separate passage of
              play, not two more numbers on the end of a row. */}
          <div className="innings-strip">
            {st.innings.map((i, n) => (
              <div key={n} className={`innings-card${n === decidedBy ? " won" : ""}`}>
                <div className="side">{i.batting === "home" ? st.home_name : st.away_name}</div>
                <div className="score">
                  {inningsScore(i)}
                  {n === decidedBy && <span className="won-mark">{t("sc.won")}</span>}
                </div>
                <div className="when">{overs(i.legal_balls)} ov</div>
                {i.super_over && <span className="super">{t("sc.super_over")}</span>}
              </div>
            ))}
          </div>

          {!needsSuperOver && (
            <div className="result-grid">
              <Awards
                st={st}
                awards={match.awards ?? []}
                fighter={match.fighter}
                send={send}
                canAct={canAct}
                nameOf={nameOf}
              />
              {match.insights && (
                <details className="fold" open>
                  <summary>{t("sc.how_the_game_went")}</summary>
                  <Comparison
                    insights={match.insights}
                    battedFirst={(st.innings[0]?.batting as Side) ?? "home"}
                  />
                </details>
              )}
            </div>
          )}
        </div>

        {needsSuperOver &&
          (scoring ? (
            <OpenersPanel st={st} send={send} canAct={canAct} nameOf={nameOf} superOver />
          ) : (
            <ScorersTurn
              title={t("sc.scores_level")}
              note={t("la.it_needs_a_super_over_whoever_is_scori")}
            />
          ))}

        {/* Not while a super over is still to come: the afternoon is not over,
            and the umpires have the hardest six balls of it left. */}
        {!needsSuperOver && <RateUmpires matchId={match.id} />}
      </>
    );
  }
  if (!agreed)
    return (
      <ConditionsPanel
        st={st}
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
    return scoring ? (
      <TossPanel st={st} send={send} canAct={canAct} />
    ) : (
      <ScorersTurn
        title={t("sc.waiting_on_the_toss")}
        note={t("la.whoever_is_scoring_records_the_toss_th")}
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
  if (needsInnings) {
    if (scoring)
      return (
        <OpenersPanel
          st={st}
          send={send}
          canAct={canAct}
          nameOf={nameOf}
          onHandOver={crossesTheFence ? onHandOver : undefined}
        />
      );
    // "Waiting for the first ball" is true before the match and nonsense at an
    // innings break, where the person reading it has just watched ten overs.
    return current ? (
      <ScorersTurn
        title={t("sc.innings_break")}
        note={t("la.innings_break_note", {
          side: battingNext === "home" ? st.home_name : st.away_name,
          chase: st.target ? t("la.chasing_target", { target: st.target }) : "",
        })}
      />
    ) : (
      <ScorersTurn
        title={t("sc.waiting_for_the_first_ball")}
        note={t("la.the_scorer_names_the_openers_and_the_b")}
      />
    );
  }
  return (
    <LivePanel match={match} send={send} scoring={scoring} canAct={canAct} synced={synced} nameOf={nameOf} />
  );
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
  canAct,
  matchId,
  mySides,
  myClubSide,
  theirClub,
  onAgreed,
}: {
  st: MatchState;
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
  const t = useT();
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
      setError(readErr(err, t("la.could_not_propose_those_terms")));
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
        <h2>{t("sc.agree_the_terms")}</h2>
        <p className="muted">
          {t("sc.set_how_the_game_is_being_played_then")}
        </p>
      </div>

      <fieldset className="setup-group">
        <legend>{t("sc.format")}</legend>
        <div className="setup-fields">
          <label>
            {t("sc.innings_each")}
            <select
              value={c.innings_per_side ?? 1}
              onChange={(e) => {
                const per = Number(e.target.value);
                // A declaration game is played to a clock and has no
                // powerplay, so switching to it clears what stops meaning
                // anything rather than leaving it to be argued about later.
                setC(
                  per >= 2
                    ? { ...c, innings_per_side: per, powerplay_overs: 0, overs_per_bowler: 0 }
                    : { ...c, innings_per_side: per }
                );
              }}
            >
              <option value={1}>{t("sc.one_limited_overs")}</option>
              <option value={2}>{t("sc.two_declaration_game")}</option>
            </select>
            <span className="subtle">
              {(c.innings_per_side ?? 1) >= 2
                ? t("la.won_on_aggregate_and_it_can_be_drawn")
                : t("la.the_usual_one_innings_a_side_most_runs")}
            </span>
          </label>
          <label>
            {t("sc.overs")} <input {...num("overs_limit")} />
            {(c.innings_per_side ?? 1) >= 2 && (
              <span className="subtle">{t("la.zero_for_no_limit_clock")}</span>
            )}
          </label>
          <label>
            {t("sc.ball")}
            <select value={c.ball} onChange={(e) => setC({ ...c, ball: e.target.value })}>
              {BALLS.map((b) => <option key={b} value={b}>{t(`ball_type.${b}` as Key)}</option>)}
            </select>
          </label>
          <label>
            {t("sc.ground")}
            <select value={c.ground} onChange={(e) => setC({ ...c, ground: e.target.value })}>
              {GROUNDS.map((g) => <option key={g} value={g}>{t(`ground_type.${g}` as Key)}</option>)}
            </select>
          </label>
        </div>
      </fieldset>

      <fieldset className="setup-group">
        <legend>{t("sc.bowling_and_fielding")}</legend>
        <div className="setup-fields">
          <label>
            {t("sc.overs_per_bowler")}
            <input {...num("overs_per_bowler")} />
            <span className="subtle">{t("la.zero_for_no_limit")}</span>
          </label>
          <label>{t("sc.powerplay_overs")} <input {...num("powerplay_overs")} /></label>
          <label>
            {t("sc.fielders_out_powerplay")}
            <input {...num("fielders_outside_powerplay")} />
          </label>
          <label>
            {t("sc.fielders_out_after")}
            <input {...num("fielders_outside_normal")} />
          </label>
          <label>
            {t("sc.overs_per_hour")}
            <input {...num("target_overs_per_hour")} />
            <span className="subtle">{t("la.zero_to_not_count_it")}</span>
          </label>
        </div>
      </fieldset>

      <fieldset className="setup-group">
        <legend>{t("sc.your_captain")}</legend>
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
                  {side === "home" ? "Home" : t("la.away")}
                </span>
              </button>
            ))}
          </div>
        )}
        <p className="muted">
          {t("sc.proposing_on_behalf_of")} <strong>{by === "home" ? st.home_name : st.away_name}</strong>.{" "}
          {t("la.side_will_be_asked", { side: other(by) === "home" ? st.home_name : st.away_name })}
        </p>
        <PersonPicker
          label={t("la.captain_of", { name: by === "home" ? st.home_name : st.away_name })}
          people={squad.people(by)}
          value={name}
          onChange={setName}
          loading={squad.loading}
          emptyHint={t("la.nobody_on_brand_for_side", { brand: brand.name })}
        />
      </fieldset>

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !name.trim()}
        onClick={propose}
      >
        {busy ? t("la.proposing") : t("la.propose_these_terms")}
      </button>
      {onCancel && (
        <button className="btn" type="button" onClick={onCancel} style={{ width: "100%" }}>
          {t("sc.keep_the_terms_as_they_were")}
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
  const t = useT();
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
      setError(readErr(err, t("la.could_not_record_that_agreement")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>
          {isMine && canAgree
            ? t("la.do_you_accept_these_terms")
            : recording
              ? t("la.do_you_agree", { name: pendingName })
              : t("la.waiting_on", { name: pendingName })}
        </h2>
        <p className="muted">
          {isMine && canAgree
            ? t("la.proposed_check_it_over", { proposer })
            : recording
              ? t("la.record_captain_agreeing", { name: pendingName })
              : t("la.proposed_terms_pending", { proposer, name: pendingName })}
        </p>
      </div>

      <dl className="terms-summary">
        <div>
          <dt>{t("sc.overs")}</dt>
          <dd className="num">{c.overs_limit || t("la.no_limit")}</dd>
        </div>
        {(c.innings_per_side ?? 1) >= 2 && (
          <div>
            <dt>{t("sc.innings_each")}</dt>
            <dd className="num">2</dd>
          </div>
        )}
        <div><dt>{t("sc.ball")}</dt><dd>{t(`ball_type.${c.ball}` as Key)}</dd></div>
        <div><dt>{t("sc.ground")}</dt><dd>{t(`ground_type.${c.ground}` as Key)}</dd></div>
        <div>
          <dt>{t("sc.overs_per_bowler")}</dt>
          <dd className="num">{c.overs_per_bowler || t("la.no_limit")}</dd>
        </div>
        <div><dt>{t("sc.powerplay")}</dt><dd className="num">{c.powerplay_overs} overs</dd></div>
        <div>
          <dt>{t("sc.fielders_out")}</dt>
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
                {who ? <><Icon name="check" size={14} /> {who}</> : t("la.not_yet")}
              </div>
            </div>
          );
        })}
      </div>

      {canAgree && (!theirsToAnswer || recording) ? (
        <>
          <fieldset className="setup-group">
            <legend>{isMine ? t("la.accepted_by") : t("la.side_agrees", { name: pendingName })}</legend>
            <PersonPicker
              label={isMine ? t("la.your_captain_s_name") : t("la.captain_of", { name: pendingName })}
              people={squad.people(pending)}
              value={name}
              onChange={setName}
              loading={squad.loading}
              emptyHint={t("la.type_their_captain_s_name")}
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
              ? t("la.saving")
              : isMine
                ? t("la.accept_named", { name: name.trim() || t("la.name_your_captain") })
                : name.trim()
                  ? t("la.side_agrees", { name: name.trim() })
                  : t("la.agree_the_terms")}
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
              {t("sc.their_captain_is_here_record_it")}
            </button>
          )}
        </>
      )}

      {canAct && (
        <>
          <button className="btn" type="button" onClick={onChange} style={{ width: "100%" }}>
            {t("sc.change_the_terms")}
          </button>
          <p className="subtle">{t("sc.changing_anything_asks_both_captains_a")}</p>
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
  const t = useT();
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
        note: p.standing === "member" ? undefined : t(STANDING_LABEL[p.standing]),
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
  const t = useT();
  const [winner, setWinner] = useState<Side | null>(null);
  const [decision, setDecision] = useState<"bat" | "bowl" | null>(null);

  return (
    <div className="panel setup-panel">
      <div className="setup-head">
        <h2>{t("sc.the_toss")}</h2>
        <p className="muted">{t("sc.who_called_it_and_what_they_did_with_i")}</p>
      </div>

      <fieldset className="setup-group">
        <legend>{t("sc.won_the_toss")}</legend>
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
              <span className="side-card-role">{side === "home" ? t("la.home") : t("la.away")}</span>
            </button>
          ))}
        </div>
      </fieldset>

      <fieldset className="setup-group" disabled={!winner}>
        <legend>{t("sc.and_chose_to")}</legend>
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
              <span className="side-card-name">{d === "bat" ? t("la.bat") : t("la.bowl")}</span>
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
          ? t("la.chose_to_label", {
              side: winner === "home" ? st.home_name : st.away_name,
              decision: decision === "bat" ? t("la.bat_lower") : t("la.bowl_lower"),
            })
          : t("la.record_the_toss")}
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
  const t = useT();
  const [squad, setSquad] = useState<SquadResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setSquad(await api<SquadResponse>("GET", `/cricket/matches/${matchId}/squad`));
    } catch (err) {
      setError(readErr(err, t("la.could_not_load_the_squads")));
    }
  }, [matchId, t]);

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
        <h2>{mine ? t("la.pick_your_side") : t("la.team_sheets")}</h2>
        <p className="muted">
          {mine
            ? t("la.name_the_eleven_who_turned_up_the_matc")
            : t("la.each_captain_names_their_own_side_the")}
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
  const t = useT();
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
  // The club's captain is marked for them as they are picked. Once somebody
  // taps C themselves, the sheet stops choosing.
  const [captainChosen, setCaptainChosen] = useState(false);
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

  const captainsSide = (id: string) => !!side.players.find((p) => p.id === id)?.is_captain;

  const toggle = (id: string) => {
    const adding = !chosen.includes(id);
    setChosen((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
    if (adding && !captain && !captainChosen && captainsSide(id)) setCaptain(id);
  };

  const drop = (id: string) => {
    setChosen((prev) => prev.filter((x) => x !== id));
    setExtras((prev) => prev.filter((x) => x.id !== id));
    if (captain === id) {
      // Their captain dropped out: another of the club's captains takes over,
      // unless the captaincy was already the scorer's call.
      const next = captainChosen ? undefined : picked.find((p) => p.id !== id && captainsSide(p.id));
      setCaptain(next?.id ?? "");
    }
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
        setError(JSON.parse(raw).error ?? t("la.could_not_save_the_sheet"));
      } catch {
        setError(raw || t("la.could_not_save_the_sheet"));
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
          <span className="tag"><Icon name="check" size={12} /> {t("sc.named")}</span>
        </div>
        <ol className="named-xi">
          {already.map((id) => (
            <li key={id}>
              {st.player_names[id] || "…"}
              {id === (side.side === "home" ? st.home_captain : st.away_captain) && (
                <span className="role-badge c">C</span>
              )}
              {id === (side.side === "home" ? st.home_keeper : st.away_keeper) && (
                <span className="role-badge wk">{t("sc.wk")}</span>
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
          <span className="tag grey">{t("sc.waiting")}</span>
        </div>
        <div className="waiting-note">
          <Icon name="clock" size={18} />
          <span>
            {t("sc.their_captain_names_this_side_from_the")}
          </span>
        </div>
        {side.can_pick && (
          <button
            className="btn ghost sm"
            type="button"
            style={{ marginTop: "var(--s3)" }}
            onClick={() => setNamingForThem(true)}
          >
            {t("sc.name_them_myself")}
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
              {t("sc.leave_it_to_them")}
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
                title={t("sc.captain")}
                onClick={() => {
                  setCaptainChosen(true);
                  setCaptain(captain === p.id ? "" : p.id);
                }}
              >
                C
              </button>
              <button
                type="button"
                className={`role-toggle${keeper === p.id ? " on" : ""}`}
                aria-pressed={keeper === p.id}
                title={t("sc.wicketkeeper")}
                onClick={() => setKeeper(keeper === p.id ? "" : p.id)}
              >
                {t("sc.wk")}
              </button>
              <button
                type="button"
                className="pick-remove"
                aria-label={t("la.take_player_out", { name: p.name })}
                onClick={() => drop(p.id)}
              >
                ×
              </button>
            </li>
          ))}
        </ol>
      ) : (
        <p className="muted">{t("sc.tap_the_players_who_turned_up_they_go")}</p>
      )}

      {captain && !captainChosen && (
        <p className="captain-note">
          <span className="role-badge c">C</span>
          <span>
            {picked.find((p) => p.id === captain)?.name} captains {side.team_name}, so they are
            marked captain. Tap C beside someone else to change it.
          </span>
        </p>
      )}

      {available.length > 0 && (
        <>
          <h3 className="sheet-sub">{t("sc.squad")}</h3>
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
                {p.is_captain && (
                  <span className="role-badge c" title={t("sc.captain")}>C<span className="sr-only">{t("sc.captain_sr")}</span></span>
                )}
                {p.standing !== "member" && (
                  <span className={`tag ${p.standing === "selected" ? "gold" : "grey"}`}>
                    {STANDING_LABEL[p.standing] ? t(STANDING_LABEL[p.standing]) : p.standing}
                  </span>
                )}
              </button>
            ))}
          </div>
        </>
      )}

      {side.players.length === 0 && (
        <p className="muted">
          Not a {brand.name} club, so there is no squad to pick from. Add whoever turned up.
        </p>
      )}

      {addingGuest ? (
        <div className="field-row guest-row">
          <label>
            {t("sc.their_name")}
            <input
              value={newName}
              autoFocus
              onChange={(e) => setNewName(e.target.value)}
              placeholder={t("sc.whoever_turned_up")}
              onKeyDown={(e) => {
                if (e.key === t("la.enter") && newName.trim()) {
                  e.preventDefault();
                  addGuest();
                }
              }}
            />
          </label>
          <label className="checkbox">
            <input type="checkbox" checked={newLeft} onChange={(e) => setNewLeft(e.target.checked)} />
            {t("sc.left_handed")}
          </label>
          <button className="btn" type="button" disabled={!newName.trim()} onClick={addGuest}>
            {t("sc.add")}
          </button>
          <button className="btn ghost" type="button" onClick={() => setAddingGuest(false)}>
            {t("sc.cancel")}
          </button>
        </div>
      ) : (
        <button className="btn ghost sm add-guest" type="button" onClick={() => setAddingGuest(true)}>
          <Icon name="plus" size={14} /> {t("sc.someone_not_in_the_squad")}
        </button>
      )}

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || picked.length < 2}
        onClick={submit}
      >
        {busy ? t("la.saving") : `Confirm ${side.team_name}`}
      </button>
      {/* Say what is missing rather than leaving a dead button. */}
      <p className="subtle">
        {picked.length < 2
          ? t("la.pick_at_least_two_players")
          : short > 0
            ? t("la.short_of_full_xi", { n: short })
            : t("la.a_full_xi_confirm_when_you_are_happy")}
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
  onHandOver,
  superOver = false,
}: {
  st: MatchState;
  send: (kind: Record<string, unknown>) => Promise<void>;
  canAct: boolean;
  nameOf: (id?: string | null) => string;
  /// Offered at an innings break, when the side about to bat is somebody else's
  /// — `Stages` decides whether that is worth saying here.
  onHandOver?: () => void;
  /// One over a side to break a tie. Same three choices, different rules —
  /// so this is the same panel rather than a second one to keep in step.
  superOver?: boolean;
}) {
  const t = useT();
  const index = st.innings.length;
  const last = st.innings[index - 1];
  // The reply to a super over arrives here too, at an ordinary innings break.
  // Treating it as a normal innings is what handed it the full match
  // allocation and let the same side bat again.
  const replying = !!last?.super_over;
  const isSuperOver = superOver || replying;

  // Whoever won the toss and chose to bat opens; the sides swap after that.
  const first: Side =
    st.toss_decision === "bat"
      ? (st.toss_winner as Side)
      : other(st.toss_winner as Side);
  // A super over does not follow that alternation. The side that batted second
  // in the match opens it — so the same side bats twice running across the
  // join — and the other side replies.
  const batting: Side = isSuperOver
    ? replying
      ? other(last.batting as Side)
      : (last?.batting as Side)
    : index % 2 === 0
      ? first
      : other(first);
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
        <h2>
          {isSuperOver
            ? replying
              ? t("la.super_over_the_reply")
              : t("la.super_over")
            : index === 0
              ? t("la.who_is_opening")
              : `Innings ${index + 1}`}
        </h2>
        <p className="muted">
          {t("sc.batting_vs_fielding", { batting: battingName, bowling: bowlingName })}
          {/* A super over reply is a chase like any other — the engine sets
              the target from the over just bowled. */}
          {st.target ? ` · ${t("sc.chasing", { target: st.target })}` : ""}.
        </p>
        {isSuperOver && (
          <p className="muted">
            {replying
              ? t("la.one_over_two_wickets_down_and_it_is_ov")
              : t("la.scores_are_level_one_over_each_two_wic")}
          </p>
        )}
      </div>

      {/* The first decision of the break, above the crease rather than under
          the button that ends it: naming the openers of a side you do not know
          is the wrong job, and this is the moment to pass it on. */}
      {onHandOver && (
        <div className="hand-over-break">
          <p className="muted">
            {t("sc.the_side_batting_normally_keeps_their")}
          </p>
          <button className="btn ghost sm" type="button" onClick={onHandOver}>
            <Icon name="book" size={14} /> {t("la.hand_the_book_to", { name: battingName })}
          </button>
        </div>
      )}

      <div className="crease">
        <div className="crease-end">
          <span className="crease-role on-strike">{t("sc.on_strike")}</span>
          <PlayerPicker
            label={t("sc.striker")}
            hint={t("la.faces_the_first_ball")}
            players={listFor(battingXi, nonStriker ? { [nonStriker]: t("la.at_the_other_end") } : {})}
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
            aria-label={t("sc.swap_the_batters_over")}
            title={t("sc.swap_ends")}
          >
            ⇄
          </button>
          <span className="crease-label">22 yards</span>
        </div>

        <div className="crease-end">
          <span className="crease-role">{t("sc.other_end")}</span>
          <PlayerPicker
            label={t("sc.non_striker")}
            hint={t("la.backing_up")}
            players={listFor(battingXi, striker ? { [striker]: t("sc.on_strike_lower") } : {})}
            value={nonStriker}
            onChange={setNonStriker}
          />
        </div>
      </div>

      <div className="bowling-end">
        <PlayerPicker
          label={t("sc.opening_bowler")}
          hint={t("la.bowls_the_first_over", { name: bowlingName })}
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
              super_over: isSuperOver,
            });
          } finally {
            setBusy(false);
          }
        }}
      >
        {busy
          ? t("la.starting")
          : isSuperOver
            ? replying
              ? t("la.start_the_reply")
              : t("la.start_the_super_over")
            : t("la.start_the_innings")}
      </button>
      <p className="subtle">
        {!striker || !nonStriker
          ? t("la.name_both_batters")
          : striker === nonStriker
            ? t("la.the_same_player_cannot_be_at_both_ends")
            : !bowler
              ? t("la.name_the_bowler_taking_the_first_over")
              : t("la.bowler_to_striker_first_ball", { bowler: nameOf(bowler), striker: nameOf(striker) })}
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
  /// Law 18.4: runs they completed that the umpire called short. Not scored,
  /// but they were still run, so they decide which end everybody ends at.
  shortRuns?: number;
  step: "detail" | "shot" | "direction";
};

const ASK_KEY = "fishers_ask_shot";
/// Whether to ask a model for a line of colour after each ball. Per device,
/// like the shot question: a scorer on a phone tethered to a car park may want
/// it off, and the one beside them on the clubhouse wifi may not.
const AI_KEY = "fishers_ai_commentary";

function LivePanel({
  match,
  send,
  scoring,
  canAct,
  synced,
  nameOf,
}: {
  match: MatchResponse;
  send: (kind: Record<string, unknown>) => Promise<void>;
  scoring: boolean;
  canAct: boolean;
  /// Every ball on this screen has reached the server.
  synced: boolean;
  nameOf: (id?: string | null) => string;
}) {
  const { t, locale } = useLocale();
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
  /// Armed when the umpire signals one short, and spent on the next ball.
  const [oneShort, setOneShort] = useState(false);
  const [sheet, setSheet] = useState<null | "wicket" | "more">(null);
  const [askShot, setAskShot] = useState(true);
  /// Model-written lines, keyed by ball. The log-written line shows instantly
  /// and is replaced only if a better one arrives.
  const [aiLines, setAiLines] = useState<Record<string, string>>({});
  const [aiOn, setAiOn] = useState(true);
  /// Why there is no model-written line, when there is none. Silence was the
  /// whole problem: with the switch on and nothing appearing, there was no way
  /// to tell an unconfigured server from an unreachable one from a model that
  /// simply had nothing to add.
  const [aiStatus, setAiStatus] = useState<"idle" | "ok" | "no_model" | "unreachable">("idle");

  const ballCount = (inn.deliveries || []).length;
  /// The last ball a line was asked for, so a sync settling does not ask
  /// again for one already in flight or answered.
  const askedAbout = useRef<string | null>(null);
  useEffect(() => {
    if (!aiOn) return;
    const last = (inn.deliveries || [])[ballCount - 1];
    if (!last) return;
    // The engine here applies the ball before the batch carrying it goes up,
    // so for a moment this screen knows about a delivery the server does not.
    // Asking then is a 404 for a ball that exists in one browser — which is
    // what the scorer's console was full of. Wait for it to land; the effect
    // runs again when it does.
    if (!synced) return;
    const key = `${last.over}.${last.ball_in_over}.${last.label}`;
    if (askedAbout.current === key) return;
    askedAbout.current = key;
    // Fire and forget: a model takes seconds and the ball is already recorded,
    // so nothing waits on this and a failure leaves the written line in place.
    //
    // Cancelled, not just ignored, when the next ball arrives. A browser keeps
    // six connections to a host over plain http (a ground's LAN), the live
    // stream holds one, and lines still being written for old balls filled the
    // rest — so the next ball queued behind them and the scorer's taps stalled.
    const ctl = new AbortController();
    api<{ line: string | null; model: string | null }>(
      "POST",
      `/cricket/matches/${match.id}/commentary`,
      // The language goes with the request, not the response: the model writes
      // the line, so it has to know which language to write it in.
      { over: last.over, ball_in_over: last.ball_in_over, lang: locale },
      true,
      false,
      ctl.signal
    )
      .then((r) => {
        if (r.line) {
          setAiLines((prev) => ({ ...prev, [key]: r.line! }));
          setAiStatus("ok");
          return;
        }
        // The route answers with the model it would have used, so a server
        // with none configured is a different thing to say than one whose
        // model did not answer.
        setAiStatus(r.model ? "unreachable" : "no_model");
      })
      .catch(() => {
        // An abort is this effect cleaning up after itself, not a failure.
        if (!ctl.signal.aborted) setAiStatus("unreachable");
      });
    return () => ctl.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ballCount, match.id, locale, aiOn, synced]);

  useEffect(() => {
    setAskShot(localStorage.getItem(ASK_KEY) !== "0");
    setAiOn(localStorage.getItem(AI_KEY) !== "0");
  }, []);
  const toggleAsk = (on: boolean) => {
    setAskShot(on);
    localStorage.setItem(ASK_KEY, on ? "1" : "0");
  };
  const toggleAi = (on: boolean) => {
    setAiOn(on);
    localStorage.setItem(AI_KEY, on ? "1" : "0");
    if (!on) setAiStatus("idle");
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
          short_runs: d.shortRuns ?? 0,
          ...(shot ? { shot } : {}),
        };
    setDraft(null);
    await send(kind);
  };

  const startRuns = (runs: number) => {
    // The scorer taps what they ran. One short takes a run off the score but
    // not off the ground they covered, so the count and the ends part company
    // here and nowhere else.
    const d: Draft = oneShort
      ? { runs: Math.max(0, runs - 1), shortRuns: 1, step: "shot" }
      : { runs, step: "shot" };
    setOneShort(false);
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
      {/* Three blocks, deliberately siblings rather than two columns of
          stacked content: on a phone the dial has to come between the state
          of the match and the commentary, and it cannot do that from inside
          another element. Desktop puts state and commentary back in one
          column with CSS. */}
      <div className="score-state">
        {/* Read left to right the way the game is: the score, who is in, who
            is bowling at them. The three used to stack in a column and leave
            most of the panel empty beside them. */}
        <div className="ground">
          <span className="ground-pitch" aria-hidden="true" />
          <div className="ground-row">
            <div className="ground-score">
              <span className="scoreline">
                {inn.runs}/{inn.wickets}
              </span>
              <span className="ground-overs">
                {t("sc.overs_of", { balls: overs(inn.legal_balls), limit: oversAvailable })}
              </span>
              <div className="ground-rates">
                {t("sc.crr", { rate: crr === null ? "—" : crr.toFixed(2) })}
                {rrr !== null && t("sc.rrr", { rate: rrr.toFixed(2) })}
              </div>
            </div>

            <div className="ground-batters">
              <BatterCard id={inn.striker_id} nameOf={nameOf} b={batterOf(inn.striker_id)} onStrike />
              <BatterCard id={inn.non_striker_id} nameOf={nameOf} b={batterOf(inn.non_striker_id)} />
            </div>

            <div className="card bowler">
              <div className="who-name">{nameOf(inn.bowler_id)}</div>
              <div className="who-figs">
                {(() => {
                  const bowl = inn.bowlers.find((b) => b.player_id === inn.bowler_id);
                  return bowl ? `${bowl.wickets}-${bowl.runs}` : "—";
                })()}
              </div>
              <div className="who-sub">
                {t("sr.bowling")} ·{" "}
                {(() => {
                  const bowl = inn.bowlers.find((b) => b.player_id === inn.bowler_id);
                  return bowl
                    ? t("sc.overs_maidens", { overs: overs(bowl.balls), maidens: bowl.maidens })
                    : t("sc.first_over");
                })()}
              </div>
            </div>
          </div>

          {st.target != null && (
            <div className="ground-row ground-chase" style={{ marginTop: "var(--s3)" }}>
              <div />
              <div>
                <strong className="num">
                  {t("sc.n_needed", { n: Math.max(0, st.target - inn.runs) })}
                </strong>
                <div className="subtle">
                  {t("sc.from_n_balls", {
                    n: Math.max(0, oversAvailable * 6 - inn.legal_balls),
                  })}
                </div>
              </div>
              <div />
            </div>
          )}
        </div>

        <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap", marginBottom: "var(--s3)" }}>
          {inn.free_hit && <span className="tag gold">{t("sc.free_hit")}</span>}
          {inPowerplay && <span className="tag">{t("sc.powerplay")}</span>}
          {match.dls && (
            <span className="tag grey">
              DLS par {match.dls.par} · {match.dls.ahead_by >= 0 ? "+" : ""}
              {match.dls.ahead_by}
            </span>
          )}
        </div>

        {fieldBreach && (
          <p className="error">
            {/* `fieldBreach` is only true when both of these are set. */}
            {t("la.fielders_outside_circle", {
              out: inn.fielders_outside ?? 0,
              allowed: allowedOutside ?? 0,
            })}
          </p>
        )}


      </div>

      <div className="score-comm">
        {overGroups.length > 0 && (
          <div className="panel over-history">
            <h2>{t("sc.this_over_and_the_last")}</h2>
            <div className="overs-strip">
            {overGroups.map(([over, balls]) => {
              const legal = balls.filter((b) => b.is_legal).length;
              const total = balls.reduce((sum, b) => sum + b.runs, 0);
              return (
                <div className="over-row" key={over}>
                  <span className="over-label">{t("sc.over_n", { n: over + 1 })}</span>
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
          </div>
        )}

        <div className="panel">
          <div className="panel-head">
            <h2>{t("sc.commentary")}</h2>
            {/* Not only for whoever has the book: the request goes out for
                anybody watching this page, so anybody watching can stop it. */}
            <label className="checkbox" style={{ fontSize: "0.85rem" }}>
              <input type="checkbox" checked={aiOn} onChange={(e) => toggleAi(e.target.checked)} />
              {t("sc.ai_commentary")}
            </label>
          </div>
          {aiOn && aiStatus !== "idle" && aiStatus !== "ok" && (
            <p className="muted" style={{ fontSize: "0.85rem" }}>
              {t(aiStatus === "no_model" ? "sc.ai_no_model" : "sc.ai_unreachable")}
            </p>
          )}
          <ul className="comm-list">
            {commentaryRows.map((row) =>
              row.kind === "over" ? (
                <li className="over-summary" key={`o${row.over}`}>
                  <strong>{t("la.end_of_over_n", { n: row.over + 1 })}</strong>
                  <span className="muted">
                    {t("la.over_runs", { n: row.overRuns, count: row.overRuns })}
                    {row.overWickets > 0 &&
                      t("la.over_wickets", { n: row.overWickets, count: row.overWickets })}
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
                    {aiLines[row.key] || commentaryFor(row.ball, nameOf, st.left_handers || [], t)}
                    {aiLines[row.key] && (
                      <span className="tag grey" style={{ marginLeft: "var(--s2)" }}>{t("sc.ai_tag")}</span>
                    )}
                  </span>
                </li>
              )
            )}
            {(inn.deliveries || []).length === 0 && <li className="muted">{t("sc.no_balls_yet")}</li>}
          </ul>
        </div>
      </div>

      {/* ---- controls ----
           Only for whoever is actually scoring. Somebody following the match
           came to watch it, and a dial they cannot press is furniture — but
           the column should not just be left empty either. */}
      {!scoring && <Following st={st} inn={inn} nameOf={nameOf} />}
      {scoring && <div className="controls">
        {needsBowler && (
          <div className="panel" style={{ borderColor: "var(--accent)" }}>
            <div className="panel-head">
              <h2>{t("la.over_n_done_who_next", { n: currentOver })}</h2>
              <span className="tag gold">{t("la.n_off_it", { n: lastOverRuns })}</span>
            </div>
            <p className="muted">
              {t("la.bowled_it_nobody_two_in_a_row", { name: nameOf(inn.last_over_bowler) })}
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
                      title={spent ? t("la.has_bowled_their_limit", { name: nameOf(id), limit }) : undefined}
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
            <h2>{t("sc.runs")}</h2>
            <label className="checkbox" style={{ fontSize: "0.85rem" }}>
              <input type="checkbox" checked={askShot} onChange={(e) => toggleAsk(e.target.checked)} />
              {t("score.ask_shot")}
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
          <h2>{t("sc.extras_wickets_and_the_rest")}</h2>
          <div className="actions">
            {EXTRA_KINDS.map((k) => (
              <button key={k} className="btn" type="button" disabled={!canAct || needsBowler} onClick={() => startExtra(k)}>
                {t(`extra.${k}` as Key)}
              </button>
            ))}
            <button className="btn danger" type="button" disabled={!canAct || needsBowler} onClick={() => setSheet("wicket")}>
              {t("sc.wicket")}
            </button>
            <button
              className={oneShort ? "btn primary" : "btn ghost"}
              type="button"
              disabled={!canAct || needsBowler}
              aria-pressed={oneShort}
              title={t("sc.the_umpire_has_signalled_one_short_the")}
              onClick={() => setOneShort((on) => !on)}
            >
              {t("sc.one_short")}
            </button>
            <button className="btn ghost" type="button" disabled={!canAct} onClick={() => send({ type: "undo_last" })}>
              <Icon name="arrowLeft" size={16} /> {t("sc.undo")}
            </button>
            <button className="btn ghost" type="button" disabled={!canAct} onClick={() => setSheet("more")}>
              {t("sc.more")}
            </button>
          </div>
        </div>
      </div>}

      {/* ---- the guided ball flow ---- */}
      {draft && draft.step === "detail" && (
        <Sheet title={t(`extra.${draft.extra || "penalty"}` as Key)} step={1} of={2} onClose={() => setDraft(null)}>
          <p className="muted">
            {t("sc.how_many_on_top", { extra: t(`extra.${draft.extra || "penalty"}` as Key) })}
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
              {t("sc.came_off_the_bat")}
            </label>
          )}
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft(null)}>{t("sc.cancel")}</button>
            <button
              className="btn primary"
              type="button"
              onClick={() =>
                draft.offTheBat && askShot ? setDraft({ ...draft, step: "shot" }) : record(draft)
              }
            >
              {t("sc.record")}
            </button>
          </div>
        </Sheet>
      )}

      {draft && draft.step === "shot" && (
        <Sheet
          title={
            draft.runs === 0
              ? t("score.which_shot_dot")
              : t("score.which_shot", { runs: draft.runs })
          }
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
                {t(`shot.${sh.kind}` as Key)}
                <span className="hint">{t(`hint.${sh.kind}` as Key)}</span>
              </button>
            ))}
          </div>
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft(null)}>{t("sc.cancel")}</button>
            <button className="btn" type="button" onClick={() => record(draft)}>
              {t("sc.skip_just_the_runs")}
            </button>
          </div>
        </Sheet>
      )}

      {draft && draft.step === "direction" && (
        <Sheet
          wide
          title={t("sc.where_did_it_go")}
          step={draft.extra ? 3 : 2}
          of={draft.extra ? 3 : 2}
          onClose={() => setDraft(null)}
        >
          <p className="muted">
            {t("sc.tap_the_field_nearer_the_rope_means_it")}
          </p>
          {/* The field is the control here, so it gets the room. `.wheel-stage`
              caps it against the viewport height as well as the sheet's width,
              so the whole wheel is on screen without the sheet scrolling. */}
          <div className="wheel-stage">
            {/* Only the ball being scored: the innings so far would be noise
                when the question is where this one went. */}
            <WagonWheel
              deliveries={[]}
              batsLeft={batsLeft}
              size={520}
              likelyAngle={SHOT_SHAPES.find((sh) => sh.kind === draft.shotKind)?.angle ?? null}
              onPick={(angle, reach) =>
                record(draft, { angle, kind: draft.shotKind || "other", reach })
              }
            />
          </div>
          <div className="sheet-actions">
            <button className="btn ghost" type="button" onClick={() => setDraft({ ...draft, step: "shot" })}>
              {t("sc.back")}
            </button>
            <button
              className="btn"
              type="button"
              // Not `angle: 0`. Zero is straight down the ground, so skipping
              // used to record a cut, a sweep and a glance as all having gone
              // to long on — and the commentary then said so. The stroke's own
              // typical bearing is the honest default: it is where that shot
              // usually goes, which is the most the scorer has told us.
              onClick={() =>
                record(draft, {
                  angle: SHOT_SHAPES.find((sh) => sh.kind === draft.shotKind)?.angle ?? 0,
                  kind: draft.shotKind || "other",
                  reach: 0.5,
                })
              }
            >
              {t("sc.skip_direction")}
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
  const t = useT();
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
          <h2>{t("sc.the_chase")}</h2>
          <p className="chase-line">
            {/* One template rather than a sentence built around two numbers:
                English runs "12 to win from 8 balls", Punjabi puts the balls
                first. Split on the placeholders so each number keeps the
                emphasis it had, in whichever order the language wants them. */}
            {t("sc.chase_line")
              .split(/(\{runs\}|\{balls\})/)
              .map((part, i) =>
                part === "{runs}" ? (
                  <strong key={i} className="num">{Math.max(need, 0)}</strong>
                ) : part === "{balls}" ? (
                  <strong key={i} className="num">{Math.max(ballsLeft, 0)}</strong>
                ) : (
                  part
                )
              )}
          </p>
          <dl className="terms-summary">
            <div><dt>{t("sc.run_rate")}</dt><dd className="num">{rr.toFixed(2)}</dd></div>
            <div>
              <dt>{t("sc.required")}</dt>
              <dd className="num">{req != null ? req.toFixed(2) : "—"}</dd>
            </div>
          </dl>
        </div>
      )}

      <div className="panel">
        <h2>{t("sc.at_the_crease")}</h2>
        <dl className="terms-summary">
          <div>
            <dt>{t("sc.partnership")}</dt>
            <dd className="num">
              {inn.partnership_runs ?? 0}
              <span className="subtle"> ({inn.partnership_balls ?? 0})</span>
            </dd>
          </div>
          <div><dt>{t("sc.run_rate")}</dt><dd className="num">{rr.toFixed(2)}</dd></div>
          <div>
            <dt>{t("sc.overs")}</dt>
            <dd className="num">
              {overs(balls)}
              {(inn.overs_available ?? st.overs_limit) > 0 && (
                <span className="subtle"> of {inn.overs_available ?? st.overs_limit}</span>
              )}
            </dd>
          </div>
          <div><dt>{t("sc.extras")}</dt><dd className="num">{inn.extras ?? 0}</dd></div>
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
          <h2>{t("sc.leading_the_attack")}</h2>
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
          <h2>{t("sc.next_in")}</h2>
          <ol className="named-xi">
            {toBat.slice(0, 3).map((id) => <li key={id}>{nameOf(id)}</li>)}
          </ol>
          {toBat.length > 3 && (
            <p className="subtle">{t("la.and_n_more_on_scorecard", { n: toBat.length - 3 })}</p>
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
  const t = useT();
  const sr = b && b.balls ? ((b.runs / b.balls) * 100).toFixed(0) : null;
  return (
    <div className={`card${onStrike ? " on-strike" : ""}`}>
      <div className="who-name">
        <span className="who-name-text">{nameOf(id)}</span>
        {onStrike && (
          <span className="on-strike-mark" title={t("sc.on_strike_lower")} aria-label={t("sc.on_strike_lower")}>
            <Icon name="bat" size={14} />
          </span>
        )}
      </div>
      <div className="who-figs">
        {b ? b.runs : 0}
        <span className="subtle" style={{ fontSize: "0.9rem" }}> ({b ? b.balls : 0})</span>
      </div>
      <div className="who-sub">
        {b ? t("la.boundaries_count", { fours: b.fours, sixes: b.sixes }) : t("la.yet_to_face")}
        {sr && t("la.sr_suffix", { sr })}
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
  const t = useT();
  const [kind, setKind] = useState<string>("bowled");
  const [batter, setBatter] = useState(striker);
  const [fielder, setFielder] = useState("");
  const [newBatter, setNewBatter] = useState(available[0] ?? "");
  const [runsBefore, setRunsBefore] = useState(0);
  const [onExtra, setOnExtra] = useState(false);

  return (
    <Sheet title={t("sc.wicket")} onClose={onClose}>
      <div className="actions" style={{ marginBottom: "var(--s3)" }}>
        {DISMISSALS.map((d) => (
          <button
            key={d}
            className={kind === d ? "btn primary" : "btn"}
            type="button"
            onClick={() => setKind(d)}
          >
            {/* The dictionary holds the scorebook's lowercase forms, because
                that is how a scorecard reads: "lbw b Jones", "run out
                (Smith)". A row of buttons is not a scorecard, and this row
                read "bowled / caught / lbw" until it got its capital back.
                A no-op in Gurmukhi, which has no case. */}
            {titleCase(t(`out.${d}` as Key))}
          </button>
        ))}
      </div>
      <div className="form">
        <label>
          {t("sc.who_is_out")}
          <select value={batter} onChange={(e) => setBatter(e.target.value)}>
            <option value={striker}>{t("la.name_striker", { name: nameOf(striker) })}</option>
            <option value={nonStriker}>{t("la.name_non_striker", { name: nameOf(nonStriker) })}</option>
          </select>
        </label>
        {DISMISSALS_WITH_FIELDER.includes(kind) && (
          <label>
            {t("sc.fielder")}
            <select value={fielder} onChange={(e) => setFielder(e.target.value)}>
              <option value="">—</option>
              {bowlingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
            </select>
          </label>
        )}
        <label>
          {t("sc.next_in")}
          <select value={newBatter} onChange={(e) => setNewBatter(e.target.value)}>
            <option value="">{t("la.innings_ends_dash")}</option>
            {available.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
        <label>
          {t("sc.runs_completed_first")}
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
        {t("sc.on_a_ball_already_recorded_as_an_extra")}
      </label>
      <div className="sheet-actions">
        <button className="btn ghost" type="button" onClick={onClose}>{t("sc.cancel")}</button>
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
          {t("sc.record_wicket")}
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
  const t = useT();
  const [outside, setOutside] = useState(inn.fielders_outside ?? 0);
  const [penalty, setPenalty] = useState(5);
  const [reason, setReason] = useState(t("la.slow_over_rate"));
  const [side, setSide] = useState<Side>("home");
  const [overs, setOvers] = useState(inn.overs_available ?? st.overs_limit);
  const [subName, setSubName] = useState("");
  const [subFor, setSubFor] = useState("");
  const [suspend, setSuspend] = useState("");
  const [suspendWhy, setSuspendWhy] = useState(t("la.second_beamer"));
  const suspended = inn.suspended_bowlers ?? [];
  // A declaration game ends in ways a limited-overs one cannot, so those
  // buttons only appear where they mean something.
  const twoInnings = (st.conditions?.innings_per_side ?? 1) >= 2;
  const [resuming, setResuming] = useState("");
  const [resumeFor, setResumeFor] = useState("");

  // The overs cannot be cut below what has already been bowled, and the engine
  // says so — but a spinner that will not go there at all is kinder.
  const oversBowled = Math.ceil(inn.legal_balls / 6);
  // Retired hurt and still not out: they are entitled to come back.
  const canResume = inn.batters.filter((b) => b.retired_hurt && !b.out);
  // With both ends occupied the scorer has to say who is making way.
  const endIsFree = !inn.striker_id || !inn.non_striker_id;
  const atCrease = [inn.striker_id, inn.non_striker_id].filter(Boolean) as string[];

  return (
    <Sheet title={t("sc.bowling_field_and_the_rest")} onClose={onClose}>
      <div className="form">
        <label>
          {t("sc.bowler")}
          <select
            value={inn.bowler_id ?? ""}
            onChange={(e) => send({ type: "bowler_changed", bowler_id: e.target.value })}
          >
            <option value="">{t("sc.nobody_yet")}</option>
            {bowlingXi
              .filter((id) => !suspended.includes(id))
              .map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
          {suspended.length > 0 && (
            <span className="subtle">
              Off for the innings: {suspended.map(nameOf).join(", ")}.
            </span>
          )}
        </label>
        <label>
          {t("sc.fielders_outside_the_circle")}
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

      <h3 style={{ marginTop: "var(--s4)" }}>{t("sc.overs_in_this_innings")}</h3>
      <p className="muted">
        Rain, bad light, a late start. Cutting the overs here is what moves the
        Duckworth&ndash;Lewis&ndash;Stern par score, so do it before the players
        are back on.
      </p>
      <div className="form">
        <label>
          {t("sc.overs")}
          <input
            type="number"
            min={Math.max(1, oversBowled)}
            max={99}
            value={overs}
            onChange={(e) => setOvers(Number(e.target.value))}
          />
          <span className="subtle">
            {oversBowled > 0
              ? t("la.already_bowled_floor", { n: oversBowled })
              : t("la.none_bowled_yet")}
          </span>
        </label>
      </div>
      <div className="sheet-actions">
        <button
          className="btn"
          type="button"
          disabled={overs === (inn.overs_available ?? st.overs_limit) || overs < oversBowled}
          onClick={async () => {
            onClose();
            await send({ type: "overs_revised", innings_index: inn.index, overs });
          }}
        >
          {t("sc.cut_the_overs")}
        </button>
      </div>

      {canResume.length > 0 && (
        <>
          <h3 style={{ marginTop: "var(--s4)" }}>{t("sc.back_from_retired_hurt")}</h3>
          <div className="form">
            <label>
              {t("sc.who_is_coming_back")}
              <select value={resuming} onChange={(e) => setResuming(e.target.value)}>
                <option value="">{t("sc.nobody")}</option>
                {canResume.map((b) => (
                  <option key={b.player_id} value={b.player_id}>
                    {nameOf(b.player_id)} ({b.runs} off {b.balls})
                  </option>
                ))}
              </select>
            </label>
            {!endIsFree && (
              <label>
                {t("sc.coming_in_for")}
                <select value={resumeFor} onChange={(e) => setResumeFor(e.target.value)}>
                  <option value="">{t("sc.say_who")}</option>
                  {atCrease.map((id) => (
                    <option key={id} value={id}>{nameOf(id)}</option>
                  ))}
                </select>
                <span className="subtle">
                  {t("sc.both_ends_are_occupied_so_somebody_has")}
                </span>
              </label>
            )}
          </div>
          <div className="sheet-actions">
            <button
              className="btn"
              type="button"
              disabled={!resuming || (!endIsFree && !resumeFor)}
              onClick={async () => {
                onClose();
                await send({
                  type: "batter_resumed",
                  batter_id: resuming,
                  replacing_id: resumeFor || null,
                });
              }}
            >
              {t("sc.back_in")}
            </button>
          </div>
        </>
      )}

      <h3 style={{ marginTop: "var(--s4)" }}>{t("sc.substitute_fielder")}</h3>
      <p className="muted">
        Law 24: somebody fielding for a player who is off. A sub may field and
        catch, but not bat or bowl, so they join no team sheet — naming them
        here is what lets a catch be credited, and the card reads
        &ldquo;c sub (name)&rdquo;.
      </p>
      <div className="form">
        <label>
          {t("sc.their_name")}
          <input
            value={subName}
            onChange={(e) => setSubName(e.target.value)}
            placeholder={t("sc.a_patel")}
            maxLength={80}
          />
        </label>
        <label>
          {t("sc.on_for")}
          <select value={subFor} onChange={(e) => setSubFor(e.target.value)}>
            <option value="">{t("sc.not_saying")}</option>
            {bowlingXi.map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
      </div>
      <div className="sheet-actions">
        <button
          className="btn"
          type="button"
          disabled={!subName.trim()}
          onClick={async () => {
            onClose();
            await send({
              type: "substitute_fielder",
              side: inn.bowling,
              player: { id: randomUUID(), name: subName.trim(), bats_left: false },
              for_player_id: subFor || null,
            });
          }}
        >
          {t("sc.on_they_come")}
        </button>
      </div>

      <h3 style={{ marginTop: "var(--s4)" }}>{t("sc.take_a_bowler_off")}</h3>
      <p className="muted">
        {t("sc.law_41_a_second_beamer_or_short_pitche")}
      </p>
      <div className="form">
        <label>
          {t("sc.bowler")}
          <select value={suspend} onChange={(e) => setSuspend(e.target.value)}>
            <option value="">{t("sc.nobody")}</option>
            {bowlingXi
              .filter((id) => !suspended.includes(id))
              .map((id) => <option key={id} value={id}>{nameOf(id)}</option>)}
          </select>
        </label>
        <label>
          {t("sc.what_for")}
          <input value={suspendWhy} onChange={(e) => setSuspendWhy(e.target.value)} />
        </label>
      </div>
      <div className="sheet-actions">
        <button
          className="btn danger"
          type="button"
          disabled={!suspend || !suspendWhy.trim()}
          onClick={async () => {
            onClose();
            await send({
              type: "bowler_suspended",
              bowler_id: suspend,
              reason: suspendWhy.trim(),
            });
          }}
        >
          {t("sc.take_them_off")}
        </button>
      </div>

      <h3 style={{ marginTop: "var(--s4)" }}>{t("sc.penalty_runs")}</h3>
      <div className="form">
        <label>
          {t("sc.runs")}
          <input type="number" min={1} max={10} value={penalty} onChange={(e) => setPenalty(Number(e.target.value))} />
        </label>
        <label>
          {t("sc.reason")}
          <input value={reason} onChange={(e) => setReason(e.target.value)} />
        </label>
        <label>
          {t("sc.awarded_to")}
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
          {t("sc.award_penalty")}
        </button>
        <button
          className="btn ghost"
          type="button"
          onClick={async () => {
            onClose();
            await send({ type: "innings_completed", declared: false, forfeited: false });
          }}
        >
          {t("sc.end_innings")}
        </button>
      </div>

      {twoInnings && (
        <>
          <h3 style={{ marginTop: "var(--s4)" }}>{t("sc.declaration_game")}</h3>
          <p className="muted">
            {t("sc.two_innings_a_side_won_on_aggregate_a")}
          </p>
          <div className="sheet-actions">
            <button
              className="btn"
              type="button"
              onClick={async () => {
                onClose();
                await send({ type: "innings_completed", declared: true, forfeited: false });
              }}
            >
              {t("sc.declare")}
            </button>
            <button
              className="btn ghost"
              type="button"
              onClick={async () => {
                onClose();
                await send({ type: "innings_completed", declared: false, forfeited: true });
              }}
            >
              {t("sc.forfeit_the_innings")}
            </button>
            <button
              className="btn ghost"
              type="button"
              onClick={async () => {
                onClose();
                await send({ type: "match_completed", winner: null, margin: "Match drawn" });
              }}
            >
              {t("sc.match_drawn")}
            </button>
          </div>
        </>
      )}
    </Sheet>
  );
}

