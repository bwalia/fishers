import type { Key } from "@/lib/i18n/en";
import type { T } from "@/lib/i18n";
import { apiPort } from "./ports";

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
  const port = apiPort();
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
  /// How much of the profile is filled in — the same count the iPhone app shows.
  profile_strength?: ProfileStrength;
  /// Whether this person runs the service. Only `/me` sets it; the API never
  /// reports it about anybody else, so it cannot be read off a teammate.
  platform_admin?: boolean;
};

export type ProfileStrength = {
  percent: number;
  /// What is not filled in yet, most valuable first: "photo", "standard"…
  missing: string[];
  /// "lb.add_a_photo_the_standard_you_play_at_a".
  next_up: string;
};

/// Past the quick start: anyone with a sport on file, on any device; anyone
/// who skipped it, in this browser.
export const quickStartKey = (userId: string) => `fishers:quick-start:${userId}`;

export function needsQuickStart(user: PublicUser): boolean {
  if ((user.sport_profiles ?? []).length > 0) return false;
  try {
    return localStorage.getItem(quickStartKey(user.id)) !== "1";
  } catch {
    return false; // no storage: never trap somebody on a screen they cannot leave
  }
}

export function markQuickStartDone(userId: string) {
  try {
    localStorage.setItem(quickStartKey(userId), "1");
  } catch {
    /* private window: they may see it once more */
  }
}

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
  { value: "beginner", label: "lb.beginner" },
  { value: "improver", label: "lb.improver" },
  { value: "club", label: "lb.club_standard" },
  { value: "league", label: "lb.league_standard" },
  { value: "county", label: "lb.county_semi_pro" },
] as const;

export function skillLabel(value: string | null | undefined, t: T): string {
  if (!value) return t("lb.not_said");
  const found = SKILL_LEVELS.find((s) => s.value === value)?.label;
  // An unknown level is whatever the server called it — there is no key for a
  // value this build has never heard of.
  return found ? t(found) : value;
}

/// What each sport calls its positions. Adding a sport is a line here, not a
/// migration — and an unknown sport still works, it just takes free text.
export const SPORT_POSITIONS: Record<string, Key[]> = {
  cricket: ["pos.batter", "pos.bowler", "lb.all_rounder", "pos.wicketkeeper"],
  football: ["lb.goalkeeper", "lb.defender", "lb.midfielder", "lb.forward"],
  badminton: ["lb.singles", "lb.doubles", "lb.mixed_doubles"],
  paddle: ["lb.right_side", "lb.left_side"],
  pickleball: ["lb.singles", "lb.doubles"],
  tennis: ["lb.singles", "lb.doubles"],
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
  /// How many guests one member may bring. Zero means members only.
  guests_allowed?: number;
  /// Anyone signed in may buy, not only members of the hosting club.
  tickets_public?: boolean;
  status: string;
};

export type ProductCondition = "new" | "used";

export type Product = {
  id: string;
  club_id: string;
  name: string;
  description?: string | null;
  price_cents: number;
  currency: string;
  category: string;
  /// `null` is "on request" — made to order, or a tea urn that does not run
  /// out. A second-hand item is almost always 1.
  stock?: number | null;
  active?: boolean;
  /// New or used. Absent for the things it does not apply to: a cup of tea is
  /// neither.
  condition?: ProductCondition | null;
  /// "lb.light_wear_on_the_toe_no_cracks" The sentence that decides whether
  /// somebody drives an hour to look at it.
  condition_note?: string | null;
  /// Short Handle, Harrow, Youth Large — free text, because bat, pad and glove
  /// sizes share no vocabulary.
  size?: string | null;
  brand?: string | null;
  photos?: string[];
  /// Whether it appears outside the club.
  listed_publicly?: boolean;
  collection_note?: string | null;
  /// Whether the price is the price. Second-hand kit gets haggled over, and a
  /// buyer who cannot tell either overpays or does not ask.
  negotiable?: boolean;
  /// Who put it up, so their own listings can be told apart from the club's.
  listed_by?: string | null;
  /// Whether they chose to publish their email and phone alongside it.
  show_contact?: boolean;
};

/// A listing on its own page: the product, plus who is selling it.
///
/// The contact details arrive only when the seller ticked the box — the API
/// leaves them out otherwise, so there is nothing here to forget to hide.
export type MarketListing = Product & {
  club_name: string;
  seller_name?: string | null;
  seller_email?: string | null;
  seller_phone?: string | null;
  /// Whether you are the one selling it. Decided by the API, not by comparing
  /// ids here — a club's secretary is looking at their own listing too.
  mine?: boolean;
  /// How many people have asked about it. Only sent to the seller.
  enquiries?: number | null;
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
    throw new Error("lb.your_session_has_expired_please_sign_i");
  }

  if (!res.ok) {
    const text = await res.text();
    const error = new Error(text || `HTTP ${res.status}`);
    // Carried so a screen can tell "refused" from "failed" without reading
    // the sentence. `readErr` still hands back the API's own wording; this is
    // for the few places where that wording is written for an API rather than
    // for the person looking at it.
    (error as Error & { status?: number }).status = res.status;
    throw error;
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

/// Whether a thrown `api` error was a refusal on permissions.
export function isForbidden(err: unknown): boolean {
  return (err as { status?: number } | null)?.status === 403;
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

/** Bookable unit inside a venue site (venue hire Phase 1). */
export type VenueSpace = {
  id: string;
  venue_id: string;
  name: string;
  kind: string;
  sports: string[];
  capacity: number | null;
  is_hireable: boolean;
  requires_approval: boolean;
  notice_hours_min: number;
  notice_days_max: number;
  slot_minutes: number;
  buffer_minutes: number;
  notes: string | null;
  active: boolean;
  timezone: string;
};

export type VenueRateCard = {
  id: string;
  space_id: string;
  name: string;
  unit: string;
  amount_cents: number;
  currency: string;
  member_amount_cents: number | null;
  days_of_week: number[];
  min_units: number;
  active: boolean;
};

/** Row from `GET /hire/spaces` — public browse of hireable spaces. */
export type HireableSpace = {
  space_id: string;
  space_name: string;
  kind: string;
  sports: string[];
  capacity: number | null;
  requires_approval: boolean;
  timezone: string;
  venue_id: string;
  venue_name: string;
  venue_address: string | null;
  venue_lat: number | null;
  venue_lng: number | null;
  club_id: string;
  club_name: string;
  from_amount_cents: number | null;
  currency: string | null;
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
  /// Captains the side — by role, or a secretary who captains too.
  is_captain?: boolean;
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
  invite: "lb.invitations",
  selection_published: "lb.squads",
  squad_promoted: "lb.squads",
  selection_reconfirm: "lb.confirmations",
  match_terms_proposed: "Match setup",
  match_terms_agreed: "Match setup",
  match_book_handed_over: "lb.scoring",
  match_scheduled: "Fixtures",
  availability_request: "Availability",
  fee_reminder: "lb.match_fees",
  scoreboard_shared: "lb.scoreboards",
};

export function kindLabel(kind: string): string {
  return NOTIFICATION_KIND[kind] ?? kind.replaceAll("_", " ");
}

/// One line for one notification, in the reader's language.
///
/// Every title is a template with named slots rather than a sentence built by
/// joining fragments: "{home} v {away}" is two names either side of a word,
/// and which side of it they go on is a fact about the language.
export function notificationLine(
  n: AppNotification,
  t: T
): {
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
  const sides = { home: p.home_name ?? t("lb.a_side"), away: p.away_name ?? t("note.another_side") };
  const toMatch = p.match_id ? `/score/${p.match_id}` : undefined;
  switch (n.type) {
    case "match_terms_proposed":
      return { when, title: t("note.terms_proposed", sides), href: toMatch };
    case "match_pick_your_xi":
      return { when, title: t("note.pick_your_xi", sides), href: toMatch };
    case "match_terms_agreed":
      return { when, title: t("lb.both_captains_have_agreed_the_terms_yo"), href: toMatch };
    case "match_book_handed_over":
      return { when, title: t("note.book_handed_over", sides), href: toMatch };
    case "fixture_scheduled":
      return {
        when,
        title: t("note.fixture_scheduled", {
          title: (n.payload as { title?: string }).title ?? t("lb.a_fixture"),
        }),
        href: p.event_id ? `/events?fixture=${p.event_id}` : undefined,
      };
    case "player_responded":
      return {
        when,
        title: t("note.player_responded", {
          player: (n.payload as { player?: string }).player ?? t("lb.a_player"),
          title: (n.payload as { title?: string }).title ?? t("note.a_fixture_lower"),
        }),
        href: p.event_id ? `/events?fixture=${p.event_id}` : undefined,
      };
    case "invite": {
      // The club (and team) by name, and who asked — an approval request that
      // says what is being approved.
      const i = n.payload as { club_name?: string; team_name?: string; event_title?: string; inviter?: string };
      const from = i.inviter ? t("note.invited_by", { who: i.inviter }) : "";
      const club = i.club_name ?? t("lb.a_club");
      if (i.team_name)
        return { title: t("note.invite_team", { club, team: i.team_name }) + from, href: "/" };
      if (i.event_title)
        return { title: t("note.invite_event", { title: i.event_title }) + from, href: "/" };
      return { title: t("note.invite_club", { club }) + from, href: "/" };
    }
    case "profile_nudge": {
      const percent = (n.payload as { percent?: number }).percent;
      return {
        title:
          percent != null
            ? t("fin.finish_profile_pct", { percent })
            : t("fin.finish_profile"),
        href: "/profile",
      };
    }
    case "invite_accepted": {
      const a = n.payload as { player?: string; team_name?: string; club_name?: string; event_title?: string; club_id?: string };
      return {
        title: t("note.invite_accepted", {
          player: a.player ?? t("lb.a_player"),
          where: a.team_name ?? a.event_title ?? a.club_name ?? t("note.the_club"),
        }),
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
  { value: "member", label: "lb.member", can: "lb.plays_and_answers_for_their_own_availa" },
  {
    value: "team_vice_captain",
    label: "lb.vice_captain",
    can: "lb.everything_a_member_can_plus_picking_a",
  },
  {
    value: "team_captain",
    label: "sc.captain",
    can: "lb.picks_the_side_agrees_terms_and_scores",
  },
  {
    value: "club_admin",
    label: "cl.secretary",
    can: "lb.everything_a_captain_can_plus_the_rost",
  },
] as const;

export function roleBlurb(role: string): string | undefined {
  return CLUB_ROLES.find((r) => r.value === role)?.can;
}

export const isSecretaryRole = (role: string) => role === "club_admin" || role === "super_admin";

/// `captain` is the membership's `is_captain`: a secretary who also captains
/// reads as both, since in a small club that is one person.
export function roleLabel(role: string, captain: boolean, t: T): string {
  if (captain && isSecretaryRole(role)) return t("lb.secretary_captain");
  const found = CLUB_ROLES.find((r) => r.value === role)?.label;
  return found ? t(found) : role.replaceAll("_", " ");
}

/// The role picker's choices: the roles, plus a secretary who captains.
export const ROLE_CHOICES: { value: string; label: Key; can: Key }[] = [
  ...CLUB_ROLES.map((r) => ({ value: r.value as string, label: r.label as Key, can: r.can as Key })),
  {
    value: "club_admin+captain",
    label: "lb.secretary_captain",
    can: "lb.a_secretary_who_also_captains_the_side",
  },
];

export const roleChoice = (m: { role: string; is_captain?: boolean }) =>
  isSecretaryRole(m.role) && m.is_captain ? "club_admin+captain" : m.role;

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
