-- Whether the price is the price.
--
-- Second-hand kit is haggled over. A club asking £45 for last season's bat
-- usually means "£45, or make me an offer", and a buyer who cannot tell which
-- either pays over the odds or does not ask. A new bat the club made is the
-- price on the label.
ALTER TABLE products
    -- FALSE is "that is the price". Existing rows are all fixed-price, which
    -- is what they were sold as.
    ADD COLUMN IF NOT EXISTS negotiable BOOLEAN NOT NULL DEFAULT FALSE;

-- Only kit leaves the club. Match-day catering and hire are for the people who
-- are already there, and a national listing for a cup of tea helps nobody.
-- Enforced rather than left to the form: a listing that escapes its category
-- is a listing somebody has to explain.
ALTER TABLE products
    ADD CONSTRAINT products_public_is_kit
    CHECK (NOT listed_publicly OR category IN ('equipment', 'merchandise'))
    NOT VALID;

-- Anything already public that is not kit comes back in, then the rule is
-- validated against what is left.
UPDATE products
   SET listed_publicly = FALSE
 WHERE listed_publicly AND category NOT IN ('equipment', 'merchandise');

ALTER TABLE products VALIDATE CONSTRAINT products_public_is_kit;
