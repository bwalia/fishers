-- Fishers initial schema (spec §6)

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,
    phone         TEXT,
    apple_id      TEXT UNIQUE,
    avatar_url    TEXT,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE clubs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    sport_types TEXT[] NOT NULL DEFAULT '{}',
    visibility  TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'invite_only')),
    owner_id    UUID NOT NULL REFERENCES users (id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE club_members (
    club_id   UUID NOT NULL REFERENCES clubs (id) ON DELETE CASCADE,
    user_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'captain', 'member')),
    status    TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending', 'removed')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (club_id, user_id)
);

CREATE TABLE teams (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id UUID NOT NULL REFERENCES clubs (id) ON DELETE CASCADE,
    sport   TEXT NOT NULL,
    name    TEXT NOT NULL
);

CREATE TABLE team_members (
    team_id UUID NOT NULL REFERENCES teams (id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role    TEXT NOT NULL DEFAULT 'player' CHECK (role IN ('captain', 'player')),
    PRIMARY KEY (team_id, user_id)
);

CREATE TABLE venues (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id UUID NOT NULL REFERENCES clubs (id) ON DELETE CASCADE,
    name    TEXT NOT NULL,
    address TEXT,
    lat     DOUBLE PRECISION,
    lng     DOUBLE PRECISION
);

CREATE TABLE events (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id              UUID NOT NULL REFERENCES clubs (id) ON DELETE CASCADE,
    team_id              UUID REFERENCES teams (id) ON DELETE SET NULL,
    sport                TEXT NOT NULL,
    event_subtype        TEXT NOT NULL DEFAULT 'generic'
        CHECK (event_subtype IN ('nets', 'friendly', 'league_match', 'social', 'generic')),
    title                TEXT NOT NULL,
    description          TEXT,
    venue_id             UUID REFERENCES venues (id) ON DELETE SET NULL,
    start_at             TIMESTAMPTZ NOT NULL,
    end_at               TIMESTAMPTZ NOT NULL,
    recurrence_rule      TEXT,
    recurrence_parent_id UUID REFERENCES events (id) ON DELETE CASCADE,
    capacity             INT,
    fee_amount           BIGINT, -- minor units (pence)
    currency             TEXT NOT NULL DEFAULT 'GBP',
    status               TEXT NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'cancelled', 'completed')),
    -- cricket nets specifics (nullable; only meaningful when event_subtype = 'nets')
    nets_lanes           INT,
    nets_max_per_lane    INT,
    nets_bowling_machine BOOLEAN,
    created_by           UUID NOT NULL REFERENCES users (id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_at > start_at)
);

CREATE INDEX idx_events_club_start ON events (club_id, start_at);
-- makes recurring-instance materialisation idempotent
CREATE UNIQUE INDEX uq_events_recurrence_instance
    ON events (recurrence_parent_id, start_at)
    WHERE recurrence_parent_id IS NOT NULL;

CREATE TABLE match_results (
    event_id       UUID PRIMARY KEY REFERENCES events (id) ON DELETE CASCADE,
    format         TEXT,
    opposition     TEXT,
    home_or_away   TEXT CHECK (home_or_away IN ('home', 'away')),
    scorecard_json JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- per-event RSVP / attendance record
CREATE TABLE event_invites (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id     UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    invited_by   UUID REFERENCES users (id),
    status       TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'going', 'not_going', 'maybe')),
    responded_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, user_id)
);

CREATE INDEX idx_event_invites_user ON event_invites (user_id);

-- inbox-style invitations to a club, team, or single event (spec §3.6)
CREATE TABLE invites (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind          TEXT NOT NULL CHECK (kind IN ('club', 'team', 'event')),
    club_id       UUID REFERENCES clubs (id) ON DELETE CASCADE,
    team_id       UUID REFERENCES teams (id) ON DELETE CASCADE,
    event_id      UUID REFERENCES events (id) ON DELETE CASCADE,
    inviter_id    UUID NOT NULL REFERENCES users (id),
    invitee_id    UUID REFERENCES users (id) ON DELETE CASCADE,
    invitee_email TEXT,
    token         TEXT UNIQUE, -- shareable-link token
    status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at  TIMESTAMPTZ
);

CREATE INDEX idx_invites_invitee ON invites (invitee_id);

CREATE TABLE availability (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    date            DATE NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('available', 'unavailable', 'maybe')),
    note            TEXT,
    recurrence_rule TEXT,
    UNIQUE (user_id, date) -- doubles as the (user_id, date) index
);

CREATE TABLE payments (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  UUID NOT NULL REFERENCES users (id),
    event_id                 UUID REFERENCES events (id) ON DELETE SET NULL,
    amount                   BIGINT NOT NULL, -- minor units (pence)
    currency                 TEXT NOT NULL DEFAULT 'GBP',
    status                   TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
    stripe_payment_intent_id TEXT UNIQUE,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_user ON payments (user_id);
CREATE INDEX idx_payments_event ON payments (event_id);

CREATE TABLE products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id     UUID NOT NULL REFERENCES clubs (id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT,
    price       BIGINT NOT NULL, -- minor units (pence)
    currency    TEXT NOT NULL DEFAULT 'GBP',
    category    TEXT NOT NULL DEFAULT 'other'
        CHECK (category IN ('food', 'equipment', 'kit_hire', 'merchandise', 'other')),
    stock       INT
);

CREATE INDEX idx_products_club ON products (club_id);

CREATE TABLE orders (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users (id),
    event_id     UUID REFERENCES events (id) ON DELETE SET NULL,
    status       TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'fulfilled', 'cancelled')),
    total_amount BIGINT NOT NULL, -- minor units (pence)
    currency     TEXT NOT NULL DEFAULT 'GBP',
    note         TEXT, -- pickup/delivery note
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_user ON orders (user_id);

CREATE TABLE order_items (
    order_id   UUID NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products (id),
    quantity   INT NOT NULL CHECK (quantity > 0),
    unit_price BIGINT NOT NULL, -- minor units (pence)
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE devices (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    device_token TEXT NOT NULL UNIQUE,
    platform     TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications_log (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    type    TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);

CREATE INDEX idx_notifications_user ON notifications_log (user_id, sent_at DESC);
