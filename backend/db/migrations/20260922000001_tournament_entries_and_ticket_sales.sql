-- Two things the tournament and ticket code could not express:
--
--   1. Inviting a *club* into a tournament. Entrants were free text an
--      organiser typed in, so the other club never saw the invitation, could
--      not accept it, and the entry was never linked to their real squad.
--      `tournament_entrants` already had `club_id` and `contact_email`; nothing
--      ever wrote them.
--
--   2. Selling a ticket to somebody who is not a member of the hosting club.
--      A tournament's spectators are, by definition, mostly not.

-- MARK: entries

-- An entrant row is now the invitation as well as the entry. One table, so
-- there is no invite/entrant pair to keep in step.
--
--   invited  — asked, hasn't answered
--   accepted — in the draw (an organiser typing a name lands here directly)
--   declined — said no
--   withdrawn — was in, pulled out
ALTER TABLE tournament_entrants
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'accepted'
        CHECK (status IN ('invited', 'accepted', 'declined', 'withdrawn')),
    ADD COLUMN IF NOT EXISTS invited_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS responded_at TIMESTAMPTZ,
    -- A club with no Fishers account is invited by email; the token is the
    -- link they follow. Null for in-app invites, which are addressed to a club.
    ADD COLUMN IF NOT EXISTS invite_token TEXT;

-- Carry the old boolean over before it stops being a column of its own.
UPDATE tournament_entrants SET status = 'withdrawn' WHERE withdrawn;

-- `withdrawn` is read by the standings view, the API, both apps and the web
-- UI. Rather than change all of them, it becomes a view onto `status` — so
-- there is exactly one source of truth and every existing reader still works.
DROP VIEW IF EXISTS tournament_standings;
ALTER TABLE tournament_entrants DROP COLUMN withdrawn;
ALTER TABLE tournament_entrants
    ADD COLUMN withdrawn BOOLEAN NOT NULL
        GENERATED ALWAYS AS (status = 'withdrawn') STORED;

-- `UNIQUE (block_id, name)` meant two clubs called "Wanderers" could not both
-- enter, and the ON CONFLICT that relied on it silently overwrote the first.
-- A club enters once; free-text sides are still unique by name among
-- themselves, case-insensitively, because "Hemel CC" and "hemel cc" are one side.
ALTER TABLE tournament_entrants DROP CONSTRAINT IF EXISTS tournament_entrants_block_id_name_key;

CREATE UNIQUE INDEX IF NOT EXISTS tournament_entrants_block_club
    ON tournament_entrants (block_id, club_id) WHERE club_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS tournament_entrants_block_name
    ON tournament_entrants (block_id, lower(name)) WHERE club_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS tournament_entrants_token
    ON tournament_entrants (invite_token) WHERE invite_token IS NOT NULL;

-- "Which tournaments has my club been asked into" — the invited club's screen.
CREATE INDEX IF NOT EXISTS tournament_entrants_club_status
    ON tournament_entrants (club_id, status) WHERE club_id IS NOT NULL;

-- Rebuilt unchanged except that only accepted sides have a table place. An
-- invited side that never answered is not a team on nought points.
CREATE VIEW tournament_standings AS
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
WHERE en.status = 'accepted'
GROUP BY en.block_id, en.id, en.name, en.group_label;

-- MARK: ticket sales

-- Off by default, so every event that exists today keeps behaving exactly as
-- it does: members of the hosting club only. On, any signed-in Fishers user
-- may buy — which is what a tournament, a finals day or a fundraiser needs.
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS tickets_public BOOLEAN NOT NULL DEFAULT FALSE;

-- The booking screen has to know whether it may offer a ticket to a
-- non-member. Dropped and recreated rather than replaced: CREATE OR REPLACE
-- can only append columns, and this one belongs beside the other ticket rules.
DROP VIEW IF EXISTS event_ticket_summary;
CREATE VIEW event_ticket_summary AS
SELECT e.id                                              AS event_id,
       e.title,
       e.ticket_capacity,
       e.ticket_price_cents,
       e.guests_allowed,
       e.tickets_public,
       COUNT(t.id) FILTER (WHERE t.status <> 'cancelled') AS bookings,
       COALESCE(SUM(1 + t.guests) FILTER (WHERE t.status <> 'cancelled'), 0) AS headcount,
       COALESCE(SUM(t.amount_cents) FILTER (WHERE t.status = 'paid'), 0)     AS collected_cents,
       COALESCE(SUM(t.amount_cents) FILTER (WHERE t.status = 'reserved'), 0) AS outstanding_cents
FROM events e
LEFT JOIN event_tickets t ON t.event_id = e.id
GROUP BY e.id, e.title, e.ticket_capacity, e.ticket_price_cents, e.guests_allowed,
         e.tickets_public;

-- MARK: webhook idempotency

-- Stripe retries a webhook until it gets a 2xx, and re-sends on its own
-- schedule besides. Without this, a retried `payment_intent.succeeded` settled
-- the same ticket twice and wrote a second payment row against it.
CREATE TABLE IF NOT EXISTS payment_webhook_events (
    -- Stripe's own `evt_…` id. Primary key: the second delivery loses the race
    -- in the database rather than in application code.
    event_id     TEXT PRIMARY KEY,
    payment_id   UUID REFERENCES payments(id) ON DELETE SET NULL,
    kind         TEXT,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
