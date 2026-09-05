-- Play-Cricket (ECB) links + season stats + achievements.
-- Note: Play-Cricket does not expose a dedicated statistics API; Fishers stores
-- season aggregates and deep-links to Play-Cricket profiles. Optional sync can
-- pull match summaries when a club API token is configured.

CREATE TABLE IF NOT EXISTS play_cricket_club_sites (
    club_id UUID PRIMARY KEY REFERENCES clubs(id) ON DELETE CASCADE,
    site_id TEXT NOT NULL,
    site_name TEXT,
    public_url TEXT,
    api_token_env TEXT,
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (site_id)
);

CREATE TABLE IF NOT EXISTS play_cricket_player_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    club_id UUID REFERENCES clubs(id) ON DELETE SET NULL,
    play_cricket_player_id TEXT NOT NULL,
    play_cricket_site_id TEXT,
    display_name TEXT,
    profile_url TEXT,
    linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_synced_at TIMESTAMPTZ,
    UNIQUE (play_cricket_player_id),
    UNIQUE (user_id, club_id)
);

CREATE INDEX IF NOT EXISTS play_cricket_player_links_user
    ON play_cricket_player_links (user_id);

CREATE TABLE IF NOT EXISTS player_season_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    club_id UUID REFERENCES clubs(id) ON DELETE SET NULL,
    team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    sport TEXT NOT NULL DEFAULT 'cricket',
    season_year INT NOT NULL,
    source TEXT NOT NULL DEFAULT 'manual',
    matches INT NOT NULL DEFAULT 0,
    runs INT NOT NULL DEFAULT 0,
    wickets INT NOT NULL DEFAULT 0,
    batting_innings INT NOT NULL DEFAULT 0,
    not_outs INT NOT NULL DEFAULT 0,
    balls_faced INT NOT NULL DEFAULT 0,
    fours INT NOT NULL DEFAULT 0,
    sixes INT NOT NULL DEFAULT 0,
    high_score INT,
    overs_bowled DOUBLE PRECISION NOT NULL DEFAULT 0,
    bowling_runs INT NOT NULL DEFAULT 0,
    maidens INT NOT NULL DEFAULT 0,
    catches INT NOT NULL DEFAULT 0,
    stumpings INT NOT NULL DEFAULT 0,
    extras JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, club_id, sport, season_year, source)
);

CREATE INDEX IF NOT EXISTS player_season_stats_club_season
    ON player_season_stats (club_id, season_year);

CREATE TABLE IF NOT EXISTS club_season_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    sport TEXT NOT NULL DEFAULT 'cricket',
    season_year INT NOT NULL,
    source TEXT NOT NULL DEFAULT 'manual',
    matches_played INT NOT NULL DEFAULT 0,
    wins INT NOT NULL DEFAULT 0,
    losses INT NOT NULL DEFAULT 0,
    draws INT NOT NULL DEFAULT 0,
    no_results INT NOT NULL DEFAULT 0,
    runs_for INT NOT NULL DEFAULT 0,
    runs_against INT NOT NULL DEFAULT 0,
    wickets_taken INT NOT NULL DEFAULT 0,
    wickets_lost INT NOT NULL DEFAULT 0,
    extras JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (club_id, team_id, sport, season_year, source)
);

CREATE TABLE IF NOT EXISTS achievement_defs (
    code TEXT PRIMARY KEY,
    sport TEXT,
    title TEXT NOT NULL,
    description TEXT,
    icon TEXT,
    criteria JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS user_achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    achievement_code TEXT NOT NULL REFERENCES achievement_defs(code) ON DELETE CASCADE,
    club_id UUID REFERENCES clubs(id) ON DELETE SET NULL,
    season_year INT,
    awarded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    evidence JSONB NOT NULL DEFAULT '{}',
    UNIQUE (user_id, achievement_code, season_year)
);

-- Achievement catalogue
INSERT INTO achievement_defs (code, sport, title, description, icon, criteria) VALUES
    ('first_fifty', 'cricket', 'First fifty', 'Scored 50 or more in an innings', '50', '{"min_score":50}'),
    ('century', 'cricket', 'Century maker', 'Scored 100 or more in an innings', '100', '{"min_score":100}'),
    ('five_fer', 'cricket', 'Five-for', 'Took five wickets in an innings', '5w', '{"min_wickets":5}'),
    ('season_200_runs', 'cricket', '200-run season', '200+ runs in a season', 'bat', '{"min_season_runs":200}'),
    ('season_20_wickets', 'cricket', '20-wicket season', '20+ wickets in a season', 'ball', '{"min_season_wickets":20}'),
    ('club_champion', 'cricket', 'Club champion', 'Leading run-scorer or wicket-taker for the club', 'trophy', '{}'),
    ('motm', 'cricket', 'Player of the match', 'Named player of the match', 'star', '{}'),
    ('reliable_squad', NULL, 'Always there', 'Confirmed for 10+ fixtures in a season', 'check', '{"min_confirmed":10}')
ON CONFLICT (code) DO NOTHING;

-- Link cricket clubs to sample Play-Cricket site IDs (public browsing URLs).
INSERT INTO play_cricket_club_sites (club_id, site_id, site_name, public_url, api_token_env)
SELECT c.id,
       CASE WHEN c.name ILIKE '%lords%' THEN '12345' ELSE '23456' END,
       c.name || ' on Play-Cricket',
       'https://play-cricket.com/website/view/' ||
           CASE WHEN c.name ILIKE '%lords%' THEN '12345' ELSE '23456' END,
       'PLAY_CRICKET_API_TOKEN'
FROM clubs c
WHERE 'cricket' = ANY (c.sport_types)
ON CONFLICT (club_id) DO NOTHING;

-- Club season board for 2026 (sample Play-Cricket import).
INSERT INTO club_season_stats (
    club_id, team_id, sport, season_year, source,
    matches_played, wins, losses, draws, no_results,
    runs_for, runs_against, wickets_taken, wickets_lost, extras
)
SELECT c.id, NULL, 'cricket', 2026, 'play_cricket',
       CASE WHEN c.name ILIKE '%lords%' THEN 14 ELSE 11 END,
       CASE WHEN c.name ILIKE '%lords%' THEN 9 ELSE 5 END,
       CASE WHEN c.name ILIKE '%lords%' THEN 4 ELSE 5 END,
       CASE WHEN c.name ILIKE '%lords%' THEN 1 ELSE 1 END,
       0,
       CASE WHEN c.name ILIKE '%lords%' THEN 2456 ELSE 1820 END,
       CASE WHEN c.name ILIKE '%lords%' THEN 2110 ELSE 1965 END,
       CASE WHEN c.name ILIKE '%lords%' THEN 118 ELSE 92 END,
       CASE WHEN c.name ILIKE '%lords%' THEN 97 ELSE 104 END,
       jsonb_build_object(
           'competition', CASE WHEN c.name ILIKE '%lords%' THEN 'Middlesex League' ELSE 'County Social' END,
           'play_cricket_site_id', pcs.site_id
       )
FROM clubs c
JOIN play_cricket_club_sites pcs ON pcs.club_id = c.id
WHERE 'cricket' = ANY (c.sport_types)
  AND NOT EXISTS (
      SELECT 1 FROM club_season_stats s
      WHERE s.club_id = c.id AND s.season_year = 2026
        AND s.team_id IS NULL AND s.source = 'play_cricket'
  );

-- Player links + season stats for every active cricket club member.
WITH ranked AS (
    SELECT cm.user_id, cm.club_id, u.name, u.email, pcs.site_id,
           row_number() OVER (PARTITION BY cm.club_id ORDER BY u.name) AS rn
    FROM club_members cm
    JOIN users u ON u.id = cm.user_id
    JOIN clubs c ON c.id = cm.club_id
    JOIN play_cricket_club_sites pcs ON pcs.club_id = c.id
    WHERE cm.status = 'active'
      AND 'cricket' = ANY (c.sport_types)
)
INSERT INTO play_cricket_player_links (
    user_id, club_id, play_cricket_player_id, play_cricket_site_id,
    display_name, profile_url, last_synced_at
)
SELECT r.user_id, r.club_id,
       (r.site_id || lpad(r.rn::text, 4, '0')),
       r.site_id,
       r.name,
       'https://play-cricket.com/website/player_stats?site_id=' || r.site_id ||
           '&player_id=' || (r.site_id || lpad(r.rn::text, 4, '0')),
       NOW()
FROM ranked r
ON CONFLICT (user_id, club_id) DO NOTHING;

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
       (8 + (abs(hashtext(l.user_id::text || 'ov')) % 40))::numeric,
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

-- Boost demo@fishers.test so the UI has a clear showcase card.
UPDATE player_season_stats p
SET runs = 412, wickets = 23, matches = 14, high_score = 87,
    batting_innings = 13, not_outs = 2, fours = 48, sixes = 9,
    overs_bowled = 68.0, bowling_runs = 295, maidens = 7, catches = 8,
    updated_at = NOW(),
    extras = extras || jsonb_build_object('featured', true, 'note', 'Sample Play-Cricket import')
FROM users u
WHERE u.id = p.user_id
  AND u.email = 'demo@fishers.test'
  AND p.season_year = 2026
  AND p.source = 'play_cricket';

-- Achievements for strong seasons + demo showcase.
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
       jsonb_build_object('note', 'Sample five-wicket haul vs Mid-Week XI')
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
