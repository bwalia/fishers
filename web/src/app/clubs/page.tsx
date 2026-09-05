"use client";

import { useEffect, useState } from "react";
import { api, getAccessToken, type Club } from "@/lib/api";

type RoleInfo = {
  role: string;
  display_name: string;
  can_invite_to_play?: boolean;
  can_score_match?: boolean;
};

export default function ClubsPage() {
  const [clubs, setClubs] = useState<Club[]>([]);
  const [roles, setRoles] = useState<Record<string, RoleInfo>>({});
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view clubs.");
      return;
    }
    (async () => {
      try {
        const list = await api<Club[]>("GET", "/clubs");
        setClubs(list);
        const entries = await Promise.all(
          list.map(async (c) => {
            try {
              const role = await api<RoleInfo>("GET", `/clubs/${c.id}/my-role`);
              return [c.id, role] as const;
            } catch {
              return [c.id, { role: "member", display_name: "Member" }] as const;
            }
          })
        );
        setRoles(Object.fromEntries(entries));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load");
      }
    })();
  }, []);

  return (
    <main>
      <section className="hero">
        <h1>Clubs</h1>
        <p>Memberships and your role in each club.</p>
      </section>
      {error && <p className="error">{error}</p>}
      <div className="grid cards">
        {clubs.map((c) => {
          const role = roles[c.id];
          return (
            <article key={c.id} className="panel">
              <h2>{c.name}</h2>
              <p className="tag">{(c.sport_types || []).join(" · ") || "club"}</p>
              {c.description && <p className="muted">{c.description}</p>}
              {role && (
                <p style={{ marginTop: 12 }}>
                  {role.display_name}
                  {role.can_score_match ? " · can score" : ""}
                  {role.can_invite_to_play ? " · can invite" : ""}
                </p>
              )}
            </article>
          );
        })}
      </div>
    </main>
  );
}
