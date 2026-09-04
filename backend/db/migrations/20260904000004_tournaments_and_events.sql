-- Two things a club calendar can't currently express:
--   1. A run tournament — entrants, groups, a schedule across pitches and time
--      slots, results and a table.
--   2. Club events that aren't fixtures — presentation nights, AGMs, ticketed
--      socials, and tours with travel and accommodation.
--
-- Both hang off fixture_blocks, which already models "a tour / tournament /
-- the next few weeks", so squad selection keeps working inside them.

ALTER TABLE fixture_blocks
    ADD COLUMN IF NOT EXISTS format TEXT NOT NULL DEFAULT 'none'
        CHECK (format IN ('none', 'round_robin', 'groups_knockout', 'knockout', 'ladder')),
    ADD COLUMN IF NOT EXISTS group_count INT,
    -- League points, per sport convention: cricket often 2/1/1, football 3/1/0.
    ADD COLUMN IF NOT EXISTS points_win       INT NOT NULL DEFAULT 2,
    ADD COLUMN IF NOT EXISTS points_draw      INT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS points_no_result INT NOT NULL DEFAULT 1,
    -- Tour logistics: the details that otherwise live in someone's head.
    ADD COLUMN IF NOT EXISTS meet_point           TEXT,
    ADD COLUMN IF NOT EXISTS departs_at           TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS travel_notes         TEXT,
    ADD COLUMN IF NOT EXISTS accommodation_notes  TEXT,
    ADD COLUMN IF NOT EXISTS cost_cents           INT;

-- Who is playing in the tournament. An entrant may be one of our own teams, or
-- a visiting side that has no account here.
CREATE TABLE IF NOT EXISTS tournament_entrants (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    block_id      UUID NOT NULL REFERENCES fixture_blocks(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    club_id       UUID REFERENCES clubs(id) ON DELETE SET NULL,
    team_id       UUID REFERENCES teams(id) ON DELETE SET NULL,
    seed          INT,
    group_label   TEXT,
    contact_name  TEXT,
    contact_email TEXT,
    withdrawn     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (block_id, name)
);

CREATE INDEX IF NOT EXISTS idx_entrants_block ON tournament_entrants (block_id, group_label);

-- The grid: a pitch or court at a time. Fixtures are dropped into these.
CREATE TABLE IF NOT EXISTS tournament_slots (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    block_id    UUID NOT NULL REFERENCES fixture_blocks(id) ON DELETE CASCADE,
    venue_id    UUID REFERENCES venues(id) ON DELETE SET NULL,
    -- "Pitch 1", "Court 3", "Main square".
    court_label TEXT NOT NULL DEFAULT 'Pitch 1',
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    event_id    UUID REFERENCES events(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ends_at > starts_at),
    UNIQUE (block_id, court_label, starts_at)
);

CREATE INDEX IF NOT EXISTS idx_slots_block ON tournament_slots (block_id, starts_at);

-- Which entrants a fixture is between, and how it finished. Two rows for a
-- normal match; more for americano-style formats later.
CREATE TABLE IF NOT EXISTS event_entrants (
    event_id   UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    entrant_id UUID NOT NULL REFERENCES tournament_entrants(id) ON DELETE CASCADE,
    side       TEXT NOT NULL DEFAULT 'home' CHECK (side IN ('home', 'away', 'entrant')),
    score      INT,
    -- Cricket wants more than a score line; keep the detail alongside it.
    score_detail JSONB,
    result     TEXT CHECK (result IN ('win', 'loss', 'draw', 'no_result')),
    points     INT,
    PRIMARY KEY (event_id, entrant_id)
);

CREATE INDEX IF NOT EXISTS idx_event_entrants_entrant ON event_entrants (entrant_id);

-- Ticketed club events: presentation nights, socials, tour dinners.
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS ticket_price_cents INT,
    ADD COLUMN IF NOT EXISTS ticket_capacity    INT,
    -- How many guests one member may bring; 0 means members only.
    ADD COLUMN IF NOT EXISTS guests_allowed     INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS rsvp_deadline      TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS event_tickets (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id     UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Places taken beyond the member's own.
    guests       INT NOT NULL DEFAULT 0 CHECK (guests >= 0),
    guest_names  TEXT,
    amount_cents INT NOT NULL DEFAULT 0,
    currency     TEXT NOT NULL DEFAULT 'GBP',
    status       TEXT NOT NULL DEFAULT 'reserved'
        CHECK (status IN ('reserved', 'paid', 'cancelled')),
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_tickets_event ON event_tickets (event_id, status);

-- Headcount and money for a ticketed event, in one row.
CREATE OR REPLACE VIEW event_ticket_summary AS
SELECT e.id                                              AS event_id,
       e.title,
       e.ticket_capacity,
       e.ticket_price_cents,
       COUNT(t.id) FILTER (WHERE t.status <> 'cancelled') AS bookings,
       COALESCE(SUM(1 + t.guests) FILTER (WHERE t.status <> 'cancelled'), 0) AS headcount,
       COALESCE(SUM(t.amount_cents) FILTER (WHERE t.status = 'paid'), 0)     AS collected_cents,
       COALESCE(SUM(t.amount_cents) FILTER (WHERE t.status = 'reserved'), 0) AS outstanding_cents
FROM events e
LEFT JOIN event_tickets t ON t.event_id = e.id
GROUP BY e.id;

-- The tournament table, straight out of recorded results.
CREATE OR REPLACE VIEW tournament_standings AS
SELECT en.block_id,
       en.id                                                    AS entrant_id,
       en.name,
       en.group_label,
       COUNT(ee.event_id) FILTER (WHERE ee.result IS NOT NULL)  AS played,
       COUNT(ee.event_id) FILTER (WHERE ee.result = 'win')      AS won,
       COUNT(ee.event_id) FILTER (WHERE ee.result = 'loss')     AS lost,
       COUNT(ee.event_id) FILTER (WHERE ee.result = 'draw')     AS drawn,
       COUNT(ee.event_id) FILTER (WHERE ee.result = 'no_result') AS no_result,
       COALESCE(SUM(ee.points), 0)                              AS points,
       COALESCE(SUM(ee.score), 0)                               AS scored,
       COALESCE((
           SELECT SUM(opp.score)
           FROM event_entrants opp
           WHERE opp.entrant_id <> en.id
             AND opp.event_id IN (
                 SELECT event_id FROM event_entrants WHERE entrant_id = en.id
             )
       ), 0)                                                    AS conceded
FROM tournament_entrants en
LEFT JOIN event_entrants ee ON ee.entrant_id = en.id
WHERE NOT en.withdrawn
GROUP BY en.block_id, en.id, en.name, en.group_label;
