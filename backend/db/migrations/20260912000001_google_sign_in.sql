-- Sign in with Google. `sub` is Google's permanent id for the account — the
-- email on it can change, the sub never does — so it, not the address, is
-- what a returning Google sign-in is matched on.
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub TEXT UNIQUE;
