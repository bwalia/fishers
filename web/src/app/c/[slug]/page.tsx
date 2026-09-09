"use client";

import { use, useEffect, useState } from "react";
import { apiV1 } from "@/lib/api";

type ClubPage = {
  club: {
    id: string;
    name: string;
    slug: string | null;
    sport_types: string[];
    tagline: string | null;
    about: string | null;
    ground: string | null;
    founded_year: number | null;
    contact_email: string | null;
    website: string | null;
  };
  record: {
    season: number;
    played: number;
    won: number;
    lost: number;
    drawn: number;
    no_result: number;
    win_percent: number | null;
  } | null;
  top_batters: { player_name?: string; runs?: number; wickets?: number }[];
  top_bowlers: { player_name?: string; runs?: number; wickets?: number }[];
  fixtures: { title: string; start_at: string }[];
};

/// A club's own page, for anybody at all.
///
/// No login, no chrome from the app — a club that wants a public site should
/// not have to go and build one, so this is the site: who they are, the record
/// they have played to, who is scoring the runs, and when they are next out.
export default function PublicClubPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = use(params);
  const [page, setPage] = useState<ClubPage | null>(null);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    (async () => {
      // Deliberately not the authenticated helper: a visitor has no session,
      // and a 401 refresh dance would be the wrong behaviour here.
      const res = await fetch(`${apiV1()}/public/clubs/${encodeURIComponent(slug)}`);
      if (!res.ok) return setMissing(true);
      setPage(await res.json());
    })();
  }, [slug]);

  if (missing)
    return (
      <main className="club-site">
        <div className="club-empty">
          <h1>No club here</h1>
          <p>That address does not belong to a club, or its page is not published.</p>
        </div>
      </main>
    );

  if (!page)
    return (
      <main className="club-site">
        <div className="skeleton" style={{ height: 320 }} />
      </main>
    );

  const { club, record } = page;

  return (
    <main className="club-site">
      <header className="club-hero">
        <p className="club-eyebrow">
          {club.sport_types.join(" · ")}
          {club.founded_year && ` · est. ${club.founded_year}`}
        </p>
        <h1>{club.name}</h1>
        {club.tagline && <p className="club-tagline">{club.tagline}</p>}
        {club.ground && (
          <p className="club-ground">
            <PinIcon /> {club.ground}
          </p>
        )}
      </header>

      {record && record.played > 0 && (
        <section className="club-record" aria-label={`${record.season} season record`}>
          {/* The number every club leads with, and the three that back it up. */}
          <div className="record-headline">
            <span className="record-pct num">{record.win_percent ?? "—"}%</span>
            <span className="record-label">
              won in {record.season}
              <small>
                {record.no_result > 0 && `${record.no_result} no result — not counted`}
              </small>
            </span>
          </div>
          <dl className="record-grid">
            <div><dt>Played</dt><dd className="num">{record.played}</dd></div>
            <div><dt>Won</dt><dd className="num">{record.won}</dd></div>
            <div><dt>Lost</dt><dd className="num">{record.lost}</dd></div>
            <div><dt>Drawn</dt><dd className="num">{record.drawn}</dd></div>
          </dl>
        </section>
      )}

      {club.about && (
        <section className="club-about prose">
          <h2>About the club</h2>
          {club.about.split("\n").filter(Boolean).map((line, i) => (
            <p key={i}>{line}</p>
          ))}
        </section>
      )}

      {(page.top_batters.length > 0 || page.top_bowlers.length > 0) && (
        <section className="club-players">
          <h2>Leading the way</h2>
          <div className="player-cols">
            {page.top_batters.length > 0 && (
              <div>
                <h3>Runs</h3>
                <ol className="club-leaders">
                  {page.top_batters.slice(0, 5).map((p, i) => (
                    <li key={i}>
                      <span>{p.player_name ?? "A player"}</span>
                      <span className="num">{p.runs ?? 0}</span>
                    </li>
                  ))}
                </ol>
              </div>
            )}
            {page.top_bowlers.length > 0 && (
              <div>
                <h3>Wickets</h3>
                <ol className="club-leaders">
                  {page.top_bowlers.slice(0, 5).map((p, i) => (
                    <li key={i}>
                      <span>{p.player_name ?? "A player"}</span>
                      <span className="num">{p.wickets ?? 0}</span>
                    </li>
                  ))}
                </ol>
              </div>
            )}
          </div>
        </section>
      )}

      {page.fixtures.length > 0 && (
        <section className="club-fixtures">
          <h2>Next up</h2>
          <ul className="club-leaders">
            {page.fixtures.map((f, i) => (
              <li key={i}>
                <span>{f.title}</span>
                <span className="subtle">
                  {new Date(f.start_at).toLocaleDateString("en-GB", {
                    weekday: "short",
                    day: "numeric",
                    month: "short",
                  })}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="club-join">
        <h2>Fancy a game?</h2>
        <p>New players are welcome. Get in touch and come down.</p>
        <div className="club-join-actions">
          {club.contact_email && (
            <a className="btn primary lg" href={`mailto:${club.contact_email}`}>
              Email the club
            </a>
          )}
          {club.website && (
            <a className="btn" href={club.website} rel="noreferrer noopener" target="_blank">
              Their website
            </a>
          )}
        </div>
      </section>

      <footer className="club-foot">
        Fixtures and figures kept on Fishers.
      </footer>
    </main>
  );
}

function PinIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden
         fill="none" stroke="currentColor" strokeWidth="1.8"
         strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
      <circle cx="12" cy="10" r="3" />
    </svg>
  );
}
