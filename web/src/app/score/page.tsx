"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api, getAccessToken, type EventRow } from "@/lib/api";
import { overs, titleCase, type MatchResponse } from "@/lib/cricket";

/// A fixture with whatever match already exists on it, so the list can say
/// "start" or "resume" rather than silently dropping you into someone's innings.
type Row = { event: EventRow; match: MatchResponse | null };

/// The score, or the result once it is over. Null before a ball is bowled, so
/// the caller does not end up printing the status twice.
function summarise(m: MatchResponse): string | null {
  if (m.state.status === "complete") return m.state.margin || "Complete";
  const inn = m.state.innings[m.state.innings.length - 1];
  if (!inn) return null;
  return `${inn.runs}/${inn.wickets} (${overs(inn.legal_balls)} ov)`;
}

export default function ScoreIndexPage() {
  const router = useRouter();
  const [rows, setRows] = useState<Row[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [names, setNames] = useState<Record<string, { home: string; away: string }>>({});

  const load = useCallback(async () => {
    try {
      const all = await api<EventRow[]>("GET", "/events");
      const cricket = all.filter((e) => e.sport === "cricket");
      const withMatches = await Promise.all(
        cricket.map(async (event) => {
          try {
            // 404 simply means nobody has started this one yet.
            const match = await api<MatchResponse>(
              "GET",
              `/events/${event.id}/cricket-match`
            );
            return { event, match };
          } catch {
            return { event, match: null };
          }
        })
      );
      setRows(withMatches);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load fixtures");
    }
  }, []);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to score a match.");
      return;
    }
    load();
  }, [load]);

  const startMatch = async (event: EventRow) => {
    setBusy(event.id);
    setError(null);
    try {
      const sides = names[event.id];
      const match = await api<MatchResponse>("POST", `/events/${event.id}/cricket-match`, {
        overs_limit: 20,
        home_name: sides?.home?.trim() || "Home",
        away_name: sides?.away?.trim() || "Away",
      });
      router.push(`/score/${match.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not start the match");
      setBusy(null);
    }
  };

  return (
    <main>
      <section className="hero">
        <h1>Score a match</h1>
        <p>
          Start a cricket fixture, or pick up one already under way. Setting up asks both
          captains to agree the overs, ground and ball before the toss.
        </p>
      </section>

      {error && <p className="error">{error}</p>}

      <div className="panel">
        {rows.map(({ event, match }) => (
          <div key={event.id} className="row">
            <div>
              <div>{event.title}</div>
              <div className="tag">{event.event_subtype.replaceAll("_", " ")}</div>
              <div className="muted">
                {new Date(event.start_at).toLocaleString("en-GB", {
                  weekday: "short",
                  day: "numeric",
                  month: "short",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </div>
              {match && (
                <div className="muted">
                  {match.state.home_name} v {match.state.away_name} ·{" "}
                  {titleCase(match.state.status)}
                  {summarise(match) && ` · ${summarise(match)}`}
                  {!match.can_score && " · you cannot score this one"}
                </div>
              )}
            </div>

            {match ? (
              <button
                className={match.state.status === "complete" ? "btn" : "btn primary"}
                type="button"
                onClick={() => router.push(`/score/${match.id}`)}
              >
                {match.state.status === "complete"
                  ? "View scorecard"
                  : match.can_score
                    ? "Resume scoring"
                    : "Watch"}
              </button>
            ) : (
              <div className="select-row" style={{ margin: 0, gap: "0.4rem" }}>
                <input
                  placeholder="Home side"
                  value={names[event.id]?.home ?? ""}
                  onChange={(ev) =>
                    setNames((n) => ({
                      ...n,
                      [event.id]: { home: ev.target.value, away: n[event.id]?.away ?? "" },
                    }))
                  }
                />
                <input
                  placeholder="Opposition"
                  value={names[event.id]?.away ?? ""}
                  onChange={(ev) =>
                    setNames((n) => ({
                      ...n,
                      [event.id]: { home: n[event.id]?.home ?? "", away: ev.target.value },
                    }))
                  }
                />
                <button
                  className="btn primary"
                  type="button"
                  disabled={busy === event.id}
                  onClick={() => startMatch(event)}
                >
                  {busy === event.id ? "Starting…" : "Start match"}
                </button>
              </div>
            )}
          </div>
        ))}
        {!error && rows.length === 0 && (
          <p className="muted">No cricket fixtures. Create one under Fixtures first.</p>
        )}
      </div>
    </main>
  );
}
