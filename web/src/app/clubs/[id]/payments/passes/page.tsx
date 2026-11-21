"use client";

/// Passes, for whoever looks after the club's money (plan §3): make one from
/// a template and change the numbers; see who's on each and how they stand;
/// add somebody, take them off, or keep covering them while a payment is
/// late.

import { useCallback, useEffect, useId, useState } from "react";
import { useParams } from "next/navigation";
import { api, errCode, money, readErr, type ClubMemberRow } from "@/lib/api";
import {
  MAX_BILL_CENTS,
  parseAmount,
  passCovers,
  passPrice,
  postOnce,
  shortDate,
  standingWord,
  useAttemptKey,
  kindWord,
  type PassHolder,
  type PassPlan,
  type PriceType,
} from "@/lib/payments";
import {
  COVERABLE,
  TEMPLATE_IDS,
  blankDraft,
  longDay,
  passBody,
  templateDraft,
  todayDay,
  type PassDraft,
  type TemplateId,
} from "@/lib/passes";
import { MoneyAdminPage } from "@/components/MoneyAdmin";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// The five starting points (plan §3): a name, and a line saying what each
/// is, in the club's own currency.
const TEMPLATE: Record<TemplateId, { name: Key; about: Key; cents: number; part?: number }> = {
  winter: { name: "pw3.tpl_winter", about: "pw3.tpl_winter_about", cents: 6000 },
  card10: { name: "pw3.tpl_card10", about: "pw3.tpl_card10_about", cents: 4000 },
  monthly: { name: "pw3.tpl_monthly", about: "pw3.tpl_monthly_about", cents: 2000 },
  season: { name: "pw3.tpl_season", about: "pw3.tpl_season_about", cents: 12000, part: 4000 },
  junior: { name: "pw3.tpl_junior", about: "pw3.tpl_junior_about", cents: 5000 },
};

export default function ClubPassesPage() {
  const t = useT();
  const { id: clubId } = useParams<{ id: string }>();
  return (
    <MoneyAdminPage clubId={clubId} title={t("pw3.passes")} intro={t("pw3.passes_admin_intro")}>
      {({ currency }) => <Passes clubId={clubId} currency={currency} />}
    </MoneyAdminPage>
  );
}

function Passes({ clubId, currency }: { clubId: string; currency: string }) {
  const t = useT();
  const [plans, setPlans] = useState<PassPlan[] | null>(null);
  const [types, setTypes] = useState<PriceType[]>([]);
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [draft, setDraft] = useState<PassDraft | null>(null);
  const [opened, setOpened] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [p, ty, m] = await Promise.all([
        api<PassPlan[]>("GET", `/clubs/${clubId}/passes?all=true`),
        api<PriceType[]>("GET", `/clubs/${clubId}/price-types`).catch(() => [] as PriceType[]),
        api<ClubMemberRow[]>("GET", `/clubs/${clubId}/members`).catch(() => [] as ClubMemberRow[]),
      ]);
      setPlans(p);
      setTypes(ty.filter((x) => !x.archived_at));
      setMembers(m);
      setError(null);
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  const start = (id: TemplateId | null) => {
    setNotice(null);
    setDraft(
      id
        ? templateDraft(id, t(TEMPLATE[id].name), types)
        : blankDraft(),
    );
  };

  return (
    <>
      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="panel" aria-labelledby="make-pass">
        <h2 id="make-pass">{t("pw3.make_a_pass")}</h2>
        {draft ? (
          <PassForm
            clubId={clubId}
            currency={currency}
            draft={draft}
            types={types}
            onDraft={setDraft}
            onCancel={() => setDraft(null)}
            onMade={async (plan) => {
              setDraft(null);
              setNotice(t("pw3.pass_made", { pass: plan.name }));
              setOpened(plan.id);
              await load();
            }}
          />
        ) : (
          <>
            <p className="muted">{t("pw3.pick_a_template")}</p>
            <div className="template-grid">
              {TEMPLATE_IDS.map((id) => (
                <button key={id} type="button" className="template-card" onClick={() => start(id)}>
                  <strong>{t(TEMPLATE[id].name)}</strong>
                  <span className="subtle">
                    {t(TEMPLATE[id].about, {
                      amount: money(TEMPLATE[id].cents, currency),
                      part: money(TEMPLATE[id].part ?? 0, currency),
                    })}
                  </span>
                </button>
              ))}
              <button type="button" className="template-card" onClick={() => start(null)}>
                <strong>{t("acc.kind_other")}</strong>
                <span className="subtle">{t("pw3.tpl_other_about")}</span>
              </button>
            </div>
          </>
        )}
      </section>

      <section className="panel" aria-labelledby="club-passes">
        <h2 id="club-passes">{t("pw3.club_passes")}</h2>
        {!plans ? (
          !error && <div className="skeleton" style={{ height: 120 }} />
        ) : plans.length === 0 ? (
          <p className="muted">{t("pw3.no_passes_yet")}</p>
        ) : (
          <ul className="pay-list pass-admin-list">
            {plans.map((p) => (
              <li key={p.id}>
                <div>
                  <strong>{p.name}</strong>{" "}
                  {p.archived_at && <span className="tag grey">{t("pw3.not_offered")}</span>}
                  {!p.archived_at && !p.open_to_join && <span className="tag grey">{t("pw3.you_add_people")}</span>}
                  <div>{passPrice(p, t)}</div>
                  <div className="muted">
                    {passCovers(p, t)}
                    {p.price_type_id && ` · ${t("pw3.only_for", { group: types.find((x) => x.id === p.price_type_id)?.name ?? "" })}`}
                  </div>
                  <div className="subtle">{t("pw3.n_on_it", { count: p.holders, n: p.holders })}</div>
                </div>
                <div className="pay-list-end">
                  <button
                    className="btn"
                    type="button"
                    aria-expanded={opened === p.id}
                    onClick={() => setOpened(opened === p.id ? null : p.id)}
                  >
                    {opened === p.id ? t("sr.close") : t("pw3.see_whos_on_it")}
                  </button>
                </div>
                {opened === p.id && (
                  <Holders
                    plan={p}
                    members={members}
                    onChanged={async (said) => {
                      setNotice(said);
                      await load();
                    }}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}

/// The pass, as the secretary changes the numbers.
function PassForm({
  clubId,
  currency,
  draft: d,
  types,
  onDraft,
  onCancel,
  onMade,
}: {
  clubId: string;
  currency: string;
  draft: PassDraft;
  types: PriceType[];
  onDraft: (d: PassDraft) => void;
  onCancel: () => void;
  onMade: (plan: PassPlan) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tried, setTried] = useState(false);
  const attempt = useAttemptKey();
  const set = (patch: Partial<PassDraft>) => onDraft({ ...d, ...patch });

  const cents = parseAmount(d.price);
  const checked = passBody(d, cents != null && cents > MAX_BILL_CENTS ? null : cents);
  const problem = "problem" in checked ? t(checked.problem) : null;
  const monthly = d.billing === "monthly";
  const parts = Number(d.instalments);

  const save = async () => {
    setTried(true);
    if (!("body" in checked)) return;
    setBusy(true);
    setError(null);
    try {
      const plan = await postOnce<PassPlan>(
        `/clubs/${clubId}/passes`,
        checked.body,
        attempt.key(JSON.stringify(checked.body)),
      );
      attempt.done();
      await onMade(plan);
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  const billing: [string, Key][] = [
    ["once", "pw3.billing_once"],
    ["monthly", "pw3.every_month"],
    ["instalments", "pw3.billing_parts"],
  ];
  const lasts: [string, Key][] = [
    ["date", "pw3.lasts_date"],
    ["sessions", "pw3.lasts_sessions"],
    ["none", "pw3.lasts_none"],
  ];

  return (
    <form
      className="cost-form pass-form"
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <div className="setup-fields">
        <label htmlFor={`${id}-name`}>
          {t("pw2.row_name")}
          <input id={`${id}-name`} value={d.name} maxLength={60} onChange={(e) => set({ name: e.target.value })} />
        </label>
      </div>

      <fieldset className="chip-set">
        <legend>{t("pay.how_its_paid")}</legend>
        {billing.map(([value, label]) => (
          <button
            key={value}
            type="button"
            className={`chip${d.billing === value ? " on" : ""}`}
            aria-pressed={d.billing === value}
            onClick={() => set({ billing: value })}
          >
            {t(label)}
          </button>
        ))}
      </fieldset>

      <div className="setup-fields">
        <label htmlFor={`${id}-price`}>
          <span id={`${id}-price-label`}>
            {monthly ? t("pw3.price_each_month") : d.billing === "instalments" ? t("pw3.price_full") : t("sh.price")}
          </span>
          <input
            id={`${id}-price`}
            aria-labelledby={`${id}-price-label`}
            inputMode="decimal"
            value={d.price}
            placeholder="20.00"
            onChange={(e) => set({ price: e.target.value })}
          />
          {d.billing === "instalments" && cents != null && cents > 0 && Number.isInteger(parts) && parts >= 2 && parts <= 12 && (
            <span className="subtle">{t("pw3.parts_of", { n: parts, part: money(Math.ceil(cents / parts), currency) })}</span>
          )}
        </label>
        {d.billing === "instalments" && (
          <label htmlFor={`${id}-parts`}>
            {t("pw3.how_many_parts")}
            <input
              id={`${id}-parts`}
              type="number"
              inputMode="numeric"
              min={2}
              max={12}
              value={d.instalments}
              onChange={(e) => set({ instalments: e.target.value })}
            />
          </label>
        )}
      </div>

      <fieldset className="chip-set">
        <legend>{t("pw3.what_it_covers")}</legend>
        {COVERABLE.map((kind) => {
          const on = d.covers.includes(kind);
          return (
            <button
              key={kind}
              type="button"
              className={`chip${on ? " on" : ""}`}
              aria-pressed={on}
              onClick={() => set({ covers: on ? d.covers.filter((c) => c !== kind) : [...d.covers, kind] })}
            >
              {kindWord(kind, t)}
            </button>
          );
        })}
      </fieldset>
      <p className="subtle">{t("pw3.covers_none_hint")}</p>

      {monthly ? (
        <p className="subtle">{t("pw3.monthly_runs")}</p>
      ) : (
        <>
          <fieldset className="chip-set">
            <legend>{t("pw3.how_long")}</legend>
            {lasts.map(([value, label]) => (
              <button
                key={value}
                type="button"
                className={`chip${d.lasts === value ? " on" : ""}`}
                aria-pressed={d.lasts === value}
                onClick={() => set({ lasts: value })}
              >
                {t(label)}
              </button>
            ))}
          </fieldset>
          <div className="setup-fields">
            {d.lasts === "date" && (
              <label htmlFor={`${id}-until`}>
                {t("pw3.covers_until_label")}
                <input
                  id={`${id}-until`}
                  type="date"
                  min={todayDay()}
                  value={d.valid_until}
                  onChange={(e) => set({ valid_until: e.target.value })}
                />
              </label>
            )}
            {d.lasts === "sessions" && (
              <label htmlFor={`${id}-sessions`}>
                {t("pw3.how_many_sessions")}
                <input
                  id={`${id}-sessions`}
                  type="number"
                  inputMode="numeric"
                  min={1}
                  max={500}
                  value={d.sessions}
                  onChange={(e) => set({ sessions: e.target.value })}
                />
              </label>
            )}
          </div>
        </>
      )}

      <div className="setup-fields">
        <label htmlFor={`${id}-who`}>
          {t("pw3.who_can_have_it")}
          <select id={`${id}-who`} value={d.price_type_id} onChange={(e) => set({ price_type_id: e.target.value })}>
            <option value="">{t("pw3.anyone")}</option>
            {types
              .filter((x) => !x.for_guests)
              .map((x) => (
                <option key={x.id} value={x.id}>
                  {t("pw3.only_for", { group: x.name })}
                </option>
              ))}
          </select>
        </label>
      </div>
      <label className="check-row">
        <input type="checkbox" checked={d.open_to_join} onChange={(e) => set({ open_to_join: e.target.checked })} />
        <span>
          <strong>{t("pw3.players_can_get_it")}</strong>
          <span className="subtle">{t("pw3.players_can_get_it_hint")}</span>
        </span>
      </label>

      {(tried || d.price.trim()) && problem && <p className="field-error">{problem}</p>}
      {cents != null && cents > MAX_BILL_CENTS && (
        <p className="field-error">{t("pay.too_much_total", { max: money(MAX_BILL_CENTS, currency) })}</p>
      )}
      {error && <p className="field-error" role="alert">{error}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy}>
          {t("pw3.make_it")}
        </button>
        <button className="btn" type="button" disabled={busy} onClick={onCancel}>
          {t("pay.never_mind")}
        </button>
      </div>
    </form>
  );
}

/// Who's on a pass and how each stands, with Add, Cancel and Keep covering.
function Holders({
  plan,
  members,
  onChanged,
}: {
  plan: PassPlan;
  members: ClubMemberRow[];
  onChanged: (said: string) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const [holders, setHolders] = useState<PassHolder[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [asking, setAsking] = useState<string | null>(null);
  const [adding, setAdding] = useState("");
  const [startOn, setStartOn] = useState(todayDay());
  const attempt = useAttemptKey();

  const load = useCallback(async () => {
    try {
      setHolders(await api<PassHolder[]>("GET", `/passes/${plan.id}/holders`));
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [plan.id, t]);

  useEffect(() => {
    void load();
  }, [load]);

  const act = async (work: () => Promise<unknown>, said: string) => {
    setBusy(true);
    setError(null);
    try {
      await work();
      setAsking(null);
      await load();
      await onChanged(said);
    } catch (e) {
      if (errCode(e) === "already_cancelled" || errCode(e) === "already_on_pass") await load();
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  const open = (holders ?? []).filter((h) => !h.cancelled_at);
  const ended = (holders ?? []).filter((h) => h.cancelled_at);
  const onIt = new Set(open.map((h) => h.user_id));
  const choices = members.filter((m) => !onIt.has(m.user_id));
  const monthly = plan.billing === "monthly";

  const add = () => {
    if (!adding) return;
    const body = { user_id: adding, started_on: startOn || undefined };
    const who = members.find((m) => m.user_id === adding)?.name ?? "";
    void act(async () => {
      await postOnce<PassHolder>(`/passes/${plan.id}/holders`, body, attempt.key(JSON.stringify([plan.id, body])));
      attempt.done();
      setAdding("");
    }, t("pw3.added_to_pass", { name: who, pass: plan.name }));
  };

  return (
    <div className="pass-holders">
      {error && <p className="field-error" role="alert">{error}</p>}
      {!holders ? (
        !error && <div className="skeleton" style={{ height: 80 }} />
      ) : open.length === 0 ? (
        <p className="muted">{t("pw3.nobody_on_it")}</p>
      ) : (
        <ul className="pay-list">
          {open.map((h) => (
            <li key={h.id}>
              <div>
                <strong>{h.name}</strong>{" "}
                <span className={h.standing === "up_to_date" ? "tag" : h.standing === "behind" ? "tag gold" : "tag warn"}>
                  {standingWord(h.standing, t)}
                </span>
                {h.keep_covering && <span className="tag grey">{t("pw3.kept_covering")}</span>}
                <div className="muted">
                  {[
                    t("pw3.since", { date: longDay(h.started_on) }),
                    h.sessions_left != null ? t("pw3.pass_sessions_left", { count: h.sessions_left, n: h.sessions_left }) : "",
                    h.next_charge_on ? t("pw3.next_charge", { date: longDay(h.next_charge_on) }) : "",
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
              </div>
              {asking === h.id ? (
                <div className="confirm-box" role="group" aria-label={t("pw3.take_off_q", { name: h.name, pass: plan.name })}>
                  <p>
                    <strong>{t("pw3.take_off_q", { name: h.name, pass: plan.name })}</strong>
                  </p>
                  <p className="subtle">{monthly ? t("pw3.take_off_monthly") : t("pw3.take_off_once")}</p>
                  <div className="field-row">
                    <button
                      className="btn danger"
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        void act(
                          () => api("POST", `/pass-holders/${h.id}/cancel`),
                          t("pw3.taken_off", { name: h.name, pass: plan.name }),
                        )
                      }
                    >
                      {t("pw3.yes_take_off")}
                    </button>
                    <button className="btn" type="button" disabled={busy} onClick={() => setAsking(null)}>
                      {t("pay.never_mind")}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="pay-list-end">
                  {(h.standing !== "up_to_date" || h.keep_covering) && (
                    <button
                      className="btn"
                      type="button"
                      disabled={busy}
                      title={t("pw3.keep_covering_hint")}
                      onClick={() =>
                        void act(
                          () => api("PUT", `/pass-holders/${h.id}/keep-covering`, { on: !h.keep_covering }),
                          h.keep_covering
                            ? t("pw3.stopped_covering", { name: h.name })
                            : t("pw3.keeping_covered", { name: h.name }),
                        )
                      }
                    >
                      {h.keep_covering ? t("pw3.stop_keep_covering") : t("pw3.keep_covering")}
                    </button>
                  )}
                  <button
                    className="btn ghost"
                    type="button"
                    aria-label={t("pw3.take_off_name", { name: h.name })}
                    onClick={() => setAsking(h.id)}
                  >
                    {t("pw3.take_off")}
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      {ended.length > 0 && (
        <p className="subtle">
          {t("pw3.ended_list", {
            names: ended.map((h) => (h.ends_on ? `${h.name} (${shortDate(h.ends_on)})` : h.name)).join(", "),
          })}
        </p>
      )}

      {!plan.archived_at && (
        <div className="pass-add">
          <h3 id={`${id}-add`}>{t("pw3.add_somebody")}</h3>
          <div className="field-row">
            <label htmlFor={`${id}-who`}>
              {t("cl.who")}
              <select id={`${id}-who`} value={adding} onChange={(e) => setAdding(e.target.value)}>
                <option value="">{t("sc.choose_ellipsis")}</option>
                {choices.map((m) => (
                  <option key={m.user_id} value={m.user_id}>
                    {m.name}
                  </option>
                ))}
              </select>
            </label>
            <label htmlFor={`${id}-start`}>
              {t("pw3.starting")}
              <input id={`${id}-start`} type="date" value={startOn} onChange={(e) => setStartOn(e.target.value)} />
            </label>
            <button className="btn primary" type="button" disabled={busy || !adding} onClick={add}>
              {t("pw3.add_to_pass")}
            </button>
          </div>
          <p className="subtle">{t("pw3.add_first_payment")}</p>
        </div>
      )}

      <div className="field-row pass-offer-toggle">
        <button
          className="btn ghost"
          type="button"
          disabled={busy}
          onClick={() =>
            void act(
              () => api("PATCH", `/passes/${plan.id}`, { archived: !plan.archived_at }),
              plan.archived_at ? t("pw3.offered_again", { pass: plan.name }) : t("pw3.stopped_offering", { pass: plan.name }),
            )
          }
        >
          {plan.archived_at ? t("pw3.offer_again") : t("pw3.stop_offering")}
        </button>
      </div>
    </div>
  );
}
