"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, getStoredUser, readErr } from "@/lib/api";
import {
  AVAILABILITY_LABEL,
  inSquad,
  pickingOrder,
  RSVP_LABEL,
  STATE_LABEL,
  type Candidate,
  type SelectionBoard,
  type SquadProposal,
} from "@/lib/selection";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";

/// Picking a side.
///
/// The whole point is that a captain should not have to remember who said they
/// were free or who has been left out three weeks running — so every name
/// carries both answers and the count of games they have missed out on, and
/// the pool is ordered by who most deserves the next look.
export default function SelectionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [board, setBoard] = useState<SelectionBoard | null>(null);
  const [proposal, setProposal] = useState<SquadProposal | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [reserves, setReserves] = useState<Set<string>>(new Set());
  const [announcement, setAnnouncement] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const me = getStoredUser();

  const load = useCallback(async () => {
    try {
      const next = await api<SelectionBoard>("GET", `/events/${id}/selection`);
      setBoard(next);
      // The board is the truth; the checkboxes start from whatever it says.
      setPicked(new Set(next.candidates.filter((c) => c.state === "selected" || c.state === "confirmed").map((c) => c.user_id)));
      setReserves(new Set(next.candidates.filter((c) => c.state === "reserve").map((c) => c.user_id)));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load the selection board"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see the squad.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  const pool = useMemo(
    () => [...(board?.candidates ?? [])].sort(pickingOrder),
    [board]
  );
  const reasons = useMemo(
    () => new Map((board?.ranked ?? []).map((r) => [r.user_id, r.reasons])),
    [board]
  );

  const mine = board?.candidates.find((c) => c.user_id === me?.id);

  /// Functional updates throughout, never `new Set(picked)`.
  ///
  /// Reading the set from the render that produced the click means two taps
  /// before React re-renders both start from the same snapshot and the second
  /// one throws the first away. That is invisible to a person clicking, and
  /// exactly what happens when a squad is loaded in from a suggestion.
  const toggle = (userId: string, into: "picked" | "reserve") => {
    const [setter, otherSetter] =
      into === "picked" ? [setPicked, setReserves] : [setReserves, setPicked];

    setter((current) => {
      const next = new Set(current);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
    // Nobody is in the XI and on the bench at once.
    otherSetter((other) => {
      if (!other.has(userId)) return other;
      const trimmed = new Set(other);
      trimmed.delete(userId);
      return trimmed;
    });
  };

  const act = async (what: string, run: () => Promise<unknown>, said: string) => {
    setBusy(what);
    setError(null);
    setNote(null);
    try {
      await run();
      setNote(said);
      await load();
    } catch (err) {
      setError(readErr(err, "That did not work"));
    } finally {
      setBusy(null);
    }
  };

  const save = (announce: boolean) =>
    act(
      announce ? "announce" : "save",
      () =>
        api("POST", `/events/${id}/selection`, {
          selected: [...picked],
          reserves: [...reserves],
          announcement: announcement.trim() || null,
          announce,
        }),
      announce ? "Squad announced — everybody picked has been told." : "Saved as a draft."
    );

  const suggest = async (from: "suggest" | "agent") => {
    setBusy(from);
    setError(null);
    try {
      const out = await api<SquadProposal>("POST", `/events/${id}/selection/${from}`, {});
      setProposal(out);
      // Load it into the checkboxes so the captain edits a proposal rather
      // than retyping one.
      setPicked(new Set(out.selected.map((r) => r.user_id)));
      setReserves(new Set(out.reserves.map((r) => r.user_id)));
      if (out.announcement) setAnnouncement(out.announcement);
    } catch (err) {
      setError(readErr(err, "Could not work out a squad"));
    } finally {
      setBusy(null);
    }
  };

  if (error && !board) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !board)
    return <main id="main"><div className="skeleton" style={{ height: 300 }} /></main>;

  const short = board.requirements.size - picked.size;

  return (
    <main id="main">
      <section className="hero">
        <p className="club-eyebrow">
          {new Date(board.starts_at).toLocaleString("en-GB", {
            weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit",
          })}
        </p>
        <h1>{board.title}</h1>
        <div className="hero-tags">
          <span className="tag">{picked.size} of {board.requirements.size} picked</span>
          {reserves.size > 0 && <span className="tag grey">{reserves.size} reserve</span>}
          <span className="tag grey">{board.confirmed_count} confirmed</span>
        </div>
      </section>

      {error && <p className="error">{error}</p>}
      {note && <p className="muted">{note}</p>}

      {/* A player looking at their own selection wants one thing. */}
      {mine && inSquad(mine.state) && !mine.is_confirmed && (
        <div className="panel claim-panel">
          <div>
            <h2>You are in this side</h2>
            <p className="muted">
              {STATE_LABEL[mine.state]}. Say whether you are playing so your captain knows
              before the deadline.
            </p>
          </div>
          <div className="field-row">
            <button
              className="btn primary lg"
              type="button"
              disabled={busy !== null}
              onClick={() => act("confirm", () => api("POST", `/events/${id}/selection/respond`, { confirming: true }), "You are in.")}
            >
              I&apos;m playing
            </button>
            <button
              className="btn"
              type="button"
              disabled={busy !== null}
              onClick={() => act("decline", () => api("POST", `/events/${id}/selection/respond`, { confirming: false }), "Told them you cannot play.")}
            >
              I can&apos;t
            </button>
          </div>
        </div>
      )}

      <div className="pro-cols">
        <div className="pro-main">
          <div className="panel">
            <div className="panel-head">
              <h2>The pool</h2>
              <span className={short > 0 ? "tag gold" : "tag"}>
                {short > 0 ? `${short} more to pick` : "Side is full"}
              </span>
            </div>
            <p className="muted">
              Ordered by who most deserves the next look: who said yes, then who is free,
              then whoever has been left out most often.
            </p>

            <ul className="pick-list">
              {pool.map((c) => (
                <PickRow
                  key={c.user_id}
                  candidate={c}
                  reasons={reasons.get(c.user_id) ?? []}
                  picked={picked.has(c.user_id)}
                  reserve={reserves.has(c.user_id)}
                  onPick={() => toggle(c.user_id, "picked")}
                  onReserve={() => toggle(c.user_id, "reserve")}
                />
              ))}
            </ul>
          </div>

          <div className="panel">
            <h2>Tell them</h2>
            <label>
              What goes in the thread
              <textarea
                rows={3}
                value={announcement}
                onChange={(e) => setAnnouncement(e.target.value)}
                placeholder="Meet at the ground for 1pm, whites and a packed lunch."
              />
            </label>
            <div className="field-row" style={{ marginTop: "var(--s4)" }}>
              <button
                className="btn primary"
                type="button"
                disabled={busy !== null || picked.size === 0}
                onClick={() => save(true)}
              >
                {busy === "announce" ? "Announcing…" : "Announce the squad"}
              </button>
              <button
                className="btn"
                type="button"
                disabled={busy !== null}
                onClick={() => save(false)}
              >
                {busy === "save" ? "Saving…" : "Save as a draft"}
              </button>
            </div>
          </div>
        </div>

        <aside className="pro-rail">
          <div className="panel">
            <h2>Pick it for me</h2>
            <p className="muted">
              Both give you a squad to edit, never one that goes out on its own.
            </p>
            <div className="field-row">
              <button className="btn" type="button" disabled={busy !== null}
                      onClick={() => suggest("suggest")}>
                <Icon name="chart" size={16} /> {busy === "suggest" ? "Working…" : "From the numbers"}
              </button>
              <button className="btn" type="button" disabled={busy !== null}
                      onClick={() => suggest("agent")}>
                <Icon name="sparkle" size={16} /> {busy === "agent" ? "Thinking…" : "Ask the assistant"}
              </button>
            </div>

            {proposal && (
              <div className="proposal" style={{ marginTop: "var(--s4)" }}>
                <header>
                  <span className="tag gold">{proposal.source}</span>
                  {proposal.confidence && <span className="subtle">{proposal.confidence}</span>}
                </header>
                {proposal.concerns && <p>{proposal.concerns}</p>}
                {proposal.unmet_quotas.length > 0 && (
                  <p className="error">
                    Nobody available for: {proposal.unmet_quotas.join(", ")}
                  </p>
                )}
                <p className="muted">
                  Loaded into the list — change what you like before announcing it.
                </p>
              </div>
            )}
          </div>

          <div className="panel">
            <h2>What the side needs</h2>
            <dl className="pro-about">
              <div><dt>Playing</dt><dd className="num">{board.requirements.size}</dd></div>
              <div><dt>Reserves</dt><dd className="num">{board.requirements.reserves}</dd></div>
              {board.requirements.position_quotas.map((q) => (
                <div key={q.position}>
                  <dt>{q.position}</dt><dd className="num">at least {q.minimum}</dd>
                </div>
              ))}
            </dl>
          </div>

          <div className="panel">
            <h2>Nobody replying?</h2>
            <p className="muted">
              Reserves move up automatically {board.confirm_lead_hours} hours before the
              start. You can do it now instead.
            </p>
            <button
              className="btn"
              type="button"
              disabled={busy !== null}
              onClick={() => act("promote", () => api("POST", `/events/${id}/selection/promote`, {}), "Reserves moved up.")}
            >
              {busy === "promote" ? "Moving…" : "Move the reserves up"}
            </button>
          </div>

          <p className="muted">
            <Link href="/events">← All fixtures</Link>
          </p>
        </aside>
      </div>
    </main>
  );
}

function PickRow({
  candidate,
  reasons,
  picked,
  reserve,
  onPick,
  onReserve,
}: {
  candidate: Candidate;
  reasons: string[];
  picked: boolean;
  reserve: boolean;
  onPick: () => void;
  onReserve: () => void;
}) {
  const c = candidate;
  return (
    <li className={picked ? "picked" : reserve ? "reserve" : undefined}>
      <Avatar name={c.name} size={34} />
      <div className="pick-who">
        <strong>
          {/* A captain choosing between two names wants to see what each has
              actually done. */}
          <Link href={`/players/${c.user_id}`}>{c.name}</Link>
        </strong>
        <span className="pick-signals">
          {c.rsvp && c.rsvp !== "invited" && (
            <span className={`tag ${c.rsvp === "going" ? "" : c.rsvp === "not_going" ? "danger" : "grey"}`}>
              {RSVP_LABEL[c.rsvp]}
            </span>
          )}
          {/* The calendar is the weaker signal, so it only shows when they
              have not answered the fixture itself. */}
          {(!c.rsvp || c.rsvp === "invited") && c.availability && (
            <span className="tag grey">{AVAILABILITY_LABEL[c.availability]}</span>
          )}
          {c.position && <span className="subtle">{c.position}</span>}
          {c.games_missed_out > 0 && (
            <span className="subtle" title="Available but left out, last 60 days">
              left out ×{c.games_missed_out}
            </span>
          )}
        </span>
        {reasons.length > 0 && <span className="pick-why">{reasons.join(" · ")}</span>}
      </div>
      <div className="pick-actions">
        <button
          type="button"
          className={picked ? "chip on" : "chip"}
          aria-pressed={picked}
          onClick={onPick}
        >
          Pick
        </button>
        <button
          type="button"
          className={reserve ? "chip on" : "chip"}
          aria-pressed={reserve}
          onClick={onReserve}
        >
          Reserve
        </button>
      </div>
    </li>
  );
}
