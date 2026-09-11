-- Live updates: Postgres announces each change on one channel, every API
-- replica LISTENs, and each forwards to its connected browsers only what that
-- person may see.
--
-- Triggers, not calls in application code, so that every path that writes a
-- message, a notification or a membership is covered — including ones written
-- later by somebody who has never heard of this. NOTIFY is transactional: it
-- fires on commit and never for a rolled-back write.
--
-- The payload carries ids only, never content. The browser fetches through the
-- normal endpoints, which check access, so a forwarding mistake here could at
-- worst say "something changed" — never what.
--
-- One function per table, deliberately. A single function switching on
-- TG_TABLE_NAME does not work: PL/pgSQL resolves every `NEW.field` in an
-- expression when it plans it, including in CASE branches that are never
-- taken, so a membership row failed on messages' `id` — and took the insert
-- down with it.

CREATE OR REPLACE FUNCTION fishers_live_message() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('fishers_live', json_build_object(
        'kind', 'message', 'conversation_id', NEW.conversation_id, 'id', NEW.id)::text);
    RETURN NULL; -- AFTER trigger: the return value is ignored
END $$;

-- Inserted, or read on another device: either way the bell changes.
CREATE OR REPLACE FUNCTION fishers_live_notification() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('fishers_live', json_build_object(
        'kind', 'notification', 'user_id', NEW.user_id)::text);
    RETURN NULL;
END $$;

-- Who can see which thread, kept current while a browser is connected.
CREATE OR REPLACE FUNCTION fishers_live_member() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('fishers_live', json_build_object(
            'kind', 'member', 'user_id', OLD.user_id,
            'conversation_id', OLD.conversation_id, 'left', true)::text);
    ELSE
        PERFORM pg_notify('fishers_live', json_build_object(
            'kind', 'member', 'user_id', NEW.user_id,
            'conversation_id', NEW.conversation_id, 'left', false)::text);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER messages_live
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION fishers_live_message();

CREATE TRIGGER notifications_live
    AFTER INSERT OR UPDATE OF read_at ON notifications_log
    FOR EACH ROW EXECUTE FUNCTION fishers_live_notification();

CREATE TRIGGER conversation_members_live
    AFTER INSERT OR DELETE ON conversation_members
    FOR EACH ROW EXECUTE FUNCTION fishers_live_member();
