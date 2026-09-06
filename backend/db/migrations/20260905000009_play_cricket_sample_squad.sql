-- Expand Play-Cricket sample squad so leaderboards look complete.
-- Creates synthetic players on cricket clubs (idempotent by email).

INSERT INTO users (id, email, password_hash, name, primary_sport, sport_profiles, profile_completed_at)
SELECT gen_random_uuid(),
       v.email,
       -- bcrypt for password123 (same as demo seed)
       (SELECT password_hash FROM users WHERE email = 'demo@fishers.test' LIMIT 1),
       v.name,
       'cricket',
       '[{"sport":"cricket","tier":"club","position":"all_rounder"}]'::jsonb,
       NOW()
FROM (VALUES
    ('alex.batter@fishers.test', 'Alex Batter'),
    ('sam.bowler@fishers.test', 'Sam Bowler'),
    ('jordan.keeper@fishers.test', 'Jordan Keeper'),
    ('riley.opener@fishers.test', 'Riley Opener'),
    ('casey.spinner@fishers.test', 'Casey Spinner'),
    ('morgan.finisher@fishers.test', 'Morgan Finisher'),
    ('taylor.pace@fishers.test', 'Taylor Pace'),
    ('jamie.allround@fishers.test', 'Jamie Allround')
) AS v(email, name)
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.email = v.email)
  AND EXISTS (SELECT 1 FROM users WHERE email = 'demo@fishers.test');

-- Add them to every cricket club as players.
INSERT INTO club_members (club_id, user_id, role, status)
SELECT c.id, u.id, 'member', 'active'
FROM clubs c
CROSS JOIN users u
WHERE 'cricket' = ANY (c.sport_types)
  AND u.email LIKE '%@fishers.test'
  AND u.email <> 'demo@fishers.test'
  AND NOT EXISTS (
      SELECT 1 FROM club_members cm
      WHERE cm.club_id = c.id AND cm.user_id = u.id
  );

-- Ensure demo is on every cricket club too.
INSERT INTO club_members (club_id, user_id, role, status)
SELECT c.id, u.id, 'club_admin', 'active'
FROM clubs c
CROSS JOIN users u
WHERE 'cricket' = ANY (c.sport_types)
  AND u.email = 'demo@fishers.test'
  AND NOT EXISTS (
      SELECT 1 FROM club_members cm
      WHERE cm.club_id = c.id AND cm.user_id = u.id
  );

-- Play-Cricket links for anyone missing them (ids derived from user uuid — unique).
INSERT INTO play_cricket_player_links (
    user_id, club_id, play_cricket_player_id, play_cricket_site_id,
    display_name, profile_url, last_synced_at
)
SELECT cm.user_id, cm.club_id,
       pcs.site_id || substr(replace(cm.user_id::text, '-', ''), 1, 8),
       pcs.site_id,
       u.name,
       'https://play-cricket.com/',
       NOW()
FROM club_members cm
JOIN users u ON u.id = cm.user_id
JOIN play_cricket_club_sites pcs ON pcs.club_id = cm.club_id
WHERE cm.status = 'active'
  AND NOT EXISTS (
      SELECT 1 FROM play_cricket_player_links l
      WHERE l.user_id = cm.user_id AND l.club_id = cm.club_id
  );

INSERT INTO player_season_stats (
    user_id, club_id, sport, season_year, source,
    matches, runs, wickets, batting_innings, not_outs, balls_faced,
    fours, sixes, high_score, overs_bowled, bowling_runs, maidens, catches, stumpings, extras
)
SELECT l.user_id, l.club_id, 'cricket', 2026, 'play_cricket',
       8 + (abs(hashtext(l.user_id::text)) % 7),
       40 + (abs(hashtext(l.user_id::text || 'runs')) % 320),
       (abs(hashtext(l.user_id::text || 'wkts')) % 28),
       6 + (abs(hashtext(l.user_id::text || 'inn')) % 8),
       abs(hashtext(l.user_id::text || 'no')) % 4,
       80 + (abs(hashtext(l.user_id::text || 'balls')) % 250),
       4 + (abs(hashtext(l.user_id::text || '4s')) % 40),
       abs(hashtext(l.user_id::text || '6s')) % 12,
       20 + (abs(hashtext(l.user_id::text || 'hs')) % 90),
       (8 + (abs(hashtext(l.user_id::text || 'ov')) % 40))::float8,
       30 + (abs(hashtext(l.user_id::text || 'br')) % 180),
       abs(hashtext(l.user_id::text || 'md')) % 8,
       abs(hashtext(l.user_id::text || 'ct')) % 10,
       abs(hashtext(l.user_id::text || 'st')) % 3,
       jsonb_build_object(
           'play_cricket_player_id', l.play_cricket_player_id,
           'profile_url', l.profile_url
       )
FROM play_cricket_player_links l
WHERE NOT EXISTS (
    SELECT 1 FROM player_season_stats p
    WHERE p.user_id = l.user_id AND p.club_id = l.club_id
      AND p.season_year = 2026 AND p.source = 'play_cricket'
);

-- Re-apply demo showcase numbers.
UPDATE player_season_stats p
SET runs = 412, wickets = 23, matches = 14, high_score = 87,
    batting_innings = 13, not_outs = 2, fours = 48, sixes = 9,
    overs_bowled = 68.0, bowling_runs = 295, maidens = 7, catches = 8,
    updated_at = NOW(),
    extras = extras || jsonb_build_object('featured', true)
FROM users u
WHERE u.id = p.user_id
  AND u.email = 'demo@fishers.test'
  AND p.season_year = 2026
  AND p.source = 'play_cricket';

INSERT INTO user_achievements (user_id, achievement_code, club_id, season_year, evidence)
SELECT p.user_id, 'first_fifty', p.club_id, 2026,
       jsonb_build_object('high_score', p.high_score)
FROM player_season_stats p
WHERE p.season_year = 2026 AND p.source = 'play_cricket' AND COALESCE(p.high_score, 0) >= 50
ON CONFLICT (user_id, achievement_code, season_year) DO NOTHING;

INSERT INTO user_achievements (user_id, achievement_code, club_id, season_year, evidence)
SELECT p.user_id, 'season_200_runs', p.club_id, 2026,
       jsonb_build_object('runs', p.runs)
FROM player_season_stats p
WHERE p.season_year = 2026 AND p.source = 'play_cricket' AND p.runs >= 200
ON CONFLICT (user_id, achievement_code, season_year) DO NOTHING;

INSERT INTO user_achievements (user_id, achievement_code, club_id, season_year, evidence)
SELECT p.user_id, 'season_20_wickets', p.club_id, 2026,
       jsonb_build_object('wickets', p.wickets)
FROM player_season_stats p
WHERE p.season_year = 2026 AND p.source = 'play_cricket' AND p.wickets >= 20
ON CONFLICT (user_id, achievement_code, season_year) DO NOTHING;

INSERT INTO user_achievements (user_id, achievement_code, club_id, season_year, evidence)
SELECT p.user_id, 'five_fer', p.club_id, 2026,
       jsonb_build_object('note', 'Sample five-wicket haul')
FROM player_season_stats p
JOIN users u ON u.id = p.user_id
WHERE u.email = 'demo@fishers.test' AND p.season_year = 2026
ON CONFLICT (user_id, achievement_code, season_year) DO NOTHING;

INSERT INTO user_achievements (user_id, achievement_code, club_id, season_year, evidence)
SELECT p.user_id, 'club_champion', p.club_id, 2026,
       jsonb_build_object('category', 'leading_run_scorer')
FROM player_season_stats p
JOIN users u ON u.id = p.user_id
WHERE u.email = 'demo@fishers.test' AND p.season_year = 2026
ON CONFLICT (user_id, achievement_code, season_year) DO NOTHING;
