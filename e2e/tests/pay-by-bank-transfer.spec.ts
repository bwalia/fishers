import { test as base, expect, type APIRequestContext, type Page } from "@playwright/test";

import { API_PORT, WEB_PORT } from "../lib/ports";

/// Paying the club by bank transfer, on the web: a secretary adds the club's
/// bank details and sends the bill for a nets session; a player sees what
/// they owe, copies the details from the pay screen and taps "I've paid"; the
/// treasurer confirms it, and the player is all paid up.
///
/// Self-contained — it makes its own club, people and session through the
/// API, so it runs against any local stack:
///
///   ./scripts/start.sh --no-ios
///   cd e2e && npx playwright test tests/pay-by-bank-transfer.spec.ts
const WEB = process.env.WEB_BASE ?? `http://localhost:${WEB_PORT}`;
const API = `${process.env.API_BASE ?? `http://localhost:${API_PORT}`}/api/v1`;
const SHOTS = process.env.SHOT_DIR ?? "test-results";
const STAMP = Date.now();
const PASSWORD = "password123";

const test = base.extend({});
if (process.env.CHROME_BIN) {
  test.use({ launchOptions: { executablePath: process.env.CHROME_BIN } });
}

type Session = { access_token: string; refresh_token: string; user: { id: string; name: string } };

async function signup(request: APIRequestContext, name: string): Promise<Session & { email: string }> {
  const email = `e2e-pay-${STAMP}-${name.split(" ")[0].toLowerCase()}@t.test`;
  const res = await request.post(`${API}/auth/signup`, { data: { name, email, password: PASSWORD } });
  expect(res.ok(), `signed up ${name}`).toBeTruthy();
  return { ...(await res.json()), email };
}

async function call(request: APIRequestContext, s: Session, method: string, path: string, data?: unknown) {
  const res = await request.fetch(`${API}${path}`, {
    method,
    data,
    headers: { Authorization: `Bearer ${s.access_token}` },
  });
  expect(res.ok(), `${method} ${path} → ${res.status()} ${await res.text()}`).toBeTruthy();
  return res.status() === 204 ? null : res.json();
}

/// Signed in the way the app signs in — the session in localStorage — and
/// past the one-time quick start, which would otherwise take over Home.
async function signIn(page: Page, s: Session) {
  await page.goto(`${WEB}/login`);
  await page.evaluate(
    ([a, r, u]) => {
      localStorage.setItem("fishers_access_token", a as string);
      localStorage.setItem("fishers_refresh_token", r as string);
      localStorage.setItem("fishers_user", JSON.stringify(u));
      localStorage.setItem(`fishers:quick-start:${(u as { id: string }).id}`, "1");
    },
    [s.access_token, s.refresh_token, s.user],
  );
}

test("a secretary adds bank details, a player pays by transfer, the treasurer confirms it", async ({ page, request }) => {
  const owner = await signup(request, "Owen Owner");
  const secretary = await signup(request, "Sasha Secretary");
  const treasurer = await signup(request, "Tess Treasurer");
  const player = await signup(request, "Pat Player");

  const clubName = `Transfer CC ${STAMP}`;
  const club = await call(request, owner, "POST", "/clubs", {
    name: clubName,
    sport_types: ["cricket"],
    visibility: "invite_only",
  });
  await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: secretary.email, role: "club_admin" });
  for (const p of [treasurer, player]) {
    await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: p.email, role: "member" });
  }
  await call(request, owner, "PUT", `/clubs/${club.id}/members/${treasurer.user.id}/treasurer`, { is_treasurer: true });

  // Nets that finished an hour ago, £30 lane hire split between whoever came.
  // Everyone in the club is asked when it is made, so the members come first.
  const start = new Date(Date.now() - 3 * 3600_000);
  const nets = await call(request, secretary, "POST", "/events", {
    club_id: club.id,
    sport: "cricket",
    event_subtype: "nets",
    title: "E2E nets",
    start_at: start.toISOString(),
    end_at: new Date(start.getTime() + 2 * 3600_000).toISOString(),
    cost_mode: "split_total",
    cost_amount_cents: 3000,
  });
  for (const p of [player, treasurer]) {
    await call(request, p, "POST", `/events/${nets.id}/rsvp`, { status: "going" });
  }

  // 1. The secretary adds the club's bank details.
  await signIn(page, secretary);
  await page.goto(`${WEB}/clubs/${club.id}`);
  await expect(page.getByRole("link", { name: "Open payments" })).toBeVisible({ timeout: 30_000 });
  await page.getByRole("link", { name: "Open payments" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Payments" })).toBeVisible();

  const form = page.locator("form.bank-form");
  await form.getByLabel("Account name, exactly as on the account").fill("Transfer Cricket Club");
  await form.getByLabel("Sort code").fill("20-00-00");
  await form.getByLabel("Account number", { exact: true }).fill("12345678");
  await form.getByLabel("Account number again").fill("12345670");
  await form.getByRole("button", { name: "Save bank details" }).click();
  // Typed twice to catch a wrong digit: the mismatch is said under the field.
  await expect(form.getByText("The two account numbers don't match.")).toBeVisible();

  await form.getByLabel("Account number again").fill("12345678");
  await form.getByRole("button", { name: "Save bank details" }).click();
  // No password: the API asks for it (428) and the page asks the person —
  // it does not sign them out.
  await expect(form.getByText("Type your password to change the club's bank details")).toBeVisible();
  await expect(page).toHaveURL(new RegExp(`/clubs/${club.id}/payments`));

  await form.getByLabel("Your password").fill(PASSWORD);
  await form.getByRole("button", { name: "Save bank details" }).click();
  await expect(page.getByText("Bank details added. Players can pay into them now.")).toBeVisible();
  const bank = page.locator("#bank-details");
  await expect(bank).toContainText("Players pay into");
  await expect(bank).toContainText("Transfer Cricket Club");
  await expect(bank).toContainText("•••• 5678");
  // The full number is never shown back on this page.
  await expect(bank).not.toContainText("12345678");
  await page.screenshot({ path: `${SHOTS}/pay-1-bank-details.png`, fullPage: true });

  // 2. The secretary ticks who came and sends the bill.
  await page.goto(`${WEB}/events/${nets.id}`);
  const money = page.locator("#money");
  await expect(money.getByRole("heading", { name: "Who came?" })).toBeVisible({ timeout: 30_000 });
  await expect(money.getByRole("checkbox", { name: /Pat Player/ })).toBeChecked();
  await expect(money.getByRole("checkbox", { name: /Tess Treasurer/ })).toBeChecked();
  await expect(money.locator(".money-preview")).toContainText("2 people · £30.00 in all");
  await expect(money.locator(".money-preview")).toContainText("£15.00 each");
  await page.screenshot({ path: `${SHOTS}/pay-2-who-came.png`, fullPage: true });
  await money.getByRole("button", { name: "Send the bill" }).click();
  await expect(money.getByText("Bill sent. Everyone on it has been told their share.")).toBeVisible();
  await expect(money).toContainText("£0.00 of £30.00 collected");

  // 3. The player sees what they owe, and pays it.
  await signIn(page, player);
  await page.goto(`${WEB}/`);
  await expect(page.getByRole("heading", { name: `You owe ${clubName} £15.00` })).toBeVisible({ timeout: 30_000 });
  await page.screenshot({ path: `${SHOTS}/pay-3-you-owe.png`, fullPage: true });
  await page.getByRole("link", { name: `Pay ${clubName} £15.00` }).click();

  await expect(page.getByRole("heading", { level: 1, name: `Pay ${clubName}` })).toBeVisible();
  const details = page.locator(".pay-details");
  await expect(details).toContainText("£15.00");
  await expect(details).toContainText("Transfer Cricket Club");
  await expect(details).toContainText("20-00-00");
  await expect(details).toContainText("12345678");
  const pay = await call(request, player, "GET", `/clubs/${club.id}/pay`);
  await expect(details).toContainText(pay.reference);

  await page.context().grantPermissions(["clipboard-read", "clipboard-write"], { origin: new URL(WEB).origin });
  const copyNumber = page.getByRole("button", { name: "Copy account number" });
  await copyNumber.click();
  await expect(copyNumber).toHaveText("Copied");
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe("12345678");
  await page.screenshot({ path: `${SHOTS}/pay-4-pay-screen.png`, fullPage: true });

  await page.getByRole("button", { name: "I've paid" }).click();
  await expect(page.getByText("Thanks. The club will confirm it once the money shows up in their account.")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Waiting for the club to confirm" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Undo" })).toBeVisible();

  // A player cannot open the club's Payments page, and is told why.
  await page.goto(`${WEB}/clubs/${club.id}/payments`);
  await expect(page.getByText("Only the club owner, a secretary or a treasurer can look after the club's money.")).toBeVisible();

  // 4. The treasurer checks the bank and confirms it.
  await signIn(page, treasurer);
  await page.goto(`${WEB}/notifications`);
  await expect(page.locator(".note-list").getByText("Pat says they paid £15.00")).toBeVisible({ timeout: 30_000 });
  await page.locator(".note-list").getByRole("link", { name: /Pat says they paid £15\.00/ }).click();
  await expect(page).toHaveURL(new RegExp(`/clubs/${club.id}/payments#to-check`));

  const toCheck = page.locator("#to-check");
  await expect(toCheck).toContainText("Pat Player");
  await expect(toCheck).toContainText(pay.reference);
  await page.screenshot({ path: `${SHOTS}/pay-5-to-check.png`, fullPage: true });
  await toCheck.getByRole("button", { name: "Received £15.00 from Pat Player" }).click();
  await expect(page.getByText("Pat Player's £15.00 confirmed.")).toBeVisible();
  await expect(toCheck).toContainText("Nothing to check.");

  // 5. The player is all paid up.
  await signIn(page, player);
  await page.goto(`${WEB}/clubs/${club.id}/pay`);
  await expect(page.getByText("You're all paid up.")).toBeVisible({ timeout: 30_000 });
  await page.goto(`${WEB}/events/${nets.id}`);
  await expect(page.locator("#money")).toContainText("Paid");
  await page.screenshot({ path: `${SHOTS}/pay-6-paid.png`, fullPage: true });
});
