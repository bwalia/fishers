"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  money,
  readErr,
  type ClubMemberRow,
  type EventRow,
} from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { PeoplePicker, type PeopleTab } from "@/components/PeoplePicker";
import { useRequireAuth } from "@/lib/require-auth";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// Everyone the fixture knows about, and what they said.
type Attendee = {
  user_id: string;
  name: string;
  /// `going` | `not_going` | `maybe` | `invited`
  status: string;
  availability: string | null;
  paid: boolean;
};

const RSVP_LABEL: Record<string, Key> = {
  going: "ev.playing",
  not_going: "ld.can_t",
  maybe: "ev.maybe",
  invited: "ev.not_answered",
};

/// One fixture: who is coming, who owes, and — if you run it — calling it off.
export default function EventPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
  const { id } = use(params);
  const authed = useRequireAuth();
  const [event, setEvent] = useState<EventRow | null>(null);
  const [attendees, setAttendees] = useState<Attendee[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const [e, a] = await Promise.all([
        api<EventRow>("GET", `/events/${id}`),
        api<Attendee[]>("GET", `/events/${id}/attendees`).catch(() => [] as Attendee[]),
      ]);
      setEvent(e);
      setAttendees(a);
      setError(null);
    } catch (err) {
      setError(readErr(err, t("ld.could_not_load_this_fixture")));
    } finally {
      setLoading(false);
    }
  }, [id, t]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

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

  if (!authed) return <main id="main" />;
  if (error && !event) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !event)
    return <main id="main"><div className="skeleton" style={{ height: 260 }} /></main>;

  const count = (s: string) => attendees.filter((a) => a.status === s).length;
  const owing = attendees.filter((a) => !a.paid && a.status === "going");

  return (
    <main id="main">
      <section className="hero">
        <p className="club-eyebrow">
          {new Date(event.start_at).toLocaleString("en-GB", {
            weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit",
          })}
        </p>
        <h1>{event.title}</h1>
        <div className="hero-tags">
          <span className="tag">{t("ev.n_playing", { n: count("going") })}</span>
          {count("maybe") > 0 && <span className="tag gold">{t("ev.n_maybe", { n: count("maybe") })}</span>}
          {count("invited") > 0 && (
            <span className="tag grey">{t("ev.n_not_answered", { n: count("invited") })}</span>
          )}
          {event.status !== "scheduled" && (
            <span className="tag danger">{event.status}</span>
          )}
        </div>
      </section>

      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}

      <div className="pro-cols">
        <div className="pro-main">
          <div className="panel">
            <div className="panel-head">
              <h2>{t("ev.are_you_playing")}</h2>
              {event.fee_amount_cents != null && (
                <span className="tag gold">{t("ev.amount_match_fee", { amount: money(event.fee_amount_cents) })}</span>
              )}
            </div>
            <div className="field-row">
              {(["going", "maybe", "not_going"] as const).map((answer) => (
                <button
                  key={answer}
                  className={answer === "going" ? "btn primary" : "btn"}
                  type="button"
                  disabled={busy !== null}
                  onClick={() =>
                    act(answer, () => api("POST", `/events/${id}/rsvp`, { status: answer }),
                        t("le.told_them", { answer: t(RSVP_LABEL[answer]).toLowerCase() }))
                  }
                >
                  {t(RSVP_LABEL[answer])}
                </button>
              ))}
            </div>
          </div>

          <div className="panel">
            <div className="panel-head">
              <h2>{t("ev.who_is_coming")}</h2>
              <Link className="btn ghost sm" href={`/events/${id}/selection`}>
                {t("ev.pick_the_squad")}
              </Link>
            </div>
            {attendees.length === 0 ? (
              <p className="muted">{t("ev.nobody_asked_yet_invite_people_below")}</p>
            ) : (
              <ul className="pick-list">
                {attendees.map((a) => (
                  <li key={a.user_id}>
                    <Avatar name={a.name} size={32} />
                    <div className="pick-who">
                      <strong>{a.name}</strong>
                      <span className="pick-signals">
                        <span className={`tag ${a.status === "going" ? "" : a.status === "not_going" ? "danger" : "grey"}`}>
                          {t(RSVP_LABEL[a.status])}
                        </span>
                        {a.availability && (
                          <span className="subtle">{t("ev.calendar_says", { what: a.availability })}</span>
                        )}
                      </span>
                    </div>
                    <div className="pick-actions">
                      {event.fee_amount_cents != null && (
                        <span className={a.paid ? "tag" : "tag grey"}>
                          {a.paid ? "paid" : "owes"}
                        </span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <Invite eventId={id} clubId={event.club_id} asked={attendees} onInvited={load} />

          <Tickets event={event} onSaved={load} />
        </div>

        <aside className="pro-rail">
          {event.fee_amount_cents != null && owing.length > 0 && (
            <div className="panel">
              <h2>{t("ev.still_to_pay")}</h2>
              <p className="muted">
                {owing.length} of the {count("going")} playing owe{" "}
                {money(event.fee_amount_cents * owing.length)} between them.
              </p>
            </div>
          )}

          <CallOff
            status={event.status}
            busy={busy !== null}
            onDo={(status, note) =>
              act(
                "status",
                () => api("POST", `/events/${id}/status`, { status, note: note || null }),
                status === "cancelled" ? t("ld.called_off_everybody_has_been_told")
                  : status === "postponed" ? t("ld.postponed_everybody_has_been_told")
                  : t("ld.back_on")
              )
            }
          />

          <p className="muted">
            <Link href="/events">{t("ev.all_fixtures_back")}</Link>
          </p>
        </aside>
      </div>
    </main>
  );
}

/// Ask more people. Only offers club members who have not been asked yet —
/// inviting somebody twice is noise for them and a duplicate row here.
function Invite({
  eventId,
  clubId,
  asked,
  onInvited,
}: {
  eventId: string;
  clubId: string;
  asked: Attendee[];
  onInvited: () => void;
}) {
  const t = useT();
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [open, setOpen] = useState(false);
  const [chosen, setChosen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || members.length > 0) return;
    api<ClubMemberRow[]>("GET", `/clubs/${clubId}/members`)
      .then(setMembers)
      .catch(() => setError(t("ld.only_a_captain_or_secretary_can_invite")));
  }, [open, members.length, clubId, t]);

  const already = new Set(asked.map((a) => a.user_id));
  const tabs: PeopleTab[] = [
    {
      label: t("ld.not_asked_yet"),
      people: members
        .filter((m) => !already.has(m.user_id))
        .map((m) => ({ id: m.user_id, name: m.name, note: m.position_role ?? undefined })),
    },
  ];

  const invite = async () => {
    if (!chosen) return;
    setBusy(true);
    setError(null);
    try {
      await api("POST", `/events/${eventId}/invite`, { user_id: chosen });
      setChosen(null);
      onInvited();
    } catch (err) {
      setError(readErr(err, t("ld.could_not_invite_them")));
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button className="btn" type="button" onClick={() => setOpen(true)}>
        <Icon name="plus" size={16} /> {t("ev.ask_somebody_else")}
      </button>
    );
  }

  return (
    <div className="panel">
      <h2>{t("ev.ask_somebody_else")}</h2>
      <PeoplePicker
        tabs={tabs}
        chosen={chosen}
        onChoose={setChosen}
        empty={t("ld.everybody_in_the_club_has_already_been")}
      />
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !chosen} onClick={invite}>
          {busy ? "Asking…" : t("ld.ask_them")}
        </button>
        <button className="btn" type="button" onClick={() => { setOpen(false); setChosen(null); }}>
          {t("ev.done")}
        </button>
      </div>
    </div>
  );
}

/// Postponing or calling a fixture off.
///
/// Both tell everybody who was asked, so the reason is worth typing — "ground
/// unplayable after Friday's rain" saves a captain fifteen replies.
function CallOff({
  status,
  busy,
  onDo,
}: {
  status: string;
  busy: boolean;
  onDo: (status: string, note: string) => void;
}) {
  const t = useT();
  const [note, setNote] = useState("");
  const off = status === "cancelled" || status === "postponed";

  return (
    <div className="panel">
      <h2>{off ? t("ld.this_fixture_is_off") : t("ld.call_it_off")}</h2>
      {off ? (
        <>
          <p className="muted">{t("ev.it_is_marked_status", { status })}</p>
          <button className="btn" type="button" disabled={busy}
                  onClick={() => onDo("scheduled", "")}>
            {t("ev.put_it_back_on")}
          </button>
        </>
      ) : (
        <>
          <p className="muted">
            {t("ev.everybody_who_was_asked_gets_told_so_t")}
          </p>
          <label>
            {t("ev.why")}
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={t("ev.ground_unplayable_after_friday_s_rain")}
            />
          </label>
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn" type="button" disabled={busy}
                    onClick={() => onDo("postponed", note)}>
              {t("ev.postpone")}
            </button>
            <button className="btn danger" type="button" disabled={busy}
                    onClick={() => onDo("cancelled", note)}>
              {t("ev.cancel_it")}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

/// Selling tickets to this one.
///
/// Every field here has been on the API since ticketing was built; until now
/// nothing in the product set any of them, so the booking screen existed and
/// no event could ever reach it.
function Tickets({ event, onSaved }: { event: EventRow; onSaved: () => void }) {
  const t = useT();
  const selling = event.ticket_price_cents != null;
  const [open, setOpen] = useState(selling);
  const [pounds, setPounds] = useState(
    event.ticket_price_cents != null ? (event.ticket_price_cents / 100).toFixed(2) : ""
  );
  const [capacity, setCapacity] = useState(event.ticket_capacity?.toString() ?? "");
  const [guests, setGuests] = useState(event.guests_allowed ?? 0);
  const [isPublic, setIsPublic] = useState(event.tickets_public ?? false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  // Pounds in, pence out. A price typed as "7.50" that reaches the API as 7
  // is the kind of bug nobody notices until the takings are short.
  //
  // Anything that is not a plain amount is refused rather than coerced: a
  // stray "abc" used to strip to "" and save the event as free.
  const typed = pounds.trim().replace(/^£/, "");
  const pence = /^\d+(\.\d{1,2})?$/.test(typed) ? Math.round(Number(typed) * 100) : NaN;
  // The payments API refuses anything over £1,000 as a fat finger, so a price
  // above it could be set and then never paid.
  const tooMuch = pence > 100_000;
  const priceOk = Number.isFinite(pence) && !tooMuch;

  const save = async () => {
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      await api("PATCH", `/events/${event.id}`, {
        ticket_price_cents: pence,
        ticket_capacity: capacity.trim() === "" ? null : Number(capacity),
        guests_allowed: guests,
        tickets_public: isPublic,
      });
      setNote(selling ? t("ld.ticket_settings_saved") : t("ld.tickets_are_on_sale"));
      onSaved();
    } catch (err) {
      setError(readErr(err, t("ld.could_not_save_that")));
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <div className="panel">
        <div className="panel-head">
          <h2>{t("ev.tickets")}</h2>
          <button className="btn ghost sm" type="button" onClick={() => setOpen(true)}>
            {t("ev.sell_tickets")}
          </button>
        </div>
        <p className="muted">
          {t("ev.not_selling_tickets_to_this_one_turn_i")}
        </p>
      </div>
    );
  }

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t("ev.tickets")}</h2>
        {selling && (
          <Link className="btn ghost sm" href={`/events/${event.id}/tickets`}>
            {t("ev.see_bookings")}
          </Link>
        )}
      </div>

      <div className="setup-fields">
        <label>
          {t("ev.price_each")}
          <span className="subtle">{t("ev.zero_for_a_free_event_you_still_want_a")}</span>
          <input
            inputMode="decimal"
            value={pounds}
            onChange={(e) => setPounds(e.target.value)}
            placeholder={t("ev.7_50")}
          />
        </label>
        <label>
          {t("ev.how_many_can_come")}
          <span className="subtle">{t("ev.leave_empty_for_no_limit")}</span>
          <input
            type="number"
            min={1}
            value={capacity}
            onChange={(e) => setCapacity(e.target.value)}
            placeholder={t("ev.80")}
          />
        </label>
        <label>
          {t("ev.guests_each_member_may_bring")}
          <input
            type="number"
            min={0}
            max={10}
            value={guests}
            onChange={(e) => setGuests(Math.max(0, Math.min(10, Number(e.target.value))))}
          />
        </label>
      </div>

      <label className="check-row">
        <input
          type="checkbox"
          checked={isPublic}
          onChange={(e) => setIsPublic(e.target.checked)}
        />
        <span>
          <strong>{t("ev.anyone_on_brand_can_buy", { brand: brand.name })}</strong>
          <span className="subtle">
            {isPublic
              ? t("ld.visiting_clubs_and_their_supporters_ca")
              : t("ld.members_of_this_club_only_leave_this_o")}
          </span>
        </span>
      </label>

      {pounds.trim() !== "" && !Number.isFinite(pence) && (
        <p className="error">{t("ev.give_the_price_as_an_amount_like_7_50")}</p>
      )}
      {tooMuch && <p className="error">That is over £1,000 — payments are refused above it.</p>}
      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !priceOk} onClick={save}>
          {busy ? "Saving…" : selling ? "Save" : t("ld.put_them_on_sale")}
        </button>
        {!selling && (
          <button className="btn" type="button" onClick={() => setOpen(false)}>
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}
