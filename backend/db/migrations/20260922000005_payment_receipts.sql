-- What a payment actually was, not only that it happened.
--
-- `payments` recorded an amount and a status. A treasurer reconciling a bank
-- statement wants the rest of it: who paid, on what card, and the receipt to
-- forward when somebody asks. All of it arrives on Stripe's `charge.*` events
-- and was being thrown away.

ALTER TABLE payments
    -- Stripe's own receipt page. The thing to send somebody who asks for one.
    ADD COLUMN IF NOT EXISTS receipt_url TEXT,
    -- Who paid, as they gave it to Stripe. Not necessarily the account holder:
    -- a club secretary often pays for a side on somebody else's card.
    ADD COLUMN IF NOT EXISTS payer_email TEXT,
    -- visa | mastercard | amex …, and the last four. Enough to match a line on
    -- a statement, and not enough to be worth stealing.
    ADD COLUMN IF NOT EXISTS card_brand TEXT,
    ADD COLUMN IF NOT EXISTS card_last4 TEXT,
    -- When the money actually landed, as distinct from when this row was last
    -- touched for any reason.
    ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ,
    -- Stripe's words for a refusal — "insufficient funds", "card declined" —
    -- so somebody can be told why rather than just that it did not work.
    ADD COLUMN IF NOT EXISTS failure_reason TEXT;

-- "What came in this month", for a club's own reconciliation.
CREATE INDEX IF NOT EXISTS payments_settled ON payments (settled_at)
    WHERE settled_at IS NOT NULL;
