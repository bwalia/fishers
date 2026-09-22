"use client";

import { use, useCallback, useEffect, useState } from "react";
import { apiV1, readErr } from "@/lib/api";

/// Answering a tournament invitation without a Fishers account.
///
/// Most opposition clubs are not on Fishers, and making a secretary sign up
/// before they can say "yes, we'll come" is how an entry list stays a
/// spreadsheet. The link is the credential, so this page never asks anyone to
/// sign in — and it is the only thing the link can do.
type Invitation = {
  tournament: string;
  host_club: string;
  side: string;
  status: string;
};

export default function EntryPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [invite, setInvite] = useState<Invitation | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Not the shared `api()` helper: that one attaches the signed-in user's
  // token and bounces to /login on a 401. There is nobody signed in here.
  const load = useCallback(async () => {
    try {
      const r = await fetch(`${apiV1()}/public/entry/${encodeURIComponent(token)}`);
      if (!r.ok) throw new Error(String(r.status));
      setInvite(await r.json());
      setError(null);
    } catch {
      setError("That invitation link is not valid, or it has already been answered.");
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    load();
  }, [load]);

  const answer = async (status: "accepted" | "declined") => {
    setBusy(status);
    setError(null);
    try {
      const r = await fetch(`${apiV1()}/public/entry/${encodeURIComponent(token)}/respond`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      if (!r.ok) throw new Error(await r.text());
      setAnswered(status);
    } catch (err) {
      setError(readErr(err, "Could not send that answer"));
    } finally {
      setBusy(null);
    }
  };

  if (loading)
    return (
      <main id="main">
        <div className="skeleton" style={{ height: 220 }} />
      </main>
    );

  if (answered) {
    return (
      <main id="main">
        <section className="hero">
          <h1>{answered === "accepted" ? "You're in" : "Thanks for letting them know"}</h1>
          <p>
            {answered === "accepted"
              ? `${invite?.host_club} has been told that ${invite?.side} is entering ${invite?.tournament}. They will send the fixtures once the draw is made.`
              : `${invite?.host_club} has been told ${invite?.side} can't make ${invite?.tournament}. Telling them now is what lets them find somebody else.`}
          </p>
        </section>
      </main>
    );
  }

  if (!invite)
    return (
      <main id="main">
        <p className="error">{error}</p>
      </main>
    );

  return (
    <main id="main">
      <section className="hero">
        <p className="club-eyebrow">{invite.host_club} has invited you</p>
        <h1>{invite.tournament}</h1>
        <div className="hero-tags">
          <span className="tag">entering as {invite.side}</span>
        </div>
      </section>

      {error && <p className="error">{error}</p>}

      <div className="panel">
        <h2>Are you coming?</h2>
        <p className="muted">
          Answering here tells {invite.host_club} straight away. They can only
          make the draw once every side has said.
        </p>
        <div className="field-row" style={{ marginTop: "var(--s4)" }}>
          <button
            className="btn primary lg"
            type="button"
            disabled={busy !== null}
            onClick={() => answer("accepted")}
          >
            {busy === "accepted" ? "Sending…" : `Yes — ${invite.side} will enter`}
          </button>
          <button
            className="btn"
            type="button"
            disabled={busy !== null}
            onClick={() => answer("declined")}
          >
            {busy === "declined" ? "Sending…" : "No, we can't make it"}
          </button>
        </div>
      </div>
    </main>
  );
}
