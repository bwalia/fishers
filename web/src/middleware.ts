import { NextResponse, type NextRequest } from "next/server";

import { isIndexable } from "@/lib/site";

/// Send every other hostname to the one this ring calls itself.
///
/// Prod answers on two names — `fishers.cloud` because people type it, and
/// `www.fishers.cloud` because that is the ring's hostname — and only one of
/// them can be the site. Two that both work is not a nicety: Google authorises
/// sign-in per origin, and a session cookie set on one is not sent to the
/// other, so whichever name a member happened to type would decide whether
/// they are logged in.
///
/// In middleware rather than `redirects()` in next.config.js, which is
/// evaluated at build time and compiled into the route manifest: one image
/// serves every ring, so a build-time list would carry whichever ring built it
/// into all the others. This is read per request, from the value the chart
/// sets alongside the ingress hosts it lets through.
///
/// `CANONICAL_REDIRECTS` is `from>to`, comma-separated. Unset — every ring but
/// prod, and local development — and this does nothing at all.
const REDIRECTS = new Map(
  (process.env.CANONICAL_REDIRECTS ?? "")
    .split(",")
    .map((pair) => pair.split(">").map((s) => s.trim().toLowerCase()))
    .filter(([from, to]) => from && to) as [string, string][]
);

export function middleware(request: NextRequest) {
  const moved = canonicalRedirect(request);
  if (moved) return moved;

  const response = NextResponse.next();
  // Said in the response as well as in robots.txt, because the two are read
  // by different things: robots.txt asks a crawler not to fetch the page,
  // this tells anything that fetched it anyway not to index what it got.
  //
  // Worth knowing if a test ring is ever actually found in a search index:
  // the two work against each other at that point, because a crawler that is
  // refused the page never sees this header and so never learns to drop it.
  // Getting it removed means letting the crawler back in — the disallow in
  // `robots.ts` lifted — until it has re-read the page and seen this.
  if (!isIndexable()) response.headers.set("X-Robots-Tag", "noindex, nofollow");
  return response;
}

/// Sends a request on to the hostname this ring calls itself, or nothing when
/// it already arrived on it.
function canonicalRedirect(request: NextRequest) {
  if (REDIRECTS.size === 0) return null;

  // The Host header carries the port on a non-standard one; the map is keyed
  // by hostname alone, because that is what anybody configures.
  const host = (request.headers.get("host") ?? "").split(":")[0].toLowerCase();
  const to = REDIRECTS.get(host);
  if (!to) return null;

  const url = request.nextUrl.clone();
  url.host = to;
  url.port = "";
  // The edge terminates TLS and talks to us over http, so the incoming
  // protocol is not the one the browser used. Anything we redirect to is
  // public and behind the edge.
  url.protocol = "https:";
  // 308 rather than 307: permanent, and it keeps the method, so a form posted
  // to the wrong hostname is not silently turned into a GET.
  return NextResponse.redirect(url, 308);
}

export const config = {
  // Everything except Next's own assets and the files served from the app
  // root. A redirect on a chunk request would break the page it belongs to
  // rather than move the visitor.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icon.svg|apple-icon.png).*)"],
};
