-- Verified contact details, what somebody came to do, and a link a player can
-- hand to a club secretary.

ALTER TABLE users
    -- Stamped when a code sent to the CURRENT address is confirmed. Changing
    -- the phone number clears phone_verified_at; email is not editable.
    ADD COLUMN email_verified_at timestamptz,
    ADD COLUMN phone_verified_at timestamptz,
    -- Asked once after signup: run a club, or play in one. Drives which first
    -- steps the dashboard walks them through. NULL until they answer.
    ADD COLUMN role_intent text CHECK (role_intent IN ('secretary', 'player')),
    -- Random, so the link cannot be guessed from a user id. Unique so a token
    -- resolves to exactly one player.
    ADD COLUMN profile_share_token text UNIQUE;

-- One row per code sent. Only the hash is stored: a leaked table must not be
-- a list of working codes.
CREATE TABLE verification_codes (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    channel     text NOT NULL CHECK (channel IN ('email', 'phone')),
    -- The address the code went to. Confirming verifies THIS address, so a
    -- code sent to an old number cannot verify a new one.
    target      text NOT NULL,
    code_hash   text NOT NULL,
    attempts    integer NOT NULL DEFAULT 0,
    expires_at  timestamptz NOT NULL,
    consumed_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Serves both "the latest live code" and "how many sent this hour".
CREATE INDEX verification_codes_recent
    ON verification_codes (user_id, channel, created_at DESC);
