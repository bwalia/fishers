"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, type EventRow } from "@/lib/api";
import { Icon, type IconName } from "@/components/Icon";

const SUBTYPE_ICON: Record<string, IconName> = {
  league_match: "trophy",
  nets: "bat",
  social: "users",
};

function when(iso: string) {
  return new Date(iso).toLocaleString("en-GB", {
    weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

export default function EventsPage() {
  const [events, setEvents] = useState<EventRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view fixtures.");
      setLoading(false);
      return;
    }
    (async () => {
      try {
        setEvents(await api<EventRow[]>("GET", "/events"));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  return (
    <main id="main">
      <section className="hero">
        <h1>Fixtures</h1>
        <p>Nets, league matches and socials across your clubs.</p>
      </section>

      {error && <p className="error">{error}</p>}

      <div className="panel">
        {loading && <div className="skeleton" style={{ height: 64 }} />}
        {events.map((e) => (
          <div key={e.id} className="row">
            <div>
              <div style={{ fontWeight: 600 }}>{e.title}</div>
              <div style={{ display: "flex", gap: "var(--s2)", alignItems: "center", marginTop: 2 }}>
                <span className="tag">
                  <Icon name={SUBTYPE_ICON[e.event_subtype] ?? "calendar"} size={12} />
                  {e.event_subtype.replaceAll("_", " ")}
                </span>
                <span className="muted">{when(e.start_at)}</span>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--s3)" }}>
              {e.fee_amount_cents != null && (
                <span className="price">£{(e.fee_amount_cents / 100).toFixed(0)}</span>
              )}
              {e.sport === "cricket" && (
                <Link className="btn sm" href="/score">Score</Link>
              )}
            </div>
          </div>
        ))}
        {!loading && !error && events.length === 0 && (
          <div className="empty">
            <Icon name="calendar" size={28} />
            <p>No fixtures yet.</p>
          </div>
        )}
      </div>
    </main>
  );
}
