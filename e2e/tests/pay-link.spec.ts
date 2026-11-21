import { test as base, expect, type APIRequestContext, type Page } from "@playwright/test";

import { API_PORT, WEB_PORT } from "../lib/ports";

/// Paying from the WhatsApp pay link, on the web (plan §5.1, step A): a
/// secretary sends the bill for a nets session and gets its pay link; a
/// signed-out phone opens it, picks a name, sees the bank details and taps
/// "I've paid", adds a screenshot, takes it back, and pays again; a second
/// player says they paid cash; the treasurer looks at the screenshot and
/// ticks both off with "All arrived". A link with one character changed gets
/// the friendly wrong-link page.
///
/// Self-contained — it makes its own club, people and session through the
/// API, so it runs against any local stack:
///
///   ./scripts/start.sh --no-ios
///   cd e2e && npx playwright test tests/pay-link.spec.ts
///
/// The API throttles "I've paid" from one address to 40 an hour on a link
/// (120 across links); this run makes three.
const WEB = process.env.WEB_BASE ?? `http://localhost:${WEB_PORT}`;
const API = `${process.env.API_BASE ?? `http://localhost:${API_PORT}`}/api/v1`;
const SHOTS = process.env.SHOT_DIR ?? "test-results";
const STAMP = Date.now();
const PASSWORD = "password123";

const test = base.extend({});
if (process.env.CHROME_BIN) {
  test.use({ launchOptions: { executablePath: process.env.CHROME_BIN } });
}

/// A phone, for the pages a player opens from WhatsApp.
const PHONE = { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true };

/// The smallest PNG there is: a picture the browser can draw and re-encode.
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

type Session = { access_token: string; refresh_token: string; user: { id: string; name: string } };

async function signup(request: APIRequestContext, name: string): Promise<Session & { email: string }> {
  const email = `e2e-link-${STAMP}-${name.split(" ")[0].toLowerCase()}@t.test`;
  const res = await request.post(`${API}/auth/signup`, { data: { name, email, password: PASSWORD } });
  expect(res.ok(), `signed up ${name}`).toBeTruthy();
  return { ...(await res.json()), email };
}

async function call(request: APIRequestContext, s: Session | null, method: string, path: string, data?: unknown) {
  const res = await request.fetch(`${API}${path}`, {
    method,
    data,
    headers: s ? { Authorization: `Bearer ${s.access_token}` } : {},
  });
  expect(res.ok(), `${method} ${path} → ${res.status()} ${await res.text()}`).toBeTruthy();
  return res.status() === 204 ? null : res.json();
}

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

test("a pay link from WhatsApp: pay without signing in, add a screenshot, undo, and the treasurer's All arrived", async ({
  browser,
  page,
  request,
}) => {
  const owner = await signup(request, "Olive Owner");
  const secretary = await signup(request, "Sana Sharma");
  const treasurer = await signup(request, "Theo Treasurer");
  const pat = await signup(request, "Pat Patel");
  const quinn = await signup(request, "Quinn Quayle");

  const clubName = `Link CC ${STAMP}`;
  const club = await call(request, owner, "POST", "/clubs", {
    name: clubName,
    sport_types: ["cricket"],
    visibility: "invite_only",
  });
  await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: secretary.email, role: "club_admin" });
  for (const p of [treasurer, pat, quinn]) {
    await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: p.email, role: "member" });
  }
  await call(request, owner, "PUT", `/clubs/${club.id}/members/${treasurer.user.id}/treasurer`, { is_treasurer: true });

  // The secretary's own account, which the club collects into.
  await call(request, secretary, "POST", `/clubs/${club.id}/payout-account`, {
    holder_name: "Sana Sharma",
    sort_code: "20-00-00",
    account_number: "55779911",
    is_personal: true,
    password: PASSWORD,
  });

  // Nets that finished an hour ago, £30 between the two who came.
  const start = new Date(Date.now() - 3 * 3600_000);
  const nets = await call(request, secretary, "POST", "/events", {
    club_id: club.id,
    sport: "cricket",
    event_subtype: "nets",
    title: "Link nets",
    start_at: start.toISOString(),
    end_at: new Date(start.getTime() + 2 * 3600_000).toISOString(),
    cost_mode: "split_total",
    cost_amount_cents: 3000,
  });
  await call(request, secretary, "POST", `/events/${nets.id}/bill`, { attendees: [pat.user.id, quinn.user.id] });

  // 1. The secretary's event page offers the bill for WhatsApp.
  await signIn(page, secretary);
  await page.goto(`${WEB}/events/${nets.id}`);
  const share = page.locator(".share-bill");
  await expect(share.getByRole("heading", { name: "Share to WhatsApp" })).toBeVisible({ timeout: 30_000 });
  // Opening the session only looks: no link exists until somebody shares.
  expect(await call(request, secretary, "GET", `/events/${nets.id}/bill/link`)).toBeNull();
  // The first Share makes the link and opens WhatsApp in a new tab.
  const [whatsapp] = await Promise.all([
    page.waitForEvent("popup"),
    share.getByRole("button", { name: "Share the bill" }).click(),
  ]);
  await whatsapp.close();
  await expect(share).toContainText("Still to pay:");
  await expect(share).toContainText("Pat Patel");
  await expect(share).toContainText("Quinn Quayle");
  const billLink = share.getByRole("link", { name: "Share the bill" });
  await expect(billLink).toHaveAttribute("href", /^https:\/\/wa\.me\/\?text=.*Link%20nets/);
  await expect(share.getByRole("link", { name: "Remind who hasn't paid" })).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/link-1-share.png`, fullPage: true });

  // The same link the API hands the apps.
  const made = await call(request, secretary, "POST", `/events/${nets.id}/bill/link`);
  const token = new URL(made.url).pathname.split("/pay/")[1];
  expect(token).toBeTruthy();

  // 2. A phone that has never signed in opens it.
  const phone = await browser.newContext(PHONE);
  const guest = await phone.newPage();
  await guest.goto(`${WEB}/pay/${token}`);
  await expect(guest.getByRole("heading", { level: 1, name: clubName })).toBeVisible({ timeout: 30_000 });
  await expect(guest.locator(".topbar")).toBeHidden();
  await expect(guest.getByRole("heading", { name: "Tap your name" })).toBeVisible();
  await expect(guest.getByRole("button", { name: "Quinn Quayle" })).toBeVisible();
  await guest.screenshot({ path: `${SHOTS}/link-2-names.png`, fullPage: true });
  await guest.getByRole("button", { name: "Pat Patel" }).click();

  await expect(guest.getByRole("heading", { name: "You owe £15.00 for Link nets" })).toBeVisible();
  await expect(guest.getByRole("heading", { name: "Pay Sana Sharma, the club secretary" })).toBeVisible();
  await expect(guest.getByText("This is Sana's own bank account. The club uses it to collect money.")).toBeVisible();
  const rows = guest.locator(".pay-rows");
  await expect(rows).toContainText("Sana Sharma");
  await expect(rows).toContainText("20-00-00");
  await expect(rows).toContainText("55779911");
  await expect(rows).toContainText("What to write in the reference box");
  await expect(rows).toContainText("PATEL");
  await expect(guest.getByRole("button", { name: "Copy account number" })).toBeVisible();
  // The account number travels in no URL.
  expect(guest.url()).not.toContain("55779911");
  await guest.getByText("First time? Here's how").click();
  await expect(guest.getByText("Open your banking app.")).toBeVisible();
  await guest.screenshot({ path: `${SHOTS}/link-3-details.png`, fullPage: true });

  // 3. "I've paid", then a screenshot of it.
  await guest.getByRole("button", { name: "I've paid" }).click();
  await expect(guest.getByRole("heading", { name: "Thanks — waiting for Sana to check" })).toBeVisible();
  await expect(guest.getByText("You said you paid £15.00 by bank transfer.")).toBeVisible();
  await guest.locator('input[type="file"]').setInputFiles({ name: "payment.png", mimeType: "image/png", buffer: PNG });
  await expect(guest.getByText("Screenshot added. Thank you.")).toBeVisible();
  await guest.screenshot({ path: `${SHOTS}/link-4-waiting.png`, fullPage: true });

  // 4. Tapped by mistake: undo, and the amount is owed again.
  await guest.getByRole("button", { name: "Undo" }).click();
  await expect(guest.getByText("Undone. You still owe it.")).toBeVisible();
  await expect(guest.getByRole("heading", { name: "You owe £15.00 for Link nets" })).toBeVisible();

  // Paid for real this time; the guide has learnt they've done it before.
  await expect(guest.getByText("Pay Sana as usual, with the same details as last time.")).toBeVisible();
  await guest.getByRole("button", { name: "I've paid" }).click();
  await expect(guest.getByRole("heading", { name: "Thanks — waiting for Sana to check" })).toBeVisible();
  await guest.locator('input[type="file"]').setInputFiles({ name: "payment.png", mimeType: "image/png", buffer: PNG });
  await expect(guest.getByText("Screenshot added. Thank you.")).toBeVisible();

  // 5. Quinn, on the same phone, paid cash.
  await guest.getByRole("button", { name: "Not Pat? Pick your name" }).click();
  await guest.getByRole("button", { name: "Quinn Quayle" }).click();
  await expect(guest.getByRole("heading", { name: "You owe £15.00 for Link nets" })).toBeVisible();
  await guest.getByRole("button", { name: "I paid cash" }).click();
  await expect(guest.getByText("You said you paid £15.00 in cash.")).toBeVisible();

  // 6. The treasurer sees both, looks at the screenshot, and ticks both off.
  await signIn(page, treasurer);
  await page.goto(`${WEB}/clubs/${club.id}/payments#to-check`);
  const toCheck = page.locator("#to-check");
  await expect(toCheck).toContainText("Pat Patel", { timeout: 30_000 });
  await expect(toCheck).toContainText("Quinn Quayle");
  await expect(toCheck.getByText("Said on the WhatsApp pay link").first()).toBeVisible();
  await toCheck.getByRole("button", { name: "See Pat Patel's screenshot" }).click();
  const shot = toCheck.getByRole("img", { name: "Screenshot of the payment from Pat Patel" });
  await expect(shot).toBeVisible();
  expect(await shot.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  await page.screenshot({ path: `${SHOTS}/link-5-to-check.png`, fullPage: true });

  await toCheck.getByRole("button", { name: "All arrived" }).click();
  await expect(toCheck.getByText("Mark all 2 as arrived?")).toBeVisible();
  await toCheck.getByRole("button", { name: "Yes, they all arrived" }).click();
  await expect(page.getByText("2 payments marked as arrived.")).toBeVisible();
  await expect(toCheck).toContainText("Nothing to check.");

  // 7. Back on the phone, Pat's line is paid.
  await guest.reload();
  await guest.getByRole("button", { name: "Pat Patel" }).click();
  await expect(guest.getByRole("heading", { name: "That's paid. Thank you!" })).toBeVisible();

  // 8. A link with a character changed is not a link at all.
  const tampered = token.slice(0, 5) + (token[5] === "A" ? "B" : "A") + token.slice(6);
  await guest.goto(`${WEB}/pay/${tampered}`);
  await expect(guest.getByRole("heading", { name: "This link isn't right" })).toBeVisible({ timeout: 30_000 });
  await expect(guest.getByText("Ask your secretary to share it again.")).toBeVisible();
  await guest.screenshot({ path: `${SHOTS}/link-6-wrong-link.png`, fullPage: true });

  // 9. The secretary switches the link off; the old link says so.
  await signIn(page, secretary);
  await page.goto(`${WEB}/events/${nets.id}`);
  await expect(share.getByRole("button", { name: "Switch the link off" })).toBeVisible({ timeout: 30_000 });
  await share.getByRole("button", { name: "Switch the link off" }).click();
  await share.getByRole("button", { name: "Yes, switch it off" }).click();
  await expect(share.getByText("Link switched off.")).toBeVisible();
  await guest.goto(`${WEB}/pay/${token}`);
  await expect(guest.getByRole("heading", { name: "This pay link has closed" })).toBeVisible({ timeout: 30_000 });

  await phone.close();
});
