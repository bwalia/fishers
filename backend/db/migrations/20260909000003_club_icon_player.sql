-- The player a club wants on its own front page. One is enough: a marketing
-- page with eleven faces is a team sheet, not a shop window.
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS icon_player_id UUID REFERENCES users(id);
