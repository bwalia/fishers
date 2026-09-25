/// The whole system, for whoever runs it.
///
/// Every field mirrors `backend/domain/src/admin.rs`. One brand's deployment is
/// one system: each has its own database, so nothing here can show another
/// brand's people.

import { api } from "./api";

export type Growth = { total: number; last_7d: number; last_30d: number };

export type AdminOverview = {
  taken_at: string;
  people: {
    users: Growth;
    email_verified: number;
    phone_verified: number;
    deleted: number;
    active_sessions: number;
    push_devices: number;
  };
  clubs: {
    clubs: Growth;
    teams: number;
    memberships: number;
    empty: number;
    by_sport: { sport: string; clubs: number }[];
  };
  cricket: {
    matches: Growth;
    by_status: { status: string; count: number }[];
    scoring_events: number;
    fixtures_ahead: number;
  };
  money: {
    taken: { currency: string; amount_cents: number; payments: number }[];
    payments: Growth;
    failed_7d: number;
    unpaid_orders: number;
  };
  health: {
    migration: string;
    migrations_failed: number;
    webhooks_unprocessed: number;
    agent_failures_7d: number;
    agent_last_error: string | null;
    codes_pending: number;
    notifications_24h: number;
    notifications_unread: number;
    database_bytes: number;
  };
  recent: {
    id: string;
    event_type: string;
    occurred_at: string;
    club_name: string | null;
  }[];
};

export type AdminUser = {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  email_verified: boolean;
  phone_verified: boolean;
  created_at: string;
  deleted_at: string | null;
  clubs: number;
  active_sessions: number;
};

export const adminOverview = () => api<AdminOverview>("GET", "/admin/overview");

export const adminFindUsers = (q: string) =>
  api<AdminUser[]>("GET", `/admin/users?q=${encodeURIComponent(q)}`);

/// "1.2 GB". Bytes are what Postgres reports and not what anybody reads.
export function bytes(n: number): string {
  const units = ["B", "kB", "MB", "GB", "TB"];
  let size = n;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size < 10 && unit > 0 ? size.toFixed(1) : Math.round(size)} ${units[unit]}`;
}

/// Money, in the currency it was taken in. Never summed across currencies:
/// pence and paise add to a number that means nothing.
export function money(amountCents: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency,
      maximumFractionDigits: 2,
    }).format(amountCents / 100);
  } catch {
    // An unknown currency code should still show the number.
    return `${(amountCents / 100).toFixed(2)} ${currency.toUpperCase()}`;
  }
}
