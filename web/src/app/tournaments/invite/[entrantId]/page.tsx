"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, money, readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { PayDialog, useCardPayments } from "@/components/PayDialog";
import {
  AGE_LABEL,
  BALL_LABEL,
  GENDER_LABEL,
  GROUND_LABEL,
  type MatchConditions,
} from "@/lib/tournament";
import { useRequireAuth } from "@/lib/require-auth";

/// Answering an invitation into somebody else's tournament.
///
/// This is where the notification lands. It used to point at the club page,
/// which has nothing on it to answer with — so the invitation arrived and led
/// nowhere.
///
/// Three things happen here in order, because that is the order they happen
/// in real life: read what you are being asked to agree to, say yes or no,
/// and — if there is an entry fee — pay it. A side that has said yes and not
/// paid is not in the draw, and the screen says so rather than implying the
/// place is safe.

type Invitation = {
  entrant_id: string;
  entrant_name: string;
  status: string;
  club_id: string | null;
  entry_paid_at: string | null;
  entry_payment_method: string | null;
  block_id: string;
  block_name: string;
  kind: string;
  description: string | null;
  starts_on: string | null;
  ends_on: string | null;
  host_club_id: string;
  host_club_name: string;
  invited_by_name: string | null;
  entry_fee_cents: number | null;
  entry_deadline: string | null;
  max_entrants: number | null;
  players_per_side: number;
  guest_players_allowed: number;
  age_group: string;
  gender: string;
  conditions: MatchConditions | null;
  rules_notes: string | null;
  venue_name: string | null;
};

type View = {
  invitation: Invitation;
  can_answer: boolean;
  confirmed: boolean;
  owes_entry_fee: boolean;
};

export default function InvitePage({ params }: { params: Promise<{ entrantId: string }> }) {
  const { entrantId } = use(params);
  const authed = useRequireAuth();
  const [view, setView] = useState<View | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const cards = useCardPayments();

  const load = useCallback(async () => {
    try {
      setView(await api<View>("GET", `/entrants/${entrantId}/invitation`));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not open that invitation"));
    } finally {
      setLoading(false);
    }
  }, [entrantId]);

  useEffect(() => {
    if (!authed) return;
    load();
  }, [authed, load]);

  const answer = async (status: "accepted" | "declined") => {
    setBusy(status);
    setError(null);
    try {
      await api("POST", `/entrants/${entrantId}/respond`, { status });
      await load();
    } catch (err) {
      setError(readErr(err, "Could not send that answer"));
    } finally {
      setBusy(null);
    }
  };

  if (!authed) return <main id="main" />;
  if (loading) return <main id="main"><div className="skeleton" style={{ height: 320 }} /></main>;
  if (!view) return <main id="main"><p className="error">{error}</p></main>;

  const i = view.invitation;
  const fee = i.entry_fee_cents ?? 0;
  const dates = blockDates(i.starts_on, i.ends_on);
  const declined = i.status === "declined";
  const withdrawn = i.status === "withdrawn";
  const answered = i.status !== "invited";

  return (
    <main id="main">
      <section className="hero">
        <p className="club-eyebrow">
          {i.host_club_name} invited you{i.invited_by_name ? ` · ${i.invited_by_name}` : ""}
        </p>
        <h1>{i.block_name}</h1>
        <div className="hero-tags">
          <span className="tag">entering as {i.entrant_name}</span>
          {dates && <span className="tag grey">{dates}</span>}
          {view.confirmed && <span className="tag">You&apos;re in</span>}
          {view.owes_entry_fee && i.status === "accepted" && (
            <span className="tag gold">Entry fee outstanding</span>
          )}
          {declined && <span className="tag grey">Declined</span>}
        </div>
        {i.description && <p>{i.description}</p>}
      </section>

      {error && <p className="error">{error}</p>}

      <div className="pro-cols">
        <div className="pro-main">
          {/* What you are agreeing to, before you agree to it. */}
          <div className="panel">
            <h2>{view.confirmed ? "What you have entered" : "What you would be entering"}</h2>
            <dl className="pro-about">
              <div><dt>Players a side</dt><dd className="num">{i.players_per_side}</dd></div>
              <div>
                <dt>Guest players</dt>
                <dd>
                  {i.guest_players_allowed === 0
                    ? "None — every player must be a club member"
                    : `Up to ${i.guest_players_allowed} from outside the club`}
                </dd>
              </div>
              {i.age_group !== "open" && (
                <div><dt>Age group</dt><dd>{AGE_LABEL[i.age_group] ?? i.age_group}</dd></div>
              )}
              {i.gender !== "open" && (
                <div><dt>Who it is for</dt><dd>{GENDER_LABEL[i.gender] ?? i.gender}</dd></div>
              )}
              {i.venue_name && <div><dt>Ground</dt><dd>{i.venue_name}</dd></div>}
              {i.conditions && (
                <>
                  <div><dt>Overs</dt><dd className="num">{i.conditions.overs_limit}</dd></div>
                  <div>
                    <dt>Most per bowler</dt>
                    <dd className="num">
                      {i.conditions.overs_per_bowler === 0 ? "No limit" : i.conditions.overs_per_bowler}
                    </dd>
                  </div>
                  <div><dt>Ball</dt><dd>{BALL_LABEL[i.conditions.ball] ?? i.conditions.ball}</dd></div>
                  <div>
                    <dt>Ground type</dt>
                    <dd>{GROUND_LABEL[i.conditions.ground] ?? i.conditions.ground}</dd>
                  </div>
                </>
              )}
            </dl>
            {i.rules_notes && (
              <>
                <h3 style={{ marginTop: "var(--s4)" }}>Anything else</h3>
                <p style={{ whiteSpace: "pre-wrap" }}>{i.rules_notes}</p>
              </>
            )}
          </div>

          {/* Step one: answer. */}
          {!answered && (
            <div className="panel">
              <h2>Are you entering?</h2>
              <p className="muted">
                {fee > 0
                  ? `${i.host_club_name} cannot make the draw until every side has said. There is an entry fee of ${money(fee)} — you pay it after you accept, and your place is confirmed once it clears.`
                  : `${i.host_club_name} cannot make the draw until every side has said.`}
              </p>
              {!view.can_answer && (
                <p className="notice">
                  Your club secretary or captain answers this one. They have the
                  same invitation.
                </p>
              )}
              {view.can_answer && (
                <div className="field-row" style={{ marginTop: "var(--s4)" }}>
                  <button
                    className="btn primary lg"
                    type="button"
                    disabled={busy !== null}
                    onClick={() => answer("accepted")}
                  >
                    {busy === "accepted" ? "Sending…" : `Yes — ${i.entrant_name} will enter`}
                  </button>
                  <button
                    className="btn"
                    type="button"
                    disabled={busy !== null}
                    onClick={() => answer("declined")}
                  >
                    No, we can&apos;t make it
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Step two: pay, when there is something to pay. */}
          {view.owes_entry_fee && i.status === "accepted" && (
            <div className="panel">
              <div className="panel-head">
                <h2>Entry fee</h2>
                <span className="tag gold">{money(fee)}</span>
              </div>
              <p className="muted">
                You have accepted, but <strong>{i.entrant_name} is not in the draw
                until the entry fee is settled</strong> — {i.host_club_name} builds
                the fixtures from the sides that have paid.
              </p>
              {view.can_answer && cards && (
                <div className="field-row" style={{ marginTop: "var(--s4)" }}>
                  <button
                    className="btn primary lg"
                    type="button"
                    onClick={() => setPaying(true)}
                  >
                    Pay {money(fee)} by card
                  </button>
                </div>
              )}
              {cards === false && (
                <p className="subtle">
                  Card payments are not switched on here — pay {i.host_club_name}{" "}
                  directly and they will record it.
                </p>
              )}
            </div>
          )}

          {view.confirmed && (
            <div className="panel">
              <h2>You&apos;re in</h2>
              <p>
                {i.entrant_name} is entered in {i.block_name}.
                {i.entry_paid_at
                  ? ` The entry fee is settled${i.entry_payment_method ? ` (${i.entry_payment_method})` : ""}.`
                  : " There is nothing to pay."}{" "}
                {i.host_club_name} will send the fixtures once the draw is made.
              </p>
            </div>
          )}

          {declined && (
            <div className="panel">
              <h2>You said no</h2>
              <p className="muted">
                {i.host_club_name} has been told, which is what lets them find
                somebody else. If that was a mistake, ask them to invite you again.
              </p>
            </div>
          )}

          {withdrawn && (
            <div className="panel">
              <h2>Withdrawn</h2>
              <p className="muted">{i.entrant_name} has pulled out of this one.</p>
            </div>
          )}
        </div>

        <aside className="pro-rail">
          <div className="panel">
            <h2>The tournament</h2>
            <dl className="pro-figures">
              <div><dt>Run by</dt><dd>{i.host_club_name}</dd></div>
              {dates && <div><dt>When</dt><dd>{dates}</dd></div>}
              {i.max_entrants != null && (
                <div><dt>Sides</dt><dd className="num">{i.max_entrants}</dd></div>
              )}
              <div>
                <dt>To enter</dt>
                <dd className="num">{fee > 0 ? money(fee) : "Free"}</dd>
              </div>
            </dl>
            {i.entry_deadline && (
              <p className="subtle">
                Entries close{" "}
                {new Date(i.entry_deadline).toLocaleString("en-GB", {
                  weekday: "short", day: "numeric", month: "short",
                  hour: "2-digit", minute: "2-digit",
                })}
                .
              </p>
            )}
          </div>
          <p className="muted">
            <Link href="/tournaments">
              <Icon name="arrowLeft" size={12} /> All tournaments
            </Link>
          </p>
        </aside>
      </div>

      {paying && (
        <PayDialog
          title={`${i.block_name} — entry fee`}
          amountCents={fee}
          open={() => api<{ client_secret: string }>("POST", `/entrants/${entrantId}/pay-entry`, {})}
          // The webhook settles the entry, so the entry is what gets asked.
          settled={async () =>
            (await api<View>("GET", `/entrants/${entrantId}/invitation`)).confirmed
          }
          onDone={() => {
            setPaying(false);
            load();
          }}
          onClose={() => setPaying(false)}
        />
      )}
    </main>
  );
}

function blockDates(from: string | null, to: string | null): string {
  const fmt = (d: string) =>
    new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  if (from && to && to !== from) return `${fmt(from)} – ${fmt(to)}`;
  if (from) return fmt(from);
  return "";
}
