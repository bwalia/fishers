/// The local stack's ports, which `.env` moves.
///
/// Separate from `env.ts` because that module refuses to load without
/// `E2E_PASSWORD`, and a test that only needs to know where the API is should
/// not have to satisfy a check about sign-in accounts to find out.
///
/// `playwright.config.ts` loads the repo's `.env` before any of this, so
/// `API_PORT=8080` there reaches these without being passed on the command
/// line. Anything already in the environment still wins.
export const WEB_PORT = process.env.WEB_PORT || "7311";
export const API_PORT = process.env.API_PORT || "7312";
