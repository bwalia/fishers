"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  API_ORIGIN,
  api,
  getAccessToken,
  getStoredUser,
  type Club,
  type EventRow,
  type PublicUser,
} from "@/lib/api";

export default function HomePage() {
  const [user, setUser] = useState<PublicUser | null>(null);
  const [clubs, setClubs] = useState<Club[]>([]);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setUser(getStoredUser());
    if (!getAccessToken()) return;
    (async () => {
      try {
        const [c, e] = await Promise.all([
          api<Club[]>("GET", "/clubs"),
          api<EventRow[]>("GET", "/events"),
        ]);
        setClubs(c);
        setEvents(e.slice(0, 6));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      }
    })();
  }, []);

  return (
    <main>
      <section className="hero">
        <h1>Club dashboard</h1>
        <p>
          Fixtures, shop and club ops in the browser — same API as the iOS app.
          {user ? ` Signed in as ${user.name}.` : " Sign in to load your clubs."}
        </p>
      </section>

      {!user && (
        <div className="panel">
          <p className="muted">
            Demo: <code>demo@fishers.test</code> / <code>password123</code>
          </p>
          <p style={{ marginTop: 12 }}>
            <Link className="btn primary" href="/login">
              Sign in
            </Link>
          </p>
        </div>
      )}

      {error && <p className="error">{error}</p>}

      {user && (
        <div className="grid cards">
          <div className="panel">
            <h2>Clubs</h2>
            <p className="muted">{clubs.length} memberships</p>
            <ul className="list" style={{ marginTop: 12, padding: 0, listStyle: "none" }}>
              {clubs.map((c) => (
                <li key={c.id} className="row">
                  <span>{c.name}</span>
                  <span className="tag">{c.sport_types?.[0] ?? "club"}</span>
                </li>
              ))}
            </ul>
            <p style={{ marginTop: 14 }}>
              <Link href="/clubs">Open clubs →</Link>
            </p>
          </div>
          <div className="panel">
            <h2>Upcoming fixtures</h2>
            <div className="list">
              {events.map((e) => (
                <div key={e.id} className="row">
                  <div>
                    <div>{e.title}</div>
                    <div className="tag">{e.event_subtype.replaceAll("_", " ")}</div>
                  </div>
                  <div className="muted">
                    {new Date(e.start_at).toLocaleDateString("en-GB", {
                      day: "numeric",
                      month: "short",
                    })}
                  </div>
                </div>
              ))}
              {events.length === 0 && <p className="muted">No fixtures yet.</p>}
            </div>
            <p style={{ marginTop: 14 }}>
              <Link href="/events">All fixtures →</Link>
            </p>
          </div>
          <div className="panel">
            <h2>Shop & API</h2>
            <p className="muted">
              Browse cricket kit, shoes, balls and clubwear seeded for each club.
            </p>
            <p style={{ marginTop: 14, display: "flex", gap: 10, flexWrap: "wrap" }}>
              <Link className="btn primary" href="/shop">
                Open shop
              </Link>
              <a className="btn" href={`${API_ORIGIN}/swagger-ui`} target="_blank" rel="noreferrer">
                Swagger UI
              </a>
            </p>
          </div>
        </div>
      )}
    </main>
  );
}
