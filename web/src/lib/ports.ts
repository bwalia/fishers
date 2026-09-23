/// The local stack's ports, in one place.
///
/// `scripts/start.sh` writes `web/.env.local` with `NEXT_PUBLIC_API_PORT` set
/// to whatever `.env` resolved to, so a dashboard started that way already
/// follows the API wherever it moved. These are what a `npm run dev` started
/// by hand lands on, and they are the same numbers `.env.example` ships and
/// `scripts/start.sh` itself falls back to.
///
/// The client cannot read `API_PORT` directly: Next only inlines `NEXT_PUBLIC_`
/// variables into the browser bundle, which is why the generated file renames
/// it rather than the code reading both.
export const DEFAULT_API_PORT = "7312";
export const DEFAULT_WEB_PORT = "7311";

/// The API's port for this dashboard. Used by both the browser path and the
/// server-render path, which had their own copies of the default and so had
/// two places to forget.
export function apiPort(): string {
  return process.env.NEXT_PUBLIC_API_PORT || DEFAULT_API_PORT;
}
