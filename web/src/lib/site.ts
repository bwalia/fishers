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
