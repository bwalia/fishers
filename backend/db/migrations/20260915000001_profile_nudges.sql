-- Reminders to finish a profile: how many have gone out, and when the last
-- did, so the scheduler sends at most two and never two close together.
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_nudges SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_nudged_at TIMESTAMPTZ;
