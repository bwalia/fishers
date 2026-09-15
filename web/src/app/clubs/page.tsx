"use client";

import { useCallback, useEffect, useRef, useState } from "react";
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
  type Page,
  type PublicUser,
  type VerificationStatus,
} from "@/lib/api";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";
import { PendingInvites } from "@/components/PendingInvites";
import { ShareProfile } from "@/components/ShareProfile";
import { VerifyContact } from "@/components/VerifyContact";
import { copyText } from "@/lib/clipboard";

/// `GET /me/clubs` returns each club with the role you hold in it.
type Membership = Club & {
  role: string;
  /// Captains the side — by role, or a secretary who captains too.
  is_captain?: boolean;
  member_count: number;
  team_count: number;
  /// Set only when the club has published its public page.
  public_slug?: string | null;
};

type Filters = {
  q: string;
  role: string;
  sport: string;
  /// "yes", "no" or "" for either.
  published: string;
  sort: string;
  page: number;
};

const NO_FILTERS: Filters = { q: "", role: "", sport: "", published: "", sort: "name", page: 1 };
const PER_PAGE = 20;

const ROLE_FILTERS = [
  ["secretary", "Secretary"],
  ["captain", "Captain"],
  ["vice_captain", "Vice captain"],
  ["member", "Member"],
] as const;

/// The filters as the address bar carries them, so back, refresh and a
/// shared link all land on the same view.
function toParams(f: Filters) {
  const p = new URLSearchParams();
  if (f.q) p.set("q", f.q);
  if (f.role) p.set("role", f.role);
  if (f.sport) p.set("sport", f.sport);
  if (f.published) p.set("published", f.published);
  if (f.sort !== "name") p.set("sort", f.sort);
  if (f.page > 1) p.set("page", String(f.page));
  return p;
}

function fromParams(p: URLSearchParams): Filters {
  const page = Number(p.get("page"));
  return {
    q: p.get("q") ?? "",
    role: p.get("role") ?? "",
    sport: p.get("sport") ?? "",
    published: p.get("published") ?? "",
    sort: p.get("sort") ?? "name",
    page: Number.isInteger(page) && page > 1 ? page : 1,
  };
}

function apiPath(f: Filters) {
  const p = new URLSearchParams({ sort: f.sort, page: String(f.page), per_page: String(PER_PAGE) });
  if (f.q) p.set("q", f.q);
  if (f.role) p.set("role", f.role);
  if (f.sport) p.set("sport", f.sport);
  if (f.published) p.set("public_page", f.published === "yes" ? "true" : "false");
  return `/me/clubs?${p}`;
}

export default function ClubsPage() {
  const router = useRouter();
  const [me, setMe] = useState<PublicUser | null>(null);
  // The getting-started guide links here as ?new=1: land with the form open,
  // not on a page that asks them to press "Start a club" a second time.
  const [creating, setCreating] = useState(false);
  const [filters, setFilters] = useState<Filters>(NO_FILTERS);
  // What is typed, before it settles into `filters.q`.
  const [search, setSearch] = useState("");
  const [ready, setReady] = useState(false);
  const [result, setResult] = useState<Page<Membership> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const listTop = useRef<HTMLElement>(null);
  // Only the latest request may land: a slow answer to an old filter must
  // not overwrite the new one.
  const latest = useRef(0);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("new") === "1") setCreating(true);
    setMe(getStoredUser());
    const f = fromParams(params);
    setFilters(f);
    setSearch(f.q);
    setReady(true);
  }, []);

  // One request per pause in typing, not per keystroke.
  useEffect(() => {
    const t = setTimeout(() => {
      const q = search.trim();
      setFilters((f) => (f.q === q ? f : { ...f, q, page: 1 }));
    }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const load = useCallback(async () => {
    if (!getAccessToken()) {
      setError("Sign in to view clubs.");
      setLoading(false);
      return;
    }
    const mine = ++latest.current;
    setLoading(true);
    try {
      const page = await api<Page<Membership>>("GET", apiPath(filters));
      if (mine !== latest.current) return;
      setResult(page);
      setError(null);
    } catch (err) {
      if (mine === latest.current) setError(readErr(err, "Could not load your clubs"));
    } finally {
      if (mine === latest.current) setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    if (ready) load();
  }, [ready, load]);

  useEffect(() => {
    if (!ready || creating) return;
    const qs = toParams(filters).toString();
    window.history.replaceState(null, "", qs ? `/clubs?${qs}` : "/clubs");
  }, [filters, ready, creating]);

  const set = (patch: Partial<Filters>) => setFilters((f) => ({ ...f, ...patch, page: patch.page ?? 1 }));
  const goToPage = (page: number) => {
    set({ page });
    listTop.current?.scrollIntoView({ block: "start", behavior: "smooth" });
  };
  const clear = () => {
    setSearch("");
    setFilters((f) => ({ ...NO_FILTERS, sort: f.sort }));
  };

  const filtered = !!(filters.q || filters.role || filters.sport || filters.published);
  const total = result?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / PER_PAGE));
  // Nothing at all, as opposed to nothing matching: a different screen.
  const noClubs = !!result && total === 0 && !filtered;

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

      {!creating && <PendingInvites onJoined={load} />}

      {!creating && !noClubs && (
        <div className="cl-layout">
          <section className="panel cl-list" ref={listTop} aria-labelledby="cl-list-title">
            <div className="cl-list-head">
              <h2 id="cl-list-title">Your clubs</h2>
              <p className="subtle" aria-live="polite">
                {result && total > 0
                  ? `Showing ${(result.page - 1) * PER_PAGE + 1}–${(result.page - 1) * PER_PAGE + result.items.length} of ${total}`
                  : result && filtered
                    ? "No matches"
                    : ""}
              </p>
            </div>

            <div className="cl-filters" role="search" aria-label="Filter your clubs">
              <label className="cl-filter-search">
                <span className="sr-only">Search clubs</span>
                <Icon name="search" size={16} />
                <input
                  type="search"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search by name or description"
                  maxLength={100}
                />
              </label>
              <select aria-label="Your role" value={filters.role} onChange={(e) => set({ role: e.target.value })}>
                <option value="">All roles</option>
                {ROLE_FILTERS.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
              </select>
              <select aria-label="Sport" value={filters.sport} onChange={(e) => set({ sport: e.target.value })}>
                <option value="">All sports</option>
                {SPORTS.map((s) => <option key={s} value={s}>{s[0].toUpperCase() + s.slice(1)}</option>)}
              </select>
              <select aria-label="Public page" value={filters.published} onChange={(e) => set({ published: e.target.value })}>
                <option value="">Any public page</option>
                <option value="yes">Page published</option>
                <option value="no">No public page</option>
              </select>
              <select aria-label="Sort by" value={filters.sort} onChange={(e) => set({ sort: e.target.value })}>
                <option value="name">Name A–Z</option>
                <option value="recent">Recently joined</option>
                <option value="members">Most members</option>
              </select>
              {filtered && (
                <button className="btn ghost sm" type="button" onClick={clear}>
                  Clear filters
                </button>
              )}
            </div>

            <div className="cl-cols" aria-hidden="true">
              <span>Club</span>
              <span>Your role</span>
              <span>Members</span>
              <span>Teams</span>
              <span>Public page</span>
            </div>

            {!result ? (
              <ul className="cl-rows" aria-hidden="true">
                {[0, 1, 2, 3].map((i) => <li key={i} className="cl-row"><div className="skeleton cl-row-skeleton" /></li>)}
              </ul>
            ) : result.items.length > 0 ? (
              <ul className={`cl-rows${loading ? " is-loading" : ""}`} aria-busy={loading}>
                {result.items.map((c) => <ClubRow key={c.id} club={c} />)}
              </ul>
            ) : (
              <div className="empty">
                <Icon name="search" size={28} />
                <p>No clubs match these filters.</p>
                <button className="btn" type="button" onClick={clear}>Clear filters</button>
              </div>
            )}

            {pages > 1 && result && (
              <nav className="cl-pager" aria-label="Pages of clubs">
                <button className="btn sm" type="button" disabled={result.page <= 1 || loading} onClick={() => goToPage(result.page - 1)}>
                  <Icon name="arrowLeft" size={14} /> Previous
                </button>
                <span>
                  Page {result.page} of {pages}
                </span>
                <button className="btn sm" type="button" disabled={!result.has_more || loading} onClick={() => goToPage(result.page + 1)}>
                  Next <Icon name="arrowLeft" size={14} className="flip" />
                </button>
              </nav>
            )}
          </section>

          <ClubsSidebar me={me} onShowPublished={() => { setSearch(""); setFilters({ ...NO_FILTERS, published: "yes" }); }} />
        </div>
      )}

      {!creating && noClubs && (
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

/// One club as a row. The name is the link, stretched over the whole row, so
/// anywhere on it opens the club while the public-page button stays its own.
function ClubRow({ club }: { club: Membership }) {
  const secretary = club.role === "club_admin" || club.role === "super_admin";
  const open = club.visibility === "public";
  return (
    <li className="cl-row">
      <span className={`cc-crest sm tone-${tone(club.id)}`} aria-hidden="true">{initials(club.name)}</span>
      <div className="cl-row-main">
        <Link className="cl-row-link" href={`/clubs/${club.id}`}>
          {club.name}
        </Link>
        <p className="cl-row-meta">
          <span>
            <Icon name={open ? "users" : "lock"} size={12} /> {open ? "Anyone can find it" : "Invite only"}
          </span>
          <span className="cl-row-sports">{club.sport_types.join(" · ")}</span>
        </p>
        {club.description && <p className="cl-row-desc">{club.description}</p>}
      </div>
      <span className="cl-row-role">
        <span className="tag gold">{roleLabel(club.role, club.is_captain)}</span>
      </span>
      <span className="cl-row-stat">
        <strong>{club.member_count}</strong> <span>{club.member_count === 1 ? "member" : "members"}</span>
      </span>
      <span className="cl-row-stat">
        <strong>{club.team_count}</strong> <span>{club.team_count === 1 ? "team" : "teams"}</span>
      </span>
      <span className="cl-row-actions">
        {club.public_slug ? (
          <a
            className="btn ghost sm"
            href={`/c/${club.public_slug}`}
            target="_blank"
            rel="noreferrer"
            aria-label={`${club.name} public page (opens in a new tab)`}
          >
            <Icon name="share" size={14} /> View page
          </a>
        ) : secretary ? (
          <Link className="btn ghost sm" href={`/clubs/${club.id}#public-page`} aria-label={`Set up ${club.name}'s public page`}>
            <Icon name="plus" size={14} /> Set up
          </Link>
        ) : (
          <span className="subtle">Not published</span>
        )}
      </span>
    </li>
  );
}

/// Beside the list: your own profile link, your clubs' published pages, and
/// how a club fits together — the things people otherwise go hunting for.
function ClubsSidebar({ me, onShowPublished }: { me: PublicUser | null; onShowPublished: () => void }) {
  const [published, setPublished] = useState<Page<Membership> | null>(null);
  const [copied, setCopied] = useState<string | null>(null);

  // Only the published ones, and only a few: this card must stay small for
  // somebody in a hundred clubs.
  useEffect(() => {
    api<Page<Membership>>("GET", "/me/clubs?public_page=true&per_page=5")
      .then(setPublished)
      .catch(() => setPublished(null));
  }, []);

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
        {published && published.total === 0 && (
          <p className="subtle">
            None of your clubs has published one yet. A secretary switches it on from the club&apos;s page.
          </p>
        )}
        {published && published.total > 0 && (
          <ul className="cl-pages">
            {published.items.map((c) => (
              <li key={c.id}>
                <span className={`cc-crest sm tone-${tone(c.id)}`} aria-hidden="true">{initials(c.name)}</span>
                <span className="cl-pages-name">
                  <strong>{c.name}</strong>
                  <span className="subtle" title={`/c/${c.public_slug}`}>/c/{c.public_slug}</span>
                </span>
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
              </li>
            ))}
          </ul>
        )}
        {published && published.total > published.items.length && (
          <button className="linkish cl-pages-more" type="button" onClick={onShowPublished}>
            Show all {published.total} in the list
          </button>
        )}
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

/// One of three crest colours, fixed per club, so a long list is not a wall of
/// identical squares.
const tone = (id: string) => parseInt(id.replace(/-/g, "").slice(-2), 16) % 3;

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
      {/* The fields are a form of their own and the code box sits outside it:
          the code box is a form too, and a form inside a form made pressing
          Confirm reload the page and lose the club that was filled in. */}
      <div className="panel cc-form">
      <form
        id="cc-fields"
        className="cc-fields"
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

      </form>

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
            <button className="btn primary" type="submit" form="cc-fields" disabled={busy || !!verify || !!missing}>
              {busy ? "Creating…" : "Create club"}
            </button>
          </div>
        </div>
      </div>

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
