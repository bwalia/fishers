"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import {
  api,
  getAccessToken,
  getStoredUser,
  needsQuickStart,
  saveUser,
  type Club,
  type EventRow,
  type Page,
  type PublicUser,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { GettingStarted } from "@/components/GettingStarted";
import { Landing } from "@/components/Landing";
import { PendingInvites } from "@/components/PendingInvites";
import { RoleChooser } from "@/components/RoleChooser";
import { PushPrompt } from "@/components/PushPrompt";
import { ProfileStrength } from "@/components/ProfileStrength";
import { WorldScoresPanel } from "@/components/WorldScores";
import { overs, type MatchResponse } from "@/lib/cricket";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

export default function HomePage() {
  const t = useT();
  const router = useRouter();
  const [user, setUser] = useState<PublicUser | null>(null);
  const [clubs, setClubs] = useState<Club[]>([]);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [live, setLive] = useState<MatchResponse[]>([]);
  const [error, setError] = useState<string | null>(null);
  /// Until the first load lands, "no clubs" and "not asked yet" look the
  /// same — and showing a new-here screen to somebody with four clubs, for
  /// half a second, is worse than showing nothing.
  const [loaded, setLoaded] = useState(false);
  const [invitesCount, setInvitesCount] = useState(0);
  /// Whether storage has been read. Before that a member and a visitor look
  /// alike, and a member should not see the sales page flash past.
  const [checked, setChecked] = useState(false);

  const load = useCallback(async () => {
    {
      try {
        const [c, e, me] = await Promise.all([
          api<Club[]>("GET", "/clubs"),
          api<Page<EventRow>>("GET", "/events?per_page=50").then((p) => p.items),
          // The stored copy predates anything changed on another device —
          // a role chosen on the phone, an email confirmed from the inbox.
          api<PublicUser>("GET", "/me").catch(() => null),
        ]);
        if (me) {
          saveUser(me);
          setUser(me);
          // Once, and skippable: a sport and a number before the dashboard.
          // Only from the dashboard itself: this answer can land after they
          // have already clicked away, and must not pull them back.
          if (needsQuickStart(me) && window.location.pathname === "/") router.replace("/welcome");
        }
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
        setError(err instanceof Error ? err.message : t("le.failed_to_load"));
      } finally {
        setLoaded(true);
      }
    }
  }, [router, t]);

  useEffect(() => {
    setUser(getStoredUser());
    setChecked(true);
    if (!getAccessToken()) return;
    load();
  }, [load]);

  const upcoming = events
    .filter((e) => new Date(e.start_at).getTime() > Date.now())
    .sort((a, b) => a.start_at.localeCompare(b.start_at));

  if (!checked) return <main id="main" />;
  if (!user) return <Landing />;

  return (
    <main id="main">
      <section className="hero dash-hero">
        <h1>{`${greeting()}, ${user.name.split(" ")[0]}`}</h1>
        <p>
          {clubs.length > 0
            ? t("le.your_club_at_a_glance_what_s_next_what")
            : `Welcome to ${brand.name}. A few quick steps and you're up and running.`}
        </p>
      </section>

      {error && <p className="error">{error}</p>}

      <PendingInvites onJoined={load} onCount={setInvitesCount} />
      {loaded && <PushPrompt />}

      {loaded && !user.role_intent && clubs.length === 0 && (
        <section className="panel welcome" aria-labelledby="welcome-title">
          <h2 id="welcome-title">{t("fin.how_will_you_use", { brand: brand.name })}</h2>
          <p className="muted">
            We&apos;ll show you exactly what to do next. You can switch later.
          </p>
          <RoleChooser onPicked={(u) => u && setUser(u)} />
        </section>
      )}

      {loaded && user.role_intent && (
        <GettingStarted
          user={user}
          clubs={clubs}
          eventsCount={events.length}
          invitesCount={invitesCount}
          onUserChange={(u) => {
            setUser(u);
            load();
          }}
        />
      )}

      {loaded && <ProfileStrength user={user} />}

      {clubs.length > 0 && (
        <>
          <div className="grid" style={{ marginBottom: "var(--s4)" }}>
            <div className="stat primary">
              <div className="stat-label">Clubs</div>
              <div className="stat-value">{clubs.length}</div>
              <div className="stat-sub">{t("rest.memberships_2")}</div>
            </div>
            <div className="stat">
              <div className="stat-label">{t("rest.upcoming")}</div>
              <div className="stat-value">{upcoming.length}</div>
              <div className="stat-sub">{t("rest.fixtures_ahead_2")}</div>
            </div>
            <div className="stat accent">
              <div className="stat-label">{t("rest.in_progress")}</div>
              <div className="stat-value">{live.length}</div>
              <div className="stat-sub">{t("rest.matches_to_score")}</div>
            </div>
          </div>

          {live.length > 0 && (
            <div className="panel">
              <div className="panel-head">
                <h2>{t("rest.in_progress")}</h2>
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
                      {m.can_score ? t("le.resume_scoring") : t("le.watch")}
                    </Link>
                  </div>
                );
              })}
            </div>
          )}

          {/* The club's own matches come first and are a different shape on
              purpose; this is the rest of the world's cricket. */}
          <WorldScoresPanel />

          <div className="panel">
            <div className="panel-head">
              <h2>{t("rest.next_fixtures")}</h2>
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
                <p>{t("rest.nothing_scheduled")}</p>
              </div>
            )}
          </div>

          <div className="grid cards">
            <Quick href="/score" icon="bat" title="Score a match" body={t("le.start_a_fixture_or_pick_up_one_under_w")} />
            <Quick href="/stats" icon="chart" title="Season stats" body={t("le.batting_bowling_and_club_results")} />
            <Quick href="/shop" icon="shop" title="Club shop" body={t("le.kit_clubwear_and_hire")} />
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

/// Morning, afternoon, evening — by the viewer's own clock.
function greeting() {
  const h = new Date().getHours();
  return h < 12 ? "le.good_morning" : h < 18 ? "le.good_afternoon" : "le.good_evening";
}
