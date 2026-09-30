"use client";

/// Scores from the wider game.
///
/// Everything on this page is read from our own API, which reads the score
/// provider on a budget of a hundred requests a day for the whole deployment.
/// That is why the page says how old the scores are instead of pretending to
/// be a broadcast: on the free allowance they are minutes behind, and a score
/// that is quietly stale is worse than one that admits its age.

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Icon } from "@/components/Icon";
import { ScoreCard } from "@/components/WorldScores";
import { useRequireAuth } from "@/lib/require-auth";
import { freshness, worldScores, type WorldScores } from "@/lib/scores";
import { useT } from "@/lib/i18n/provider";

export default function ScoresPage() {
  const t = useT();
  const authed = useRequireAuth();
  const [scores, setScores] = useState<WorldScores | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const load = useCallback(async () => {
    try {
      setScores(await worldScores());
      setError(null);
    } catch {
      setError(t("le.could_not_load_the_scores_try_again_in"));
    } finally {
      setLoaded(true);
    }
  }, [t]);

  useEffect(() => {
    if (!authed) return;
    load();
    // Our own API, not the score provider — this costs a database query, not
    // one of the day's hundred requests.
    //
    // Only while the tab is in front of somebody: reading the scores is what
    // tells the server a person is watching, and that is what makes it poll
    // the feed every few minutes rather than every quarter of an hour. A tab
    // left open overnight would spend tomorrow's allowance on an empty room.
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") load();
    }, 120_000);
    return () => clearInterval(timer);
  }, [authed, load]);

  if (!authed) return null;

  return (
    <main id="main">
      <section className="hero">
        <h1>{t("sr.cricket_scores")}</h1>
        <p>
          Internationals and domestic competitions from around the world. Your own club&apos;s
          matches are under <Link href="/score">{t("sr.score_a_match")}</Link>.
        </p>
      </section>

      {error && <div className="notice">{error}</div>}

      {loaded && scores && !scores.enabled && (
        <div className="empty">
          <Icon name="ball" size={28} />
          <p>World scores aren&apos;t switched on here.</p>
          <p className="muted">{t("sr.they_run_on_this_ring_only_when_a_scor")}</p>
        </div>
      )}

      {loaded && scores?.enabled && (
        <>
          <p className="score-asof">
            <Icon name="clock" size={14} /> Scores updated {freshness(scores.as_of)}. They come
            from a free feed and run a few minutes behind live play.
          </p>

          <Section
            title={t("sr.being_played_now")}
            note={t("le.matches_in_progress_including_the_inte")}
            matches={scores.live}
            empty={t("le.nothing_is_being_played_at_the_moment")}
          />
          <Section
            title={t("sr.coming_up")}
            note={t("le.due_to_start_soon")}
            matches={scores.upcoming}
            empty={t("le.no_fixtures_listed_for_the_next_few_da")}
          />
          <Section
            title={t("sr.recent_results")}
            note={t("le.matches_that_have_finished")}
            matches={scores.recent}
            empty={t("le.no_results_yet")}
          />
        </>
      )}

      {!loaded && <div className="empty"><p className="muted">{t("sr.loading_scores")}</p></div>}
    </main>
  );
}

/// One labelled group. The note under each heading is there because "live",
/// "upcoming" and "recent" mean slightly different things in cricket than in
/// other sports — a Test at stumps is still being played.
function Section({
  title,
  note,
  matches,
  empty,
}: {
  title: string;
  note: string;
  matches: WorldScores["live"];
  empty: string;
}) {
  return (
    <section className="panel">
      <div className="panel-head">
        <h2>{title}</h2>
        <span className="tag">{matches.length}</span>
      </div>
      <p className="panel-note">{note}</p>
      {matches.length === 0 ? (
        <div className="empty"><p className="muted">{empty}</p></div>
      ) : (
        <div className="score-list">
          {matches.map((m) => (
            <ScoreCard key={m.id} match={m} href={`/scores/${m.id}`} />
          ))}
        </div>
      )}
    </section>
  );
}
