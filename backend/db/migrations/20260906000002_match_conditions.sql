-- The terms two captains agree before a ball is bowled, and the bookkeeping
-- that stops a completed match being counted into the season twice.

ALTER TABLE cricket_matches
    -- 'open' | 'boxed' | 'indoor'
    ADD COLUMN IF NOT EXISTS ground_type      TEXT NOT NULL DEFAULT 'open',
    -- 'red' | 'white' | 'pink' | 'tennis' | 'tape'
    ADD COLUMN IF NOT EXISTS ball_type        TEXT NOT NULL DEFAULT 'white',
    -- 0 means no limit; the default is a fifth of the innings, rounded up.
    ADD COLUMN IF NOT EXISTS overs_per_bowler INT  NOT NULL DEFAULT 4,
    -- The captain who agreed, by name: the away captain rarely has an account.
    ADD COLUMN IF NOT EXISTS agreed_home      TEXT,
    ADD COLUMN IF NOT EXISTS agreed_away      TEXT,
    -- Set the first time a finished match is folded into the season, so a
    -- resync or a replayed batch cannot count it again.
    ADD COLUMN IF NOT EXISTS stats_recorded_at TIMESTAMPTZ;

-- Season aggregates written from scoring live alongside the manual and
-- Play-Cricket rows, because `source` is part of the unique key.
COMMENT ON COLUMN player_season_stats.source IS
    'manual | play_cricket | fishers_scoring — scoring writes its own row so it never fights an import';
