import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/site";

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
