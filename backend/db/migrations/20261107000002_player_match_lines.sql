-- What each player did in each match.
--
-- The season tables hold totals, and a total cannot say whether somebody is
-- getting better. "Your last five innings", a best-ever score with the day it
-- came, the first fifty, a strike rate that went up since last summer — all
-- of it needs the match the number came from. One row per player per match,
-- written by the same step that folds the match into the season, and filled
-- in for matches already played by the scheduler (`backfill_match_lines`).
CREATE TABLE IF NOT EXISTS player_match_lines (
    match_id        UUID NOT NULL REFERENCES cricket_matches(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_id        UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    -- The club they played *for*: the one of the two sides they are a member
    -- of. The season table credits both XIs to the scoring club, so the
    -- opposition's players landed on its leaderboard; a line knows better.
    club_id         UUID REFERENCES clubs(id) ON DELETE SET NULL,
    sport           TEXT NOT NULL DEFAULT 'cricket',
    season_year     INT NOT NULL,
    played_at       TIMESTAMPTZ NOT NULL,
    opposition      TEXT NOT NULL DEFAULT '',
    -- NULL for a tie or no result.
    won             BOOLEAN,

    batting_innings INT NOT NULL DEFAULT 0,
    not_outs        INT NOT NULL DEFAULT 0,
    runs            INT NOT NULL DEFAULT 0,
    balls_faced     INT NOT NULL DEFAULT 0,
    fours           INT NOT NULL DEFAULT 0,
    sixes           INT NOT NULL DEFAULT 0,
    -- The best single innings in the match, and whether it was unbeaten:
    -- 64* is not the same as 64.
    high_score      INT,
    high_score_not_out BOOLEAN NOT NULL DEFAULT FALSE,
    fifties         INT NOT NULL DEFAULT 0,
    hundreds        INT NOT NULL DEFAULT 0,
    ducks           INT NOT NULL DEFAULT 0,

    bowling_balls   INT NOT NULL DEFAULT 0,
    bowling_runs    INT NOT NULL DEFAULT 0,
    wickets         INT NOT NULL DEFAULT 0,
    maidens         INT NOT NULL DEFAULT 0,

    catches         INT NOT NULL DEFAULT 0,
    stumpings       INT NOT NULL DEFAULT 0,
    player_of_match BOOLEAN NOT NULL DEFAULT FALSE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (match_id, user_id)
);

CREATE INDEX IF NOT EXISTS player_match_lines_user
    ON player_match_lines (user_id, played_at DESC);
CREATE INDEX IF NOT EXISTS player_match_lines_club_season
    ON player_match_lines (club_id, season_year);

-- Set once a match's lines are written, so the backfill never looks at it
-- again — including a match with nobody in it who has an account.
ALTER TABLE cricket_matches
    ADD COLUMN IF NOT EXISTS lines_recorded_at TIMESTAMPTZ;
