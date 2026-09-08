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
    return `${window.location.protocol}//${window.location.hostname}:${port}`;
  }
  return `http://127.0.0.1:${port}`;
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
  email: string;
  profile_complete?: boolean;
};

export type Club = {
  id: string;
  name: string;
  sport_types: string[];
  description?: string | null;
};

export type EventRow = {
  id: string;
  club_id: string;
  title: string;
  sport: string;
  event_subtype: string;
  start_at: string;
  end_at: string;
  fee_amount_cents?: number | null;
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
async function usableToken(): Promise<string | null> {
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
  retried = false
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
  });

  // A token can still lapse between the check and the call — a long upload, a
  // sleeping laptop, a clock that drifted. Refresh once and send it again.
  if (res.status === 401 && authorized && !retried) {
    const token = await refreshSession();
    if (token) return api<T>(method, path, body, authorized, true);
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

export function money(cents: number, currency = "GBP") {
  return new Intl.NumberFormat("en-GB", {
    style: "currency",
    currency,
  }).format(cents / 100);
}

export type Team = {
  id: string;
  club_id: string;
  name: string;
  sport: string;
};

export type ClubMemberRow = {
  user_id: string;
  name: string;
  email: string;
  role: string;
  status: string;
  position_role?: string | null;
  skill_level?: string | null;
};

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
