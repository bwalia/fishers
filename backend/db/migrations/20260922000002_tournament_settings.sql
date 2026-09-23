-- What a tournament actually needs settling before anybody enters it.
--
-- `fixture_blocks` could say its format and its points, and nothing else: not
-- how many sides fit, not when entries close, not how many overs, not what
-- colour the ball is, and not whether a side may borrow a player from another
-- club. Organisers were keeping all of it in the covering email.

ALTER TABLE fixture_blocks
    -- What it is, in the organiser's own words. Shown to a club deciding
    -- whether to enter.
    ADD COLUMN IF NOT EXISTS description TEXT,
    -- The main ground. Individual pitches still hang off tournament_slots,
    -- which is how a tournament runs across more than one.
    ADD COLUMN IF NOT EXISTS venue_id UUID REFERENCES venues(id) ON DELETE SET NULL,

    -- MARK: entry
    -- Null means no limit. Two is the smallest thing that can be a tournament.
    ADD COLUMN IF NOT EXISTS max_entrants INT
        CHECK (max_entrants IS NULL OR max_entrants >= 2),
    ADD COLUMN IF NOT EXISTS entry_deadline TIMESTAMPTZ,
    -- What a side pays to enter. Separate from a spectator's ticket and from
    -- the match fee a player owes.
    ADD COLUMN IF NOT EXISTS entry_fee_cents INT
        CHECK (entry_fee_cents IS NULL OR entry_fee_cents >= 0),

    -- MARK: who may play
    -- Eleven a side normally; six for sixes, eight for eights.
    ADD COLUMN IF NOT EXISTS players_per_side INT NOT NULL DEFAULT 11
        CHECK (players_per_side BETWEEN 2 AND 15),
    -- 0 means every player must be a member of the entering club — the usual
    -- rule, and the one clubs argue about on the day when nobody wrote it down.
    ADD COLUMN IF NOT EXISTS guest_players_allowed INT NOT NULL DEFAULT 0
        CHECK (guest_players_allowed BETWEEN 0 AND 11),
    ADD COLUMN IF NOT EXISTS age_group TEXT NOT NULL DEFAULT 'open'
        CHECK (age_group IN ('open', 'u11', 'u13', 'u15', 'u17', 'u19', 'veterans')),
    ADD COLUMN IF NOT EXISTS gender TEXT NOT NULL DEFAULT 'open'
        CHECK (gender IN ('open', 'men', 'women', 'mixed')),

    -- MARK: playing conditions
    -- A `MatchConditions` (domain/src/cricket/types.rs): overs, overs per
    -- bowler, ball, ground, powerplay, fielding restrictions. The same shape
    -- two captains agree before a one-off match, so a tournament sets it once
    -- and every fixture in it inherits the answer rather than each scorer
    -- typing it again. Null means the sport's default.
    ADD COLUMN IF NOT EXISTS conditions JSONB,
    -- Everything a form cannot hold: last-over rules, ties, super overs,
    -- boundary counts, whatever this tournament does differently.
    ADD COLUMN IF NOT EXISTS rules_notes TEXT;

-- "Which tournaments are still taking entries" — the organiser's own screen
-- and, later, an open-entry listing.
CREATE INDEX IF NOT EXISTS fixture_blocks_entry_deadline
    ON fixture_blocks (entry_deadline) WHERE entry_deadline IS NOT NULL;
