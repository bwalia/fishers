-- Secure, revocable tokens for public live scoreboard links shared into chat.

CREATE TABLE IF NOT EXISTS cricket_scoreboard_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES cricket_matches(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS cricket_scoreboard_shares_match_active
    ON cricket_scoreboard_shares (match_id)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS cricket_scoreboard_shares_token_active
    ON cricket_scoreboard_shares (token)
    WHERE revoked_at IS NULL;
