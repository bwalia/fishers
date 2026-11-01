import { expect, test } from "@playwright/test";

/// The App Store banner, footer badge and blog — signed out, no API needed.
///
/// Brand-aware without being told the brand: a site with a live App Store
/// listing (Gully Cricket) must show all of it on every public page, and a site
/// without one (Fishers) must show none of it and 404 on /blog. Either way the
/// run says which it found, so a ring that lost its banner fails rather than
/// quietly being taken for the other brand — the title says which brand it is.
///
///   E2E_BASE_URL=https://int.gullycricket.app npx playwright test tests/app-store-and-blog.spec.ts
///   E2E_BASE_URL=https://int.fishers.cloud    npx playwright test tests/app-store-and-blog.spec.ts
const APP_STORE = /^https:\/\/apps\.apple\.com\/app\/[a-z0-9-]+\/id\d+$/;
const PAGES = ["/", "/privacy", "/terms", "/support", "/tour"];

async function hasListing(page: import("@playwright/test").Page) {
  await page.goto("/");
  const title = await page.title();
  // Only Gully Cricket has a live listing today. When Fishers gets one this
  // becomes "every brand", and the else-branch below is what changes.
  return { listed: /Gully Cricket/.test(title), title };
}

test("App Store banner and footer badge on every public page", async ({ page }) => {
  const { listed, title } = await hasListing(page);
  test.info().annotations.push({ type: "brand", description: title });

  for (const path of PAGES) {
    await page.goto(path);
    const banner = page.locator("aside.app-banner");
    const footBadge = page.locator(".site-foot .app-store-badge");

    if (!listed) {
      await expect(banner, `${path}: no banner without a listing`).toHaveCount(0);
      await expect(footBadge, `${path}: no footer badge without a listing`).toHaveCount(0);
      continue;
    }

    // Top: visible without scrolling, icon loaded, badge pointing at the listing.
    await expect(banner, `${path}: banner`).toBeVisible();
    const box = await banner.boundingBox();
    expect(box?.y ?? 999, `${path}: banner is at the top`).toBeLessThan(10);
    const icon = banner.locator("img.app-banner-icon");
    await expect(icon).toBeVisible();
    expect(await icon.evaluate((img: HTMLImageElement) => img.naturalWidth), `${path}: icon loaded`).toBeGreaterThan(0);

    const topBadge = banner.locator(".app-store-badge");
    await expect(topBadge).toBeVisible();
    await expect(topBadge).toHaveAttribute("href", APP_STORE);
    await expect(topBadge).toHaveAttribute("target", "_blank");
    await expect(topBadge).toHaveAttribute("aria-label", /App Store/);

    // Bottom: the same listing, and a Blog link.
    await expect(footBadge, `${path}: footer badge`).toHaveCount(1);
    expect(await footBadge.getAttribute("href")).toBe(await topBadge.getAttribute("href"));
    await expect(page.locator(".site-foot a[href='/blog']")).toHaveCount(1);
  }
});

test("blog index, launch post and sitemap", async ({ page, request }) => {
  const { listed } = await hasListing(page);

  if (!listed) {
    expect((await request.get("/blog")).status()).toBe(404);
    await expect(page.locator(".site-foot a[href='/blog']")).toHaveCount(0);
    return;
  }

  const index = await page.goto("/blog");
  expect(index?.status()).toBe(200);
  const post = page.locator(".blog-card h2 a").first();
  await expect(post).toBeVisible();
  const href = await post.getAttribute("href");
  expect(href).toMatch(/^\/blog\/[a-z0-9-]+$/);

  await post.click();
  await expect(page).toHaveURL(new RegExp(`${href}$`));
  await expect(page.locator("article.blog-post h1")).toContainText("App Store");
  await expect(page.locator("article.blog-post time")).toHaveAttribute("datetime", /^\d{4}-\d{2}-\d{2}$/);
  // Above the body and below it.
  await expect(page.locator("article.blog-post .app-store-badge")).toHaveCount(2);
  await expect(page.locator(".blog-post-body h2").first()).toBeVisible();

  // Its canonical is itself, not the home page.
  const canonical = await page.locator("link[rel='canonical']").getAttribute("href");
  expect(canonical ?? "").toMatch(new RegExp(`${href}$`));

  // The banner's "launch post" link lands on it.
  await page.goto("/");
  const story = page.locator("a.app-banner-story");
  if (await story.isVisible()) {
    expect(await story.getAttribute("href")).toBe(href);
  }

  expect((await request.get("/blog/no-such-post")).status()).toBe(404);

  // Only production is indexable; elsewhere the sitemap is deliberately empty.
  const sitemap = await (await request.get("/sitemap.xml")).text();
  if (sitemap.includes("<loc>")) {
    expect(sitemap).toContain(`${href}</loc>`);
  }
});

test("the banner fits a phone", async ({ browser, baseURL }) => {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(baseURL + "/");
  if (!/Gully Cricket/.test(await page.title())) return;

  const banner = page.locator("aside.app-banner");
  await expect(banner).toBeVisible();
  await expect(banner.locator(".app-store-badge")).toBeVisible();
  // Nothing in it spills sideways off the screen.
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
  const box = await banner.boundingBox();
  expect(box?.height ?? 999, "banner stays slim on a phone").toBeLessThan(110);
  await page.close();
});
