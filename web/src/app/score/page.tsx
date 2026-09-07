"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api, getAccessToken, type EventRow } from "@/lib/api";
import type { MatchResponse } from "@/lib/cricket";

export default function ScoreIndexPage() {
  const router = useRouter();
  const [events, setEvents] = useState<EventRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [names, setNames] = useState<Record<string, { home: string; away: string }>>({});

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to score a match.");
      return;
    }
    (async () => {
      try {
        const all = await api<EventRow[]>("GET", "/events");
        setEvents(all.filter((e) => e.sport === "cricket"));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load fixtures");
      }
    })();
  }, []);

  const start = async (event: EventRow) => {
    setBusy(event.id);
    setError(null);
    try {
      const sides = names[event.id];
      // Create-or-get: opening a fixture that is already being scored just
      // returns it, so this is safe to click twice.
      const match = await api<MatchResponse>("POST", `/events/${event.id}/cricket-match`, {
        overs_limit: 20,
        home_name: sides?.home?.trim() || "Home",
        away_name: sides?.away?.trim() || "Away",
      });
      router.push(`/score/${match.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open the match");
      setBusy(null);
    }
  };

  return (
    <main>
      <section className="hero">
        <h1>Score a match</h1>
        <p>
          Pick a cricket fixture to start it. Setting up asks both captains to agree the
          overs, ground and ball before the toss.
        </p>
      </section>

      {error && <p className="error">{error}</p>}

      <div className="panel">
        {events.map((e) => (
          <div key={e.id} className="row">
            <div>
              <div>{e.title}</div>
              <div className="tag">{e.event_subtype.replaceAll("_", " ")}</div>
              <div className="muted">
                {new Date(e.start_at).toLocaleString("en-GB", {
                  weekday: "short",
                  day: "numeric",
                  month: "short",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </div>
            </div>
            <div className="select-row" style={{ margin: 0, gap: "0.4rem" }}>
              <input
                placeholder="Home side"
                value={names[e.id]?.home ?? ""}
                onChange={(ev) =>
                  setNames((n) => ({
                    ...n,
                    [e.id]: { home: ev.target.value, away: n[e.id]?.away ?? "" },
                  }))
                }
              />
              <input
                placeholder="Opposition"
                value={names[e.id]?.away ?? ""}
                onChange={(ev) =>
                  setNames((n) => ({
                    ...n,
                    [e.id]: { home: n[e.id]?.home ?? "", away: ev.target.value },
                  }))
                }
              />
              <button
                className="btn primary"
                type="button"
                disabled={busy === e.id}
                onClick={() => start(e)}
              >
                {busy === e.id ? "Opening…" : "Open"}
              </button>
            </div>
          </div>
        ))}
        {!error && events.length === 0 && (
          <p className="muted">No cricket fixtures. Create one under Fixtures first.</p>
        )}
      </div>
    </main>
  );
}
