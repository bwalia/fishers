-- Let somebody register with a mobile number instead of an email.
--
-- Plenty of club members have a phone and no address they check, and requiring
-- one just to be put on a team sheet keeps them out. Either identifies a person
-- now; at least one is required, which the API enforces.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- Postgres already treats NULLs as distinct in a UNIQUE constraint, so the
-- existing email constraint keeps working and simply permits absent ones. The
-- phone had no constraint at all, and now needs the same guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_key ON users (phone) WHERE phone IS NOT NULL;
