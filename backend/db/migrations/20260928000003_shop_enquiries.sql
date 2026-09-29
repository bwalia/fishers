-- Talking to whoever is selling the thing.
--
-- Two gaps. A product had no author at all — only a club — so "message the
-- person who posted this" had nobody to point at. And a direct conversation
-- requires a shared club, which is right for the app in general and wrong for
-- exactly this case: the whole point of the marketplace is that somebody at
-- another club sees the bat.

-- 1. Who put it up. NULL for everything listed before this existed; the
--    enquiry falls back to the club's officers, who could have listed it.
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS listed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    -- Whether to print the seller's own email and number on the listing.
    -- Off unless asked for: a phone number shown to every signed-in person is
    -- not a thing to switch on for somebody by default.
    ADD COLUMN IF NOT EXISTS show_contact BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS products_listed_by ON products (listed_by);

-- 2. A conversation can be about a listing.
--
--    This is what makes a stranger's message legitimate: not "anybody may
--    message anybody", but "the person selling this put it in front of the
--    whole app, so somebody may ask them about it". The general rule that a
--    direct thread needs a shared club is untouched.
--    SET NULL rather than CASCADE: if a listing ever does go, what two people
--    said to each other about it should not go with it. The thread keeps its
--    title, which is the name of the thing they were discussing.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(id) ON DELETE SET NULL;

-- One thread per buyer per listing. A second enquiry continues the first
-- rather than starting a thread nobody reads.
CREATE UNIQUE INDEX IF NOT EXISTS conversations_product_buyer
    ON conversations (product_id, created_by)
 WHERE product_id IS NOT NULL;
