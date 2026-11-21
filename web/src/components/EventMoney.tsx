"use client";

/// An event's money: its cost, who came, the bill, and your own share.
///
/// What each person sees is decided by the flags the API sends — `can_bill`
/// for whoever runs the session or looks after the club's money,
/// `can_manage_money` for letting somebody off — never by working out roles
/// here. A player sees their own share and the way to pay it.

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { api, errCode, isForbidden, money, readErr } from "@/lib/api";
import {
  CONFIRM_SHARE_CENTS,
  MAX_BILL_CENTS,
  MAX_SHARE_CENTS,
  STALE_CODES,
  parseAmount,
  shareGroups,
  shareStateTag,
  shareTag,
  toAmount,
  type BillResponse,
  type Candidate,
  type CashRecorded,
  type EventCost,
  type Preview,
  type PriceType,
  type Share,
  type TypePrice,
} from "@/lib/payments";
import { ReasonForm } from "@/components/ReasonForm";
import { ShareBill } from "@/components/ShareBill";
import type { T } from "@/lib/i18n";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

type Open = "none" | "cost" | "who" | "cancel" | "cash";

/// What a change came back with: the bill as it is now, when the call
/// returns it (otherwise it is reloaded), and a better sentence than the
/// default, when there is one.
type Outcome = { data?: BillResponse; said?: string } | void;

export function EventMoney({
  eventId,
  currency,
  inSeries,
  onBilling,
}: {
  eventId: string;
  /// The event's currency, for a cost that does not exist yet.
  currency: string;
  /// One week of a weekly series: a new cost can go on the later weeks too.
  inSeries: boolean;
  /// Told whether this event's money is run by bills, so the page can drop
  /// the older per-fixture fee lines that would contradict it.
  onBilling?: (billing: boolean) => void;
}) {
  const t = useT();
  const [data, setData] = useState<BillResponse | null>(null);
  const [hidden, setHidden] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  /// The server's objection to the open form, shown inside it.
  const [formError, setFormError] = useState<string | null>(null);
  const [open, setOpen] = useState<Open>("none");
  const [waiving, setWaiving] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setData(await api<BillResponse>("GET", `/events/${eventId}/bill`));
      setError(null);
    } catch (e) {
      // The other side of a fixture: the host club's money is not theirs to
      // see, and an error box about it would be noise.
      if (isForbidden(e) || (e as { status?: number }).status === 404) setHidden(true);
      else setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [eventId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (data) onBilling?.(!!data.cost || !!data.bill);
  }, [data, onBilling]);

  // A notification links to #money, which does not exist until this loads.
  const arrived = useRef(false);
  useEffect(() => {
    if (!data || arrived.current) return;
    arrived.current = true;
    if (window.location.hash === "#money") document.getElementById("money")?.scrollIntoView({ block: "start" });
  }, [data]);

  /// Runs one change. Somebody else having got there first (a stale version,
  /// already billed) reloads and says so in the server's words; any other
  /// refusal stays with the form it came from.
  const run = async (work: () => Promise<Outcome>, said: string): Promise<boolean> => {
    setBusy(true);
    setError(null);
    setNotice(null);
    setFormError(null);
    try {
      const out = await work();
      if (out?.data) setData(out.data);
      else await load();
      setNotice(out?.said ?? said);
      setOpen("none");
      setWaiving(null);
      return true;
    } catch (e) {
      const said = readErr(e, t("le.that_did_not_work"));
      if (STALE_CODES.has(errCode(e) ?? "")) {
        setOpen("none");
        setWaiving(null);
        await load();
        setError(said);
      } else {
        setFormError(said);
      }
      return false;
    } finally {
      setBusy(false);
    }
  };

  if (hidden || !data) {
    return error ? <p className="error" role="alert">{error}</p> : null;
  }
  const { cost, bill } = data;
  if (!cost && !bill && !data.can_bill) return null;

  const cur = bill?.currency ?? cost?.currency ?? currency;
  const over = new Date(data.end_at).getTime() < Date.now();
  const admin = data.can_bill || data.can_manage_money;
  const openForm = (which: Open) => {
    setFormError(null);
    setNotice(null);
    setWaiving(null);
    setOpen(which);
  };

  const sendBill = (body: { attendees: string[]; guests: string[]; note: string }, resplit: boolean) =>
    run(
      async () => ({
        data: await api<BillResponse>("POST", `/events/${eventId}/bill`, {
          attendees: body.attendees,
          guests: body.guests,
          note: body.note || undefined,
          version: resplit ? bill?.version : undefined,
        }),
      }),
      resplit ? t("pay.bill_resplit") : t("pay.bill_sent"),
    );

  return (
    <section className="panel money" id="money" aria-labelledby="money-title">
      <div className="panel-head">
        <h2 id="money-title">{t("pay.money")}</h2>
        {/* Unbilled, whoever runs it sees the cost in the row below, with
            the button to change it. */}
        {cost && !(data.can_bill && !bill) && <span className="tag gold">{costLine(cost, t)}</span>}
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      {data.my_share && <MyShare share={data.my_share} clubId={data.club_id} />}

      {admin && !data.has_payout_account && (
        <p className="pay-warn" role="note">
          {t("pay.no_bank_details_yet")}{" "}
          {data.can_manage_money && (
            <Link href={`/clubs/${data.club_id}/payments#bank-details`}>{t("pay.add_bank_details")}</Link>
          )}
        </p>
      )}

      {bill && !admin ? (
        !data.my_share && <p className="muted">{t("pay.not_on_this_bill")}</p>
      ) : bill ? (
        <>
          <p className="money-totals">
            {t("pay.collected_of", { paid: money(bill.paid_cents, cur), total: money(bill.total_cents, cur) })}
          </p>
          {(bill.waiting_cents > 0 || bill.owed_cents > 0) && (
            <p className="muted">
              {t("pay.waiting_and_owed", { waiting: money(bill.waiting_cents, cur), owed: money(bill.owed_cents, cur) })}
            </p>
          )}
          {bill.note && <p className="muted">{t("pay.bill_note", { note: bill.note })}</p>}
          {bill.surplus_cents > 0 && (
            <p className="subtle">{t("pay.surplus_note", { amount: money(bill.surplus_cents, cur) })}</p>
          )}

          {data.shares.length > 0 && (
            <ul className="pay-list money-shares" aria-label={t("pay.who_owes_what_on_bill")}>
              {data.shares.map((s) => (
                <li key={s.id}>
                  <div>
                    <strong>{s.name}</strong> {s.user_id == null && <span className="tag grey">{t("pay.guest")}</span>}
                    {s.state === "part_paid" && (
                      <div className="muted">
                        {t("pay.paid_of", { paid: money(s.paid_cents, s.currency), amount: money(s.amount_cents, s.currency) })}
                      </div>
                    )}
                    {s.state === "waived" && s.reason && (
                      <div className="muted">{t("pay.let_off_because", { reason: s.reason })}</div>
                    )}
                  </div>
                  <div className="pay-list-end">
                    <span className="num">{money(s.amount_cents, s.currency)}</span>
                    <span className={shareStateTag(s.state)}>{shareTag(s, t)}</span>
                    {data.can_manage_money && (s.state === "owed" || s.state === "part_paid") && waiving !== s.id && (
                      <button
                        className="btn"
                        type="button"
                        disabled={busy}
                        aria-label={t("pay.let_off_name", { name: s.name })}
                        onClick={() => {
                          setFormError(null);
                          setOpen("none");
                          setWaiving(s.id);
                        }}
                      >
                        {t("pay.let_off")}
                      </button>
                    )}
                  </div>
                  {waiving === s.id && (
                    <ReasonForm
                      label={t("pay.why_let_off", { name: s.name })}
                      hint={t("pay.why_let_off_hint")}
                      submitLabel={t("pay.let_off_name", { name: s.name })}
                      busy={busy}
                      error={formError}
                      onCancel={() => setWaiving(null)}
                      onSubmit={(reason) =>
                        void run(async () => {
                          await api("POST", `/shares/${s.id}/waive`, { reason });
                        }, t("pay.let_off_done", { name: s.name }))
                      }
                    />
                  )}
                </li>
              ))}
            </ul>
          )}

          {data.can_bill && (
            <ShareBill
              eventId={eventId}
              refreshKey={`${bill.id}:${bill.version}:${bill.paid_cents}:${bill.waiting_cents}:${bill.owed_cents}`}
            />
          )}

          {data.can_bill && open === "none" && (
            <div className="field-row money-actions">
              {owingShares(data.shares).length > 0 && (
                <button className="btn" type="button" onClick={() => openForm("cash")}>
                  {t("pw2.who_paid_cash")}
                </button>
              )}
              <button className="btn" type="button" onClick={() => openForm("who")}>
                {t("pay.change_who_came")}
              </button>
              <button className="btn ghost" type="button" onClick={() => openForm("cancel")}>
                {t("pay.cancel_bill")}
              </button>
            </div>
          )}
          {data.can_bill && open === "who" && (
            <WhoCame
              eventId={eventId}
              data={data}
              resplit
              busy={busy}
              error={formError}
              onSend={(body) => void sendBill(body, true)}
              onCancel={() => setOpen("none")}
            />
          )}
          {data.can_bill && open === "cash" && (
            <WhoPaidCash
              shares={owingShares(data.shares)}
              received={data.can_manage_money}
              busy={busy}
              error={formError}
              onCancel={() => setOpen("none")}
              onSave={(ids) =>
                void run(async () => {
                  const out = await api<CashRecorded>("POST", `/events/${eventId}/bill/cash`, { share_ids: ids });
                  const amount = money(out.total_cents, cur);
                  return {
                    said: out.received
                      ? t("pw2.cash_recorded", { count: out.recorded, n: out.recorded, amount })
                      : t("pw2.cash_recorded_waiting", { count: out.recorded, n: out.recorded, amount }),
                  };
                }, t("pw2.cash_recorded", { count: 0, n: 0, amount: money(0, cur) }))
              }
            />
          )}
          {data.can_bill && open === "cancel" && (
            <ReasonForm
              label={t("pay.why_cancel_bill")}
              hint={t("pay.cancel_bill_hint")}
              submitLabel={t("pay.cancel_bill")}
              danger
              busy={busy}
              error={formError}
              onCancel={() => setOpen("none")}
              onSubmit={(reason) =>
                void run(
                  async () => ({ data: await api<BillResponse>("POST", `/events/${eventId}/bill/void`, { reason }) }),
                  t("pay.bill_cancelled"),
                )
              }
            />
          )}
        </>
      ) : data.can_bill ? (
        <>
          {open === "cost" ? (
            <CostEditor
              cost={cost}
              clubId={data.club_id}
              prices={data.prices ?? []}
              currency={cur}
              inSeries={inSeries}
              busy={busy}
              error={formError}
              onCancel={() => setOpen("none")}
              onSave={(body) =>
                void run(async () => {
                  const out = await api<{ series_updated: number }>("PUT", `/events/${eventId}/cost`, body);
                  const weeks = out.series_updated;
                  return weeks > 0 ? { said: t("pay.cost_saved_weeks", { count: weeks, n: weeks }) } : undefined;
                }, t("pay.cost_saved"))
              }
              onRemove={() =>
                void run(async () => {
                  await api("DELETE", `/events/${eventId}/cost`);
                }, t("pay.cost_removed"))
              }
            />
          ) : cost ? (
            <div className="row money-cost">
              <div>
                <strong>{costLine(cost, t)}</strong>
                {cost.mode === "per_player" && (data.prices?.length ?? 0) > 0 && (
                  <div className="muted">{pricesLine(data.prices ?? [], cur)}</div>
                )}
                {cost.note && <div className="muted">{cost.note}</div>}
              </div>
              <button className="btn" type="button" onClick={() => openForm("cost")}>
                {t("pay.change_cost")}
              </button>
            </div>
          ) : (
            <div className="row money-cost">
              <p className="muted">{t("pay.add_a_cost_help")}</p>
              <button className="btn" type="button" onClick={() => openForm("cost")}>
                {t("pay.add_a_cost")}
              </button>
            </div>
          )}

          {cost && open !== "cost" && (over || open === "who") ? (
            <WhoCame
              eventId={eventId}
              data={data}
              resplit={false}
              busy={busy}
              error={formError}
              onSend={(body) => void sendBill(body, false)}
              onCancel={over ? undefined : () => setOpen("none")}
            />
          ) : (
            cost &&
            open === "none" && (
              <div className="row money-cost">
                <p className="muted">{t("pay.not_over_yet")}</p>
                <button className="btn" type="button" onClick={() => openForm("who")}>
                  {t("pay.send_the_bill_now")}
                </button>
              </div>
            )
          )}
        </>
      ) : (
        cost && !data.my_share && <p className="muted">{t("pay.billed_after")}</p>
      )}
    </section>
  );
}

/// Still something to pay on: owed in full or in part, with nothing waiting
/// to be checked against it.
function owingShares(shares: Share[]): Share[] {
  return shares.filter(
    (s) => (s.state === "owed" || s.state === "part_paid") && s.amount_cents - s.paid_cents - s.waiting_cents > 0,
  );
}

/// "Who paid cash?" at the ground: tick, then save. A money admin's tick
/// counts as received; anybody else's — a captain who collected it — waits
/// for the treasurer to have the cash in hand.
function WhoPaidCash({
  shares,
  received,
  busy,
  error,
  onSave,
  onCancel,
}: {
  shares: Share[];
  /// Whether a tick here counts as received straight away.
  received: boolean;
  busy: boolean;
  error: string | null;
  onSave: (shareIds: string[]) => void;
  onCancel: () => void;
}) {
  const t = useT();
  const id = useId();
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  const toggle = (sid: string) =>
    setTicked((cur) => {
      const next = new Set(cur);
      if (next.has(sid)) next.delete(sid);
      else next.add(sid);
      return next;
    });
  const total = shares.filter((s) => ticked.has(s.id)).reduce((sum, s) => sum + s.amount_cents - s.paid_cents - s.waiting_cents, 0);
  const cur = shares[0]?.currency ?? "GBP";

  return (
    <form
      className="who-came cash-form"
      aria-labelledby={`${id}-title`}
      onSubmit={(e) => {
        e.preventDefault();
        if (ticked.size > 0) onSave([...ticked]);
      }}
    >
      <h3 id={`${id}-title`}>{t("pw2.who_paid_cash")}</h3>
      <p className="muted">{received ? t("pw2.who_paid_cash_help") : t("pw2.who_paid_cash_help_collector")}</p>
      <fieldset className="who-list">
        <legend className="sr-only">{t("pw2.who_paid_cash")}</legend>
        {shares.map((s) => (
          <label className="who-person" key={s.id}>
            <input type="checkbox" checked={ticked.has(s.id)} onChange={() => toggle(s.id)} />
            <span className="who-name">{s.name}</span>
            <span className="num">{money(s.amount_cents - s.paid_cents - s.waiting_cents, s.currency)}</span>
          </label>
        ))}
      </fieldset>
      {ticked.size > 0 && (
        <p className="money-preview" role="status">
          <strong>{t("pw2.cash_total", { count: ticked.size, n: ticked.size, amount: money(total, cur) })}</strong>
        </p>
      )}
      {error && <p className="field-error" role="alert">{error}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy || ticked.size === 0}>
          {t("pw2.save_cash")}
        </button>
        <button className="btn" type="button" disabled={busy} onClick={onCancel}>
          {t("pay.never_mind")}
        </button>
      </div>
    </form>
  );
}

/// "Junior £3.00 · Guest £8.00": the session's own prices by group.
function pricesLine(prices: TypePrice[], currency: string): string {
  return prices.map((p) => `${p.name} ${money(p.amount_cents, currency)}`).join(" · ");
}

function costLine(cost: EventCost, t: T): string {
  const amount = money(cost.amount_cents, cost.currency);
  return cost.mode === "split_total" ? t("pay.cost_split", { amount }) : t("pay.cost_each", { amount });
}

/// Your own share of the bill, and the way to pay it.
function MyShare({ share: s, clubId }: { share: Share; clubId: string }) {
  const t = useT();
  const owes = s.state === "owed" || s.state === "part_paid";
  const covered = s.state === "covered";
  return (
    <div className="money-mine">
      <div>
        <p className="stat-label">{t("pay.your_share")}</p>
        {covered ? (
          <p className="pay-big">{t("pw3.nothing_to_pay")}</p>
        ) : (
          <p className="pay-big num">{money(s.amount_cents, s.currency)}</p>
        )}
        <span className={shareStateTag(s.state)}>{shareTag(s, t)}</span>
        {s.state === "waiting" && <p className="muted">{t("pay.waiting_for_the_club")}</p>}
        {s.state === "part_paid" && (
          <p className="muted">
            {t("pay.paid_of", { paid: money(s.paid_cents, s.currency), amount: money(s.amount_cents, s.currency) })}
          </p>
        )}
        {s.state === "waived" && (
          <p className="muted">{s.reason ? t("pay.let_off_because", { reason: s.reason }) : t("pay.you_were_let_off")}</p>
        )}
      </div>
      {owes && (
        <Link className="btn primary lg" href={`/clubs/${clubId}/pay`}>
          {t("pay.pay")}
        </Link>
      )}
    </div>
  );
}

const RSVP: Record<string, Key> = {
  going: "pay.rsvp_going",
  maybe: "pay.rsvp_maybe",
  not_going: "pay.rsvp_not_going",
  invited: "pay.rsvp_invited",
};

/// "Who came?": tick them, add any guests, watch the split, send it.
///
/// The total is asked of the server as the ticks change, so what is shown is
/// exactly what the bill will say — the leftover pennies included.
function WhoCame({
  eventId,
  data,
  resplit,
  busy,
  error,
  onSend,
  onCancel,
}: {
  eventId: string;
  data: BillResponse;
  resplit: boolean;
  busy: boolean;
  error: string | null;
  onSend: (body: { attendees: string[]; guests: string[]; note: string }) => void;
  onCancel?: () => void;
}) {
  const t = useT();
  const id = useId();
  const known = useMemo(() => new Set(data.candidates.map((c) => c.user_id)), [data.candidates]);
  // A re-split starts from who is on the bill now; a first bill from who
  // turned up, or failing that who said they would.
  const [ticked, setTicked] = useState<Set<string>>(() =>
    resplit
      ? new Set(data.shares.flatMap((s) => (s.user_id && known.has(s.user_id) ? [s.user_id] : [])))
      : new Set(data.candidates.filter((c) => c.suggested).map((c) => c.user_id)),
  );
  const [guests, setGuests] = useState<string[]>(resplit ? data.guests : []);
  const [guest, setGuest] = useState("");
  const [note, setNote] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);

  useEffect(() => {
    const abort = new AbortController();
    const timer = window.setTimeout(async () => {
      try {
        const p = await api<Preview>(
          "POST",
          `/events/${eventId}/bill/preview`,
          { attendees: [...ticked], guests },
          true,
          false,
          abort.signal,
        );
        setPreview(p);
        setPreviewError(null);
      } catch (e) {
        if (abort.signal.aborted) return;
        setPreview(null);
        // "Nobody's ticked as coming…" — the server's words say what to do.
        setPreviewError(readErr(e, t("le.something_went_wrong")));
      }
    }, 250);
    return () => {
      window.clearTimeout(timer);
      abort.abort();
    };
  }, [eventId, ticked, guests, t]);

  const toggle = (userId: string) =>
    setTicked((cur) => {
      const next = new Set(cur);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });

  const addGuest = () => {
    const name = guest.trim().replace(/\s+/g, " ");
    if (!name) return;
    if (!guests.some((g) => g.toLowerCase() === name.toLowerCase())) setGuests([...guests, name]);
    setGuest("");
  };

  const asked = data.candidates.filter((c) => c.rsvp !== "not_invited");
  const others = data.candidates.filter((c) => c.rsvp === "not_invited");
  // Somebody a pass or a free price covers owes nothing, and is not counted.
  const paying = preview ? preview.shares.filter((s) => !s.covered) : [];
  const covered = preview ? preview.shares.filter((s) => s.covered) : [];
  const groups = shareGroups(paying.map((s) => s.amount_cents));

  const person = (c: Candidate) => (
    <label className="who-person" key={c.user_id}>
      <input type="checkbox" checked={ticked.has(c.user_id)} onChange={() => toggle(c.user_id)} />
      <span className="who-name">{c.name}</span>
      <span className="subtle">
        {c.attended ? t("pay.was_there") : RSVP[c.rsvp] ? t(RSVP[c.rsvp]) : ""}
      </span>
    </label>
  );

  return (
    <form
      className="who-came"
      aria-labelledby={`${id}-title`}
      onSubmit={(e) => {
        e.preventDefault();
        onSend({ attendees: [...ticked], guests, note: note.trim() });
      }}
    >
      <h3 id={`${id}-title`}>{resplit ? t("pay.change_who_came") : t("pay.who_came")}</h3>
      <p className="muted">{resplit ? t("pay.resplit_help") : t("pay.who_came_help")}</p>

      <fieldset className="who-list">
        <legend className="sr-only">{t("pay.who_came")}</legend>
        {asked.map(person)}
      </fieldset>
      {others.length > 0 && (
        <fieldset className="who-list">
          <legend>{t("pay.others_in_the_club")}</legend>
          {others.map(person)}
        </fieldset>
      )}

      <div className="field-row who-guest">
        <label htmlFor={`${id}-guest`}>
          {t("pay.add_a_guest")}
          <input
            id={`${id}-guest`}
            value={guest}
            maxLength={60}
            placeholder={t("pay.guest_hint")}
            onChange={(e) => setGuest(e.target.value)}
            onKeyDown={(e) => {
              // Enter adds the guest rather than sending the whole bill.
              if (e.key === "Enter") {
                e.preventDefault();
                addGuest();
              }
            }}
          />
        </label>
        <button className="btn" type="button" disabled={!guest.trim()} onClick={addGuest}>
          {t("pay.add")}
        </button>
      </div>
      {guests.length > 0 && (
        <ul className="who-guests" aria-label={t("pay.guests")}>
          {guests.map((g) => (
            <li key={g}>
              <span>{g}</span>
              <button
                className="btn ghost"
                type="button"
                aria-label={t("pay.remove_name", { name: g })}
                onClick={() => setGuests(guests.filter((x) => x !== g))}
              >
                {t("pay.remove")}
              </button>
            </li>
          ))}
        </ul>
      )}

      <label htmlFor={`${id}-note`}>
        {t("pay.note_for_everyone")}
        <input
          id={`${id}-note`}
          value={note}
          maxLength={200}
          placeholder={t("pay.note_for_everyone_hint")}
          onChange={(e) => setNote(e.target.value)}
        />
      </label>

      <div className="money-preview" role="status" aria-live="polite">
        {previewError ? (
          <span>{previewError}</span>
        ) : preview ? (
          <>
            <strong>
              {t("pay.preview_total", {
                count: paying.length,
                n: paying.length,
                total: money(preview.total_cents, preview.currency),
              })}
            </strong>
            {groups.length > 0 && (
              <span>
                {groups.length === 1
                  ? t("pay.each", { amount: money(groups[0].amount_cents, preview.currency) })
                  : groups
                      .map((g) => t("pay.n_pay", { count: g.count, n: g.count, amount: money(g.amount_cents, preview.currency) }))
                      .join(", ")}
              </span>
            )}
            {covered.length > 0 && (
              <span>
                {t("pw3.owe_nothing", { names: covered.map((s) => `${s.name} (${s.covered})`).join(", ") })}
              </span>
            )}
            {preview.surplus_cents > 0 && (
              <span className="subtle">{t("pay.surplus_note", { amount: money(preview.surplus_cents, preview.currency) })}</span>
            )}
          </>
        ) : null}
      </div>

      {error && <p className="field-error" role="alert">{error}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy || ticked.size + guests.length === 0}>
          {resplit ? t("pay.resplit_the_bill") : t("pay.send_the_bill")}
        </button>
        {onCancel && (
          <button className="btn" type="button" onClick={onCancel} disabled={busy}>
            {t("pay.never_mind")}
          </button>
        )}
      </div>
    </form>
  );
}

type CostBody = {
  mode: string;
  amount_cents: number;
  note?: string;
  apply_to_series: boolean;
  /// The session's own prices by group; left out, they stay as they are.
  prices?: { price_type_id: string; amount_cents: number }[];
};

/// Setting what the session costs, before it is billed — and, for a price
/// each, a different one for juniors, students or guests.
function CostEditor({
  cost,
  clubId,
  prices,
  currency,
  inSeries,
  busy,
  error,
  onSave,
  onRemove,
  onCancel,
}: {
  cost: EventCost | null;
  clubId: string;
  prices: TypePrice[];
  currency: string;
  inSeries: boolean;
  busy: boolean;
  error: string | null;
  onSave: (body: CostBody) => void;
  onRemove: () => void;
  onCancel: () => void;
}) {
  const t = useT();
  const id = useId();
  const [mode, setMode] = useState(cost?.mode ?? "split_total");
  const [amount, setAmount] = useState(cost ? toAmount(cost.amount_cents) : "");
  const [note, setNote] = useState(cost?.note ?? "");
  const [series, setSeries] = useState(false);
  const [sure, setSure] = useState(false);
  /// The club's groups with a price of their own. None: the question is not asked.
  const [groups, setGroups] = useState<PriceType[]>([]);
  const [byGroup, setByGroup] = useState(prices.length > 0);
  const [groupAmounts, setGroupAmounts] = useState<Record<string, string>>(() =>
    Object.fromEntries(prices.map((p) => [p.price_type_id, toAmount(p.amount_cents)])),
  );

  useEffect(() => {
    api<PriceType[]>("GET", `/clubs/${clubId}/price-types`)
      .then((all) => setGroups(all.filter((g) => !g.archived_at && !g.free)))
      .catch(() => setGroups([]));
  }, [clubId]);

  const check = costCheck(mode, amount, currency, t);
  const perPlayer = mode === "per_player";
  // Each group's price: empty means the usual price, 0 means free.
  const groupCents = groups.map((g) => {
    const raw = (groupAmounts[g.id] ?? "").trim();
    return { g, raw, cents: raw ? parseAmount(raw) : null };
  });
  const groupProblem =
    perPlayer && byGroup && groupCents.some((x) => x.raw && (x.cents == null || x.cents > MAX_SHARE_CENTS))
      ? t("pay.not_an_amount")
      : null;
  const said = check.problem ?? groupProblem ?? error;

  return (
    <form
      className="cost-form"
      onSubmit={(e) => {
        e.preventDefault();
        if (check.cents == null || check.problem || groupProblem || (check.confirm && !sure)) return;
        const set = groupCents.flatMap((x) => (x.cents != null ? [{ price_type_id: x.g.id, amount_cents: x.cents }] : []));
        onSave({
          mode,
          amount_cents: check.cents,
          note: note.trim() || undefined,
          apply_to_series: series,
          // Ticked: these replace the session's prices. Unticked: clear any
          // it had. A split total has none to send.
          prices: perPlayer ? (byGroup ? set : prices.length > 0 ? [] : undefined) : undefined,
        });
      }}
    >
      <CostModePicker mode={mode} onMode={setMode} />
      <div className="setup-fields">
        <label htmlFor={`${id}-amount`}>
          <span id={`${id}-amount-label`}>
            {mode === "split_total" ? t("pay.total_to_split") : t("pay.each_person_pays")}
          </span>
          <input
            id={`${id}-amount`}
            aria-labelledby={`${id}-amount-label`}
            inputMode="decimal"
            value={amount}
            placeholder={mode === "split_total" ? "60.00" : "5.00"}
            aria-invalid={said ? true : undefined}
            aria-describedby={said ? `${id}-error` : `${id}-hint`}
            onChange={(e) => {
              setAmount(e.target.value);
              setSure(false);
            }}
          />
          <span className="subtle" id={`${id}-hint`}>
            {mode === "split_total" ? t("pay.split_hint") : t("pay.each_hint")}
          </span>
          {said && (
            <span className="field-error" id={`${id}-error`}>
              {said}
            </span>
          )}
        </label>
        <label htmlFor={`${id}-note`}>
          {t("pay.cost_note")}
          <input
            id={`${id}-note`}
            value={note}
            maxLength={200}
            placeholder={t("pay.cost_note_hint")}
            onChange={(e) => setNote(e.target.value)}
          />
        </label>
      </div>
      {perPlayer && groups.length > 0 && (
        <div className="group-prices">
          <label className="check-row">
            <input type="checkbox" checked={byGroup} onChange={(e) => setByGroup(e.target.checked)} />
            <span>
              <strong>{t("pw3.different_price_q")}</strong>
              <span className="subtle">{t("pw3.different_price_hint")}</span>
            </span>
          </label>
          {byGroup && (
            <div className="setup-fields">
              {groupCents.map(({ g, raw }) => (
                <label key={g.id} htmlFor={`${id}-g-${g.id}`}>
                  <span id={`${id}-g-${g.id}-label`}>{t("pw3.group_price", { group: g.name })}</span>
                  <input
                    id={`${id}-g-${g.id}`}
                    aria-labelledby={`${id}-g-${g.id}-label`}
                    inputMode="decimal"
                    value={raw}
                    placeholder={check.cents != null ? toAmount(check.cents) : "3.00"}
                    onChange={(e) => setGroupAmounts({ ...groupAmounts, [g.id]: e.target.value })}
                  />
                </label>
              ))}
            </div>
          )}
        </div>
      )}
      {check.confirm && (
        <label className="check-row">
          <input type="checkbox" checked={sure} onChange={(e) => setSure(e.target.checked)} />
          <span>
            <strong>{t("pay.yes_amount_each", { amount: money(check.cents ?? 0, currency) })}</strong>
            <span className="subtle">{t("pay.big_amount_check")}</span>
          </span>
        </label>
      )}
      {inSeries && (
        <label className="check-row">
          <input type="checkbox" checked={series} onChange={(e) => setSeries(e.target.checked)} />
          <span>
            <strong>{t("pay.apply_to_later_weeks")}</strong>
            <span className="subtle">{t("pay.apply_to_later_weeks_hint")}</span>
          </span>
        </label>
      )}
      <div className="field-row">
        <button
          className="btn primary"
          type="submit"
          disabled={busy || check.cents == null || !!check.problem || !!groupProblem || (check.confirm && !sure)}
        >
          {t("pay.save_cost")}
        </button>
        {cost && (
          <button className="btn ghost" type="button" disabled={busy} onClick={onRemove}>
            {t("pay.remove_cost")}
          </button>
        )}
        <button className="btn" type="button" disabled={busy} onClick={onCancel}>
          {t("pay.never_mind")}
        </button>
      </div>
    </form>
  );
}

/// "Split a total" or "Same for everyone". Shared with the schedule form.
export function CostModePicker({
  mode,
  onMode,
  withNone = false,
}: {
  mode: string;
  onMode: (mode: string) => void;
  /// Offer "No cost" first, for a form where the cost is optional.
  withNone?: boolean;
}) {
  const t = useT();
  const choices: [string, Key][] = [
    ...(withNone ? ([["", "pay.no_cost"]] as [string, Key][]) : []),
    ["split_total", "pay.split_a_total"],
    ["per_player", "pay.same_for_everyone"],
  ];
  return (
    <fieldset className="chip-set">
      <legend>{t("pay.how_its_paid")}</legend>
      {choices.map(([value, label]) => (
        <button
          key={value || "none"}
          type="button"
          className={`chip${mode === value ? " on" : ""}`}
          aria-pressed={mode === value}
          onClick={() => onMode(value)}
        >
          {t(label)}
        </button>
      ))}
    </fieldset>
  );
}

/// What is wrong with a typed cost, if anything, and whether it is big enough
/// a head to ask "is that right?" first. The hard limits are the API's own.
export function costCheck(
  mode: string,
  raw: string,
  currency: string,
  t: T,
): { cents: number | null; problem: string | null; confirm: boolean } {
  if (!raw.trim()) return { cents: null, problem: null, confirm: false };
  const cents = parseAmount(raw);
  if (cents == null || cents <= 0) return { cents: null, problem: t("pay.not_an_amount"), confirm: false };
  if (mode === "per_player" && cents > MAX_SHARE_CENTS) {
    return { cents, problem: t("pay.too_much_each", { max: money(MAX_SHARE_CENTS, currency) }), confirm: false };
  }
  if (cents > MAX_BILL_CENTS) {
    return { cents, problem: t("pay.too_much_total", { max: money(MAX_BILL_CENTS, currency) }), confirm: false };
  }
  return { cents, problem: null, confirm: mode === "per_player" && cents > CONFIRM_SHARE_CENTS };
}
