-- Who the club removed, and who removed them.
--
-- A removed member was only marked 'left', with their role and treasurer flag
-- kept, and following the club's open link set them 'active' again. So a
-- player the secretary removed could rejoin from the WhatsApp message still on
-- their phone, a removed captain or secretary came back as one, and a removed
-- treasurer got the club's books back. The open link now refuses anyone the
-- club removed; a secretary inviting them, or adding them, still can.
ALTER TABLE club_members
    ADD COLUMN IF NOT EXISTS removed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS removed_by UUID REFERENCES users(id) ON DELETE SET NULL;

-- Removal is the only thing that has ever set 'left', so everyone 'left' was
-- removed. When is not recorded; now is the honest lower bound.
UPDATE club_members SET removed_at = NOW()
WHERE status = 'left' AND removed_at IS NULL;

-- A removal takes the role and the books with it, including the ones already
-- made: otherwise the next invitation would restore them.
UPDATE club_members SET role = 'member', is_treasurer = FALSE
WHERE status = 'left' AND (role <> 'member' OR is_treasurer);
