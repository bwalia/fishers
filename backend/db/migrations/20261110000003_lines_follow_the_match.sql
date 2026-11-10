-- A player's line for a match follows the match after it finishes.
--
-- Lines were written once, on the last ball. Three things happen after that:
-- the scorer gives player of the match (the award screen only appears once
-- there is a result, so no line ever had it), a correction to the card, and
-- members leaving the club, whose past matches the backfill then credited to
-- nobody. A line is now rewritten whenever a finished match is saved, and
-- credits the club the player played for even if they have left it since.
ALTER TABLE player_match_lines
    ADD COLUMN IF NOT EXISTS magic_moments INT NOT NULL DEFAULT 0;

-- Every finished match is read again from its scorecard by the scheduler's
-- backfill — a few hundred a tick — which repairs player of the match, club
-- credit and magic moments for the matches already played.
UPDATE cricket_matches SET lines_recorded_at = NULL WHERE lines_recorded_at IS NOT NULL;
