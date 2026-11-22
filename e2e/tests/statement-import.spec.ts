import { test as base, expect, type APIRequestContext, type Page } from "@playwright/test";

import { API_PORT, WEB_PORT } from "../lib/ports";

/// Importing a bank statement, on the web (plan §12, step D): the treasurer
/// picks the CSV their bank exports on the Payments page and sees
///   - "Ticked off: 2" — Josh said he'd paid and the money is there; Pat
///     hadn't said, but his reference is on a transfer;
///   - "Needs a look: 2" — Tom said £6 and sent £9; and "SHARMA" with no
///     number, when the club has two Sharmas;
///   - "Not recognised: 1", folded away (bank interest).
/// Money going out is left out. Apply 2 ticks Josh's "I've paid" and records
/// Pat's payment, so both owe nothing. The same statement again changes
/// nothing ("Already done: 2"), and a file that isn't a statement says so.
///
/// Self-contained — it makes its own club, people and session through the
/// API, so it runs against any local stack:
///
///   ./scripts/start.sh --no-ios
///   cd e2e && npx playwright test tests/statement-import.spec.ts
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
  const email = `e2e-stmt-${STAMP}-${name.split(" ")[0].toLowerCase()}@t.test`;
  const res = await request.post(`${API}/auth/signup`, { data: { name, email, password: PASSWORD } });
  expect(res.ok(), `signed up ${name}`).toBeTruthy();
  return { ...(await res.json()), email };
}

async function call(
  request: APIRequestContext,
  s: Session,
  method: string,
  path: string,
  data?: unknown,
  headers: Record<string, string> = {},
) {
  const res = await request.fetch(`${API}${path}`, {
    method,
    data,
    headers: { Authorization: `Bearer ${s.access_token}`, ...headers },
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

/// Today as a UK bank writes it in a statement: 22/11/2026.
function bankDay(d = new Date()): string {
  return `${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}/${d.getFullYear()}`;
}

test("a bank statement ticks off who paid, says why the rest need a look, and changes nothing the second time", async ({
  page,
  request,
}) => {
  const owner = await signup(request, "Olive Owner");
  const treasurer = await signup(request, "Theo Treasurer");
  const ravi = await signup(request, "Ravi Sharma");
  const rohit = await signup(request, "Rohit Sharma");
  const josh = await signup(request, "Josh Turner");
  const tom = await signup(request, "Tom Bennett");
  const pat = await signup(request, "Pat Patel");

  const club = await call(request, owner, "POST", "/clubs", {
    name: `Statement CC ${STAMP}`,
    sport_types: ["cricket"],
    visibility: "invite_only",
  });
  for (const p of [treasurer, ravi, rohit, josh, tom, pat]) {
    await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: p.email, role: "member" });
  }
  await call(request, owner, "PUT", `/clubs/${club.id}/members/${treasurer.user.id}/treasurer`, { is_treasurer: true });
  await call(request, owner, "POST", `/clubs/${club.id}/payout-account`, {
    holder_name: "Olive Owner",
    sort_code: "20-00-00",
    account_number: "55779911",
    is_personal: true,
    password: PASSWORD,
  });

  // Nets that finished an hour ago, £6 each for the five who came.
  const start = new Date(Date.now() - 3 * 3600_000);
  const nets = await call(request, owner, "POST", "/events", {
    club_id: club.id,
    sport: "cricket",
    event_subtype: "nets",
    title: "Statement nets",
    start_at: start.toISOString(),
    end_at: new Date(start.getTime() + 2 * 3600_000).toISOString(),
    cost_mode: "per_player",
    cost_amount_cents: 600,
  });
  const people = [ravi, rohit, josh, tom, pat];
  await call(request, owner, "POST", `/events/${nets.id}/bill`, { attendees: people.map((p) => p.user.id) });

  // Each opens the pay screen, which gives them their reference: Ravi is
  // SHARMA, Rohit SHARMA 2.
  const ref: Record<string, string> = {};
  for (const p of people) ref[p.user.id] = (await call(request, p, "GET", `/clubs/${club.id}/pay`)).reference;
  expect(ref[ravi.user.id]).toBe("SHARMA");
  expect(ref[rohit.user.id]).toBe("SHARMA 2");

  // Josh and Tom say they've paid by bank transfer, £6 each.
  for (const p of [josh, tom]) {
    await call(request, p, "POST", `/clubs/${club.id}/payments`, { method: "transfer" }, {
      "Idempotency-Key": `stmt-${STAMP}-${p.user.id}`,
    });
  }

  const day = bankDay();
  const csv = [
    "Date,Description,Amount",
    `${day},J TURNER ${ref[josh.user.id]},6.00`,
    `${day},T BENNETT ${ref[tom.user.id]},9.00`,
    `${day},P PATEL ${ref[pat.user.id]},6.00`,
    `${day},R SHARMA SHARMA,7.00`,
    `${day},INTEREST,0.12`,
    `${day},CARD PAYMENT NETS LTD,-50.00`,
  ].join("\n");

  // 1. The treasurer picks the file on the Payments page.
  await signIn(page, treasurer);
  await page.goto(`${WEB}/clubs/${club.id}/payments`);
  const statement = page.locator("#statement");
  await expect(statement.getByRole("heading", { name: "Import a bank statement" })).toBeVisible({ timeout: 30_000 });
  await statement.locator('input[type="file"]').setInputFiles({
    name: "statement.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(csv),
  });

  // 2. What it found. Money going out isn't counted.
  await expect(statement.getByText("5 payments came in on that statement.")).toBeVisible();
  await expect(statement.getByRole("heading", { name: "Ticked off: 2" })).toBeVisible();
  const joshLine = statement.locator("label", { hasText: "Josh Turner" });
  await expect(joshLine).toContainText("Said they'd paid: this ticks it off");
  await expect(joshLine).toContainText("£6.00");
  await expect(joshLine.getByRole("checkbox")).toBeChecked();
  const patLine = statement.locator("label", { hasText: "Pat Patel" });
  await expect(patLine).toContainText("Hadn't said they'd paid: recorded as paid");
  await expect(patLine.getByRole("checkbox")).toBeChecked();

  await expect(statement.getByRole("heading", { name: "Needs a look: 2" })).toBeVisible();
  await expect(statement.locator("li", { hasText: "Tom Bennett" })).toContainText("Said £6.00, sent £9.00");
  await expect(statement.getByText("Two members called SHARMA — the number was left off")).toBeVisible();

  // Not recognised, folded away until opened.
  await expect(statement.getByText("INTEREST")).toBeHidden();
  await statement.getByText("Not recognised: 1").click();
  await expect(statement.getByText("INTEREST")).toBeVisible();
  await expect(statement).not.toContainText("NETS LTD");
  await page.screenshot({ path: `${SHOTS}/statement-1-preview.png`, fullPage: true });

  // Unticking one takes it out of what's applied; ticked again, both go.
  await joshLine.getByRole("checkbox").uncheck();
  await expect(statement.getByRole("button", { name: "Apply 1" })).toBeVisible();
  await joshLine.getByRole("checkbox").check();

  // 3. Apply 2.
  await statement.getByRole("button", { name: "Apply 2" }).click();
  await expect(page.getByText("Ticked off: 1. Recorded as paid: 1.")).toBeVisible();
  await expect(statement.getByRole("button", { name: "Choose the CSV file" })).toBeVisible();
  // Josh's "I've paid" is ticked; Tom's still waits for a person.
  const toCheck = page.locator("#to-check");
  await expect(toCheck).toContainText("Tom Bennett");
  await expect(toCheck).not.toContainText("Josh Turner");
  await page.screenshot({ path: `${SHOTS}/statement-2-applied.png`, fullPage: true });

  // Josh and Pat owe nothing now.
  for (const p of [josh, pat]) {
    const now = await call(request, p, "GET", `/clubs/${club.id}/pay`);
    expect(now.owed_cents, `${p.user.name} owes`).toBe(0);
    expect(now.waiting_cents, `${p.user.name} waiting`).toBe(0);
  }

  // 4. The same statement again: already done, nothing to apply.
  await statement.locator('input[type="file"]').setInputFiles({
    name: "statement.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(csv),
  });
  await expect(statement.getByText("Already done: 2")).toBeVisible();
  await expect(statement.getByRole("heading", { name: "Ticked off: 0" })).toBeVisible();
  await expect(statement.getByText("Nothing to tick off.")).toBeVisible();
  await expect(statement.getByRole("button", { name: /^Apply/ })).toHaveCount(0);
  await page.screenshot({ path: `${SHOTS}/statement-3-again.png`, fullPage: true });

  // 5. A file that isn't a bank statement says so, in plain words.
  await statement.getByRole("button", { name: "Choose another file" }).click();
  await statement.locator('input[type="file"]').setInputFiles({
    name: "notes.csv",
    mimeType: "text/csv",
    buffer: Buffer.from("shopping,list\nmilk,eggs\n"),
  });
  await expect(
    statement.getByText("That doesn't look like a bank statement. Download it from your bank as a CSV file, then try again."),
  ).toBeVisible();
  // Nothing of the statement went into the page's address.
  expect(page.url()).not.toContain("TURNER");
});
