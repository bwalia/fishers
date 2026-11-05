import { test as base, expect, type APIRequestContext, type Page } from "@playwright/test";

import { API_PORT, WEB_PORT } from "../lib/ports";

/// Club accounts on the web: the treasurer sees the books and the AGM report
/// with a real club's figures; a member sees neither the link nor the page.
///
/// Self-contained — it makes its own club, people and year through the API,
/// so it runs against any local stack:
///
///   ./scripts/start.sh --no-ios
///   cd e2e && npx playwright test tests/club-accounts.spec.ts
const WEB = process.env.WEB_BASE ?? `http://localhost:${WEB_PORT}`;
const API = `${process.env.API_BASE ?? `http://localhost:${API_PORT}`}/api/v1`;
const SHOTS = process.env.SHOT_DIR ?? "test-results";
const STAMP = Date.now();

const test = base.extend({});
if (process.env.CHROME_BIN) {
  test.use({ launchOptions: { executablePath: process.env.CHROME_BIN } });
}

type Session = { access_token: string; refresh_token: string; user: unknown };

async function signup(request: APIRequestContext, name: string): Promise<Session & { email: string }> {
  const email = `e2e-acc-${STAMP}-${name.split(" ")[0].toLowerCase()}@t.test`;
  const res = await request.post(`${API}/auth/signup`, { data: { name, email, password: "password123" } });
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
  return res.json();
}

async function signIn(page: Page, s: Session) {
  await page.goto(`${WEB}/login`);
  await page.evaluate(
    ([a, r, u]) => {
      localStorage.setItem("fishers_access_token", a as string);
      localStorage.setItem("fishers_refresh_token", r as string);
      localStorage.setItem("fishers_user", JSON.stringify(u));
    },
    [s.access_token, s.refresh_token, s.user],
  );
}

test("a treasurer keeps the books and prints the AGM report; a member can't get in", async ({ page, request }) => {
  const owner = await signup(request, "Owner Example");
  const treasurer = await signup(request, "Treasurer Example");
  const member = await signup(request, "Member Example");

  const club = await call(request, owner, "POST", "/clubs", {
    name: `Ledger CC ${STAMP}`,
    sport_types: ["cricket"],
    visibility: "invite_only",
  });
  for (const p of [treasurer, member]) {
    await call(request, owner, "POST", `/clubs/${club.id}/members`, { identifier: p.email, role: "member" });
  }
  const roster: { user_id: string; name: string }[] = await call(request, owner, "GET", `/clubs/${club.id}/members`);
  const tid = roster.find((m) => m.name === "Treasurer Example")!.user_id;
  await call(request, owner, "PUT", `/clubs/${club.id}/members/${tid}/treasurer`, { is_treasurer: true });

  // The year, with the real club's figures.
  const A = `/clubs/${club.id}/accounts`;
  const overview = await call(request, treasurer, "GET", A);
  const cat = (kind: string, name: string) =>
    overview.categories.find((c: { kind: string; name: string }) => c.kind === kind && c.name === name).id;
  const period = await call(request, treasurer, "POST", `${A}/periods`, {
    label: "2025/26",
    starts_on: "2025-10-01",
    ends_on: "2026-09-30",
    opening_balance_cents: 384659,
  });
  const bank = await call(request, treasurer, "POST", `${A}/money-accounts`, {
    name: "Bank current a/c",
    kind: "bank",
    opening_cents: 299688,
  });
  const balls = await call(request, treasurer, "POST", `${A}/stock`, { name: "Unused balls" });
  await call(request, treasurer, "PUT", `${A}/stock/${balls.id}/count`, {
    period_id: period.id,
    opening_cents: 10494,
    closing_cents: 7085,
  });
  const lines: [string, string, number, boolean?][] = [
    ["income", "Indoor net fees", 64876],
    ["income", "Outdoor match fees", 254961],
    ["income", "Cost share with other teams", 62000],
    ["expenditure", "Indoor nets", 112000],
    ["expenditure", "Pitch hire", 169250],
    ["expenditure", "Cost share with other teams", 24500],
    ["expenditure", "Losses on previous year recovered debt", 1883],
    ["expenditure", "Equipment purchase", 34337],
    ["expenditure", "Public liability insurance", 10080],
    ["expenditure", "Engraving, trophies etc.", 6000],
    ["expenditure", "Food (home games)", 31893],
    ["expenditure", "Website", 21421],
    ["expenditure", "Miscellaneous", 49000, true],
  ];
  for (const [kind, name, pence, extraordinary] of lines) {
    await call(request, treasurer, "POST", `${A}/periods/${period.id}/transactions`, {
      occurred_on: "2026-06-01",
      kind,
      category_id: cat(kind, name),
      money_account_id: bank.id,
      amount_cents: pence,
      description: name,
      extraordinary: !!extraordinary,
    });
  }
  for (const [kind, pence, description, accrue, raised_on] of [
    ["member_fees", 33900, "Unpaid 2026 match/net fees", true, "2026-09-30"],
    ["member_fees", 6100, "Unpaid 2025 match fees", false, "2025-10-01"],
    ["cost_share", 13000, "Cost share from another team", true, "2026-09-30"],
  ] as const) {
    await call(request, treasurer, "POST", `${A}/debts`, {
      direction: "debtor",
      kind,
      description,
      amount_cents: pence,
      raised_on,
      accrue,
    });
  }
  await call(request, treasurer, "PUT", `${A}/money-accounts/${bank.id}/balance`, {
    period_id: period.id,
    reconciled_cents: 282546,
  });
  await call(request, treasurer, "PATCH", `${A}/periods/${period.id}`, {
    report_text:
      "At the end of the year the club's assets totalled £3,496.23.\n\nAnother fine summer carried the club's finances.",
    signed_by_name: "Treasurer Example",
    signed_on: "2026-11-03",
  });

  // The treasurer: the club page offers the books.
  await signIn(page, treasurer);
  await page.goto(`${WEB}/clubs/${club.id}`);
  await expect(page.getByRole("link", { name: "Open the accounts" })).toBeVisible({ timeout: 30_000 });

  await page.getByRole("link", { name: "Open the accounts" }).click();
  await expect(page.getByRole("heading", { name: "Club accounts" })).toBeVisible();
  await expect(page.locator(".acc-headline")).toContainText("3,496.23");
  await expect(page.locator(".acc-gap")).toContainText("The books are 69.92 short.");
  await page.screenshot({ path: `${SHOTS}/accounts-1-overview.png`, fullPage: true });

  await page.getByRole("tab", { name: "Transactions" }).click();
  await expect(page.locator("table.acc-tx")).toContainText("Pitch hire");
  await page.screenshot({ path: `${SHOTS}/accounts-2-transactions.png`, fullPage: true });

  await page.getByRole("tab", { name: "Owed" }).click();
  await expect(page.getByText("Unpaid 2026 match/net fees")).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/accounts-3-owed.png`, fullPage: true });

  await page.getByRole("tab", { name: "Bank and stock" }).click();
  await expect(page.getByText("Unused balls")).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/accounts-4-bank.png`, fullPage: true });

  await page.getByRole("tab", { name: "Report" }).click();
  await expect(page.getByRole("heading", { name: "Income & Expenditure account" })).toBeVisible();
  await expect(page.locator(".acc-statement").first()).toContainText("4,287.37");
  await expect(page.locator(".acc-statement").first()).toContainText("4,637.73");
  await page.screenshot({ path: `${SHOTS}/accounts-5-report.png`, fullPage: true });

  await page.getByRole("link", { name: "Printable report" }).click();
  await expect(page.getByRole("heading", { name: "Treasurer's Annual Report" })).toBeVisible();
  await expect(page.locator(".acc-lede")).toContainText("a loss of 350.36");
  await page.screenshot({ path: `${SHOTS}/accounts-6-printable.png`, fullPage: true });
  await page.emulateMedia({ media: "print" });
  await expect(page.locator(".topbar")).toBeHidden();
  await page.screenshot({ path: `${SHOTS}/accounts-7-print.png`, fullPage: true });
  await page.emulateMedia({ media: "screen" });

  // A member: no link, and the page says why rather than showing nothing.
  await signIn(page, member);
  await page.goto(`${WEB}/clubs/${club.id}`);
  await expect(page.getByRole("heading", { level: 1, name: club.name })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByRole("link", { name: "Open the accounts" })).toHaveCount(0);
  await page.goto(`${WEB}/clubs/${club.id}/accounts`);
  await expect(page.getByText("Only the club owner or a treasurer can open the accounts.")).toBeVisible();
  await page.screenshot({ path: `${SHOTS}/accounts-8-member-refused.png` });
});
