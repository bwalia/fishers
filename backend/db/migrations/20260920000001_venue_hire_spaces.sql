-- Venue hire Phase 1: hireable spaces, rate cards, weekly availability, blackouts.
-- Bookings / payments / marketplace discovery across clubs come in later phases
-- (see docs/VENUE_HIRE.md). Existing `venues` rows stay as site labels for fixtures.

CREATE TYPE venue_space_kind AS ENUM (
    'pitch', 'square', 'net_lane', 'court', 'hall', 'pavilion', 'bar', 'room', 'other'
);

CREATE TYPE venue_rate_unit AS ENUM (
    'per_hour', 'per_session', 'per_half_day', 'per_day', 'per_head', 'fixed'
);

CREATE TABLE venue_spaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    kind venue_space_kind NOT NULL DEFAULT 'other',
    -- SportType snake_case values; empty = non-sport (hall / pavilion hire).
    sports TEXT[] NOT NULL DEFAULT '{}',
    capacity INT,
    is_hireable BOOLEAN NOT NULL DEFAULT false,
    requires_approval BOOLEAN NOT NULL DEFAULT true,
    notice_hours_min INT NOT NULL DEFAULT 24 CHECK (notice_hours_min >= 0),
    notice_days_max INT NOT NULL DEFAULT 365 CHECK (notice_days_max >= 0),
    slot_minutes INT NOT NULL DEFAULT 60 CHECK (slot_minutes > 0),
    buffer_minutes INT NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
    notes TEXT,
    active BOOLEAN NOT NULL DEFAULT true,
    timezone TEXT NOT NULL DEFAULT 'Europe/London',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (char_length(name) BETWEEN 1 AND 160),
    CHECK (capacity IS NULL OR capacity > 0)
);

CREATE INDEX idx_venue_spaces_venue ON venue_spaces (venue_id);
CREATE INDEX idx_venue_spaces_hireable ON venue_spaces (is_hireable, active)
    WHERE is_hireable AND active;

CREATE TABLE venue_rate_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id UUID NOT NULL REFERENCES venue_spaces(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    unit venue_rate_unit NOT NULL DEFAULT 'per_hour',
    amount_cents INT NOT NULL CHECK (amount_cents >= 0),
    currency TEXT NOT NULL DEFAULT 'GBP' CHECK (char_length(currency) = 3),
    member_amount_cents INT CHECK (member_amount_cents IS NULL OR member_amount_cents >= 0),
    -- 0=Sunday … 6=Saturday (chrono weekday numbering). Empty = every day.
    days_of_week SMALLINT[] NOT NULL DEFAULT '{}',
    time_from TIME,
    time_to TIME,
    season_from DATE,
    season_to DATE,
    min_units INT NOT NULL DEFAULT 1 CHECK (min_units >= 1),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (char_length(name) BETWEEN 1 AND 120),
    CHECK (time_from IS NULL OR time_to IS NULL OR time_to > time_from),
    CHECK (season_from IS NULL OR season_to IS NULL OR season_to >= season_from)
);

CREATE INDEX idx_venue_rate_cards_space ON venue_rate_cards (space_id);

-- Weekly opening hours for a space. day_of_week: 0=Sunday … 6=Saturday.
CREATE TABLE venue_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id UUID NOT NULL REFERENCES venue_spaces(id) ON DELETE CASCADE,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    opens_at TIME NOT NULL,
    closes_at TIME NOT NULL,
    CHECK (closes_at > opens_at),
    UNIQUE (space_id, day_of_week, opens_at, closes_at)
);

CREATE INDEX idx_venue_availability_space ON venue_availability (space_id);

CREATE TABLE venue_blackouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id UUID NOT NULL REFERENCES venue_spaces(id) ON DELETE CASCADE,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ends_at > starts_at)
);

CREATE INDEX idx_venue_blackouts_space_range ON venue_blackouts (space_id, starts_at, ends_at);
