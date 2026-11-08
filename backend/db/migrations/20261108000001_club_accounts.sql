-- Club accounts: the books a treasurer keeps and takes to the AGM.
--
-- Who may open them is decided by two facts, not a role: owning the club
-- (`clubs.owner_id`) or being its treasurer. Treasurer is a flag on the
-- membership rather than a new `user_role` value, for two reasons:
--
--   * a small club's secretary is very often its treasurer too, and a
--     membership holds one role;
--   * phones already in people's hands decode `role` as a closed list. A value
--     they have never heard of fails the whole member list on iOS. An extra
--     key is ignored.
--
-- Money is integer minor units, as everywhere else. Nothing here is ever
-- deleted: a mistake is voided, with a reason, and stays in the audit trail.

ALTER TABLE club_members
    ADD COLUMN IF NOT EXISTS is_treasurer BOOLEAN NOT NULL DEFAULT false;

-- An accounting year. One open at a time; a closed one never moves.
CREATE TABLE IF NOT EXISTS club_account_periods (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id               UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    label                 TEXT NOT NULL,
    starts_on             DATE NOT NULL,
    ends_on               DATE NOT NULL,
    status                TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    currency              TEXT NOT NULL DEFAULT 'GBP',
    -- Balance b/f. For a club's first year in the app it is typed in; after
    -- that it is the previous year's c/f, copied when the year is opened.
    opening_balance_cents BIGINT NOT NULL DEFAULT 0,
    -- The treasurer's written report, and the signed statement under it.
    report_text           TEXT,
    statement_text        TEXT,
    signed_by_name        TEXT,
    signed_on             DATE,
    closed_at             TIMESTAMPTZ,
    closed_by             UUID REFERENCES users(id) ON DELETE SET NULL,
    created_by            UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ends_on > starts_on),
    UNIQUE (club_id, starts_on)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_account_periods_one_open
    ON club_account_periods (club_id) WHERE status = 'open';

-- Lines on the Income & Expenditure account. Archived, never deleted, so an
-- old year still prints with the categories it was kept in.
CREATE TABLE IF NOT EXISTS club_account_categories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN ('income', 'expenditure')),
    name        TEXT NOT NULL,
    -- What the app itself relies on: where fees paid in the app land, where a
    -- write-off goes, which line stock movement adjusts. NULL for the rest.
    system_key  TEXT,
    sort_order  INT  NOT NULL DEFAULT 0,
    footnote    TEXT,
    archived    BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (club_id, kind, name)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_account_categories_system
    ON club_account_categories (club_id, kind, system_key) WHERE system_key IS NOT NULL;

-- Where the money is: the bank, a cash tin, credit held with the nets venue.
CREATE TABLE IF NOT EXISTS club_money_accounts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('bank', 'cash', 'supplier_credit', 'provider')),
    sort_order  INT  NOT NULL DEFAULT 0,
    archived    BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (club_id, name)
);

-- Each account's opening figure for a year, and the figure the treasurer read
-- off the statement. The report prints the statement figure when there is
-- one, and says so when there isn't.
CREATE TABLE IF NOT EXISTS club_money_account_balances (
    account_id       UUID NOT NULL REFERENCES club_money_accounts(id) ON DELETE CASCADE,
    period_id        UUID NOT NULL REFERENCES club_account_periods(id) ON DELETE CASCADE,
    opening_cents    BIGINT NOT NULL DEFAULT 0,
    reconciled_cents BIGINT,
    reconciled_on    DATE,
    PRIMARY KEY (account_id, period_id)
);

-- Money in, money out, and the rare correction to last year's books.
--
-- `income` and `expenditure` carry a positive amount and a category.
-- `adjustment` is a prior-period adjustment: signed, no category, printed on
-- the balance sheet as its own line so it is never mistaken for trading.
-- A NULL money account means the line is an accrual (fees owed, cost share
-- owed) — the other side of it is a debtor or creditor, not the bank.
CREATE TABLE IF NOT EXISTS club_account_transactions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id            UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    period_id          UUID NOT NULL REFERENCES club_account_periods(id) ON DELETE CASCADE,
    occurred_on        DATE NOT NULL,
    kind               TEXT NOT NULL CHECK (kind IN ('income', 'expenditure', 'adjustment')),
    category_id        UUID REFERENCES club_account_categories(id),
    money_account_id   UUID REFERENCES club_money_accounts(id),
    amount_cents       BIGINT NOT NULL,
    description        TEXT NOT NULL,
    counterparty       TEXT,
    member_id          UUID REFERENCES users(id) ON DELETE SET NULL,
    event_id           UUID REFERENCES events(id) ON DELETE SET NULL,
    note               TEXT,
    receipt_url        TEXT,
    -- One-off spending a committee signed off, kept apart in the insights so
    -- "would we have made money without it" has an answer.
    extraordinary      BOOLEAN NOT NULL DEFAULT false,
    authorised_on      DATE,
    authorisation_ref  TEXT,
    -- Where the line came from when the app wrote it: a payment taken in the
    -- app, a debt written off. Unique among live lines, so nothing is counted
    -- twice.
    source             TEXT,
    source_ref         UUID,
    voided_at          TIMESTAMPTZ,
    voided_by          UUID REFERENCES users(id) ON DELETE SET NULL,
    void_reason        TEXT,
    created_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
        (kind IN ('income', 'expenditure') AND amount_cents > 0 AND category_id IS NOT NULL)
        OR (kind = 'adjustment' AND amount_cents <> 0 AND category_id IS NULL)
    )
);
CREATE INDEX IF NOT EXISTS idx_account_tx_period
    ON club_account_transactions (period_id, occurred_on) WHERE voided_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_account_tx_source
    ON club_account_transactions (club_id, source, source_ref)
    WHERE source IS NOT NULL AND voided_at IS NULL;

-- Owed to the club (debtor) or by it (creditor).
CREATE TABLE IF NOT EXISTS club_account_debts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id      UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    period_id    UUID NOT NULL REFERENCES club_account_periods(id) ON DELETE CASCADE,
    direction    TEXT NOT NULL CHECK (direction IN ('debtor', 'creditor')),
    kind         TEXT NOT NULL CHECK (kind IN ('member_fees', 'cost_share', 'other')),
    description  TEXT NOT NULL,
    counterparty TEXT,
    member_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    event_id     UUID REFERENCES events(id) ON DELETE SET NULL,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    raised_on    DATE NOT NULL,
    note         TEXT,
    -- The accrual line that put it in the books, when there is one.
    transaction_id UUID REFERENCES club_account_transactions(id),
    voided_at    TIMESTAMPTZ,
    created_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_account_debts_club ON club_account_debts (club_id, direction);
-- One debt per member per fixture, so the fees owed at year end can be raised
-- again without doubling.
CREATE UNIQUE INDEX IF NOT EXISTS idx_account_debts_member_event
    ON club_account_debts (club_id, member_id, event_id)
    WHERE member_id IS NOT NULL AND event_id IS NOT NULL AND voided_at IS NULL;

-- A debt paid, part paid, written off, or recovered short.
CREATE TABLE IF NOT EXISTS club_account_settlements (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id          UUID NOT NULL REFERENCES club_account_debts(id) ON DELETE CASCADE,
    period_id        UUID NOT NULL REFERENCES club_account_periods(id) ON DELETE CASCADE,
    settled_on       DATE NOT NULL,
    kind             TEXT NOT NULL CHECK (kind IN ('payment', 'write_off', 'shortfall')),
    amount_cents     BIGINT NOT NULL CHECK (amount_cents > 0),
    money_account_id UUID REFERENCES club_money_accounts(id),
    -- The payment taken in the app, when that is how it was paid.
    payment_id       UUID REFERENCES payments(id) ON DELETE SET NULL,
    note             TEXT,
    -- The expense line a write-off or shortfall posted.
    transaction_id   UUID REFERENCES club_account_transactions(id),
    voided_at        TIMESTAMPTZ,
    created_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (kind <> 'payment' OR money_account_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_account_settlements_debt ON club_account_settlements (debt_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_account_settlements_payment
    ON club_account_settlements (payment_id) WHERE payment_id IS NOT NULL AND voided_at IS NULL;

-- Stock: match balls first, anything else the club wants to count.
CREATE TABLE IF NOT EXISTS club_stock_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    archived    BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (club_id, name)
);

-- What was on the shelf at the end of a year, at cost. The opening figure is
-- the previous year's closing one; the difference moves the equipment line.
CREATE TABLE IF NOT EXISTS club_stock_counts (
    item_id     UUID NOT NULL REFERENCES club_stock_items(id) ON DELETE CASCADE,
    period_id   UUID NOT NULL REFERENCES club_account_periods(id) ON DELETE CASCADE,
    opening_quantity INT    NOT NULL DEFAULT 0 CHECK (opening_quantity >= 0),
    opening_cents    BIGINT NOT NULL DEFAULT 0 CHECK (opening_cents >= 0),
    closing_quantity INT    NOT NULL DEFAULT 0 CHECK (closing_quantity >= 0),
    closing_cents    BIGINT NOT NULL DEFAULT 0 CHECK (closing_cents >= 0),
    counted_on       DATE,
    PRIMARY KEY (item_id, period_id)
);

-- Every change to the books: who, what, when, and the row before and after.
CREATE TABLE IF NOT EXISTS club_account_audit (
    id          BIGSERIAL PRIMARY KEY,
    club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    actor_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    entity      TEXT NOT NULL,
    entity_id   UUID,
    before      JSONB,
    after       JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_account_audit_club ON club_account_audit (club_id, created_at DESC);
