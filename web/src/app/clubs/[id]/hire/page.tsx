"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import {
  api,
  money,
  readErr,
  SPORTS,
  type Venue,
  type VenueRateCard,
  type VenueSpace,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

const KINDS = [
  "pitch",
  "square",
  "net_lane",
  "court",
  "hall",
  "pavilion",
  "bar",
  "room",
  "other",
] as const;

const UNITS = [
  "per_hour",
  "per_session",
  "per_half_day",
  "per_day",
  "per_head",
  "fixed",
] as const;

export default function ClubHireManagePage() {
  const t = useT();
  const authed = useRequireAuth();
  const params = useParams<{ id: string }>();
  const clubId = params.id;

  const [venues, setVenues] = useState<Venue[]>([]);
  const [venueId, setVenueId] = useState("");
  const [spaces, setSpaces] = useState<VenueSpace[]>([]);
  const [selected, setSelected] = useState<VenueSpace | null>(null);
  const [rates, setRates] = useState<VenueRateCard[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [name, setName] = useState("");
  const [kind, setKind] = useState<string>("pitch");
  const [sport, setSport] = useState("cricket");
  const [hireable, setHireable] = useState(true);
  const [capacity, setCapacity] = useState("");

  const [rateName, setRateName] = useState("Standard");
  const [rateUnit, setRateUnit] = useState<string>("per_hour");
  const [rateAmount, setRateAmount] = useState("40");
  const [memberAmount, setMemberAmount] = useState("");

  const loadVenues = useCallback(async () => {
    if (!authed || !clubId) return;
    try {
      const list = await api<Venue[]>("GET", `/clubs/${clubId}/venues`);
      setVenues(list);
      if (!venueId && list[0]) setVenueId(list[0].id);
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [authed, clubId, venueId, t]);

  const loadSpaces = useCallback(async () => {
    if (!authed || !venueId) return;
    try {
      const list = await api<VenueSpace[]>("GET", `/venues/${venueId}/spaces`);
      setSpaces(list);
    } catch (e) {
      setError(readErr(e, t("le.could_not_load_spaces")));
    }
  }, [authed, venueId, t]);

  const loadRates = useCallback(async () => {
    if (!authed || !selected) {
      setRates([]);
      return;
    }
    try {
      const list = await api<VenueRateCard[]>(
        "GET",
        `/spaces/${selected.id}/rates`,
      );
      setRates(list);
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }, [authed, selected, t]);

  useEffect(() => {
    void loadVenues();
  }, [loadVenues]);
  useEffect(() => {
    void loadSpaces();
  }, [loadSpaces]);
  useEffect(() => {
    void loadRates();
  }, [loadRates]);

  async function createSpace() {
    if (!venueId || !name.trim()) return;
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      const space = await api<VenueSpace>("POST", `/venues/${venueId}/spaces`, {
        name: name.trim(),
        kind,
        sports: sport ? [sport] : [],
        capacity: capacity ? Number(capacity) : null,
        is_hireable: hireable,
        requires_approval: true,
      });
      setName("");
      setCapacity("");
      setNote(`Added ${space.name}`);
      await loadSpaces();
      setSelected(space);
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    } finally {
      setBusy(false);
    }
  }

  async function toggleHireable(space: VenueSpace) {
    setBusy(true);
    setError(null);
    try {
      const updated = await api<VenueSpace>("PATCH", `/spaces/${space.id}`, {
        is_hireable: !space.is_hireable,
      });
      setSelected(updated);
      await loadSpaces();
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    } finally {
      setBusy(false);
    }
  }

  async function addRate() {
    if (!selected) return;
    const amount = Math.round(Number(rateAmount) * 100);
    if (!Number.isFinite(amount) || amount < 0) {
      setError(t("le.enter_a_valid_rate_in_pounds"));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api<VenueRateCard>("POST", `/spaces/${selected.id}/rates`, {
        name: rateName.trim() || "Standard",
        unit: rateUnit,
        amount_cents: amount,
        currency: "GBP",
        member_amount_cents: memberAmount
          ? Math.round(Number(memberAmount) * 100)
          : null,
      });
      setNote(t("le.rate_added"));
      await loadRates();
    } catch (e) {
      setError(readErr(e, t("le.something_went_wrong")));
    } finally {
      setBusy(false);
    }
  }

  if (!authed) return null;

  return (
    <main className="page">
      <header className="page-head">
        <p className="eyebrow">
          <Link href={`/clubs/${clubId}`}>← Club</Link>
        </p>
        <h1>
          <Icon name="pin" /> {t("cl.hireable_spaces")}
        </h1>
        <p className="lede">
          Define spaces under a venue site, set rates, and mark them hireable so
          they appear on{" "}
          <Link href="/hire">Hire</Link>. Bookings land in a later phase.
        </p>
      </header>

      {error && <p className="error">{error}</p>}
      {note && <p className="ok">{note}</p>}

      {venues.length === 0 ? (
        <p className="muted">
          {t("cl.add_a_venue_on_the_club_page_first_a_g")}
        </p>
      ) : (
        <>
          <label className="field">
            <span>{t("cl.venue_site")}</span>
            <select
              value={venueId}
              onChange={(e) => {
                setVenueId(e.target.value);
                setSelected(null);
              }}
            >
              {venues.map((v) => (
                <option key={v.id} value={v.id}>
                  {v.name}
                </option>
              ))}
            </select>
          </label>

          <section className="card" style={{ marginTop: 16 }}>
            <h2>{t("cl.add_a_space")}</h2>
            <div className="toolbar" style={{ flexWrap: "wrap", gap: 12 }}>
              <label className="field">
                <span>{t("cl.name")}</span>
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder={t("cl.main_pitch")}
                />
              </label>
              <label className="field">
                <span>{t("cl.kind")}</span>
                <select value={kind} onChange={(e) => setKind(e.target.value)}>
                  {KINDS.map((k) => (
                    <option key={k} value={k}>
                      {k.replace(/_/g, " ")}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>{t("cl.sport")}</span>
                <select
                  value={sport}
                  onChange={(e) => setSport(e.target.value)}
                >
                  <option value="">{t("cl.none_hall_pavilion")}</option>
                  {SPORTS.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>{t("cl.capacity")}</span>
                <input
                  value={capacity}
                  onChange={(e) => setCapacity(e.target.value)}
                  placeholder={t("le.optional")}
                  inputMode="numeric"
                />
              </label>
              <label className="field" style={{ flexDirection: "row", gap: 8 }}>
                <input
                  type="checkbox"
                  checked={hireable}
                  onChange={(e) => setHireable(e.target.checked)}
                />
                <span>{t("cl.list_as_hireable")}</span>
              </label>
              <button
                className="btn"
                type="button"
                disabled={busy || !name.trim()}
                onClick={() => void createSpace()}
              >
                {t("cl.add_space")}
              </button>
            </div>
          </section>

          <section style={{ marginTop: 24 }}>
            <h2>{t("cl.spaces")}</h2>
            {spaces.length === 0 ? (
              <p className="muted">{t("cl.none_yet_on_this_venue")}</p>
            ) : (
              <ul className="card-list">
                {spaces.map((s) => (
                  <li
                    key={s.id}
                    className={`card ${selected?.id === s.id ? "selected" : ""}`}
                  >
                    <button
                      type="button"
                      className="card-body"
                      style={{
                        textAlign: "left",
                        background: "transparent",
                        border: 0,
                        width: "100%",
                        cursor: "pointer",
                      }}
                      onClick={() => setSelected(s)}
                    >
                      <h3>
                        {s.name}{" "}
                        <span className="pill">{s.kind.replace(/_/g, " ")}</span>
                      </h3>
                      <p className="muted">
                        {s.is_hireable ? t("le.hireable") : t("le.not_listed")} ·{" "}
                        {s.sports.length ? s.sports.join(", ") : "general"}
                        {s.capacity != null ? ` · ${s.capacity}` : ""}
                      </p>
                    </button>
                    <button
                      type="button"
                      className="btn ghost"
                      disabled={busy}
                      onClick={() => void toggleHireable(s)}
                    >
                      {s.is_hireable ? t("le.unlist") : t("le.list")}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {selected && (
            <section className="card" style={{ marginTop: 24 }}>
              <h2>Rates for {selected.name}</h2>
              {rates.length === 0 ? (
                <p className="muted">{t("cl.no_rates_yet")}</p>
              ) : (
                <ul>
                  {rates.map((r) => (
                    <li key={r.id}>
                      {r.name}: {money(r.amount_cents, r.currency)} /{" "}
                      {r.unit.replace(/_/g, " ")}
                      {r.member_amount_cents != null
                        ? ` (members ${money(r.member_amount_cents, r.currency)})`
                        : ""}
                      {!r.active ? " — inactive" : ""}
                    </li>
                  ))}
                </ul>
              )}
              <div className="toolbar" style={{ flexWrap: "wrap", gap: 12 }}>
                <label className="field">
                  <span>{t("cl.label")}</span>
                  <input
                    value={rateName}
                    onChange={(e) => setRateName(e.target.value)}
                  />
                </label>
                <label className="field">
                  <span>{t("cl.unit")}</span>
                  <select
                    value={rateUnit}
                    onChange={(e) => setRateUnit(e.target.value)}
                  >
                    {UNITS.map((u) => (
                      <option key={u} value={u}>
                        {u.replace(/_/g, " ")}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>£ amount</span>
                  <input
                    value={rateAmount}
                    onChange={(e) => setRateAmount(e.target.value)}
                    inputMode="decimal"
                  />
                </label>
                <label className="field">
                  <span>£ member (optional)</span>
                  <input
                    value={memberAmount}
                    onChange={(e) => setMemberAmount(e.target.value)}
                    inputMode="decimal"
                  />
                </label>
                <button
                  className="btn"
                  type="button"
                  disabled={busy}
                  onClick={() => void addRate()}
                >
                  {t("cl.add_rate")}
                </button>
              </div>
            </section>
          )}
        </>
      )}
    </main>
  );
}
