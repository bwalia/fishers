"use client";

/// "Passes" on the club's pay screen (plan §3, §11): the passes the club
/// offers, one line each with **Get this pass**; your own pass and how it
/// stands, in words; and for a monthly pass, exactly what to type into a
/// banking app to set up the standing order that pays it.
///
/// The app never takes money. A monthly pass is paid by the player's own
/// standing order; the club ticks each month off as it arrives.

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { api, errCode, money, readErr } from "@/lib/api";
import {
  passCovers,
  passPrice,
  postOnce,
  toAmount,
  useAttemptKey,
  type BankDetails,
  type MyPass,
  type PassHolder,
  type PassPlan,
  type PriceType,
} from "@/lib/payments";
import { longDay, passState } from "@/lib/passes";
import { firstName } from "@/lib/pay-link";
import { PayeeRows, PayRow, SendText } from "@/components/PayDetails";
import { useT } from "@/lib/i18n/provider";

type Person = { user_id: string; name: string };

export function PlayerPasses({
  clubId,
  meId,
  account,
  people,
  refreshKey,
  onChanged,
}: {
  clubId: string;
  meId: string | null;
  /// The club's bank details, when the pay screen has them to show.
  account: BankDetails | null;
  /// Those you pay for in this club, who can be put on a pass too.
  people: Person[];
  /// Changes when the pay screen reloads, so a pass charged meanwhile shows.
  refreshKey: string;
  /// A pass was got or cancelled: what you owe has changed.
  onChanged: () => Promise<void>;
}) {
  const t = useT();
  const [plans, setPlans] = useState<PassPlan[] | null>(null);
  const [mine, setMine] = useState<MyPass[]>([]);
  const [types, setTypes] = useState<PriceType[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  /// `join:<plan id>` or `cancel:<holder id>`: the question open.
  const [asking, setAsking] = useState<string | null>(null);
  const [askError, setAskError] = useState<string | null>(null);
  const [joinFor, setJoinFor] = useState("");
  const [busy, setBusy] = useState(false);
  const attempt = useAttemptKey();

  const load = useCallback(async () => {
    try {
      const [p, m, ty] = await Promise.all([
        api<PassPlan[]>("GET", `/clubs/${clubId}/passes`),
        api<MyPass[]>("GET", "/me/passes"),
        api<PriceType[]>("GET", `/clubs/${clubId}/price-types`).catch(() => [] as PriceType[]),
      ]);
      setPlans(p);
      setMine(m.filter((x) => x.club_id === clubId));
      setTypes(ty);
      setError(null);
    } catch (e) {
      // An API from before passes answers 404: say nothing at all.
      if ((e as { status?: number }).status === 404) setPlans([]);
      else setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [clubId, t]);

  useEffect(() => {
    void load();
  }, [load, refreshKey]);

  // The club page links to #passes, which exists only once this has loaded.
  const arrived = useRef(false);
  useEffect(() => {
    if (!plans || arrived.current) return;
    arrived.current = true;
    if (window.location.hash === "#passes") document.getElementById("passes")?.scrollIntoView({ block: "start" });
  }, [plans]);

  if (!plans) return error ? <p className="error" role="alert">{error}</p> : null;
  const offered = plans.filter((p) => !p.archived_at && !p.mine);
  if (offered.length === 0 && mine.length === 0) return null;
  const planOf = (h: PassHolder) => plans.find((p) => p.id === h.plan_id);
  const groupName = (id: string | null) => (id ? types.find((x) => x.id === id)?.name : undefined);

  const ask = (what: string) => {
    setAsking(what);
    setAskError(null);
    setNotice(null);
    setJoinFor("");
  };

  const join = async (plan: PassPlan) => {
    setBusy(true);
    setAskError(null);
    const body = joinFor ? { for_user_id: joinFor } : {};
    try {
      await postOnce<PassHolder>(`/passes/${plan.id}/join`, body, attempt.key(JSON.stringify([plan.id, body])));
      attempt.done();
      const who = people.find((p) => p.user_id === joinFor);
      setAsking(null);
      setNotice(
        who
          ? t("pw3.joined_for", { name: who.name, pass: plan.name })
          : plan.billing === "monthly"
            ? t("pw3.joined_monthly", { pass: plan.name })
            : t("pw3.joined", { pass: plan.name }),
      );
      await Promise.all([load(), onChanged()]);
    } catch (e) {
      if (errCode(e) === "already_on_pass") {
        attempt.done();
        await load();
      }
      setAskError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  const cancel = async (h: MyPass) => {
    setBusy(true);
    setAskError(null);
    try {
      const after = await api<PassHolder>("POST", `/pass-holders/${h.id}/cancel`);
      setAsking(null);
      setNotice(
        h.billing === "monthly" && after.ends_on
          ? t("pw3.cancelled_monthly", { date: longDay(after.ends_on) })
          : t("pw3.cancelled_pass", { pass: h.plan_name }),
      );
      await Promise.all([load(), onChanged()]);
    } catch (e) {
      if (errCode(e) === "already_cancelled") await load();
      setAskError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel passes" id="passes" aria-labelledby="passes-title">
      <h2 id="passes-title">{t("pw3.passes")}</h2>
      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {mine.map((h) => (
        <OwnPass
          key={h.id}
          pass={h}
          plan={planOf(h)}
          mine={!meId || h.user_id === meId}
          account={account}
          asking={asking === `cancel:${h.id}`}
          askError={askError}
          busy={busy}
          onAsk={() => ask(`cancel:${h.id}`)}
          onNever={() => setAsking(null)}
          onCancel={() => void cancel(h)}
        />
      ))}

      {offered.length > 0 && (
        <>
          {mine.length > 0 && <h3 className="pass-more">{t("pw3.more_passes")}</h3>}
          <ul className="pass-offers">
            {offered.map((p) => {
              const group = groupName(p.price_type_id);
              const open = asking === `join:${p.id}`;
              return (
                <li key={p.id}>
                  <div className="pass-offer">
                    <div>
                      <strong className="pass-name">{p.name}</strong>
                      <div className="pass-price">{passPrice(p, t)}</div>
                      <div className="muted">{passCovers(p, t)}</div>
                      {group && <div className="subtle">{t("pw3.only_for", { group })}</div>}
                    </div>
                    {p.open_to_join ? (
                      !open && (
                        <button
                          className="btn primary lg"
                          type="button"
                          aria-label={t("pw3.get_pass_named", { pass: p.name })}
                          onClick={() => ask(`join:${p.id}`)}
                        >
                          {t("pw3.get_this_pass")}
                        </button>
                      )
                    ) : (
                      <p className="subtle pass-ask">{t("pw3.ask_secretary")}</p>
                    )}
                  </div>
                  {open && (
                    <JoinConfirm
                      plan={p}
                      people={people}
                      joinFor={joinFor}
                      onFor={setJoinFor}
                      busy={busy}
                      error={askError}
                      onYes={() => void join(p)}
                      onNever={() => setAsking(null)}
                    />
                  )}
                </li>
              );
            })}
          </ul>
        </>
      )}
    </section>
  );
}

/// "Get Monthly nets?" — what it costs and how it's paid, then yes or no.
function JoinConfirm({
  plan: p,
  people,
  joinFor,
  onFor,
  busy,
  error,
  onYes,
  onNever,
}: {
  plan: PassPlan;
  people: Person[];
  joinFor: string;
  onFor: (id: string) => void;
  busy: boolean;
  error: string | null;
  onYes: () => void;
  onNever: () => void;
}) {
  const t = useT();
  const id = useId();
  const charge = money(p.charge_cents, p.currency);
  return (
    <div className="confirm-box pass-confirm" role="group" aria-labelledby={`${id}-q`}>
      <p id={`${id}-q`}>
        <strong>{t("pw3.get_pass_q", { pass: p.name })}</strong>
      </p>
      <p>
        {p.billing === "monthly"
          ? t("pw3.join_monthly", { amount: charge })
          : p.billing === "instalments"
            ? t("pw3.join_parts", { amount: charge })
            : t("pw3.join_once", { amount: charge })}
      </p>
      {people.length > 0 && (
        <fieldset className="chip-set">
          <legend>{t("pw3.who_is_it_for")}</legend>
          {[{ user_id: "", name: t("pw3.me") }, ...people].map((who) => (
            <button
              key={who.user_id || "me"}
              type="button"
              className={`chip${joinFor === who.user_id ? " on" : ""}`}
              aria-pressed={joinFor === who.user_id}
              onClick={() => onFor(who.user_id)}
            >
              {who.name}
            </button>
          ))}
        </fieldset>
      )}
      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}
      <div className="field-row">
        <button className="btn primary" type="button" disabled={busy} onClick={onYes}>
          {t("pw3.yes_get_it")}
        </button>
        <button className="btn" type="button" disabled={busy} onClick={onNever}>
          {t("pay.never_mind")}
        </button>
      </div>
    </div>
  );
}

/// A pass you (or somebody you pay for) are on: how it stands, the
/// standing order to set up for a monthly one, and Cancel.
function OwnPass({
  pass: h,
  plan,
  mine,
  account,
  asking,
  askError,
  busy,
  onAsk,
  onNever,
  onCancel,
}: {
  pass: MyPass;
  plan: PassPlan | undefined;
  mine: boolean;
  account: BankDetails | null;
  asking: boolean;
  askError: string | null;
  busy: boolean;
  onAsk: () => void;
  onNever: () => void;
  onCancel: () => void;
}) {
  const t = useT();
  const id = useId();
  const state = passState(h, plan ?? undefined);
  const first = firstName(h.name);
  const monthly = h.billing === "monthly";

  const [line, warn] = ((): [string, boolean] => {
    switch (state.kind) {
      case "suspended":
        return [t("pw3.pass_suspended"), true];
      case "behind":
        return [t("pw3.pass_behind"), true];
      case "cancelled":
        return [t("pw3.pass_cancelled_until", { date: longDay(state.until) }), false];
      case "starts":
        return [t("pw3.pass_starts", { date: longDay(state.on) }), false];
      case "sessions":
        return [
          state.left > 0 ? t("pw3.pass_sessions_left", { count: state.left, n: state.left }) : t("pw3.pass_no_sessions"),
          state.left === 0,
        ];
      case "until":
        return [t("pw3.pass_covered_until", { date: longDay(state.on) }), false];
      case "monthly":
        return [t("pw3.pass_monthly_running"), false];
      case "running":
        return [t("pw3.pass_running"), false];
      case "stopped":
        return [t("pw3.pass_not_running"), false];
    }
  })();

  return (
    <article className={`pass-card${warn ? " is-warn" : ""}`} aria-labelledby={`${id}-name`}>
      <div className="pass-card-head">
        <h3 id={`${id}-name`}>{h.plan_name}</h3>
        {!mine && <span className="tag grey">{t("pw3.for_name", { name: h.name })}</span>}
      </div>
      <p className={warn ? "pay-warn pass-state" : "pass-state"} role={warn ? "note" : undefined}>
        {state.kind !== "suspended" && state.kind !== "behind" && state.kind !== "cancelled" && "✓ "}
        {line}
      </p>
      {!h.cancelled_at && h.next_charge_on && (
        <p className="muted">
          {monthly
            ? t("pw3.next_payment", { date: longDay(h.next_charge_on), amount: money(h.charge_cents, h.currency) })
            : t("pw3.next_part", { date: longDay(h.next_charge_on), amount: money(h.charge_cents, h.currency) })}
        </p>
      )}

      {h.standing_order && (
        <StandingOrderCard pass={h} account={account} />
      )}
      {monthly && h.cancelled_at && (
        <p className="pay-warn" role="note">
          {t("pw3.cancel_bank_too")}
        </p>
      )}

      {!h.cancelled_at &&
        (asking ? (
          <div className="confirm-box" role="group" aria-labelledby={`${id}-cancel`}>
            <p id={`${id}-cancel`}>
              <strong>{t("pw3.cancel_q", { pass: h.plan_name })}</strong>
            </p>
            <p>{monthly ? t("pw3.cancel_monthly_help") : t("pw3.cancel_once_help")}</p>
            {askError && (
              <p className="field-error" role="alert">
                {askError}
              </p>
            )}
            <div className="field-row">
              <button className="btn danger" type="button" disabled={busy} onClick={onCancel}>
                {t("pw3.yes_cancel_it")}
              </button>
              <button className="btn" type="button" disabled={busy} onClick={onNever}>
                {t("pw3.keep_it")}
              </button>
            </div>
          </div>
        ) : (
          <button className="btn ghost pass-cancel" type="button" onClick={onAsk}>
            {mine ? t("pw3.cancel_my_pass") : t("pw3.cancel_their_pass", { name: first })}
          </button>
        ))}
    </article>
  );
}

/// "Set up your standing order": what the banking app asks for, one big row
/// each with Copy, and "Send to someone who pays for me".
function StandingOrderCard({ pass: h, account }: { pass: MyPass; account: BankDetails | null }) {
  const t = useT();
  const so = h.standing_order;
  if (!so) return null;
  const amount = money(so.amount_cents, h.currency);
  const start = longDay(so.first_payment_on);

  const text = [
    t("pw3.so_send_line", { pass: h.plan_name, amount }),
    ...(account
      ? [
          `${t("pw2.row_name")}: ${account.holder_name}`,
          `${t("pay.sort_code")}: ${account.sort_code}`,
          `${t("pay.account_number")}: ${account.account_number}`,
        ]
      : []),
    `${t("pay.amount")}: ${amount}`,
    `${t("pw3.so_how_often")}: ${t("pw3.every_month")}`,
    `${t("pw3.so_first_payment")}: ${start}`,
    `${t("pay.reference")}: ${so.reference}`,
  ].join("\n");

  return (
    <div className="standing-order">
      <h4>{t("pw3.so_title")}</h4>
      <p className="muted">{t("pw3.so_help")}</p>
      <dl className="pay-details pay-rows">
        {account && <PayeeRows account={account} />}
        <PayRow term={t("pay.amount")} value={amount} copy={toAmount(so.amount_cents)} what={t("pw3.what_amount")} />
        <PayRow term={t("pw3.so_how_often")} value={t("pw3.every_month")} what={t("pw3.what_how_often")} />
        <PayRow term={t("pw3.so_first_payment")} value={start} what={t("pw3.what_first_payment")} />
        <PayRow term={t("pw2.row_reference")} value={so.reference} what={t("pw2.what_reference")} />
      </dl>
      {!account && <p className="subtle">{t("pw3.so_same_details")}</p>}
      <p className="subtle">{t("pw3.so_not_twice")}</p>
      <SendText
        title={t("pw3.so_send_title")}
        help={t("pw2.send_details_help")}
        button={t("pw3.so_send_button")}
        text={text}
      />
    </div>
  );
}
