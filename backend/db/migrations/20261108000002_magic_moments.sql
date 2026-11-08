-- How often a player made the ball a match turned on.
--
-- Counted when a scored match is folded into the season, the same once-only
-- moment as runs and wickets. Matches recorded before this column existed are
-- not counted back: the turning point is worked out from the ball-by-ball log
-- by the engine, which SQL cannot replay.
ALTER TABLE player_season_stats
    ADD COLUMN IF NOT EXISTS magic_moments INT NOT NULL DEFAULT 0;
