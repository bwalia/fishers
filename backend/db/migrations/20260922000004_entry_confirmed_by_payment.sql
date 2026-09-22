-- A side that has said yes but not paid is not yet in the tournament.
--
-- Accepting put a club straight into the draw, whatever the entry fee said.
-- An organiser could therefore build a fixture list around sides who had not
-- paid and might never, and the table counted them from the start.
--
-- "Confirmed" is: accepted, and — where the tournament charges — paid. That
-- rule lives here, in the view and in the draw, because the organiser's screen
-- and the invited club's screen must not each decide it for themselves.

DROP VIEW IF EXISTS tournament_standings;

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
JOIN fixture_blocks fb ON fb.id = en.block_id
LEFT JOIN event_entrants ee ON ee.entrant_id = en.id
WHERE en.status = 'accepted'
  AND (COALESCE(fb.entry_fee_cents, 0) = 0 OR en.entry_paid_at IS NOT NULL)
GROUP BY en.block_id, en.id, en.name, en.group_label;
