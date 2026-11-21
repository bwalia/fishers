"use client";

/// Paying the club, signed in (plan §5.2): what you owe and what for, who the
/// money goes to, the four things your banking app asks for — each with a
/// Copy button — then "I've paid" or "I paid cash". After that, "Thanks —
/// waiting for Aman to check", with Undo and Add a screenshot.
///
/// A parent (plan §4) sees each junior they pay for as their own block, and
/// one payment covers everyone: "I've paid for everyone". "I'm paying for
/// friends too" adds friends from the same sessions. Below it all, the
/// club's passes (plan §3).
///
/// The app never touches the money. It goes from the player's bank to the
/// club's; this page only says where, and records that they say they sent it.
/// A treasurer confirms it once it shows up. The same design as the public
/// pay page (`/pay/<token>`), so a player sees one thing whichever way in.

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { api, errCode, getStoredUser, money, readErr } from "@/lib/api";
import {
  STALE_CODES,
  checker,
  dateTime,
  listWords,
  markPaidBefore,
  postImage,
  postOnce,
  useAttemptKey,
  type Dues,
  type ForOthers,
  type PayScreen,
  type Payment,
  type PersonDues,
} from "@/lib/payments";
import { PayDetails, SendDetails } from "@/components/PayDetails";
import { DueList } from "@/components/DueList";
import { PlayerPasses } from "@/components/PlayerPasses";
import { ScreenshotButton } from "@/components/ScreenshotButton";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// A screenshot is taken up to two hours after the payment is said.
const SCREENSHOT_MS = 120 * 60_000;

/// Somebody from your sessions you could pay for.
type Friend = { user_id: string; name: string };

export default function PayPage() {
  const t = useT();
  const authed = useRequireAuth();
  const { id: clubId } = useParams<{ id: string }>();
  const [pay, setPay] = useState<PayScreen | null>(null);
  /// Those you pay for, in this club.
  const [people, setPeople] = useState<PersonDues[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  /// Friends ticked under "I'm paying for friends too".
  const [friends, setFriends] = useState<Friend[]>([]);
  /// What the last payment for others said, until the page is left.
  const [paidFor, setPaidFor] = useState<ForOthers | null>(null);
  const [meId, setMeId] = useState<string | null>(null);
  const attempt = useAttemptKey();

  useEffect(() => setMeId(getStoredUser()?.id ?? null), []);

  const load = useCallback(async () => {
    if (!authed || !clubId) return;
    try {
      const [p, d] = await Promise.all([
        api<PayScreen>("GET", `/clubs/${clubId}/pay`),
        // Only a parent has anybody here; the pay screen works without it.
        api<Dues>("GET", "/me/dues").catch(() => null),
      ]);
      setPay(p);
      setPeople((d?.people ?? []).filter((x) => x.club_id === clubId));
      setLoadError(null);
    } catch (e) {
      setLoadError(readErr(e, t("le.something_went_wrong")));
    }
  }, [authed, clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  const owingPeople = useMemo(() => people.filter((p) => p.dues.owed_cents > 0), [people]);

  if (!authed) return <main id="main" />;
  if (!pay) {
    return (
      <main id="main">
        {loadError ? <p className="error" role="alert">{loadError}</p> : <div className="skeleton" style={{ height: 240 }} />}
      </main>
    );
  }

  const othersCents = owingPeople.reduce((sum, p) => sum + p.dues.owed_cents, 0);
  const total = pay.owed_cents + othersCents;
  const owes = total > 0;
  /// One payment for more than yourself.
  const forOthers = owingPeople.length > 0 || friends.length > 0;
  const account = pay.account_state === "active" ? pay.account : null;
  // A parent who owes nothing themselves is not shown the details (the API
  // keeps them for those who owe): the same words as "none".
  const accountState = pay.account_state === "nothing_owed" && othersCents > 0 ? "hidden" : pay.account_state;
  const who = checker(pay.account);
  // What it's for, in one line when it is one thing: "You owe £5 for Friday nets".
  const owing = pay.shares.filter((s) => s.state === "owed" || s.state === "part_paid");
  const forTitle = owingPeople.length === 0 && owing.length === 1 ? owing[0].title : null;
  const amount = money(total, pay.currency);
  const everyone = [
    ...(pay.owed_cents > 0 ? [t("pw3.you")] : []),
    ...owingPeople.map((p) => p.name),
    ...friends.map((f) => f.name),
  ];

  const claim = async (method: "transfer" | "cash") => {
    setBusy(method);
    setError(null);
    setNotice(null);
    try {
      if (forOthers) {
        // One payment for everyone, under your own reference. The key stays
        // the same for every press until one works, so a second tap on a bad
        // signal still makes one payment for each person.
        const body = {
          method,
          people: [...owingPeople.map((p) => p.user_id), ...friends.map((f) => f.user_id)],
          include_me: pay.owed_cents > 0,
        };
        const out = await postOnce<ForOthers>(
          `/clubs/${clubId}/payments/for-others`,
          body,
          attempt.key(JSON.stringify(body)),
        );
        attempt.done();
        setPaidFor(out);
        setFriends([]);
      } else {
        // Everything owed, in one go: the body names no amount.
        await postOnce<Payment>(`/clubs/${clubId}/payments`, { method }, attempt.key(`${method}:${pay.owed_cents}`));
        attempt.done();
      }
      if (method === "transfer" && account) markPaidBefore(account);
      await load();
      document.getElementById("pay-waiting")?.focus();
    } catch (e) {
      // `nothing_owed`: already said, perhaps on another device. The
      // server's sentence says which, and the page catches up.
      if (STALE_CODES.has(errCode(e) ?? "")) {
        attempt.done();
        await load();
      }
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(null);
    }
  };

  const undo = async (p: Payment) => {
    setBusy(p.id);
    setError(null);
    setNotice(null);
    try {
      await api("DELETE", `/payments/${p.id}`);
      setNotice(t("pay.claim_undone"));
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      await load();
      setBusy(null);
    }
  };

  const paidLabel = forOthers ? t("pw3.ive_paid_for_everyone") : t("pay.ive_paid");
  const cashLabel = forOthers ? t("pw3.paid_cash_for_everyone") : t("pay.i_paid_cash");
  const paidNames = paidFor
    ? listWords(
        paidFor.payments.map((p) => (p.user_id === meId ? t("pw3.you") : p.name)),
        t,
      )
    : "";

  return (
    <main id="main" className="page pay-page">
      <p className="muted">
        <Link href="/profile/payments">{t("pay.back_to_your_payments")}</Link>
      </p>
      <h1>{t("pay.pay_club", { club: pay.club_name })}</h1>

      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="panel pay-sum" aria-labelledby="pay-owe">
        <p className="pay-headline" id="pay-owe">
          {owes
            ? owingPeople.length > 0
              ? t("pw3.you_owe_everyone", { amount })
              : forTitle
                ? t("pw2.you_owe_for", { amount, title: forTitle })
                : t("pay.you_owe_amount", { amount })
            : pay.waiting_cents > 0
              ? t("pay.said_you_paid")
              : t("pay.all_paid_up")}
        </p>
        {owingPeople.length > 0 && (
          <ul className="pay-people-sum">
            {pay.owed_cents > 0 && (
              <li>
                <span>{t("nav.you")}</span> <strong className="num">{money(pay.owed_cents, pay.currency)}</strong>
              </li>
            )}
            {owingPeople.map((p) => (
              <li key={p.user_id}>
                <span>{p.name}</span> <strong className="num">{money(p.dues.owed_cents, p.dues.currency)}</strong>
              </li>
            ))}
          </ul>
        )}
        {owes && pay.waiting_cents > 0 && (
          <p className="muted">{t("pay.amount_waiting", { amount: money(pay.waiting_cents, pay.currency) })}</p>
        )}
        {pay.credit_cents > 0 && (
          <p className="muted">{t("pay.amount_credit", { amount: money(pay.credit_cents, pay.currency) })}</p>
        )}
      </section>

      {owes && account && (
        <section className="panel" aria-label={t("pay.how_to_pay")}>
          <PayDetails account={account} reference={pay.reference} amountCents={total} currency={pay.currency} />
          {pay.owed_cents > 0 && (
            <FriendsToo
              clubId={clubId}
              pay={pay}
              meId={meId}
              skip={people.map((p) => p.user_id)}
              ticked={friends}
              onTicked={setFriends}
            />
          )}
          {forOthers && (
            <p className="pay-for-who" role="status">
              {t("pw3.paying_for", { names: listWords(everyone, t) })}
            </p>
          )}
          <p className="pay-then">{forOthers ? t("pw3.then_tap_everyone") : t("pw2.then_tap")}</p>
          <div className="pay-buttons">
            <button
              className="btn primary xl"
              type="button"
              disabled={busy !== null}
              aria-describedby={error ? "pay-error" : undefined}
              onClick={() => void claim("transfer")}
            >
              {busy === "transfer" ? t("pay.sending") : paidLabel}
            </button>
            <button
              className="btn xl"
              type="button"
              disabled={busy !== null}
              aria-describedby={error ? "pay-error" : undefined}
              onClick={() => void claim("cash")}
            >
              {busy === "cash" ? t("pay.sending") : cashLabel}
            </button>
          </div>
          {error && <p className="field-error" id="pay-error" role="alert">{error}</p>}
          <SendDetails
            account={account}
            reference={pay.reference}
            amountCents={total}
            currency={pay.currency}
            title={forTitle ?? pay.club_name}
          />
        </section>
      )}

      {owes && !account && (
        <section className="panel" aria-labelledby="pay-how">
          <AccountProblem state={accountState} />
          {/* "Don't pay yet" means it: no button to say otherwise. */}
          {accountState !== "frozen" && (
            <div className="pay-buttons">
              <button className="btn primary xl" type="button" disabled={busy !== null} onClick={() => void claim("cash")}>
                {busy === "cash" ? t("pay.sending") : cashLabel}
              </button>
            </div>
          )}
          {error && <p className="field-error" role="alert">{error}</p>}
        </section>
      )}

      {!owes && error && <p className="error" role="alert">{error}</p>}

      {(pay.claims.length > 0 || paidFor) && (
        <section className="panel pay-waiting" aria-labelledby="pay-waiting">
          <h2 id="pay-waiting" tabIndex={-1}>
            {who ? t("pw2.thanks_waiting", { first: who }) : t("pw2.thanks_waiting_club")}
          </h2>
          {paidFor && (
            <p className="pay-for-who">
              {paidFor.payments[0]?.method === "cash"
                ? t("pw3.said_paid_cash_for", { amount: money(paidFor.total_cents, pay.currency), names: paidNames })
                : t("pw3.said_paid_for", { amount: money(paidFor.total_cents, pay.currency), names: paidNames })}
            </p>
          )}
          {pay.claims.length > 0 && (
            <ul className="pay-list">
              {pay.claims.map((c) => (
                <li key={c.id}>
                  <div>
                    <strong className="num">{money(c.amount_cents, c.currency)}</strong>{" "}
                    <span className="muted">
                      {c.method === "cash" ? t("pay.in_cash") : t("pay.by_transfer_ref", { reference: c.reference ?? "" })}
                      {" · "}
                      {dateTime(c.created_at)}
                    </span>
                    {c.method === "transfer" && Date.now() - new Date(c.created_at).getTime() < SCREENSHOT_MS && (
                      <ScreenshotButton
                        done={!!c.has_screenshot}
                        who={who}
                        upload={(image) => postImage(`/payments/${c.id}/screenshot`, image)}
                        onUploaded={load}
                      />
                    )}
                  </div>
                  <button
                    className="btn"
                    type="button"
                    disabled={busy !== null}
                    aria-label={t("pw2.undo_amount", { amount: money(c.amount_cents, c.currency) })}
                    onClick={() => void undo(c)}
                  >
                    {t("pay.undo")}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {(pay.shares.length > 0 || people.some((p) => p.dues.shares.length > 0)) && (
        <section className="panel" aria-labelledby="pay-for">
          <h2 id="pay-for">{t("pay.what_its_for")}</h2>
          {people.length > 0 && pay.shares.length > 0 && <h3 className="pay-person-name">{t("nav.you")}</h3>}
          <DueList shares={pay.shares} />
          {people.map((p) => {
            const lines = p.dues.shares.filter((s) => s.state !== "paid");
            if (lines.length === 0) return null;
            return (
              <div className="pay-person" key={p.user_id}>
                <h3 className="pay-person-name">
                  {p.name}
                  {p.dues.owed_cents > 0 && (
                    <span className="num muted"> · {money(p.dues.owed_cents, p.dues.currency)}</span>
                  )}
                </h3>
                <DueList shares={lines} label={p.name} />
              </div>
            );
          })}
        </section>
      )}

      <PlayerPasses
        clubId={clubId}
        meId={meId}
        account={account}
        people={people.map((p) => ({ user_id: p.user_id, name: p.name }))}
        refreshKey={`${pay.owed_cents}:${pay.waiting_cents}`}
        onChanged={load}
      />
    </main>
  );
}

/// "I'm paying for friends too": tick who else you're covering, from the
/// sessions you owe for. Their lines go into your one payment, each for what
/// they owe; the club still checks it arrived.
function FriendsToo({
  clubId,
  pay,
  meId,
  skip,
  ticked,
  onTicked,
}: {
  clubId: string;
  pay: PayScreen;
  meId: string | null;
  /// Already in the payment: those you pay for.
  skip: string[];
  ticked: Friend[];
  onTicked: (f: Friend[]) => void;
}) {
  const t = useT();
  const [open, setOpen] = useState(false);
  const [names, setNames] = useState<Friend[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const sessions = useMemo(
    () => [
      ...new Set(
        pay.shares
          .filter((s) => s.event_id && (s.state === "owed" || s.state === "part_paid"))
          .map((s) => s.event_id as string),
      ),
    ],
    [pay.shares],
  );

  useEffect(() => {
    if (!open || names) return;
    // Who was at the same sessions. The API checks each one is on a bill
    // with you before it takes the payment.
    type Attendee = { user_id: string; name: string; status: string; club_id?: string | null };
    Promise.all(sessions.slice(0, 6).map((e) => api<Attendee[]>("GET", `/events/${e}/attendees`).catch(() => [] as Attendee[])))
      .then((lists) => {
        const seen = new Map<string, Friend>();
        for (const a of lists.flat()) {
          if (a.user_id === meId || skip.includes(a.user_id) || a.status === "not_going") continue;
          if (a.club_id && a.club_id !== clubId) continue;
          seen.set(a.user_id, { user_id: a.user_id, name: a.name });
        }
        setNames([...seen.values()].sort((a, b) => a.name.localeCompare(b.name)));
      })
      .catch((e) => setError(readErr(e, t("le.something_went_wrong"))));
  }, [open, names, sessions, meId, skip, clubId, t]);

  if (sessions.length === 0) return null;
  const has = (id: string) => ticked.some((f) => f.user_id === id);
  const toggle = (f: Friend) => onTicked(has(f.user_id) ? ticked.filter((x) => x.user_id !== f.user_id) : [...ticked, f]);

  return (
    <details className="pay-guide pay-friends" open={open} onToggle={(e) => setOpen((e.target as HTMLDetailsElement).open)}>
      <summary>{t("pw3.paying_for_friends")}</summary>
      <div className="pay-friends-body">
        <p className="muted">{t("pw3.friends_help")}</p>
        {error && <p className="field-error" role="alert">{error}</p>}
        {!names && !error && <div className="skeleton" style={{ height: 88 }} />}
        {names && names.length === 0 && <p className="muted">{t("pw3.no_friends")}</p>}
        {names && names.length > 0 && (
          <fieldset className="who-list">
            <legend className="sr-only">{t("pw3.paying_for_friends")}</legend>
            {names.map((f) => (
              <label className="who-person" key={f.user_id}>
                <input type="checkbox" checked={has(f.user_id)} onChange={() => toggle(f)} />
                <span className="who-name">{f.name}</span>
              </label>
            ))}
          </fieldset>
        )}
      </div>
    </details>
  );
}

/// Why there are no bank details to copy, in the same words as the pay link.
function AccountProblem({ state }: { state: string }) {
  const t = useT();
  const [title, body]: [Key, Key] =
    state === "frozen"
      ? ["pw2.frozen_title", "pw2.frozen_body"]
      : state === "unreadable"
        ? ["pw2.unreadable_title", "pw2.unreadable_body"]
        : state === "hidden"
          ? ["pw3.details_hidden_title", "pw3.details_hidden_body"]
          : ["pw2.none_title", "pw2.none_body"];
  return (
    <div className={`paylink-state small is-${state}`} role="note">
      <h2 id="pay-how">{t(title)}</h2>
      <p>{t(body)}</p>
    </div>
  );
}
