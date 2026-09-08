"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  getAccessToken,
  type Club,
  type EventRow,
  type OpponentIdentity,
  type Team,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { OppositionPicker } from "@/components/OppositionPicker";
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
  const [opening, setOpening] = useState<EventRow | null>(null);

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

  const startMatch = async (event: EventRow, setup: Setup) => {
    setBusy(event.id);
    setError(null);
    try {
      const match = await api<MatchResponse>("POST", `/events/${event.id}/cricket-match`, {
        overs_limit: 20,
        home_name: setup.homeName.trim() || "Home",
        away_name: setup.awayName.trim() || "Away",
        // Recording who they are is what gives their captain a way in and a
        // squad to pick from.
        opponent_club_id: setup.opponent?.club_id ?? null,
      });
      router.push(`/score/${match.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not start the match");
      setBusy(null);
    }
  };

  return (
    <main id="main">
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
              <button
                className="btn primary"
                type="button"
                onClick={() => setOpening(event)}
              >
                Set up match
              </button>
            )}
          </div>
        ))}
        {!error && rows.length === 0 && (
          <p className="muted">No cricket fixtures. Create one under Fixtures first.</p>
        )}
      </div>

      {opening && (
        <MatchSetupSheet
          event={opening}
          busy={busy === opening.id}
          onClose={() => setOpening(null)}
          onStart={(setup) => startMatch(opening, setup)}
        />
      )}
    </main>
  );
}

type Setup = {
  homeName: string;
  awayName: string;
  opponent: OpponentIdentity | null;
};

/// Who is playing whom, before anything else.
///
/// Your side is chosen from the club's own teams rather than typed, and the
/// opposition is found by their code or by name so the match records who they
/// actually are — which is what lets their captain name their own eleven.
function MatchSetupSheet({
  event,
  busy,
  onClose,
  onStart,
}: {
  event: EventRow;
  busy: boolean;
  onClose: () => void;
  onStart: (setup: Setup) => void;
}) {
  const [teams, setTeams] = useState<Team[]>([]);
  const [clubName, setClubName] = useState("");
  const [homeName, setHomeName] = useState("");
  const [awayName, setAwayName] = useState("");
  const [opponent, setOpponent] = useState<OpponentIdentity | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const clubs = await api<Club[]>("GET", "/clubs");
        const club = clubs.find((c) => c.id === event.club_id);
        if (club) {
          setClubName(club.name);
          setHomeName(club.name);
        }
        setTeams(await api<Team[]>("GET", `/clubs/${event.club_id}/teams`));
      } catch {
        // A club with no teams is normal; the club's own name still works.
      }
    })();
  }, [event.club_id]);

  return (
    <div className="sheet-backdrop" role="presentation" onClick={(e) => {
      if (e.target === e.currentTarget) onClose();
    }}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label="Set up the match">
        <div className="sheet-head">
          <h2>{event.title}</h2>
          <button className="btn ghost sm" type="button" onClick={onClose}>Close</button>
        </div>

        <h3 className="section-head">Your side</h3>
        <div className="actions">
          {clubName && (
            <button
              className={homeName === clubName ? "btn primary" : "btn"}
              type="button"
              onClick={() => setHomeName(clubName)}
            >
              {clubName}
            </button>
          )}
          {teams.map((t) => (
            <button
              key={t.id}
              className={homeName === t.name ? "btn primary" : "btn"}
              type="button"
              onClick={() => setHomeName(t.name)}
            >
              {t.name}
            </button>
          ))}
        </div>
        <label style={{ marginTop: "var(--s2)" }}>
          Or name it yourself
          <input value={homeName} onChange={(e) => setHomeName(e.target.value)} />
        </label>

        <h3 className="section-head">The opposition</h3>
        <OppositionPicker
          onPick={(identity, name) => {
            setOpponent(identity);
            setAwayName(name);
          }}
        />
        <label style={{ marginTop: "var(--s2)" }}>
          Their name
          <input
            value={awayName}
            onChange={(e) => {
              setAwayName(e.target.value);
              // Typing over a matched club means they are no longer that club.
              setOpponent(null);
            }}
            placeholder="Whoever you are playing"
          />
        </label>
        {opponent && (
          <p className="muted">
            <Icon name="check" size={14} /> Matched to {opponent.club_name} in Fishers — their
            captain can name their own eleven.
          </p>
        )}

        <div className="sheet-actions">
          <button className="btn ghost" type="button" onClick={onClose}>Cancel</button>
          <button
            className="btn primary"
            type="button"
            disabled={busy || !homeName.trim() || !awayName.trim()}
            onClick={() => onStart({ homeName, awayName, opponent })}
          >
            {busy ? "Starting…" : "Start match"}
          </button>
        </div>
      </div>
    </div>
  );
}
