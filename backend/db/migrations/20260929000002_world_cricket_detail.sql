-- The scorecard behind a match, for the page you get when you tap one.
--
-- Costed differently from the list. Asking the feed for a date returns every
-- match being played anywhere for one request; asking it for a scorecard
-- returns one match for one request. So this is fetched only when somebody
-- actually opens a match, and:
--
--   * a finished scorecard is fetched once and marked `final` — it cannot
--     change again, so it is never fetched twice;
--   * ten people opening the same live match cost one request, not ten,
--     because the claim to refresh is a single atomic UPDATE;
--   * it gives way to the list when the day's allowance runs low, so the thing
--     everybody sees keeps working even when the thing one person opened does
--     not.
--
-- Stored as one JSONB document rather than five tables of rows. Nothing ever
-- queries inside it — it is written whole and read whole, one row per match —
-- and the shape is already parsed into our own types before it lands here, so
-- a change at the feed's end fails in the parser rather than leaking into a
-- schema.
CREATE TABLE IF NOT EXISTS world_cricket_match_details (
    match_id   TEXT PRIMARY KEY REFERENCES world_cricket_matches(id) ON DELETE CASCADE,
    -- A `WorldMatchDetail`, ours not theirs.
    detail     JSONB NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- The match is over and this card is the final one. Never fetched again.
    final      BOOLEAN NOT NULL DEFAULT FALSE
);

-- The poller's question when it prunes, and the page's when it decides whether
-- a refresh is due.
CREATE INDEX IF NOT EXISTS world_cricket_match_details_fetched
    ON world_cricket_match_details (fetched_at)
 WHERE NOT final;
