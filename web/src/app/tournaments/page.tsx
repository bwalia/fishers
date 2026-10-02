"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, money, readErr, type Club } from "@/lib/api";
import { defaultConditions, type EntryInvitation, type FixtureBlock } from "@/lib/tournament";
import {
  emptyRules,
  pence,
  rulesPayload,
  rulesSummary,
  TournamentRuleFields,
  type Rules,
  type Venue,
} from "@/components/TournamentRules";
import { Icon } from "@/components/Icon";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

/// Blocks of fixtures: a tournament, a tour, a season.
///
/// A block is the thing that holds entrants, a grid of pitches and times, and
/// a table. A one-off fixture needs none of that, which is why it is a separate
/// idea rather than a flag on an event.
export default function TournamentsPage() {
  const t = useT();
  const authed = useRequireAuth();
  const [clubs, setClubs] = useState<Club[]>([]);
  const [blocks, setBlocks] = useState<Record<string, FixtureBlock[]>>({});
  const [invites, setInvites] = useState<EntryInvitation[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    try {
      const mine = await api<Club[]>("GET", "/clubs");
      setClubs(mine);
      const found = await Promise.all(
        mine.map(async (c) => [
          c.id,
          await api<FixtureBlock[]>("GET", `/clubs/${c.id}/fixture-blocks`).catch(() => []),
        ] as const)
      );
      setBlocks(Object.fromEntries(found));

      // Tournaments other clubs have asked yours into. They belong at the top
      // of this screen rather than buried in a club page: an invitation nobody
      // answers is a tournament your side does not play in.
      const asked = await Promise.all(
        mine.map((c) =>
          api<EntryInvitation[]>("GET", `/clubs/${c.id}/tournament-invites?pending=1`)
            .catch(() => [] as EntryInvitation[])
        )
      );
      setInvites(asked.flat());
      setError(null);
    } catch (err) {
      setError(readErr(err, t("le.could_not_load_your_tournaments")));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  const total = Object.values(blocks).reduce((n, list) => n + list.length, 0);

  if (!authed) return <main id="main" />;

  return (
    <main id="main">
      <section className="hero">
        <h1>{t("tn.tournaments")}</h1>
        <p>{t("tn.a_block_holds_the_sides_the_pitches_an")}</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setCreating(true)}>
            <Icon name="plus" size={16} /> {t("tn.new_tournament")}
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}
      {loading && <div className="skeleton" style={{ height: 180 }} />}

      {invites.length > 0 && <Invitations invites={invites} onAnswered={load} />}

      {!loading && !error && total === 0 && (
        <div className="panel empty">
          <Icon name="trophy" size={28} />
          <p>{t("tn.nothing_running_start_one_and_add_the")}</p>
        </div>
      )}

      {clubs.map((club) => {
        const list = blocks[club.id] ?? [];
        if (list.length === 0) return null;
        return (
          <div className="panel" key={club.id}>
            <h2>{club.name}</h2>
            <ul className="thread-list">
              {list.map((b) => (
                <li key={b.id}>
                  <Link href={`/tournaments/${b.id}`} className="thread-row">
                    <span className="thread-mark" aria-hidden>
                      <Icon name="trophy" size={18} />
                    </span>
                    <span className="thread-body">
                      <span className="thread-head">
                        <strong>{b.name}</strong>
                        <span className="subtle">{dates(b)}</span>
                      </span>
                      <span className="thread-last">{b.kind}</span>
                    </span>
                    <span className="thread-badges">
                      <Icon name="arrowLeft" size={14} className="flip" />
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        );
      })}

      {creating && (
        <NewBlock clubs={clubs} onClose={() => setCreating(false)} onCreated={load} />
      )}
    </main>
  );
}

/// Tournaments your club has been asked into and has not answered.
///
/// The host is waiting on this to make the draw, so it is the first thing on
/// the page and it says who asked — an invitation from a club you have never
/// heard of is answered differently from one from your league rivals.
function Invitations({ invites }: { invites: EntryInvitation[]; onAnswered: () => void }) {
  const t = useT();
  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("tn.you_have_been_asked")}</h2>
        <span className="tag gold">{invites.length}</span>
      </div>
      <ul className="thread-list">
        {invites.map((i) => (
          <li key={i.entrant_id}>
            {/* Opened rather than answered here: a club should read the
                format, the fee and who may play before it agrees to them,
                and none of that fits on a list row. */}
            <Link href={`/tournaments/invite/${i.entrant_id}`} className="thread-row">
              <span className="thread-mark" aria-hidden>
                <Icon name="trophy" size={18} />
              </span>
              <span className="thread-body">
                <span className="thread-head">
                  <strong>{i.block_name}</strong>
                  <span className="subtle">{blockDates(i)}</span>
                </span>
                <span className="thread-last">
                  {i.host_club_name}
                  {i.invited_by_name ? ` · ${i.invited_by_name}` : ""} — entering as{" "}
                  {i.entrant_name}
                </span>
              </span>
              <span className="thread-badges">
                {i.entry_fee_cents ? (
                  <span className="tag grey">{t("tn.amount_to_enter", { amount: money(i.entry_fee_cents) })}</span>
                ) : null}
                <span className="tag gold">{t("tn.answer")}</span>
              </span>
            </Link>
          </li>
        ))}
      </ul>
      <p className="subtle" style={{ marginTop: "var(--s3)" }}>
        {t("tn.open_one_to_see_what_you_would_be_ente")}
      </p>
    </div>
  );
}

function blockDates(i: EntryInvitation): string {
  const fmt = (d: string) =>
    new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  if (i.starts_on && i.ends_on) return `${fmt(i.starts_on)} – ${fmt(i.ends_on)}`;
  if (i.starts_on) return `from ${fmt(i.starts_on)}`;
  return "";
}

function dates(b: FixtureBlock): string {
  const fmt = (d: string) =>
    new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  if (b.starts_on && b.ends_on) return `${fmt(b.starts_on)} – ${fmt(b.ends_on)}`;
  if (b.starts_on) return `from ${fmt(b.starts_on)}`;
  return "";
}

/// Starting a tournament.
///
/// Was eighteen boxes in three rows that did not line up, with nothing to tell
/// somebody who had never run one what to put in them. Now: what it is, then
/// the format — picked from the real ones, which fills in the numbers — then
/// entry and who may play, and a line at the end saying what it all adds up to.
function NewBlock({
  clubs,
  onClose,
  onCreated,
}: {
  clubs: Club[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const t = useT();
  // The club list arrives after this form's first render, and useState reads its
  // argument only once — seeding from it left clubId "" for good while the select
  // happily showed the first club, so adding a ground posted to /clubs//venues.
  // Derive it instead: the default follows the list the moment it lands.
  const [pickedClub, setPickedClub] = useState("");
  const clubId = pickedClub || clubs[0]?.id || "";
  const [name, setName] = useState("");
  const [kind, setKind] = useState("tournament");
  const [startsOn, setStartsOn] = useState("");
  const [endsOn, setEndsOn] = useState("");
  const [rules, setRules] = useState<Rules>(emptyRules);
  const [venues, setVenues] = useState<Venue[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = (patch: Partial<Rules>) => setRules((r) => ({ ...r, ...patch }));

  // Only a tournament has entrants, a draw and a table. A tour or a plain block
  // of fixtures is a name and two dates, so it is not asked for the rest.
  const isTournament = kind === "tournament";

  // The grounds belong to whichever club is hosting, so they follow the club.
  useEffect(() => {
    if (!clubId) return;
    set({ venueId: "" });
    api<Venue[]>("GET", `/clubs/${clubId}/venues`).then(setVenues).catch(() => setVenues([]));
  }, [clubId]);

  const fee = pence(rules.entryFee);
  const feeOk = fee === null || Number.isFinite(fee);
  const ready = !!name.trim() && !!clubId && feeOk;

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      // `clear` names settings to unset, which means nothing on a tournament
      // that does not exist yet.
      const settings = rulesPayload(rules, defaultConditions(rules.overs));
      delete (settings as Partial<typeof settings>).clear;
      await api("POST", "/fixture-blocks", {
        club_id: clubId,
        name: name.trim(),
        kind,
        starts_on: startsOn || null,
        ends_on: endsOn || null,
        description: rules.description.trim() || null,
        // Sending the playing conditions for a tour would put a ball colour on
        // a coach trip.
        ...(isTournament ? settings : {}),
      });
      onCreated();
      onClose();
    } catch (err) {
      setError(readErr(err, t("le.could_not_create_that")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel setup-panel">
      <div className="panel-head">
        <h2>{t("tn.new_tournament")}</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>{t("sc.cancel")}</button>
      </div>

      <section className="form-step">
        <h3 className="form-step-head">
          <span className="step-num" aria-hidden>1</span>
          What it is
        </h3>
        <div className="setup-fields">
          <label>
            Club
            <select value={clubId} onChange={(e) => setPickedClub(e.target.value)}>
              {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <span className="subtle">{t("tn.whoever_is_running_it")}</span>
          </label>
          <label>
            Name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("tn.summer_sixes")}
              maxLength={120}
            />
            <span className="subtle">{t("tn.what_the_clubs_you_invite_will_see")}</span>
          </label>
          <label>
            {t("tn.what_is_it")}
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="tournament">{t("tn.tournament")}</option>
              <option value="tour">{t("tn.tour")}</option>
              <option value="season">{t("tn.season")}</option>
              <option value="block">{t("tn.block_of_fixtures")}</option>
            </select>
            <span className="subtle">
              {isTournament
                ? t("le.carries_entrants_a_draw_and_a_table")
                : t("le.just_holds_fixtures_no_entries_or_rule")}
            </span>
          </label>
          <label>
            {t("tn.first_day")}
            <input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} />
          </label>
          <label>
            {t("tn.last_day")}
            <input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
            <span className="subtle">{t("tn.same_as_the_first_for_a_one_day_event")}</span>
          </label>
        </div>
        <label style={{ marginTop: "var(--s4)" }}>
          {t("tn.what_to_tell_the_clubs_you_invite")}
          <textarea
            rows={2}
            value={rules.description}
            onChange={(e) => set({ description: e.target.value })}
            placeholder={t("tn.eight_sides_two_groups_finals_in_the_a")}
          />
        </label>
      </section>

      {isTournament && (
        <div className="form-steps-rest">
          <TournamentRuleFields
              rules={rules}
              set={set}
              venues={venues}
              clubId={clubId}
              onVenueAdded={(v) => setVenues((all) => [...all, v])}
              from={2}
            />
        </div>
      )}

      {isTournament && (
        <div className="form-summary">
          <Icon name="check" size={16} />
          <span className="form-summary-body">
            <span className="form-summary-title">{t("tn.what_you_are_creating")}</span>
            <span className="form-summary-text">{rulesSummary(rules, t)}</span>
          </span>
        </div>
      )}

      {error && <p className="error">{error}</p>}
      {!ready && !error && (
        <p className="subtle" style={{ marginTop: "var(--s3)" }}>
          {!name.trim() ? t("le.give_it_a_name_to_create_it") : t("le.check_the_entry_fee")}
        </p>
      )}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !ready} onClick={create}>
          {busy ? "Creating…" : t("le.create_it")}
        </button>
        <button className="btn" type="button" onClick={onClose}>{t("sc.cancel")}</button>
      </div>
    </div>
  );
}
