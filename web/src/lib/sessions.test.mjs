// `npm test` from web/ — plain `node --test`, with Node stripping the types
// from sessions.ts as it imports it. TZ=Europe/London is set by the script,
// so the clock-change case is the clock change it says it is.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  clampWeeks,
  isPractice,
  matchBody,
  seriesWeek,
  sessionBodies,
  sessionNote,
  toLocalInput,
} from "./sessions.ts";

const MIN = 60_000;

const plan = (over = {}) => ({
  kind: "nets",
  clubId: "club-1",
  sport: "cricket",
  title: "Wednesday nets",
  start: new Date("2026-06-03T19:00"),
  minutes: 120,
  weeks: 1,
  ...over,
});

test("a single session is one body with no series", () => {
  const [only, ...rest] = sessionBodies(plan({ note: "  Bring your own bat.  ", venueId: "ground-1" }));
  assert.equal(rest.length, 0);
  assert.deepEqual(only, {
    club_id: "club-1",
    sport: "cricket",
    event_subtype: "nets",
    title: "Wednesday nets",
    venue_id: "ground-1",
    start_at: new Date("2026-06-03T19:00").toISOString(),
    end_at: new Date(new Date("2026-06-03T19:00").getTime() + 120 * MIN).toISOString(),
    metadata: { note: "Bring your own bat." },
  });
  // Left out, not sent as null: a session has no opposition and is not an
  // RRULE, and an empty team or ground is no team or ground.
  for (const key of ["opponent_club_id", "recurrence_rule", "team_id"]) assert.ok(!(key in only), key);
});

test("a session with nothing optional sends an empty metadata", () => {
  const [only] = sessionBodies(plan({ kind: "training", minutes: 90, note: "   " }));
  assert.equal(only.event_subtype, "training");
  assert.deepEqual(only.metadata, {});
  assert.ok(!("venue_id" in only));
  assert.equal(Date.parse(only.end_at) - Date.parse(only.start_at), 90 * MIN);
});

test("a three-week series shares one id and counts 0, 1, 2", () => {
  const bodies = sessionBodies(plan({ weeks: 3, seriesId: "series-1", teamId: "team-1" }));
  assert.equal(bodies.length, 3);
  bodies.forEach((b, i) => {
    assert.equal(b.metadata.series_id, "series-1");
    assert.equal(b.metadata.series_index, i);
    assert.equal(b.metadata.series_count, 3);
    assert.equal(b.team_id, "team-1");
    assert.equal(Date.parse(b.end_at) - Date.parse(b.start_at), 120 * MIN, `week ${i + 1} runs two hours`);
  });
  // June has no clock change, so a week is exactly seven days.
  assert.equal(Date.parse(bodies[1].start_at) - Date.parse(bodies[0].start_at), 7 * 24 * 60 * MIN);
  assert.equal(Date.parse(bodies[2].start_at) - Date.parse(bodies[1].start_at), 7 * 24 * 60 * MIN);
});

test("a series cannot be made without an id to tie it together", () => {
  assert.throws(() => sessionBodies(plan({ weeks: 2 })));
});

test("19:00 stays 19:00 when the clocks go back in late October", () => {
  assert.equal(
    Intl.DateTimeFormat().resolvedOptions().timeZone,
    "Europe/London",
    "run with TZ=Europe/London (npm test does)",
  );
  // British Summer Time ends at 02:00 on Sunday 25 October 2026.
  const bodies = sessionBodies(plan({ start: new Date("2026-10-21T19:00"), weeks: 3, seriesId: "s" }));
  const local = bodies.map((b) => new Date(b.start_at));
  assert.deepEqual(local.map((d) => d.getHours()), [19, 19, 19]);
  assert.deepEqual(local.map((d) => d.getMinutes()), [0, 0, 0]);
  assert.deepEqual(local.map((d) => d.getDate()), [21, 28, 4]);
  // Which is why it is not seven times 24 hours: the instant moves instead.
  assert.deepEqual(
    bodies.map((b) => b.start_at),
    ["2026-10-21T18:00:00.000Z", "2026-10-28T19:00:00.000Z", "2026-11-04T19:00:00.000Z"],
  );
  assert.equal(Date.parse(bodies[1].end_at) - Date.parse(bodies[1].start_at), 120 * MIN);
});

test("a match is sent exactly as it always was", () => {
  const start = new Date("2026-07-11T13:00");
  assert.deepEqual(
    matchBody({
      clubId: "club-1",
      club: { name: "Fishers CC", sport_types: ["cricket"] },
      opponent: { club_id: "club-2", name: "Gully XI" },
      oppositionName: "Gully XI",
      venueId: "ground-1",
      start,
    }),
    {
      club_id: "club-1",
      opponent_club_id: "club-2",
      sport: "cricket",
      event_subtype: "league_match",
      title: "Fishers CC v Gully XI",
      venue_id: "ground-1",
      start_at: start.toISOString(),
      end_at: new Date(start.getTime() + 5 * 60 * MIN).toISOString(),
    },
  );
  // An opposition typed by hand, no ground, a club that plays something else.
  const typed = matchBody({
    clubId: "club-1",
    club: { name: "Fishers FC", sport_types: ["football", "cricket"] },
    opponent: null,
    oppositionName: "Riverside",
    venueId: "",
    start,
  });
  assert.equal(typed.opponent_club_id, null);
  assert.equal(typed.venue_id, null);
  assert.equal(typed.sport, "football");
  assert.equal(typed.title, "Fishers FC v Riverside");
  assert.ok(!("metadata" in typed));
});

test("only nets and training read as a session", () => {
  assert.ok(isPractice("nets"));
  assert.ok(isPractice("training"));
  for (const match of ["league_match", "friendly", "tournament", "social", "generic"]) {
    assert.ok(!isPractice(match), match);
  }
});

test("a session's note and week are read back from its metadata", () => {
  assert.deepEqual(seriesWeek({ series_id: "s", series_index: 0, series_count: 8 }), { i: 1, n: 8 });
  assert.deepEqual(seriesWeek({ series_index: 7, series_count: 8 }), { i: 8, n: 8 });
  assert.equal(seriesWeek({}), null);
  assert.equal(seriesWeek(null), null);
  assert.equal(seriesWeek({ series_index: 8, series_count: 8 }), null);
  assert.equal(seriesWeek({ series_index: "1", series_count: 8 }), null);
  assert.equal(sessionNote({ note: " Bring a bat " }), "Bring a bat");
  assert.equal(sessionNote({ note: "  " }), null);
  assert.equal(sessionNote(undefined), null);
});

test("the weeks box is held between 2 and 12", () => {
  assert.equal(clampWeeks(1), 2);
  assert.equal(clampWeeks(8), 8);
  assert.equal(clampWeeks(20), 12);
  assert.equal(clampWeeks(Number("")), 2);
  assert.equal(clampWeeks(Number.NaN), 8);
});

test("the earliest a session may start is written in local time", () => {
  assert.equal(toLocalInput(new Date("2026-10-21T19:05")), "2026-10-21T19:05");
});
