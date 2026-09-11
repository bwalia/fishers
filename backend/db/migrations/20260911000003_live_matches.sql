-- Live scoring: every change to a match — a ball, the toss, a handover, the
-- result — is an UPDATE of its cricket_matches row (state_json, last_seq), so
-- one trigger here covers them all. Watchers refetch through the normal
-- endpoints; the payload is only the id. See the live_events migration.

CREATE OR REPLACE FUNCTION fishers_live_match() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('fishers_live', json_build_object(
        'kind', 'match', 'id', NEW.id, 'seq', NEW.last_seq)::text);
    RETURN NULL;
END $$;

CREATE TRIGGER cricket_matches_live
    AFTER UPDATE ON cricket_matches
    FOR EACH ROW EXECUTE FUNCTION fishers_live_match();
