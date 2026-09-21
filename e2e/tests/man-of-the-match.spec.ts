import { test as base, expect } from "@playwright/test";

/// The man-of-the-match card on the dashboard, clicked by somebody who did
/// not play — the web half of what `ios/FishersUITests/ManOfTheMatchTour`
/// does on a phone.
///
/// Not part of the full-match journey yet, because that journey's two clubs
/// are made fresh and have no chat thread for the card to be posted into: a
/// poll opens for them, and there is nowhere to draw it. Until the journey
/// makes a thread, this runs against a seeded world and skips politely
/// without one:
///
///   ./scripts/start.sh --no-ios          # then finish a match
///   MOTM_VOTER_EMAIL=someone@club.test \
///     npx playwright test tests/zz-web-motm.spec.ts
///
/// A machine whose Playwright never unpacked its own browser can point at
/// another with CHROME_BIN.
const WEB = process.env.WEB_BASE ?? "http://localhost:7311";
const API = process.env.API_BASE ?? "http://localhost:8080";
const EMAIL = process.env.MOTM_VOTER_EMAIL;
const PASSWORD = process.env.MOTM_VOTER_PASSWORD ?? "password123";
const SHOTS = process.env.SHOT_DIR ?? "test-results";

const test = base.extend({});
if (process.env.CHROME_BIN) {
  test.use({ launchOptions: { executablePath: process.env.CHROME_BIN } });
}

test("a member who did not play votes, changes it, and is refused the close", async ({ page }) => {
  test.skip(!EMAIL, "set MOTM_VOTER_EMAIL to a club member who did not play");

  const auth = await page.request.post(`${API}/api/v1/auth/login`, {
    data: { identifier: EMAIL, password: PASSWORD },
  });
  expect(auth.ok(), "the API accepted the sign-in").toBeTruthy();
  const tokens = await auth.json();

  // Which fixture is being voted on changes with every seed, so it is asked
  // for rather than written down.
  const mine = await page.request.get(`${API}/api/v1/conversations`, {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });
  const threads = await mine.json();
  let thread: string | undefined;
  for (const t of threads) {
    const messages = await (
      await page.request.get(`${API}/api/v1/conversations/${t.id}/messages?limit=50`, {
        headers: { Authorization: `Bearer ${tokens.access_token}` },
      })
    ).json();
    if (messages.some((m: { metadata?: Record<string, unknown> }) => m.metadata?.kind === "motm_poll")) {
      thread = t.id;
      break;
    }
  }
  test.skip(!thread, "no open man-of-the-match vote in any of this account's threads");

  await page.goto(`${WEB}/login`);
  await page.evaluate(
    ([access, refresh, user]) => {
      localStorage.setItem("fishers_access_token", access as string);
      localStorage.setItem("fishers_refresh_token", refresh as string);
      localStorage.setItem("fishers_user", JSON.stringify(user));
    },
    [tokens.access_token, tokens.refresh_token, tokens.user],
  );
  await page.goto(`${WEB}/chat/${thread}`);

  // The card, under the message that announced the result.
  const card = page.locator("article.motm");
  await expect(card).toBeVisible({ timeout: 30_000 });
  await expect(card.getByRole("heading", { name: "Man of the match" })).toBeVisible();
  await card.scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${SHOTS}/web-1-ballot.png`, fullPage: false });

  // Both team sheets are on the ballot.
  const names = card.locator("button.motm-pick");
  expect(await names.count()).toBeGreaterThan(20);
  await expect(card.getByText("Votes are hidden until you have voted.")).toBeVisible();

  // By name, not by position: an index is only as stable as the order, and
  // the order is exactly what this is checking.
  const nameOf = async (i: number) => (await names.nth(i).innerText()).trim().split("\n")[0];
  const rowFor = (name: string) => card.locator("button.motm-pick", { hasText: name });
  const orderNow = async () => (await names.allInnerTexts()).map((t) => t.trim().split("\n")[0]);

  const before = await orderNow();
  const firstName = await nameOf(0);
  const secondName = await nameOf(1);

  await rowFor(firstName).click();
  await expect(rowFor(firstName)).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });
  await expect(card.getByText(/vote[s]? so far\./)).toBeVisible();
  await card.scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${SHOTS}/web-2-voted.png` });

  // The ballot must not re-sort under the hand that is using it. Voting
  // reveals the tally, and the tally used to re-order the list — so the name
  // you were about to pick instead had moved.
  expect(await orderNow(), "the ballot re-ordered after voting").toEqual(before);

  // Move the vote — one vote each, not two.
  await rowFor(secondName).click();
  await expect(rowFor(secondName)).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });
  await expect(rowFor(firstName)).toHaveAttribute("aria-pressed", "false");
  await expect(card.getByText("1 vote so far.")).toBeVisible();
  expect(await orderNow(), "the ballot re-ordered after moving a vote").toEqual(before);

  // Clicking the same name again takes it back.
  await rowFor(secondName).click();
  await expect(rowFor(secondName)).toHaveAttribute("aria-pressed", "false", { timeout: 15_000 });

  // Put it back so the close has something to count.
  await rowFor(secondName).click();
  await expect(rowFor(secondName)).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });

  await card.getByRole("button", { name: "Close the vote now" }).click();
  await expect(card.getByText("Only a captain or club secretary can close the vote.")).toBeVisible({
    timeout: 15_000,
  });
  // The refusal must not leak the permission's internal name.
  await expect(card.getByText(/manage_events/)).toHaveCount(0);
  await card.scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${SHOTS}/web-3-refused.png` });

  // Refused, not closed: the ballot is still there.
  expect(await names.count()).toBeGreaterThan(20);
  console.log(`voted, moved it, took it back — and the ballot never re-ordered`);
});
