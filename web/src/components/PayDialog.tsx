"use client";

import { useCallback, useEffect, useState } from "react";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import { loadStripe, type Stripe } from "@stripe/stripe-js";
import { api, apiV1, money, readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Paying by card.
///
/// The API has been handing out a Stripe client secret for a long time and
/// nothing on this side ever used it: the button said "payment opened" and
/// threw the secret away, so no card was ever charged. This is the form it was
/// always meant to be given to.
///
/// The card details never touch Fishers — they go from the browser straight to
/// Stripe, and we are told the answer by webhook. That is why the dialog waits
/// for the *server* to agree the money arrived rather than trusting what
/// `confirmPayment` hands back.

type Config = { cards: boolean; publishable_key: string | null };

/// One `loadStripe` per key, because it injects a script tag.
let stripeFor: { key: string; promise: Promise<Stripe | null> } | null = null;
function stripePromise(key: string) {
  if (stripeFor?.key !== key) stripeFor = { key, promise: loadStripe(key) };
  return stripeFor.promise;
}

/// Whether this deployment can take a card at all, so a button that cannot
/// work is never drawn. `null` while we are still asking.
export function useCardPayments(): boolean | null {
  const [cards, setCards] = useState<boolean | null>(null);
  useEffect(() => {
    let alive = true;
    fetch(`${apiV1()}/payments/config`)
      .then((r) => (r.ok ? r.json() : { cards: false }))
      .then((c: Config) => alive && setCards(!!c.cards))
      .catch(() => alive && setCards(false));
    return () => {
      alive = false;
    };
  }, []);
  return cards;
}

export function PayDialog({
  title,
  amountCents,
  currency = "GBP",
  /// Opens the payment on the server and hands back its client secret.
  open,
  /// True once the server agrees the money arrived. Polled, because the
  /// webhook is what settles it and it does not arrive on our schedule.
  settled,
  onDone,
  onClose,
}: {
  title: string;
  amountCents: number;
  currency?: string;
  open: () => Promise<{ client_secret: string }>;
  settled: () => Promise<boolean>;
  onDone: () => void;
  onClose: () => void;
}) {
  const [config, setConfig] = useState<Config | null>(null);
  const [secret, setSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const c: Config = await (await fetch(`${apiV1()}/payments/config`)).json();
        if (!alive) return;
        setConfig(c);
        if (!c.cards || !c.publishable_key) {
          setError("Card payments are not switched on for this server.");
          return;
        }
        const started = await open();
        if (alive) setSecret(started.client_secret);
      } catch (err) {
        if (alive) setError(readErr(err, "Could not start that payment"));
      }
    })();
    return () => {
      alive = false;
    };
    // Opening runs once per dialog: a second intent would be a second payment.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const key = config?.publishable_key;

  return (
    <div className="pay-backdrop" role="dialog" aria-modal="true" aria-label={`Pay for ${title}`}>
      <div className="pay-sheet">
        <div className="panel-head">
          <h2>{title}</h2>
          <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
        </div>
        <p className="pay-amount">{money(amountCents, currency)}</p>

        {error && <p className="error">{error}</p>}

        {!error && (!secret || !key) && <div className="skeleton" style={{ height: 180 }} />}

        {!error && secret && key && (
          <Elements
            stripe={stripePromise(key)}
            options={{ clientSecret: secret, appearance: { theme: "flat" } }}
          >
            <CardForm settled={settled} onDone={onDone} />
          </Elements>
        )}

        <p className="subtle pay-note">
          <Icon name="lock" size={12} /> Your card details go straight to Stripe.
          Fishers never sees them.
        </p>
      </div>
    </div>
  );
}

function CardForm({
  settled,
  onDone,
}: {
  settled: () => Promise<boolean>;
  onDone: () => void;
}) {
  const stripe = useStripe();
  const elements = useElements();
  const [busy, setBusy] = useState(false);
  const [waiting, setWaiting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /// Stripe says the card went through; the ticket is not paid until our own
  /// webhook has said so. Ten seconds is generous for a test card and honest
  /// about the alternative — it is already paid, the screen is just behind.
  const waitForSettlement = useCallback(async () => {
    setWaiting(true);
    for (let i = 0; i < 10; i++) {
      if (await settled().catch(() => false)) {
        setWaiting(false);
        onDone();
        return;
      }
      await new Promise((r) => setTimeout(r, 1000));
    }
    setWaiting(false);
    // Not an error: the money is taken either way, and saying otherwise would
    // invite a second payment.
    onDone();
  }, [settled, onDone]);

  const pay = async () => {
    if (!stripe || !elements) return;
    setBusy(true);
    setError(null);
    const { error: err } = await stripe.confirmPayment({
      elements,
      redirect: "if_required",
    });
    setBusy(false);
    if (err) {
      setError(err.message ?? "That card was refused.");
      return;
    }
    await waitForSettlement();
  };

  return (
    <>
      <PaymentElement />
      {error && <p className="error">{error}</p>}
      {waiting && <p className="notice">Taken — waiting for it to clear.</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button
          className="btn primary lg"
          type="button"
          disabled={!stripe || busy || waiting}
          onClick={pay}
        >
          {busy ? "Paying…" : waiting ? "Clearing…" : "Pay now"}
        </button>
      </div>
    </>
  );
}

/// Convenience for the common shape: POST to open it, GET to see if it landed.
export function payVia(openPath: string, check: () => Promise<boolean>) {
  return {
    open: () => api<{ client_secret: string }>("POST", openPath, {}),
    settled: check,
  };
}
