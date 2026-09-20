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

const KIND_LABEL: Record<string, string> = {
  pitch: "Pitch",
  square: "Square",
  net_lane: "Net lane",
  court: "Court",
  hall: "Hall",
  pavilion: "Pavilion",
  bar: "Bar",
  room: "Room",
  other: "Space",
};

export default function HireBrowsePage() {
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
      setError(readErr(e, "Something went wrong"));
    }
  }

  return (
    <main className="page">
      <header className="page-head">
        <h1>
          <Icon name="pin" /> Venue hire
        </h1>
        <p className="lede">
          Spaces clubs are offering for hire — pitches, nets, halls and
          pavilions. Booking requests come in the next phase; this list is the
          catalogue.
        </p>
      </header>

      <div className="toolbar" style={{ gap: 12, flexWrap: "wrap" }}>
        <label className="field" style={{ flex: "1 1 220px" }}>
          <span>Search</span>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Club, venue or space"
          />
        </label>
        <label className="field" style={{ flex: "0 1 180px" }}>
          <span>Sport</span>
          <select value={sport} onChange={(e) => setSport(e.target.value)}>
            <option value="">Any</option>
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
        <p className="muted">Loading…</p>
      ) : rows.length === 0 ? (
        <p className="muted">
          No hireable spaces yet. Secretaries can mark a space as hireable from
          their club&apos;s venues.
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
                    : "General hire"}
                  {row.capacity != null ? ` · up to ${row.capacity}` : ""}
                  {row.requires_approval ? " · approval required" : " · instant"}
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
