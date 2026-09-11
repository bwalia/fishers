"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, readErr } from "@/lib/api";
import {
  AVAILABILITY_LABEL,
  dayKey,
  monthGrid,
  weekdaysIn,
  WEEKDAYS,
  type Availability,
  type AvailabilityStatus,
} from "@/lib/availability";
import { byDay, dayTitle, myFixtures, saidLabel, timeOf, type MyFixture } from "@/lib/fixtures";
import { FixtureAnswer } from "@/components/FixtureAnswer";
import { Icon } from "@/components/Icon";

const STATUSES: AvailabilityStatus[] = ["available", "maybe", "unavailable"];
const GUIDE_KEY = "fishers:availability-guide-dismissed";

/// When you can play — and what you said to each fixture.
///
/// Two things a captain reads, on one calendar: the colour of a day is your
/// general availability; the marks on it are that day's fixtures, each in the
/// colour of your answer. Two matches on one day are two marks, because being
/// free on Sunday is not the same as playing both of Sunday's games.
///
/// Tap a day to open it: set the day, and answer its fixtures, right there.
export default function AvailabilityPage() {
  const [month, setMonth] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });
  const [days, setDays] = useState<Record<string, Availability>>({});
  const [fixtures, setFixtures] = useState<MyFixture[]>([]);
  const [chosen, setChosen] = useState(() => dayKey(new Date()));
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [guide, setGuide] = useState(false);

  const cells = useMemo(() => monthGrid(month), [month]);
  const fixturesOn = useMemo(() => byDay(fixtures), [fixtures]);

  useEffect(() => {
    try {
      setGuide(localStorage.getItem(GUIDE_KEY) !== "1");
    } catch {
      setGuide(true);
    }
  }, []);

  const load = useCallback(async () => {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const last = new Date(month.getFullYear(), month.getMonth() + 1, 0);
    const next = new Date(month.getFullYear(), month.getMonth() + 1, 1);
    try {
      const [mine, list] = await Promise.all([
        api<Availability[]>("GET", `/availability?from=${dayKey(first)}&to=${dayKey(last)}`),
        myFixtures(first, next),
      ]);
      setDays(Object.fromEntries(mine.map((a) => [a.date, a])));
      setFixtures(list);
      // Open on a day in this month: today if it is here, else its first fixture.
      const inMonth = (k: string) => k.startsWith(dayKey(first).slice(0, 7));
      setChosen((prev) => (inMonth(prev) ? prev : list[0] ? dayKey(new Date(list[0].start_at)) : dayKey(first)));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load your calendar"));
    } finally {
      setLoading(false);
    }
  }, [month]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to set when you can play.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  const setDay = async (key: string, status: AvailabilityStatus) => {
    setBusy(key);
    setError(null);
    // Optimistic: a calendar that lags a tap feels broken, and the only thing
    // a failure costs is putting the old value back.
    const previous = days[key];
    setDays((prev) => ({ ...prev, [key]: { ...(previous ?? blank(key)), status } }));
    try {
      const saved = await api<Availability>("POST", "/availability", { date: key, status });
      setDays((prev) => ({ ...prev, [key]: saved }));
    } catch (err) {
      setDays((prev) => {
        const next = { ...prev };
        if (previous) next[key] = previous;
        else delete next[key];
        return next;
      });
      setError(readErr(err, "Could not save that day"));
    } finally {
      setBusy(null);
    }
  };

  const setEvery = async (weekday: number, status: AvailabilityStatus) => {
    const dates = weekdaysIn(month, weekday).map(dayKey);
    setBusy("bulk");
    setError(null);
    try {
      const saved = await api<Availability[]>("POST", "/availability/bulk", { dates, status });
      setDays((prev) => ({ ...prev, ...Object.fromEntries(saved.map((a) => [a.date, a])) }));
    } catch (err) {
      setError(readErr(err, "Could not set those days"));
    } finally {
      setBusy(null);
    }
  };

  const setAnswer = (id: string, answer: MyFixture["my_answer"]) =>
    setFixtures((all) => all.map((f) => (f.event_id === id ? { ...f, my_answer: answer } : f)));

  const step = (by: number) => setMonth((m) => new Date(m.getFullYear(), m.getMonth() + by, 1));
  const toToday = () => {
    const now = new Date();
    setMonth(new Date(now.getFullYear(), now.getMonth(), 1));
    setChosen(dayKey(now));
  };

  const today = dayKey(new Date());
  const unanswered = fixtures.filter((f) => !f.my_answer && Date.parse(f.end_at) > Date.now());
  const chosenFixtures = fixturesOn.get(chosen) ?? [];
  const chosenStatus = days[chosen]?.status;
  const monthName = month.toLocaleDateString("en-GB", { month: "long" });

  const dismissGuide = () => {
    setGuide(false);
    try {
      localStorage.setItem(GUIDE_KEY, "1");
    } catch {
      /* shown again next time */
    }
  };

  return (
    <main id="main" className="avail">
      <section className="hero">
        <h1>When you can play</h1>
        <p>Your usual days, and every fixture with what you said to it. Your captain sees both when picking the side.</p>
      </section>

      {error && <p className="error">{error}</p>}

      {guide && (
        <section className="panel guide-card" aria-labelledby="av-guide-title">
          <div className="guide-card-head">
            <h2 id="av-guide-title">Reading your calendar</h2>
            <button className="btn ghost sm" type="button" onClick={dismissGuide}>
              Got it
            </button>
          </div>
          <ol className="guide-steps">
            <li>
              <span className="guide-num" aria-hidden>1</span>
              <div>
                <strong>Tap a day, say if you&rsquo;re free</strong>
                <p>The colour of the day is your general availability.</p>
              </div>
            </li>
            <li>
              <span className="guide-num" aria-hidden>2</span>
              <div>
                <strong>Fixtures sit on their day</strong>
                <p>
                  Each in the colour of your answer — two matches on one day are two marks, each answered on
                  its own.
                </p>
              </div>
            </li>
            <li>
              <span className="guide-num" aria-hidden>3</span>
              <div>
                <strong>Same every week?</strong>
                <p>Set a whole weekday for the month at the bottom, then fix the odd day.</p>
              </div>
            </li>
          </ol>
        </section>
      )}

      <div className="avail-layout">
        <div className="panel avail-cal">
          <div className="cal-head">
            <button className="btn ghost sm" type="button" onClick={() => step(-1)} aria-label="Previous month">
              <Icon name="arrowLeft" size={16} />
            </button>
            <h2>{month.toLocaleDateString("en-GB", { month: "long", year: "numeric" })}</h2>
            <div className="cal-head-end">
              <button className="btn ghost sm" type="button" onClick={toToday}>
                Today
              </button>
              <button className="btn ghost sm" type="button" onClick={() => step(1)} aria-label="Next month">
                <Icon name="arrowLeft" size={16} className="flip" />
              </button>
            </div>
          </div>

          {unanswered.length > 0 && (
            <button
              type="button"
              className="avail-needs"
              onClick={() => setChosen(dayKey(new Date(unanswered[0].start_at)))}
            >
              <span className="guide-num" aria-hidden>{unanswered.length}</span>
              {unanswered.length === 1 ? "fixture" : "fixtures"} in {monthName} {unanswered.length === 1 ? "needs" : "need"} your
              answer — show me
            </button>
          )}

          {loading ? (
            <div className="skeleton" style={{ height: 320 }} />
          ) : (
            <div className="cal-grid" role="grid" aria-label="Your availability and fixtures">
              {WEEKDAYS.map((d) => (
                <span key={d} className="cal-weekday" role="columnheader">
                  {d}
                </span>
              ))}
              {cells.map((date, i) => {
                if (!date) return <span key={`blank-${i}`} className="cal-blank" />;
                const key = dayKey(date);
                const status = days[key]?.status;
                const playing = fixturesOn.get(key) ?? [];
                return (
                  <button
                    key={key}
                    type="button"
                    role="gridcell"
                    aria-selected={key === chosen}
                    className={[
                      "cal-day",
                      status ? `is-${status}` : "",
                      key === today ? "today" : "",
                      key === chosen ? "chosen" : "",
                      key < today ? "gone" : "",
                    ]
                      .filter(Boolean)
                      .join(" ")}
                    aria-label={`${date.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })} — ${status ? AVAILABILITY_LABEL[status] : "not said"}${playing.map((f) => `; ${f.title} at ${timeOf(f.start_at)}: ${saidLabel(f.my_answer)}`).join("")}`}
                    onClick={() => setChosen(key)}
                  >
                    <span className="cal-num num">{date.getDate()}</span>
                    {playing.length > 0 && (
                      <span className="cal-fxs" aria-hidden>
                        {playing.slice(0, 3).map((f) => (
                          <span key={f.event_id} className={`cal-fx is-${f.my_answer ?? "none"}`}>
                            <span className="cal-fx-text">
                              {timeOf(f.start_at)} {f.title}
                            </span>
                          </span>
                        ))}
                        {playing.length > 3 && <span className="cal-fx-more">+{playing.length - 3}</span>}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          )}

          <div className="cal-key">
            {STATUSES.map((s) => (
              <span key={s} className="cal-key-item">
                <span className={`cal-swatch is-${s}`} aria-hidden /> {AVAILABILITY_LABEL[s]} day
              </span>
            ))}
            <span className="cal-key-item">
              <span className="cal-fx is-going key" aria-hidden /> Fixture: you&rsquo;re available
            </span>
            <span className="cal-key-item">
              <span className="cal-fx is-maybe key" aria-hidden /> Maybe
            </span>
            <span className="cal-key-item">
              <span className="cal-fx is-not_going key" aria-hidden /> Can&rsquo;t play
            </span>
            <span className="cal-key-item">
              <span className="cal-fx is-none key" aria-hidden /> Not answered
            </span>
          </div>
        </div>

        <aside className="panel avail-day" aria-labelledby="avail-day-title">
          <h2 id="avail-day-title">{dayTitle(chosen)}</h2>

          <div className="avail-day-block">
            <p className="avail-label">Are you free this day?</p>
            <div className="fx-seg" role="radiogroup" aria-label="Your availability this day">
              {STATUSES.map((s) => (
                <button
                  key={s}
                  type="button"
                  role="radio"
                  aria-checked={chosenStatus === s}
                  className={`fx-seg-btn is-${s}${chosenStatus === s ? " on" : ""}`}
                  disabled={busy === chosen}
                  onClick={() => setDay(chosen, s)}
                >
                  {AVAILABILITY_LABEL[s]}
                </button>
              ))}
            </div>
          </div>

          <div className="avail-day-block">
            <p className="avail-label">
              {chosenFixtures.length === 0
                ? "No fixtures this day"
                : chosenFixtures.length === 1
                  ? "1 fixture"
                  : `${chosenFixtures.length} fixtures — answer each one`}
            </p>
            {chosenStatus === "unavailable" && chosenFixtures.some((f) => f.my_answer === "going") && (
              <p className="fx-warn">You&rsquo;ve marked the day not available, but said yes to a fixture on it.</p>
            )}
            <ul className="avail-fixtures">
              {chosenFixtures.map((f) => (
                <li key={f.event_id} className={`avail-fixture is-${f.my_answer ?? "none"}`}>
                  <div className="avail-fixture-head">
                    <span className="num avail-fixture-time">{timeOf(f.start_at)}</span>
                    <Link href={`/events/${f.event_id}`} className="avail-fixture-title">
                      {f.title}
                    </Link>
                  </div>
                  <p className="subtle">
                    {f.club_name}
                    {f.venue_name ? ` · ${f.venue_name}` : ""} · {saidLabel(f.my_answer)}
                  </p>
                  {Date.parse(f.end_at) > Date.now() && (
                    <FixtureAnswer
                      eventId={f.event_id}
                      answer={f.my_answer}
                      onAnswered={(a) => setAnswer(f.event_id, a)}
                      label={`Can you play ${f.title}?`}
                    />
                  )}
                </li>
              ))}
            </ul>
          </div>
        </aside>
      </div>

      <div className="panel">
        <h2>A whole month at once</h2>
        <p className="muted">
          Most people are the same every week. Set every Sunday in {monthName}, then fix the odd one.
        </p>
        <div className="cal-bulk">
          {WEEKDAYS.map((label, weekday) => (
            <div key={label} className="cal-bulk-row">
              <span className="cal-bulk-day">{label}</span>
              {STATUSES.map((s) => (
                <button
                  key={s}
                  type="button"
                  className={`chip is-${s}`}
                  disabled={busy === "bulk"}
                  onClick={() => setEvery(weekday, s)}
                >
                  {AVAILABILITY_LABEL[s]}
                </button>
              ))}
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}

function blank(date: string): Availability {
  return { id: "", user_id: "", date, status: "available", note: null, recurrence_rule: null };
}
