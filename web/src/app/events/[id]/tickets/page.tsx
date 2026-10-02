"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, getStoredUser, money, readErr } from "@/lib/api";
import { type EventTicket, type TicketBooking } from "@/lib/tournament";
import { Avatar } from "@/components/Avatar";
import {
  PaymentReturn,
  payAtStripe,
  useCardPayments,
  useReturnedFromStripe,
} from "@/components/PayDialog";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

/// A ticketed club event — the dinner, the quiz, presentation night.
///
/// Two jobs on one screen, because they are the same conversation: book your
/// own place and bring people, and — if you are running it — see the headcount
/// and who still owes.
export default function TicketsPage({ params }: { params: Promise<{ id: string }> }) {
  const t = useT();
  const { id } = use(params);
  const authed = useRequireAuth();
  const [booking, setBooking] = useState<TicketBooking | null>(null);
  const [guests, setGuests] = useState(0);
  const [guestNames, setGuestNames] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const cards = useCardPayments();
  const me = getStoredUser();

  // Back from Stripe's page. The redirect beats our webhook more often than
  // not, so the wait is shown rather than a booking that still says unpaid.
  const back = useReturnedFromStripe({
    settled: async () =>
      (await api<TicketBooking>("GET", `/events/${id}/tickets`)).tickets.some(
        (t) => t.user_id === me?.id && t.status === "paid"
      ),
    onSettled: () => load(),
  });

  const load = useCallback(async () => {
    try {
      setBooking(await api<TicketBooking>("GET", `/events/${id}/tickets`));
      setError(null);
    } catch (err) {
      setError(readErr(err, t("le.could_not_load_the_tickets")));
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
  if (error && !booking) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !booking)
    return <main id="main"><div className="skeleton" style={{ height: 260 }} /></main>;

  const { summary, tickets } = booking;
  // A non-member at a public event gets the headcount and their own booking.
  // The guest list, the takings and the treasurer's buttons are club business.
  const insider = booking.can_see_everyone;
  const mine = tickets.find((t) => t.user_id === me?.id && t.status !== "cancelled");
  const left =
    summary.ticket_capacity != null ? summary.ticket_capacity - summary.headcount : null;

  return (
    <main id="main">
      <section className="hero">
        <h1>{summary.title}</h1>
        <div className="hero-tags">
          <span className="tag">{summary.headcount} coming</span>
          {left != null && (
            <span className={left <= 0 ? "tag danger" : "tag grey"}>
              {left <= 0 ? t("le.full") : t("le.n_places_left", { n: left })}
            </span>
          )}
          {summary.ticket_price_cents != null && (
            <span className="tag gold">{money(summary.ticket_price_cents)} each</span>
          )}
          {summary.tickets_public && <span className="tag grey">{t("ev.open_to_all")}</span>}
        </div>
      </section>

      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}
      <PaymentReturn waiting={back.waiting} gaveUp={back.gaveUp} />

      <div className="pro-cols">
        <div className="pro-main">
          {mine ? (
            <div className="panel">
              <div className="panel-head">
                <h2>{t("ev.you_are_booked")}</h2>
                <span className={`tag ${mine.status === "paid" ? "" : "grey"}`}>
                  {mine.status}
                </span>
              </div>
              <dl className="pro-about">
                <div><dt>{t("ev.places")}</dt><dd className="num">{1 + mine.guests}</dd></div>
                {mine.guest_names && <div><dt>{t("ev.bringing")}</dt><dd>{mine.guest_names}</dd></div>}
                <div><dt>{t("ev.to_pay")}</dt><dd className="num">{money(mine.amount_cents, mine.currency)}</dd></div>
              </dl>
              <div className="field-row" style={{ marginTop: "var(--s4)" }}>
                {mine.status !== "paid" && mine.amount_cents > 0 && cards && (
                  <button
                    className="btn primary"
                    type="button"
                    disabled={busy !== null || paying}
                    onClick={async () => {
                      setPaying(true);
                      const problem = await payAtStripe(`/tickets/${mine.id}/pay`, t);
                      if (problem) {
                        setError(problem);
                        setPaying(false);
                      }
                    }}
                  >
                    {paying
                      ? t("le.taking_you_to_stripe")
                      : t("le.pay_by_card", { amount: money(mine.amount_cents, mine.currency) })}
                  </button>
                )}
                {mine.status !== "paid" && cards === false && (
                  // Said rather than shown as a button that cannot work: this
                  // server has no Stripe keys, so the only way to pay is to
                  // hand the money over.
                  <span className="subtle">
                    {t("ev.pay_your_club_directly_card_payments_a")}
                  </span>
                )}
                <button
                  className="btn"
                  type="button"
                  disabled={busy !== null}
                  onClick={() => act("cancel", () => api("POST", `/tickets/${mine.id}/cancel`, {}), t("le.booking_cancelled"))}
                >
                  {busy === "cancel" ? t("le.cancelling") : t("le.cancel_my_place")}
                </button>
              </div>
            </div>
          ) : (
            <div className="panel">
              <h2>{t("ev.book_a_place")}</h2>
              {left != null && left <= 0 ? (
                <p className="muted">{t("ev.sold_out_ask_your_secretary_whether_th")}</p>
              ) : (
                <>
                  {/* Only offered when the event actually allows guests —
                      otherwise this is a field the server always refuses. */}
                  {summary.guests_allowed > 0 && (
                    <div className="setup-fields">
                      <label>
                        {t("ev.how_many_are_you_bringing")}
                        <span className="subtle">up to {summary.guests_allowed}</span>
                        <input
                          type="number"
                          min={0}
                          max={summary.guests_allowed}
                          value={guests}
                          onChange={(e) =>
                            setGuests(
                              Math.min(summary.guests_allowed, Math.max(0, Number(e.target.value)))
                            )
                          }
                        />
                      </label>
                      {guests > 0 && (
                        <label>
                          {t("ev.who")}
                          <input
                            value={guestNames}
                            onChange={(e) => setGuestNames(e.target.value)}
                            placeholder={t("ev.names_so_the_table_plan_works")}
                          />
                        </label>
                      )}
                    </div>
                  )}
                  {summary.guests_allowed === 0 && (
                    <p className="muted">{t("ev.members_only_no_guests_at_this_one")}</p>
                  )}
                  <label>
                    {t("ev.anything_the_club_should_know")}
                    <input
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      placeholder={t("ev.two_vegetarians_one_gluten_free")}
                    />
                  </label>
                  <div className="field-row" style={{ marginTop: "var(--s4)" }}>
                    <button
                      className="btn primary lg"
                      type="button"
                      disabled={busy !== null}
                      onClick={() =>
                        act(
                          "book",
                          () =>
                            api("POST", `/events/${id}/tickets`, {
                              guests,
                              guest_names: guestNames.trim() || null,
                              notes: notes.trim() || null,
                            }),
                          `Booked ${1 + guests} ${guests ? "places" : "place"}.`
                        )
                      }
                    >
                      {busy === "book" ? t("le.booking") : `Book ${1 + guests} ${guests ? "places" : "place"}`}
                    </button>
                  </div>
                </>
              )}
            </div>
          )}

          {insider && (
            <div className="panel">
              <div className="panel-head">
                <h2>{t("ev.who_is_coming")}</h2>
                <span className="tag grey">{summary.bookings} bookings</span>
              </div>
              {tickets.length === 0 ? (
                <p className="muted">{t("ev.nobody_yet_be_the_first")}</p>
              ) : (
                <ul className="pick-list">
                  {tickets.map((ticket) => (
                    <TicketRow
                      key={ticket.id}
                      ticket={ticket}
                      busy={busy !== null}
                      onPaid={(method) =>
                        act(
                          ticket.id,
                          () => api("POST", `/tickets/${ticket.id}/mark-paid`, { method }),
                          t("le.marked_paid", { what: ticket.name ?? t("le.that_booking") })
                        )
                      }
                    />
                  ))}
                </ul>
              )}
            </div>
          )}
        </div>

        <aside className="pro-rail">
          <div className="panel">
            <h2>{t("ev.the_numbers")}</h2>
            <dl className="pro-figures">
              <div><dt>{t("ev.coming")}</dt><dd className="num">{summary.headcount}</dd></div>
              {insider && (
                <>
                  <div><dt>{t("ev.bookings")}</dt><dd className="num">{summary.bookings}</dd></div>
                  <div><dt>{t("ev.taken")}</dt><dd className="num">{money(summary.collected_cents)}</dd></div>
                  <div><dt>{t("ev.owed")}</dt><dd className="num">{money(summary.outstanding_cents)}</dd></div>
                </>
              )}
            </dl>
            {summary.ticket_capacity != null && (
              <p className="subtle">
                Room for {summary.ticket_capacity}.
              </p>
            )}
          </div>
          <p className="muted">
            <Link href="/events">{t("ev.all_fixtures_back")}</Link>
          </p>
        </aside>
      </div>

    </main>
  );
}

function TicketRow({
  ticket,
  busy,
  onPaid,
}: {
  ticket: EventTicket;
  busy: boolean;
  onPaid: (method: "cash" | "transfer") => void;
}) {
  const t = useT();
  const who = ticket.name ?? t("le.a_member");
  return (
    <li className={ticket.status === "cancelled" ? "reserve" : undefined}>
      <Avatar name={who} size={32} />
      <div className="pick-who">
        <strong>{who}</strong>
        <span className="pick-signals">
          {ticket.guests > 0 && (
            <span className="subtle">
              +{ticket.guests}{ticket.guest_names ? ` — ${ticket.guest_names}` : ""}
            </span>
          )}
          {ticket.notes && <span className="subtle">{ticket.notes}</span>}
        </span>
      </div>
      <div className="pick-actions">
        <span className={`tag ${ticket.status === "paid" ? "" : "grey"}`}>{ticket.status}</span>
        {/* Cash at the door is how most club events are actually paid for.
            Whoever is collecting needs to record it without a card reader. */}
        {ticket.status === "reserved" && (
          <>
            <button className="btn ghost sm" type="button" disabled={busy}
                    onClick={() => onPaid("cash")}>
              {t("ev.cash")}
            </button>
            <button className="btn ghost sm" type="button" disabled={busy}
                    onClick={() => onPaid("transfer")}>
              {t("ev.transfer")}
            </button>
          </>
        )}
      </div>
    </li>
  );
}
