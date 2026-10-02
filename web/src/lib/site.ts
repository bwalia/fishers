import { brand } from "@/brand.generated";

/// The absolute base this deployment answers on, for canonicals, OpenGraph
/// images, the sitemap and robots — all of which have to be absolute URLs.
///
/// `PUBLIC_WEB_BASE` first, because a ring is not its brand: int answers on
/// int.gullycricket.app while the brand's domain is gullycricket.app, and a
/// canonical pointing at production from a test ring is how the wrong page
/// gets indexed. The brand's own domain is the fallback, which is right for
/// production and harmless anywhere a base is set.
export function siteUrl(): string {
  const base = process.env.PUBLIC_WEB_BASE?.trim();
  if (base) return base.replace(/\/+$/, "");
  return `https://${brand.domain}`;
}

/// Whether this ring may appear in a search engine at all.
///
/// Only production may. int, test and acc all answer on the open internet
/// with no password in front of them, so without this they are four more
/// crawlable copies of the same product, competing with the real one for the
/// same words — and the test ring, being smaller, sometimes wins.
///
/// Unset means no: a ring that nobody remembered to configure, and a local
/// development server, are both kept out rather than let in. Production sets
/// `WEB_RING` from the chart, where it is required.
export function isIndexable(): boolean {
  return process.env.WEB_RING?.trim().toLowerCase() === "prod";
}
