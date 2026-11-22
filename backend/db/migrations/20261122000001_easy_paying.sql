-- Easy paying: pay links from WhatsApp with no sign-in, readable references,
-- payment screenshots kept private, the club's usual prices, and signing in
-- with a WhatsApp code. See docs/CLUB_PAYMENTS_V2_PLAN.md, step A.

-- A pay link for one bill. Its token is never stored: it is the link's id and
-- an HMAC of it, minted again when needed, so a copy of the database holds no
-- working link. Links expire; a secretary can switch one off.
CREATE TABLE IF NOT EXISTS pay_links (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    bill_id     UUID NOT NULL REFERENCES event_bills(id) ON DELETE CASCADE,
    created_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL,
    disabled_at TIMESTAMPTZ,
    disabled_by UUID REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_pay_links_bill ON pay_links (bill_id, created_at DESC);

-- A claim made through a pay link: which link, and which share it was for.
-- `created_by` is NULL for these (nobody signed in), so retries are made
-- idempotent per link instead of per person.
ALTER TABLE member_payments
    ADD COLUMN IF NOT EXISTS via_link UUID REFERENCES pay_links(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS share_id UUID REFERENCES bill_shares(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_member_payments_link_idempotency
    ON member_payments (via_link, idempotency_key)
    WHERE via_link IS NOT NULL AND idempotency_key IS NOT NULL;

-- A screenshot of the payment, from the payer's banking app. Kept in the
-- database, not the public bucket: it can show a name, an account and an
-- amount, and only the club's money admins may see it.
CREATE TABLE IF NOT EXISTS payment_attachments (
    payment_id   UUID PRIMARY KEY REFERENCES member_payments(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/heic')),
    bytes        BYTEA NOT NULL CHECK (octet_length(bytes) <= 3145728),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- References people can read: the surname ("SHARMA"), with a number only when
-- two members of a club share one ("SHARMA 2"). The old five-character codes
-- were never in a store build; they are made again, readable, on first use.
ALTER TABLE payment_references DROP CONSTRAINT IF EXISTS payment_references_code_check;
DELETE FROM payment_references;
ALTER TABLE payment_references
    ADD CONSTRAINT payment_references_code_check CHECK (code ~ '^[A-Z][A-Z0-9 ]{0,17}$');

-- The club's usual prices, set once in the setup wizard and offered on every
-- new session so nobody types them again.
ALTER TABLE clubs
    ADD COLUMN IF NOT EXISTS default_nets_mode TEXT
        CHECK (default_nets_mode IS NULL OR default_nets_mode IN ('split_total', 'per_player')),
    ADD COLUMN IF NOT EXISTS default_nets_cents BIGINT
        CHECK (default_nets_cents IS NULL OR (default_nets_cents > 0 AND default_nets_cents <= 1000000)),
    ADD COLUMN IF NOT EXISTS default_match_fee_cents BIGINT
        CHECK (default_match_fee_cents IS NULL OR (default_match_fee_cents > 0 AND default_match_fee_cents <= 100000));

-- Signing in with a WhatsApp code is a channel of its own: a code sent to sign
-- in must never confirm a number, nor one sent to confirm a number sign in.
ALTER TABLE verification_codes DROP CONSTRAINT IF EXISTS verification_codes_channel_check;
ALTER TABLE verification_codes
    ADD CONSTRAINT verification_codes_channel_check CHECK (channel IN ('email', 'phone', 'signin'));
