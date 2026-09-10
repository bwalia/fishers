"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, getAccessToken, readErr, type EventRow, type Page } from "@/lib/api";
import {
  AVAILABILITY_LABEL,
  dayKey,
  monthGrid,
  nextStatus,
  weekdaysIn,
  WEEKDAYS,
  type Availability,
  type AvailabilityStatus,
} from "@/lib/availability";
import { Icon } from "@/components/Icon";

/// When you can play.
///
/// One tap moves a day on: available → maybe → not available → available. The
/// same cycle as the phone, because a player who sets Sundays on the app and
/// checks them here should find the two agree.
///
/// Fixtures are drawn underneath, so nobody marks themselves off on a day
/// their club is playing without seeing it.
export default function AvailabilityPage() {
  const [month, setMonth] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });
  const [days, setDays] = useState<Record<string, Availability>>({});
  const [fixtures, setFixtures] = useState<EventRow[]>([]);
  const [chosen, setChosen] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const cells = useMemo(() => monthGrid(month), [month]);

  const load = useCallback(async () => {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const last = new Date(month.getFullYear(), month.getMonth() + 1, 0);
    try {
      const [mine, events] = await Promise.all([
        api<Availability[]>(
          "GET",
          `/availability?from=${dayKey(first)}&to=${dayKey(last)}`
        ),
        api<Page<EventRow>>("GET", "/events?per_page=100").catch(() => ({ items: [] as EventRow[] })),
      ]);
      setDays(Object.fromEntries(mine.map((a) => [a.date, a])));
      setFixtures(events.items);
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

  const fixturesOn = useCallback(
    (key: string) => fixtures.filter((f) => dayKey(new Date(f.start_at)) === key),
    [fixtures]
  );

  const cycle = async (date: Date) => {
    const key = dayKey(date);
    const status = nextStatus(days[key]?.status);
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
      setDays((prev) => ({
        ...prev,
        ...Object.fromEntries(saved.map((a) => [a.date, a])),
      }));
    } catch (err) {
      setError(readErr(err, "Could not set those days"));
    } finally {
      setBusy(null);
    }
  };

  const step = (by: number) =>
    setMonth((m) => new Date(m.getFullYear(), m.getMonth() + by, 1));

  const today = dayKey(new Date());
  const chosenDay = chosen ? days[chosen] : undefined;

  return (
    <main id="main">
      <section className="hero">
        <h1>When you can play</h1>
        <p>
          Tap a day to move it on. Your captain sees this when picking a side — and so does
          the assistant, so you can say it in the chat instead.
        </p>
      </section>

      {error && <p className="error">{error}</p>}

      <div className="panel">
        <div className="cal-head">
          <button className="btn ghost sm" type="button" onClick={() => step(-1)}
                  aria-label="Previous month">
            <Icon name="arrowLeft" size={16} />
          </button>
          <h2>
            {month.toLocaleDateString("en-GB", { month: "long", year: "numeric" })}
          </h2>
          <button className="btn ghost sm" type="button" onClick={() => step(1)}
                  aria-label="Next month">
            <Icon name="arrowLeft" size={16} className="flip" />
          </button>
        </div>

        {loading ? (
          <div className="skeleton" style={{ height: 320 }} />
        ) : (
          <>
            <div className="cal-grid" role="grid" aria-label="Your availability">
              {WEEKDAYS.map((d) => (
                <span key={d} className="cal-weekday" role="columnheader">{d}</span>
              ))}
              {cells.map((date, i) => {
                if (!date) return <span key={`blank-${i}`} className="cal-blank" />;
                const key = dayKey(date);
                const status = days[key]?.status;
                const playing = fixturesOn(key);
                return (
                  <button
                    key={key}
                    type="button"
                    role="gridcell"
                    className={[
                      "cal-day",
                      status ? `is-${status}` : "",
                      key === today ? "today" : "",
                      key === chosen ? "chosen" : "",
                    ].filter(Boolean).join(" ")}
                    disabled={busy === key}
                    aria-label={`${date.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })} — ${status ? AVAILABILITY_LABEL[status] : "not said"}${playing.length ? `, ${playing.length} fixture` : ""}`}
                    onClick={() => { setChosen(key); void cycle(date); }}
                  >
                    <span className="num">{date.getDate()}</span>
                    {playing.length > 0 && <span className="cal-fixture" aria-hidden />}
                  </button>
                );
              })}
            </div>

            <div className="cal-key">
              {(["available", "maybe", "unavailable"] as AvailabilityStatus[]).map((s) => (
                <span key={s} className="cal-key-item">
                  <span className={`cal-swatch is-${s}`} aria-hidden /> {AVAILABILITY_LABEL[s]}
                </span>
              ))}
              <span className="cal-key-item">
                <span className="cal-swatch has-fixture" aria-hidden /> Fixture that day
              </span>
            </div>
          </>
        )}
      </div>

      {chosen && (
        <div className="panel">
          <h2>
            {new Date(chosen).toLocaleDateString("en-GB", {
              weekday: "long", day: "numeric", month: "long",
            })}
          </h2>
          <p className="muted">
            {chosenDay ? AVAILABILITY_LABEL[chosenDay.status] : "You have not said."}
          </p>
          {fixturesOn(chosen).map((f) => (
            <p key={f.id}>
              <Icon name="calendar" size={14} /> {f.title}
            </p>
          ))}
        </div>
      )}

      <div className="panel">
        <h2>A whole month at once</h2>
        <p className="muted">
          Most people are the same every week. Set every Sunday in{" "}
          {month.toLocaleDateString("en-GB", { month: "long" })}, then fix the odd one.
        </p>
        <div className="cal-bulk">
          {WEEKDAYS.map((label, weekday) => (
            <div key={label} className="cal-bulk-row">
              <span className="cal-bulk-day">{label}</span>
              {(["available", "maybe", "unavailable"] as AvailabilityStatus[]).map((s) => (
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
  return {
    id: "", user_id: "", date, status: "available", note: null, recurrence_rule: null,
  };
}
