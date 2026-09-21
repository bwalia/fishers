-- Man of the match, voted for by the club rather than named by the scorer.
--
-- The scorer's own award already exists (`MatchState::player_of_the_match`,
-- set by a `player_of_the_match` scoring event). It is one person's opinion,
-- decided by whoever happened to be holding the book. This is the other half:
-- when the game ends, the fixture's chat thread gets a poll, and everybody in
-- the club votes — including the people who were watching from the boundary
-- rather than playing, which is most of a club on any given Saturday.
--
-- A poll belongs to a fixture, not to a match: a fixture always exists, a
-- cricket_matches row only exists once somebody has scored the game. The
-- match id is kept when there is one so closing the poll can write the award
-- back to the scorecard.

CREATE TABLE IF NOT EXISTS motm_polls (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id         UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    -- One poll per fixture. Re-completing a match (a correction, a super over)
    -- must reopen the same poll rather than start a second one that splits
    -- the vote in half.
    event_id        UUID NOT NULL UNIQUE REFERENCES events(id) ON DELETE CASCADE,
    match_id        UUID REFERENCES cricket_matches(id) ON DELETE SET NULL,
    -- Where the vote card is rendered, and the message carrying it. Both are
    -- nullable: a club with no thread still gets a poll, it just has to be
    -- opened from the fixture instead.
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    message_id      UUID REFERENCES messages(id) ON DELETE SET NULL,
    title           TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    -- Voting stops here on its own. The close endpoint is for a captain who
    -- wants the result now; this is so a poll nobody closes still ends.
    closes_at       TIMESTAMPTZ NOT NULL,
    -- NULL when nobody voted, or when a tie was left undecided.
    winner_user_id  UUID REFERENCES users(id) ON DELETE SET NULL,
    -- NULL for the poll the server opens when the last wicket falls.
    created_by      UUID REFERENCES users(id) ON DELETE SET NULL,
    closed_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_motm_polls_club ON motm_polls (club_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_motm_polls_open ON motm_polls (status, closes_at);

-- Who can be voted for: everyone named on either team sheet.
--
-- `display_name` is a snapshot taken when the poll opens, the same way the
-- scorecard snapshots names into the event log — a poll read next season
-- should still say who was on the list, whether or not that account still
-- exists. `side` is home/away so the card can group the two elevens.
CREATE TABLE IF NOT EXISTS motm_poll_candidates (
    poll_id      UUID NOT NULL REFERENCES motm_polls(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    side         TEXT NOT NULL CHECK (side IN ('home', 'away')),
    PRIMARY KEY (poll_id, user_id)
);

-- One vote each, changeable while the poll is open: the primary key is the
-- voter, not the vote, so voting again moves your vote instead of stuffing
-- the box. Deleting the candidate takes the votes for them with it, which is
-- the only sane reading of a player whose account has gone.
CREATE TABLE IF NOT EXISTS motm_votes (
    poll_id           UUID NOT NULL REFERENCES motm_polls(id) ON DELETE CASCADE,
    voter_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    candidate_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (poll_id, voter_id),
    FOREIGN KEY (poll_id, candidate_user_id)
        REFERENCES motm_poll_candidates (poll_id, user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_motm_votes_tally ON motm_votes (poll_id, candidate_user_id);
