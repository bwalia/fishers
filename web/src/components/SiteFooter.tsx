import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";
import { appVersion } from "@/lib/version";

/// The bottom of every page: what the thing is, where the legal pages are,
/// and which build you are looking at.
///
/// A server component, so none of this costs the browser any JavaScript — and
/// so the links are in the HTML a crawler reads, which is half the point of
/// having them. The other half is that App Store review, the ICO and anybody
/// deciding whether to trust a club's data to us all look for exactly these
/// links in exactly this place.
export async function SiteFooter() {
  const t = await getT();
  const version = await appVersion();
  const year = new Date().getFullYear();

  return (
    <footer className="site-foot">
      <div className="site-foot-in">
        <div className="site-foot-brand">
          <p className="site-foot-name">{brand.name}</p>
          <p className="muted">{t("foot.blurb")}</p>
        </div>

        <nav className="site-foot-cols" aria-label={t("foot.label")}>
          <div className="site-foot-col">
            <h2>{t("foot.the_app")}</h2>
            <Link href="/tour">{t("foot.tour")}</Link>
            <Link href="/docs">{t("foot.guide")}</Link>
            <Link href="/hire">{t("nav.hire")}</Link>
          </div>

          <div className="site-foot-col">
            <h2>{t("foot.your_account")}</h2>
            <Link href="/profile">{t("nav.profile")}</Link>
            <Link href="/profile#delete">{t("foot.delete_account")}</Link>
          </div>

          <div className="site-foot-col">
            <h2>{t("foot.legal")}</h2>
            <Link href="/privacy">{t("rest.privacy")}</Link>
            <Link href="/terms">{t("foot.terms")}</Link>
            <Link href="/sitemap.xml">{t("foot.sitemap")}</Link>
          </div>

          <div className="site-foot-col">
            <h2>{t("foot.get_in_touch")}</h2>
            <a href={`mailto:${brand.supportEmail}`}>{brand.supportEmail}</a>
          </div>
        </nav>
      </div>

      <div className="site-foot-bar">
        <p className="muted">
          © {year} {brand.legalName}. {t("foot.rights")}
        </p>
        {version && (
          <a
            className="site-foot-build"
            href={version.url}
            rel="noreferrer noopener"
            target="_blank"
            title={t("foot.build_on_github")}
          >
            {version.tag}
          </a>
        )}
      </div>
    </footer>
  );
}
