-- 1. A QR token every row gets on its own.
--
-- The previous migration made the column NOT NULL without a default, so every
-- INSERT that did not name it failed. Patching the two call sites fixed the
-- symptom; this fixes the cause, so a seed script or an import cannot hit it.
ALTER TABLE clubs
    ALTER COLUMN qr_token SET DEFAULT encode(gen_random_bytes(12), 'hex');
ALTER TABLE teams
    ALTER COLUMN qr_token SET DEFAULT encode(gen_random_bytes(12), 'hex');

-- 2. Fielding restrictions, agreed with the rest of the conditions.
ALTER TABLE cricket_matches
    ADD COLUMN IF NOT EXISTS powerplay_overs INT NOT NULL DEFAULT 0;

-- 3. A tied match can go to a super over, and to another after that.
ALTER TABLE cricket_matches
    ADD COLUMN IF NOT EXISTS super_overs INT NOT NULL DEFAULT 0;
