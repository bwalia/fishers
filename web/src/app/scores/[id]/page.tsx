"use client";

/// One match in full — the scorecard.
///
/// Innings are tabs rather than a stack: a Test has four of them, and scrolling
/// past a hundred batting rows to reach the one you wanted is not reading, it
/// is hunting. The card itself then uses the whole width — batting on the left,
/// bowling and the wickets beside it — rather than leaving half the screen
/// empty the way most score sites do.

import Link from "next/link";
import { use, useCallback, useEffect, useState } from "react";
import { Icon } from "@/components/Icon";
import { ScoreCard } from "@/components/WorldScores";
import { useRequireAuth } from "@/lib/require-auth";
import {
  freshness,
  inningsLabel,
  inningsScore,
  inningsTitle,
  sideScore,
  worldMatch,
  type BattingRow,
  type BowlingRow,
  type Innings,
  type WorldMatchDetailView,
} from "@/lib/scores";

const num = (v?: number | null) => (v == null ? "—" : String(v));

export default function MatchPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const authed = useRequireAuth();
  const [view, setView] = useState<WorldMatchDetailView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  /// Which innings is open. Null until the card arrives, then the latest one —
  /// what is happening now is what somebody came to see, not the first day.
  const [tab, setTab] = useState<number | null>(null);

  const load = useCallback(async () => {
    try {
      const next = await worldMatch(id);
      setView(next);
      setTab((current) => {
        const count = next.detail?.innings.length ?? 0;
        if (count === 0) return null;
        // A refresh must not throw somebody back to the innings they were not
        // reading — only a first load picks for them.
        return current == null || current >= count ? count - 1 : current;
      });
      setError(null);
    } catch {
      setError("Could not load that match.");
    } finally {
      setLoaded(true);
    }
  }, [id]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  // Only while it is actually being played, and only while the tab is in front
  // of somebody — this is the one screen that costs a request per match.
  useEffect(() => {
    if (!authed || view?.summary.phase !== "live") return;
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") load();
    }, 120_000);
    return () => clearInterval(timer);
  }, [authed, view?.summary.phase, load]);

  if (!authed) return null;

  const innings = view?.detail?.innings ?? [];
  const open = tab != null ? innings[tab] : undefined;

  return (
    <main id="main">
      <nav className="crumbs">
        <Link href="/scores">← All cricket scores</Link>
      </nav>

      {error && <div className="notice">{error}</div>}
      {!loaded && <div className="empty"><p className="muted">Loading the match…</p></div>}

      {view && (
        <>
          <div className="score-list score-single">
            {/* The header reads off the card when there is one. The summary is
                fetched by the list poll and the card when somebody opens the
                match, so they can be minutes apart — and the card is the
                fresher. */}
            <ScoreCard
              match={
                innings.length === 0
                  ? view.summary
                  : {
                      ...view.summary,
                      home_score:
                        sideScore(innings, view.summary.home_team_name) ??
                        view.summary.home_score,
                      away_score:
                        sideScore(innings, view.summary.away_team_name) ??
                        view.summary.away_score,
                    }
              }
            />
          </div>

          {view.detail?.venue && (
            <p className="score-meta score-venue">
              <Icon name="pin" size={14} /> {view.detail.venue}
            </p>
          )}

          {((view.detail?.batting_now?.length ?? 0) > 0 ||
            (view.detail?.bowling_now?.length ?? 0) > 0) && (
            <section className="panel">
              <div className="panel-head"><h2>At the crease</h2></div>
              <p className="panel-note">Who is in, and who is bowling at them, right now.</p>
              <div className="score-crease">
                {/* Grouped under two headings rather than a label on every
                    row: the label repeated four times is four wasted lines on
                    a phone, and side by side it uses the width on a desktop. */}
                {view.detail!.batting_now.length > 0 && (
                  <div className="score-crease-group">
                    <h3 className="card-sub">Batting</h3>
                    {view.detail!.batting_now.map((p) => (
                      <div className="score-crease-row" key={`bat-${p.name}`}>
                        <span className="score-crease-name">{p.name}</span>
                        <span className="score-crease-line">{p.line}</span>
                      </div>
                    ))}
                  </div>
                )}
                {view.detail!.bowling_now.length > 0 && (
                  <div className="score-crease-group">
                    <h3 className="card-sub">Bowling</h3>
                    {view.detail!.bowling_now.map((p) => (
                      <div className="score-crease-row" key={`bowl-${p.name}`}>
                        <span className="score-crease-name">{p.name}</span>
                        <span className="score-crease-line">{p.line}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </section>
          )}

          {innings.length > 1 && (
            <div className="innings-tabs" role="tablist" aria-label="Innings">
              {innings.map((inn, i) => (
                <button
                  key={`${inn.team_name}-${i}`}
                  type="button"
                  role="tab"
                  id={`innings-tab-${i}`}
                  aria-selected={tab === i}
                  aria-controls={`innings-panel-${i}`}
                  className={tab === i ? "active" : undefined}
                  onClick={() => setTab(i)}
                >
                  <span className="innings-tab-team">{inningsLabel(innings, i)}</span>
                  <span className="innings-tab-score">{inningsScore(inn) ?? "—"}</span>
                </button>
              ))}
            </div>
          )}

          {open && (
            <InningsCard
              innings={open}
              index={tab!}
              labelled={innings.length > 1}
              title={inningsTitle(innings, tab!)}
            />
          )}

          {loaded && !view.detail && (
            <div className="empty">
              <Icon name="ball" size={28} />
              <p>No scorecard for this match yet.</p>
              <p className="muted">
                Scorecards are fetched when somebody opens a match. If this one has not
                started, there is nothing to show yet.
              </p>
            </div>
          )}

          {loaded && view.detail && innings.length === 0 && (
            <div className="empty">
              <Icon name="ball" size={28} />
              <p>Not a ball bowled yet.</p>
              <p className="muted">The card will fill in once the match is under way.</p>
            </div>
          )}

          {view.detail_as_of && (
            <p className="score-asof">
              <Icon name="clock" size={14} /> Scorecard updated {freshness(view.detail_as_of)}.
              {view.summary.phase === "done"
                ? " This match has finished, so this is the final card."
                : " It comes from a free feed and runs a few minutes behind play."}
            </p>
          )}
        </>
      )}
    </main>
  );
}

/// One innings. Batting is the tall thing, so it takes the wide column and the
/// rest sits beside it — a scorecard in a single narrow column leaves half a
/// desktop empty for no reason.
function InningsCard({
  innings,
  index,
  labelled,
  title,
}: {
  innings: Innings;
  index: number;
  labelled: boolean;
  title: string;
}) {
  const e = innings.extras;
  const extras = [
    e.byes ? `${e.byes}b` : null,
    e.leg_byes ? `${e.leg_byes}lb` : null,
    e.wides ? `${e.wides}w` : null,
    e.no_balls ? `${e.no_balls}nb` : null,
  ].filter(Boolean);
  const score = inningsScore(innings);

  return (
    <section
      className="panel"
      role={labelled ? "tabpanel" : undefined}
      id={labelled ? `innings-panel-${index}` : undefined}
      aria-labelledby={labelled ? `innings-tab-${index}` : undefined}
    >
      <div className="panel-head">
        <h2>{title}</h2>
        {score && <span className="innings-total">{score}</span>}
      </div>

      <div className="innings-grid">
        <div className="innings-bat">
          <h3 className="card-sub">Batting</h3>
          <div className="card-table" role="table" aria-label={`${title} batting`}>
            <div className="card-head" role="row">
              <span role="columnheader">Batter</span>
              <span role="columnheader">R</span>
              <span role="columnheader">B</span>
              <span role="columnheader">4s</span>
              <span role="columnheader">6s</span>
              <span role="columnheader">SR</span>
            </div>
            {innings.batting.map((b) => (
              <BatRow key={b.name} row={b} />
            ))}
          </div>

          {e.total != null && (
            <p className="card-extras">
              <strong>Extras</strong> {e.total}
              {extras.length > 0 && <span className="muted"> ({extras.join(", ")})</span>}
            </p>
          )}
        </div>

        <div className="innings-side">
          {innings.bowling.length > 0 && (
            <>
              <h3 className="card-sub">Bowling</h3>
              <div
                className="card-table bowling"
                role="table"
                aria-label={`Bowling at ${title}`}
              >
                <div className="card-head" role="row">
                  <span role="columnheader">Bowler</span>
                  <span role="columnheader">O</span>
                  <span role="columnheader">M</span>
                  <span role="columnheader">R</span>
                  <span role="columnheader">W</span>
                  <span role="columnheader">Econ</span>
                </div>
                {innings.bowling.map((b) => (
                  <BowlRow key={b.name} row={b} />
                ))}
              </div>
            </>
          )}

          {innings.fall_of_wickets.length > 0 && (
            <>
              <h3 className="card-sub">Fall of wickets</h3>
              <p className="card-fow">
                {innings.fall_of_wickets.map((f) => (
                  <span key={f.wicket}>
                    <strong>{f.wicket}</strong>–{num(f.runs)}
                    {f.batter && <span className="muted"> {f.batter}</span>}
                    {f.overs != null && <span className="muted"> ({f.overs} ov)</span>}
                  </span>
                ))}
              </p>
            </>
          )}
        </div>
      </div>
    </section>
  );
}

function BatRow({ row }: { row: BattingRow }) {
  return (
    <div className={`card-row${row.not_out ? " in" : ""}`} role="row">
      <span role="cell" className="card-player">
        <span className="card-name">{row.name}</span>
        {/* The whole reason a scorecard is readable: not a code, a sentence. */}
        <span className="card-out">{row.how_out}</span>
      </span>
      <span role="cell"><strong>{num(row.runs)}</strong></span>
      <span role="cell">{num(row.balls)}</span>
      <span role="cell">{num(row.fours)}</span>
      <span role="cell">{num(row.sixes)}</span>
      <span role="cell">{row.strike_rate != null ? row.strike_rate.toFixed(1) : "—"}</span>
    </div>
  );
}

function BowlRow({ row }: { row: BowlingRow }) {
  return (
    <div className="card-row" role="row">
      <span role="cell" className="card-player">
        <span className="card-name">{row.name}</span>
      </span>
      <span role="cell">{num(row.overs)}</span>
      <span role="cell">{num(row.maidens)}</span>
      <span role="cell">{num(row.runs)}</span>
      <span role="cell"><strong>{num(row.wickets)}</strong></span>
      <span role="cell">{row.economy != null ? row.economy.toFixed(2) : "—"}</span>
    </div>
  );
}
