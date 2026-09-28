-- The shop becomes somewhere a club can sell its kit, new and second-hand.
--
-- A club that has just bought a new set of pads has the old set in a cupboard,
-- and a club that makes its own bats has nobody to sell them to but its own
-- thirty members. Both want the same thing: a listing with a photograph, an
-- honest description of what state it is in, and somebody to come and collect
-- it.
--
-- Money is settled in person. That is a deliberate choice, not a gap: there is
-- no Stripe Connect here, so an online payment for another club's bat would
-- land in the platform's own account and leave us owing them the money. A
-- listing is an advert and a reservation; the cash is between the two clubs.

-- 1. What state the thing is in. The whole point of the second-hand half.
DO $$ BEGIN
    CREATE TYPE product_condition AS ENUM ('new', 'used');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE products
    -- NULL for the things this does not apply to — a cup of tea is neither new
    -- nor used. Only kit carries a condition, and only kit shows one.
    ADD COLUMN IF NOT EXISTS condition product_condition,
    -- "Light wear on the toe, no cracks." The sentence that decides whether
    -- somebody drives an hour to look at it.
    ADD COLUMN IF NOT EXISTS condition_note TEXT,
    -- Short Handle, Harrow, Youth Large. Free text on purpose: bat sizes,
    -- pad sizes and glove sizes share no vocabulary, and an enum here would be
    -- wrong for two of the three by the end of the week.
    ADD COLUMN IF NOT EXISTS size TEXT,
    ADD COLUMN IF NOT EXISTS brand TEXT,
    -- Object-storage keys, in the order they should be shown. Nobody buys a
    -- second-hand bat they cannot see.
    ADD COLUMN IF NOT EXISTS photos TEXT[] NOT NULL DEFAULT '{}',
    -- Whether it appears outside the club. A club selling kit needs a bigger
    -- room than its own membership; the tea urn does not.
    ADD COLUMN IF NOT EXISTS listed_publicly BOOLEAN NOT NULL DEFAULT FALSE,
    -- Who to ask. Falls back to the club's own contact when empty.
    ADD COLUMN IF NOT EXISTS collection_note TEXT;

-- Existing rows: kit goes out to the marketplace, match-day catering stays in
-- the clubhouse where it belongs.
UPDATE products
   SET listed_publicly = TRUE
 WHERE category IN ('equipment', 'merchandise')
   AND active;

-- The marketplace's own query: what is on sale, newest first.
CREATE INDEX IF NOT EXISTS products_marketplace
    ON products (created_at DESC)
 WHERE listed_publicly AND active;

-- 2. Stock has been a number nobody enforced.
--
-- `place_order` read the product, summed the price and wrote the line — and
-- never touched `stock`. With a shop of teas and caps that is untidy. With
-- second-hand kit, where almost everything is a quantity of one, it means the
-- same bat is sold to everybody who asks. The decrement is in the order
-- transaction now; this makes the column honest about what it is.
ALTER TABLE products
    ADD CONSTRAINT products_stock_not_negative CHECK (stock IS NULL OR stock >= 0)
    NOT VALID;

-- NOT VALID, then validated: existing rows are checked without taking an
-- ACCESS EXCLUSIVE lock on a table the shop is reading.
ALTER TABLE products VALIDATE CONSTRAINT products_stock_not_negative;
