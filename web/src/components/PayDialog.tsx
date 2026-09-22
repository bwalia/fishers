"use client";

import { useEffect, useState } from "react";
import { api, apiV1, readErr } from "@/lib/api";

/// Sending somebody to Stripe to pay, and noticing when they come back.
///
/// The checkout page is Stripe's own, at checkout.stripe.com — their card
/// fields, their wallets, their 3-D Secure step, their receipt, their
/// translations. Card details never reach a Fishers origin, so there is no
/// embedded form to maintain and far less of our surface in PCI scope.
///
/// The cost is a round trip out of the app and back. That is why `paid=1` on
/// the return URL matters: the page has to know it is coming back from a
/// payment and wait for the webhook, rather than showing the booking still
/// unpaid and inviting a second one.

type Config = { cards: boolean; publishable_key: string | null };

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

/// Open the checkout and send them there. Resolves only if it fails — on
/// success the browser has already left.
///
/// The origin goes with the request because Stripe has to return them *here*,
/// not to whatever base URL the server was configured with. `localStorage` is
/// per origin: somebody signed in at localhost who is returned to the LAN
/// address arrives with no session, sees a login page, and cannot tell whether
/// they paid. The server checks the origin against the ones it serves before
/// trusting it.
export async function payAtStripe(openPath: string): Promise<string> {
  const out = await api<{ checkout_url: string | null }>("POST", openPath, {
    return_to: window.location.origin,
  });
  if (!out.checkout_url) {
    return "Card payments are not switched on for this server.";
  }
  window.location.assign(out.checkout_url);
  // The assignment is not instant; the caller keeps its spinner until the
  // page actually goes.
  await new Promise((r) => setTimeout(r, 4000));
  return "";
}

/// Waiting for the webhook after Stripe sends them back.
///
/// Stripe redirects the moment the card clears, which is usually before our
/// webhook has landed. Showing "unpaid" in that gap is how somebody pays
/// twice, so the return is a state of its own.
export function useReturnedFromStripe({
  settled,
  onSettled,
}: {
  settled: () => Promise<boolean>;
  onSettled: () => void;
}): { waiting: boolean; gaveUp: boolean } {
  const [waiting, setWaiting] = useState(false);
  const [gaveUp, setGaveUp] = useState(false);

  useEffect(() => {
    const url = new URL(window.location.href);
    if (url.searchParams.get("paid") !== "1") return;
    // Taken out of the address bar so a refresh, or a shared link, does not
    // put the page back into waiting for a payment that already happened.
    url.searchParams.delete("paid");
    window.history.replaceState({}, "", url.toString());

    let alive = true;
    setWaiting(true);
    (async () => {
      for (let i = 0; i < 20 && alive; i++) {
        if (await settled().catch(() => false)) {
          if (!alive) return;
          setWaiting(false);
          onSettled();
          return;
        }
        await new Promise((r) => setTimeout(r, 1000));
      }
      if (!alive) return;
      setWaiting(false);
      // Not an error: the money is taken either way. Saying otherwise would
      // invite a second payment, which is the one outcome worth avoiding.
      setGaveUp(true);
      onSettled();
    })();
    return () => {
      alive = false;
    };
    // Runs once, on arrival back from Stripe.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { waiting, gaveUp };
}

/// The line to show while the webhook catches up.
export function PaymentReturn({ waiting, gaveUp }: { waiting: boolean; gaveUp: boolean }) {
  if (waiting) return <p className="notice">Paid — waiting for it to clear.</p>;
  if (gaveUp) {
    return (
      <p className="notice">
        Your payment went through. It can take a moment to show here — refresh
        in a minute rather than paying again.
      </p>
    );
  }
  return null;
}

export { readErr };
