//! Postgres access layer: pool construction, row types and queries.
//!
//! All queries use runtime `sqlx::query_as`/`sqlx::query` (no compile-time
//! `query!` macros) so the workspace builds without a database.

pub use sqlx::postgres::PgPoolOptions;
pub use sqlx::PgPool;

pub mod availability;
pub mod clubs;
pub mod devices;
pub mod events;
pub mod invites;
pub mod payments;
pub mod rows;
pub mod shop;
pub mod users;

/// Build a lazily-connecting pool so the API can boot before Postgres is up.
pub fn connect_lazy(database_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect_lazy(database_url)
}

/// True when `err` is a Postgres unique-constraint violation.
pub fn is_unique_violation(err: &sqlx::Error) -> bool {
    matches!(
        err,
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505")
    )
}

/// True when `err` is a Postgres foreign-key violation.
pub fn is_foreign_key_violation(err: &sqlx::Error) -> bool {
    matches!(
        err,
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23503")
    )
}
