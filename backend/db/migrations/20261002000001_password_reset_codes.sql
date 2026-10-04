-- Forgotten-password codes, carried by the table that already holds one-time
-- codes.
--
-- A separate table would have been a second copy of the same four columns, the
-- same hashing, the same expiry and the same attempt counter — and a second
-- place to get the rate limiting wrong. The only thing in the way was the
-- CHECK, which named the two channels that existed when it was written.
--
-- 'reset' is a third channel rather than a flag on 'email': the resend limit
-- and the "only the latest code counts" rule are both per channel, so somebody
-- confirming their address and somebody resetting their password must not
-- retire each other's codes.
--
-- The constraint is found rather than named. It was declared inline, so its
-- name is Postgres' own choice; dropping a guessed name with IF EXISTS would
-- do nothing and then add a second constraint beside the first, leaving
-- 'reset' still refused and nothing in the log to say why.
DO $$
DECLARE existing text;
BEGIN
    SELECT conname INTO existing
      FROM pg_constraint
     WHERE conrelid = 'verification_codes'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%channel%';
    IF existing IS NOT NULL THEN
        EXECUTE format('ALTER TABLE verification_codes DROP CONSTRAINT %I', existing);
    END IF;
END $$;

ALTER TABLE verification_codes
    ADD CONSTRAINT verification_codes_channel_check
    CHECK (channel IN ('email', 'phone', 'reset'));
