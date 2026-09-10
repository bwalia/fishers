-- A club's own page, so a club that wants a public site does not have to go
-- and build one. Everything here is theirs to write; the record and the
-- players are computed from what they have already played.
ALTER TABLE clubs
  ADD COLUMN IF NOT EXISTS slug TEXT,
  ADD COLUMN IF NOT EXISTS public_page BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS tagline TEXT,
  ADD COLUMN IF NOT EXISTS about TEXT,
  ADD COLUMN IF NOT EXISTS ground TEXT,
  ADD COLUMN IF NOT EXISTS founded_year INT,
  ADD COLUMN IF NOT EXISTS contact_email TEXT,
  ADD COLUMN IF NOT EXISTS website TEXT;

-- The slug is the public address, so two clubs cannot share one. Partial, so
-- the clubs without a page do not all collide on NULL.
CREATE UNIQUE INDEX IF NOT EXISTS clubs_slug_key ON clubs (LOWER(slug))
  WHERE slug IS NOT NULL;
