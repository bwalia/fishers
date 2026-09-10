"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  api,
  getAccessToken,
  getStoredUser,
  type Club,
  type EventRow,
  type Page,
  type PublicUser,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { PendingInvites } from "@/components/PendingInvites";
import { overs, type MatchResponse } from "@/lib/cricket";

/// The first screen after signing up.
///
/// Everything in Fishers hangs off a club — fixtures, chat, availability,
/// scoring — so somebody with none has nine screens that all say "your clubs"
/// and nothing to press. This is the one thing to do, and the two ways to do
/// it: start a club, or join one somebody already runs.
function FirstRun({ onJoined }: { onJoined: () => void }) {
  return (
    <>
      <PendingInvites onJoined={onJoined} />

      <div className="panel first-run">
        <Icon name="users" size={32} />
        <h2>You are not in a club yet</h2>
        <p className="muted">
          Fixtures, availability, the chat and scoring all belong to a club. Start yours,
          or join one that already exists.
        </p>
        <div className="field-row">
          <Link className="btn primary lg" href="/clubs">
            <Icon name="plus" size={18} /> Start a club
          </Link>
        </div>
        <p className="subtle">
          Been sent an invite link or a QR code? Open it and you are in — no need to start
          anything.
        </p>
      </div>

      <div className="grid cards">
        <div className="panel">
          <h3>While you are here</h3>
          <p className="muted">
            Set the days you can usually play. Your captain sees it the moment you join a
            club, so the first side they pick already knows about you.
          </p>
          <Link className="btn" href="/availability">
            <Icon name="clock" size={16} /> Set your availability
          </Link>
        </div>
        <div className="panel">
          <h3>Your profile</h3>
          <p className="muted">
            A photo and what you play. It is what a captain sees on the team sheet.
          </p>
          <Link className="btn" href="/profile">
            <Icon name="book" size={16} /> Fill in your profile
          </Link>
        </div>
      </div>
    </>
  );
}

export default function HomePage() {
  const [user, setUser] = useState<PublicUser | null>(null);
  const [clubs, setClubs] = useState<Club[]>([]);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [live, setLive] = useState<MatchResponse[]>([]);
  const [error, setError] = useState<string | null>(null);
  /// Until the first load lands, "no clubs" and "not asked yet" look the
  /// same — and showing a new-here screen to somebody with four clubs, for
  /// half a second, is worse than showing nothing.
  const [loaded, setLoaded] = useState(false);

  const load = useCallback(async () => {
    {
      try {
        const [c, e] = await Promise.all([
          api<Club[]>("GET", "/clubs"),
          api<Page<EventRow>>("GET", "/events?per_page=50").then((p) => p.items),
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
      } finally {
        setLoaded(true);
      }
    }
  }, []);

  useEffect(() => {
    setUser(getStoredUser());
    if (!getAccessToken()) return;
    load();
  }, [load]);

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

      {user && loaded && clubs.length === 0 && <FirstRun onJoined={load} />}

      {user && clubs.length > 0 && (
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
