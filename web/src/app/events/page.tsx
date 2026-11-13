"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  api,
  readErr,
  type Club,
  type MyRole,
  type OpponentIdentity,
  type Venue,
} from "@/lib/api";
import { dayKey, type Availability, type AvailabilityStatus } from "@/lib/availability";
import {
  byDay,
  clashes,
  dayTitle,
  myFixtures,
  saidLabel,
  searchFixtureClubs,
  sessionMetadata,
  timeOf,
  type MyFixture,
} from "@/lib/fixtures";
import {
  DEFAULT_MINUTES,
  DEFAULT_WEEKS,
  MAX_WEEKS,
  MIN_WEEKS,
  PRACTICE_LABEL,
  SESSION_MINUTES,
  clampWeeks,
  isPractice,
  matchBody,
  seriesWeek,
  sessionBodies,
  sessionNote,
  sportOf,
  toLocalInput,
  type ScheduleKind,
  type SessionBody,
} from "@/lib/sessions";
import { randomUUID } from "@/lib/uuid";
import { FixtureAnswer } from "@/components/FixtureAnswer";
import { OppositionPicker } from "@/components/OppositionPicker";
import { Icon, type IconName } from "@/components/Icon";
import { SearchSelect } from "@/components/SearchSelect";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

const SUBTYPE_ICON: Record<string, IconName> = {
  league_match: "trophy",
  friendly: "ball",
  tournament: "trophy",
  nets: "bat",
  social: "users",
};

type View = "upcoming" | "unanswered" | "past";

const GUIDE_KEY = "fishers:fixtures-guide-dismissed";

/// Every fixture of every club you are in, a day at a time, each asking the
/// one thing it needs from you: can you play?
///
/// Your answer is on the card and you can change it there. It is the same
/// answer the availability calendar shows and the captain picks from.
export default function EventsPage() {
  const t = useT();
  const authed = useRequireAuth();
  const [fixtures, setFixtures] = useState<MyFixture[] | null>(null);
  const [past, setPast] = useState<MyFixture[] | null>(null);
  const [days, setDays] = useState<Record<string, AvailabilityStatus>>({});
  const [schedulable, setSchedulable] = useState<Club[]>([]);
  const [view, setView] = useState<View>("upcoming");
  const [club, setClub] = useState("");
  const [error, setError] = useState<string | null>(null);
  /// Which kind the schedule panel is making, while it is open.
  const [scheduling, setScheduling] = useState<ScheduleKind | null>(null);
  /// "3 sessions scheduled", once the panel has closed on them.
  const [notice, setNotice] = useState<string | null>(null);
  /// Each nets or training session's note and week, by event id.
  const [meta, setMeta] = useState<Record<string, unknown>>({});
  const [guide, setGuide] = useState(false);

  /// A session's note and week are not in the fixtures list; fetched beside
  /// it, and a fixture shows without them rather than waiting.
  const readSessions = useCallback((list: MyFixture[]) => {
    sessionMetadata(list)
      .then((found) => setMeta((had) => ({ ...had, ...found })))
      .catch(() => {});
  }, []);

  useEffect(() => {
    // ?new=1 from the getting-started guide: open the form on arrival.
    if (new URLSearchParams(window.location.search).get("new") === "1") setScheduling("match");
    try {
      setGuide(localStorage.getItem(GUIDE_KEY) !== "1");
    } catch {
      setGuide(true);
    }
  }, []);

  const load = useCallback(async () => {
    // From a few hours back, so a match on now is still here.
    const from = new Date(Date.now() - 6 * 3600e3);
    const to = new Date(Date.now() + 180 * 864e5);
    try {
      const [mine, marked] = await Promise.all([
        myFixtures(from, to),
        api<Availability[]>("GET", `/availability?from=${dayKey(from)}&to=${dayKey(to)}`).catch(() => []),
      ]);
      setFixtures(mine);
      setDays(Object.fromEntries(marked.map((a) => [a.date, a.status])));
      setError(null);
      readSessions(mine);
    } catch (err) {
      setError(readErr(err, t("ld.could_not_load_your_fixtures")));
    }
  }, [t, readSessions]);

  useEffect(() => {
    if (!authed) return;
    load();
    // Who can put a match in the diary: only they see the button.
    (async () => {
      const clubs = await api<Club[]>("GET", "/clubs").catch(() => [] as Club[]);
      const roles = await Promise.all(
        clubs.map((c) => api<MyRole>("GET", `/clubs/${c.id}/my-role`).catch(() => null))
      );
      setSchedulable(clubs.filter((_, i) => roles[i]?.permissions.includes("manage_events")));
    })();
  }, [load, authed]);

  // Hooks must run every render — before any authed early return — or React
  // throws #310 the moment a token appears and this component keeps mounting.
  // Only to decide whether a filter is worth showing at all. Which clubs it
  // offers is the server's business — see `searchFixtureClubs`.
  const clubs = useMemo(() => {
    const seen = new Set<string>();
    for (const f of [...(fixtures ?? []), ...(past ?? [])]) seen.add(f.club_id);
    return [...seen];
  }, [fixtures, past]);

  if (!authed) return <main id="main" />;

  const showPast = async () => {
    setView("past");
    if (past) return;
    try {
      const list = await myFixtures(new Date(Date.now() - 120 * 864e5), new Date());
      setPast(list.reverse());
      readSessions(list);
    } catch (err) {
      setError(readErr(err, t("ld.could_not_load_past_fixtures")));
    }
  };

  const setAnswer = (id: string, answer: MyFixture["my_answer"]) =>
    setFixtures((all) => all?.map((f) => (f.event_id === id ? { ...f, my_answer: answer } : f)) ?? all);

  const upcoming = fixtures ?? [];
  const unanswered = upcoming.filter((f) => !f.my_answer);
  const playing = upcoming.filter((f) => f.my_answer === "going");
  const source = view === "past" ? past ?? [] : view === "unanswered" ? unanswered : upcoming;
  const shown = club ? source.filter((f) => f.club_id === club || f.opponent_club_id === club) : source;
  const grouped = byDay(shown);
  const clashing = clashes(upcoming);

  const dismissGuide = () => {
    setGuide(false);
    try {
      localStorage.setItem(GUIDE_KEY, "1");
    } catch {
      /* shown again next time; no harm */
    }
  };

  return (
    <main id="main" className="fixtures">
      <section className="hero fixtures-hero">
        <div>
          <h1>{t("ev.fixtures")}</h1>
          <p>{t("ev.every_match_your_clubs_play_say_whethe")}</p>
        </div>
        <div className="fixtures-hero-actions">
          {schedulable.length > 0 && (
            <>
              <button
                className="btn primary"
                type="button"
                onClick={() => {
                  setNotice(null);
                  setScheduling("match");
                }}
              >
                <Icon name="plus" size={16} /> {t("ev.schedule_a_match")}
              </button>
              <button
                className="btn"
                type="button"
                onClick={() => {
                  setNotice(null);
                  setScheduling("nets");
                }}
              >
                <Icon name={SUBTYPE_ICON.nets} size={16} /> {t("np.schedule_nets_or_practice")}
              </button>
            </>
          )}
          <Link className="btn" href="/availability">
            <Icon name="calendar" size={16} /> {t("ev.your_calendar")}
          </Link>
        </div>
      </section>

      {error && <p className="error">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      {scheduling && schedulable.length > 0 && (
        <ScheduleMatch
          clubs={schedulable}
          kind={scheduling}
          onKind={setScheduling}
          onClose={() => setScheduling(null)}
          onSent={load}
          onScheduled={(sessions) => {
            setScheduling(null);
            setNotice(sessions ? t("np.scheduled_sessions", { count: sessions, n: sessions }) : null);
            load();
          }}
        />
      )}

      {guide && fixtures !== null && (
        <section className="panel guide-card" aria-labelledby="fx-guide-title">
          <div className="guide-card-head">
            <h2 id="fx-guide-title">{t("ev.how_fixtures_work")}</h2>
            <button className="btn ghost sm" type="button" onClick={dismissGuide}>
              {t("ev.got_it")}
            </button>
          </div>
          <ol className="guide-steps">
            <li>
              <span className="guide-num" aria-hidden>1</span>
              <div>
                <strong>{t("ev.answer_each_fixture")}</strong>
                <p>{t("ev.answer_each_detail")}</p>
              </div>
            </li>
            <li>
              <span className="guide-num" aria-hidden>2</span>
              <div>
                <strong>{t("ev.the_captain_picks_the_side")}</strong>
                <p>{t("ev.captain_picks_detail")}</p>
              </div>
            </li>
            <li>
              <span className="guide-num" aria-hidden>3</span>
              <div>
                <strong>{t("ev.keep_your_calendar")}</strong>
                <p>
                  {t("ev.mark_your_usual_days_on")} <Link href="/availability">{t("ev.your_calendar_2")}</Link>{" "}
                  {t("ev.calendar_shows_every_fixture")}
                </p>
              </div>
            </li>
          </ol>
        </section>
      )}

      {fixtures !== null && upcoming.length > 0 && (
        <div className="fx-summary" role="group" aria-label={t("ev.your_fixtures_at_a_glance")}>
          <button
            type="button"
            className={`fx-stat${view === "unanswered" ? " on" : ""}${unanswered.length ? " needs" : ""}`}
            aria-pressed={view === "unanswered"}
            onClick={() => setView(view === "unanswered" ? "upcoming" : "unanswered")}
          >
            <span className="fx-stat-num num">{unanswered.length}</span>
            <span className="fx-stat-label">{unanswered.length === 1 ? "needs your answer" : "need your answer"}</span>
          </button>
          <div className="fx-stat">
            <span className="fx-stat-num num">{playing.length}</span>
            <span className="fx-stat-label">{t("ev.said_available")}</span>
          </div>
          <div className="fx-stat">
            <span className="fx-stat-num num">{upcoming.length}</span>
            <span className="fx-stat-label">{t("ev.coming_up")}</span>
          </div>
        </div>
      )}

      <div className="fx-filters">
        <div className="people-tabs fx-views" role="tablist" aria-label={t("ev.which_fixtures")}>
          {([
            ["upcoming", t("ev.coming_up")],
            ["unanswered", t("ld.needs_my_answer")],
            ["past", t("ld.past")],
          ] as [View, string][]).map(([v, label]) => (
            <button
              key={v}
              type="button"
              role="tab"
              aria-selected={view === v}
              className={view === v ? "on" : undefined}
              onClick={() => (v === "past" ? showPast() : setView(v))}
            >
              {label}
              {v === "unanswered" && unanswered.length > 0 && <span className="people-count num">{unanswered.length}</span>}
            </button>
          ))}
        </div>
        {clubs.length > 1 && (
          <SearchSelect
            value={club}
            onChange={setClub}
            search={searchFixtureClubs}
            label={t("ev.which_club")}
            anyLabel={t("ev.all_clubs")}
          />
        )}
      </div>

      {(fixtures === null || (view === "past" && past === null)) && !error && (
        <div className="skeleton" style={{ height: 180 }} />
      )}

      {fixtures !== null && !(view === "past" && past === null) && shown.length === 0 && (
        <div className="panel empty">
          <Icon name={view === "unanswered" ? "check" : "calendar"} size={28} />
          <p>
            {view === "unanswered"
              ? t("ld.you_ve_answered_every_fixture_nice")
              : view === "past"
                ? t("ld.no_fixtures_in_the_last_four_months")
                : schedulable.length > 0
                  ? t("ld.nothing_in_the_diary_yet_schedule_a_ma")
                  : t("ld.nothing_in_the_diary_yet_when_your_clu")}
          </p>
        </div>
      )}

      {[...grouped].map(([key, list]) => (
        <section key={key} className="fx-day" aria-labelledby={`day-${key}`}>
          <h2 id={`day-${key}`} className="fx-day-title">
            {dayTitle(key)}
            {list.length > 1 && <span className="fx-day-count">{list.length} fixtures</span>}
          </h2>
          {list.map((f) => (
            <FixtureCard
              key={f.event_id}
              f={f}
              meta={meta[f.event_id]}
              past={view === "past"}
              clash={clashing.has(f.event_id)}
              dayStatus={days[key]}
              onAnswered={(a) => setAnswer(f.event_id, a)}
            />
          ))}
        </section>
      ))}
    </main>
  );
}

function FixtureCard({
  f,
  meta,
  past,
  clash,
  dayStatus,
  onAnswered,
}: {
  f: MyFixture;
  /// The event's metadata, when it is a session and it has been read.
  meta?: unknown;
  past: boolean;
  clash: boolean;
  dayStatus?: AvailabilityStatus;
  onAnswered: (a: MyFixture["my_answer"]) => void;
}) {
  const t = useT();
  const hours = Math.round((Date.parse(f.end_at) - Date.parse(f.start_at)) / 3600e3);
  const state = f.my_answer ?? "none";
  // Nets or training: a session to turn up to. No opposition, no squad, no
  // scorecard — and "are you coming?" rather than "can you play?".
  const session = isPractice(f.event_subtype) ? f.event_subtype : null;
  const week = session ? seriesWeek(meta) : null;
  const note = session ? sessionNote(meta) : null;
  const mins = Math.round((Date.parse(f.end_at) - Date.parse(f.start_at)) / 60e3);
  return (
    <article className={`fx-card is-${state}${past ? " past" : ""}`}>
      <div className="fx-time">
        <strong className="num">{timeOf(f.start_at)}</strong>
        {session ? mins > 0 && <span>{t("np.n_minutes", { n: mins })}</span> : hours > 0 && <span>{hours}h</span>}
      </div>
      <div className="fx-body">
        <div className="fx-tags">
          <span className="tag">
            <Icon name={SUBTYPE_ICON[f.event_subtype] ?? "calendar"} size={12} />
            {session ? t(PRACTICE_LABEL[session]) : f.event_subtype.replaceAll("_", " ")}
          </span>
          {week && <span className="tag grey">{t("np.week_of", { i: week.i, n: week.n })}</span>}
          {f.status !== "scheduled" && <span className="tag gold">{f.status.replaceAll("_", " ")}</span>}
          {!past && !f.my_answer && <span className="tag gold">{t("ev.needs_your_answer")}</span>}
        </div>
        <Link className="fx-title" href={`/events/${f.event_id}`}>
          {f.title}
        </Link>
        <p className="fx-meta">
          <span>
            <Icon name="users" size={14} /> {f.club_name}
            {f.opponent_club_name && !session ? ` v ${f.opponent_club_name}` : ""}
          </span>
          {f.venue_name && (
            <span>
              <Icon name="pin" size={14} /> {f.venue_name}
            </span>
          )}
          {f.fee_amount_cents != null && <span className="num">{t("ev.match_fee_amount", { amount: `£${(f.fee_amount_cents / 100).toFixed(2)}` })}</span>}
        </p>
        {note && <p className="fx-meta">{note}</p>}
        {clash && <p className="fx-warn">{t("ev.clash_same_time")}</p>}
        {dayStatus === "unavailable" && f.my_answer !== "not_going" && (
          <p className="fx-warn">{t("ev.calendar_says_not_available")}</p>
        )}
        {(!session || f.ticket_price_cents != null) && (
          <div className="fx-links">
            {!session && (
              <Link className="btn sm" href={`/events/${f.event_id}/selection`}>
                <Icon name="users" size={14} /> Squad
              </Link>
            )}
            {f.match_id && !session && (
              <Link className="btn sm" href={`/score/${f.match_id}`}>
                <Icon name="radio" size={14} /> {past ? t("ld.scorecard") : "Score"}
              </Link>
            )}
            {f.ticket_price_cents != null && (
              <Link className="btn sm" href={`/events/${f.event_id}/tickets`}>
                {t("ev.tickets")}
              </Link>
            )}
          </div>
        )}
      </div>
      <div className="fx-side">
        {past ? (
          <span className={`fx-said is-${state}`}>{t(saidLabel(f.my_answer))}</span>
        ) : (
          <>
            <span className={`fx-said is-${state}`}>{t(saidLabel(f.my_answer))}</span>
            <FixtureAnswer
              eventId={f.event_id}
              answer={f.my_answer}
              onAnswered={onAnswered}
              label={session ? t("np.are_you_coming") : t("fin.can_you_play_fixture", { fixture: f.title })}
            />
          </>
        )}
      </div>
    </article>
  );
}

/// Schedule a match against another club, or nets or training for your own.
///
/// Naming the opposition here is what lets both sides be asked who is
/// available — a fixture that only knows its host can only ask half a match.
///
/// Nets and training have no opposition. They have a length instead, a note,
/// and can repeat every week: one event per week, made one after another,
/// sharing a series id so only the first week notifies anybody.
function ScheduleMatch({
  clubs,
  kind,
  onKind,
  onClose,
  onSent,
  onScheduled,
}: {
  /// Only the clubs this person can schedule for.
  clubs: Club[];
  kind: ScheduleKind;
  onKind: (kind: ScheduleKind) => void;
  onClose: () => void;
  /// Some weeks of a series were made before one failed: the list behind
  /// should show them while the panel stays open to finish the rest.
  onSent: () => void;
  /// Done. `sessions` is how many nets or training sessions were made; a
  /// match passes nothing.
  onScheduled: (sessions?: number) => void;
}) {
  const t = useT();
  /// How many sessions are made, and — once a week has failed partway
  /// through a series — the weeks still to send. Trying again sends only
  /// those, so no week is ever made twice, and the form is held still so what
  /// it shows is what they will be.
  const [made, setMade] = useState(0);
  const [left, setLeft] = useState<SessionBody[] | null>(null);
  // Held to the kind of the weeks still to send, whichever button is pressed
  // above the panel in the meantime.
  const shown: ScheduleKind = left?.[0]?.event_subtype ?? kind;
  const session = shown === "match" ? null : shown;
  const [clubId, setClubId] = useState(clubs[0]?.id ?? "");
  const [opponent, setOpponent] = useState<OpponentIdentity | null>(null);
  const [oppositionName, setOppositionName] = useState("");
  const [start, setStart] = useState("");
  const [venues, setVenues] = useState<Venue[]>([]);
  const [venueId, setVenueId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Nets and training. `null` until touched, so each follows the kind: the
  // name is "Nets" or "Training", the length two hours or ninety minutes.
  const [name, setName] = useState<string | null>(null);
  const [minutes, setMinutes] = useState<number | null>(null);
  const [note, setNote] = useState("");
  const [repeat, setRepeat] = useState(false);
  const [weeks, setWeeks] = useState(String(DEFAULT_WEEKS));

  // The grounds belong to whichever club is hosting, so they follow the club.
  useEffect(() => {
    if (!clubId) return;
    setVenueId("");
    api<Venue[]>("GET", `/clubs/${clubId}/venues`).then(setVenues).catch(() => setVenues([]));
  }, [clubId]);

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      await api(
        "POST",
        "/events",
        matchBody({
          clubId,
          club: clubs.find((c) => c.id === clubId),
          opponent,
          oppositionName,
          venueId,
          start: new Date(start),
        })
      );
      onScheduled();
    } catch (err) {
      setError(readErr(err, t("ld.could_not_schedule_that")));
    } finally {
      setBusy(false);
    }
  };

  const length = session ? minutes ?? DEFAULT_MINUTES[session] : 0;
  const count = repeat ? clampWeeks(Number(weeks)) : 1;

  const submitSessions = async () => {
    if (!session) return;
    setBusy(true);
    setError(null);
    let queue: SessionBody[] = [];
    let sent = 0;
    try {
      queue =
        left ??
        sessionBodies({
          kind: session,
          clubId,
          sport: sportOf(clubs.find((c) => c.id === clubId)?.sport_types),
          title: name?.trim() || t(PRACTICE_LABEL[session]),
          venueId: venueId || undefined,
          start: new Date(start),
          minutes: length,
          note,
          weeks: count,
          seriesId: count > 1 ? randomUUID() : undefined,
        });
      // One after another, so a failure stops the series where it is rather
      // than leaving a gap in the middle of it.
      for (const body of queue) {
        await api("POST", "/events", body);
        sent++;
      }
      onScheduled(made + sent);
    } catch (err) {
      setError(readErr(err, t("ld.could_not_schedule_that")));
      if (made + sent > 0) {
        setMade(made + sent);
        setLeft(queue.slice(sent));
        onSent();
      }
    } finally {
      setBusy(false);
    }
  };

  // In the order the form asks, so the answer is always the next thing down
  // the page rather than something they have to hunt for. A session cannot
  // start in the past; the picker's `min` stops most of those, this the rest.
  const earliest = toLocalInput(new Date());
  const missing = left
    ? ""
    : [
        !clubId && t("ev.missing_which_club"),
        !session && !opponent && !oppositionName.trim() && t("ev.missing_who"),
        (!start || (session && start < earliest)) && t("ev.missing_when"),
      ]
        .filter(Boolean)
        .join(", ");

  return (
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>{session ? t("np.schedule_nets_or_practice") : t("ev.schedule_a_match")}</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>{t("sc.cancel")}</button>
      </div>

      <fieldset className="chip-set" disabled={!!left}>
        <legend>{t("np.what_kind")}</legend>
        {(["match", "nets", "training"] as const).map((k) => (
          <button
            key={k}
            type="button"
            className={`chip${shown === k ? " on" : ""}`}
            aria-pressed={shown === k}
            onClick={() => onKind(k)}
          >
            {t(k === "match" ? "np.match" : PRACTICE_LABEL[k])}
          </button>
        ))}
      </fieldset>

      <fieldset className="setup-group" disabled={!!left}>
        <legend>{session ? t(PRACTICE_LABEL[session]) : t("ev.your_side")}</legend>
        <label>
          {t("ev.club")}
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        {session && (
          <>
            <label>
              {t("np.name")}
              <input
                value={name ?? t(PRACTICE_LABEL[session])}
                onChange={(e) => setName(e.target.value)}
                placeholder={t("np.name_hint")}
                maxLength={200}
              />
            </label>
            <label>
              {t("np.note")}
              <textarea
                rows={2}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder={t("np.note_hint")}
              />
            </label>
          </>
        )}
      </fieldset>

      <fieldset className="setup-group" disabled={!!left}>
        <legend>{t("ev.where")}</legend>
        {venues.length === 0 ? (
          <p className="muted">
            {t("ev.no_grounds_saved")}{" "}
            <Link href={`/clubs/${clubId}`}>{t("ev.club_page")}</Link> {t("ev.and_they_show_up_here")}
          </p>
        ) : (
          <label>
            {t("cl.ground")}
            <select value={venueId} onChange={(e) => setVenueId(e.target.value)}>
              <option value="">{t("ev.not_decided_yet")}</option>
              {venues.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
            </select>
          </label>
        )}
      </fieldset>

      {/* Hidden rather than unmounted for nets and training: the picker keeps
          its own state, and remounting it would show nothing chosen while the
          opposition picked before it was hidden was still sent. */}
      <fieldset className="setup-group" hidden={!!session}>
        <legend>{t("ev.the_opposition")}</legend>
        <OppositionPicker
          homeClubId={clubId}
          onPick={(found, typed) => {
            setOpponent(found);
            setOppositionName(typed);
          }}
        />
        {/* Only while nothing is chosen. Once it is, the picker's own panel
            says the same thing where the choice is, and two copies of it on
            one screen is one too many. */}
        {!opponent && (
          <p className="subtle">{t("ev.club_on_brand_gets_asked", { brand: brand.name })}</p>
        )}
      </fieldset>

      <fieldset className="setup-group" disabled={!!left}>
        <legend>{t("ev.when")}</legend>
        <label>
          {t("ev.date_and_time")}
          <input
            type="datetime-local"
            value={start}
            min={session ? earliest : undefined}
            onChange={(e) => setStart(e.target.value)}
          />
        </label>
        {session && (
          <label className="check-row">
            <input type="checkbox" checked={repeat} onChange={(e) => setRepeat(e.target.checked)} />
            <span>
              <strong>{t("np.repeat_weekly")}</strong>
            </span>
          </label>
        )}
        {session && repeat && (
          <label>
            {t("np.for_weeks", { count, n: count })}
            <input
              type="number"
              inputMode="numeric"
              min={MIN_WEEKS}
              max={MAX_WEEKS}
              value={weeks}
              onChange={(e) => setWeeks(e.target.value)}
              onBlur={() => setWeeks(String(count))}
            />
          </label>
        )}
      </fieldset>

      {session && (
        <fieldset className="setup-group" disabled={!!left}>
          <legend>{t("rest.how_long")}</legend>
          <div className="chips">
            {SESSION_MINUTES.map((m) => (
              <button
                key={m}
                type="button"
                className={`chip${length === m ? " on" : ""}`}
                aria-pressed={length === m}
                onClick={() => setMinutes(m)}
                // "120 min", not the chip's usual "120 Min".
                style={{ textTransform: "none" }}
              >
                {t("np.n_minutes", { n: m })}
              </button>
            ))}
          </div>
        </fieldset>
      )}

      {session && made > 0 && (
        <p className="notice" role="status">{t("np.scheduled_sessions", { count: made, n: made })}</p>
      )}
      {error && <p className="error">{error}</p>}

      {/* A dead button with no explanation reads as a broken app. Say which
          piece is missing, in the order the form asks for them. */}
      {!busy && missing && (
        <p className="muted" role="status">{t("ev.still_needed", { what: missing })}</p>
      )}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !!missing}
        onClick={session ? submitSessions : submit}
      >
        {busy ? t("ld.scheduling") : session ? t("np.schedule") : t("ld.schedule_and_ask_who_is_available")}
      </button>
      <p className="subtle">
        {session
          ? t("np.everyone_asked")
          : t("ev.everyone_in_is_asked", { who: opponent ? t("ev.both_clubs") : t("ev.your_club") })}
      </p>
    </div>
  );
}
