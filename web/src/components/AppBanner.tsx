import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { postsForBrand } from "@/lib/blog";

/// The strip above the top bar on every page: the app's own icon, one line
/// saying it is on the App Store, and the badge.
///
/// Above the bar rather than inside it because the bar is already full on a
/// phone, and above the page rather than in a hero because it has to be on
/// every page — a club's public page or a live scoreboard is exactly where
/// somebody who has never heard of the app arrives. It scrolls away with the
/// page; the bar under it stays sticky as it always did.
///
/// A server component, and nothing at all for a brand with no live listing.
export async function AppBanner() {
  if (!brand.appStoreUrl) return null;
  const t = await getT();
  const launch = postsForBrand()[0];

  return (
    <aside className="app-banner" aria-label={t("app.banner_label")}>
      <div className="app-banner-in">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="app-banner-icon" src="/icon-192.png" width={40} height={40} alt="" />
        <p className="app-banner-text">
          <strong>{t("app.banner", { brand: brand.name })}</strong>
          {launch && (
            <Link href={`/blog/${launch.slug}`} className="app-banner-story">
              {t("app.banner_story")}
            </Link>
          )}
        </p>
        <AppStoreBadge label={t("app.download", { brand: brand.name })} height={40} />
      </div>
    </aside>
  );
}
