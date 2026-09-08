"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  api,
  getAccessToken,
  getStoredUser,
  type Club,
  type EventRow,
  type PublicUser,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { overs, type MatchResponse } from "@/lib/cricket";

export default function HomePage() {
  const [user, setUser] = useState<PublicUser | null>(null);
  const [clubs, setClubs] = useState<Club[]>([]);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [live, setLive] = useState<MatchResponse[]>([]);
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
        setEvents(e);
        // Any cricket fixture may have a match on it; a 404 just means none.
        const matches = await Promise.all(
          e.filter((x) => x.sport === "cricket").map(async (x) => {
            try {
              return await api<MatchResponse>("GET", `/events/${x.id}/cricket-match`);
            } catch {
              return null;
            }
          })
        );
        setLive(matches.filter((m): m is MatchResponse => !!m && m.state.status !== "complete"));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      }
    })();
  }, []);

  const upcoming = events
    .filter((e) => new Date(e.start_at).getTime() > Date.now())
    .sort((a, b) => a.start_at.localeCompare(b.start_at));

  return (
    <main id="main">
      <section className="hero">
        <h1>Club dashboard</h1>
        <p>
          Fixtures, live cricket scoring, season stats and the club shop — the same API the
          iOS app uses.
          {user ? ` Signed in as ${user.name}.` : ""}
        </p>
      </section>

      {!user && (
        <div className="panel">
          <h2>Sign in to get started</h2>
          <p className="muted">
            Demo account: <code>demo@fishers.test</code> / <code>password123</code>
          </p>
          <Link className="btn primary" href="/login">
            <Icon name="signIn" size={16} /> Sign in
          </Link>
        </div>
      )}

      {error && <p className="error">{error}</p>}

      {user && (
        <>
          <div className="grid" style={{ marginBottom: "var(--s4)" }}>
            <div className="stat primary">
              <div className="stat-label">Clubs</div>
              <div className="stat-value">{clubs.length}</div>
              <div className="stat-sub">memberships</div>
            </div>
            <div className="stat">
              <div className="stat-label">Upcoming</div>
              <div className="stat-value">{upcoming.length}</div>
              <div className="stat-sub">fixtures ahead</div>
            </div>
            <div className="stat accent">
              <div className="stat-label">In progress</div>
              <div className="stat-value">{live.length}</div>
              <div className="stat-sub">matches to score</div>
            </div>
          </div>

          {live.length > 0 && (
            <div className="panel">
              <div className="panel-head">
                <h2>In progress</h2>
                <span className="tag live">Live</span>
              </div>
              {live.map((m) => {
                const inn = m.state.innings[m.state.innings.length - 1];
                return (
                  <div className="row" key={m.id}>
                    <div>
                      <div style={{ fontWeight: 600 }}>
                        {m.state.home_name} v {m.state.away_name}
                      </div>
                      <div className="muted">
                        {inn
                          ? `${inn.runs}/${inn.wickets} (${overs(inn.legal_balls)} ov)`
                          : "Not started"}
                      </div>
                    </div>
                    <Link className="btn primary sm" href={`/score/${m.id}`}>
                      {m.can_score ? "Resume scoring" : "Watch"}
                    </Link>
                  </div>
                );
              })}
            </div>
          )}

          <div className="panel">
            <div className="panel-head">
              <h2>Next fixtures</h2>
              <Link href="/events">All fixtures →</Link>
            </div>
            {upcoming.slice(0, 5).map((e) => (
              <div className="row" key={e.id}>
                <div>
                  <div style={{ fontWeight: 600 }}>{e.title}</div>
                  <div className="muted">
                    {new Date(e.start_at).toLocaleString("en-GB", {
                      weekday: "short", day: "numeric", month: "short",
                      hour: "2-digit", minute: "2-digit",
                    })}
                  </div>
                </div>
                <span className="tag">{e.event_subtype.replaceAll("_", " ")}</span>
              </div>
            ))}
            {upcoming.length === 0 && (
              <div className="empty">
                <Icon name="calendar" size={28} />
                <p>Nothing scheduled.</p>
              </div>
            )}
          </div>

          <div className="grid cards">
            <Quick href="/score" icon="bat" title="Score a match" body="Start a fixture or pick up one under way." />
            <Quick href="/stats" icon="chart" title="Season stats" body="Batting, bowling and club results." />
            <Quick href="/shop" icon="shop" title="Club shop" body="Kit, clubwear and hire." />
          </div>
        </>
      )}
    </main>
  );
}

function Quick({
  href, icon, title, body,
}: {
  href: string;
  icon: "bat" | "chart" | "shop";
  title: string;
  body: string;
}) {
  return (
    <Link href={href} className="panel" style={{ display: "block", marginBottom: 0 }}>
      <div style={{ color: "var(--primary)", marginBottom: "var(--s2)" }}>
        <Icon name={icon} size={22} />
      </div>
      <h3>{title}</h3>
      <p className="muted" style={{ margin: "var(--s1) 0 0" }}>{body}</p>
    </Link>
  );
}
