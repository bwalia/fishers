"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  api,
  errCode,
  getAccessToken,
  getStoredUser,
  readErr,
  roleLabel,
  SPORTS,
  type Club,
  type PublicUser,
  type VerificationStatus,
} from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { PendingInvites } from "@/components/PendingInvites";
import { ShareProfile } from "@/components/ShareProfile";
import { VerifyContact } from "@/components/VerifyContact";
import { copyText } from "@/lib/clipboard";

/// `GET /clubs` returns each club with the role you hold in it.
type Membership = Club & {
  role: string;
  member_count?: number;
  team_count?: number;
  /// Set only when the club has published its public page.
  public_slug?: string | null;
};

export default function ClubsPage() {
  const router = useRouter();
  const [clubs, setClubs] = useState<Membership[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [me, setMe] = useState<PublicUser | null>(null);
  // The getting-started guide links here as ?new=1: land with the form open,
  // not on a page that asks them to press "Start a club" a second time.
  const [creating, setCreating] = useState(false);
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get("new") === "1") setCreating(true);
    setMe(getStoredUser());
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

  // Somebody in several clubs finds one by name rather than by scrolling.
  const [query, setQuery] = useState("");
  const term = query.trim().toLowerCase();
  const shown = term
    ? clubs.filter((c) => `${c.name} ${c.description ?? ""} ${c.sport_types.join(" ")}`.toLowerCase().includes(term))
    : clubs;

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
              : "Your clubs, and what your role lets you do in each."}
          </p>
        </div>
        {!error && !creating && (
          <button className="btn primary" type="button" onClick={() => setCreating(true)}>
            <Icon name="plus" size={16} /> Start a club
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}

      {creating && (
        <CreateClub
          onClose={() => setCreating(false)}
          // Straight to the new club: adding players happens there, not here.
          onCreated={(club) => router.push(`/clubs/${club.id}?welcome=1`)}
        />
      )}

      <PendingInvites onJoined={load} />

      {loading && (
        <div className="cl-grid" aria-hidden="true">
          {[0, 1, 2].map((i) => <div key={i} className="skeleton cl-skeleton" />)}
        </div>
      )}

      <div className={creating || clubs.length === 0 ? undefined : "cl-layout"}>
      <div className="cl-main">
      {clubs.length > 0 && (
        <div className="cl-bar">
          <h2 className="section-head">
            {creating ? "Your clubs" : `${clubs.length} ${clubs.length === 1 ? "club" : "clubs"}`}
          </h2>
          {clubs.length > 4 && (
            <label className="cl-search">
              <span className="sr-only">Find a club</span>
              <input
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Find a club"
              />
            </label>
          )}
        </div>
      )}
      {clubs.length > 0 && (
        <div className="cl-grid">
          {shown.map((c) => <ClubCard key={c.id} club={c} />)}
          {shown.length === 0 && <p className="muted">No club matches “{query.trim()}”.</p>}
        </div>
      )}
      </div>

      {!creating && clubs.length > 0 && <ClubsSidebar me={me} clubs={clubs} />}
      </div>

      {!loading && !error && clubs.length === 0 && !creating && (
        <section className="panel cl-empty" aria-labelledby="cl-empty-title">
          <span className="cl-empty-icon"><Icon name="users" size={28} /></span>
          <h2 id="cl-empty-title">You&apos;re not in a club yet</h2>
          <p className="muted">Start your own, or get invited into the one you play for.</p>
          <div className="cl-paths">
            <div className="cl-path">
              <h3><Icon name="shield" size={18} /> I run a club</h3>
              <p>Set it up in a minute. You become its secretary and can add players straight away.</p>
              <button className="btn primary" type="button" onClick={() => setCreating(true)}>
                <Icon name="plus" size={16} /> Start a club
              </button>
            </div>
            <div className="cl-path">
              <h3><Icon name="ball" size={18} /> I play for a club</h3>
              <p>Send your profile link to the secretary. Their invite appears here to accept.</p>
              {me && <ShareProfile userId={me.id} />}
            </div>
          </div>
        </section>
      )}
    </main>
  );
}

/// Beside the list: your own profile link, each club's public page, and how
/// a club fits together — the things people otherwise go hunting for.
function ClubsSidebar({ me, clubs }: { me: PublicUser | null; clubs: Membership[] }) {
  const [copied, setCopied] = useState<string | null>(null);
  const copy = async (slug: string) => {
    if (await copyText(`${window.location.origin}/c/${slug}`)) {
      setCopied(slug);
      setTimeout(() => setCopied(null), 2000);
    }
  };

  return (
    <aside className="cl-side" aria-label="Profile, public pages and how clubs work">
      {me && (
        <section className="panel cl-side-card" aria-labelledby="cl-me">
          <h2 id="cl-me" className="section-head">Your player profile</h2>
          <div className="cl-me">
            <Avatar name={me.name} url={me.avatar_url} size={44} />
            <div>
              <strong>{me.name}</strong>
              <Link href="/profile">Edit profile</Link>
            </div>
          </div>
          <p className="muted">
            Send this link to a club&apos;s secretary and they can invite you straight from it.
          </p>
          <ShareProfile userId={me.id} />
        </section>
      )}

      <section className="panel cl-side-card" aria-labelledby="cl-pages">
        <h2 id="cl-pages" className="section-head">Club public pages</h2>
        <p className="muted">A page anyone can open, no login: your record, top players and next fixtures.</p>
        <ul className="cl-pages">
          {clubs.map((c) => {
            const secretary = c.role === "club_admin" || c.role === "super_admin";
            return (
              <li key={c.id}>
                <span className={`cc-crest sm tone-${tone(c.id)}`} aria-hidden="true">{initials(c.name)}</span>
                <span className="cl-pages-name">
                  <strong>{c.name}</strong>
                  <span className="subtle" title={c.public_slug ? `/c/${c.public_slug}` : undefined}>
                    {c.public_slug ? `/c/${c.public_slug}` : "Not published"}
                  </span>
                </span>
                {c.public_slug ? (
                  <span className="cl-pages-actions">
                    <button
                      className="btn ghost sm icon-only"
                      type="button"
                      onClick={() => copy(c.public_slug!)}
                      aria-label={`Copy the link to ${c.name}'s public page`}
                    >
                      <Icon name={copied === c.public_slug ? "check" : "copy"} size={16} />
                    </button>
                    <a
                      className="btn ghost sm"
                      href={`/c/${c.public_slug}`}
                      target="_blank"
                      rel="noreferrer"
                      aria-label={`View ${c.name}'s public page (opens in a new tab)`}
                    >
                      View
                    </a>
                  </span>
                ) : (
                  secretary && (
                    <Link className="btn sm" href={`/clubs/${c.id}#public-page`} aria-label={`Set up ${c.name}'s public page`}>
                      Set up
                    </Link>
                  )
                )}
              </li>
            );
          })}
        </ul>
      </section>

      <section className="panel cl-side-card" aria-labelledby="cl-how">
        <h2 id="cl-how" className="section-head">How clubs work</h2>
        <ol className="guide-steps cc-steps">
          {HOW_CLUBS_WORK.map(([title, text], i) => (
            <li key={title}>
              <span className="guide-num">{i + 1}</span>
              <div>
                <strong>{title}</strong>
                <p>{text}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>
    </aside>
  );
}

const HOW_CLUBS_WORK = [
  ["A secretary runs the club", "Members and their roles, teams, grounds, fixtures and fees."],
  ["Players join by invite", "Added by email or mobile, or from their profile link — then accepted on this page."],
  ["Captains pick the side", "Everyone says whether they can play; the captain picks from who is available."],
  ["Matches are scored live", "Ball by ball. Stats and the club's public page keep themselves up to date."],
] as const;

/// The whole card is the link, so the list reads as places to go.
function ClubCard({ club }: { club: Membership }) {
  const open = club.visibility === "public";
  return (
    <Link className="club-card cl-card" href={`/clubs/${club.id}`}>
      <div className="cl-card-top">
        <span className={`cc-crest tone-${tone(club.id)}`} aria-hidden="true">{initials(club.name)}</span>
        <div className="cl-card-title">
          <h2>{club.name}</h2>
          <p className="cl-card-meta">
            <Icon name={open ? "users" : "lock"} size={12} />
            {open ? "Anyone can find it" : "Invite only"}
          </p>
        </div>
        <span className="tag gold">{roleLabel(club.role)}</span>
      </div>
      <p className={`cl-card-desc${club.description ? "" : " none"}`}>
        {club.description || "No description yet."}
      </p>
      <div className="cl-card-tags">
        {club.sport_types.map((s) => <span className="tag" key={s}>{s}</span>)}
      </div>
      <div className="cl-card-foot">
        {club.member_count !== undefined && (
          <span><Icon name="users" size={14} /> {plural(club.member_count, "member")}</span>
        )}
        {club.team_count !== undefined && (
          <span><Icon name="shield" size={14} /> {plural(club.team_count, "team")}</span>
        )}
        <span className="cl-card-open">Open <Icon name="arrowLeft" size={14} className="flip" /></span>
      </div>
    </Link>
  );
}

/// One of three crest colours, fixed per club, so a long list is not a wall of
/// identical squares.
const tone = (id: string) => parseInt(id.replace(/-/g, "").slice(-2), 16) % 3;

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

const initials = (name: string) =>
  name
    .trim()
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

/// Whoever creates the club is its first secretary, so this is also how a new
/// account gets somewhere to add people to.
function CreateClub({ onClose, onCreated }: { onClose: () => void; onCreated: (club: Club) => void }) {
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
      const club = await api<Club>("POST", "/clubs", {
        name: name.trim(),
        sport_types: sports,
        visibility,
        description: description.trim() || null,
      });
      onCreated(club);
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
              <span className="cc-crest">{initials(trimmed) || <Icon name="users" size={22} />}</span>
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
