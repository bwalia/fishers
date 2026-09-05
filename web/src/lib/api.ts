export const API_ORIGIN =
  process.env.NEXT_PUBLIC_API_BASE?.replace(/\/$/, "") || "http://127.0.0.1:8080";

export const API_V1 = `${API_ORIGIN}/api/v1`;

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

export async function api<T>(
  method: string,
  path: string,
  body?: unknown,
  authorized = true
): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (authorized) {
    const token = getAccessToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }
  const res = await fetch(`${API_V1}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store",
  });
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
