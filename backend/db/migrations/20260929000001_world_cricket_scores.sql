-- Scores from the wider game: the internationals and the domestic competitions
-- people follow while they are waiting for their own side to bat.
--
-- The whole design here is shaped by one number. The feed we read costs
-- nothing and allows 100 requests a day — for the entire deployment, not per
-- person. So nothing here is fetched on demand: a background job reads the
-- feed a handful of times an hour and writes what it finds into these tables,
-- and every request anybody makes is answered from Postgres. The upstream
-- service is never in the path of a page load, which is also why a rate limit
-- shared by every user is survivable at all.
--
-- The second half of the saving is that most of this never changes again. A
-- finished match is finished forever, and a day whose matches have all ended
-- is marked settled and never asked about again. Only play still going on is
-- worth spending a request on.

-- One row per match, with its teams, league and country written in rather than
-- referenced.
--
-- Normalising the teams out would be tidier and would save nothing that
-- matters: the feed returns a match with its teams already attached, so a
-- teams table would save a few hundred bytes and not one single request. Bytes
-- are not what is scarce here.
CREATE TABLE IF NOT EXISTS world_cricket_matches (
    -- The feed's own id, so re-reading a day updates rather than duplicates.
    id              TEXT PRIMARY KEY,

    league_name     TEXT NOT NULL,
    league_season   INTEGER,

    home_team_name  TEXT NOT NULL,
    home_team_short TEXT,
    home_team_logo  TEXT,
    away_team_name  TEXT NOT NULL,
    away_team_short TEXT,
    away_team_logo  TEXT,

    country_code    TEXT,
    country_name    TEXT,

    -- T20 / ODI / TEST, and whether it runs over more than one day.
    format          TEXT,
    day_type        TEXT,

    start_time      TIMESTAMPTZ,
    start_date      DATE NOT NULL,
    end_date        DATE,

    -- What the feed calls it: 'In play', 'Tea', 'Stumps', 'Finished' and so
    -- on. Kept verbatim because it is worth showing — "Tea" tells a reader
    -- something that "live" does not.
    state           TEXT NOT NULL,
    -- Our own bucket for that state: 'live', 'pending' or 'done'. Derived when
    -- the row is written so that both the poller and every query can ask the
    -- cheap question ("is anything actually on?") without a twelve-way CASE.
    phase           TEXT NOT NULL,
    -- The feed's sentence about the match: "Day 2 - Hindukush trail by 79
    -- runs.", "India won by 8 wkts".
    report          TEXT,

    -- Scores are the feed's own strings, not numbers. A Test innings reads
    -- "128 & 59/5" and an over count reads "84.4 ov"; parsing those into
    -- integers would be throwing away the only format that is correct for
    -- every one of the three formats.
    home_score      TEXT,
    home_info       TEXT,
    away_score      TEXT,
    away_info       TEXT,

    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The three questions the API asks: what is on now, what is coming, what just
-- finished.
CREATE INDEX IF NOT EXISTS world_cricket_matches_phase_start
    ON world_cricket_matches (phase, start_time);
-- Re-reading a day replaces that day's rows, and the poller asks which days
-- still hold live play.
CREATE INDEX IF NOT EXISTS world_cricket_matches_start_date
    ON world_cricket_matches (start_date);

-- What we have asked the feed about, and whether we ever need to again.
CREATE TABLE IF NOT EXISTS world_cricket_days (
    day          DATE PRIMARY KEY,
    fetched_at   TIMESTAMPTZ,
    -- The day is over and every match on it has ended. Nothing about it can
    -- change, so it is never fetched again — this is what stops yesterday's
    -- cricket costing anything today.
    settled      BOOLEAN NOT NULL DEFAULT FALSE,
    match_count  INTEGER NOT NULL DEFAULT 0
);

-- The day's allowance, and what we have spent of it.
--
-- A row per UTC day. Whether the provider's own quota resets at midnight UTC
-- or rolls over 24 hours is not documented, so this is deliberately the
-- conservative reading of it; every response also carries the true figure in
-- `x-ratelimit-requests-remaining`, and the poller writes that back here, so a
-- wrong guess corrects itself on the first call of the day rather than
-- overspending.
CREATE TABLE IF NOT EXISTS world_cricket_budget (
    day                DATE PRIMARY KEY,
    spent              INTEGER NOT NULL DEFAULT 0,
    -- Straight from the provider's header: the truth, when we have it.
    upstream_remaining INTEGER,
    -- When somebody last actually looked at the scores. The poller reads the
    -- feed often while people are watching and rarely when they are not,
    -- which is what makes a hundred requests stretch across a day of cricket.
    watched_at         TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
