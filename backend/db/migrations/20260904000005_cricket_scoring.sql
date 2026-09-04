-- Cricket match scoring (event-sourced, offline-syncable)

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'team_vice_captain';

DO $$ BEGIN
    CREATE TYPE cricket_match_status AS ENUM (
        'scheduled', 'preparing', 'toss', 'selecting_xi', 'ready',
        'live', 'innings_break', 'complete', 'published'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE cricket_match_side AS ENUM ('home', 'away');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE cricket_toss_decision AS ENUM ('bat', 'bowl');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS cricket_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL UNIQUE REFERENCES events(id) ON DELETE CASCADE,
    club_id UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    status cricket_match_status NOT NULL DEFAULT 'scheduled',
    overs_limit INT NOT NULL DEFAULT 20,
    home_name TEXT NOT NULL DEFAULT 'Home',
    away_name TEXT NOT NULL DEFAULT 'Away',
    toss_winner cricket_match_side,
    toss_decision cricket_toss_decision,
    active_scorer_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    active_scorer_device_id TEXT,
    target INT,
    winner cricket_match_side,
    margin TEXT,
    last_seq BIGINT NOT NULL DEFAULT 0,
    state_json JSONB NOT NULL DEFAULT '{}',
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cricket_match_officials (
    match_id UUID NOT NULL REFERENCES cricket_matches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'scorer',
    PRIMARY KEY (match_id, user_id)
);

CREATE TABLE IF NOT EXISTS cricket_scoring_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES cricket_matches(id) ON DELETE CASCADE,
    seq BIGINT NOT NULL,
    client_event_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    created_by UUID NOT NULL REFERENCES users(id),
    device_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (match_id, client_event_id),
    UNIQUE (match_id, seq)
);

CREATE INDEX IF NOT EXISTS cricket_scoring_events_match_seq
    ON cricket_scoring_events (match_id, seq);
