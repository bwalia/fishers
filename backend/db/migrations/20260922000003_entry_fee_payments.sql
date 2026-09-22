-- A tournament could say what a side pays to enter and had no way to take it.
-- `entry_fee_cents` was stored, validated, and shown to the club being asked,
-- and there the trail ended.
--
-- A payment already knows how to be for a fixture or for an order. This makes
-- it able to be for an entry as well, rather than inventing a second kind of
-- payment with its own webhook and its own settling.

ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS entrant_id UUID
        REFERENCES tournament_entrants(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS payments_entrant ON payments (entrant_id)
    WHERE entrant_id IS NOT NULL;

ALTER TABLE tournament_entrants
    -- Set when the entry fee is settled, however it was settled: by card
    -- through Stripe, or by an organiser recording a cheque.
    ADD COLUMN IF NOT EXISTS entry_paid_at TIMESTAMPTZ,
    -- `card` | `cash` | `transfer` — what the organiser will be asked when the
    -- money does not come through the app, which for club cricket is most of
    -- the time.
    ADD COLUMN IF NOT EXISTS entry_payment_method TEXT;
