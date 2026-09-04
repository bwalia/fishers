-- Squad selection: availability first, captain (or the assistant) picks, players
-- reconfirm a couple of days out, reserves fill the gaps automatically.
--
-- Defaults chosen here, stated so they are easy to change:
--   confirm_lead_hours = 48  — reconfirmation is requested two days out
--   drop_lead_hours    = 24  — unconfirmed players are dropped a day out
--   selection_autonomy = 'suggest' — the assistant proposes, a human publishes

CREATE TABLE IF NOT EXISTS fixture_blocks (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id    UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    team_id    UUID REFERENCES teams(id) ON DELETE SET NULL,
    name       TEXT NOT NULL,
    -- A tour, a tournament, or just "the next few weeks".
    kind       TEXT NOT NULL DEFAULT 'block'
        CHECK (kind IN ('block', 'tour', 'tournament', 'season')),
    starts_on  DATE,
    ends_on    DATE,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fixture_blocks_club ON fixture_blocks (club_id, starts_on);

ALTER TABLE events
    ADD COLUMN IF NOT EXISTS fixture_block_id UUID REFERENCES fixture_blocks(id) ON DELETE SET NULL;

-- Selection lives alongside the RSVP: `status` stays the player's own answer
-- (what reliability reads), `selection_state` is the captain's side of it.
ALTER TABLE event_invites
    ADD COLUMN IF NOT EXISTS selection_state   TEXT NOT NULL DEFAULT 'pool'
        CHECK (selection_state IN ('pool', 'selected', 'reserve', 'not_selected',
                                   'confirmed', 'declined', 'dropped')),
    ADD COLUMN IF NOT EXISTS selected_at       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS selected_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    -- Captain's order; also the order reserves are promoted in.
    ADD COLUMN IF NOT EXISTS selection_rank    INT,
    ADD COLUMN IF NOT EXISTS confirm_deadline  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS confirmed_at      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS declined_at       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reminders_sent    INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS promoted_at       TIMESTAMPTZ,
    -- Set when the assistant picked this player rather than a human.
    ADD COLUMN IF NOT EXISTS selected_by_agent BOOLEAN NOT NULL DEFAULT FALSE,
    -- Match-fee chasing: the credit controller should never have to keep a list.
    ADD COLUMN IF NOT EXISTS fee_reminders_sent    INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_fee_reminder_at  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_event_invites_selection
    ON event_invites (event_id, selection_state);

-- Per-club selection policy, so the reconfirm window and how much the assistant
-- is trusted are settings rather than constants.
ALTER TABLE clubs
    ADD COLUMN IF NOT EXISTS selection_autonomy TEXT NOT NULL DEFAULT 'suggest'
        CHECK (selection_autonomy IN ('off', 'suggest', 'auto_publish')),
    ADD COLUMN IF NOT EXISTS confirm_lead_hours INT NOT NULL DEFAULT 48,
    ADD COLUMN IF NOT EXISTS drop_lead_hours    INT NOT NULL DEFAULT 24,
    -- Fee chasing: first nudge this long after the fixture, then daily, capped.
    ADD COLUMN IF NOT EXISTS fee_chase_after_hours INT NOT NULL DEFAULT 24,
    ADD COLUMN IF NOT EXISTS fee_chase_max_reminders INT NOT NULL DEFAULT 3;

-- What a captain looks at when picking: everyone eligible, with the signals.
CREATE OR REPLACE VIEW selection_candidates AS
SELECT e.id                                   AS event_id,
       cm.user_id,
       u.name,
       u.position_role,
       u.skill_level,
       a.status::TEXT                         AS availability,
       i.selection_state,
       i.selection_rank,
       i.status::TEXT                         AS rsvp_status,
       i.confirmed_at IS NOT NULL             AS is_confirmed,
       i.confirm_deadline,
       COALESCE(rc.invites_received, 0)       AS invites_received,
       COALESCE(rc.responded, 0)              AS responded,
       COALESCE(rc.said_going, 0)             AS said_going,
       COALESCE(rc.turned_up, 0)              AS turned_up,
       COALESCE(rc.late_cancellations, 0)     AS late_cancellations,
       COALESCE(rc.fees_due, 0)               AS fees_due,
       COALESCE(rc.fees_paid, 0)              AS fees_paid,
       -- Rotation debt: available but left out, over the last 60 days.
       COALESCE((
           SELECT COUNT(*)
           FROM events pe
           JOIN availability pa
             ON pa.user_id = cm.user_id
            AND pa.date = (pe.start_at AT TIME ZONE 'UTC')::date
            AND pa.status = 'available'
           LEFT JOIN event_invites pi ON pi.event_id = pe.id AND pi.user_id = cm.user_id
           WHERE pe.club_id = e.club_id
             AND pe.start_at < NOW()
             AND pe.start_at > NOW() - INTERVAL '60 days'
             AND pe.status <> 'cancelled'
             AND (pi.id IS NULL OR pi.selection_state = 'not_selected')
       ), 0)                                  AS games_missed_out
FROM events e
JOIN club_members cm ON cm.club_id = e.club_id AND cm.status = 'active'
JOIN users u ON u.id = cm.user_id
LEFT JOIN event_invites i ON i.event_id = e.id AND i.user_id = cm.user_id
LEFT JOIN availability a
       ON a.user_id = cm.user_id
      AND a.date = (e.start_at AT TIME ZONE 'UTC')::date
LEFT JOIN player_reliability_counts rc ON rc.user_id = cm.user_id;

-- Rain stops play: a fixture can be delayed or called off, with the reason the
-- squad actually needs, and the assistant can announce it in the thread.
DO $$ BEGIN
    ALTER TYPE event_status ADD VALUE IF NOT EXISTS 'postponed';
EXCEPTION WHEN others THEN NULL; END $$;

ALTER TABLE events
    -- "Called off — ground unplayable after Friday's rain."
    ADD COLUMN IF NOT EXISTS status_note      TEXT,
    -- Set when a postponed fixture gets a new date.
    ADD COLUMN IF NOT EXISTS rescheduled_to   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ;

-- Who still owes what, so chasing is a query rather than a spreadsheet.
CREATE OR REPLACE VIEW outstanding_match_fees AS
SELECT e.id                        AS event_id,
       e.club_id,
       e.title,
       e.start_at,
       e.fee_amount_cents,
       e.fee_currency,
       i.user_id,
       u.name,
       u.email,
       i.fee_reminders_sent,
       i.last_fee_reminder_at
FROM event_invites i
JOIN events e ON e.id = i.event_id
JOIN users u ON u.id = i.user_id
WHERE e.fee_amount_cents IS NOT NULL
  AND e.fee_amount_cents > 0
  AND e.status <> 'cancelled'
  AND i.status = 'going'
  AND NOT EXISTS (
      SELECT 1 FROM payments p
      WHERE p.event_id = e.id AND p.user_id = i.user_id AND p.status = 'succeeded'
  );
