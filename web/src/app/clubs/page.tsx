"use client";

import { useEffect, useState } from "react";
import { api, getAccessToken, type Club, type QrCode, type Team } from "@/lib/api";
import { QrCard } from "@/components/QrCard";
import { Icon } from "@/components/Icon";

type Membership = Club & {
  role?: string | null;
  can_score?: boolean;
  can_invite?: boolean;
};

export default function ClubsPage() {
  const [clubs, setClubs] = useState<Membership[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view clubs.");
      setLoading(false);
      return;
    }
    (async () => {
      try {
        setClubs(await api<Membership[]>("GET", "/clubs"));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  return (
    <main id="main">
      <section className="hero">
        <h1>Clubs</h1>
        <p>Your memberships and what each role lets you do.</p>
      </section>

      {error && <p className="error">{error}</p>}
      {loading && <div className="panel"><div className="skeleton" style={{ height: 64 }} /></div>}

      <div className="grid">
        {clubs.map((c) => (
          <div className="panel" key={c.id} style={{ marginBottom: 0 }}>
            <div className="panel-head">
              <h2>{c.name}</h2>
            </div>
            <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap" }}>
              {c.sport_types.map((s) => <span className="tag" key={s}>{s}</span>)}
            </div>
            {c.description && <p className="muted">{c.description}</p>}
            <ClubCodes clubId={c.id} />
            <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap", marginTop: "var(--s2)" }}>
              {c.role && <span className="tag gold">{c.role.replaceAll("_", " ")}</span>}
              {c.can_score && (
                <span className="tag grey"><Icon name="check" size={12} /> can score</span>
              )}
              {c.can_invite && (
                <span className="tag grey"><Icon name="check" size={12} /> can invite</span>
              )}
            </div>
          </div>
        ))}
      </div>

      {!loading && !error && clubs.length === 0 && (
        <div className="panel">
          <div className="empty">
            <Icon name="users" size={28} />
            <p>You are not a member of any club yet.</p>
          </div>
        </div>
      )}
    </main>
  );
}

/// The club's own code, and one per team — what you show an opposition captain
/// so they can find you without anybody typing a name.
function ClubCodes({ clubId }: { clubId: string }) {
  const [codes, setCodes] = useState<QrCode[]>([]);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open || codes.length > 0) return;
    (async () => {
      const found: QrCode[] = [];
      try {
        found.push(await api<QrCode>("GET", `/clubs/${clubId}/qr`));
      } catch {
        // A club with no code yet simply has none to show.
      }
      try {
        const teams = await api<Team[]>("GET", `/clubs/${clubId}/teams`);
        for (const team of teams) {
          try {
            found.push(await api<QrCode>("GET", `/teams/${team.id}/qr`));
          } catch {
            // Likewise per team.
          }
        }
      } catch {
        // No teams is normal.
      }
      setCodes(found);
    })();
  }, [open, clubId, codes.length]);

  return (
    <div style={{ marginTop: "var(--s3)" }}>
      <button className="btn sm ghost" type="button" onClick={() => setOpen((v) => !v)}>
        {open ? "Hide codes" : "Show our QR codes"}
      </button>
      {open && (
        <div className="qr-grid">
          {codes.map((qr) => (
            <QrCard key={`${qr.kind}-${qr.id}`} qr={qr} />
          ))}
          {codes.length === 0 && <p className="muted">No codes yet.</p>}
        </div>
      )}
    </div>
  );
}
