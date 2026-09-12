import { expect, type Browser, type BrowserContext, type Locator, type Page } from "@playwright/test";
import { BASE_URL, PASSWORD } from "./env";
import type { ClubSpec, Person } from "./people";

/// One person at their own browser: their own cookies and storage, so two
/// captains and a player can be signed in at once, the way they would be at a
/// ground.
export type Actor = { who: Person; context: BrowserContext; page: Page };

export async function actor(browser: Browser, who: Person, videoDir: string): Promise<Actor> {
  const context = await browser.newContext({
    baseURL: BASE_URL,
    viewport: { width: 1280, height: 900 },
    recordVideo: { dir: `${videoDir}/${who.key}`, size: { width: 1280, height: 900 } },
  });
  // Runs are one tap each: the shot-and-direction questions are for people.
  await context.addInitScript(() => {
    try {
      localStorage.setItem("fishers_ask_shot", "0");
      localStorage.setItem("fishers:push-prompt-dismissed", "1");
    } catch {
      /* storage blocked */
    }
  });
  const page = await context.newPage();
  return { who, context, page };
}

/// Click something a floating panel may be sitting over. The getting-started
/// tour renders after its dashboard data arrives, so it can appear between
/// clearing the overlays and the click — clear again and have another go.
export async function clickPast(page: Page, target: Locator, tries = 3) {
  for (let attempt = 1; ; attempt++) {
    try {
      await target.click({ timeout: 8000 });
      return;
    } catch (err) {
      if (attempt >= tries) throw err;
      await clearOverlays(page);
    }
  }
}

/// Close anything floating over the page: the getting-started spotlight and
/// live toasts sit on top of buttons a person would simply look past.
export async function clearOverlays(page: Page) {
  for (const got of await page.getByRole("button", { name: "Got it" }).all()) {
    await got.click({ timeout: 2000 }).catch(() => {});
  }
  for (const close of await page.locator(".live-alert-close").all()) {
    await close.click({ timeout: 2000 }).catch(() => {});
  }
}

/// Sign in through the sign-in page. False when there is no such account —
/// and only then: the page says the same thing however a sign-in fails, so a
/// refusal is checked against the API before it is taken to mean "not
/// registered yet". A server that is down must not look like a missing
/// account and quietly send the run off to register 24 people again.
export async function signIn(page: Page, who: Person): Promise<boolean> {
  await page.goto("/login");
  const form = page.locator("form.auth-form");
  await form.locator('input[autocomplete="username"]').fill(who.email);
  await form.locator('input[autocomplete="current-password"]').fill(PASSWORD);
  await form.getByRole("button", { name: "Sign in", exact: true }).click();
  const outcome = await Promise.race([
    page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30_000 }).then(() => "in" as const),
    form.locator(".error").waitFor({ timeout: 30_000 }).then(() => "refused" as const),
  ]);
  if (outcome === "in") return true;

  const status = await page.evaluate(async ([email, password]) => {
    const base = location.port === "7311" ? `${location.protocol}//${location.hostname}:7312` : "";
    const r = await fetch(`${base}/api/v1/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identifier: email, password }),
    });
    return r.status;
  }, [who.email, PASSWORD]);
  if (status === 401) return false; // no such account (or the password changed)
  throw new Error(`Signing ${who.email} in failed with HTTP ${status} — not a missing account.`);
}

/// Register through the register page, saying what they are here to do.
export async function register(page: Page, who: Person) {
  await page.goto("/register");
  await page
    .getByRole("radio", { name: who.role === "secretary" ? /I run a club/ : /I play for a club/ })
    .click();
  const form = page.locator("form.auth-form");
  await form.locator('input[autocomplete="name"]').fill(who.name);
  await form.locator('input[autocomplete="email"]').fill(who.email);
  await form.locator('input[autocomplete="new-password"]').fill(PASSWORD);
  await form.getByRole("button", { name: "Create account" }).click();
  await page.waitForURL((u) => u.pathname === "/", { timeout: 30_000 });
}

/// Signed in as `who`, registering first if this is the first run.
export async function ensureAccount(a: Actor): Promise<"created" | "reused"> {
  const reused = await signIn(a.page, a.who);
  if (!reused) await register(a.page, a.who);
  const user = await storedUser(a.page);
  expect(user?.name, "signed in as the right person").toBe(a.who.name);
  return reused ? "reused" : "created";
}

export async function signOut(page: Page) {
  await page.goto("/");
  await clearOverlays(page);
  await page.getByRole("button", { name: /Sign out/ }).first().click();
  await page.waitForURL((u) => u.pathname.startsWith("/login"), { timeout: 15_000 });
  // Landing on /login is not the end of it: the page can still be settling,
  // and reading storage mid-navigation throws rather than answering. Ask
  // until it answers.
  await expect
    .poll(
      () =>
        page
          .evaluate(() => localStorage.getItem("fishers_access_token"))
          .catch(() => "still navigating"),
      { message: "the session was cleared", timeout: 15_000 }
    )
    .toBeNull();
}

/// Reading the page while it is still navigating throws instead of
/// answering. Ask again once it has settled.
export async function stableEval<T>(page: Page, run: () => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await run();
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      if (attempt >= 3 || !/Execution context was destroyed|navigating|Target closed/i.test(message)) throw err;
      await page.waitForLoadState("domcontentloaded").catch(() => {});
    }
  }
}

export async function storedUser(page: Page): Promise<{ id: string; name: string; role_intent?: string | null } | null> {
  return stableEval(page, () =>
    page.evaluate(() => {
      const raw = localStorage.getItem("fishers_user");
      return raw ? JSON.parse(raw) : null;
    })
  );
}

/// Read from the API as this person — for checking that what the screen
/// showed was really saved. Refreshes an expired session the way the app does.
export async function apiGet<T = any>(page: Page, path: string): Promise<T> {
  const out = await stableEval(page, () =>
    page.evaluate(async (path) => {
      // The same rule the app uses: the dev server's API is on the next port;
      // anywhere else it is this origin under /api.
      const base = location.port === "7311" ? `${location.protocol}//${location.hostname}:7312` : "";
      const get = () =>
        fetch(`${base}/api/v1${path}`, {
          headers: { Authorization: `Bearer ${localStorage.getItem("fishers_access_token")}` },
        });
      let r = await get();
      if (r.status === 401) {
        const refreshed = await fetch(`${base}/api/v1/auth/refresh`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refresh_token: localStorage.getItem("fishers_refresh_token") }),
        });
        if (refreshed.ok) {
          const t = await refreshed.json();
          localStorage.setItem("fishers_access_token", t.access_token);
          localStorage.setItem("fishers_refresh_token", t.refresh_token);
          r = await get();
        }
      }
      return { status: r.status, body: await r.json().catch(() => null) };
    }, path)
  );
  if (out.status >= 300) throw new Error(`GET ${path}: ${out.status} ${JSON.stringify(out.body)}`);
  return out.body as T;
}

export type ClubInfo = { id: string; name: string; code: string; codeLink: string };

/// The secretary's club: opened if it exists, started if not. Returns its id
/// and the link printed under its code.
export async function ensureClub(a: Actor, club: ClubSpec): Promise<ClubInfo & { status: "created" | "reused" }> {
  const page = a.page;
  const mine = await apiGet<{ id: string; name: string }[]>(page, "/clubs");
  let status: "created" | "reused" = "reused";
  if (!mine.some((c) => c.name === club.name)) {
    status = "created";
    await page.goto("/clubs?new=1");
    await clearOverlays(page);
    await page.locator('input[placeholder="Fishers CC"]').fill(club.name);
    await page.getByRole("button", { name: "Create club" }).click();
    await expect(page.locator(".club-card", { hasText: club.name })).toBeVisible();
  }
  await page.goto("/clubs");
  await page.locator(".club-card", { hasText: club.name }).first().click();
  await page.waitForURL(/\/clubs\/[0-9a-f-]{36}/);
  const id = page.url().match(/\/clubs\/([0-9a-f-]{36})/)![1];
  await expect(page.locator("main h1").first(), "club page shows the club").toContainText(club.name);
  // The code and its link, "at the bottom of the club page".
  const card = page.locator(".qr-card", { has: page.locator(".tag", { hasText: /^club$/ }) });
  await expect(card, "the club's code is on its page").toBeVisible();
  const codeLink = (await card.locator(".qr-payload").innerText()).trim();
  const code = codeLink.split("/").pop()!;
  return { id, name: club.name, code, codeLink, status };
}

export type Member = { user_id: string; name: string; role: string; status: string };

export async function members(page: Page, clubId: string): Promise<Member[]> {
  return apiGet<Member[]>(page, `/clubs/${clubId}/members`);
}

/// The player's own profile link, from their profile page.
export async function profileLink(page: Page): Promise<string> {
  await page.goto("/profile");
  const button = page.getByRole("button", { name: /Get my profile link/ });
  const input = page.locator("#profile-link");
  // One or the other, once the page has loaded — isVisible() does not wait.
  await expect(button.or(input).first()).toBeVisible();
  if (await button.isVisible()) await button.click();
  await expect(input).toHaveValue(/\/p\/[A-Za-z0-9]{16,64}$/);
  return input.inputValue();
}

/// Path part of a link, so a link printed for one host can be opened here.
export const pathOf = (link: string) => new URL(link, BASE_URL).pathname;
