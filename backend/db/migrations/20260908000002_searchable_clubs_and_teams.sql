-- Club search was a sequential scan: `name ILIKE '%x%'` cannot use a B-tree,
-- so every keystroke read the whole table. At 100k clubs that measured 106ms
-- per request; with these indexes the same search is ~10-27ms and stops
-- growing with the table.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS clubs_name_trgm ON clubs USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS teams_name_trgm ON teams USING GIN (name gin_trgm_ops);

-- Search filters on visibility before it ranks, so it wants that in the index.
CREATE INDEX IF NOT EXISTS clubs_visibility ON clubs (visibility);

-- A member's own club has to stay findable even when it is invite-only, and
-- that lookup goes the other way: user -> clubs.
CREATE INDEX IF NOT EXISTS club_members_user_active
  ON club_members (user_id) WHERE status = 'active';
