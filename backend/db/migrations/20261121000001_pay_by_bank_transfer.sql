-- Paying the club by bank transfer. See docs/PAY_BY_BANK_TRANSFER.md.
--
-- The app never touches the money: it works out who owes what, shows the
-- club's bank details with a reference, and keeps the record. A debt is
-- cleared by a treasurer confirming it (or a card payment that succeeded),
-- never on the payer's say-so.
--
-- What is paid towards what is *not* stored. Payments are matched to shares
-- oldest first, in code (`fishers_domain::money::settle`), every time they are
-- read. A re-split, a waived share or a cancelled bill therefore can't leave an
-- allocation pointing at the wrong thing: there are no allocations to go stale.
--
-- Money is integer minor units. Nothing is deleted: a mistake is voided,
-- rejected or cancelled, with a reason.

-- Per-club switches. `payments_enabled_at` is set when a club adds its first
-- bank details (or sends its first bill by hand); nothing is billed
-- automatically for a fixture that ended before it.
ALTER TABLE clubs
    ADD COLUMN IF NOT EXISTS payments_enabled_at   TIMESTAMPTZ,
    -- Send the bill from the "going" list when nobody has confirmed who came.
    ADD COLUMN IF NOT EXISTS auto_bill             BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS auto_bill_after_hours INT     NOT NULL DEFAULT 24
        CHECK (auto_bill_after_hours BETWEEN 1 AND 336),
    -- Round each share of a split up to the next 10p; the surplus is the club's.
    ADD COLUMN IF NOT EXISTS round_shares_up       BOOLEAN NOT NULL DEFAULT FALSE;

-- Where the money goes. Phase one: one account per club, plus at most one
-- replacement waiting to go live. A club's first account is live at once; any
-- later one waits (`live_from`) so the owner, secretaries and treasurers can
-- freeze it if it wasn't them.
--
-- The account number is encrypted (AES-256-GCM) before it gets here; `key_id`
-- names the key, so keys can rotate. Sort code, last four digits and holder
-- name are kept readable for display. `fingerprint` is a keyed hash, to spot
-- the same account entered twice without decrypting anything.
--
-- Status is derived, not stored: retired, frozen, pending (live_from still
-- ahead), superseded (a newer one went live) or active.
CREATE TABLE IF NOT EXISTS club_payout_accounts (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id            UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    method             TEXT NOT NULL DEFAULT 'uk_bank' CHECK (method IN ('uk_bank')),
    label              TEXT NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    holder_name        TEXT NOT NULL CHECK (char_length(holder_name) BETWEEN 1 AND 70),
    is_personal        BOOLEAN NOT NULL DEFAULT FALSE,
    sort_code          TEXT CHECK (sort_code ~ '^[0-9]{6}$'),
    last4              TEXT NOT NULL CHECK (last4 ~ '^[0-9]{4}$'),
    -- NULL once retired: only the name and last four digits are kept.
    details_ciphertext BYTEA,
    key_id             TEXT NOT NULL,
    fingerprint        TEXT NOT NULL,
    live_from          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    replaces_id        UUID REFERENCES club_payout_accounts(id),
    frozen_at          TIMESTAMPTZ,
    frozen_by          UUID REFERENCES users(id) ON DELETE SET NULL,
    freeze_reason      TEXT,
    retired_at         TIMESTAMPTZ,
    retired_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    created_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payout_accounts_club
    ON club_payout_accounts (club_id, created_at DESC);

-- What an event costs, set when it is scheduled. `per_player` is the old
-- match fee (and keeps `events.fee_amount_cents` in step, so apps that only
-- know that field still show it); `split_total` divides a total between
-- whoever came, and never touches `fee_amount_cents`.
CREATE TABLE IF NOT EXISTS event_costs (
    event_id               UUID PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
    club_id                UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    mode                   TEXT NOT NULL CHECK (mode IN ('split_total', 'per_player')),
    amount_cents           BIGINT NOT NULL CHECK (amount_cents > 0 AND amount_cents <= 1000000),
    currency               TEXT NOT NULL DEFAULT 'GBP' CHECK (char_length(currency) = 3),
    note                   TEXT CHECK (note IS NULL OR char_length(note) <= 200),
    -- The "who came?" nudge to whoever scheduled it, once.
    attendance_prompted_at TIMESTAMPTZ,
    -- The scheduler looked and could not bill (nobody going); it won't retry.
    auto_bill_skipped_at   TIMESTAMPTZ,
    updated_by             UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_event_costs_club ON event_costs (club_id);

-- The bill for one event, sent once attendance is known. It fixes who pays,
-- how much and in what. A re-split keeps the bill and bumps `version`; a
-- cancelled bill is voided. One live bill per event.
--
-- `event_id` is deliberately not ON DELETE CASCADE: money records never
-- disappear with a fixture. Deleting a whole club still takes them with it
-- (club_id cascades, and NO ACTION is checked at the end of the statement).
CREATE TABLE IF NOT EXISTS event_bills (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id          UUID NOT NULL REFERENCES events(id),
    club_id           UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    title             TEXT NOT NULL,
    event_start_at    TIMESTAMPTZ NOT NULL,
    mode              TEXT NOT NULL CHECK (mode IN ('split_total', 'per_player')),
    amount_cents      BIGINT NOT NULL CHECK (amount_cents > 0),
    total_cents       BIGINT NOT NULL CHECK (total_cents > 0),
    currency          TEXT NOT NULL CHECK (char_length(currency) = 3),
    rounding          TEXT NOT NULL DEFAULT 'exact' CHECK (rounding IN ('exact', 'up_10p')),
    payout_account_id UUID REFERENCES club_payout_accounts(id),
    status            TEXT NOT NULL DEFAULT 'issued' CHECK (status IN ('issued', 'void')),
    version           INT  NOT NULL DEFAULT 1,
    auto              BOOLEAN NOT NULL DEFAULT FALSE,
    note              TEXT,
    issued_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    issued_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    voided_at         TIMESTAMPTZ,
    voided_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    void_reason       TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_event_bills_one_live
    ON event_bills (event_id) WHERE status = 'issued';
CREATE INDEX IF NOT EXISTS idx_event_bills_club ON event_bills (club_id, issued_at DESC);

-- One person's part of a bill. Never edited: a re-split voids the old shares
-- and writes new ones, so the history reads straight. `name` is a snapshot,
-- so a share still reads right after its member deletes their account.
-- A guest (typed in by name, no account) has `user_id` NULL.
CREATE TABLE IF NOT EXISTS bill_shares (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bill_id          UUID NOT NULL REFERENCES event_bills(id) ON DELETE CASCADE,
    club_id          UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    user_id          UUID REFERENCES users(id) ON DELETE SET NULL,
    guest_name       TEXT,
    name             TEXT NOT NULL,
    amount_cents     BIGINT NOT NULL CHECK (amount_cents > 0),
    status           TEXT NOT NULL DEFAULT 'live' CHECK (status IN ('live', 'waived', 'void')),
    reason           TEXT,
    decided_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    decided_at       TIMESTAMPTZ,
    reminders_sent   INT NOT NULL DEFAULT 0,
    last_reminded_at TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_bill_shares_member
    ON bill_shares (bill_id, user_id) WHERE status = 'live' AND user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bill_shares_user ON bill_shares (user_id, club_id) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS idx_bill_shares_bill ON bill_shares (bill_id);

-- A member's payment reference for one club: the same every time, so a
-- treasurer learns to read it and a player can save the club as a payee.
-- Five characters with nothing easily confused (no 0/O, 1/I/L, U).
CREATE TABLE IF NOT EXISTS payment_references (
    club_id    UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code       TEXT NOT NULL CHECK (code ~ '^[2-9A-HJKMNP-TV-Z]{5}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (club_id, user_id),
    UNIQUE (club_id, code)
);

-- Money a member says they sent, and what a treasurer decided about it.
-- `claimed` → `confirmed` | `rejected` (by a treasurer) | `cancelled` (by the
-- payer, while unconfirmed). Cash a treasurer records is `confirmed` at once.
-- A `refund` is money the club sent back out of a member's credit.
CREATE TABLE IF NOT EXISTS member_payments (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id           UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    user_id           UUID REFERENCES users(id) ON DELETE SET NULL,
    guest_name        TEXT,
    name              TEXT NOT NULL,
    amount_cents      BIGINT NOT NULL CHECK (amount_cents > 0 AND amount_cents <= 1000000),
    currency          TEXT NOT NULL CHECK (char_length(currency) = 3),
    method            TEXT NOT NULL CHECK (method IN ('transfer', 'cash', 'refund')),
    reference         TEXT,
    payout_account_id UUID REFERENCES club_payout_accounts(id),
    status            TEXT NOT NULL CHECK (status IN ('claimed', 'confirmed', 'rejected', 'cancelled')),
    note              TEXT CHECK (note IS NULL OR char_length(note) <= 200),
    idempotency_key   TEXT CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 100),
    created_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    decided_at        TIMESTAMPTZ,
    decision_reason   TEXT,
    -- The 48-hour "still waiting for you to check this" nudge, once.
    check_reminded_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_member_payments_club ON member_payments (club_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_member_payments_user ON member_payments (user_id, club_id);
-- A retried "I've paid" on a bad signal is the same claim, not a second one.
CREATE UNIQUE INDEX IF NOT EXISTS idx_member_payments_idempotency
    ON member_payments (created_by, idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Every change: who, what, when, before and after. Never the account number.
CREATE TABLE IF NOT EXISTS club_payment_audit (
    id         BIGSERIAL PRIMARY KEY,
    club_id    UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    actor_id   UUID REFERENCES users(id) ON DELETE SET NULL,
    action     TEXT NOT NULL,
    entity     TEXT NOT NULL,
    entity_id  UUID,
    before     JSONB,
    after      JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payment_audit_club ON club_payment_audit (club_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_audit_actor ON club_payment_audit (actor_id, action, created_at DESC);

-- Fixtures that already carry a per-player fee get it as a cost, so a club
-- that switches payments on finds its fees already there.
INSERT INTO event_costs (event_id, club_id, mode, amount_cents, currency)
SELECT id, club_id, 'per_player', fee_amount_cents, fee_currency
FROM events
WHERE fee_amount_cents IS NOT NULL AND fee_amount_cents > 0 AND fee_amount_cents <= 1000000
  AND char_length(fee_currency) = 3
ON CONFLICT (event_id) DO NOTHING;
