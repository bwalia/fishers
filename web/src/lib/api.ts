/// Where the API lives, worked out at call time.
///
/// Baking a LAN IP in at build time meant the dashboard stopped talking to the
/// API the moment DHCP handed the machine a different address. Deriving it from
/// the page's own hostname keeps localhost, 127.0.0.1 and any LAN address all
/// working without a rebuild; NEXT_PUBLIC_API_BASE still overrides when the API
/// really is somewhere else.
export function apiOrigin(): string {
  const explicit = process.env.NEXT_PUBLIC_API_BASE?.replace(/\/$/, "");
  if (explicit) return explicit;
  const port = process.env.NEXT_PUBLIC_API_PORT || "7312";
  if (typeof window !== "undefined") {
    // A page served on the default port arrived through the ingress, and the
    // ingress puts the API on this same origin under /api. Returning an empty
    // origin makes every call a relative URL: one image serves every ring, and
    // there is no cross-origin request to need CORS.
    //
    // Deriving the port instead sent the browser to
    // https://int.fishers.cloud:7312, a development port that is not published
    // and never answers, so nothing could log in.
    if (!window.location.port) return "";
    // Development: the dashboard is on 7311 and the API beside it on 7312.
    return `${window.location.protocol}//${window.location.hostname}:${port}`;
  }
  // Server-side render. In the cluster the API is a Service, not a neighbour on
  // localhost; API_INTERNAL_BASE is read at runtime so it needs no rebuild.
  return process.env.API_INTERNAL_BASE?.replace(/\/$/, "") || `http://127.0.0.1:${port}`;
}

export function apiV1(): string {
  return `${apiOrigin()}/api/v1`;
}

const TOKEN_KEY = "fishers_access_token";
const REFRESH_KEY = "fishers_refresh_token";
const USER_KEY = "fishers_user";

export type PublicUser = {
  id: string;
  name: string;
  /// Absent for somebody who registered with a mobile number instead.
  email?: string | null;
  phone?: string | null;
  avatar_url?: string | null;
  emergency_contact?: string | null;
  /// The sport they lead with; the rest hang off it.
  primary_sport?: string | null;
  /// One entry per sport played, each with its own position and numbers.
  sport_profiles?: SportProfile[];
  location?: PlayerLocation | null;
  profile_complete?: boolean;
  email_verified?: boolean;
  phone_verified?: boolean;
  /// What they said they came to do; absent until they have been asked.
  role_intent?: RoleIntent | null;
};

export type RoleIntent = "secretary" | "player";

/// `GET /me/verification`.
export type VerificationStatus = {
  /// Whether the server asks for confirmation at all (VERIFICATION_REQUIRED).
  enabled: boolean;
  email: { address?: string | null; verified: boolean; available: boolean };
  phone: { address?: string | null; verified: boolean; available: boolean };
  /// Starting a club or accepting an invite is refused until one is verified.
  verification_required: boolean;
};

/// A player's card, as a secretary sees it from a shared link. No contact
/// details — those come with membership, which the player still accepts.
export type SharedPlayerCard = {
  id: string;
  name: string;
  avatar_url?: string | null;
  primary_sport?: string | null;
  sport_profiles?: SportProfile[];
  area?: string | null;
};

/// One sport a player plays, with whatever that sport measures.
///
/// `stats` is a free map on purpose: a bowling average and a tennis first-serve
/// percentage do not share a schema, and inventing columns for every sport
/// would mean a migration each time one is added. Cricket's real numbers come
/// from the scoring log instead — this is what the player says about
/// themselves for the sports the app does not yet score.
export type SportProfile = {
  sport: string;
  position?: string | null;
  skill_level?: string | null;
  current_division?: string | null;
  target_division?: string | null;
  age_group?: string | null;
  team_name?: string | null;
  years_playing?: number | null;
  stats?: Record<string, string>;
};

export type PlayerLocation = {
  area?: string | null;
  postcode?: string | null;
  travel_radius_miles?: number | null;
  /// `driverWithSeats` | `driver` | `publicTransport` | `needsLift`
  transport?: string | null;
  spare_seats?: number | null;
  notes?: string | null;
};

/// The standards a player picks from, in the words a club uses.
export const SKILL_LEVELS = [
  { value: "beginner", label: "Beginner" },
  { value: "improver", label: "Improver" },
  { value: "club", label: "Club standard" },
  { value: "league", label: "League standard" },
  { value: "county", label: "County / semi-pro" },
] as const;

export function skillLabel(value?: string | null): string {
  if (!value) return "Not said";
  return SKILL_LEVELS.find((s) => s.value === value)?.label ?? value;
}

/// What each sport calls its positions. Adding a sport is a line here, not a
/// migration — and an unknown sport still works, it just takes free text.
export const SPORT_POSITIONS: Record<string, string[]> = {
  cricket: ["Batter", "Bowler", "All-rounder", "Wicketkeeper"],
  football: ["Goalkeeper", "Defender", "Midfielder", "Forward"],
  badminton: ["Singles", "Doubles", "Mixed doubles"],
  paddle: ["Right side", "Left side"],
  pickleball: ["Singles", "Doubles"],
  tennis: ["Singles", "Doubles"],
  other: [],
};

export type Club = {
  id: string;
  name: string;
  sport_types: string[];
  description?: string | null;
  visibility?: string;
  owner_id?: string;
};

/// What `GET /clubs/{id}/my-role` answers — the club decides what you may do,
/// so the page asks rather than guessing from a role name.
export type MyRole = {
  role: string;
  display_name: string;
  is_secretary: boolean;
  is_captain: boolean;
  can_invite_to_play: boolean;
  can_score_match: boolean;
  permissions: string[];
};

/// A page of anything the API pages: `{ items, total, page, per_page, has_more }`.
export type Page<T> = {
  items: T[];
  total: number;
  page: number;
  per_page: number;
  has_more: boolean;
};

/// Whether you are playing, and what you said about it.
export type EventRow = {
  id: string;
  club_id: string;
  title: string;
  sport: string;
  event_subtype: string;
  start_at: string;
  end_at: string;
  fee_amount_cents?: number | null;
  /// Set when the event sells tickets — a dinner, a quiz. Distinct from
  /// `fee_amount_cents`, which is what a player owes for a fixture.
  ticket_price_cents?: number | null;
  ticket_capacity?: number | null;
  status: string;
};

export type Product = {
  id: string;
  club_id: string;
  name: string;
  description?: string | null;
  price_cents: number;
  currency: string;
  category: string;
  stock?: number | null;
};

export function getAccessToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(REFRESH_KEY);
  localStorage.removeItem(USER_KEY);
}

export function saveSession(tokens: {
  access_token: string;
  refresh_token: string;
  user: PublicUser;
}) {
  localStorage.setItem(TOKEN_KEY, tokens.access_token);
  localStorage.setItem(REFRESH_KEY, tokens.refresh_token);
  localStorage.setItem(USER_KEY, JSON.stringify(tokens.user));
}

/// Replace the cached user after an edit, so the nav and greeting follow.
export function saveUser(user: PublicUser) {
  if (typeof window === "undefined") return;
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function getStoredUser(): PublicUser | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as PublicUser;
  } catch {
    return null;
  }
}

export type AuthTokens = {
  access_token: string;
  refresh_token: string;
  user: PublicUser;
};

/// Milliseconds until this JWT expires, or null if it cannot be read. Only the
/// `exp` claim is needed, and the server verifies the signature anyway.
function expiryOf(token: string): number | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const json = atob(part.replace(/-/g, "+").replace(/_/g, "/"));
    const exp = (JSON.parse(json) as { exp?: number }).exp;
    return typeof exp === "number" ? exp * 1000 : null;
  } catch {
    return null;
  }
}

let refreshing: Promise<string | null> | null = null;

async function performRefresh(): Promise<string | null> {
  const stored = localStorage.getItem(REFRESH_KEY);
  const before = getAccessToken();
  if (!stored) return null;
  try {
    const res = await fetch(`${apiV1()}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: stored }),
      cache: "no-store",
    });
    if (!res.ok) {
      // Another tab may have rotated the pair a moment ago, which revokes the
      // one we just sent. If the stored access token has moved on, use it.
      const now = getAccessToken();
      return now && now !== before ? now : null;
    }
    const tokens = (await res.json()) as AuthTokens;
    saveSession(tokens);
    return tokens.access_token;
  } catch {
    return null;
  }
}

/// Refresh the session, one at a time.
///
/// The server rotates refresh tokens — issuing a new pair revokes the old one —
/// so two refreshes in flight together would revoke each other and sign the
/// user out mid-over. Callers share whichever is already running.
export function refreshSession(): Promise<string | null> {
  if (!refreshing) {
    refreshing = performRefresh().finally(() => {
      refreshing = null;
    });
  }
  return refreshing;
}

/// The access token to send, refreshed first if it is about to lapse. Doing it
/// before the request rather than after a rejection means a ball being scored
/// never fails on an expired token.
export async function usableToken(): Promise<string | null> {
  const token = getAccessToken();
  if (!token) return null;
  const expires = expiryOf(token);
  if (expires !== null && expires - Date.now() < 60_000) {
    return (await refreshSession()) ?? getAccessToken();
  }
  return token;
}

function sessionLost() {
  clearSession();
  if (typeof window !== "undefined" && !window.location.pathname.startsWith("/login")) {
    const next = window.location.pathname + window.location.search;
    window.location.href = `/login?next=${encodeURIComponent(next)}`;
  }
}

export async function api<T>(
  method: string,
  path: string,
  body?: unknown,
  authorized = true,
  retried = false,
  /// Cancels the request — for work that a newer request makes pointless.
  signal?: AbortSignal
): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (authorized) {
    const token = await usableToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }
  const res = await fetch(`${apiV1()}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store",
    signal,
  });

  // A token can still lapse between the check and the call — a long upload, a
  // sleeping laptop, a clock that drifted. Refresh once and send it again.
  if (res.status === 401 && authorized && !retried) {
    const token = await refreshSession();
    if (token) return api<T>(method, path, body, authorized, true, signal);
    sessionLost();
    throw new Error("Your session has expired. Please sign in again.");
  }

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `HTTP ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

/// A file upload. Separate from `api` because the browser must set the
/// multipart boundary itself — sending our own Content-Type breaks the body.
export async function upload<T>(path: string, file: File): Promise<T> {
  const token = await usableToken();
  const form = new FormData();
  form.append("file", file);
  const res = await fetch(`${apiV1()}${path}`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  if (!res.ok) throw new Error((await res.text()) || `HTTP ${res.status}`);
  return (await res.json()) as T;
}

/// The sentence to put in front of somebody.
///
/// The API answers a refusal as `{"error": "..."}`, written to be read. Showing
/// the raw body instead hands them the plumbing.
/// The stable reason behind a refusal, where the API gives one — "unverified"
/// means send them to verify, not to an error message.
export function errCode(err: unknown): string | undefined {
  try {
    return JSON.parse(err instanceof Error ? err.message : "").code;
  } catch {
    return undefined;
  }
}

export function readErr(err: unknown, fallback: string): string {
  const raw = err instanceof Error ? err.message : "";
  try {
    return JSON.parse(raw).error ?? fallback;
  } catch {
    return raw || fallback;
  }
}

export function money(cents: number, currency = "GBP") {
  return new Intl.NumberFormat("en-GB", {
    style: "currency",
    currency,
  }).format(cents / 100);
}

/// A club's public page, as the club writes it. The record and the leading
/// players are computed, so they are not here.
export type ClubPageSettings = {
  id: string;
  name: string;
  slug: string | null;
  sport_types: string[];
  tagline: string | null;
  about: string | null;
  ground: string | null;
  founded_year: number | null;
  contact_email: string | null;
  website: string | null;
  public_page: boolean;
  /// The one player the club leads its page with.
  icon_player_id: string | null;
};

/// Unpaid match fees for a club (`GET /clubs/{id}/fees/outstanding`).
///
/// One row per person per fixture, because that is how a club chases them —
/// "you owe for the Watford game", not "you owe £24".
export type OutstandingFees = {
  total_cents: number;
  count: number;
  owed: {
    user_id: string;
    name: string;
    event_id: string;
    fixture: string;
    start_at: string;
    amount_cents: number | null;
    currency: string;
    reminders_sent: number;
  }[];
};

/// A club shop order (`backend/domain/src/order.rs`).
export type Order = {
  id: string;
  user_id: string;
  club_id: string;
  event_id: string | null;
  /// `draft` | `placed` | `paid` | `fulfilled` | `cancelled`
  status: string;
  total_amount_cents: number;
  currency: string;
  note: string | null;
  created_at: string;
};

export type OrderItem = {
  id: string;
  order_id: string;
  product_id: string;
  quantity: number;
  unit_price_cents: number;
};

export type OrderResponse = { order: Order; items: OrderItem[] };

/// What Stripe needs to take the money. The client secret is handed to
/// Stripe's own form — it never buys anything on its own.
export type PaymentIntent = {
  payment_id: string;
  client_secret: string;
  amount_cents: number;
  currency: string;
  status: string;
};

/// How a club wants selection and fee-chasing to run itself
/// (`backend/db/src/repos/clubs.rs`).
export type ClubSettings = {
  /// `off` — the captain does everything.
  /// `suggest` — the assistant offers a squad and waits.
  /// `auto_publish` — it announces one on its own.
  selection_autonomy: string;
  confirm_lead_hours: number;
  drop_lead_hours: number;
  fee_chase_after_hours: number;
  fee_chase_max_reminders: number;
};

/// Somewhere a club plays (`backend/domain/src/club.rs`).
export type Venue = {
  id: string;
  club_id: string;
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
};

export type TeamMemberRow = {
  user_id: string;
  name: string;
  role: string;
  avatar_url?: string | null;
  position_role?: string | null;
};

export type Team = {
  id: string;
  club_id: string;
  name: string;
  sport: string;
};

export type ClubMemberRow = {
  user_id: string;
  name: string;
  /// One of these is absent: people register with an address or a number.
  email?: string | null;
  phone?: string | null;
  role: string;
  status: string;
  position_role?: string | null;
  skill_level?: string | null;
  avatar_url?: string | null;
};

/// Sent as `icon_player_id` to mean "nobody". A JSON null means the editor did
/// not touch the field, so clearing needs a value the API can tell apart.
export const NO_ICON_PLAYER = "00000000-0000-0000-0000-000000000000";

/// A club or team's QR code, already drawn.
export type QrCode = {
  id: string;
  name: string;
  qr_token: string;
  /// "club" or "team"
  kind: string;
  club_id: string;
  club_name: string;
  sport?: string | null;
  payload: string;
  svg: string;
};

/// What a scanned or searched opponent resolves to.
export type OpponentIdentity = {
  id: string;
  name: string;
  qr_token: string;
  kind: string;
  club_id: string;
  club_name: string;
  sport?: string | null;
};

/// Something that happened which you need to know about.
export type AppNotification = {
  id: string;
  type: string;
  payload: Record<string, unknown>;
  sent_at: string;
  read_at?: string | null;
};

/// One line of plain English per notification. A player is not going to read
/// `match_terms_proposed`.
/// Another player, as their club-mates may see them.
///
/// Deliberately narrower than `PublicUser`: no email, no phone, no emergency
/// contact, no home location. Sharing a club is not consent to hand over
/// somebody's mobile number.
export type TeammateProfile = {
  id: string;
  name: string;
  avatar_url: string | null;
  position_role: string | null;
  skill_level: string | null;
  primary_sport: string | null;
  sport_profiles: SportProfile[];
  reliability?: {
    score: number;
    attendance_rate: number;
    response_rate: number;
    band?: string;
  } | null;
  /// Clubs you and they are both in.
  shared_clubs: string[];
};

/// One page of notifications, as `GET /notifications` serves it.
///
/// `unread` counts everything, not the page — it is what the bell shows, and a
/// filter must not change it. `kinds` is every type this person has been sent,
/// so the filter offers only what would match something.
export type NotificationPage = {
  items: AppNotification[];
  total: number;
  page: number;
  per_page: number;
  has_more: boolean;
  unread: number;
  kinds: string[];
};

/// The words for a notification type. Anything not listed falls back to the
/// raw type with its underscores knocked out, so a new kind on the server
/// shows up as readable-ish rather than blank.
export const NOTIFICATION_KIND: Record<string, string> = {
  invite: "Invitations",
  selection_published: "Squads",
  squad_promoted: "Squads",
  selection_reconfirm: "Confirmations",
  match_terms_proposed: "Match setup",
  match_terms_agreed: "Match setup",
  match_book_handed_over: "Scoring",
  match_scheduled: "Fixtures",
  availability_request: "Availability",
  fee_reminder: "Match fees",
  scoreboard_shared: "Scoreboards",
};

export function kindLabel(kind: string): string {
  return NOTIFICATION_KIND[kind] ?? kind.replaceAll("_", " ");
}

export function notificationLine(n: AppNotification): {
  title: string;
  href?: string;
  /// Which fixture this is, when there are several against the same side.
  when?: string;
} {
  const p = n.payload as {
    home_name?: string;
    away_name?: string;
    match_id?: string;
    event_id?: string;
    start_at?: string;
  };
  // Two clubs often play each other several times a season, so the sides alone
  // do not say which match — and following the wrong one lands you in a
  // different game than the one you are scoring.
  const when = p.start_at
    ? new Date(p.start_at).toLocaleString("en-GB", {
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
      })
    : undefined;
  switch (n.type) {
    case "match_terms_proposed":
      return {
        when,
        title: `${p.home_name ?? "A side"} v ${p.away_name ?? "another"} — the other captain has proposed the terms. Tap to agree.`,
        href: p.match_id ? `/score/${p.match_id}` : undefined,
      };
    case "match_pick_your_xi":
      return {
        when,
        title: `${p.home_name ?? "A side"} v ${p.away_name ?? "another"} — the toss is done. Pick your side.`,
        href: p.match_id ? `/score/${p.match_id}` : undefined,
      };
    case "match_terms_agreed":
      return {
        when,
        title: "Both captains have agreed the terms. You can do the toss.",
        href: p.match_id ? `/score/${p.match_id}` : undefined,
      };
    case "match_book_handed_over":
      return {
        when,
        title: `${p.home_name ?? "A side"} v ${p.away_name ?? "another"} — you have the book. You're scoring from the next ball.`,
        href: p.match_id ? `/score/${p.match_id}` : undefined,
      };
    case "fixture_scheduled":
      return {
        when,
        title: `${(n.payload as { title?: string }).title ?? "A fixture"} — can you play?`,
        href: p.event_id ? `/events?fixture=${p.event_id}` : undefined,
      };
    case "player_responded":
      return {
        when,
        title: `${(n.payload as { player?: string }).player ?? "A player"} answered for ${
          (n.payload as { title?: string }).title ?? "a fixture"
        }.`,
        href: p.event_id ? `/events?fixture=${p.event_id}` : undefined,
      };
    case "invite": {
      // The club (and team) by name, and who asked — an approval request that
      // says what is being approved.
      const i = n.payload as { club_name?: string; team_name?: string; event_title?: string; inviter?: string };
      const from = i.inviter ? ` ${i.inviter} invited you.` : "";
      if (i.team_name)
        return { title: `${i.club_name ?? "A club"} wants you in their ${i.team_name}.${from}`, href: "/" };
      if (i.event_title) return { title: `You're invited: ${i.event_title}.${from}`, href: "/" };
      return { title: `${i.club_name ?? "A club"} wants you in the club.${from}`, href: "/" };
    }
    case "invite_accepted": {
      const a = n.payload as { player?: string; team_name?: string; club_name?: string; event_title?: string; club_id?: string };
      return {
        title: `${a.player ?? "A player"} accepted — they're in ${a.team_name ?? a.event_title ?? a.club_name ?? "the club"}.`,
        href: a.club_id ? `/clubs/${a.club_id}#members` : undefined,
      };
    }
    default:
      return { title: n.type.replaceAll("_", " ") };
  }
}

export type Invite = {
  id: string;
  target_type: string;
  target_id: string;
  invited_user_id?: string | null;
  invited_email?: string | null;
  token: string;
  status: string;
  created_at: string;
  /// The club, "team · club", or fixture — present on your own invites.
  target_name?: string | null;
  invited_by_name?: string | null;
};

/// What somebody is allowed to do in the club — an office, not a job that
/// replaces playing.
///
/// The levels stack: a secretary already has everything a captain has, so the
/// same person being both is one choice rather than two. And everybody in the
/// club is a candidate for selection whatever their role, including the
/// secretary — the roster is who plays, this is who runs it.
export const CLUB_ROLES = [
  { value: "member", label: "Member", can: "Plays, and answers for their own availability." },
  {
    value: "team_vice_captain",
    label: "Vice captain",
    can: "Everything a member can, plus picking a side.",
  },
  {
    value: "team_captain",
    label: "Captain",
    can: "Picks the side, agrees terms, and scores a match.",
  },
  {
    value: "club_admin",
    label: "Secretary",
    can: "Everything a captain can, plus the roster, fixtures and fees.",
  },
] as const;

export function roleBlurb(role: string): string | undefined {
  return CLUB_ROLES.find((r) => r.value === role)?.can;
}

export function roleLabel(role: string): string {
  return CLUB_ROLES.find((r) => r.value === role)?.label ?? role.replaceAll("_", " ");
}

/// Exactly what the API's SportType accepts — anything else is rejected.
export const SPORTS = [
  "cricket",
  "football",
  "badminton",
  "paddle",
  "pickleball",
  "tennis",
  "other",
] as const;
