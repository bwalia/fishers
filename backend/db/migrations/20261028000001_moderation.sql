-- Reporting something, and blocking somebody.
--
-- The app carries club chat, member profiles, photographs and free-text
-- marketplace listings between strangers. An app shaped like that needs two
-- things it did not have: a way to tell us something is wrong, and a way for
-- one person to stop another reaching them without waiting for us to act.

-- 1. Blocks.
--
--    Stored one-directional because that is what the person did — they
--    blocked somebody — but read symmetrically everywhere it is enforced. If
--    either one has blocked the other, neither sees the other. A block that
--    only worked one way would leave the person who blocked still being
--    talked at, which is the thing they were trying to stop.
CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    -- Blocking yourself is a bug in a caller, not a thing to store.
    CONSTRAINT user_blocks_not_self CHECK (blocker_id <> blocked_id)
);

-- Enforcement asks "who is hidden from me", which reads both columns.
CREATE INDEX IF NOT EXISTS user_blocks_blocked ON user_blocks (blocked_id);

-- 2. Reports.
--
--    `subject_id` is deliberately not a foreign key: it names a row in one of
--    several tables, and the report has to outlive what it is about. A report
--    whose evidence vanished when somebody deleted the message is no use to
--    whoever has to decide what happened.
CREATE TABLE IF NOT EXISTS content_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- SET NULL rather than CASCADE: somebody closing their account should not
    -- quietly withdraw the complaints they made about other people.
    reporter_id UUID REFERENCES users(id) ON DELETE SET NULL,
    subject_kind TEXT NOT NULL,
    subject_id UUID NOT NULL,
    reason TEXT NOT NULL,
    -- What they typed, if they typed anything.
    note TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT content_reports_status CHECK (status IN ('open', 'actioned', 'dismissed'))
);

-- The only query that matters day to day: what is still open, oldest first,
-- because Apple's requirement is a timely response and the oldest one is the
-- one running out of time.
CREATE INDEX IF NOT EXISTS content_reports_open
    ON content_reports (created_at)
 WHERE status = 'open';

-- The same person reporting the same thing twice is one report, not two.
CREATE UNIQUE INDEX IF NOT EXISTS content_reports_once
    ON content_reports (reporter_id, subject_kind, subject_id)
 WHERE status = 'open';
