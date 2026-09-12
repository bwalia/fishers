/**
 * Fishers, end to end: two clubs and twenty-two players, a 5-over match
 * proposed and accepted, both XIs, the toss, an innings each side with the
 * book handed over in between, and the result.
 *
 * Every step checks that what it did was saved — on the next screen, from the
 * other person's account, and against the API — not only that a button could
 * be pressed. Scores are checked against an independent model of the Laws
 * (lib/model.ts), ball by ball.
 *
 * Accounts are fixed (lib/people.ts): the first run registers them, every run
 * after signs the same people back in and skips what is already done.
 *
 * The app's order differs from the written plan in one place: the toss comes
 * before the team sheets (Scorer → Terms → Toss → Team sheets → Openers), so
 * Step 12 runs between Step 10 and the two Playing XI steps.
 */
import { expect, test, type Page } from "@playwright/test";
import {
  actor,
  apiGet,
  clearOverlays,
  clickPast,
  ensureAccount,
  ensureClub,
  members,
  pathOf,
  profileLink,
  signIn,
  signOut,
  stableEval,
  storedUser,
  type Actor,
  type ClubInfo,
} from "../lib/app";
import { BASE_URL } from "../lib/env";
import { Innings, type Ball } from "../lib/model";
import { AWAY, CLUB_ONE, CLUB_TWO, HOME, PLAYERS, type ClubSpec, type Person } from "../lib/people";
import { check, inningsLine, save, summary } from "../lib/summary";

test.describe.configure({ mode: "serial" });

const OVERS = 5;

// Innings one: Club One bat. Each over is six legal balls plus its extras,
// and between them every kind of ball the plan asks for.
const FIRST: Ball[][] = [
  [{ t: "runs", runs: 0 }, { t: "runs", runs: 1 }, { t: "runs", runs: 4 }, { t: "wicket", kind: "bowled" },
   { t: "runs", runs: 2 }, { t: "wide", runs: 0 }, { t: "runs", runs: 6 }],
  [{ t: "runs", runs: 1 }, { t: "runs", runs: 1 }, { t: "no_ball", runs: 0 }, { t: "runs", runs: 0 },
   { t: "runs", runs: 4 }, { t: "leg_bye", runs: 1 }, { t: "runs", runs: 2 }],
  [{ t: "bye", runs: 2 }, { t: "runs", runs: 0 }, { t: "runs", runs: 3 },
   { t: "wicket", kind: "caught", fielder: AWAY[3].name }, { t: "runs", runs: 1 }, { t: "runs", runs: 6 }],
  [{ t: "runs", runs: 0 }, { t: "runs", runs: 0 }, { t: "wide", runs: 1 }, { t: "runs", runs: 4 },
   { t: "runs", runs: 1 }, { t: "runs", runs: 1 }, { t: "runs", runs: 2 }],
  [{ t: "runs", runs: 6 }, { t: "runs", runs: 0 }, { t: "runs", runs: 1 }, { t: "runs", runs: 0 },
   { t: "runs", runs: 4 }, { t: "runs", runs: 1 }],
];
// Innings two: Club Two chase and fall short, so all five overs are bowled.
const SECOND: Ball[][] = [
  [{ t: "runs", runs: 1 }, { t: "runs", runs: 0 }, { t: "runs", runs: 2 }, { t: "wicket", kind: "bowled" },
   { t: "runs", runs: 1 }, { t: "runs", runs: 0 }],
  [{ t: "runs", runs: 4 }, { t: "runs", runs: 0 }, { t: "wide", runs: 0 }, { t: "runs", runs: 1 },
   { t: "runs", runs: 1 }, { t: "runs", runs: 0 }, { t: "runs", runs: 2 }],
  [{ t: "runs", runs: 0 }, { t: "wicket", kind: "caught", fielder: HOME[4].name }, { t: "runs", runs: 1 },
   { t: "runs", runs: 1 }, { t: "leg_bye", runs: 2 }, { t: "runs", runs: 0 }],
  [{ t: "runs", runs: 6 }, { t: "runs", runs: 0 }, { t: "runs", runs: 1 }, { t: "no_ball", runs: 1 },
   { t: "runs", runs: 0 }, { t: "runs", runs: 2 }, { t: "runs", runs: 1 }],
  [{ t: "runs", runs: 0 }, { t: "runs", runs: 1 }, { t: "wicket", kind: "bowled" }, { t: "runs", runs: 4 },
   { t: "runs", runs: 0 }, { t: "runs", runs: 1 }],
];

let club1: Actor;
let club2: Actor;
/// One browser the twenty-two players take turns at.
let players: Actor;
const clubs: { one?: ClubInfo; two?: ClubInfo } = {};
const links = new Map<string, string>();
let matchId = "";
let inn1: Innings;
let inn2: Innings;

/// Which account a step is using, for the failure report.
const as = (account: string) => test.info().annotations.push({ type: "account", description: account });

test.beforeAll(async ({ browser }, info) => {
  const videos = `${info.project.outputDir}/videos`;
  club1 = await actor(browser, CLUB_ONE.secretary, videos);
  club2 = await actor(browser, CLUB_TWO.secretary, videos);
  players = await actor(browser, PLAYERS[0], videos);
});

test.afterEach(async ({}, info) => {
  save();
  if (info.status === info.expectedStatus) return;
  // Every open browser, as it was when the step failed — saved as files, so
  // they go up with the run's artifacts and into Slack.
  for (const a of [club1, club2, players]) {
    if (!a || a.page.isClosed()) continue;
    const path = info.outputPath(`${a.who.key}.png`);
    const shot = await a.page.screenshot({ path, fullPage: true }).catch(() => null);
    if (shot) await info.attach(`${a.who.key} (${a.who.name}) at ${new URL(a.page.url()).pathname}`, { path, contentType: "image/png" });
  }
});

test.afterAll(async () => {
  save();
  for (const a of [club1, club2, players]) await a?.context.close();
});

// ---------------------------------------------------------------------------

async function clubAccount(a: Actor, spec: ClubSpec, key: "one" | "two") {
  const status = await ensureAccount(a);
  summary.accounts[status].push(spec.secretary.name);
  check("Accounts", `${spec.name} account works`, true, status);

  // Login works: the dashboard greets them by name — the greeting itself,
  // not whatever heading the page happens to start with.
  await a.page.goto("/");
  await expect(a.page.locator("main h1").first()).toHaveText(
    new RegExp(`^Good (morning|afternoon|evening), ${spec.secretary.name.split(" ")[0]}$`)
  );
  const me = await storedUser(a.page);
  expect(me?.role_intent, "registered as someone who runs a club").toBe("secretary");

  const club = await ensureClub(a, spec);
  clubs[key] = club;
  check("Clubs", `${spec.name} created`, true, club.status);

  // The club page opened (ensureClub checked its heading). Its details:
  const roster = await members(a.page, club.id);
  const sec = roster.find((m) => m.name === spec.secretary.name);
  expect(sec?.role, "the founder is the club's secretary").toBe("club_admin");
  check("Accounts", `${spec.name} secretary role is correct`, sec?.role === "club_admin", sec?.role);

  // The link under the club's code opens the club. To its own secretary it is
  // something to send, not something to play against.
  await a.page.goto(pathOf(club.codeLink));
  await expect(a.page.getByRole("heading", { name: spec.name })).toBeVisible();
  await expect(a.page.getByText(/This is your own code/)).toBeVisible();
  await expect(a.page.getByRole("link", { name: /Start a match against/ })).toHaveCount(0);
  const sameSite = new URL(club.codeLink).origin === new URL(BASE_URL).origin;
  if (!/localhost|127\.0\.0\.1/.test(BASE_URL)) {
    expect.soft(new URL(club.codeLink).origin, "the code's link points at this site").toBe(new URL(BASE_URL).origin);
  }
  check("Clubs", "Club profile links work", sameSite || /localhost|127\.0\.0\.1/.test(BASE_URL), club.codeLink);
  summary.clubs[key] = { id: club.id, name: spec.name, players: 0 };
}

test("Step 1 — Club 1 account and club", async () => {
  as(`${CLUB_ONE.secretary.name} (${CLUB_ONE.secretary.email}) — runs ${CLUB_ONE.name}`);
  await clubAccount(club1, CLUB_ONE, "one");
});

test("Step 2 — Club 2 account and club", async () => {
  as(`${CLUB_TWO.secretary.name} (${CLUB_TWO.secretary.email}) — runs ${CLUB_TWO.name}`);
  // Log out from Club 1 first: signing out has to actually end the session.
  await signOut(club1.page);
  await clubAccount(club2, CLUB_TWO, "two");
});

// ---------------------------------------------------------------------------

/// Put the shared players' browser in `who`'s hands.
async function switchTo(who: Person) {
  await players.page.goto("/login");
  await stableEval(players.page, () => players.page.evaluate(() => localStorage.clear()));
  players.who = who;
  return ensureAccount(players);
}

test("Step 3 — 22 player accounts", async () => {
  as("each of E2E Player 01–22, in turn");
  for (const who of PLAYERS) {
    await test.step(who.name, async () => {
      const status = await switchTo(who);
      summary.accounts[status].push(who.name);
      const me = await storedUser(players.page);
      expect(me?.role_intent, `${who.name} registered as a player, not a club`).toBe("player");
      const mine = await apiGet<unknown[]>(players.page, "/clubs");
      // A player never runs a club: any club they are in, they joined.
      const running = [];
      for (const c of mine as { id: string }[]) {
        const role = await apiGet<{ is_secretary: boolean }>(players.page, `/clubs/${c.id}/my-role`);
        if (role.is_secretary) running.push(c.id);
      }
      expect(running, `${who.name} is nobody's secretary`).toEqual([]);

      // Their profile opens and has a link to share.
      const link = await profileLink(players.page);
      for (const part of [who.name.replace(/ \d+$/, ""), who.name.split(" ").pop()!]) {
        await expect(players.page.locator("main"), "their profile shows their name").toContainText(part);
      }
      links.set(who.key, link);
      await players.page.goto(pathOf(link));
      await expect(players.page.getByRole("heading", { name: "This is your own link" })).toBeVisible();
    });
  }
  check("Accounts", "22 player accounts work", links.size === 22, `${links.size} profile links`);
  check("Accounts", "Player roles are correct", true);
});

// ---------------------------------------------------------------------------

/// A secretary adds each player from their profile link; each player then
/// approves it from their own dashboard. Players already in the club (a
/// second run) are left alone.
async function fillClub(sec: Actor, club: ClubInfo, squad: Person[], others: Person[]) {
  const before = await members(sec.page, club.id);
  const missing = squad.filter((p) => !before.some((m) => m.name === p.name && m.status === "active"));

  for (const who of missing) {
    await test.step(`${club.name} adds ${who.name} by link`, async () => {
      await sec.page.goto(`/clubs/${club.id}#members`);
      await clearOverlays(sec.page);
      const form = sec.page.locator("form.add-by-link");
      // Pasted the way it arrives: inside a message.
      await form.locator("input").fill(`Hi, it's ${who.name} — ${links.get(who.key)}`);
      await form.locator('button[type="submit"]').click();
      await sec.page.waitForURL(/\/p\/[A-Za-z0-9]+/);
      await expect(sec.page.locator("main h1"), "the link shows the right player").toHaveText(who.name);
      await sec.page.getByRole("button", { name: `Add to ${club.name}` }).click();
      await expect(sec.page.locator(".invite-sent")).toBeVisible();
    });
  }
  for (const who of missing) {
    await test.step(`${who.name} accepts ${club.name}`, async () => {
      await switchTo(who);
      await players.page.goto("/");
      await clearOverlays(players.page);
      const row = players.page.locator("#pending-invites li", { hasText: club.name });
      await expect(row, "the invite is waiting on their dashboard").toBeVisible();
      await clickPast(players.page, row.getByRole("button", { name: /Accept/ }));
      await expect(row).toHaveCount(0);
    });
  }

  // What the club now holds, from its own members list.
  const roster = await members(sec.page, club.id);
  const e2ePlayers = roster.filter((m) => m.name.startsWith("E2E Player"));
  const names = e2ePlayers.map((m) => m.name).sort();
  expect(names, `${club.name} has exactly its eleven`).toEqual(squad.map((p) => p.name).sort());
  expect(new Set(e2ePlayers.map((m) => m.user_id)).size, "no one twice").toBe(e2ePlayers.length);
  expect(e2ePlayers.every((m) => m.role === "member" && m.status === "active"), "all active members").toBe(true);
  const strays = e2ePlayers.filter((m) => others.some((o) => o.name === m.name));
  expect(strays, `none of the other club's players`).toEqual([]);

  // And on the club's page, where a secretary would look.
  await sec.page.goto(`/clubs/${club.id}#members`);
  for (const who of squad) await expect(sec.page.locator("table.table")).toContainText(who.name);

  return { added: missing.length, total: e2ePlayers.length };
}

test("Step 4 — Club 1 adds players 1–11", async () => {
  as(`${CLUB_ONE.secretary.name}, then players 1–11 approving`);
  expect(await signIn(club1.page, CLUB_ONE.secretary), "Club 1 signs back in").toBe(true);
  const r = await fillClub(club1, clubs.one!, HOME, AWAY);
  summary.clubs.one.players = r.total;
  check("Clubs", "Club 1 has 11 correct players", r.total === 11, `${r.added} added this run`);
});

test("Step 5 — Club 2 adds players 12–22", async () => {
  as(`${CLUB_TWO.secretary.name}, then players 12–22 approving`);
  const r = await fillClub(club2, clubs.two!, AWAY, HOME);
  summary.clubs.two.players = r.total;
  check("Clubs", "Club 2 has 11 correct players", r.total === 11, `${r.added} added this run`);
});

// ---------------------------------------------------------------------------

const state = (page: Page) => apiGet<any>(page, `/cricket/matches/${matchId}`).then((m) => m.state);

test("Step 6 — Start a match against Club 2 from its link", async () => {
  as(CLUB_ONE.secretary.name);
  const page = club1.page;
  // Club 2's link, from the bottom of Club 2's page.
  await page.goto(pathOf(clubs.two!.codeLink));
  await expect(page.getByRole("heading", { name: CLUB_TWO.name })).toBeVisible();
  await page.getByRole("link", { name: new RegExp(`Start a match against ${CLUB_TWO.name}`) }).click();
  await page.waitForURL(/\/score\?against=/);
  const sheet = page.locator(".sheet[role=dialog]");
  await expect(sheet).toBeVisible();
  await expect(sheet, "Club 2 is the opposition").toContainText(`Matched to ${CLUB_TWO.name}`);
  check("Match", "Opposition club can be selected", true);
});

test("Step 7 — Create the 5-over match", async () => {
  as(CLUB_ONE.secretary.name);
  const page = club1.page;
  const sheet = page.locator(".sheet[role=dialog]");
  await sheet.getByRole("button", { name: "Friendly", exact: true }).click();
  await sheet.getByRole("button", { name: CLUB_ONE.name, exact: true }).click();
  await sheet.locator(".sheet-actions").getByRole("button", { name: "Start match" }).click();
  await page.waitForURL(/\/score\/[0-9a-f-]{36}$/);
  matchId = page.url().split("/").pop()!;
  summary.match = { id: matchId, url: `${BASE_URL}/score/${matchId}` };

  await expect(page.locator(".match-head-side").first()).toHaveText(CLUB_ONE.name);
  await expect(page.locator(".match-head-side.away")).toHaveText(CLUB_TWO.name);

  // Whoever scores takes the book — once the page is up (isVisible does not wait).
  await expect(page.getByRole("heading", { name: "Agree the terms" })).toBeVisible();
  const take = page.getByRole("button", { name: "Take the book" });
  if (await take.isVisible()) await take.click();
  await expect(take).toHaveCount(0);
  const held = await apiGet<any>(page, `/cricket/matches/${matchId}`);
  expect(held.active_scorer_user_id, "Club 1's captain holds the book").toBe((await storedUser(page))!.id);

  // Five overs, a two-over powerplay, two overs a bowler at most.
  await page.getByLabel("Overs", { exact: true }).fill(String(OVERS));
  await page.getByLabel(/^Overs per bowler/).fill("2");
  await page.getByLabel("Powerplay overs", { exact: true }).fill("2");
  const m = await apiGet<any>(page, `/cricket/matches/${matchId}`);
  expect(m.opponent_club_id, "the match is against Club 2 on Fishers").toBe(clubs.two!.id);
  check("Match", "Match can be created", true, matchId);
});

test("Step 8 — Propose the terms to Club 2's captain", async () => {
  as(CLUB_ONE.secretary.name);
  const page = club1.page;
  await page.getByRole("combobox", { name: `Captain of ${CLUB_ONE.name}` }).fill(CLUB_ONE.secretary.name);
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Propose these terms" }).click();
  await expect(page.getByRole("heading", { name: `Waiting on ${CLUB_TWO.name}` })).toBeVisible();
  const overs = page.locator(".terms-summary div", { hasText: /^Overs/ }).first();
  await expect(overs.locator("dd"), "the terms say five overs").toHaveText(String(OVERS));

  const st = await state(page);
  expect(st.conditions.overs_limit, "5 overs saved").toBe(OVERS);
  expect(st.agreed_home, "proposed by Club 1's captain").toBe(CLUB_ONE.secretary.name);
  check("Match", "5-over match can be created", st.conditions.overs_limit === OVERS);
  check("Match", "Match proposal can be sent", true);
});

test("Step 9 — Club 2's captain sees the proposal", async () => {
  as(CLUB_TWO.secretary.name);
  const page = club2.page;
  await page.goto("/notifications");
  // Accounts are reused, so earlier runs' notifications are here too: this
  // match's is the one that links to it.
  const note = page.locator(`a[href="/score/${matchId}"]`, { hasText: /proposed the terms/ }).first();
  await expect(note, "the proposal is in Club 2's notifications").toBeVisible();
  await note.click();
  await page.waitForURL(new RegExp(`/score/${matchId}$`));

  await expect(page.getByRole("heading", { name: "Do you accept these terms?" })).toBeVisible();
  await expect(page.locator(".match-head-side").first()).toHaveText(CLUB_ONE.name);
  await expect(page.locator(".match-head-side.away")).toHaveText(CLUB_TWO.name);
  const overs = page.locator(".terms-summary div", { hasText: /^Overs/ }).first();
  await expect(overs.locator("dd")).toHaveText(String(OVERS));
  await expect(page.locator(".agree-card").first()).toContainText(CLUB_ONE.secretary.name);
  check("Match", "Opposition captain receives proposal", true);
});

test("Step 10 — Club 2's captain accepts", async () => {
  as(CLUB_TWO.secretary.name);
  const page = club2.page;
  await page.getByRole("combobox", { name: "Your captain's name" }).fill(CLUB_TWO.secretary.name);
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: `Accept — ${CLUB_TWO.secretary.name}` }).click();
  await expect(page.getByRole("heading", { name: "Waiting on the toss" })).toBeVisible();
  await expect(page.locator(".rail-step.done", { hasText: "Terms" })).toBeVisible();
  const st = await state(page);
  expect(st.agreed_away).toBe(CLUB_TWO.secretary.name);
  check("Match", "Proposal can be accepted", true);
});

test("Step 12 — The toss (the app records it before the team sheets)", async () => {
  as(CLUB_ONE.secretary.name);
  const page = club1.page;
  await page.goto(`/score/${matchId}`);
  await expect(page.getByRole("heading", { name: "The toss" })).toBeVisible();
  await page.locator(".side-card", { hasText: CLUB_ONE.name }).click();
  await page.locator(".side-card", { hasText: "Bat" }).click();
  await page.getByRole("button", { name: `${CLUB_ONE.name} chose to bat` }).click();
  await expect(page.locator(".toss-result")).toContainText(`${CLUB_ONE.name} won the toss and chose to bat`);
  const st = await state(page);
  expect([st.toss_winner, st.toss_decision]).toEqual(["home", "bat"]);
  summary.toss = `${CLUB_ONE.name} won the toss and chose to bat`;
  check("Toss", "Toss works", true);
  check("Toss", "Toss winner is saved", st.toss_winner === "home");
  check("Toss", "Bat/Bowl decision works", st.toss_decision === "bat");
});

/// A captain names their eleven, in batting order, with a captain and keeper.
async function pickXi(a: Actor, club: ClubSpec, squad: Person[], others: Person[], side: "home" | "away") {
  const page = a.page;
  const sheet = page.locator(".sheet-panel", { has: page.getByRole("heading", { name: club.name, exact: true }) });
  await expect(sheet).toBeVisible();
  const offered = (await sheet.locator(".squad-chip").allInnerTexts()).map((t) => t.trim());
  for (const p of squad) expect(offered.some((o) => o.startsWith(p.name)), `${p.name} is in the squad`).toBe(true);
  const intruders = offered.filter((o) => others.some((p) => o.startsWith(p.name)));
  expect(intruders, "no one from the other club").toEqual([]);

  for (const p of squad) await sheet.locator(".squad-chip", { hasText: p.name }).click();
  await expect(sheet.locator(".count-pill")).toContainText("11");
  await sheet.locator(".picked-xi li", { hasText: squad[0].name }).getByRole("button", { name: "C", exact: true }).click();
  await sheet.locator(".picked-xi li", { hasText: squad[1].name }).getByRole("button", { name: "WK", exact: true }).click();
  await sheet.getByRole("button", { name: `Confirm ${club.name}` }).click();

  // The first side named stays on screen as a team sheet; naming the second
  // moves the page straight on to the openers.
  const named = page.locator(".sheet-panel.done", { has: page.getByRole("heading", { name: club.name, exact: true }) });
  const next = page.getByRole("heading", { name: /Who is opening\?|Waiting for the first ball/ });
  await expect(named.or(next).first()).toBeVisible();
  if (await named.isVisible()) {
    await expect(named.locator(".named-xi li")).toHaveText(squad.map((p) => new RegExp(`^${p.name}`)));
  }

  const st = await state(page);
  const xi: string[] = side === "home" ? st.home_xi : st.away_xi;
  expect(xi.map((id) => st.player_names[id]), "saved in batting order").toEqual(squad.map((p) => p.name));
  expect(st.player_names[side === "home" ? st.home_captain : st.away_captain]).toBe(squad[0].name);
}

test("Step 10b — Club 2 names its Playing XI", async () => {
  as(CLUB_TWO.secretary.name);
  const page = club2.page;
  await page.goto("/notifications");
  const note = page.locator(`a[href="/score/${matchId}"]`, { hasText: /the toss is done/ }).first();
  await expect(note, "Club 2 is told it is their turn").toBeVisible();
  await note.click();
  await page.waitForURL(new RegExp(`/score/${matchId}$`));
  await pickXi(club2, CLUB_TWO, AWAY, HOME, "away");
});

test("Step 11 — Club 1 names its Playing XI", async () => {
  as(CLUB_ONE.secretary.name);
  const page = club1.page;
  await page.goto(`/score/${matchId}`);
  await pickXi(club1, CLUB_ONE, HOME, AWAY, "home");
  await expect(page.getByRole("heading", { name: "Who is opening?" })).toBeVisible();
  check("Match", "Both teams can select Playing 11", true);
});

// ---------------------------------------------------------------------------

const EXTRA_LABEL = { wide: "Wide", no_ball: "No ball", bye: "Bye", leg_bye: "Leg bye" } as const;

async function deliver(page: Page, ball: Ball) {
  // A notification toast can land over the controls mid-over.
  if (await page.locator(".live-alert").count()) await clearOverlays(page);
  const controls = page.locator(".controls");
  const sheet = page.locator(".sheet[role=dialog]");
  if (ball.t === "runs") {
    await controls.locator(".dial").getByRole("button", { name: String(ball.runs), exact: true }).click();
  } else if (ball.t === "wicket") {
    await controls.getByRole("button", { name: "Wicket", exact: true }).click();
    await sheet.getByRole("button", { name: ball.kind === "bowled" ? "Bowled" : "Caught", exact: true }).click();
    if (ball.fielder) await sheet.getByLabel("Fielder").selectOption({ label: ball.fielder });
    await sheet.getByRole("button", { name: "Record wicket" }).click();
    await expect(sheet).toHaveCount(0);
  } else {
    await controls.getByRole("button", { name: EXTRA_LABEL[ball.t], exact: true }).click();
    await sheet.locator(".dial").getByRole("button", { name: String(ball.runs), exact: true }).click();
    await sheet.getByRole("button", { name: "Record", exact: true }).click();
    await expect(sheet).toHaveCount(0);
  }
}

const describe = (b: Ball) =>
  b.t === "runs" ? (b.runs === 0 ? "dot" : `${b.runs}`) : b.t === "wicket" ? `W (${b.kind})` : `${b.t}+${b.runs}`;

/// Score an innings ball by ball, checking the app against the model after
/// every one: total, wickets, overs, who is on strike, who is bowling.
async function playInnings(page: Page, inn: Innings, script: Ball[][], bowlers: string[]) {
  for (let o = 0; o < script.length; o++) {
    await test.step(`Over ${o + 1} — ${bowlers[o]}: ${script[o].map(describe).join(" ")}`, async () => {
      if (o > 0) {
        await expect(page.getByRole("heading", { name: /who bowls next\?/ })).toBeVisible();
        await page.locator(".bowler-options button", { hasText: bowlers[o] }).first().click();
        inn.setBowler(bowlers[o]);
      }
      await expect(page.locator(".card.bowler .who-name")).toHaveText(bowlers[o]);
      for (const ball of script[o]) {
        await expect(page.locator(".card.on-strike .who-name"), "on strike before the ball").toContainText(inn.striker);
        await deliver(page, ball);
        inn.apply(ball);
        if (inn.complete) break;
        await expect(page.locator(".scoreline"), `after ${describe(ball)}`).toHaveText(inn.scoreline);
        await expect(page.locator(".matchbar")).toContainText(`(${inn.overs} of ${OVERS} ov)`);
      }
    });
  }
}

type Row = string[];

/// The scorecard as the page shows it, innings `index`.
async function readScorecard(page: Page, index: number) {
  const card = page.locator(".panel", { has: page.locator("h3.section-head", { hasText: / batting$/ }) }).last();
  const tabs = card.locator(".innings-tab");
  if (await tabs.count()) await tabs.nth(index).click();
  const rows = (table: number) =>
    card.locator("table.table").nth(table).locator("tbody tr").evaluateAll((trs) =>
      trs.map((tr) => [...tr.querySelectorAll("td")].map((td) => (td as HTMLElement).innerText.trim()))
    ) as Promise<Row[]>;
  return { batting: await rows(0), bowling: await rows(1) };
}

async function verifyScorecard(page: Page, index: number, inn: Innings, label: string) {
  const { batting, bowling } = await readScorecard(page, index);
  const firstLine = (cell: string) => cell.split("\n")[0].replace(/[\s ]\*$/, "").trim();
  for (const b of inn.batters.values()) {
    if (b.balls === 0 && !b.out && b.name !== inn.striker && b.name !== inn.nonStriker) continue;
    const row = batting.find((r) => firstLine(r[0]) === b.name);
    expect(row, `${label}: ${b.name} is on the card`).toBeTruthy();
    expect(row!.slice(1, 5).map(Number), `${label}: ${b.name} R B 4s 6s`).toEqual([b.runs, b.balls, b.fours, b.sixes]);
    expect(row![0].toLowerCase().includes("not out"), `${label}: ${b.name} ${b.out ? "out" : "not out"}`).toBe(!b.out);
  }
  const extras = batting.find((r) => r[0].startsWith("Extras"));
  expect(Number(extras?.[1]), `${label}: extras`).toBe(inn.extras);
  const breakdown = [
    inn.byes && `b ${inn.byes}`,
    inn.legByes && `lb ${inn.legByes}`,
    inn.wides && `w ${inn.wides}`,
    inn.noBalls && `nb ${inn.noBalls}`,
  ].filter(Boolean).join(", ");
  expect(extras?.[0], `${label}: extras breakdown`).toContain(`(${breakdown})`);
  const total = batting.find((r) => r[0].startsWith("Total"));
  expect(total?.[1], `${label}: total`).toBe(inn.scoreline.replace("/", "-"));
  expect(total?.[0], `${label}: overs`).toContain(`${inn.overs} ov`);

  for (const bw of inn.bowlers.values()) {
    const row = bowling.find((r) => r[0] === bw.name);
    expect(row, `${label}: ${bw.name} bowled`).toBeTruthy();
    const o = `${Math.floor(bw.balls / 6)}.${bw.balls % 6}`;
    expect([row![1], row![2], row![3], row![4]], `${label}: ${bw.name} O M R W`).toEqual([
      o, String(bw.maidens), String(bw.runs), String(bw.wickets),
    ]);
  }
}

test("Step 13 — First innings: Club 1 bat, five overs", async () => {
  as(`${CLUB_ONE.secretary.name}, holding the book`);
  const page = club1.page;
  inn1 = new Innings(HOME.map((p) => p.name), AWAY[0].name, OVERS);
  // The defaults are the first two in the order and Club 2's first player.
  await page.getByRole("button", { name: "Start the innings" }).click();
  await playInnings(page, inn1, FIRST, AWAY.slice(0, 5).map((p) => p.name));

  await expect(page.getByRole("heading", { name: "Innings 2" }), "the innings closes at five overs").toBeVisible();
  await verifyScorecard(page, 0, inn1, "1st innings");
  inningsLine(CLUB_ONE.name, inn1);
  check("Scoring", "First innings scoring works", true, `${inn1.scoreline} (${inn1.overs})`);
  check("Scoring", "Runs calculate correctly", true);
  check("Scoring", "Wickets work", true);
  check("Scoring", "Extras work", true, `${inn1.extras} extras`);
  check("Scoring", "Overs calculate correctly", true);
  check("Scoring", "Player statistics update correctly", true);
});

test("Step 14 — Hand the book to Club 2's captain", async () => {
  as(CLUB_ONE.secretary.name);
  const page = club1.page;
  await clearOverlays(page);
  // Offered on the innings-break panel itself — the moment the book actually
  // changes hands — and not only behind the ⋯ menu.
  const pass = page.getByRole("button", { name: /^Hand the book to/ });
  await expect(pass, "the break offers the book to the side batting next").toContainText(CLUB_TWO.name);
  await pass.click();
  const dialog = page.getByRole("dialog", { name: "Hand over the book" });
  await expect(dialog).toBeVisible();
  // Open on the side about to bat: their names are listed without a tap.
  await expect(
    dialog.locator(".people-tabs [role=tab][aria-selected=true]"),
    "the sheet opens on the side batting next"
  ).toContainText(CLUB_TWO.name);
  await dialog.locator(".people-list button", { hasText: CLUB_TWO.secretary.name }).click();
  await dialog.getByRole("button", { name: "Hand it over" }).click();
  await expect(dialog).toHaveCount(0);

  const m = await apiGet<any>(page, `/cricket/matches/${matchId}`);
  const club2Id = (await storedUser(club2.page))!.id;
  expect(m.active_scorer_user_id, "Club 2's captain holds the book").toBe(club2Id);
  // Club 1 can no longer score: no controls, and the page says who can.
  await page.reload();
  await expect(page.getByText(/Someone else is scoring this match/)).toBeVisible();
  await expect(page.getByRole("button", { name: "Start the innings" })).toHaveCount(0);
  check("Scoring", "Scorebook handover works", true);
});

test("Step 15 — Club 2's captain has the book", async () => {
  as(`${CLUB_TWO.secretary.name}, now holding the book`);
  const page = club2.page;
  // Told, rather than left to discover it: the book usually crosses at the
  // break to somebody whose phone is in a bag, and until they open it nobody
  // is scoring.
  const notes = await apiGet<{ items: { type: string; payload: { match_id?: string } }[] }>(
    page,
    "/notifications?per_page=50"
  );
  const told = notes.items.filter(
    (n) => n.type === "match_book_handed_over" && n.payload?.match_id === matchId
  );
  expect(told, "Club 2's captain is told they have the book").toHaveLength(1);

  await page.goto(`/score/${matchId}`);
  await expect(page.getByRole("heading", { name: "Innings 2" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Start the innings" })).toBeEnabled();
  await expect(page.locator(".setup-head")).toContainText(`chasing ${inn1.runs + 1}`);
  // They are the side batting, so they are not invited to hand it to themselves.
  await expect(
    page.getByRole("button", { name: /Hand the book to/ }),
    "the offer is not made to the side about to bat"
  ).toHaveCount(0);
  // The first innings, exactly as Club 1 left it.
  await verifyScorecard(page, 0, inn1, "1st innings, seen by Club 2");
  check("Scoring", "Second captain receives the book", true);
  check("Scoring", "Handover is offered at the innings break", true);
  check("Notifications", "New scorer is told they have the book", true);
});

test("Step 16 — Second innings: Club 2 bat, five overs", async () => {
  as(`${CLUB_TWO.secretary.name}, holding the book`);
  const page = club2.page;
  inn2 = new Innings(AWAY.map((p) => p.name), HOME[0].name, OVERS);
  // Taking the book now sends its own alert, and it lands over this panel.
  await clearOverlays(page);
  await page.getByRole("button", { name: "Start the innings" }).click();
  await expect(page.locator(".matchbar")).toContainText(`${inn1.runs + 1} needed`);
  await playInnings(page, inn2, SECOND, HOME.slice(0, 5).map((p) => p.name));
  await expect(page.locator(".result-panel"), "the match ends after both innings").toBeVisible();
  inningsLine(CLUB_TWO.name, inn2);
  check("Scoring", "Second innings scoring works", true, `${inn2.scoreline} (${inn2.overs})`);
});

test("Step 17 — The result", async () => {
  as(`${CLUB_TWO.secretary.name}, then ${CLUB_ONE.secretary.name}`);
  // However it finished: the side batting first wins by runs, the side
  // chasing wins by the wickets it had left, or it is tied.
  const margin = inn1.runs - inn2.runs;
  const expected =
    margin > 0
      ? `${CLUB_ONE.name} won by ${margin} runs`
      : margin < 0
        ? `${CLUB_TWO.name} won by ${AWAY.length - 1 - inn2.wickets} wickets`
        : "Match tied";

  for (const a of [club2, club1]) {
    const page = a.page;
    await page.goto(`/score/${matchId}`);
    await expect(page.locator(".result-line"), `${a.who.name} sees the result`).toContainText(expected);
    await expect(page.locator(".status-pill")).toHaveText(/complete/i);
    const sides = page.locator(".result-side");
    await expect(sides.nth(0)).toContainText(`${inn1.runs}-${inn1.wickets}`);
    await expect(sides.nth(0)).toContainText(`(${inn1.overs} ov)`);
    await expect(sides.nth(1)).toContainText(`${inn2.runs}-${inn2.wickets}`);
    await expect(sides.nth(1)).toContainText(`(${inn2.overs} ov)`);
    await verifyScorecard(page, 0, inn1, `1st innings (${a.who.name})`);
    await verifyScorecard(page, 1, inn2, `2nd innings (${a.who.name})`);
  }

  const st = await state(club1.page);
  expect(st.status).toBe("complete");
  expect(st.margin).toBe(expected);
  expect(st.winner).toBe(margin > 0 ? "home" : margin < 0 ? "away" : null);
  expect([st.toss_winner, st.toss_decision], "toss kept").toEqual(["home", "bat"]);
  expect(st.home_xi.map((id: string) => st.player_names[id]), "Club 1's XI kept").toEqual(HOME.map((p) => p.name));
  expect(st.away_xi.map((id: string) => st.player_names[id]), "Club 2's XI kept").toEqual(AWAY.map((p) => p.name));

  summary.result = st.margin;
  check("Scoring", "Final score is correct", true, `${inn1.scoreline} v ${inn2.scoreline}`);
  check("Scoring", "Match result is correct", st.margin === expected, st.margin);
});

test("Step 18 — Final end-to-end checks", async () => {
  const failed = summary.checks.filter((c) => !c.ok);
  expect(failed, "every check in the Step 18 list").toEqual([]);
  // Named, not counted: a step that quietly stopped recording its checks
  // would still pass a count.
  const required = [
    "22 player accounts work",
    "Player roles are correct",
    "Club 1 has 11 correct players",
    "Club 2 has 11 correct players",
    "Club profile links work",
    "Opposition club can be selected",
    "Match can be created",
    "5-over match can be created",
    "Match proposal can be sent",
    "Opposition captain receives proposal",
    "Proposal can be accepted",
    "Both teams can select Playing 11",
    "Toss works",
    "Toss winner is saved",
    "Bat/Bowl decision works",
    "First innings scoring works",
    "Runs calculate correctly",
    "Wickets work",
    "Extras work",
    "Overs calculate correctly",
    "Player statistics update correctly",
    "Scorebook handover works",
    "Handover is offered at the innings break",
    "New scorer is told they have the book",
    "Second captain receives the book",
    "Second innings scoring works",
    "Final score is correct",
    "Match result is correct",
  ];
  const ran = new Set(summary.checks.map((c) => c.check));
  expect([...required].filter((c) => !ran.has(c)), "every listed check ran").toEqual([]);
});
