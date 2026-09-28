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

export type AdminUserRow = {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  email_verified: boolean;
  phone_verified: boolean;
  avatar_url: string | null;
  primary_sport: string | null;
  position_role: string | null;
  skill_level: string | null;
  clubs: number;
  matches: number;
  created_at: string;
  /// Newest refresh token — near enough to "last signed in".
  last_seen: string | null;
  deleted_at: string | null;
};

export type AdminUserPage = {
  rows: AdminUserRow[];
  total: number;
  page: number;
  per_page: number;
};

export type AdminUserClub = {
  club_id: string;
  club_name: string;
  role: string;
  is_captain: boolean;
  status: string;
  joined_at: string | null;
};

export type AdminUserSeason = {
  season_year: number;
  sport: string;
  club_name: string | null;
  matches: number;
  runs: number;
  batting_innings: number;
  not_outs: number;
  balls_faced: number;
  fours: number;
  sixes: number;
  /// Null for a season with no innings — not 0, which reads as a duck.
  high_score: number | null;
  wickets: number;
  overs_bowled: number;
  bowling_runs: number;
  maidens: number;
  catches: number;
  stumpings: number;
};

export type AdminAvailability = {
  invited: number;
  said_yes: number;
  said_no: number;
  never_answered: number;
  selected: number;
  attended: number;
};

export type AdminUserDetail = {
  user: AdminUserRow;
  sport_profiles: unknown;
  location: unknown;
  role_intent: string | null;
  profile_completed_at: string | null;
  umpires: boolean;
  umpire_note: string | null;
  clubs: AdminUserClub[];
  seasons: AdminUserSeason[];
  availability: AdminAvailability;
  umpired: number;
  umpire_rating: number | null;
  umpire_reviews: number;
  achievements: number;
  active_sessions: number;
  push_devices: number;
  has_password: boolean;
  has_google: boolean;
  has_apple: boolean;
};

export const adminUsers = (params: {
  q?: string;
  sort?: string;
  page?: number;
  per_page?: number;
}) => {
  const qs = new URLSearchParams();
  if (params.q) qs.set("q", params.q);
  if (params.sort) qs.set("sort", params.sort);
  if (params.page) qs.set("page", String(params.page));
  if (params.per_page) qs.set("per_page", String(params.per_page));
  return api<AdminUserPage>("GET", `/admin/users?${qs}`);
};

export const adminUser = (id: string) => api<AdminUserDetail>("GET", `/admin/users/${id}`);

/// Career totals across every season on file. Averages are computed from the
/// sums, never by averaging the seasons' own averages — which is a different
/// and wrong number.
export function career(seasons: AdminUserSeason[]) {
  const t = seasons.reduce(
    (a, s) => ({
      matches: a.matches + s.matches,
      runs: a.runs + s.runs,
      innings: a.innings + s.batting_innings,
      notOuts: a.notOuts + s.not_outs,
      balls: a.balls + s.balls_faced,
      fours: a.fours + s.fours,
      sixes: a.sixes + s.sixes,
      high: Math.max(a.high, s.high_score ?? 0),
      wickets: a.wickets + s.wickets,
      overs: a.overs + s.overs_bowled,
      conceded: a.conceded + s.bowling_runs,
      maidens: a.maidens + s.maidens,
      catches: a.catches + s.catches,
      stumpings: a.stumpings + s.stumpings,
    }),
    { matches: 0, runs: 0, innings: 0, notOuts: 0, balls: 0, fours: 0, sixes: 0, high: 0,
      wickets: 0, overs: 0, conceded: 0, maidens: 0, catches: 0, stumpings: 0 },
  );
  const dismissals = t.innings - t.notOuts;
  return {
    ...t,
    /// Undefined rather than 0 when they have never been out — an average of
    /// zero reads as "terrible" when it means "not yet calculable".
    average: dismissals > 0 ? t.runs / dismissals : null,
    strikeRate: t.balls > 0 ? (t.runs / t.balls) * 100 : null,
    bowlingAverage: t.wickets > 0 ? t.conceded / t.wickets : null,
    economy: t.overs > 0 ? t.conceded / t.overs : null,
  };
}


export const adminOverview = () => api<AdminOverview>("GET", "/admin/overview");


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
