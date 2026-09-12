/// Where the run points and who it signs in as. All from the environment, so
/// the same suite runs against int from CI and against a laptop's stack.
///
///   E2E_BASE_URL    default http://localhost:7311 — a deployed ring is always
///                   asked for by name, because a run writes into it
///   E2E_PASSWORD    the password every test account uses (required)
///   E2E_NAMESPACE   default "e2e" — change it for a fresh set of accounts

export const BASE_URL = (process.env.E2E_BASE_URL ?? "http://localhost:7311").replace(/\/$/, "");
export const PASSWORD = process.env.E2E_PASSWORD ?? "";
export const NAMESPACE = (process.env.E2E_NAMESPACE ?? "e2e").toLowerCase().replace(/[^a-z0-9]/g, "") || "e2e";

if (PASSWORD.length < 8) {
  throw new Error(
    "E2E_PASSWORD is not set (8+ characters). It is the password of every test account — " +
      "the same one each run, so the accounts made the first time are signed back into after."
  );
}
