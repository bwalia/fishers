"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  saveUser,
  skillLabel,
  SKILL_LEVELS,
  SPORTS,
  SPORT_POSITIONS,
  type PublicUser,
  type SportProfile,
} from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Everything the app knows about you, in one place.
///
/// Deliberately not a cricket page: the profile is a list of sports, each with
/// its own position, standard and numbers. Cricket happens to have a scoring
/// engine behind it so its stats are computed; the rest are what the player
/// tells us, and both render through the same card.
export default function ProfilePage() {
  const [me, setMe] = useState<PublicUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const user = await api<PublicUser>("GET", "/me");
      setMe(user);
      // The nav reads the cached copy, so keep it honest after an edit.
      saveUser(user);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load your profile");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see your profile.");
      setLoading(false);
      return;
    }
    load();
  }, [load]);

  if (error) return <main id="main"><p className="error">{error}</p></main>;
  if (loading || !me)
    return <main id="main"><div className="panel"><div className="skeleton" style={{ height: 120 }} /></div></main>;

  const profiles = me.sport_profiles ?? [];

  return (
    <main id="main">
      <section className="hero">
        <h1>{me.name}</h1>
        <p>{me.email || me.phone || "No contact details yet"}</p>
        <div className="hero-tags">
          {me.primary_sport && <span className="tag gold">{me.primary_sport}</span>}
          {profiles
            .filter((p) => p.sport !== me.primary_sport)
            .map((p) => <span className="tag" key={p.sport}>{p.sport}</span>)}
        </div>
      </section>

      <Details me={me} onSaved={load} />

      <div className="panel">
        <div className="panel-head">
          <h2>Sports you play</h2>
          <span className="tag grey">{profiles.length}</span>
        </div>
        <p className="muted">
          One card per sport. Each keeps its own position, standard and numbers, so
          adding a sport never disturbs the others.
        </p>
        {profiles.length === 0 && (
          <div className="empty">
            <Icon name="bat" size={28} />
            <p>No sports set up yet. Add the one you play most.</p>
          </div>
        )}
        {profiles.map((p) => (
          <SportCard
            key={p.sport}
            profile={p}
            isPrimary={p.sport === me.primary_sport}
            me={me}
            onSaved={load}
          />
        ))}
        <AddSport me={me} onSaved={load} />
      </div>

      <div className="panel">
        <h2>Your numbers</h2>
        <p className="muted">
          Cricket is scored ball by ball, so those are worked out from the matches you
          played rather than typed in.
        </p>
        <Link className="btn" href="/stats">
          <Icon name="chart" size={16} /> Season stats
        </Link>
      </div>
    </main>
  );
}

function Details({ me, onSaved }: { me: PublicUser; onSaved: () => void }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(me.name);
  const [phone, setPhone] = useState(me.phone ?? "");
  const [emergency, setEmergency] = useState(me.emergency_contact ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("PATCH", "/me", {
        name: name.trim(),
        phone: phone.trim() || null,
        emergency_contact: emergency.trim() || null,
      });
      setEditing(false);
      onSaved();
    } catch (err) {
      setError(readError(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  if (!editing) {
    return (
      <div className="panel">
        <div className="panel-head">
          <h2>Your details</h2>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            Edit
          </button>
        </div>
        <dl className="terms-summary">
          <div><dt>Name</dt><dd>{me.name}</dd></div>
          <div><dt>Mobile</dt><dd>{me.phone || "—"}</dd></div>
          <div><dt>In an emergency</dt><dd>{me.emergency_contact || "—"}</dd></div>
        </dl>
      </div>
    );
  }

  return (
    <div className="panel">
      <h2>Your details</h2>
      <div className="setup-fields">
        <label>
          Name
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          Mobile
          <input
            type="tel"
            inputMode="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="07700 900123"
          />
        </label>
        <label>
          In an emergency
          <input
            value={emergency}
            onChange={(e) => setEmergency(e.target.value)}
            placeholder="Name and number"
          />
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button className="btn primary" type="button" disabled={busy || !name.trim()} onClick={save}>
          {busy ? "Saving…" : "Save"}
        </button>
        <button className="btn" type="button" onClick={() => setEditing(false)}>Cancel</button>
      </div>
    </div>
  );
}

function SportCard({
  profile,
  isPrimary,
  me,
  onSaved,
}: {
  profile: SportProfile;
  isPrimary: boolean;
  me: PublicUser;
  onSaved: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<SportProfile>(profile);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const positions = SPORT_POSITIONS[profile.sport] ?? [];

  const write = async (profiles: SportProfile[], primary?: string) => {
    setBusy(true);
    setError(null);
    try {
      await api("PATCH", "/me", {
        sport_profiles: profiles,
        ...(primary ? { primary_sport: primary } : {}),
      });
      setEditing(false);
      onSaved();
    } catch (err) {
      setError(readError(err, "Could not save that"));
    } finally {
      setBusy(false);
    }
  };

  const others = (me.sport_profiles ?? []).filter((p) => p.sport !== profile.sport);

  if (!editing) {
    return (
      <div className="sport-card">
        <div className="sheet-head">
          <h3>
            {titleOf(profile.sport)}
            {isPrimary && <span className="tag gold">Main sport</span>}
          </h3>
          <button className="btn ghost sm" type="button" onClick={() => setEditing(true)}>
            Edit
          </button>
        </div>
        <dl className="terms-summary">
          <div><dt>Position</dt><dd>{profile.position || "—"}</dd></div>
          <div><dt>Standard</dt><dd>{skillLabel(profile.skill_level)}</dd></div>
          {profile.team_name && <div><dt>Team</dt><dd>{profile.team_name}</dd></div>}
          {profile.years_playing != null && (
            <div><dt>Playing for</dt><dd className="num">{profile.years_playing} years</dd></div>
          )}
          {/* Whatever this sport measures, shown as it was stored. */}
          {Object.entries(profile.stats ?? {}).map(([k, v]) => (
            <div key={k}><dt>{k.replaceAll("_", " ")}</dt><dd className="num">{v}</dd></div>
          ))}
        </dl>
      </div>
    );
  }

  return (
    <div className="sport-card">
      <h3>{titleOf(profile.sport)}</h3>
      <div className="setup-fields">
        <label>
          Position
          {positions.length > 0 ? (
            <select
              value={draft.position ?? ""}
              onChange={(e) => setDraft({ ...draft, position: e.target.value })}
            >
              <option value="">—</option>
              {positions.map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          ) : (
            <input
              value={draft.position ?? ""}
              onChange={(e) => setDraft({ ...draft, position: e.target.value })}
              placeholder="However you'd describe it"
            />
          )}
        </label>
        <label>
          Standard
          <select
            value={draft.skill_level ?? ""}
            onChange={(e) => setDraft({ ...draft, skill_level: e.target.value })}
          >
            <option value="">—</option>
            {SKILL_LEVELS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
        </label>
        <label>
          Team
          <input
            value={draft.team_name ?? ""}
            onChange={(e) => setDraft({ ...draft, team_name: e.target.value })}
            placeholder="1st XI"
          />
        </label>
        <label>
          Years playing
          <input
            type="number"
            inputMode="numeric"
            value={draft.years_playing ?? ""}
            onChange={(e) =>
              setDraft({
                ...draft,
                years_playing: e.target.value === "" ? null : Number(e.target.value),
              })
            }
          />
        </label>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button
          className="btn primary"
          type="button"
          disabled={busy}
          onClick={() => write([...others, draft])}
        >
          {busy ? "Saving…" : "Save"}
        </button>
        {!isPrimary && (
          <button
            className="btn"
            type="button"
            disabled={busy}
            onClick={() => write([...others, draft], profile.sport)}
          >
            Save and make it my main sport
          </button>
        )}
        <button className="btn ghost" type="button" onClick={() => setEditing(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}

function AddSport({ me, onSaved }: { me: PublicUser; onSaved: () => void }) {
  const existing = (me.sport_profiles ?? []).map((p) => p.sport);
  const spare = SPORTS.filter((s) => !existing.includes(s));
  const [busy, setBusy] = useState(false);

  if (spare.length === 0) return null;

  const add = async (sport: string) => {
    setBusy(true);
    try {
      await api("PATCH", "/me", {
        sport_profiles: [...(me.sport_profiles ?? []), { sport }],
        // The first sport somebody adds is the one they lead with.
        ...(me.primary_sport ? {} : { primary_sport: sport }),
      });
      onSaved();
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <h3 className="sheet-sub">Add a sport</h3>
      <div className="squad-grid">
        {spare.map((s) => (
          <button
            key={s}
            type="button"
            className="squad-chip"
            disabled={busy}
            onClick={() => add(s)}
          >
            <Icon name="plus" size={14} />
            <span>{titleOf(s)}</span>
          </button>
        ))}
      </div>
    </>
  );
}

function titleOf(sport: string) {
  return sport.charAt(0).toUpperCase() + sport.slice(1);
}

function readError(err: unknown, fallback: string): string {
  const raw = err instanceof Error ? err.message : "";
  try {
    return JSON.parse(raw).error ?? fallback;
  } catch {
    return raw || fallback;
  }
}
