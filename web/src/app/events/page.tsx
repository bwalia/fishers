"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  type Club,
  type EventRow,
  type OpponentIdentity,
  type Page,
} from "@/lib/api";
import { OppositionPicker } from "@/components/OppositionPicker";
import { Icon, type IconName } from "@/components/Icon";

const SUBTYPE_ICON: Record<string, IconName> = {
  league_match: "trophy",
  nets: "bat",
  social: "users",
};

function when(iso: string) {
  return new Date(iso).toLocaleString("en-GB", {
    weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

export default function EventsPage() {
  const [events, setEvents] = useState<EventRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [scheduling, setScheduling] = useState(false);

  const load = useCallback(async () => {
    try {
      setEvents((await api<Page<EventRow>>("GET", "/events?per_page=50")).items);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view fixtures.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  return (
    <main id="main">
      <section className="hero">
        <h1>Fixtures</h1>
        <p>Nets, league matches and socials across your clubs.</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setScheduling(true)}>
            <Icon name="plus" size={16} /> Schedule a match
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}

      {scheduling && (
        <ScheduleMatch
          onClose={() => setScheduling(false)}
          onScheduled={() => {
            setScheduling(false);
            load();
          }}
        />
      )}

      <div className="panel">
        {loading && <div className="skeleton" style={{ height: 64 }} />}
        {events.map((e) => (
          <div key={e.id} className="row">
            <div>
              <div style={{ fontWeight: 600 }}>{e.title}</div>
              <div style={{ display: "flex", gap: "var(--s2)", alignItems: "center", marginTop: 2 }}>
                <span className="tag">
                  <Icon name={SUBTYPE_ICON[e.event_subtype] ?? "calendar"} size={12} />
                  {e.event_subtype.replaceAll("_", " ")}
                </span>
                <span className="muted">{when(e.start_at)}</span>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--s3)" }}>
              {e.fee_amount_cents != null && (
                <span className="price">£{(e.fee_amount_cents / 100).toFixed(0)}</span>
              )}
              <Availability eventId={e.id} />
              {e.sport === "cricket" && (
                <Link className="btn sm" href="/score">Score</Link>
              )}
            </div>
          </div>
        ))}
        {!loading && !error && events.length === 0 && (
          <div className="empty">
            <Icon name="calendar" size={28} />
            <p>No fixtures yet.</p>
          </div>
        )}
      </div>
    </main>
  );
}

/// "Can you play?" — the one question a fixture asks of everybody.
///
/// The answer is what a captain picks a side from, so it lives on the fixture
/// row rather than behind a detail page nobody opens.
function Availability({ eventId }: { eventId: string }) {
  const [said, setSaid] = useState<"going" | "not_going" | null>(null);
  const [busy, setBusy] = useState(false);

  const answer = async (status: "going" | "not_going") => {
    setBusy(true);
    try {
      await api("POST", `/events/${eventId}/rsvp`, { status });
      setSaid(status);
    } catch {
      // Somebody not invited to this fixture simply cannot answer it.
    } finally {
      setBusy(false);
    }
  };

  if (said) {
    return (
      <span className={`tag ${said === "going" ? "" : "grey"}`}>
        {said === "going" ? "You're in" : "Can't play"}
      </span>
    );
  }

  return (
    <span className="rsvp">
      <button className="btn sm" type="button" disabled={busy} onClick={() => answer("going")}>
        Available
      </button>
      <button
        className="btn ghost sm"
        type="button"
        disabled={busy}
        onClick={() => answer("not_going")}
      >
        Can&rsquo;t
      </button>
    </span>
  );
}

/// Schedule a match against another club.
///
/// Naming the opposition here is what lets both sides be asked who is
/// available — a fixture that only knows its host can only ask half a match.
function ScheduleMatch({
  onClose,
  onScheduled,
}: {
  onClose: () => void;
  onScheduled: () => void;
}) {
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [opponent, setOpponent] = useState<OpponentIdentity | null>(null);
  const [oppositionName, setOppositionName] = useState("");
  const [start, setStart] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const mine = await api<Club[]>("GET", "/clubs").catch(() => [] as Club[]);
      setClubs(mine);
      if (mine[0]) setClubId(mine[0].id);
    })();
  }, []);

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      const from = new Date(start);
      // A cricket fixture runs most of an afternoon; nobody wants to type an
      // end time as well.
      const to = new Date(from.getTime() + 5 * 60 * 60 * 1000);
      const us = clubs.find((c) => c.id === clubId)?.name ?? "Us";
      await api("POST", "/events", {
        club_id: clubId,
        opponent_club_id: opponent?.club_id ?? null,
        sport: "cricket",
        event_subtype: "league_match",
        title: `${us} v ${opponent?.name ?? (oppositionName || "opposition")}`,
        start_at: from.toISOString(),
        end_at: to.toISOString(),
      });
      onScheduled();
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "Could not schedule that");
      } catch {
        setError(raw || "Could not schedule that");
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>Schedule a match</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
      </div>

      <fieldset className="setup-group">
        <legend>Your side</legend>
        <label>
          Club
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
      </fieldset>

      <fieldset className="setup-group">
        <legend>The opposition</legend>
        <OppositionPicker
          onPick={(found, name) => {
            setOpponent(found);
            setOppositionName(name);
          }}
        />
        <p className="subtle">
          {opponent
            ? `${opponent.name} are on Fishers — their players get asked too.`
            : "A club on Fishers gets asked as well. Otherwise only your side is."}
        </p>
      </fieldset>

      <fieldset className="setup-group">
        <legend>When</legend>
        <label>
          Date and time
          <input
            type="datetime-local"
            value={start}
            onChange={(e) => setStart(e.target.value)}
          />
        </label>
      </fieldset>

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary lg"
        type="button"
        disabled={busy || !clubId || !start || (!opponent && !oppositionName.trim())}
        onClick={submit}
      >
        {busy ? "Scheduling…" : "Schedule and ask who is available"}
      </button>
      <p className="subtle">
        Everyone in {opponent ? "both clubs" : "your club"} is asked whether they can
        play, and the captain hears each answer.
      </p>
    </div>
  );
}
