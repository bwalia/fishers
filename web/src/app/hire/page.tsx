"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  money,
  readErr,
  SPORTS,
  type HireableSpace,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

const KIND_LABEL: Record<string, string> = {
  pitch: "Pitch",
  square: "le.square",
  net_lane: "le.net_lane",
  court: "le.court",
  hall: "le.hall",
  pavilion: "le.pavilion",
  bar: "Bar",
  room: "le.room",
  other: "le.space",
};

export default function HireBrowsePage() {
  const t = useT();
  const [rows, setRows] = useState<HireableSpace[] | null>(null);
  const [q, setQ] = useState("");
  const [sport, setSport] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(() => {
      void load();
    }, 200);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, sport]);

  async function load() {
    setError(null);
    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set("q", q.trim());
      if (sport) params.set("sport", sport);
      params.set("limit", "50");
      const qs = params.toString();
      const list = await api<HireableSpace[]>(
        "GET",
        `/hire/spaces${qs ? `?${qs}` : ""}`,
      );
      setRows(list);
    } catch (e) {
      setRows([]);
      setError(readErr(e, t("le.something_went_wrong")));
    }
  }

  return (
    <main className="page">
      <header className="page-head">
        <h1>
          <Icon name="pin" /> {t("rest.venue_hire")}
        </h1>
        <p className="lede">
          {t("rest.hire_lede")}
        </p>
      </header>

      <div className="toolbar" style={{ gap: 12, flexWrap: "wrap" }}>
        <label className="field" style={{ flex: "1 1 220px" }}>
          <span>{t("rest.search")}</span>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t("rest.club_venue_or_space")}
          />
        </label>
        <label className="field" style={{ flex: "0 1 180px" }}>
          <span>{t("rest.sport")}</span>
          <select value={sport} onChange={(e) => setSport(e.target.value)}>
            <option value="">{t("rest.any")}</option>
            {SPORTS.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </label>
      </div>

      {error && <p className="error">{error}</p>}

      {rows === null ? (
        <p className="muted">{t("rest.loading")}</p>
      ) : rows.length === 0 ? (
        <p className="muted">
          {t("rest.no_hireable_spaces_yet")}
        </p>
      ) : (
        <ul className="card-list">
          {rows.map((row) => (
            <li key={row.space_id} className="card">
              <div className="card-body">
                <h2>
                  {row.space_name}
                  <span className="pill" style={{ marginLeft: 8 }}>
                    {KIND_LABEL[row.kind] ?? row.kind}
                  </span>
                </h2>
                <p className="muted">
                  {row.club_name} · {row.venue_name}
                  {row.venue_address ? ` · ${row.venue_address}` : ""}
                </p>
                <p>
                  {row.sports.length > 0
                    ? row.sports.join(", ")
                    : t("le.general_hire")}
                  {row.capacity != null ? t("le.up_to_capacity", { n: row.capacity }) : ""}
                  {row.requires_approval ? t("le.approval_required") : t("le.instant")}
                </p>
                {row.from_amount_cents != null && (
                  <p className="price">
                    From {money(row.from_amount_cents, row.currency ?? "GBP")}
                  </p>
                )}
              </div>
              <Link
                className="btn ghost"
                href={`/clubs/${row.club_id}/hire`}
              >
                Club
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
