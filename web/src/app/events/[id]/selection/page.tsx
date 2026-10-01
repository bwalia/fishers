"use client";

import { use, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api, getStoredUser, readErr } from "@/lib/api";
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
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

/// Picking a side.
///
/// The whole point is that a captain should not have to remember who said they
/// were free or who has been left out three weeks running — so every name
/// carries both answers and the count of games they have missed out on, and
/// the pool is ordered by who most deserves the next look.
export default function SelectionPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
  const { id } = use(params);
  const authed = useRequireAuth();
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
      setError(readErr(err, t("ld.could_not_load_the_selection_board")));
    } finally {
      setLoading(false);
    }
  }, [id, t]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

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
      setError(readErr(err, t("le.that_did_not_work")));
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
      announce ? t("ld.squad_announced_everybody_picked_has_b") : t("ld.saved_as_a_draft")
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
      setError(readErr(err, t("ld.could_not_work_out_a_squad")));
    } finally {
      setBusy(null);
    }
  };

  if (!authed) return <main id="main" />;
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
            <h2>{t("ev.you_are_in_this_side")}</h2>
            <p className="muted">
              {t(STATE_LABEL[mine.state])}. Say whether you are playing so your captain knows
              before the deadline.
            </p>
          </div>
          <div className="field-row">
            <button
              className="btn primary lg"
              type="button"
              disabled={busy !== null}
              onClick={() => act("confirm", () => api("POST", `/events/${id}/selection/respond`, { confirming: true }), t("ld.you_are_in"))}
            >
              I&apos;m playing
            </button>
            <button
              className="btn"
              type="button"
              disabled={busy !== null}
              onClick={() => act("decline", () => api("POST", `/events/${id}/selection/respond`, { confirming: false }), t("ld.told_them_you_cannot_play"))}
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
              <h2>{t("ev.the_pool")}</h2>
              <span className={short > 0 ? "tag gold" : "tag"}>
                {short > 0 ? t("le.n_more_to_pick", { n: short }) : t("ld.side_is_full")}
              </span>
            </div>
            <p className="muted">
              {t("ev.ordered_by_who_most_deserves_the_next")}
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
            <h2>{t("ev.tell_them")}</h2>
            <label>
              {t("ev.what_goes_in_the_thread")}
              <textarea
                rows={3}
                value={announcement}
                onChange={(e) => setAnnouncement(e.target.value)}
                placeholder={t("ev.meet_at_the_ground_for_1pm_whites_and")}
              />
            </label>
            <div className="field-row" style={{ marginTop: "var(--s4)" }}>
              <button
                className="btn primary"
                type="button"
                disabled={busy !== null || picked.size === 0}
                onClick={() => save(true)}
              >
                {busy === "announce" ? t("ld.announcing") : t("ld.announce_the_squad")}
              </button>
              <button
                className="btn"
                type="button"
                disabled={busy !== null}
                onClick={() => save(false)}
              >
                {busy === "save" ? "Saving…" : t("ld.save_as_a_draft")}
              </button>
            </div>
          </div>
        </div>

        <aside className="pro-rail">
          <div className="panel">
            <h2>{t("ev.pick_it_for_me")}</h2>
            <p className="muted">
              {t("ev.both_give_you_a_squad_to_edit_never_on")}
            </p>
            <div className="field-row">
              <button className="btn" type="button" disabled={busy !== null}
                      onClick={() => suggest("suggest")}>
                <Icon name="chart" size={16} /> {busy === "suggest" ? "Working…" : t("ld.from_the_numbers")}
              </button>
              <button className="btn" type="button" disabled={busy !== null}
                      onClick={() => suggest("agent")}>
                <Icon name="sparkle" size={16} /> {busy === "agent" ? t("ld.thinking") : t("ld.ask_the_assistant")}
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
                  {t("ev.loaded_into_the_list_change_what_you_l")}
                </p>
              </div>
            )}
          </div>

          <div className="panel">
            <h2>{t("ev.what_the_side_needs")}</h2>
            <dl className="pro-about">
              <div><dt>{t("ev.playing")}</dt><dd className="num">{board.requirements.size}</dd></div>
              <div><dt>{t("ev.reserves")}</dt><dd className="num">{board.requirements.reserves}</dd></div>
              {board.requirements.position_quotas.map((q) => (
                <div key={q.position}>
                  <dt>{q.position}</dt><dd className="num">at least {q.minimum}</dd>
                </div>
              ))}
            </dl>
          </div>

          <div className="panel">
            <h2>{t("ev.nobody_replying")}</h2>
            <p className="muted">
              Reserves move up automatically {board.confirm_lead_hours} hours before the
              start. You can do it now instead.
            </p>
            <button
              className="btn"
              type="button"
              disabled={busy !== null}
              onClick={() => act("promote", () => api("POST", `/events/${id}/selection/promote`, {}), t("ld.reserves_moved_up"))}
            >
              {busy === "promote" ? t("ld.moving") : t("ld.move_the_reserves_up")}
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
  const t = useT();
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
              {t(RSVP_LABEL[c.rsvp])}
            </span>
          )}
          {/* The calendar is the weaker signal, so it only shows when they
              have not answered the fixture itself. */}
          {(!c.rsvp || c.rsvp === "invited") && c.availability && (
            <span className="tag grey">{t(AVAILABILITY_LABEL[c.availability])}</span>
          )}
          {c.position && <span className="subtle">{c.position}</span>}
          {c.games_missed_out > 0 && (
            <span className="subtle" title={t("ev.available_but_left_out_last_60_days")}>
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
          {t("ev.pick")}
        </button>
        <button
          type="button"
          className={reserve ? "chip on" : "chip"}
          aria-pressed={reserve}
          onClick={onReserve}
        >
          {t("ev.reserve")}
        </button>
      </div>
    </li>
  );
}
