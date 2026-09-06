-- Fixes for three things the first pass got wrong, plus the indexes the hot
-- queries were missing.

-- 1. RSVP reminders had no sent-marker, so the scheduler re-sent them every
--    five minutes for the whole 48-hour window.
ALTER TABLE event_invites
    ADD COLUMN IF NOT EXISTS rsvp_reminded_at TIMESTAMPTZ;

-- 2. A weekly fixture stopped being materialised eight weeks after its anchor,
--    because the job only ever looked at weeks 1..8 from the original date.
--    Remembering how far each series has been expanded makes the window roll.
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS recurrence_expanded_to TIMESTAMPTZ;

-- 3. Ticket payments are money: a ticket becomes 'paid' when a payment
--    succeeds, or when an organiser records cash — never on the buyer's say-so.
ALTER TABLE event_tickets
    ADD COLUMN IF NOT EXISTS paid_at        TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS paid_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    -- 'stripe' | 'cash' | 'transfer'
    ADD COLUMN IF NOT EXISTS payment_method TEXT;

-- Indexes for the queries that run on every screen and every scheduler tick.
CREATE INDEX IF NOT EXISTS idx_events_status_start
    ON events (status, start_at);
CREATE INDEX IF NOT EXISTS idx_events_recurrence_parent
    ON events (recurrence_parent_id, start_at);
CREATE INDEX IF NOT EXISTS idx_event_invites_event_user
    ON event_invites (event_id, user_id);
CREATE INDEX IF NOT EXISTS idx_event_invites_reminders
    ON event_invites (selection_state, confirm_deadline)
    WHERE selection_state = 'selected';
CREATE INDEX IF NOT EXISTS idx_club_members_user
    ON club_members (user_id, status);
CREATE INDEX IF NOT EXISTS idx_team_members_user
    ON team_members (user_id);
CREATE INDEX IF NOT EXISTS idx_payments_event_user
    ON payments (event_id, user_id, status);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user
    ON conversation_members (user_id);
CREATE INDEX IF NOT EXISTS idx_availability_user_range
    ON availability (user_id, date DESC);

-- The scoring log is read whole on every sync; keep it clustered by match.
CREATE INDEX IF NOT EXISTS idx_cricket_events_match
    ON cricket_scoring_events (match_id, seq DESC);
