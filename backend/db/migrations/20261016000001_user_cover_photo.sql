-- A photograph behind the name on a profile.
--
-- The header has always been the brand's own gradient, which is the same for
-- everyone — a page about a person that looks exactly like a page about any
-- other person. A cover is the one part of a profile somebody chooses purely
-- because they want to, and a club full of them stops looking like a database.
--
-- Nullable with no default: most profiles will not have one, and the gradient
-- stays as the fallback rather than becoming a missing-image box.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS cover_url TEXT;
