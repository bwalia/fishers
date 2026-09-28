//! What the whole system looks like from one desk.
//!
//! Every brand runs its own database, so "the system" here is one brand's
//! deployment. Nothing crosses between them and nothing here could.

use chrono::{DateTime, Utc};
use serde::Serialize;
use uuid::Uuid;

/// A count, and how much of it arrived recently.
///
/// The totals answer "how big is this"; the deltas answer "is anything
/// happening" — which is the question somebody actually has when they open
/// this at eleven at night.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct Growth {
    pub total: i64,
    pub last_7d: i64,
    pub last_30d: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct AdminOverview {
    /// When this snapshot was taken, so a stale tab is obvious.
    pub taken_at: DateTime<Utc>,
    pub people: People,
    pub clubs: Clubs,
    pub cricket: Cricket,
    pub money: Money,
    pub health: Health,
    /// The last few things that happened, newest first.
    pub recent: Vec<RecentEvent>,
}

#[derive(Debug, Clone, Serialize)]
pub struct People {
    pub users: Growth,
    /// Of the total: how many have confirmed an address or a number. A gap
    /// here is usually a mail problem, not a people problem.
    pub email_verified: i64,
    pub phone_verified: i64,
    /// Soft-deleted accounts, which every other count here excludes.
    pub deleted: i64,
    /// Refresh tokens not yet expired — roughly, who is signed in somewhere.
    pub active_sessions: i64,
    /// Devices that could receive a push.
    pub push_devices: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Clubs {
    pub clubs: Growth,
    pub teams: i64,
    pub memberships: i64,
    /// Clubs with nobody but their owner — usually somebody who signed up,
    /// made a club and stopped.
    pub empty: i64,
    /// How many clubs play each sport. A club can play several.
    pub by_sport: Vec<SportCount>,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct SportCount {
    pub sport: String,
    pub clubs: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Cricket {
    pub matches: Growth,
    /// By status: scheduled, live, complete, published…
    pub by_status: Vec<StatusCount>,
    /// Balls recorded. The one number that says whether the app is used for
    /// what it is for.
    pub scoring_events: i64,
    pub fixtures_ahead: i64,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct StatusCount {
    pub status: String,
    pub count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Money {
    /// Settled, in the smallest unit. Mixed currencies are kept apart rather
    /// than summed — adding pence to paise gives a number that means nothing.
    pub taken: Vec<CurrencyTotal>,
    pub payments: Growth,
    pub failed_7d: i64,
    /// Placed and not yet paid. A basket left in `draft` is not money
    /// anybody is waiting for, so it is not counted here.
    pub unpaid_orders: i64,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct CurrencyTotal {
    pub currency: String,
    pub amount_cents: i64,
    pub payments: i64,
}

/// The things that go wrong, and where to look when they do.
#[derive(Debug, Clone, Serialize)]
pub struct Health {
    /// The newest applied migration, and whether any failed. A failed one
    /// means the API is running against a schema it does not expect.
    pub migration: String,
    pub migrations_failed: i64,
    /// Stripe webhooks received but not processed.
    pub webhooks_unprocessed: i64,
    /// Agent runs that ended in an error, and the newest message.
    pub agent_failures_7d: i64,
    pub agent_last_error: Option<String>,
    /// Verification codes still outstanding — a pile of these with few
    /// verified users is a mail or WhatsApp problem.
    pub codes_pending: i64,
    /// Notifications written in the last day, and how many nobody opened.
    pub notifications_24h: i64,
    pub notifications_unread: i64,
    pub database_bytes: i64,
}

/// One line of the audit trail.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct RecentEvent {
    pub id: Uuid,
    pub event_type: String,
    pub occurred_at: DateTime<Utc>,
    pub club_name: Option<String>,
}

/// One row of the people table.
///
/// The columns somebody scans down when they are looking for a person: who
/// they are, whether they can be contacted, what they play, and whether they
/// have actually used the thing.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AdminUserRow {
    pub id: Uuid,
    pub name: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub email_verified: bool,
    pub phone_verified: bool,
    pub avatar_url: Option<String>,
    pub primary_sport: Option<String>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub clubs: i64,
    /// Matches with a scorecard to their name, across every season.
    pub matches: i64,
    pub created_at: DateTime<Utc>,
    /// The newest refresh token issued — near enough to "last signed in", and
    /// the only thing recorded that answers it at all.
    pub last_seen: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
}

/// A page of them, with enough to draw the pager.
#[derive(Debug, Clone, Serialize)]
pub struct AdminUserPage {
    pub rows: Vec<AdminUserRow>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
}

/// A club this person belongs to, and what they are in it.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AdminUserClub {
    pub club_id: Uuid,
    pub club_name: String,
    pub role: String,
    pub is_captain: bool,
    pub status: String,
    pub joined_at: Option<DateTime<Utc>>,
}

/// One season's figures, as the scorers recorded them.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AdminUserSeason {
    pub season_year: i32,
    pub sport: String,
    pub club_name: Option<String>,
    pub matches: i32,
    pub runs: i32,
    pub batting_innings: i32,
    pub not_outs: i32,
    pub balls_faced: i32,
    pub fours: i32,
    pub sixes: i32,
    /// Nullable in the table: a season with no innings has no highest score,
    /// and 0 would read as "out for a duck every time".
    pub high_score: Option<i32>,
    pub wickets: i32,
    pub overs_bowled: f64,
    pub bowling_runs: i32,
    pub maidens: i32,
    pub catches: i32,
    pub stumpings: i32,
}

/// Whether they turn up, from the invitations they have been sent.
///
/// The question a captain actually asks about somebody, and the one thing on
/// this page that is about behaviour rather than record.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AdminAvailability {
    pub invited: i64,
    pub said_yes: i64,
    pub said_no: i64,
    pub never_answered: i64,
    pub selected: i64,
    pub attended: i64,
}

/// Everything held about one person, in one response.
///
/// Deliberately one request rather than six: the operator opened this because
/// somebody wrote in, and a page that fills in over four seconds is a page
/// they are still scrolling when the phone call ends.
#[derive(Debug, Clone, Serialize)]
pub struct AdminUserDetail {
    pub user: AdminUserRow,
    /// The profile as they filled it in — sports, positions, standards.
    pub sport_profiles: serde_json::Value,
    pub location: serde_json::Value,
    pub role_intent: Option<String>,
    pub profile_completed_at: Option<DateTime<Utc>>,
    pub umpires: bool,
    pub umpire_note: Option<String>,
    pub clubs: Vec<AdminUserClub>,
    pub seasons: Vec<AdminUserSeason>,
    pub availability: AdminAvailability,
    /// Matches stood as umpire, and what players made of it.
    pub umpired: i64,
    pub umpire_rating: Option<f64>,
    pub umpire_reviews: i64,
    pub achievements: i64,
    pub active_sessions: i64,
    pub push_devices: i64,
    /// How they sign in: password, Google, Apple. A person who cannot get in
    /// is the commonest reason this page is open, and the answer is usually
    /// here.
    pub has_password: bool,
    pub has_google: bool,
    pub has_apple: bool,
}
