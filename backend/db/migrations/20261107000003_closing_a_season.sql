-- A club closes its season, and every member gets their season by email.
--
-- A season has only ever been a year on a stats row; nothing said it was
-- over. The secretary saying so is the moment the season email goes, and the
-- only one: closing is once per club per year.
CREATE TABLE IF NOT EXISTS club_seasons (
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    season_year INT NOT NULL,
    closed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (club_id, season_year)
);

-- One row per member per closed season: the email owed, and whether it went.
-- The scheduler sends what is unsent, a batch a tick, and marks it — so a
-- restart halfway through a big club neither stops nor sends anybody two.
CREATE TABLE IF NOT EXISTS season_emails (
    club_id     UUID NOT NULL,
    season_year INT NOT NULL,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    queued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at     TIMESTAMPTZ,
    -- Why it was not sent, when it was not: no_email, opted_out, failed.
    skipped     TEXT,
    attempts    INT NOT NULL DEFAULT 0,
    PRIMARY KEY (club_id, season_year, user_id),
    FOREIGN KEY (club_id, season_year) REFERENCES club_seasons (club_id, season_year) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS season_emails_unsent
    ON season_emails (queued_at) WHERE sent_at IS NULL AND skipped IS NULL;

-- Bulk email needs a way out that works without signing in. The token is the
-- whole of the unsubscribe link, so it is random and only ever does this.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS season_emails_off BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS email_prefs_token TEXT NOT NULL
        DEFAULT replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
CREATE UNIQUE INDEX IF NOT EXISTS users_email_prefs_token ON users (email_prefs_token);
