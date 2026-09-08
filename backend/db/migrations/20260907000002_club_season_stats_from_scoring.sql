-- The club season board was only ever filled by the Play-Cricket sync, so a club
-- that scores its own matches in Fishers saw "Played 0" however many it played.
-- `record_match_outcomes` now folds each finished match in, which needs an
-- ON CONFLICT target that works for the club-wide row.
--
-- The table's UNIQUE (club_id, team_id, sport, season_year, source) does not
-- serve: team_id is nullable and Postgres treats NULLs as distinct, so two
-- club-wide rows could both be inserted and neither would conflict.
CREATE UNIQUE INDEX IF NOT EXISTS club_season_stats_clubwide_key
    ON club_season_stats (club_id, sport, season_year, source)
    WHERE team_id IS NULL;
