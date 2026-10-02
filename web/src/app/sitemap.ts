import type { MetadataRoute } from "next";
import { apiV1 } from "@/lib/api";
import { isIndexable, siteUrl } from "@/lib/site";

/// Rendered per request, never at build time.
///
/// One image serves int, test, acc and prod, so anything prerendered carries
/// whichever ring happened to build it into all the others — the same reason
/// the canonical-hostname redirects live in middleware rather than in
/// `next.config.js`. Prerendered, this file would have been built with no
/// `WEB_RING` set at all and served production a flat `Disallow: /`.
export const dynamic = "force-dynamic";


/// The club list is re-read hourly rather than per crawl, though: a sitemap
/// that costs the API a query every time a bot pulls it is a small denial of
/// service somebody else gets to schedule. The route is dynamic, the fetch
/// inside it is cached — which is the division that matters, because the ring
/// has to be read now and the club list does not.
const CLUBS_TTL = 3600;

/// The pages worth indexing: the ones a signed-out visitor can actually read.
///
/// Everything behind a sign-in is left out on purpose, and `robots.ts`
/// disallows it for the same reason — a crawler there gets the same empty
/// shell every time, because the session is read in the browser.
const STATIC: { path: string; priority: number }[] = [
  { path: "/", priority: 1 },
  { path: "/hire", priority: 0.7 },
  { path: "/docs", priority: 0.6 },
  { path: "/tour", priority: 0.6 },
  { path: "/register", priority: 0.5 },
  { path: "/login", priority: 0.3 },
  { path: "/terms", priority: 0.3 },
  { path: "/privacy", priority: 0.3 },
];

/// Club pages a club chose to publish — the only part of this site holding
/// content a search engine has any business ranking.
///
/// A failure here gives back nothing rather than throwing: a sitemap missing
/// the club pages still tells a crawler about the rest, and a 500 tells it
/// nothing at all.
async function clubPages(): Promise<MetadataRoute.Sitemap> {
  try {
    const res = await fetch(`${apiV1()}/public/clubs`, { next: { revalidate: CLUBS_TTL } });
    if (!res.ok) return [];
    const clubs: { slug: string; updated_at: string }[] = await res.json();
    return clubs.map((club) => ({
      url: `${siteUrl()}/c/${club.slug}`,
      lastModified: new Date(club.updated_at),
      changeFrequency: "weekly" as const,
      priority: 0.8,
    }));
  } catch {
    return [];
  }
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  // `robots.ts` already closes a non-production ring to crawlers; this is the
  // belt to that pair of braces. A sitemap is an invitation, and a test ring
  // has nothing to invite anybody to.
  if (!isIndexable()) return [];

  const base = siteUrl();
  const now = new Date();
  return [
    ...STATIC.map(({ path, priority }) => ({
      url: path === "/" ? base : base + path,
      lastModified: now,
      changeFrequency: "monthly" as const,
      priority,
    })),
    ...(await clubPages()),
  ];
}
