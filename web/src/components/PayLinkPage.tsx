"use client";

/// The pay link from the club's WhatsApp group: `/p/<token>`.
///
/// Whoever opens it may never have signed in, may not have the app, and may
/// not use banking apps much (plan §5.1, §5.2). So: no sign-in, no app
/// navigation, very large text and buttons, one thing at a time —
///
///   your name → what you owe and where to send it → "I've paid" →
///   "Thanks — waiting for Aman to check", with Undo and Add a screenshot.
///
/// A signed-in phone sends its session along and opens straight on the
/// person's own name. What anybody can do here is deliberately small: say
/// they have paid. The treasurer still checks the bank before it counts.
///
/// The account number is shown and copied, never logged and never put in a
/// URL.

import { useCallback, useEffect, useRef, useState, type RefObject } from "react";
import { errCode, money, readErr } from "@/lib/api";
import {
  checker,
  linkApi,
  markPaidBefore,
  postImage,
  shortDate,
  useAttemptKey,
  type LinkPage,
  type LinkPerson,
} from "@/lib/payments";
import { firstName } from "@/lib/pay-link";
import { PayDetails, SendDetails } from "@/components/PayDetails";
import { ScreenshotButton } from "@/components/ScreenshotButton";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// A screenshot is taken up to two hours after the payment is said.
const SCREENSHOT_MS = 120 * 60_000;

/// Why the whole page cannot open: each has its own page, in plain words.
type Fatal = "bad_link" | "link_closed" | "slow_down" | "failed";

const FATAL: Record<Fatal, { title: Key; body: Key; icon: "link" | "clock" }> = {
  bad_link: { title: "pw2.bad_link_title", body: "pw2.bad_link_body", icon: "link" },
  link_closed: { title: "pw2.link_closed_title", body: "pw2.link_closed_body", icon: "clock" },
  slow_down: { title: "pw2.slow_down_title", body: "pw2.slow_down_body", icon: "clock" },
  failed: { title: "pw2.link_failed_title", body: "pw2.link_failed_body", icon: "link" },
};

function fatalOf(e: unknown): Fatal | null {
  const code = errCode(e);
  if (code === "bad_link" || code === "link_closed" || code === "slow_down") return code;
  // One name gone from the bill (a re-split): back to the names, not the end.
  if (code === "not_on_bill") return null;
  const status = (e as { status?: number }).status;
  if (status === 404) return "bad_link";
  if (status === 410) return "link_closed";
  if (status === 429) return "slow_down";
  return null;
}

export function PayLinkPage({ token }: { token: string }) {
  const t = useT();
  const base = `/pay-links/${encodeURIComponent(token)}`;
  const [page, setPage] = useState<LinkPage | null>(null);
  const [fatal, setFatal] = useState<Fatal | null>(null);
  /// The person whose line is open, by their id on the bill.
  const [chosen, setChosen] = useState<string | null>(null);
  const [person, setPerson] = useState<LinkPerson | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const attempt = useAttemptKey();
  /// Each view's heading takes focus when it arrives, so a screen reader
  /// hears that the page moved on.
  const heading = useRef<HTMLHeadingElement>(null);

  const openPage = useCallback(async () => {
    setFatal(null);
    try {
      const p = await linkApi<LinkPage>("GET", base);
      setPage(p);
      if (p.me) setChosen((c) => c ?? p.me);
    } catch (e) {
      setFatal(fatalOf(e) ?? "failed");
    }
  }, [base]);

  useEffect(() => {
    void openPage();
  }, [openPage]);

  useEffect(() => {
    if (page) document.title = t("pay.pay_club", { club: page.club_name });
  }, [page, t]);

  const loadPerson = useCallback(
    async (id: string) => {
      try {
        setPerson(await linkApi<LinkPerson>("GET", `${base}/people/${id}`));
      } catch (e) {
        const f = fatalOf(e);
        if (f && errCode(e)) {
          setFatal(f);
        } else {
          // "That name isn't on this bill any more": back to the names.
          setChosen(null);
          setPerson(null);
          setError(readErr(e, t("le.something_went_wrong")));
        }
      }
    },
    [base, t],
  );

  useEffect(() => {
    if (!chosen) {
      setPerson(null);
      return;
    }
    void loadPerson(chosen);
  }, [chosen, loadPerson]);

  // A new view: put focus on what it is about.
  const view = !page ? "loading" : !chosen ? "names" : !person ? "loading-person" : person.claim ? "waiting" : "person";
  useEffect(() => {
    if (view !== "loading" && view !== "loading-person") heading.current?.focus();
  }, [view]);

  if (fatal) {
    const f = FATAL[fatal];
    return (
      <main id="main" className="paylink">
        <div className="paylink-state" role="alert">
          <span className="paylink-state-icon" aria-hidden="true">
            <Icon name={f.icon} size={32} />
          </span>
          <h1>{t(f.title)}</h1>
          <p>{t(f.body)}</p>
          {(fatal === "slow_down" || fatal === "failed") && (
            <button
              className="btn primary xl"
              type="button"
              onClick={() => {
                // From the top: the name they had open, if any, loads again
                // once the page does (their own, when signed in).
                setChosen(null);
                setPerson(null);
                void openPage();
              }}
            >
              {t("pw2.try_again")}
            </button>
          )}
        </div>
      </main>
    );
  }

  if (!page) {
    return (
      <main id="main" className="paylink" aria-busy="true">
        <p className="paylink-loading">{t("pw2.link_opening")}</p>
        <div className="skeleton" style={{ height: 220 }} />
      </main>
    );
  }

  const when = shortDate(page.event_start_at);
  const account = page.account_state === "active" ? page.account : null;
  const who = checker(account);

  const pick = (id: string | null) => {
    setError(null);
    setNotice(null);
    attempt.done();
    setPerson(null);
    setChosen(id);
  };

  const claim = async (method: "transfer" | "cash") => {
    if (!person) return;
    setBusy(method);
    setError(null);
    setNotice(null);
    try {
      // One key for every press of this button for this person until one
      // works: a double tap or a retry on a bad signal makes one payment.
      const next = await linkApi<LinkPerson>("POST", `${base}/people/${person.id}/claim`, { method }, {
        "Idempotency-Key": attempt.key(`${person.id}:${method}`),
      });
      attempt.done();
      if (method === "transfer" && account) markPaidBefore(account);
      setPerson(next);
    } catch (e) {
      const f = fatalOf(e);
      if (f && f !== "slow_down" && errCode(e)) {
        setFatal(f);
        return;
      }
      // `nothing_owed`: paid, let off, or said already — the server says which.
      if (errCode(e) === "nothing_owed") {
        attempt.done();
        await loadPerson(person.id);
      }
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(null);
    }
  };

  const undo = async () => {
    if (!person?.claim) return;
    setBusy("undo");
    setError(null);
    setNotice(null);
    try {
      await linkApi<void>("DELETE", `${base}/claims/${person.claim.id}`);
      setNotice(t("pay.claim_undone"));
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      await loadPerson(person.id);
      setBusy(null);
    }
  };

  return (
    <main id="main" className="paylink">
      <header className="paylink-head">
        <h1 className="paylink-club">{page.club_name}</h1>
        <p className="paylink-event">{t("pw2.event_on", { title: page.title, date: when })}</p>
      </header>

      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}

      {view === "names" && (
        <>
          {page.account_state === "frozen" ? (
            <AccountState state="frozen" />
          ) : (
            page.account_state !== "active" && <AccountState state={page.account_state} />
          )}
          {page.account_state !== "frozen" && (
            <section aria-labelledby="paylink-names">
              <h2 id="paylink-names" ref={heading} tabIndex={-1} className="paylink-h">
                {page.account_state === "active" ? t("pw2.tap_your_name") : t("pw2.paid_cash_tap_name")}
              </h2>
              <p className="paylink-sub">{t("pw2.tap_your_name_help", { title: page.title })}</p>
              {error && (
                <p className="error" role="alert">
                  {error}
                </p>
              )}
              <ul className="paylink-names" aria-labelledby="paylink-names">
                {page.people.map((p) => (
                  <li key={p.id}>
                    <button className="paylink-name" type="button" onClick={() => pick(p.id)}>
                      <span>{p.name}</span>
                      <span aria-hidden="true">›</span>
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </>
      )}

      {(view === "loading-person" || view === "person" || view === "waiting") && (
        <p className="paylink-who">
          <span>{chosen === page.me ? t("pw2.paying_as", { name: person?.name ?? "" }) : person?.name}</span>{" "}
          <button className="btn ghost" type="button" onClick={() => pick(null)}>
            {person ? t("pw2.not_name", { first: firstName(person.name) }) : t("pw2.pick_your_name")}
          </button>
        </p>
      )}

      {view === "loading-person" && <div className="skeleton" style={{ height: 260 }} />}

      {view === "person" && person && (
        <section aria-labelledby="paylink-owe">
          {person.owed_cents > 0 ? (
            <>
              <h2 id="paylink-owe" ref={heading} tabIndex={-1} className="pay-headline">
                {t("pw2.you_owe_for", { amount: money(person.owed_cents, person.currency), title: page.title })}
              </h2>
              {person.paid_cents > 0 && (
                <p className="paylink-sub">
                  {t("pay.paid_of", {
                    paid: money(person.paid_cents, person.currency),
                    amount: money(person.amount_cents, person.currency),
                  })}
                </p>
              )}

              {account ? (
                <>
                  <PayDetails
                    account={account}
                    reference={person.reference}
                    amountCents={person.owed_cents}
                    currency={person.currency}
                  />
                  <p className="pay-then">{t("pw2.then_tap")}</p>
                  <div className="pay-buttons">
                    <button
                      className="btn primary xl"
                      type="button"
                      disabled={busy !== null}
                      aria-describedby={error ? "paylink-error" : undefined}
                      onClick={() => void claim("transfer")}
                    >
                      {busy === "transfer" ? t("pay.sending") : t("pay.ive_paid")}
                    </button>
                    <button
                      className="btn xl"
                      type="button"
                      disabled={busy !== null}
                      aria-describedby={error ? "paylink-error" : undefined}
                      onClick={() => void claim("cash")}
                    >
                      {busy === "cash" ? t("pay.sending") : t("pay.i_paid_cash")}
                    </button>
                  </div>
                  {error && (
                    <p className="field-error" id="paylink-error" role="alert">
                      {error}
                    </p>
                  )}
                  <SendDetails
                    account={account}
                    reference={person.reference}
                    amountCents={person.owed_cents}
                    currency={person.currency}
                    title={page.title}
                  />
                </>
              ) : (
                <>
                  <AccountState state={page.account_state} small />
                  {page.account_state !== "frozen" && (
                    <div className="pay-buttons">
                      <button className="btn primary xl" type="button" disabled={busy !== null} onClick={() => void claim("cash")}>
                        {busy === "cash" ? t("pay.sending") : t("pay.i_paid_cash")}
                      </button>
                    </div>
                  )}
                  {error && (
                    <p className="field-error" role="alert">
                      {error}
                    </p>
                  )}
                </>
              )}
            </>
          ) : (
            <Settled person={person} heading={heading} />
          )}
        </section>
      )}

      {view === "waiting" && person?.claim && (
        <section aria-labelledby="paylink-waiting" className="paylink-waiting">
          <span className="paylink-state-icon ok" aria-hidden="true">
            <Icon name="check" size={32} />
          </span>
          <h2 id="paylink-waiting" ref={heading} tabIndex={-1} className="pay-headline">
            {who ? t("pw2.thanks_waiting", { first: who }) : t("pw2.thanks_waiting_club")}
          </h2>
          <p>
            {person.claim.method === "cash"
              ? t("pw2.said_cash", { amount: money(person.claim.amount_cents, person.currency) })
              : t("pw2.said_transfer", { amount: money(person.claim.amount_cents, person.currency) })}
          </p>
          <p className="muted">
            {person.claim.method === "cash"
              ? who
                ? t("pw2.waiting_cash_help", { first: who })
                : t("pw2.waiting_cash_help_club")
              : who
                ? t("pw2.waiting_transfer_help", { first: who })
                : t("pw2.waiting_transfer_help_club")}
          </p>

          {person.claim.method === "transfer" &&
            Date.now() - new Date(person.claim.created_at).getTime() < SCREENSHOT_MS && (
              <ScreenshotButton
                done={person.claim.has_screenshot}
                who={who}
                upload={(image) => postImage(`${base}/claims/${person.claim!.id}/screenshot`, image, true)}
                onUploaded={() => loadPerson(person.id)}
              />
            )}

          {person.claim.can_undo && (
            <div className="paylink-undo">
              <p className="subtle">{t("pw2.undo_help")}</p>
              <button className="btn" type="button" disabled={busy !== null} onClick={() => void undo()}>
                {busy === "undo" ? t("pay.sending") : t("pay.undo")}
              </button>
            </div>
          )}
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
        </section>
      )}

      <footer className="paylink-foot">
        <p className="subtle">{t("pw2.link_until", { date: shortDate(page.expires_at) })}</p>
      </footer>
    </main>
  );
}

/// Nothing left to pay on this line, and nothing waiting from this link.
function Settled({ person, heading }: { person: LinkPerson; heading: RefObject<HTMLHeadingElement | null> }) {
  const t = useT();
  const [title, body]: [Key, Key | null] =
    person.state === "paid"
      ? ["pw2.all_paid", null]
      : person.state === "waived"
        ? ["pay.you_were_let_off", "pw2.nothing_to_pay"]
        : person.state === "covered"
          ? ["pw2.state_covered", "pw2.nothing_to_pay"]
          : person.state === "waiting" || person.waiting_cents > 0
            ? ["pay.said_you_paid", null]
            : ["pw2.nothing_to_pay", null];
  return (
    <div className="paylink-waiting">
      <span className="paylink-state-icon ok" aria-hidden="true">
        <Icon name="check" size={32} />
      </span>
      <h2 ref={heading} tabIndex={-1} className="pay-headline">
        {t(title)}
      </h2>
      {body && <p>{t(body)}</p>}
    </div>
  );
}

/// Why there are no bank details to show: the club's details are being
/// checked (don't pay yet), there are none (pay the secretary directly), or
/// they need entering again.
function AccountState({ state, small = false }: { state: string; small?: boolean }) {
  const t = useT();
  const [title, body]: [Key, Key] =
    state === "frozen"
      ? ["pw2.frozen_title", "pw2.frozen_body"]
      : state === "unreadable"
        ? ["pw2.unreadable_title", "pw2.unreadable_body"]
        : ["pw2.none_title", "pw2.none_body"];
  const Heading = small ? "h3" : "h2";
  return (
    <div className={`paylink-state is-${state}${small ? " small" : ""}`} role="note">
      {!small && (
        <span className="paylink-state-icon" aria-hidden="true">
          <Icon name={state === "frozen" ? "shield" : "help"} size={32} />
        </span>
      )}
      <Heading>{t(title)}</Heading>
      <p>{t(body)}</p>
    </div>
  );
}
