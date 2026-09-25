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

/// A person, as the operator needs to see them when they write in.
///
/// This is the one place in the API that hands over somebody's contact
/// details without them being in a shared club, which is the whole point of an
/// admin panel and the reason it is gated the way it is.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AdminUser {
    pub id: Uuid,
    pub name: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub email_verified: bool,
    pub phone_verified: bool,
    pub created_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub clubs: i64,
    /// Whether they can still sign in somewhere without a password.
    pub active_sessions: i64,
}
