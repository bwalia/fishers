import { test as base, expect, type APIRequestContext, type Page } from "@playwright/test";

import { API_PORT, WEB_PORT } from "../lib/ports";

/// Passes, group fees and paying for others, on the web (plan §11, steps B
/// and C):
///   - the secretary names a Junior price, adds a junior by name, puts a
///     second junior on the junior price, and makes a monthly pass from a
///     template;
///   - a player gets the pass and sees the standing order to set up;
///   - the secretary gives the session a junior price, and the bill covers
///     the pass holder ("Covered by Monthly nets ✓");
///   - a group fee for the whole club, shared to WhatsApp;
///   - a parent pays for themselves and two juniors with one button;
///   - the player cancels the pass and is reminded about the bank.
///
/// Self-contained — it makes its own club, people and session through the
/// API, so it runs against any local stack:
///
///   ./scripts/start.sh --no-ios
///   cd e2e && npx playwright test tests/passes.spec.ts
const WEB = process.env.WEB_BASE ?? `http://localhost:${WEB_PORT}`;
const API = `${process.env.API_BASE ?? `http://localhost:${API_PORT}`}/api/v1`;
const SHOTS = process.env.SHOT_DIR ?? "test-results";
const STAMP = Date.now();
const PASSWORD = "password123";

const test = base.extend({});
if (process.env.CHROME_BIN) {
  test.use({ launchOptions: { executablePath: process.env.CHROME_BIN } });
}

/// A phone: these are the pages a player opens.
const PHONE = { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true };

type Session = { access_token: string; refresh_token: string; user: { id: string; name: string } };

async function signup(request: APIRequestContext, name: string): Promise<Session & { email: string }> {
  const email = `e2e-pass-${STAMP}-${name.split(" ")[0].toLowerCase()}@t.test`;
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

/// A day as the date box takes it, some days from now.
function dayFromNow(days: number): string {
  const d = new Date(Date.now() + days * 86_400_000);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

test("passes, a junior price, a group fee, and a parent paying for two juniors with one button", async ({
  browser,
  page,
  request,
}) => {
  const owner = await signup(request, "Olive Owner");
  const secretary = await signup(request, "Sana Sharma");
  const ravi = await signup(request, "Ravi Raman");
  const pat = await signup(request, "Pat Patel");
  const neha = await signup(request, "Neha Nagra");

  const club = await call(request, owner, "POST", "/clubs", {
    name: `Pass CC ${STAMP}`,
    sport_types: ["cricket"],
    visibility: "invite_only",
  });
  await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: secretary.email, role: "club_admin" });
  for (const p of [ravi, pat, neha]) {
    await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: p.email, role: "member" });
  }
  await call(request, secretary, "POST", `/clubs/${club.id}/payout-account`, {
    holder_name: "Sana Sharma",
    sort_code: "20-00-00",
    account_number: "55779911",
    is_personal: true,
    password: PASSWORD,
  });
  // A junior Neha pays for, added through the API; the other is added below,
  // on the page.
  const arjun = await call(request, secretary, "POST", `/clubs/${club.id}/members/managed`, {
    name: "Arjun Nagra",
    payer_id: neha.user.id,
  });

  // 1. Prices and who pays: a Junior price, a junior added by name, and
  //    Arjun put on the junior price.
  await signIn(page, secretary);
  await page.goto(`${WEB}/clubs/${club.id}/payments/members`);
  await expect(page.getByRole("heading", { name: "Prices for juniors, students…" })).toBeVisible({ timeout: 30_000 });
  await page.getByRole("button", { name: "Junior", exact: true }).click();
  await page.getByRole("button", { name: "Add the group" }).click();
  await expect(page.getByText("Junior added.")).toBeVisible();

  await page.getByLabel("Their name").fill("Kiran Nagra");
  const addJunior = page.locator("section", { has: page.getByRole("heading", { name: "Add a junior by name" }) });
  await addJunior.getByLabel("Who pays for them").selectOption({ label: "Neha Nagra" });
  await expect(addJunior.getByLabel("Their price")).toHaveValue(/.+/); // the Junior price, chosen for them
  await addJunior.getByRole("button", { name: "Add them" }).click();
  await expect(page.getByText("Kiran Nagra added. Neha Nagra pays for them.")).toBeVisible();

  await page.getByRole("button", { name: "Change Arjun Nagra's price or who pays" }).click();
  await page.getByRole("form", { name: "Change Arjun Nagra's price or who pays" }).getByLabel("Their price").selectOption({ label: "Junior" });
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByText("Saved for Arjun Nagra.")).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/pass-1-prices.png`, fullPage: true });

  // 2. A monthly pass, from the template.
  await page.goto(`${WEB}/clubs/${club.id}/payments`);
  await page.getByRole("link", { name: /^Passes/ }).click();
  await expect(page.getByRole("heading", { name: "Make a pass" })).toBeVisible({ timeout: 30_000 });
  await page.getByRole("button", { name: /^Monthly nets/ }).click();
  await expect(page.getByLabel("Name", { exact: true })).toHaveValue("Monthly nets");
  await expect(page.getByLabel("Price each month")).toHaveValue("20.00");
  await page.getByRole("button", { name: "Make the pass" }).click();
  await expect(page.getByText(/^Monthly nets made\./)).toBeVisible();
  await expect(page.getByText("£20.00 a month", { exact: true })).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/pass-2-made.png`, fullPage: true });

  // 3. Ravi gets it from the club's pay page, and sees the standing order.
  const phone = await browser.newContext(PHONE);
  const player = await phone.newPage();
  await signIn(player, ravi);
  await player.goto(`${WEB}/clubs/${club.id}/pay`);
  const passes = player.locator("#passes");
  await expect(passes.getByRole("heading", { name: "Passes" })).toBeVisible({ timeout: 30_000 });
  await expect(passes).toContainText("£20.00 a month");
  await expect(passes).toContainText("Covers nets");
  await passes.getByRole("button", { name: "Get Monthly nets" }).click();
  await expect(passes.getByText("Get Monthly nets?")).toBeVisible();
  await passes.getByRole("button", { name: "Yes, get it" }).click();
  await expect(passes.getByText("You're on Monthly nets. Pay the first month, then set up the standing order below.")).toBeVisible();
  const order = passes.locator(".standing-order");
  await expect(order.getByRole("heading", { name: "Set up your standing order" })).toBeVisible();
  await expect(order).toContainText("Sana Sharma");
  await expect(order).toContainText("55779911");
  await expect(order).toContainText("£20.00");
  await expect(order).toContainText("Every month");
  await expect(order).toContainText("RAMAN");
  await expect(order.getByRole("button", { name: "Copy reference" })).toBeVisible();
  await expect(order.getByText("Somebody else does your banking?")).toBeVisible();
  // The first month is in "You owe", like any session.
  await expect(player.locator("#pay-owe")).toContainText("You owe £20.00 for Monthly nets — ");
  await player.screenshot({ path: `${SHOTS}/pass-3-standing-order.png`, fullPage: true });

  // 4. Tomorrow's nets, £6 each, £3 for juniors — set on the session's own
  //    cost form. Billed: Ravi's pass covers him.
  const start = new Date(Date.now() + 26 * 3600_000);
  const nets = await call(request, secretary, "POST", "/events", {
    club_id: club.id,
    sport: "cricket",
    event_subtype: "nets",
    title: "Pass nets",
    start_at: start.toISOString(),
    end_at: new Date(start.getTime() + 2 * 3600_000).toISOString(),
    cost_mode: "per_player",
    cost_amount_cents: 600,
  });
  await page.goto(`${WEB}/events/${nets.id}`);
  const money = page.locator("#money");
  await money.getByRole("button", { name: "Change the cost" }).click({ timeout: 30_000 });
  await money.getByText("Different price for juniors?").click();
  await money.getByLabel("Junior price").fill("3.00");
  await money.getByRole("button", { name: "Save the cost" }).click();
  await expect(money.getByText("Cost saved.")).toBeVisible();
  await expect(money).toContainText("Junior £3.00");

  const kiran = (await call(request, secretary, "GET", `/clubs/${club.id}/members`)).find(
    (m: { name: string }) => m.name === "Kiran Nagra",
  );
  const billed = await call(request, secretary, "POST", `/events/${nets.id}/bill`, {
    attendees: [ravi.user.id, pat.user.id, kiran.user_id, arjun.user_id],
  });
  const line = (id: string) => billed.shares.find((s: { user_id: string }) => s.user_id === id);
  expect(line(ravi.user.id).state).toBe("covered");
  expect(line(pat.user.id).amount_cents).toBe(600);
  expect(line(kiran.user_id).amount_cents).toBe(300);
  expect(line(arjun.user_id).amount_cents).toBe(300);

  await page.reload();
  await expect(money).toContainText("Covered by Monthly nets ✓", { timeout: 30_000 });
  await page.screenshot({ path: `${SHOTS}/pass-4-bill.png`, fullPage: true });

  await player.goto(`${WEB}/profile/payments`);
  const covered = player.locator("li", { hasText: "Pass nets" });
  await expect(covered).toContainText("Covered by Monthly nets ✓", { timeout: 30_000 });
  await expect(covered).not.toContainText("£6.00");
  await player.screenshot({ path: `${SHOTS}/pass-5-covered.png`, fullPage: true });

  // 5. A group fee for the whole club: £5 each, by a date, shared to WhatsApp.
  await page.goto(`${WEB}/clubs/${club.id}/payments/group-fees`);
  await expect(page.getByRole("heading", { name: "Group fees", level: 1 })).toBeVisible({ timeout: 30_000 });
  await page.getByLabel("What's it for?").fill("Match balls");
  await page.getByRole("button", { name: "Same for everyone" }).click();
  await page.getByLabel("Each person pays").fill("5.00");
  await page.getByLabel("Pay by (optional)").fill(dayFromNow(14));
  await page.getByRole("button", { name: "Send the group fee" }).click();
  await expect(page.getByText("Match balls sent to 7 people.")).toBeVisible();
  const fee = page.locator(".fee-detail");
  await expect(fee).toContainText("Kiran Nagra");
  await expect(fee).toContainText("£5.00");
  const [whatsapp] = await Promise.all([
    page.waitForEvent("popup"),
    fee.getByRole("button", { name: "Share the bill" }).click(),
  ]);
  await whatsapp.close();
  await expect(fee.getByRole("link", { name: "Share the bill" })).toHaveAttribute("href", /^https:\/\/wa\.me\/\?text=.*Match%20balls/);
  await expect(fee.getByRole("link", { name: "Remind who hasn't paid" })).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/pass-6-group-fee.png`, fullPage: true });

  // 6. Neha pays for herself and both juniors with one button.
  const parentPhone = await browser.newContext(PHONE);
  const parent = await parentPhone.newPage();
  await signIn(parent, neha);
  await parent.goto(`${WEB}/profile/payments`);
  // Neha £5; Kiran and Arjun £3 for nets and £5 for the balls each.
  await expect(parent.getByText("You owe £21.00 for everyone")).toBeVisible({ timeout: 30_000 });
  await expect(parent.getByRole("heading", { name: "Kiran Nagra" })).toBeVisible();
  await expect(parent.getByText("Kiran owes £8.00")).toBeVisible();
  await expect(parent.getByText("Arjun owes £8.00")).toBeVisible();
  await parent.screenshot({ path: `${SHOTS}/pass-7-parent.png`, fullPage: true });
  await parent.getByRole("link", { name: "Pay for everyone: £21.00" }).click();

  await expect(parent.getByText("You owe £21.00 for everyone")).toBeVisible({ timeout: 30_000 });
  await expect(parent.locator(".pay-rows")).toContainText("NAGRA");
  await expect(parent.getByText("One payment for you, Arjun Nagra and Kiran Nagra.")).toBeVisible();
  await parent.getByRole("button", { name: "I've paid for everyone" }).click();
  await expect(parent.getByRole("heading", { name: "Thanks — waiting for Sana to check" })).toBeVisible();
  await expect(parent.getByText("You said you paid £21.00, for you, Arjun Nagra and Kiran Nagra.")).toBeVisible();
  await parent.screenshot({ path: `${SHOTS}/pass-8-paid-for-everyone.png`, fullPage: true });

  // One reference, three lines for the club to check.
  const overview = await call(request, secretary, "GET", `/clubs/${club.id}/money`);
  const claims = overview.to_check.filter((p: { created_by: string }) => p.created_by === neha.user.id);
  expect(claims).toHaveLength(3);
  expect(new Set(claims.map((p: { reference: string }) => p.reference))).toEqual(new Set(["NAGRA"]));
  expect(claims.reduce((sum: number, p: { amount_cents: number }) => sum + p.amount_cents, 0)).toBe(2100);
  await parentPhone.close();

  // 7. Ravi cancels the pass, and is told to cancel the standing order too.
  await player.goto(`${WEB}/clubs/${club.id}/pay`);
  await passes.getByRole("button", { name: "Cancel my pass" }).click({ timeout: 30_000 });
  await expect(passes.getByText("Cancel Monthly nets?")).toBeVisible();
  await passes.getByRole("button", { name: "Yes, cancel it" }).click();
  await expect(passes.getByText(/^Cancelled\. It covers you until .+\. Now cancel the standing order in your banking app too\.$/)).toBeVisible();
  await expect(passes.getByText("Remember to cancel the standing order in your banking app too, or it will keep paying.")).toBeVisible();
  await player.screenshot({ path: `${SHOTS}/pass-9-cancelled.png`, fullPage: true });
  await phone.close();
});
