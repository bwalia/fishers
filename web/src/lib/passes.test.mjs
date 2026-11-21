// `npm test` from web/ — passes' pure helpers: dates, templates, the body a
// pass form sends, and how a pass stands in words.

import assert from "node:assert/strict";
import { test } from "node:test";

import { dayDate, juniorGroup, nextMarch31, passBody, passState, templateDraft, todayDay } from "./passes.ts";

const types = [
  { id: "g1", club_id: "c", name: "Guest", free: false, for_guests: true, sort_order: 1, archived_at: null },
  { id: "c1", club_id: "c", name: "Coach", free: true, for_guests: false, sort_order: 2, archived_at: null },
  { id: "j1", club_id: "c", name: "Junior", free: false, for_guests: false, sort_order: 3, archived_at: null },
];

test("a bare day is that day here, not the evening before", () => {
  const d = dayDate("2026-12-06");
  assert.equal(d.getFullYear(), 2026);
  assert.equal(d.getMonth(), 11);
  assert.equal(d.getDate(), 6);
  assert.equal(todayDay(new Date(2026, 0, 5)), "2026-01-05");
});

test("a winter pass runs to the next 31 March", () => {
  assert.equal(nextMarch31(new Date(2026, 10, 22)), "2027-03-31");
  assert.equal(nextMarch31(new Date(2027, 1, 10)), "2027-03-31");
  assert.equal(nextMarch31(new Date(2027, 3, 1)), "2028-03-31");
});

test("each template sends what the API asks for", () => {
  const now = new Date(2026, 10, 22);
  const body = (id) => passBody(templateDraft(id, "x", types, now), 100).body;
  assert.deepEqual(body("winter").valid_until, "2027-03-31");
  assert.equal(body("winter").billing, "once");
  assert.equal(body("card10").sessions, 10);
  assert.equal(body("card10").valid_until, undefined);
  // A monthly pass has no end date or session count.
  assert.equal(body("monthly").billing, "monthly");
  assert.equal(body("monthly").sessions, undefined);
  assert.equal(body("monthly").valid_until, undefined);
  assert.equal(body("season").instalments, 3);
  assert.equal(body("junior").price_type_id, "j1");
  assert.equal(juniorGroup(types)?.id, "j1");
});

test("a pass form says what is missing before sending", () => {
  const d = templateDraft("card10", "Card", types);
  assert.deepEqual(passBody({ ...d, name: " " }, 4000), { problem: "pw3.need_name" });
  assert.deepEqual(passBody(d, null), { problem: "pay.not_an_amount" });
  assert.deepEqual(passBody({ ...d, sessions: "0" }, 4000), { problem: "pw3.sessions_range" });
  assert.deepEqual(passBody({ ...d, billing: "instalments", instalments: "13" }, 4000), { problem: "pw3.parts_range" });
  assert.deepEqual(passBody({ ...d, lasts: "date", valid_until: "" }, 4000), { problem: "pw3.need_date" });
});

test("how a pass stands: not covering first, then late, then what's left", () => {
  const base = {
    standing: "up_to_date",
    cancelled_at: null,
    ends_on: null,
    started_on: "2026-11-01",
    sessions_left: null,
    running: true,
    billing: "monthly",
  };
  const today = "2026-11-22";
  assert.deepEqual(passState({ ...base, standing: "suspended" }, undefined, today), { kind: "suspended" });
  assert.deepEqual(passState({ ...base, cancelled_at: "x", ends_on: "2026-11-30" }, undefined, today), {
    kind: "cancelled",
    until: "2026-11-30",
  });
  assert.deepEqual(passState({ ...base, started_on: "2026-12-01" }, undefined, today), { kind: "starts", on: "2026-12-01" });
  assert.deepEqual(passState({ ...base, standing: "behind", sessions_left: 3 }, undefined, today), { kind: "behind" });
  assert.deepEqual(passState({ ...base, billing: "once", sessions_left: 3 }, undefined, today), { kind: "sessions", left: 3 });
  assert.deepEqual(passState({ ...base, billing: "once" }, { valid_until: "2027-03-31" }, today), {
    kind: "until",
    on: "2027-03-31",
  });
  assert.deepEqual(passState(base, undefined, today), { kind: "monthly" });
  assert.deepEqual(passState({ ...base, billing: "once", running: false }, { valid_until: null }, today), { kind: "stopped" });
});
