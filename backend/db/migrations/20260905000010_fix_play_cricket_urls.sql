-- Canonical Play-Cricket public URL is https://play-cricket.com/
-- Earlier sample seeds used fabricated /website/... paths that do not resolve.

UPDATE play_cricket_club_sites
SET public_url = 'https://play-cricket.com/'
WHERE public_url IS DISTINCT FROM 'https://play-cricket.com/';

UPDATE play_cricket_player_links
SET profile_url = 'https://play-cricket.com/'
WHERE profile_url IS DISTINCT FROM 'https://play-cricket.com/';
