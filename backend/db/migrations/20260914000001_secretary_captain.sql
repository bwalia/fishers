-- In a small club the secretary usually captains the side as well. A
-- membership holds one role, and a secretary's already carries every captain
-- power, so what was missing is the fact itself: this person is the captain.
-- It only means something alongside a secretary's role — a Captain is a
-- captain by role — and the queries read it that way, so a flag left behind
-- by a later role change is ignored rather than trusted.
ALTER TABLE club_members ADD COLUMN IF NOT EXISTS is_captain BOOLEAN NOT NULL DEFAULT false;
