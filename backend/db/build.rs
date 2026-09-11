//! Rebuild this crate whenever a migration is added or changed.
//!
//! `sqlx::migrate!` embeds the migrations directory at compile time, but cargo
//! only reruns it when a Rust source changes. A new .sql file went unnoticed:
//! the binary kept the old list, and a local API started without the
//! migration its code depended on.
fn main() {
    println!("cargo:rerun-if-changed=migrations");
}
