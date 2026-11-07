-- An open link to join a club.
--
-- Every invite so far was spent by the first person through it: the right
-- thing for one addressed to somebody, and the wrong thing for the link a
-- secretary drops into the team WhatsApp group. The first player in used it
-- up and the other fifteen were told it had already been used.
--
-- An open invite is addressed to nobody, is never spent, and stays good until
-- the club turns it off (status 'revoked'). `uses` is how many people have
-- come in through it, so the secretary can see the link is working.
ALTER TABLE invites
    ADD COLUMN IF NOT EXISTS open BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS uses INT NOT NULL DEFAULT 0;

-- One live open link per club or team. Sharing a new one means turning the
-- old one off, so there is never a forgotten second link still letting
-- people in.
CREATE UNIQUE INDEX IF NOT EXISTS invites_one_open_link
    ON invites (target_type, target_id)
    WHERE open AND status = 'pending';
