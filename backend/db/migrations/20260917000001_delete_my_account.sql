-- Somewhere to say an account is gone.
--
-- Apple requires an in-app way to delete an account for any app that lets you
-- create one (App Store Review 5.1.1(v)). A hard DELETE is not open to us:
-- twelve foreign keys point at users(id) with no ON DELETE clause, so any
-- member who owns a club, created a fixture, bought a ticket or invited
-- somebody would fail the delete outright — and cascading those instead would
-- take a club's whole history out with one member who left.
--
-- So deleting scrubs the person out of their row and stamps it. What is left
-- is a nameless stranger holding together matches that still have to add up.
-- Every column that says who they are is cleared by the delete itself; this
-- migration only adds the stamp that says it happened.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Sign-in finds people by email, phone, google_sub and share token, and a
-- delete clears all four — so a deleted row is already unreachable by every
-- route into an account. The queries check this column as well, because
-- "unreachable because every key happens to be NULL" is not a thing to rest
-- an account deletion on.
CREATE INDEX IF NOT EXISTS users_live_idx ON users (id) WHERE deleted_at IS NULL;
