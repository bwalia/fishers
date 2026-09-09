-- Naming an umpire can put the book in their hands, which is a fourth way it
-- changes owner. The trail is read by people — "appointed" is a different
-- story from "claim" (they picked it up) or "override" (it was taken off
-- somebody), so it gets its own word rather than being folded into one.

ALTER TABLE cricket_scorer_handovers
  DROP CONSTRAINT IF EXISTS cricket_scorer_handovers_reason_check;

ALTER TABLE cricket_scorer_handovers
  ADD CONSTRAINT cricket_scorer_handovers_reason_check
  CHECK (reason IN ('handover', 'override', 'claim', 'appointed'));
