import { defineConfig, devices } from "@playwright/test";

// Local runs read E2E_* from the repo's .env (git-ignored); CI sets them as
// secrets. Values already in the environment win.
try {
  process.loadEnvFile("../.env");
} catch {
  /* no .env: fine in CI */
}

const { BASE_URL } = await import("./lib/env");

/// One long journey, not a suite of independent tests: each step builds on
/// the one before (the players it made, the match it started), so they run in
/// order in one worker and a failure skips what depends on it.
export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  // A step can be long — twenty-two players, or five overs ball by ball.
  timeout: 20 * 60_000,
  expect: { timeout: 20_000 },
  outputDir: "test-results",
  reporter: [
    ["list"],
    ["html", { open: "never", outputFolder: "playwright-report" }],
    ["json", { outputFile: "test-results/results.json" }],
  ],
  use: {
    baseURL: BASE_URL,
    actionTimeout: 20_000,
    navigationTimeout: 45_000,
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
