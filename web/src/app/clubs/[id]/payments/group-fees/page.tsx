"use client";

/// Group fees, for whoever looks after the club's money (plan §4): a charge
/// not tied to a session — league registration, the tour, match balls, a kit
/// order. Who (everyone, a team, juniors, ticked names, plus guests), how
/// much (a total to split, or the same from each), and a date to pay by.
/// Then the list, one opened, Share to WhatsApp, and cancel.

import { useCallback, useEffect, useId, useState } from "react";
import { useParams } from "next/navigation";
import { api, errCode, money, readErr, type ClubMemberRow, type Team } from "@/lib/api";
import {
  STALE_CODES,
  postOnce,
  shareStateTag,
  shareTag,
  useAttemptKey,
  type GroupFee,
  type PriceType,
} from "@/lib/payments";
import { shortDay, todayDay } from "@/lib/passes";
import { CostModePicker, costCheck } from "@/components/EventMoney";
import { MoneyAdminPage } from "@/components/MoneyAdmin";
import { ReasonForm } from "@/components/ReasonForm";
import { ShareBill } from "@/components/ShareBill";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

export default function GroupFeesPage() {
  const t = useT();
  const { id: clubId } = useParams<{ id: string }>();
  return (
    <MoneyAdminPage clubId={clubId} title={t("pw3.group_fees")} intro={t("pw3.group_fees_intro")}>
      {({ currency }) => <GroupFees clubId={clubId} currency={currency} />}
    </MoneyAdminPage>
  );
}

function GroupFees({ clubId, currency }: { clubId: string; currency: string }) {
  const t = useT();
  const [fees, setFees] = useState<GroupFee[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [making, setMaking] = useState(false);
  const [opened, setOpened] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const list = await api<GroupFee[]>("GET", `/clubs/${clubId}/collections`);
      setFees(list);
      setError(null);
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="panel" aria-labelledby="new-fee">
        <div className="panel-head">
          <h2 id="new-fee">{t("pw3.new_group_fee")}</h2>
        </div>
        {making || fees?.length === 0 ? (
          <NewFee
            clubId={clubId}
            currency={currency}
            onCancel={fees?.length ? () => setMaking(false) : undefined}
            onMade={async (fee) => {
              setMaking(false);
              setNotice(t("pw3.fee_sent", { title: fee.title, count: fee.people, n: fee.people }));
              setOpened(fee.id);
              await load();
            }}
          />
        ) : (
          <>
            <p className="muted">{t("pw3.new_group_fee_help")}</p>
            <button className="btn primary lg" type="button" onClick={() => setMaking(true)}>
              {t("pw3.new_group_fee")}
            </button>
          </>
        )}
      </section>

      <section className="panel" aria-labelledby="fee-list">
        <h2 id="fee-list">{t("pw3.group_fees")}</h2>
        {!fees ? (
          !error && <div className="skeleton" style={{ height: 120 }} />
        ) : fees.length === 0 ? (
          <p className="muted">{t("pw3.no_group_fees")}</p>
        ) : (
          <ul className="pay-list">
            {fees.map((f) => (
              <li key={f.id}>
                <div>
                  <strong>{f.title}</strong> {f.status === "void" && <span className="tag grey">{t("pay.state_void")}</span>}
                  <div className="muted">
                    {[f.due_on ? t("pw3.by_date", { date: shortDay(f.due_on) }) : "", t("pay.n_people", { count: f.people, n: f.people })]
                      .filter(Boolean)
                      .join(" · ")}
                  </div>
                  <div className="num">
                    {t("pay.collected_of", { paid: money(f.paid_cents, f.currency), total: money(f.total_cents, f.currency) })}
                  </div>
                </div>
                <div className="pay-list-end">
                  <button
                    className="btn"
                    type="button"
                    aria-expanded={opened === f.id}
                    aria-label={opened === f.id ? t("sr.close") : t("pw3.see_who_owes_for", { title: f.title })}
                    onClick={() => setOpened(opened === f.id ? null : f.id)}
                  >
                    {opened === f.id ? t("sr.close") : t("pw3.see_who_owes")}
                  </button>
                </div>
                {opened === f.id && (
                  <FeeDetail
                    feeId={f.id}
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

type Who = "everyone" | "team" | "group" | "names";

/// "New group fee": who, how much, and by when.
function NewFee({
  clubId,
  currency,
  onCancel,
  onMade,
}: {
  clubId: string;
  currency: string;
  onCancel?: () => void;
  onMade: (fee: GroupFee) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const [title, setTitle] = useState("");
  const [who, setWho] = useState<Who>("everyone");
  const [teamId, setTeamId] = useState("");
  const [groupId, setGroupId] = useState("");
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  const [guests, setGuests] = useState<string[]>([]);
  const [guest, setGuest] = useState("");
  const [mode, setMode] = useState("per_player");
  const [amount, setAmount] = useState("");
  const [due, setDue] = useState("");
  const [note, setNote] = useState("");
  const [teams, setTeams] = useState<Team[]>([]);
  const [groups, setGroups] = useState<PriceType[]>([]);
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tried, setTried] = useState(false);
  const attempt = useAttemptKey();

  useEffect(() => {
    void Promise.all([
      api<Team[]>("GET", `/clubs/${clubId}/teams`).catch(() => [] as Team[]),
      api<PriceType[]>("GET", `/clubs/${clubId}/price-types`).catch(() => [] as PriceType[]),
      api<ClubMemberRow[]>("GET", `/clubs/${clubId}/members`).catch(() => [] as ClubMemberRow[]),
    ]).then(([tm, g, m]) => {
      setTeams(tm);
      const live = g.filter((x) => !x.archived_at && !x.for_guests);
      setGroups(live);
      setGroupId((cur) => cur || (live.find((x) => /junior/i.test(x.name)) ?? live[0])?.id || "");
      setTeamId((cur) => cur || tm[0]?.id || "");
      setMembers(m);
    });
  }, [clubId]);

  const check = costCheck(mode, amount, currency, t);
  const whoChoices: [Who, Key][] = [
    ["everyone", "pw3.who_everyone"],
    ...(teams.length > 0 ? ([["team", "pw3.who_team"]] as [Who, Key][]) : []),
    ...(groups.length > 0 ? ([["group", "pw3.who_group"]] as [Who, Key][]) : []),
    ["names", "pw3.who_names"],
  ];
  const whoMissing =
    (who === "names" && ticked.size === 0 && guests.length === 0) ||
    (who === "team" && !teamId) ||
    (who === "group" && !groupId);
  const problem = !title.trim()
    ? t("pw3.need_title")
    : check.cents == null
      ? check.problem ?? t("pay.not_an_amount")
      : check.problem ?? (whoMissing ? t("pw3.need_who") : null);

  const addGuest = () => {
    const name = guest.trim().replace(/\s+/g, " ");
    if (name && !guests.some((g) => g.toLowerCase() === name.toLowerCase())) setGuests([...guests, name]);
    setGuest("");
  };

  const send = async () => {
    setTried(true);
    if (problem || check.cents == null) return;
    const body = {
      title: title.trim(),
      mode,
      amount_cents: check.cents,
      due_on: due || undefined,
      note: note.trim() || undefined,
      everyone: who === "everyone" ? true : undefined,
      team_id: who === "team" ? teamId : undefined,
      price_type_id: who === "group" ? groupId : undefined,
      user_ids: who === "names" && ticked.size > 0 ? [...ticked] : undefined,
      guests: guests.length > 0 ? guests : undefined,
    };
    setBusy(true);
    setError(null);
    try {
      const fee = await postOnce<GroupFee>(`/clubs/${clubId}/collections`, body, attempt.key(JSON.stringify(body)));
      attempt.done();
      await onMade(fee);
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      className="cost-form fee-form"
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void send();
      }}
    >
      <div className="setup-fields">
        <label htmlFor={`${id}-title`}>
          {t("pw3.fee_title")}
          <input
            id={`${id}-title`}
            value={title}
            maxLength={80}
            placeholder={t("pw3.fee_title_hint")}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
      </div>

      <fieldset className="chip-set">
        <legend>{t("pw3.who_pays")}</legend>
        {whoChoices.map(([value, label]) => (
          <button
            key={value}
            type="button"
            className={`chip${who === value ? " on" : ""}`}
            aria-pressed={who === value}
            onClick={() => setWho(value)}
          >
            {t(label)}
          </button>
        ))}
      </fieldset>
      {who === "team" && (
        <div className="setup-fields">
          <label htmlFor={`${id}-team`}>
            {t("pw3.which_team")}
            <select id={`${id}-team`} value={teamId} onChange={(e) => setTeamId(e.target.value)}>
              {teams.map((tm) => (
                <option key={tm.id} value={tm.id}>
                  {tm.name}
                </option>
              ))}
            </select>
          </label>
        </div>
      )}
      {who === "group" && (
        <div className="setup-fields">
          <label htmlFor={`${id}-group`}>
            {t("pw3.which_group")}
            <select id={`${id}-group`} value={groupId} onChange={(e) => setGroupId(e.target.value)}>
              {groups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          </label>
        </div>
      )}
      {who === "names" && (
        <fieldset className="who-list">
          <legend>{t("pw3.tick_names")}</legend>
          {members.map((m) => (
            <label className="who-person" key={m.user_id}>
              <input
                type="checkbox"
                checked={ticked.has(m.user_id)}
                onChange={() =>
                  setTicked((cur) => {
                    const next = new Set(cur);
                    if (next.has(m.user_id)) next.delete(m.user_id);
                    else next.add(m.user_id);
                    return next;
                  })
                }
              />
              <span className="who-name">{m.name}</span>
            </label>
          ))}
        </fieldset>
      )}
      <div className="field-row who-guest">
        <label htmlFor={`${id}-guest`}>
          {t("pay.add_a_guest")}
          <input
            id={`${id}-guest`}
            value={guest}
            maxLength={60}
            placeholder={t("pay.guest_hint")}
            onChange={(e) => setGuest(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addGuest();
              }
            }}
          />
        </label>
        <button className="btn" type="button" disabled={!guest.trim()} onClick={addGuest}>
          {t("pay.add")}
        </button>
      </div>
      {guests.length > 0 && (
        <ul className="who-guests" aria-label={t("pay.guests")}>
          {guests.map((g) => (
            <li key={g}>
              <span>{g}</span>
              <button
                className="btn ghost"
                type="button"
                aria-label={t("pay.remove_name", { name: g })}
                onClick={() => setGuests(guests.filter((x) => x !== g))}
              >
                {t("pay.remove")}
              </button>
            </li>
          ))}
        </ul>
      )}

      <CostModePicker mode={mode} onMode={setMode} />
      <div className="setup-fields">
        <label htmlFor={`${id}-amount`}>
          <span id={`${id}-amount-label`}>
            {mode === "split_total" ? t("pay.total_to_split") : t("pay.each_person_pays")}
          </span>
          <input
            id={`${id}-amount`}
            aria-labelledby={`${id}-amount-label`}
            inputMode="decimal"
            value={amount}
            placeholder={mode === "split_total" ? "300.00" : "25.00"}
            onChange={(e) => setAmount(e.target.value)}
          />
        </label>
        <label htmlFor={`${id}-due`}>
          {t("pw3.pay_by_optional")}
          <input id={`${id}-due`} type="date" min={todayDay()} value={due} onChange={(e) => setDue(e.target.value)} />
        </label>
        <label htmlFor={`${id}-note`}>
          {t("pay.note_optional")}
          <input id={`${id}-note`} value={note} maxLength={200} onChange={(e) => setNote(e.target.value)} />
        </label>
      </div>

      {(tried || amount.trim()) && problem && <p className="field-error">{problem}</p>}
      {error && <p className="field-error" role="alert">{error}</p>}
      <p className="subtle">{t("pw3.fee_told")}</p>
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy}>
          {t("pw3.send_group_fee")}
        </button>
        {onCancel && (
          <button className="btn" type="button" disabled={busy} onClick={onCancel}>
            {t("pay.never_mind")}
          </button>
        )}
      </div>
    </form>
  );
}

/// One group fee opened: who owes what, Share to WhatsApp, and cancel.
function FeeDetail({ feeId, onChanged }: { feeId: string; onChanged: (said: string) => Promise<void> }) {
  const t = useT();
  const [fee, setFee] = useState<GroupFee | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setFee(await api<GroupFee>("GET", `/collections/${feeId}`));
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [feeId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!fee) return error ? <p className="field-error" role="alert">{error}</p> : <div className="skeleton" style={{ height: 80 }} />;
  const live = fee.status !== "void";

  const cancel = async (reason: string) => {
    setBusy(true);
    setFormError(null);
    try {
      setFee(await api<GroupFee>("POST", `/collections/${fee.id}/void`, { reason }));
      setCancelling(false);
      await onChanged(t("pw3.fee_cancelled", { title: fee.title }));
    } catch (e) {
      if (STALE_CODES.has(errCode(e) ?? "")) {
        setCancelling(false);
        await load();
      }
      setFormError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fee-detail">
      {fee.note && <p className="muted">{t("pay.bill_note", { note: fee.note })}</p>}
      {!live && fee.void_reason && <p className="muted">{t("pw3.cancelled_because", { reason: fee.void_reason })}</p>}
      {(fee.waiting_cents > 0 || fee.owed_cents > 0) && (
        <p className="muted">
          {t("pay.waiting_and_owed", { waiting: money(fee.waiting_cents, fee.currency), owed: money(fee.owed_cents, fee.currency) })}
        </p>
      )}
      <ul className="pay-list money-shares" aria-label={t("pay.who_owes_what_on_bill")}>
        {fee.shares.map((s) => (
          <li key={s.id}>
            <div>
              <strong>{s.name}</strong> {s.user_id == null && <span className="tag grey">{t("pay.guest")}</span>}
            </div>
            <div className="pay-list-end">
              <span className="num">{money(s.amount_cents, s.currency)}</span>
              <span className={shareStateTag(s.state)}>{shareTag(s, t)}</span>
            </div>
          </li>
        ))}
      </ul>

      {live && (
        <ShareBill billId={fee.id} refreshKey={`${fee.id}:${fee.paid_cents}:${fee.waiting_cents}:${fee.owed_cents}`} />
      )}

      {live &&
        (cancelling ? (
          <ReasonForm
            label={t("pw3.why_cancel_fee")}
            hint={t("pw3.cancel_fee_hint")}
            submitLabel={t("pw3.cancel_fee")}
            danger
            busy={busy}
            error={formError}
            onCancel={() => setCancelling(false)}
            onSubmit={(reason) => void cancel(reason)}
          />
        ) : (
          <div className="field-row money-actions">
            <button className="btn ghost" type="button" onClick={() => setCancelling(true)}>
              {t("pw3.cancel_fee")}
            </button>
          </div>
        ))}
    </div>
  );
}
