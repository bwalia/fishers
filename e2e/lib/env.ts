import { WEB_PORT } from "./ports";

/// Where the run points and who it signs in as. All from the environment, so
/// the same suite runs against int from CI and against a laptop's stack.
///
///   E2E_BASE_URL    default http://localhost:$WEB_PORT — a deployed ring is
///                   always asked for by name, because a run writes into it
///   E2E_PASSWORD    the password every test account uses (required)
///   E2E_NAMESPACE   default "e2e" — change it for a fresh set of accounts
///   WEB_PORT        default 7311, and API_PORT default 7312 — the local
///                   stack's ports, read from the repo's .env by
///                   playwright.config.ts before this module loads

/// Re-exported so the common case is one import. A run against a stack on a
/// moved port used to reach the dashboard — E2E_BASE_URL was given by hand —
/// and then miss the API, because app.ts's browser-side helpers had 7312
/// written into them.
export { API_PORT, WEB_PORT } from "./ports";

export const BASE_URL = (process.env.E2E_BASE_URL ?? `http://localhost:${WEB_PORT}`).replace(/\/$/, "");
export const PASSWORD = process.env.E2E_PASSWORD ?? "";
export const NAMESPACE = (process.env.E2E_NAMESPACE ?? "e2e").toLowerCase().replace(/[^a-z0-9]/g, "") || "e2e";

if (PASSWORD.length < 8) {
  throw new Error(
    "E2E_PASSWORD is not set (8+ characters). It is the password of every test account — " +
      "the same one each run, so the accounts made the first time are signed back into after."
  );
}
