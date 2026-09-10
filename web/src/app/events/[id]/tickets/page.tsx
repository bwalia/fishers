"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, getStoredUser, money, readErr } from "@/lib/api";
import { type EventTicket, type TicketBooking } from "@/lib/tournament";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";

/// A ticketed club event — the dinner, the quiz, presentation night.
///
/// Two jobs on one screen, because they are the same conversation: book your
/// own place and bring people, and — if you are running it — see the headcount
/// and who still owes.
export default function TicketsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [booking, setBooking] = useState<TicketBooking | null>(null);
  const [guests, setGuests] = useState(0);
  const [guestNames, setGuestNames] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const me = getStoredUser();

  const load = useCallback(async () => {
    try {
      setBooking(await api<TicketBooking>("GET", `/events/${id}/tickets`));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load the tickets"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to book a place.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

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

  if (error && !booking) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !booking)
    return <main id="main"><div className="skeleton" style={{ height: 260 }} /></main>;

  const { summary, tickets } = booking;
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
              {left <= 0 ? "Full" : `${left} places left`}
            </span>
          )}
          {summary.ticket_price_cents != null && (
            <span className="tag gold">{money(summary.ticket_price_cents)} each</span>
          )}
        </div>
      </section>

      {error && <p className="error">{error}</p>}
      {note && <p className="notice">{note}</p>}

      <div className="pro-cols">
        <div className="pro-main">
          {mine ? (
            <div className="panel">
              <div className="panel-head">
                <h2>You are booked</h2>
                <span className={`tag ${mine.status === "paid" ? "" : "grey"}`}>
                  {mine.status}
                </span>
              </div>
              <dl className="pro-about">
                <div><dt>Places</dt><dd className="num">{1 + mine.guests}</dd></div>
                {mine.guest_names && <div><dt>Bringing</dt><dd>{mine.guest_names}</dd></div>}
                <div><dt>To pay</dt><dd className="num">{money(mine.amount_cents, mine.currency)}</dd></div>
              </dl>
              <div className="field-row" style={{ marginTop: "var(--s4)" }}>
                {mine.status !== "paid" && (
                  <button
                    className="btn primary"
                    type="button"
                    disabled={busy !== null}
                    onClick={() => act("pay", () => api("POST", `/tickets/${mine.id}/pay`, {}), "Payment opened — your club confirms it once it clears.")}
                  >
                    {busy === "pay" ? "Opening…" : `Pay ${money(mine.amount_cents, mine.currency)}`}
                  </button>
                )}
                <button
                  className="btn"
                  type="button"
                  disabled={busy !== null}
                  onClick={() => act("cancel", () => api("POST", `/tickets/${mine.id}/cancel`, {}), "Booking cancelled.")}
                >
                  {busy === "cancel" ? "Cancelling…" : "Cancel my place"}
                </button>
              </div>
            </div>
          ) : (
            <div className="panel">
              <h2>Book a place</h2>
              {left != null && left <= 0 ? (
                <p className="muted">Sold out. Ask your secretary whether there is a list.</p>
              ) : (
                <>
                  {/* Only offered when the event actually allows guests —
                      otherwise this is a field the server always refuses. */}
                  {summary.guests_allowed > 0 && (
                    <div className="setup-fields">
                      <label>
                        How many are you bringing
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
                          Who
                          <input
                            value={guestNames}
                            onChange={(e) => setGuestNames(e.target.value)}
                            placeholder="Names, so the table plan works"
                          />
                        </label>
                      )}
                    </div>
                  )}
                  {summary.guests_allowed === 0 && (
                    <p className="muted">Members only — no guests at this one.</p>
                  )}
                  <label>
                    Anything the club should know
                    <input
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      placeholder="Two vegetarians, one gluten free"
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
                      {busy === "book" ? "Booking…" : `Book ${1 + guests} ${guests ? "places" : "place"}`}
                    </button>
                  </div>
                </>
              )}
            </div>
          )}

          <div className="panel">
            <div className="panel-head">
              <h2>Who is coming</h2>
              <span className="tag grey">{summary.bookings} bookings</span>
            </div>
            {tickets.length === 0 ? (
              <p className="muted">Nobody yet. Be the first.</p>
            ) : (
              <ul className="pick-list">
                {tickets.map((t) => (
                  <TicketRow
                    key={t.id}
                    ticket={t}
                    busy={busy !== null}
                    onPaid={(method) =>
                      act(
                        t.id,
                        () => api("POST", `/tickets/${t.id}/mark-paid`, { method }),
                        `${t.name ?? "That booking"} marked paid.`
                      )
                    }
                  />
                ))}
              </ul>
            )}
          </div>
        </div>

        <aside className="pro-rail">
          <div className="panel">
            <h2>The numbers</h2>
            <dl className="pro-figures">
              <div><dt>Coming</dt><dd className="num">{summary.headcount}</dd></div>
              <div><dt>Bookings</dt><dd className="num">{summary.bookings}</dd></div>
              <div><dt>Taken</dt><dd className="num">{money(summary.collected_cents)}</dd></div>
              <div><dt>Owed</dt><dd className="num">{money(summary.outstanding_cents)}</dd></div>
            </dl>
            {summary.ticket_capacity != null && (
              <p className="subtle">
                Room for {summary.ticket_capacity}.
              </p>
            )}
          </div>
          <p className="muted">
            <Link href="/events">← All fixtures</Link>
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
  const who = ticket.name ?? "A member";
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
              Cash
            </button>
            <button className="btn ghost sm" type="button" disabled={busy}
                    onClick={() => onPaid("transfer")}>
              Transfer
            </button>
          </>
        )}
      </div>
    </li>
  );
}
