"use client";

import { use, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, money, readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";
import {
  PaymentReturn,
  payAtStripe,
  useCardPayments,
  useReturnedFromStripe,
} from "@/components/PayDialog";
import {
  AGE_LABEL,
  BALL_LABEL,
  GENDER_LABEL,
  GROUND_LABEL,
  type MatchConditions,
} from "@/lib/tournament";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

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
  const t = useT();
  const { entrantId } = use(params);
  const authed = useRequireAuth();
  const [view, setView] = useState<View | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const cards = useCardPayments();

  // Back from Stripe's page, where the redirect usually beats our webhook.
  const back = useReturnedFromStripe({
    settled: async () =>
      (await api<View>("GET", `/entrants/${entrantId}/invitation`)).confirmed,
    onSettled: () => load(),
  });

  const load = useCallback(async () => {
    try {
      setView(await api<View>("GET", `/entrants/${entrantId}/invitation`));
      setError(null);
    } catch (err) {
      setError(readErr(err, t("le.could_not_open_that_invitation")));
    } finally {
      setLoading(false);
    }
  }, [entrantId, t]);

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
      setError(readErr(err, t("le.could_not_send_that_answer")));
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
          <span className="tag">{t("tn.entering_as", { name: i.entrant_name })}</span>
          {dates && <span className="tag grey">{dates}</span>}
          {view.confirmed && <span className="tag">{t("tn.youre_in")}</span>}
          {view.owes_entry_fee && i.status === "accepted" && (
            <span className="tag gold">{t("tn.entry_fee_outstanding")}</span>
          )}
          {declined && <span className="tag grey">{t("tn.declined")}</span>}
        </div>
        {i.description && <p>{i.description}</p>}
      </section>

      {error && <p className="error">{error}</p>}
      <PaymentReturn waiting={back.waiting} gaveUp={back.gaveUp} />

      <div className="pro-cols">
        <div className="pro-main">
          {/* What you are agreeing to, before you agree to it. */}
          <div className="panel">
            <h2>{view.confirmed ? t("le.what_you_have_entered") : t("le.what_you_would_be_entering")}</h2>
            <dl className="pro-about">
              <div><dt>{t("tn.players_a_side")}</dt><dd className="num">{i.players_per_side}</dd></div>
              <div>
                <dt>{t("tn.guest_players")}</dt>
                <dd>
                  {i.guest_players_allowed === 0
                    ? t("tn.none_every_player_a_member")
                    : t("tn.up_to_n_from_outside", { n: i.guest_players_allowed })}
                </dd>
              </div>
              {i.age_group !== "open" && (
                <div><dt>{t("tn.age_group")}</dt><dd>{t(AGE_LABEL[i.age_group])}</dd></div>
              )}
              {i.gender !== "open" && (
                <div><dt>{t("tn.who_it_is_for")}</dt><dd>{t(GENDER_LABEL[i.gender])}</dd></div>
              )}
              {i.venue_name && <div><dt>{t("tn.ground")}</dt><dd>{i.venue_name}</dd></div>}
              {i.conditions && (
                <>
                  <div><dt>{t("tn.overs")}</dt><dd className="num">{i.conditions.overs_limit}</dd></div>
                  <div>
                    <dt>{t("tn.most_per_bowler")}</dt>
                    <dd className="num">
                      {i.conditions.overs_per_bowler === 0 ? "No limit" : i.conditions.overs_per_bowler}
                    </dd>
                  </div>
                  <div><dt>{t("tn.ball")}</dt><dd>{t(BALL_LABEL[i.conditions.ball])}</dd></div>
                  <div>
                    <dt>{t("tn.ground_type")}</dt>
                    <dd>{t(GROUND_LABEL[i.conditions.ground])}</dd>
                  </div>
                </>
              )}
            </dl>
            {i.rules_notes && (
              <>
                <h3 style={{ marginTop: "var(--s4)" }}>{t("tn.anything_else")}</h3>
                <p style={{ whiteSpace: "pre-wrap" }}>{i.rules_notes}</p>
              </>
            )}
          </div>

          {/* Step one: answer. */}
          {!answered && (
            <div className="panel">
              <h2>{t("tn.are_you_entering")}</h2>
              <p className="muted">
                {fee > 0
                  ? t("tn.cannot_make_draw_with_fee", { host: i.host_club_name, fee: money(fee) })
                  : t("tn.cannot_make_draw", { host: i.host_club_name })}
              </p>
              {!view.can_answer && (
                <p className="notice">
                  {t("tn.your_club_secretary_or_captain_answers")}
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
                    {busy === "accepted" ? t("tn.sending") : t("tn.yes_side_will_enter", { name: i.entrant_name })}
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
                <h2>{t("tn.entry_fee")}</h2>
                <span className="tag gold">{money(fee)}</span>
              </div>
              <p className="muted">
                {t("tn.you_have_accepted_but")} <strong>{i.entrant_name} is not in the draw
                until the entry fee is settled</strong> — {i.host_club_name} builds
                the fixtures from the sides that have paid.
              </p>
              {view.can_answer && cards && (
                <div className="field-row" style={{ marginTop: "var(--s4)" }}>
                  <button
                    className="btn primary lg"
                    type="button"
                    disabled={paying}
                    onClick={async () => {
                      setPaying(true);
                      const problem = await payAtStripe(`/entrants/${entrantId}/pay-entry`, t);
                      if (problem) {
                        setError(problem);
                        setPaying(false);
                      }
                    }}
                  >
                    {paying ? t("le.taking_you_to_stripe") : t("tn.pay_by_card", { amount: money(fee) })}
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
              <h2>{t("tn.youre_in")}</h2>
              <p>
                {t("tn.side_is_entered_in", { name: i.entrant_name, block: i.block_name })}
                {i.entry_paid_at
                  ? t("tn.entry_fee_is_settled", {
                      method: i.entry_payment_method
                        ? t("tn.payment_method_paren", { method: i.entry_payment_method })
                        : "",
                    })
                  : t("fin.nothing_to_pay")}{" "}
                {t("tn.will_send_fixtures_once_draw", { host: i.host_club_name })}
              </p>
            </div>
          )}

          {declined && (
            <div className="panel">
              <h2>{t("tn.you_said_no")}</h2>
              <p className="muted">
                {i.host_club_name} has been told, which is what lets them find
                somebody else. If that was a mistake, ask them to invite you again.
              </p>
            </div>
          )}

          {withdrawn && (
            <div className="panel">
              <h2>{t("tn.withdrawn")}</h2>
              <p className="muted">{i.entrant_name} has pulled out of this one.</p>
            </div>
          )}
        </div>

        <aside className="pro-rail">
          <div className="panel">
            <h2>{t("tn.the_tournament")}</h2>
            <dl className="pro-figures">
              <div><dt>{t("tn.run_by")}</dt><dd>{i.host_club_name}</dd></div>
              {dates && <div><dt>{t("tn.when")}</dt><dd>{dates}</dd></div>}
              {i.max_entrants != null && (
                <div><dt>{t("tn.sides")}</dt><dd className="num">{i.max_entrants}</dd></div>
              )}
              <div>
                <dt>{t("tn.to_enter")}</dt>
                <dd className="num">{fee > 0 ? money(fee) : t("le.free")}</dd>
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
              <Icon name="arrowLeft" size={12} /> {t("tn.all_tournaments")}
            </Link>
          </p>
        </aside>
      </div>

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
