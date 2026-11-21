-- Bank statement lines a treasurer has applied (step D of
-- docs/CLUB_PAYMENTS_V2_PLAN.md). Only a fingerprint of each line and the
-- payment it became — never the statement itself, which holds the club's
-- other banking — so the same line imported twice is applied once.
CREATE TABLE IF NOT EXISTS statement_lines (
    club_id    UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    line_hash  TEXT NOT NULL CHECK (line_hash ~ '^[0-9a-f]{32}$'),
    payment_id UUID REFERENCES member_payments(id) ON DELETE SET NULL,
    applied_by UUID REFERENCES users(id) ON DELETE SET NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (club_id, line_hash)
);
