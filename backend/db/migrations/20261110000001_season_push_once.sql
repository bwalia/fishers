-- When the "season closed" push went to a member, apart from their email.
--
-- The push used to go on the first attempt at the email (`attempts = 0`), so
-- an email that could not be tried yet — mail switched off on the server, or
-- a row whose season failed to load — sent the push again every tick. Now the
-- push is marked once it goes, and the email waits on its own.
ALTER TABLE season_emails ADD COLUMN IF NOT EXISTS pushed_at TIMESTAMPTZ;

-- Every row the sender has already touched had its push then.
UPDATE season_emails
SET pushed_at = queued_at
WHERE pushed_at IS NULL AND (attempts > 0 OR sent_at IS NOT NULL OR skipped IS NOT NULL);
