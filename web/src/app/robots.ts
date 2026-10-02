import type { MetadataRoute } from "next";
import { isIndexable, siteUrl } from "@/lib/site";

/// Rendered per request, never at build time.
///
/// One image serves int, test, acc and prod, so anything prerendered carries
/// whichever ring happened to build it into all the others — the same reason
/// the canonical-hostname redirects live in middleware rather than in
/// `next.config.js`. Prerendered, this file would have been built with no
/// `WEB_RING` set at all and served production a flat `Disallow: /`.
export const dynamic = "force-dynamic";

/// What a crawler may read.
///
/// Everything behind a sign-in is disallowed — not to hide it, but because a
/// crawler there gets the same empty shell every time (the session is read in
/// the browser), and a few hundred identical pages is how a site teaches a
/// search engine that it has nothing to say.
///
/// The token routes are disallowed for a better reason: a share link, an
/// invite and a player's profile link are all addresses somebody was given.
/// They are not secret, but they are not for indexing either.
export default function robots(): MetadataRoute.Robots {
  // Every ring but production is a copy of the product on the open internet.
  // Nothing on one of them should ever be a search result, so none of the
  // detail below applies there — the whole host is closed, and no sitemap is
  // offered to go and read.
  if (!isIndexable()) {
    return { rules: [{ userAgent: "*", disallow: "/" }] };
  }

  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: [
          "/api/",
          "/admin",
          "/availability",
          "/chat",
          "/clubs",
          "/events",
          "/notifications",
          "/players",
          "/profile",
          "/score",
          "/scores",
          "/shop",
          "/stats",
          "/tournaments",
          "/welcome",
          // Given out, not found: share links, invites and profile links.
          "/entry/",
          "/invite/",
          "/live/",
          "/p/",
          "/play/",
        ],
      },
    ],
    sitemap: `${siteUrl()}/sitemap.xml`,
    host: siteUrl(),
  };
}
