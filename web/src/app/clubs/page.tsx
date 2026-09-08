"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, roleLabel, SPORTS, type Club } from "@/lib/api";
import { Icon } from "@/components/Icon";

/// `GET /clubs` returns each club with the role you hold in it.
type Membership = Club & { role: string };

export default function ClubsPage() {
  const [clubs, setClubs] = useState<Membership[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);

  const load = async () => {
    try {
      setClubs(await api<Membership[]>("GET", "/clubs"));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to view clubs.");
      setLoading(false);
      return;
    }
    load();
  }, []);

  return (
    <main id="main">
      <section className="hero">
        <h1>Clubs</h1>
        <p>Your memberships and what each role lets you do.</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setCreating(true)}>
            <Icon name="plus" size={16} /> Start a club
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}
      {loading && <div className="panel"><div className="skeleton" style={{ height: 64 }} /></div>}

      {creating && (
        <CreateClub
          onClose={() => setCreating(false)}
          onCreated={() => {
            setCreating(false);
            load();
          }}
        />
      )}

      <div className="grid">
        {clubs.map((c) => (
          <Link className="panel club-card" key={c.id} href={`/clubs/${c.id}`}>
            <div className="panel-head">
              <h2>{c.name}</h2>
            </div>
            <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap" }}>
              {c.sport_types.map((s) => <span className="tag" key={s}>{s}</span>)}
            </div>
            {c.description && <p className="muted">{c.description}</p>}
            <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap", marginTop: "var(--s2)" }}>
              <span className="tag gold">{roleLabel(c.role)}</span>
            </div>
          </Link>
        ))}
      </div>

      {!loading && !error && clubs.length === 0 && !creating && (
        <div className="panel">
          <div className="empty">
            <Icon name="users" size={28} />
            <p>You are not a member of any club yet.</p>
            <button className="btn primary" type="button" onClick={() => setCreating(true)}>
              Start one
            </button>
          </div>
        </div>
      )}
    </main>
  );
}

/// Whoever creates the club is its first secretary, so this is also how a new
/// account gets somewhere to add people to.
function CreateClub({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [name, setName] = useState("");
  const [sports, setSports] = useState<string[]>(["cricket"]);
  const [description, setDescription] = useState("");
  const [visibility, setVisibility] = useState("invite_only");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = (sport: string) =>
    setSports((current) =>
      current.includes(sport) ? current.filter((s) => s !== sport) : [...current, sport]
    );

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      await api<Club>("POST", "/clubs", {
        name: name.trim(),
        sport_types: sports,
        visibility,
        description: description.trim() || null,
      });
      onCreated();
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      try {
        setError(JSON.parse(raw).error ?? "Could not create the club");
      } catch {
        setError(raw || "Could not create the club");
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <div className="panel-head">
        <h2>Start a club</h2>
        <button className="btn ghost sm" type="button" onClick={onClose}>Cancel</button>
      </div>

      <label>
        Club name
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Fishers CC"
          autoFocus
        />
      </label>

      <fieldset className="chip-set">
        <legend>Sports played</legend>
        {SPORTS.map((s) => (
          <button
            key={s}
            type="button"
            className={`chip${sports.includes(s) ? " on" : ""}`}
            aria-pressed={sports.includes(s)}
            onClick={() => toggle(s)}
          >
            {s}
          </button>
        ))}
      </fieldset>

      <label>
        Who can find it
        <select value={visibility} onChange={(e) => setVisibility(e.target.value)}>
          <option value="invite_only">Invite only</option>
          <option value="public">Anyone can find it</option>
        </select>
      </label>

      <label>
        Description
        <input
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Sunday friendlies, Hemel Hempstead"
        />
      </label>

      {error && <p className="error">{error}</p>}

      <button
        className="btn primary"
        type="button"
        disabled={busy || name.trim().length < 2 || sports.length === 0}
        onClick={submit}
      >
        {busy ? "Creating…" : "Create club"}
      </button>
      <p className="subtle">You become its secretary, so you can add members straight away.</p>
    </div>
  );
}
