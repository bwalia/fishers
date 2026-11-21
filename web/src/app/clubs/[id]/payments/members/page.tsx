"use client";

/// Prices for juniors, students… and who pays for whom, for whoever looks
/// after the club's money (plan §2, §4):
///   - name the groups with a price of their own, and mark one free (coaches)
///     or the price for guests;
///   - set each member's group, and who pays for them (a parent for a
///     junior);
///   - add a junior by name, who has no sign-in of their own.
///
/// Each session's prices by group are set on the session's own cost.

import { useCallback, useEffect, useId, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import { api, readErr, type ClubMemberRow } from "@/lib/api";
import { postOnce, useAttemptKey, type PriceType } from "@/lib/payments";
import { juniorGroup } from "@/lib/passes";
import { MoneyAdminPage } from "@/components/MoneyAdmin";
import { useT } from "@/lib/i18n/provider";

/// "Leave as it is" in a picker: the API has no way to read a member's
/// current group or payer back, so nothing is assumed.
const KEEP = "__keep__";
/// The usual price, or paying for themselves.
const NONE = "";

export default function PricesAndPayersPage() {
  const t = useT();
  const { id: clubId } = useParams<{ id: string }>();
  return (
    <MoneyAdminPage clubId={clubId} title={t("pw3.prices_and_payers")} intro={t("pw3.prices_and_payers_intro")}>
      {() => <PricesAndPayers clubId={clubId} />}
    </MoneyAdminPage>
  );
}

/// What was set here this visit, so the row can say so.
type Said = { group?: string; payer?: string };

function PricesAndPayers({ clubId }: { clubId: string }) {
  const t = useT();
  const [groups, setGroups] = useState<PriceType[] | null>(null);
  const [members, setMembers] = useState<ClubMemberRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [said, setSaid] = useState<Record<string, Said>>({});

  const load = useCallback(async () => {
    try {
      const [g, m] = await Promise.all([
        api<PriceType[]>("GET", `/clubs/${clubId}/price-types`),
        api<ClubMemberRow[]>("GET", `/clubs/${clubId}/members`),
      ]);
      setGroups(g.filter((x) => !x.archived_at));
      setMembers(m);
      setError(null);
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [clubId, t]);

  useEffect(() => {
    void load();
  }, [load]);

  const done = async (message: string) => {
    setNotice(message);
    setError(null);
    await load();
  };
  const remember = (userId: string, s: Said) => setSaid((cur) => ({ ...cur, [userId]: { ...cur[userId], ...s } }));

  return (
    <>
      {error && <p className="error" role="alert">{error}</p>}
      {notice && <p className="notice" role="status">{notice}</p>}
      <Groups clubId={clubId} groups={groups} onDone={done} />
      <Members
        clubId={clubId}
        groups={groups ?? []}
        members={members}
        said={said}
        onSaved={(userId, s, message) => {
          remember(userId, s);
          setNotice(message);
          setError(null);
        }}
      />
      <AddJunior
        clubId={clubId}
        groups={groups ?? []}
        members={members}
        onAdded={async (userId, s, message) => {
          remember(userId, s);
          await done(message);
        }}
      />
    </>
  );
}

/// "Prices for juniors, students…": the groups, and a new one.
function Groups({
  clubId,
  groups,
  onDone,
}: {
  clubId: string;
  groups: PriceType[] | null;
  onDone: (said: string) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const [name, setName] = useState("");
  const [free, setFree] = useState(false);
  const [forGuests, setForGuests] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const hasGuests = (groups ?? []).some((g) => g.for_guests);

  const act = async (work: () => Promise<unknown>, said: string) => {
    setBusy(true);
    setError(null);
    try {
      await work();
      await onDone(said);
      return true;
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const add = async () => {
    const clean = name.trim();
    if (!clean) return;
    const ok = await act(
      () => api("POST", `/clubs/${clubId}/price-types`, { name: clean, free, for_guests: forGuests }),
      t("pw3.group_added", { group: clean }),
    );
    if (ok) {
      setName("");
      setFree(false);
      setForGuests(false);
    }
  };

  const quick: [string, boolean, boolean][] = [
    [t("pw3.group_junior"), false, false],
    [t("pw3.group_student"), false, false],
    [t("pw3.group_coach"), true, false],
    [t("pay.guest"), false, true],
  ];

  return (
    <section className="panel" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>{t("pw3.prices_for_groups")}</h2>
      <p className="muted">{t("pw3.prices_for_groups_help")}</p>
      {!groups ? (
        <div className="skeleton" style={{ height: 80 }} />
      ) : groups.length === 0 ? (
        <p className="muted">{t("pw3.no_groups_yet")}</p>
      ) : (
        <ul className="pay-list">
          {groups.map((g) => (
            <li key={g.id}>
              <div>
                <strong>{g.name}</strong> {g.free && <span className="tag">{t("le.free")}</span>}{" "}
                {g.for_guests && <span className="tag grey">{t("pw3.for_guests")}</span>}
              </div>
              <div className="pay-list-end">
                <label className="check-row inline">
                  <input
                    type="checkbox"
                    checked={g.free}
                    disabled={busy}
                    onChange={(e) =>
                      void act(
                        () => api("PATCH", `/price-types/${g.id}`, { free: e.target.checked }),
                        t("pw3.group_saved", { group: g.name }),
                      )
                    }
                  />
                  <span>{t("le.free")}</span>
                </label>
                <button
                  className="btn ghost"
                  type="button"
                  disabled={busy}
                  aria-label={t("pay.remove_name", { name: g.name })}
                  onClick={() =>
                    void act(
                      () => api("PATCH", `/price-types/${g.id}`, { archived: true }),
                      t("pw3.group_removed", { group: g.name }),
                    )
                  }
                >
                  {t("pay.remove")}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <form
        className="cost-form"
        onSubmit={(e) => {
          e.preventDefault();
          void add();
        }}
      >
        <h3>{t("pw3.add_a_group")}</h3>
        <div className="chips">
          {quick
            .filter(([n, , guests]) => !(groups ?? []).some((g) => g.name.toLowerCase() === n.toLowerCase()) && !(guests && hasGuests))
            .map(([n, f, g]) => (
              <button
                key={n}
                type="button"
                className="chip"
                onClick={() => {
                  setName(n);
                  setFree(f);
                  setForGuests(g);
                }}
              >
                {n}
              </button>
            ))}
        </div>
        <div className="setup-fields">
          <label htmlFor={`${id}-name`}>
            {t("pw3.group_name")}
            <input id={`${id}-name`} value={name} maxLength={30} onChange={(e) => setName(e.target.value)} />
          </label>
        </div>
        <label className="check-row">
          <input type="checkbox" checked={free} onChange={(e) => setFree(e.target.checked)} />
          <span>
            <strong>{t("pw3.group_free")}</strong>
            <span className="subtle">{t("pw3.group_free_hint")}</span>
          </span>
        </label>
        {!hasGuests && (
          <label className="check-row">
            <input type="checkbox" checked={forGuests} onChange={(e) => setForGuests(e.target.checked)} />
            <span>
              <strong>{t("pw3.group_guests")}</strong>
              <span className="subtle">{t("pw3.group_guests_hint")}</span>
            </span>
          </label>
        )}
        {error && <p className="field-error" role="alert">{error}</p>}
        <div className="field-row">
          <button className="btn primary" type="submit" disabled={busy || !name.trim()}>
            {t("pw3.add_group")}
          </button>
        </div>
      </form>
    </section>
  );
}

/// Each member's group and who pays for them.
function Members({
  clubId,
  groups,
  members,
  said,
  onSaved,
}: {
  clubId: string;
  groups: PriceType[];
  members: ClubMemberRow[];
  said: Record<string, Said>;
  onSaved: (userId: string, s: Said, message: string) => void;
}) {
  const t = useT();
  const id = useId();
  const [filter, setFilter] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const shown = useMemo(() => {
    const term = filter.trim().toLowerCase();
    return term ? members.filter((m) => m.name.toLowerCase().includes(term)) : members;
  }, [members, filter]);

  return (
    <section className="panel" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>{t("pw3.members_prices_payers")}</h2>
      <p className="muted">{t("pw3.members_prices_payers_help")}</p>
      {members.length > 8 && (
        <div className="setup-fields">
          <label htmlFor={`${id}-find`}>
            {t("pw3.find_member")}
            <input id={`${id}-find`} value={filter} onChange={(e) => setFilter(e.target.value)} />
          </label>
        </div>
      )}
      <ul className="pay-list">
        {shown.map((m) => {
          const s = said[m.user_id];
          return (
            <li key={m.user_id}>
              <div>
                <strong>{m.name}</strong>
                {s && (
                  <div className="muted">
                    {[
                      s.group != null ? (s.group ? t("pw3.group_price", { group: s.group }) : t("pw3.usual_price")) : "",
                      s.payer != null ? (s.payer ? t("pw3.paid_for_by", { name: s.payer }) : t("pw3.pays_for_self")) : "",
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </div>
                )}
              </div>
              {open !== m.user_id && (
                <div className="pay-list-end">
                  <button
                    className="btn"
                    type="button"
                    aria-label={t("pw3.change_for", { name: m.name })}
                    onClick={() => setOpen(m.user_id)}
                  >
                    {t("la.change")}
                  </button>
                </div>
              )}
              {open === m.user_id && (
                <MemberForm
                  clubId={clubId}
                  member={m}
                  groups={groups}
                  members={members}
                  onCancel={() => setOpen(null)}
                  onSaved={(s, message) => {
                    setOpen(null);
                    onSaved(m.user_id, s, message);
                  }}
                />
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function MemberForm({
  clubId,
  member: m,
  groups,
  members,
  onCancel,
  onSaved,
}: {
  clubId: string;
  member: ClubMemberRow;
  groups: PriceType[];
  members: ClubMemberRow[];
  onCancel: () => void;
  onSaved: (s: Said, message: string) => void;
}) {
  const t = useT();
  const id = useId();
  const [group, setGroup] = useState(KEEP);
  const [payer, setPayer] = useState(KEEP);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    const s: Said = {};
    try {
      if (group !== KEEP) {
        await api("PUT", `/clubs/${clubId}/members/${m.user_id}/price-type`, { price_type_id: group || null });
        s.group = groups.find((g) => g.id === group)?.name ?? "";
      }
      if (payer !== KEEP) {
        await api("PUT", `/clubs/${clubId}/members/${m.user_id}/payer`, { payer_id: payer || null });
        s.payer = members.find((x) => x.user_id === payer)?.name ?? "";
      }
      onSaved(s, t("pw3.saved_for", { name: m.name }));
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
      // Whatever went through before the refusal still went through.
      if (Object.keys(s).length > 0) onSaved(s, readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      className="money-form"
      aria-label={t("pw3.change_for", { name: m.name })}
      onSubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <div className="setup-fields">
        <label htmlFor={`${id}-group`}>
          {t("pw3.their_price")}
          <select id={`${id}-group`} value={group} onChange={(e) => setGroup(e.target.value)}>
            <option value={KEEP}>{t("pw3.leave_as_it_is")}</option>
            <option value={NONE}>{t("pw3.usual_price")}</option>
            {groups
              .filter((g) => !g.for_guests)
              .map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
          </select>
        </label>
        <label htmlFor={`${id}-payer`}>
          {t("pw3.who_pays_for_them")}
          <select id={`${id}-payer`} value={payer} onChange={(e) => setPayer(e.target.value)}>
            <option value={KEEP}>{t("pw3.leave_as_it_is")}</option>
            <option value={NONE}>{t("pw3.they_pay_themselves")}</option>
            {members
              .filter((x) => x.user_id !== m.user_id)
              .map((x) => (
                <option key={x.user_id} value={x.user_id}>
                  {x.name}
                </option>
              ))}
          </select>
        </label>
      </div>
      {error && <p className="field-error" role="alert">{error}</p>}
      <div className="field-row">
        <button className="btn primary" type="submit" disabled={busy || (group === KEEP && payer === KEEP)}>
          {t("acc.save")}
        </button>
        <button className="btn" type="button" disabled={busy} onClick={onCancel}>
          {t("pay.never_mind")}
        </button>
      </div>
    </form>
  );
}

/// "Add a junior by name": somebody with no sign-in of their own, looked
/// after by the member who pays for them.
function AddJunior({
  clubId,
  groups,
  members,
  onAdded,
}: {
  clubId: string;
  groups: PriceType[];
  members: ClubMemberRow[];
  onAdded: (userId: string, s: Said, message: string) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const [name, setName] = useState("");
  const [payer, setPayer] = useState("");
  const [group, setGroup] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const attempt = useAttemptKey();
  // Juniors start on the club's Junior price, when it has one.
  const chosen = group ?? juniorGroup(groups)?.id ?? NONE;

  const add = async () => {
    const clean = name.trim();
    if (!clean || !payer) return;
    setBusy(true);
    setError(null);
    const body = { name: clean, payer_id: payer };
    try {
      const made = await postOnce<{ user_id: string; name: string }>(
        `/clubs/${clubId}/members/managed`,
        body,
        attempt.key(JSON.stringify(body)),
      );
      attempt.done();
      const payerName = members.find((m) => m.user_id === payer)?.name ?? "";
      let groupName: string | undefined;
      if (chosen) {
        await api("PUT", `/clubs/${clubId}/members/${made.user_id}/price-type`, { price_type_id: chosen }).catch(() => undefined);
        groupName = groups.find((g) => g.id === chosen)?.name;
      }
      setName("");
      setGroup(null);
      await onAdded(made.user_id, { group: groupName, payer: payerName }, t("pw3.junior_added", { name: made.name, payer: payerName }));
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>{t("pw3.add_junior")}</h2>
      <p className="muted">{t("pw3.add_junior_help")}</p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void add();
        }}
      >
        <div className="setup-fields">
          <label htmlFor={`${id}-name`}>
            {t("sc.their_name")}
            <input id={`${id}-name`} value={name} maxLength={70} onChange={(e) => setName(e.target.value)} />
          </label>
          <label htmlFor={`${id}-payer`}>
            {t("pw3.who_pays_for_them")}
            <select id={`${id}-payer`} value={payer} onChange={(e) => setPayer(e.target.value)}>
              <option value="">{t("sc.choose_ellipsis")}</option>
              {members.map((m) => (
                <option key={m.user_id} value={m.user_id}>
                  {m.name}
                </option>
              ))}
            </select>
          </label>
          {groups.length > 0 && (
            <label htmlFor={`${id}-group`}>
              {t("pw3.their_price")}
              <select id={`${id}-group`} value={chosen} onChange={(e) => setGroup(e.target.value)}>
                <option value={NONE}>{t("pw3.usual_price")}</option>
                {groups
                  .filter((g) => !g.for_guests)
                  .map((g) => (
                    <option key={g.id} value={g.id}>
                      {g.name}
                    </option>
                  ))}
              </select>
            </label>
          )}
        </div>
        {error && <p className="field-error" role="alert">{error}</p>}
        <div className="field-row">
          <button className="btn primary" type="submit" disabled={busy || !name.trim() || !payer}>
            {t("pw3.add_junior_button")}
          </button>
        </div>
      </form>
    </section>
  );
}
