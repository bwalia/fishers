-- A fixture knows who it is against from the moment it is scheduled, not only
-- once somebody starts scoring it. Without this there is nobody to invite on
-- the other side, and the visiting club cannot see the match in their diary.
ALTER TABLE events ADD COLUMN IF NOT EXISTS opponent_club_id UUID REFERENCES clubs(id);

-- Both "who is coming to this fixture" and "which fixtures is this player
-- being asked about" are read on every availability screen.
CREATE INDEX IF NOT EXISTS event_invites_user_status
  ON event_invites (user_id, status);
CREATE INDEX IF NOT EXISTS events_opponent_club ON events (opponent_club_id)
  WHERE opponent_club_id IS NOT NULL;
