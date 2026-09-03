-- Player profiles: per-sport level, league and stats; travel logistics; and the
-- attendance history the reliability score is derived from.

ALTER TABLE users
    ADD COLUMN primary_sport     TEXT,
    ADD COLUMN sports            TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN position          TEXT,
    ADD COLUMN skill_level       TEXT,
    ADD COLUMN emergency_contact TEXT,
    -- one object per sport: {sport, position, skill_level, current_division,
    -- target_division, age_group, team_name, years_playing,
    -- stats: [{key, value}]}
    ADD COLUMN sport_profiles    JSONB NOT NULL DEFAULT '[]',
    -- {area, postcode, travel_radius_miles, transport, spare_seats,
    --  preferred_days[], notes}
    ADD COLUMN location          JSONB;

-- A profile is "set up" once the player has named a sport and a standard; the
-- app keeps them in setup until then.
ALTER TABLE users
    ADD COLUMN profile_completed_at TIMESTAMPTZ;

ALTER TABLE teams
    ADD COLUMN division  TEXT,
    ADD COLUMN age_group TEXT;

-- Attendance and late drop-outs, the two facts reliability needs that RSVP
-- status alone can't tell us.
ALTER TABLE event_invites
    ADD COLUMN attended     BOOLEAN,
    ADD COLUMN cancelled_at TIMESTAMPTZ;

-- Raw counters per player for past events only. The weighting itself lives in
-- fishers-domain::reliability so the API and the iOS demo agree on the number.
CREATE VIEW player_reliability_counts AS
WITH invite_counts AS (
    SELECT i.user_id,
           COUNT(*)                                              AS invites_received,
           COUNT(*) FILTER (WHERE i.responded_at IS NOT NULL)     AS responded,
           COUNT(*) FILTER (WHERE i.status = 'going')             AS said_going,
           COUNT(*) FILTER (WHERE i.attended IS TRUE)             AS turned_up,
           COUNT(*) FILTER (
               WHERE i.cancelled_at IS NOT NULL
                 AND i.cancelled_at > e.start_at - INTERVAL '24 hours'
           )                                                      AS late_cancellations
    FROM event_invites i
    JOIN events e ON e.id = i.event_id
    WHERE e.start_at < now()
    GROUP BY i.user_id
),
payment_counts AS (
    SELECT p.user_id,
           COUNT(*)                                          AS fees_due,
           COUNT(*) FILTER (WHERE p.status = 'succeeded')     AS fees_paid
    FROM payments p
    WHERE p.event_id IS NOT NULL
    GROUP BY p.user_id
)
SELECT u.id                                     AS user_id,
       COALESCE(i.invites_received, 0)::BIGINT  AS invites_received,
       COALESCE(i.responded, 0)::BIGINT         AS responded,
       COALESCE(i.said_going, 0)::BIGINT        AS said_going,
       COALESCE(i.turned_up, 0)::BIGINT         AS turned_up,
       COALESCE(i.late_cancellations, 0)::BIGINT AS late_cancellations,
       COALESCE(p.fees_due, 0)::BIGINT          AS fees_due,
       COALESCE(p.fees_paid, 0)::BIGINT         AS fees_paid
FROM users u
LEFT JOIN invite_counts i ON i.user_id = u.id
LEFT JOIN payment_counts p ON p.user_id = u.id;
