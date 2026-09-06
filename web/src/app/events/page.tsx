"use client";

import { useEffect, useState } from "react";
import { api, getAccessToken, type EventRow } from "@/lib/api";

export default function EventsPage() {
  const [events, setEvents] = useState<EventRow[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view fixtures.");
      return;
    }
    (async () => {
      try {
        setEvents(await api<EventRow[]>("GET", "/events"));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      }
    })();
  }, []);

  return (
    <main>
      <section className="hero">
        <h1>Fixtures</h1>
        <p>Upcoming nets, league matches and socials across your clubs.</p>
      </section>
      {error && <p className="error">{error}</p>}
      <div className="panel">
        {events.map((e) => (
          <div key={e.id} className="row">
            <div>
              <div>{e.title}</div>
              <div className="tag">{e.sport} · {e.event_subtype.replaceAll("_", " ")}</div>
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
            {e.fee_amount_cents != null && (
              <div className="price">£{(e.fee_amount_cents / 100).toFixed(0)}</div>
            )}
          </div>
        ))}
        {!error && events.length === 0 && <p className="muted">No fixtures.</p>}
      </div>
    </main>
  );
}
