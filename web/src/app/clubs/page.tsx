"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  errCode,
  getAccessToken,
  readErr,
  roleLabel,
  SPORTS,
  type Club,
  type VerificationStatus,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { PendingInvites } from "@/components/PendingInvites";
import { VerifyContact } from "@/components/VerifyContact";

/// `GET /clubs` returns each club with the role you hold in it.
type Membership = Club & { role: string };

export default function ClubsPage() {
  const [clubs, setClubs] = useState<Membership[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  // The getting-started guide links here as ?new=1: land with the form open,
  // not on a page that asks them to press "Start a club" a second time.
  const [creating, setCreating] = useState(false);
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get("new") === "1") setCreating(true);
  }, []);

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
      {/* With the form open this header is the form's own, so it does not
          offer "Start a club" to someone already starting one. */}
      <section className="hero hero-row">
        <div>
          <h1>{creating ? "Start a club" : "Clubs"}</h1>
          <p>
            {creating
              ? "It takes a minute. You run the club, so you can invite players the moment it exists."
              : "Your memberships and what each role lets you do."}
          </p>
        </div>
        {!error && !creating && (
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

      {creating && clubs.length > 0 && <h2 className="section-head">Your clubs</h2>}
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

      <PendingInvites onJoined={load} />

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
  // Set when the server refuses because the account is not confirmed yet: the
  // code goes in right here, then the same club is created without retyping.
  const [verify, setVerify] = useState<VerificationStatus | null>(null);

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
      if (errCode(err) === "unverified") {
        setVerify(await api<VerificationStatus>("GET", "/me/verification").catch(() => null));
      }
      setError(readErr(err, "Could not create the club"));
    } finally {
      setBusy(false);
    }
  };

  const trimmed = name.trim();
  // Said out loud rather than left as a greyed-out button nobody can explain.
  const missing =
    trimmed.length < 2 ? "Give the club a name to continue." : sports.length === 0 ? "Pick at least one sport." : null;
  const initials = trimmed
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  return (
    <div className="cc">
      <form
        className="panel cc-form"
        onSubmit={(e) => {
          e.preventDefault();
          if (!missing && !busy && !verify) submit();
        }}
      >
        <div className="cc-field">
          <label className="cc-label" htmlFor="cc-name">
            <span className="cc-num" aria-hidden="true">1</span> Club name
          </label>
          <input
            id="cc-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Fishers CC"
            maxLength={160}
            autoComplete="off"
            aria-describedby="cc-name-help"
            autoFocus
          />
          <p className="cc-help" id="cc-name-help">How your players and the clubs you play will see you.</p>
        </div>

        <fieldset className="cc-field">
          <legend className="cc-label">
            <span className="cc-num" aria-hidden="true">2</span> Sports played
          </legend>
          <div className="cc-chips">
            {SPORTS.map((s) => {
              const on = sports.includes(s);
              return (
                <button
                  key={s}
                  type="button"
                  className={`chip${on ? " on" : ""}`}
                  aria-pressed={on}
                  onClick={() => toggle(s)}
                >
                  {on && <Icon name="check" size={14} />}
                  {s}
                </button>
              );
            })}
          </div>
          <p className="cc-help">Pick every one you play — teams are set up per sport inside the club.</p>
        </fieldset>

        <fieldset className="cc-field">
          <legend className="cc-label">
            <span className="cc-num" aria-hidden="true">3</span> Who can find it
          </legend>
          <div className="cc-options">
            {VISIBILITY.map((o) => {
              const on = visibility === o.value;
              return (
                <label key={o.value} className={`cc-option${on ? " on" : ""}`}>
                  <input
                    type="radio"
                    name="visibility"
                    value={o.value}
                    checked={on}
                    onChange={() => setVisibility(o.value)}
                  />
                  <span className="cc-option-icon"><Icon name={o.icon} size={18} /></span>
                  <span className="cc-option-body">
                    <span className="cc-option-title">{o.title}</span>
                    <span className="cc-option-text">{o.text}</span>
                  </span>
                  <span className="cc-option-tick"><Icon name="check" size={12} /></span>
                </label>
              );
            })}
          </div>
        </fieldset>

        <div className="cc-field">
          <label className="cc-label" htmlFor="cc-about">
            <span className="cc-num" aria-hidden="true">4</span> Description
            <span className="cc-optional">Optional</span>
          </label>
          <textarea
            id="cc-about"
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Sunday friendlies, Hemel Hempstead"
            aria-describedby="cc-about-help"
          />
          <p className="cc-help" id="cc-about-help">Where and when you play. It shows on the club card.</p>
        </div>

        {verify ? (
          <div className="verify-gate">
            <p className="verify-gate-title">
              <Icon name="shield" size={16} /> One thing first — confirm it&apos;s you
            </p>
            <VerifyContact
              status={verify}
              compact
              onVerified={() => {
                setVerify(null);
                setError(null);
                submit(); // the club they already filled in
              }}
            />
          </div>
        ) : (
          error && <p className="error" role="alert">{error}</p>
        )}

        <div className="cc-actions">
          <p className="cc-hint" aria-live="polite">
            <Icon name={missing ? "help" : "shield"} size={16} />
            {missing ?? "You become its secretary, so you can add members straight away."}
          </p>
          <div className="cc-buttons">
            <button className="btn ghost" type="button" onClick={onClose}>Cancel</button>
            <button className="btn primary" type="submit" disabled={busy || !!verify || !!missing}>
              {busy ? "Creating…" : "Create club"}
            </button>
          </div>
        </div>
      </form>

      <aside className="cc-aside">
        {/* A mirror of the form, so it is hidden from screen readers. */}
        <div className="panel cc-preview" aria-hidden="true">
          <p className="section-head">Preview</p>
          <div className="cc-card">
            <div className="cc-card-top">
              <span className="cc-crest">{initials || <Icon name="users" size={22} />}</span>
              <div>
                <p className={`cc-card-name${trimmed ? "" : " placeholder"}`}>{trimmed || "Your club"}</p>
                <p className="cc-card-meta">
                  <Icon name={visibility === "public" ? "users" : "lock"} size={12} />
                  {VISIBILITY.find((o) => o.value === visibility)?.title}
                </p>
              </div>
            </div>
            <div className="cc-card-tags">
              {sports.map((s) => <span className="tag" key={s}>{s}</span>)}
              <span className="tag gold">Secretary</span>
            </div>
            {description.trim() && <p className="cc-card-desc">{description.trim()}</p>}
          </div>
        </div>

        <div className="panel">
          <h2 className="section-head">What happens next</h2>
          <ol className="guide-steps cc-steps">
            {NEXT_STEPS.map(([title, text], i) => (
              <li key={title}>
                <span className="guide-num">{i + 1}</span>
                <div>
                  <strong>{title}</strong>
                  <p>{text}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </aside>
    </div>
  );
}

const VISIBILITY = [
  {
    value: "invite_only",
    icon: "lock",
    title: "Invite only",
    text: "Kept out of search. Players join with your invite link or club code.",
  },
  {
    value: "public",
    icon: "users",
    title: "Anyone can find it",
    text: "Other clubs can find you by name when they arrange a match.",
  },
] as const;

const NEXT_STEPS = [
  ["Invite your players", "Share the club link or QR code from the club page."],
  ["Schedule a fixture", "Players say whether they can play; the captain picks the side."],
  ["Score it live", "Ball by ball — and hand the book over at the innings break."],
] as const;
