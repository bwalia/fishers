// `npm test` from web/ — importing a bank statement: the groups a preview is
// shown in, and the words "Needs a look" uses for why.

import assert from "node:assert/strict";
import { test } from "node:test";

import { groupLines, referenceBase, saidCents, sharedSurname } from "./statement.ts";

const line = (hash, action, extra = {}) => ({
  hash,
  row: 2,
  date: "2026-11-22",
  amount_cents: 600,
  text: "",
  action,
  user_id: null,
  name: null,
  payment_ids: [],
  why: null,
  ...extra,
});

test("confirm and record are ticked off; check needs a look; the rest fold away", () => {
  const g = groupLines([
    line("a", "confirm"),
    line("b", "check", { why: "different_amount" }),
    line("c", "record"),
    line("d", "unknown"),
    line("e", "already"),
    line("f", "something_new"),
  ]);
  assert.deepEqual(g.ticked.map((l) => l.hash), ["a", "c"]);
  assert.deepEqual(g.look.map((l) => l.hash), ["b"]);
  // An action this build has never heard of is not applied by accident.
  assert.deepEqual(g.unknown.map((l) => l.hash), ["d", "f"]);
  assert.deepEqual(g.already.map((l) => l.hash), ["e"]);
});

test("a reference is the surname in capitals, as the server makes it", () => {
  assert.equal(referenceBase("Ravi Sharma"), "SHARMA");
  assert.equal(referenceBase("Mary O'Neill"), "ONEILL");
  assert.equal(referenceBase("Tom Bennett 2"), "BENNETT");
  assert.equal(referenceBase("Wolfeschlegelsteinhausen"), "WOLFESCHLEGELS");
  assert.equal(referenceBase("42"), "PLAYER");
});

test("the shared surname on a line, and how many members have it", () => {
  const names = ["Ravi Sharma", "Rohit Sharma", "Josh Turner", "Neha Gill", "Jas Gill", "Arjun Gill"];
  assert.deepEqual(sharedSurname("R SHARMA SHARMA", names), { surname: "SHARMA", count: 2 });
  assert.deepEqual(sharedSurname("N gill / gill", names), { surname: "GILL", count: 3 });
  // Only a surname two people share; a word inside another word is no match.
  assert.equal(sharedSurname("J TURNER TURNER", names), null);
  assert.equal(sharedSurname("SHARMAJI", names), null);
});

test("what somebody said they sent: their own, and what they paid for others", () => {
  const toCheck = [
    { user_id: "tom", created_by: "tom", method: "transfer", amount_cents: 600 },
    { user_id: "tom", created_by: null, method: "cash", amount_cents: 500 },
    { user_id: "jas", created_by: "neha", method: "transfer", amount_cents: 300 },
    { user_id: "arjun", created_by: "neha", method: "transfer", amount_cents: 300 },
    { user_id: "josh", created_by: null, method: "transfer", amount_cents: 600 },
  ];
  assert.equal(saidCents(toCheck, "tom"), 600);
  assert.equal(saidCents(toCheck, "neha"), 600);
  assert.equal(saidCents(toCheck, "josh"), 600);
  assert.equal(saidCents(toCheck, "jas"), 0);
});
