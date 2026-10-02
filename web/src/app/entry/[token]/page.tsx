"use client";

import { use, useCallback, useEffect, useState } from "react";
import { apiV1, readErr } from "@/lib/api";
import { useT } from "@/lib/i18n/provider";

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
  const t = useT();
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
      setError(t("le.that_invitation_link_is_not_valid_or_i"));
    } finally {
      setLoading(false);
    }
  }, [token, t]);

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
      setError(readErr(err, t("le.could_not_send_that_answer")));
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
          <h1>{answered === "accepted" ? t("le.you_re_in") : t("le.thanks_for_letting_them_know")}</h1>
          <p>
            {answered === "accepted"
              ? t("tn.told_entering", {
                  host: invite?.host_club ?? "",
                  side: invite?.side ?? "",
                  tournament: invite?.tournament ?? "",
                })
              : t("tn.told_cannot_make", {
                  host: invite?.host_club ?? "",
                  side: invite?.side ?? "",
                  tournament: invite?.tournament ?? "",
                })}
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
        <p className="club-eyebrow">{t("tn.host_has_invited_you", { host: invite.host_club })}</p>
        <h1>{invite.tournament}</h1>
        <div className="hero-tags">
          <span className="tag">{t("tn.entering_as", { name: invite.side })}</span>
        </div>
      </section>

      {error && <p className="error">{error}</p>}

      <div className="panel">
        <h2>{t("rest.are_you_coming")}</h2>
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
            {busy === "accepted" ? t("le.sending") : t("tn.yes_side_will_enter", { name: invite.side })}
          </button>
          <button
            className="btn"
            type="button"
            disabled={busy !== null}
            onClick={() => answer("declined")}
          >
            {busy === "declined" ? "Sending…" : t("le.no_we_can_t_make_it")}
          </button>
        </div>
      </div>
    </main>
  );
}
