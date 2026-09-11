"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  getAccessToken,
  type Club,
  type EventRow,
  type OpponentIdentity,
  type Page,
  type Team,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { OppositionPicker } from "@/components/OppositionPicker";
import { overs, titleCase, type MatchResponse } from "@/lib/cricket";

/// A fixture and the match on it, as `GET /cricket/fixtures` returns them —
/// one paged request rather than a fetch per row.
type Fixture = {
  event_id: string;
  club_id: string;
  title: string;
  start_at: string;
  event_status: string;
  match_id: string | null;
  match_status: string | null;
  home_name: string | null;
  away_name: string | null;
  has_scorer: boolean;
  score: string | null;
  result: string | null;
};

type StateFilter = "" | "live" | "upcoming" | "finished";

const STATE_TABS: { value: StateFilter; label: string }[] = [
  { value: "", label: "All" },
  { value: "live", label: "In progress" },
  { value: "upcoming", label: "Not started" },
  { value: "finished", label: "Finished" },
];

const PER_PAGE = 20;

export default function ScoreIndexPage() {
  const router = useRouter();
  const [page, setPage] = useState<Page<Fixture> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [opening, setOpening] = useState<EventRow | null>(null);
  /// A match with no fixture behind it yet — two sides who just turned up.
  const [instant, setInstant] = useState(false);
  const [loading, setLoading] = useState(true);

  // Filtering, sorting and paging all happen in the database. A club with a
  // season behind it is not something to download and sift through here.
  const [stateFilter, setStateFilter] = useState<StateFilter>("");
  const [search, setSearch] = useState("");
  const [newestFirst, setNewestFirst] = useState(false);
  const [pageNo, setPageNo] = useState(1);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        page: String(pageNo),
        per_page: String(PER_PAGE),
        order: newestFirst ? "desc" : "asc",
      });
      if (stateFilter) params.set("state", stateFilter);
      // One letter matches most of the table; the API refuses it anyway.
      if (search.trim().length >= 2) params.set("q", search.trim());
      setPage(await api<Page<Fixture>>("GET", `/cricket/fixtures?${params}`));
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load fixtures");
    } finally {
      setLoading(false);
    }
  }, [pageNo, stateFilter, search, newestFirst]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to score a match.");
      setLoading(false);
      return;
    }
    // Typing should not fire a request per keystroke.
    const timer = setTimeout(load, search ? 300 : 0);
    return () => clearTimeout(timer);
  }, [load, search]);

  // Any change of filter starts again at the first page, or you land on an
  // empty page 3 of a one-page result.
  useEffect(() => {
    setPageNo(1);
  }, [stateFilter, search, newestFirst]);

  /// Start a match, creating the fixture first when there is not one.
  ///
  /// A game arranged in the car park has no fixture behind it, and making
  /// somebody go and create one before they can score is the wrong order — so
  /// the fixture is written from what they already told us.
  const startMatch = async (event: EventRow | null, setup: Setup) => {
    setBusy(event?.id ?? "instant");
    setError(null);
    try {
      let fixture = event;
      if (!fixture) {
        const now = new Date();
        const end = new Date(now.getTime() + 4 * 60 * 60 * 1000);
        fixture = await api<EventRow>("POST", "/events", {
          club_id: setup.clubId,
          sport: "cricket",
          event_subtype: setup.kind,
          title: `${setup.homeName.trim()} v ${setup.awayName.trim()}`,
          start_at: now.toISOString(),
          end_at: end.toISOString(),
          capacity: 22,
        });
      }
      const match = await api<MatchResponse>("POST", `/events/${fixture.id}/cricket-match`, {
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

      <div className="panel instant-start">
        <div>
          <h2>Two sides, right now</h2>
          <p className="muted">
            No fixture needed — name the teams and start scoring. The fixture is
            written for you.
          </p>
        </div>
        <button className="btn primary" type="button" onClick={() => setInstant(true)}>
          <Icon name="plus" size={16} /> Start a match now
        </button>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="fixture-controls">
        <div className="tabs" role="tablist" aria-label="Which fixtures">
          {STATE_TABS.map((tab) => (
            <button
              key={tab.value}
              role="tab"
              aria-selected={stateFilter === tab.value}
              className={`tab${stateFilter === tab.value ? " active" : ""}`}
              type="button"
              onClick={() => setStateFilter(tab.value)}
            >
              {tab.label}
            </button>
          ))}
        </div>
        <div className="fixture-tools">
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search fixtures or teams"
            aria-label="Search fixtures"
          />
          <button
            className="btn sm"
            type="button"
            onClick={() => setNewestFirst((v) => !v)}
          >
            {newestFirst ? "Newest first" : "Soonest first"}
          </button>
        </div>
      </div>

      <div className="panel">
        {loading && !page && <div className="skeleton" style={{ height: 72 }} />}

        {page?.items.map((f) => (
          <div key={f.event_id} className="row">
            <div>
              <div style={{ fontWeight: 600 }}>
                {f.home_name && f.away_name ? `${f.home_name} v ${f.away_name}` : f.title}
              </div>
              <div className="muted">
                {new Date(f.start_at).toLocaleString("en-GB", {
                  weekday: "short",
                  day: "numeric",
                  month: "short",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </div>
              <div className="fixture-tags">
                {f.match_status ? (
                  <span className={`status-pill ${f.match_status}`}>
                    {titleCase(f.match_status)}
                  </span>
                ) : (
                  <span className="tag grey">Not started</span>
                )}
                {f.score && <span className="tag num">{f.score}</span>}
                {f.result && <span className="tag gold">{f.result}</span>}
                {f.has_scorer && f.match_status !== "complete" && (
                  <span className="tag grey">Being scored</span>
                )}
              </div>
            </div>

            {f.match_id ? (
              <button
                className={f.match_status === "complete" ? "btn" : "btn primary"}
                type="button"
                onClick={() => router.push(`/score/${f.match_id}`)}
              >
                {f.match_status === "complete" ? "View scorecard" : "Open"}
              </button>
            ) : (
              <button
                className="btn primary"
                type="button"
                onClick={() =>
                  setOpening({
                    id: f.event_id,
                    club_id: f.club_id,
                    title: f.title,
                    sport: "cricket",
                    event_subtype: "league_match",
                    start_at: f.start_at,
                    end_at: f.start_at,
                    status: f.event_status,
                  })
                }
              >
                Set up match
              </button>
            )}
          </div>
        ))}

        {page && page.items.length === 0 && !loading && (
          <div className="empty">
            <Icon name="bat" size={28} />
            <p>{search || stateFilter ? "Nothing matches that." : "No cricket fixtures yet."}</p>
          </div>
        )}

        {page && page.total > 0 && (
          <div className="pager">
            <span className="muted">
              {(page.page - 1) * page.per_page + 1}–
              {(page.page - 1) * page.per_page + page.items.length} of {page.total}
            </span>
            <div className="pager-buttons">
              <button
                className="btn sm"
                type="button"
                disabled={page.page <= 1 || loading}
                onClick={() => setPageNo((n) => n - 1)}
              >
                Previous
              </button>
              <button
                className="btn sm"
                type="button"
                disabled={!page.has_more || loading}
                onClick={() => setPageNo((n) => n + 1)}
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>


      {(opening || instant) && (
        <MatchSetupSheet
          event={opening}
          busy={busy === (opening?.id ?? "instant")}
          onClose={() => {
            setOpening(null);
            setInstant(false);
          }}
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
  /// Only used when there is no fixture yet and one has to be written.
  clubId: string;
  kind: string;
};

/// Who is playing whom, before anything else.
///
/// Your side is chosen from the club's own teams rather than typed, and the
/// opposition is found by their code or by name so the match records who they
/// actually are — which is what lets their captain name their own eleven.
const MATCH_KINDS = [
  { value: "friendly", label: "Friendly" },
  { value: "league_match", label: "League" },
  { value: "social", label: "Social" },
];

function MatchSetupSheet({
  event,
  busy,
  onClose,
  onStart,
}: {
  /// Null for a match with no fixture behind it — one is written on start.
  event: EventRow | null;
  busy: boolean;
  onClose: () => void;
  onStart: (setup: Setup) => void;
}) {
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState(event?.club_id ?? "");
  const [teams, setTeams] = useState<Team[]>([]);
  const [clubName, setClubName] = useState("");
  const [homeName, setHomeName] = useState("");
  const [awayName, setAwayName] = useState("");
  const [kind, setKind] = useState("friendly");
  const [opponent, setOpponent] = useState<OpponentIdentity | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const found = await api<Club[]>("GET", "/clubs");
        setClubs(found);
        if (!clubId && found[0]) setClubId(found[0].id);
      } catch {
        // Without clubs there is nothing to play as; the error shows on start.
      }
    })();
    // Clubs are fetched once; the chosen one is tracked separately.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!clubId) return;
    const club = clubs.find((c) => c.id === clubId);
    if (club) {
      setClubName(club.name);
      setHomeName((current) => current || club.name);
    }
    (async () => {
      try {
        setTeams(await api<Team[]>("GET", `/clubs/${clubId}/teams`));
      } catch {
        // A club with no teams is normal; the club's own name still works.
        setTeams([]);
      }
    })();
  }, [clubId, clubs]);

  // Switching which club you play for can make the chosen opposition your own.
  useEffect(() => {
    setOpponent((o) => (o && o.club_id === clubId && o.kind !== "team" ? null : o));
  }, [clubId]);

  // Your own club as the opposition means two of its teams: your side has to
  // be one of them, and not the same one.
  const internal = !!opponent && opponent.club_id === clubId;
  const sameSides = !internal
    ? null
    : !teams.some((t) => t.name === homeName)
      ? "For a match between your teams, pick which team is your side."
      : homeName.trim().toLowerCase() === awayName.trim().toLowerCase()
        ? "Your side and the opposition are the same team — pick two different teams."
        : null;

  return (
    <div className="sheet-backdrop" role="presentation" onClick={(e) => {
      if (e.target === e.currentTarget) onClose();
    }}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label="Set up the match">
        <div className="sheet-head">
          <h2>{event ? event.title : "New match"}</h2>
          <button className="btn ghost sm" type="button" onClick={onClose}>Close</button>
        </div>

        {!event && (
          <>
            {clubs.length > 1 && (
              <label>
                Playing for
                <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
                  {clubs.map((c) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
              </label>
            )}
            <h3 className="section-head">What sort of game</h3>
            <div className="actions">
              {MATCH_KINDS.map((k) => (
                <button
                  key={k.value}
                  className={kind === k.value ? "btn primary" : "btn"}
                  type="button"
                  onClick={() => setKind(k.value)}
                >
                  {k.label}
                </button>
              ))}
            </div>
          </>
        )}

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
        {/* Two of your own teams can play each other — a trial, the 1s
            against the 2s. Only then is your own club the opposition. */}
        {teams.length >= 2 && (
          <div className="internal-match">
            <span className="subtle">Between your teams:</span>
            {teams
              .filter((t) => t.name !== homeName)
              .map((t) => (
                <button
                  key={t.id}
                  className={opponent?.id === t.id ? "btn sm primary" : "btn sm"}
                  type="button"
                  onClick={() => {
                    setOpponent({ id: t.id, name: t.name, qr_token: "", kind: "team", club_id: clubId, club_name: clubName });
                    setAwayName(t.name);
                  }}
                >
                  {t.name}
                </button>
              ))}
          </div>
        )}
        <OppositionPicker
          homeClubId={clubId}
          ownTeamsAllowed={teams.length >= 2}
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
        {opponent && !internal && (
          <p className="muted">
            <Icon name="check" size={14} /> Matched to {opponent.club_name} in Fishers — their
            captain can name their own eleven.
          </p>
        )}
        {internal && !sameSides && (
          <p className="muted">
            <Icon name="check" size={14} /> A match between two {clubName} teams: {homeName} v {awayName}.
          </p>
        )}
        {sameSides && <p className="error">{sameSides}</p>}

        <div className="sheet-actions">
          <button className="btn ghost" type="button" onClick={onClose}>Cancel</button>
          <button
            className="btn primary"
            type="button"
            disabled={busy || !homeName.trim() || !awayName.trim() || !!sameSides}
            onClick={() => onStart({ homeName, awayName, opponent, clubId, kind })}
          >
            {busy ? "Starting…" : "Start match"}
          </button>
        </div>
      </div>
    </div>
  );
}
