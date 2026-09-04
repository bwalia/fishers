-- In-app chat, plus the agent that reads it and proposes the admin work a
-- captain would otherwise do by hand.
--
-- Kinds and statuses here are TEXT + CHECK rather than Postgres enums: agent
-- proposal kinds are expected to grow (payments, scoring, lift sharing) and a
-- CHECK is cheaper to evolve than ALTER TYPE across environments.

CREATE TABLE IF NOT EXISTS conversations (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id    UUID REFERENCES clubs(id) ON DELETE CASCADE,
    team_id    UUID REFERENCES teams(id) ON DELETE CASCADE,
    -- Set for match-day threads, which the agent treats as being about one fixture.
    event_id   UUID REFERENCES events(id) ON DELETE CASCADE,
    kind       TEXT NOT NULL DEFAULT 'club'
        CHECK (kind IN ('club', 'team', 'event', 'direct')),
    title      TEXT NOT NULL,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_club ON conversations (club_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS conversation_members (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
    -- Drives unread counts without a per-message read table.
    last_read_at    TIMESTAMPTZ,
    muted           BOOLEAN NOT NULL DEFAULT FALSE,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    -- NULL sender means the message came from the agent.
    sender_id       UUID REFERENCES users(id) ON DELETE SET NULL,
    kind            TEXT NOT NULL DEFAULT 'text'
        CHECK (kind IN ('text', 'system', 'agent')),
    body            TEXT NOT NULL,
    -- Agent messages carry {proposal_id, kind} so the app can render an action card.
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    edited_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages (conversation_id, created_at DESC);

-- One row per time the agent was asked to read a thread; keeps token spend and
-- failures auditable.
CREATE TABLE IF NOT EXISTS agent_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    requested_by    UUID NOT NULL REFERENCES users(id),
    model           TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'running'
        CHECK (status IN ('running', 'succeeded', 'failed', 'refused', 'disabled')),
    input_tokens    INT,
    output_tokens   INT,
    error           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

-- The agent never acts on its own: it proposes, a captain or admin applies.
CREATE TABLE IF NOT EXISTS agent_proposals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_run_id    UUID NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    kind            TEXT NOT NULL
        CHECK (kind IN ('availability', 'squad', 'announcement', 'payment_chase')),
    subject_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_id        UUID REFERENCES events(id) ON DELETE SET NULL,
    payload         JSONB NOT NULL DEFAULT '{}',
    rationale       TEXT NOT NULL,
    confidence      TEXT NOT NULL DEFAULT 'medium'
        CHECK (confidence IN ('low', 'medium', 'high')),
    status          TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'applied', 'dismissed', 'failed')),
    decided_by      UUID REFERENCES users(id) ON DELETE SET NULL,
    decided_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_proposals_conversation
    ON agent_proposals (conversation_id, status, created_at DESC);
