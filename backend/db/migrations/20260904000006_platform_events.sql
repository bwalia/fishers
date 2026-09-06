-- Platform event log: append-only club activity for AI, stats, notifications.
-- Not a replacement for cricket_scoring_events; those remain sport-engine truth.

CREATE TABLE IF NOT EXISTS platform_events (
    id UUID PRIMARY KEY,
    club_id UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    actor_json JSONB NOT NULL,
    payload JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS platform_events_club_occurred
    ON platform_events (club_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS platform_events_type
    ON platform_events (event_type, occurred_at DESC);
