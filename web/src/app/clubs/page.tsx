"use client";

import { useEffect, useState } from "react";
import { api, getAccessToken, type Club } from "@/lib/api";
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
