"use client";

/// Scores from the wider game, as a card and as a home page panel.
///
/// Deliberately not styled like the club's own "In progress" panel above it.
/// Somebody glancing at their dashboard has to be able to tell at once that
/// India are 307 for 5 and their own third XI are not — two "Live" badges of
/// the same colour on one screen would say the opposite.

import Link from "next/link";
import { useEffect, useState } from "react";
import { Icon } from "@/components/Icon";
import {
  formatLabel,
  freshness,
  startLabel,
  worldScores,
  type WorldMatch,
  type WorldScores as Scores,
} from "@/lib/scores";
import { useT } from "@/lib/i18n/provider";

/// One side of a match: badge, name, and what they have made.
function TeamLine({
  name,
  short,
  logo,
  score,
  info,
  batting,
}: {
  name: string;
  short?: string | null;
  logo?: string | null;
  score?: string | null;
  info?: string | null;
  batting: boolean;
}) {
  return (
    <div className={`score-team${batting ? " batting" : ""}`}>
      {logo ? (
        // Plain <img>: the badges are served from the feed's own host, which
        // the next/image loader would have to be told about at build time.
        // eslint-disable-next-line @next/next/no-img-element
        <img className="score-badge" src={logo} alt="" width={28} height={28} loading="lazy" />
      ) : (
        <span className="score-badge placeholder" aria-hidden>
          {(short || name).slice(0, 2).toUpperCase()}
        </span>
      )}
      <span className="score-team-name">
        {/* The name truncates; the label must not. With both in one clipped
            span, "Maiwand Champions · batting" rendered as "Maiwand
            Champions · b…", which reads as a broken word rather than a fact
            about the match. */}
        <span className="score-team-label">{name}</span>
        {/* Not a colour or a bold weight alone: a screen reader has to be able
            to say which side is in. */}
        {batting && <span className="score-batting">· batting</span>}
      </span>
      <span className="score-runs">
        <strong>{score || "—"}</strong>
        {info && <span className="score-overs">{info}</span>}
      </span>
    </div>
  );
}

/// A single match, in the shape a scorecard is normally read in: who, what
/// they made, and then the sentence that says where the game stands.
export function ScoreCard({ match, href }: { match: WorldMatch; href?: string }) {
  const live = match.phase === "live";
  const format = formatLabel(match.format);
  const start = match.phase === "pending" ? startLabel(match.start_time) : null;
  // The side with an over count against it is the side at the crease. The feed
  // does not say so outright, but it only ever fills that field in for them.
  const homeBatting = live && !!match.home_info;
  const awayBatting = live && !!match.away_info;

  const card = (
    <article className={`score-card${live ? " is-live" : ""}${href ? " is-link" : ""}`}>
      <header className="score-card-head">
        <span className="score-league" title={match.league_name}>
          {match.league_name}
        </span>
        <span className={`ws-state ${match.phase}`}>
          {live && <span className="score-dot" aria-hidden />}
          {match.state}
        </span>
      </header>

      <div className="score-teams">
        <TeamLine
          name={match.home_team_name}
          short={match.home_team_short}
          logo={match.home_team_logo}
          score={match.home_score}
          info={match.home_info}
          batting={homeBatting}
        />
        <TeamLine
          name={match.away_team_name}
          short={match.away_team_short}
          logo={match.away_team_logo}
          score={match.away_score}
          info={match.away_info}
          batting={awayBatting}
        />
      </div>

      {match.report && <p className="score-report">{match.report}</p>}

      <footer className="score-meta">
        {format && <span className="score-chip">{format}</span>}
        {start && <span>Starts {start}</span>}
        {match.country_name && <span>{match.country_name}</span>}
      </footer>
    </article>
  );

  // The whole card is the target, not a "more" link tucked in a corner: on a
  // phone the card is what a thumb is already aiming at.
  return href ? (
    <Link href={href} className="score-link" aria-label={`${match.home_team_name} v ${match.away_team_name}, full scorecard`}>
      {card}
    </Link>
  ) : (
    card
  );
}

/// The home page panel: what is being played right now, or what is on next.
///
/// Hidden entirely when the feed is off or has nothing — a dashboard is not
/// improved by a panel explaining that it is empty.
export function WorldScoresPanel() {
  const t = useT();
  const [scores, setScores] = useState<Scores | null>(null);

  useEffect(() => {
    let alive = true;
    const load = () =>
      worldScores()
        .then((s) => alive && setScores(s))
        .catch(() => alive && setScores(null));
    load();
    // The server refreshes from the feed every few minutes at best, so asking
    // it more often than this would only cost queries to be told the same
    // thing. Nothing here reaches the score provider.
    //
    // Only while the tab is actually in front of somebody, though. Reading the
    // scores is what tells the server a person is watching, and that is what
    // makes it poll the feed every few minutes instead of every quarter of an
    // hour — so a tab left open overnight would spend the next day's whole
    // allowance on an empty room.
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") load();
    }, 120_000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);

  if (!scores?.enabled) return null;
  const showing = scores.live.length > 0 ? scores.live : scores.upcoming;
  if (showing.length === 0) return null;

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("sr.around_the_world")}</h2>
        <Link href="/scores">All scores →</Link>
      </div>
      <p className="panel-note">
        {scores.live.length > 0
          ? t("le.internationals_and_domestic_cricket_be")
          : t("le.no_international_or_domestic_cricket_o")}
      </p>
      <div className="score-list">
        {showing.slice(0, 3).map((m) => (
          <ScoreCard key={m.id} match={m} href={`/scores/${m.id}`} />
        ))}
      </div>
      <p className="score-asof">
        <Icon name="clock" size={14} /> {t("sr.scores_updated", { when: freshness(scores.as_of, t) })}
      </p>
    </div>
  );
}
