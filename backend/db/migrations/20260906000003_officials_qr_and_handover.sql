-- Three things a real match day needs: a QR code each side can show, umpires
-- who are allowed to score, and a scoring lock that only ever moves by hand.

-- 1. A club's QR code. The token is the whole secret, so it is unguessable and
--    can be shown to a side you have never played before.
ALTER TABLE clubs
    ADD COLUMN IF NOT EXISTS qr_token TEXT;

UPDATE clubs SET qr_token = encode(gen_random_bytes(12), 'hex') WHERE qr_token IS NULL;

ALTER TABLE clubs ALTER COLUMN qr_token SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS clubs_qr_token ON clubs (qr_token);

-- Teams get their own, so a 2nd XI can be scanned directly.
ALTER TABLE teams
    ADD COLUMN IF NOT EXISTS qr_token TEXT;

UPDATE teams SET qr_token = encode(gen_random_bytes(12), 'hex') WHERE qr_token IS NULL;

ALTER TABLE teams ALTER COLUMN qr_token SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS teams_qr_token ON teams (qr_token);

-- 2. Officials have a role. An umpire appointed here may score the match even
--    without holding a club office.
ALTER TABLE cricket_match_officials
    ADD COLUMN IF NOT EXISTS appointed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS appointed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$ BEGIN
    ALTER TABLE cricket_match_officials
        ADD CONSTRAINT cricket_match_officials_role
        CHECK (role IN ('scorer', 'umpire'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS cricket_match_officials_user
    ON cricket_match_officials (user_id);

-- 3. The book changes hands deliberately, and the trail says who and when.
--    A match cannot be altered by anyone but the current scorer.
CREATE TABLE IF NOT EXISTS cricket_scorer_handovers (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id   UUID NOT NULL REFERENCES cricket_matches(id) ON DELETE CASCADE,
    from_user  UUID REFERENCES users(id) ON DELETE SET NULL,
    to_user    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- 'handover' when the scorer passed it on, 'override' when an officer took
    -- it because the phone was gone.
    reason     TEXT NOT NULL DEFAULT 'handover'
        CHECK (reason IN ('handover', 'override', 'claim')),
    acted_by   UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS cricket_scorer_handovers_match
    ON cricket_scorer_handovers (match_id, created_at DESC);

-- Opposition can be a club we know about rather than a typed name.
ALTER TABLE cricket_matches
    ADD COLUMN IF NOT EXISTS opponent_club_id UUID REFERENCES clubs(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS opponent_team_id UUID REFERENCES teams(id) ON DELETE SET NULL;
