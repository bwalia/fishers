-- Player profiles (per-sport level, league grade and stats), travel logistics,
-- and the attendance history the reliability score is derived from.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS primary_sport        TEXT,
    -- [{sport, position, skill_level, current_division, target_division,
    --   age_group, team_name, years_playing, stats{}}]
    ADD COLUMN IF NOT EXISTS sport_profiles       JSONB NOT NULL DEFAULT '[]',
    -- {area, postcode, travel_radius_miles, transport, spare_seats,
    --  preferred_days[], notes}
    ADD COLUMN IF NOT EXISTS location             JSONB,
    ADD COLUMN IF NOT EXISTS profile_completed_at TIMESTAMPTZ;

-- Sides are graded, so a fixture can show both teams' standard.
ALTER TABLE teams
    ADD COLUMN IF NOT EXISTS division  TEXT,
    ADD COLUMN IF NOT EXISTS age_group TEXT;

-- Whether a player actually turned up, and when they pulled out: the two facts
-- RSVP status alone cannot supply to the reliability score.
ALTER TABLE event_invites
    ADD COLUMN IF NOT EXISTS attended     BOOLEAN,
    ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- Raw counters per player over past events. The weighting lives in
-- fishers_domain::reliability so the API and the iOS client agree.
CREATE OR REPLACE VIEW player_reliability_counts AS
WITH invite_counts AS (
    SELECT i.user_id,
           COUNT(*)                                           AS invites_received,
           COUNT(*) FILTER (WHERE i.responded_at IS NOT NULL)  AS responded,
           COUNT(*) FILTER (WHERE i.status = 'going')          AS said_going,
           COUNT(*) FILTER (WHERE i.attended IS TRUE)          AS turned_up,
           COUNT(*) FILTER (
               WHERE i.cancelled_at IS NOT NULL
                 AND i.cancelled_at > e.start_at - INTERVAL '24 hours'
           )                                                   AS late_cancellations
    FROM event_invites i
    JOIN events e ON e.id = i.event_id
    WHERE e.start_at < NOW()
    GROUP BY i.user_id
),
payment_counts AS (
    SELECT p.user_id,
           COUNT(*)                                       AS fees_due,
           COUNT(*) FILTER (WHERE p.status = 'succeeded')  AS fees_paid
    FROM payments p
    WHERE p.event_id IS NOT NULL
    GROUP BY p.user_id
)
SELECT u.id                                        AS user_id,
       COALESCE(i.invites_received, 0)::BIGINT     AS invites_received,
       COALESCE(i.responded, 0)::BIGINT            AS responded,
       COALESCE(i.said_going, 0)::BIGINT           AS said_going,
       COALESCE(i.turned_up, 0)::BIGINT            AS turned_up,
       COALESCE(i.late_cancellations, 0)::BIGINT   AS late_cancellations,
       COALESCE(p.fees_due, 0)::BIGINT             AS fees_due,
       COALESCE(p.fees_paid, 0)::BIGINT            AS fees_paid
FROM users u
LEFT JOIN invite_counts i ON i.user_id = u.id
LEFT JOIN payment_counts p ON p.user_id = u.id;
