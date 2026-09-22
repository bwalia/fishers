/**
 * Inviting a club into a tournament, and selling a ticket to somebody who is
 * not a member of the club running it.
 *
 * Two things the app could not do before, and both are conversations between
 * two clubs rather than one club's own screen — so both sides are driven here,
 * in their own browsers, through the real UI.
 *
 * Reuses the two clubs the full-match journey makes (lib/people.ts), so it
 * costs two sign-ins rather than twenty-four registrations. Every account and
 * club helper is idempotent: run this file alone and it makes what it needs.
 */
import { expect, test } from "@playwright/test";
import {
  actor,
  apiGet,
  clearOverlays,
  ensureAccount,
  ensureClub,
  type Actor,
  type ClubInfo,
} from "../lib/app";
import { CLUB_ONE, CLUB_TWO } from "../lib/people";
import { check, save } from "../lib/summary";

test.describe.configure({ mode: "serial" });

/// The host, who runs the tournament and sells the tickets.
let host: Actor;
/// The guest, who is asked in and who buys a ticket as an outsider.
let guest: Actor;
let hostClub: ClubInfo;
let guestClub: ClubInfo;
/// Named per run so re-running never collides with the last one's entry.
const TOURNAMENT = `E2E Sixes ${Date.now().toString(36).slice(-5)}`;
let blockId = "";
let ticketedEventId = "";

test.beforeAll(async ({ browser }, info) => {
  const videos = `${info.project.outputDir}/videos`;
  host = await actor(browser, CLUB_ONE.secretary, videos);
  guest = await actor(browser, CLUB_TWO.secretary, videos);
});

test.afterEach(async ({}, info) => {
  save();
  if (info.status === info.expectedStatus) return;
  for (const a of [host, guest]) {
    if (!a || a.page.isClosed()) continue;
    const path = info.outputPath(`${a.who.key}.png`);
    const shot = await a.page.screenshot({ path, fullPage: true }).catch(() => null);
    if (shot) {
      await info.attach(`${a.who.key} at ${new URL(a.page.url()).pathname}`, {
        path,
        contentType: "image/png",
      });
    }
  }
});

test.afterAll(async () => {
  save();
  for (const a of [host, guest]) await a?.context.close();
});

test("1. both clubs exist, and their secretaries are signed in", async () => {
  await ensureAccount(host);
  await ensureAccount(guest);
  hostClub = await ensureClub(host, CLUB_ONE);
  guestClub = await ensureClub(guest, CLUB_TWO);
  expect(hostClub.id).not.toBe(guestClub.id);
  check("entries", "two clubs, two secretaries", true, `${hostClub.name} · ${guestClub.name}`);
});

test("2. the host starts a tournament", async () => {
  const page = host.page;
  await page.goto("/tournaments");
  await clearOverlays(page);
  await page.getByRole("button", { name: /New tournament/ }).click();
  await page.locator('input[placeholder="Summer Sixes"]').fill(TOURNAMENT);
  await page.getByRole("button", { name: "Create it" }).click();

  await expect(page.getByRole("link", { name: new RegExp(TOURNAMENT) })).toBeVisible();
  await page.getByRole("link", { name: new RegExp(TOURNAMENT) }).click();
  await page.waitForURL(/\/tournaments\/[0-9a-f-]{36}/);
  blockId = page.url().match(/\/tournaments\/([0-9a-f-]{36})/)![1];
  check("entries", "tournament created", true, TOURNAMENT);
});

test("3. the host asks the other club in, and it is not yet in the draw", async () => {
  const page = host.page;
  await page.goto(`/tournaments/${blockId}`);
  await clearOverlays(page);

  // By their code, not by searching: an invite-only club is deliberately not
  // findable by name, so the link they send you is how you reach them. The
  // picker is the same one used to name a fixture's opposition.
  const invite = page.locator(".panel", { has: page.getByRole("heading", { name: "Invite a club" }) });
  await invite.getByRole("tab", { name: "Paste a link" }).click();
  await invite.getByLabel("Their code or link").fill(guestClub.codeLink);
  await invite.getByRole("button", { name: "Match" }).click();
  await expect(invite.getByText(`Matched ${CLUB_TWO.name}`)).toBeVisible();
  await invite.getByRole("button", { name: /Send the invitation/ }).click();

  await expect(page.getByText(/They decide whether to enter/)).toBeVisible();

  const entrants = await apiGet<{ name: string; status: string; club_id: string | null }[]>(
    page,
    `/fixture-blocks/${blockId}/entrants`
  );
  const asked = entrants.find((e) => e.club_id === guestClub.id);
  expect(asked, "the other club is on the entry list").toBeTruthy();
  expect(asked!.status, "asked, not entered").toBe("invited");
  check("entries", "invited, not yet in", true, `${asked!.name} is ${asked!.status}`);
});

test("4. the guest club sees it and accepts", async () => {
  const page = guest.page;
  await page.goto("/tournaments");
  await clearOverlays(page);

  const waiting = page.locator(".panel", {
    has: page.getByRole("heading", { name: "You have been asked" }),
  });
  await expect(waiting, "the invitation is on their tournaments screen").toBeVisible();
  await expect(waiting.getByText(TOURNAMENT)).toBeVisible();
  await expect(waiting.getByText(hostClub.name)).toBeVisible();

  await waiting
    .locator("li", { hasText: TOURNAMENT })
    .getByRole("button", { name: "Accept" })
    .click();

  await expect(waiting.getByText(TOURNAMENT)).toBeHidden();
  check("entries", "the invited club accepted for itself", true, guestClub.name);
});

test("5. the host sees them in, and the draw can be made", async () => {
  const page = host.page;
  await page.goto(`/tournaments/${blockId}`);
  await clearOverlays(page);

  const entrants = await apiGet<{ name: string; status: string; club_id: string | null }[]>(
    page,
    `/fixture-blocks/${blockId}/entrants`
  );
  expect(entrants.find((e) => e.club_id === guestClub.id)!.status).toBe("accepted");

  // One accepted side is not a tournament: enter a second so there is a
  // fixture to draw, and check the draw is made from accepted sides only.
  const sides = page.locator(".panel", { has: page.getByRole("heading", { name: "Enter sides yourself" }) });
  await sides.locator("textarea").fill("E2E Wanderers");
  await sides.getByRole("button", { name: /Enter them/ }).click();
  await expect(page.getByText("Entered 1 side.")).toBeVisible();

  await expect(page.locator(".hero-tags")).toContainText("2 in");
  check("entries", "accepted sides make the draw", true, "2 in");
});

test("6. a declined invitation keeps the side out of the draw", async () => {
  // A third side, asked and refused. It must not appear as a team on nought
  // points, and it must not be scheduled against anybody.
  const page = host.page;
  const invited = await page.request.post(
    `${await apiBase(page)}/fixture-blocks/${blockId}/invite`,
    {
      headers: await authHeader(page),
      data: { name: "E2E Declined CC", contact_email: "sec@declined.test" },
    }
  );
  expect(invited.ok(), "the off-platform side was asked").toBeTruthy();
  const { invite_link } = await invited.json();
  expect(invite_link, "a side with no account gets a link").toContain("/entry/");

  // Answered from the link, with nobody signed in — which is the whole point
  // of it. A fresh page, so no token is carried over.
  const stranger = await host.context.browser()!.newContext();
  const strangerPage = await stranger.newPage();
  await strangerPage.goto(new URL(invite_link).pathname);
  await expect(strangerPage.getByRole("heading", { name: "E2E Sixes", exact: false })).toBeVisible();
  await strangerPage.getByRole("button", { name: /No, we can't make it/ }).click();
  await expect(strangerPage.getByText(/Thanks for letting them know/)).toBeVisible();
  await stranger.close();

  const standings = await apiGet<{ name: string }[]>(page, `/fixture-blocks/${blockId}/standings`);
  expect(
    standings.some((s) => s.name === "E2E Declined CC"),
    "a side that declined is not in the table"
  ).toBeFalsy();
  check("entries", "a declined side stays out of the table", true, "E2E Declined CC");
});

test("7. the host puts tickets on sale, open to anyone", async () => {
  const page = host.page;
  // A fixture to sell tickets to. Made through the API because scheduling a
  // match is the full-match journey's job, not this one's.
  const start = new Date(Date.now() + 14 * 864e5);
  const created = await page.request.post(`${await apiBase(page)}/events`, {
    headers: await authHeader(page),
    data: {
      club_id: hostClub.id,
      sport: "cricket",
      event_subtype: "tournament",
      title: `${TOURNAMENT} finals day`,
      start_at: start.toISOString(),
      end_at: new Date(start.getTime() + 6 * 3600e3).toISOString(),
    },
  });
  expect(created.ok()).toBeTruthy();
  ticketedEventId = (await created.json()).id;

  await page.goto(`/events/${ticketedEventId}`);
  await clearOverlays(page);
  await page.getByRole("button", { name: "Sell tickets" }).click();

  const tickets = page.locator(".panel", { has: page.getByRole("heading", { name: "Tickets" }) });
  await tickets.getByPlaceholder("7.50").fill("5.00");
  await tickets.getByPlaceholder("80").fill("50");
  await tickets.getByRole("checkbox").check();
  await tickets.getByRole("button", { name: /Put them on sale/ }).click();
  await expect(page.getByText("Tickets are on sale.")).toBeVisible();

  const event = await apiGet<{ ticket_price_cents: number; tickets_public: boolean }>(
    page,
    `/events/${ticketedEventId}`
  );
  // Pounds in the box, pence in the database — "5.00" must not become 5p.
  expect(event.ticket_price_cents, "£5.00 saved as 500p").toBe(500);
  expect(event.tickets_public).toBe(true);
  check("tickets", "put on sale from the fixture screen", true, "£5.00, open to all");
});

test("8. someone from the other club buys one, and cannot see the guest list", async () => {
  const page = guest.page;
  await page.goto(`/events/${ticketedEventId}/tickets`);
  await clearOverlays(page);

  await expect(page.locator(".hero-tags")).toContainText("Open to all");
  await page.getByRole("button", { name: /Book 1 place/ }).click();
  await expect(page.getByText("Booked 1 place.")).toBeVisible();
  await expect(page.getByText("You are booked")).toBeVisible();

  // Not a member of the hosting club: the headcount, their own booking, and
  // nothing about anybody else or about the club's takings.
  await expect(
    page.getByRole("heading", { name: "Who is coming" }),
    "an outsider is not shown the guest list"
  ).toBeHidden();
  await expect(page.getByText("Taken"), "nor the club's takings").toBeHidden();

  const booking = await apiGet<{ can_see_everyone: boolean; tickets: unknown[] }>(
    page,
    `/events/${ticketedEventId}/tickets`
  );
  expect(booking.can_see_everyone).toBe(false);
  expect(booking.tickets, "only their own booking comes back").toHaveLength(1);
  check("tickets", "a non-member buys without seeing club business", true, guestClub.name);
});

test("9. the host sees the booking, and the money", async () => {
  const page = host.page;
  await page.goto(`/events/${ticketedEventId}/tickets`);
  await clearOverlays(page);

  await expect(page.getByRole("heading", { name: "Who is coming" })).toBeVisible();
  await expect(page.getByText(CLUB_TWO.secretary.name)).toBeVisible();
  await expect(page.locator(".pro-rail")).toContainText("Owed");
  check("tickets", "the organiser sees the booking and what is owed", true, "£5.00 outstanding");
});

/// The API origin this browser is talking to, read from the page rather than
/// assumed, so the suite works against a laptop and against a deployed ring.
async function apiBase(page: import("@playwright/test").Page): Promise<string> {
  return page.evaluate(() => {
    const port = 7312;
    if (!window.location.port) return `${window.location.origin}/api/v1`;
    return `${window.location.protocol}//${window.location.hostname}:${port}/api/v1`;
  });
}

async function authHeader(page: import("@playwright/test").Page) {
  const token = await page.evaluate(() => localStorage.getItem("fishers_access_token"));
  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}
