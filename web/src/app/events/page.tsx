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
import { byDay, clashes, dayTitle, myFixtures, saidLabel, timeOf, type MyFixture } from "@/lib/fixtures";
import { FixtureAnswer } from "@/components/FixtureAnswer";
import { OppositionPicker } from "@/components/OppositionPicker";
import { Icon, type IconName } from "@/components/Icon";
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
  const [scheduling, setScheduling] = useState(false);
  const [guide, setGuide] = useState(false);

  useEffect(() => {
    // ?new=1 from the getting-started guide: open the form on arrival.
    if (new URLSearchParams(window.location.search).get("new") === "1") setScheduling(true);
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
    } catch (err) {
      setError(readErr(err, t("ld.could_not_load_your_fixtures")));
    }
  }, [t]);

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
  const clubs = useMemo(() => {
    const seen = new Map<string, string>();
    for (const f of [...(fixtures ?? []), ...(past ?? [])]) seen.set(f.club_id, f.club_name);
    return [...seen];
  }, [fixtures, past]);

  if (!authed) return <main id="main" />;

  const showPast = async () => {
    setView("past");
    if (past) return;
    try {
      const list = await myFixtures(new Date(Date.now() - 120 * 864e5), new Date());
      setPast(list.reverse());
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
          <h1>Fixtures</h1>
          <p>{t("ev.every_match_your_clubs_play_say_whethe")}</p>
        </div>
        <div className="fixtures-hero-actions">
          {schedulable.length > 0 && (
            <button className="btn primary" type="button" onClick={() => setScheduling(true)}>
              <Icon name="plus" size={16} /> {t("ev.schedule_a_match")}
            </button>
          )}
          <Link className="btn" href="/availability">
            <Icon name="calendar" size={16} /> {t("ev.your_calendar")}
          </Link>
        </div>
      </section>

      {error && <p className="error">{error}</p>}

      {scheduling && schedulable.length > 0 && (
        <ScheduleMatch
          clubs={schedulable}
          onClose={() => setScheduling(false)}
          onScheduled={() => {
            setScheduling(false);
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
                <p>Available, Maybe or Can&rsquo;t play — right on the card. Change it any time.</p>
              </div>
            </li>
            <li>
              <span className="guide-num" aria-hidden>2</span>
              <div>
                <strong>{t("ev.the_captain_picks_the_side")}</strong>
                <p>From everyone&rsquo;s answers. You get told when you&rsquo;re in the squad.</p>
              </div>
            </li>
            <li>
              <span className="guide-num" aria-hidden>3</span>
              <div>
                <strong>{t("ev.keep_your_calendar")}</strong>
                <p>
                  {t("ev.mark_your_usual_days_on")} <Link href="/availability">{t("ev.your_calendar_2")}</Link> — it shows every
                  fixture and what you said, two matches on one day included.
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
        <div className="people-tabs fx-views" role="tablist" aria-label="Which fixtures">
          {([
            ["upcoming", "Coming up"],
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
          <div className="chip-set fx-clubs" role="group" aria-label={t("ev.which_club")}>
            <button type="button" className={`chip${club === "" ? " on" : ""}`} aria-pressed={club === ""} onClick={() => setClub("")}>
              {t("ev.all_clubs")}
            </button>
            {clubs.map(([id, name]) => (
              <button key={id} type="button" className={`chip${club === id ? " on" : ""}`} aria-pressed={club === id} onClick={() => setClub(id)}>
                {name}
              </button>
            ))}
          </div>
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
  past,
  clash,
  dayStatus,
  onAnswered,
}: {
  f: MyFixture;
  past: boolean;
  clash: boolean;
  dayStatus?: AvailabilityStatus;
  onAnswered: (a: MyFixture["my_answer"]) => void;
}) {
  const t = useT();
  const hours = Math.round((Date.parse(f.end_at) - Date.parse(f.start_at)) / 3600e3);
  const state = f.my_answer ?? "none";
  return (
    <article className={`fx-card is-${state}${past ? " past" : ""}`}>
      <div className="fx-time">
        <strong className="num">{timeOf(f.start_at)}</strong>
        {hours > 0 && <span>{hours}h</span>}
      </div>
      <div className="fx-body">
        <div className="fx-tags">
          <span className="tag">
            <Icon name={SUBTYPE_ICON[f.event_subtype] ?? "calendar"} size={12} />
            {f.event_subtype.replaceAll("_", " ")}
          </span>
          {f.status !== "scheduled" && <span className="tag gold">{f.status.replaceAll("_", " ")}</span>}
          {!past && !f.my_answer && <span className="tag gold">{t("ev.needs_your_answer")}</span>}
        </div>
        <Link className="fx-title" href={`/events/${f.event_id}`}>
          {f.title}
        </Link>
        <p className="fx-meta">
          <span>
            <Icon name="users" size={14} /> {f.club_name}
            {f.opponent_club_name ? ` v ${f.opponent_club_name}` : ""}
          </span>
          {f.venue_name && (
            <span>
              <Icon name="pin" size={14} /> {f.venue_name}
            </span>
          )}
          {f.fee_amount_cents != null && <span className="num">£{(f.fee_amount_cents / 100).toFixed(2)} match fee</span>}
        </p>
        {clash && <p className="fx-warn">You&rsquo;re available for another fixture at the same time.</p>}
        {dayStatus === "unavailable" && f.my_answer !== "not_going" && (
          <p className="fx-warn">Your calendar says you&rsquo;re not available this day.</p>
        )}
        <div className="fx-links">
          <Link className="btn sm" href={`/events/${f.event_id}/selection`}>
            <Icon name="users" size={14} /> Squad
          </Link>
          {f.match_id && (
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
      </div>
      <div className="fx-side">
        {past ? (
          <span className={`fx-said is-${state}`}>{saidLabel(f.my_answer)}</span>
        ) : (
          <>
            <span className={`fx-said is-${state}`}>{saidLabel(f.my_answer)}</span>
            <FixtureAnswer eventId={f.event_id} answer={f.my_answer} onAnswered={onAnswered} label={t("fin.can_you_play_fixture", { fixture: f.title })} />
          </>
        )}
      </div>
    </article>
  );
}

/// Schedule a match against another club.
///
/// Naming the opposition here is what lets both sides be asked who is
/// available — a fixture that only knows its host can only ask half a match.
function ScheduleMatch({
  clubs,
  onClose,
  onScheduled,
}: {
  /// Only the clubs this person can schedule for.
  clubs: Club[];
  onClose: () => void;
  onScheduled: () => void;
}) {
  const t = useT();
  const [clubId, setClubId] = useState(clubs[0]?.id ?? "");
  const [opponent, setOpponent] = useState<OpponentIdentity | null>(null);
  const [oppositionName, setOppositionName] = useState("");
  const [start, setStart] = useState("");
  const [venues, setVenues] = useState<Venue[]>([]);
  const [venueId, setVenueId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
      const from = new Date(start);
      // A fixture runs most of an afternoon; nobody wants to type an end time
      // as well.
      const to = new Date(from.getTime() + 5 * 60 * 60 * 1000);
      const club = clubs.find((c) => c.id === clubId);
      const us = club?.name ?? "Us";
      await api("POST", "/events", {
        club_id: clubId,
        opponent_club_id: opponent?.club_id ?? null,
        // What the club plays. Hard-coding cricket here filed every fixture as
        // a cricket match, whatever sport the club was actually turning out for.
        sport: club?.sport_types[0] ?? "cricket",
        event_subtype: "league_match",
        title: `${us} v ${opponent?.name ?? (oppositionName || "opposition")}`,
        venue_id: venueId || null,
        start_at: from.toISOString(),
        end_at: to.toISOString(),
      });
      onScheduled();
    } catch (err) {
      setError(readErr(err, t("ld.could_not_schedule_that")));
    } finally {
      setBusy(false);
    }
  };

  // In the order the form asks, so the answer is always the next thing down
  // the page rather than something they have to hunt for.
  const missing = [
    !clubId && "which of your clubs is playing",
    !opponent && !oppositionName.trim() && "who you are playing",
    !start && "when",
  ]
    .filter(Boolean)
    .join(", ");

  return (
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>{t("ev.schedule_a_match")}</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
      </div>

      <fieldset className="setup-group">
        <legend>Your side</legend>
        <label>
          Club
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
      </fieldset>

      <fieldset className="setup-group">
        <legend>{t("ev.where")}</legend>
        {venues.length === 0 ? (
          <p className="muted">
            No grounds saved for this club yet. Add them on the{" "}
            <Link href={`/clubs/${clubId}`}>{t("ev.club_page")}</Link> {t("ev.and_they_show_up_here")}
          </p>
        ) : (
          <label>
            Ground
            <select value={venueId} onChange={(e) => setVenueId(e.target.value)}>
              <option value="">{t("ev.not_decided_yet")}</option>
              {venues.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
            </select>
          </label>
        )}
      </fieldset>

      <fieldset className="setup-group">
        <legend>The opposition</legend>
        <OppositionPicker
          homeClubId={clubId}
          onPick={(found, name) => {
            setOpponent(found);
            setOppositionName(name);
          }}
        />
        <p className="subtle">
          {opponent
            ? `${opponent.name} are on ${brand.name} — their players get asked too.`
            : `A club on ${brand.name} gets asked as well. Otherwise only your side is.`}
        </p>
      </fieldset>

      <fieldset className="setup-group">
        <legend>{t("ev.when")}</legend>
        <label>
          {t("ev.date_and_time")}
          <input
            type="datetime-local"
            value={start}
            onChange={(e) => setStart(e.target.value)}
          />
        </label>
      </fieldset>

      {error && <p className="error">{error}</p>}

      {/* A dead button with no explanation reads as a broken app. Say which
          piece is missing, in the order the form asks for them. */}
      {!busy && missing && (
        <p className="muted" role="status">Still needed: {missing}.</p>
      )}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !!missing}
        onClick={submit}
      >
        {busy ? t("ld.scheduling") : t("ld.schedule_and_ask_who_is_available")}
      </button>
      <p className="subtle">
        Everyone in {opponent ? "both clubs" : "your club"} is asked whether they can
        play, and the captain hears each answer.
      </p>
    </div>
  );
}
