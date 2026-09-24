-- Umpiring is a thing a player does, and a thing they can be good at.
--
-- A club side umpires its own matches: the batting side gives two, or the
-- square-leg umpire is whoever is next in. The app already knew who stood —
-- `cricket_match_officials` has carried `role = 'umpire'` since September —
-- but it was a fact about one match and nothing carried it forward. Nobody
-- could see that somebody had stood in eleven matches, and nobody could say
-- whether they were any good at it.
--
-- Two additions. A player says they umpire, so a captain looking for one can
-- find them. And the players in a match can say how the umpiring went, once,
-- afterwards.

-- 1. Willingness, which is not the same as having done it. Somebody who has
--    stood twenty times but will not stand again should not appear in the list
--    a captain picks from, and somebody who has never stood should.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS umpires BOOLEAN NOT NULL DEFAULT FALSE,
    -- Free text: "Level 1 ECB", "club matches only", "not behind the stumps".
    -- Deliberately not an enum — umpiring qualifications differ by country and
    -- this app is in two of them already.
    ADD COLUMN IF NOT EXISTS umpire_note TEXT;

CREATE INDEX IF NOT EXISTS users_umpires ON users (umpires) WHERE umpires;

-- 2. What the players thought.
CREATE TABLE IF NOT EXISTS cricket_umpire_reviews (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id    UUID NOT NULL REFERENCES cricket_matches(id) ON DELETE CASCADE,
    umpire_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- One to five. Five points is what people expect to be asked for, and a
    -- finer scale would imply a precision nobody standing at square leg has.
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    -- Optional, and the useful half: "gave everything, explained the wides"
    -- tells the next captain more than a four does.
    comment     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One review per player, per umpire, per match. A player may change their
    -- mind; they may not vote twice.
    UNIQUE (match_id, umpire_id, reviewer_id),
    -- Nobody reviews themselves. Enforced here rather than in the handler,
    -- because a check in one of four call sites is a check in none of them.
    CONSTRAINT cricket_umpire_reviews_not_self CHECK (umpire_id <> reviewer_id)
);

-- The two reads: an umpire's own page, and "have I already reviewed this one".
CREATE INDEX IF NOT EXISTS cricket_umpire_reviews_umpire
    ON cricket_umpire_reviews (umpire_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cricket_umpire_reviews_match
    ON cricket_umpire_reviews (match_id);
