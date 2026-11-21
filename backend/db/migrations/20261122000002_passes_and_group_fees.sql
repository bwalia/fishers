-- Passes, price types, group fees and paying for others. Steps B and C of
-- docs/CLUB_PAYMENTS_V2_PLAN.md.
--
-- Everything anybody owes is still a share on a bill, and phase 1's ledger
-- still matches payments to shares oldest first. What is new is where bills
-- come from — a session, a pass, or a group fee — and that a share can be
-- `covered` (by a pass, or because the person's price type is free): kept on
-- the bill for the record, owing nothing.

-- MARK: price types

-- Adult, junior, student, guest, coach… as a club names them. A member has
-- one (none means the standard price). `free` types owe nothing; the guest
-- type, when a club has one, prices people on a bill who have no account.
CREATE TABLE IF NOT EXISTS club_price_types (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 30),
    free        BOOLEAN NOT NULL DEFAULT FALSE,
    for_guests  BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order  INT NOT NULL DEFAULT 0,
    archived_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (club_id, name)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_price_types_one_guest
    ON club_price_types (club_id) WHERE for_guests AND archived_at IS NULL;

ALTER TABLE club_members
    ADD COLUMN IF NOT EXISTS price_type_id UUID REFERENCES club_price_types(id) ON DELETE SET NULL;

-- A session's price for one price type, where it differs from the standard
-- (per-player costs only: a split total is split evenly).
CREATE TABLE IF NOT EXISTS event_cost_prices (
    event_id      UUID NOT NULL REFERENCES event_costs(event_id) ON DELETE CASCADE,
    price_type_id UUID NOT NULL REFERENCES club_price_types(id) ON DELETE CASCADE,
    amount_cents  BIGINT NOT NULL CHECK (amount_cents >= 0 AND amount_cents <= 100000),
    PRIMARY KEY (event_id, price_type_id)
);

-- MARK: passes

-- What a pass costs, how it is paid, and what it covers.
--   once        — one payment; covers until `valid_until`, or for `sessions`.
--   monthly     — a payment each month, by the player's own standing order,
--                 until they cancel.
--   instalments — `instalments` equal monthly payments; covers until
--                 `valid_until`.
CREATE TABLE IF NOT EXISTS pass_plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id         UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    name            TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    price_cents     BIGINT NOT NULL CHECK (price_cents > 0 AND price_cents <= 1000000),
    currency        TEXT NOT NULL DEFAULT 'GBP' CHECK (char_length(currency) = 3),
    billing         TEXT NOT NULL CHECK (billing IN ('once', 'monthly', 'instalments')),
    instalments     INT CHECK (instalments IS NULL OR instalments BETWEEN 2 AND 12),
    -- Which sessions it covers, by kind; empty covers none (a plain membership).
    covers          TEXT[] NOT NULL DEFAULT '{}',
    team_id         UUID REFERENCES teams(id) ON DELETE SET NULL,
    valid_until     DATE,
    sessions        INT CHECK (sessions IS NULL OR sessions BETWEEN 1 AND 500),
    price_type_id   UUID REFERENCES club_price_types(id) ON DELETE SET NULL,
    open_to_join    BOOLEAN NOT NULL DEFAULT TRUE,
    created_by      UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archived_at     TIMESTAMPTZ,
    CHECK (billing <> 'instalments' OR instalments IS NOT NULL),
    CHECK (covers <@ ARRAY['nets', 'training', 'friendly', 'league_match', 'tournament', 'social', 'generic']::TEXT[])
);
CREATE INDEX IF NOT EXISTS idx_pass_plans_club ON pass_plans (club_id) WHERE archived_at IS NULL;

-- Somebody on a pass. Whether it covers a session today is worked out when a
-- bill is made (is it running, is it paid up enough, are sessions left), not
-- stored, so it can never drift.
CREATE TABLE IF NOT EXISTS pass_holders (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id        UUID NOT NULL REFERENCES pass_plans(id) ON DELETE CASCADE,
    club_id        UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    started_on     DATE NOT NULL,
    -- Set when cancelled: the last day it covers (the end of the paid month).
    ends_on        DATE,
    cancelled_at   TIMESTAMPTZ,
    -- A secretary's override: keep covering however far behind.
    keep_covering  BOOLEAN NOT NULL DEFAULT FALSE,
    -- What the holder was last told about their standing, so each change is
    -- said once: behind, then suspended, then quiet again once paid up.
    told_standing  TEXT NOT NULL DEFAULT 'up_to_date'
        CHECK (told_standing IN ('up_to_date', 'behind', 'suspended')),
    created_by     UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pass_holders_user ON pass_holders (user_id, club_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pass_holders_one_open
    ON pass_holders (plan_id, user_id) WHERE cancelled_at IS NULL;

-- MARK: bills that aren't for a session

ALTER TABLE event_bills ALTER COLUMN event_id DROP NOT NULL;
ALTER TABLE event_bills
    ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'event'
        CHECK (kind IN ('event', 'pass', 'collection')),
    ADD COLUMN IF NOT EXISTS pass_holder_id UUID REFERENCES pass_holders(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS period_start DATE,
    ADD COLUMN IF NOT EXISTS due_on DATE;
ALTER TABLE event_bills DROP CONSTRAINT IF EXISTS event_bills_kind_shape;
ALTER TABLE event_bills ADD CONSTRAINT event_bills_kind_shape CHECK (
    (kind = 'event' AND event_id IS NOT NULL)
    OR (kind = 'pass' AND event_id IS NULL AND pass_holder_id IS NOT NULL AND period_start IS NOT NULL)
    OR (kind = 'collection' AND event_id IS NULL)
);
-- A session everybody's pass covers still gets its bill, for the record —
-- one that collects nothing.
ALTER TABLE event_bills DROP CONSTRAINT IF EXISTS event_bills_total_cents_check;
ALTER TABLE event_bills ADD CONSTRAINT event_bills_total_cents_check CHECK (total_cents >= 0);
-- One charge per pass per month, however often the scheduler looks.
CREATE UNIQUE INDEX IF NOT EXISTS idx_event_bills_pass_period
    ON event_bills (pass_holder_id, period_start) WHERE kind = 'pass' AND status = 'issued';

-- MARK: covered shares

ALTER TABLE bill_shares DROP CONSTRAINT IF EXISTS bill_shares_status_check;
ALTER TABLE bill_shares
    ADD CONSTRAINT bill_shares_status_check CHECK (status IN ('live', 'waived', 'void', 'covered'));
ALTER TABLE bill_shares
    ADD COLUMN IF NOT EXISTS covered_by UUID REFERENCES pass_holders(id) ON DELETE SET NULL;
-- Sessions a bundle has used: covered shares on bills still standing.
CREATE INDEX IF NOT EXISTS idx_bill_shares_covered ON bill_shares (covered_by) WHERE status = 'covered';

-- MARK: paying for others

-- A member somebody else pays for: a junior by their parent. The payer sees
-- and pays the member's dues as well as their own.
CREATE TABLE IF NOT EXISTS club_payers (
    club_id    UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    member_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payer_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (club_id, member_id),
    CHECK (member_id <> payer_id)
);
CREATE INDEX IF NOT EXISTS idx_club_payers_payer ON club_payers (payer_id, club_id);

-- A member with no sign-in of their own (a young junior), looked after by
-- somebody who has one. They have no email, phone or password, so nobody can
-- sign in as them.
ALTER TABLE users ADD COLUMN IF NOT EXISTS managed_by UUID REFERENCES users(id) ON DELETE SET NULL;

-- Who paid, when it was somebody else: "paid by Neha Gill".
ALTER TABLE member_payments
    ADD COLUMN IF NOT EXISTS paid_by UUID REFERENCES users(id) ON DELETE SET NULL;
