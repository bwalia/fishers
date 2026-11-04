import type { Metadata } from "next";
import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  return {
    title: `${t("foot.delete_account")} — ${brand.name}`,
    description: t("del.description", { brand: brand.name }),
    alternates: { canonical: "/delete-account" },
  };
}

/// The address Google Play's Data safety form asks for: a public page that
/// names the app, gives the steps to delete an account, and says which data
/// goes, which stays and for how long. App Store Connect has no field for it,
/// but the same page answers the question there.
///
/// Static and signed-out on purpose, for the reason the privacy policy and the
/// support page are: the person reading this may be the one who cannot sign
/// in. Profile → Delete account is behind a login; this page is not.
///
/// What it says is what `users_repo::delete_account` does, and nothing it does
/// not — the name, email, phone, password, picture reference, emergency
/// contact, location and player profile are cleared, every session and device
/// token is closed, and the row becomes "Deleted member". Scorecards, club
/// history and messages are not touched, so they are listed under what stays
/// rather than left for somebody to discover. The picture's file is the one
/// thing a reader might assume is gone and is not: Storage can put and cannot
/// delete yet, and the page says so rather than round it up.
///
/// Backups are 14 days, the same figure the policy gives under "How long".
export default async function DeleteAccountPage() {
  const t = await getT();
  return (
    <main id="main" className="reading">
      <section className="hero">
        <h1>{t("foot.delete_account")}</h1>
        <p>{t("del.intro", { brand: brand.name, controller: brand.legalEntity })}</p>
      </section>

      <div className="panel">
        <h2>{t("del.in_the_app")}</h2>
        <ol>
          <li>{t("del.step_signin", { brand: brand.name })}</li>
          <li>
            {t("del.step_profile")} <strong>{t("privacy.profile_delete_account")}</strong>
          </li>
          <li>{t("del.step_confirm")}</li>
          <li>{t("del.step_done")}</li>
        </ol>

        <h2>{t("del.on_the_website")}</h2>
        <p>
          {t("del.web_same")}{" "}
          <Link href="/profile#delete">{t("cl.delete_account")}</Link>
        </p>

        <h2>{t("del.cannot_sign_in")}</h2>
        <p>
          {t("del.cannot_sign_in_detail", { email: brand.supportEmail })}{" "}
          <a href={`mailto:${brand.supportEmail}`}>{brand.supportEmail}</a>
        </p>
      </div>

      <div className="panel">
        <h2>{t("del.what_goes")}</h2>
        <ul>
          <li>{t("del.d_identity")}</li>
          <li>{t("del.d_profile")}</li>
          <li>{t("del.d_access")}</li>
        </ul>

        <h2>{t("del.what_stays")}</h2>
        <ul>
          <li>{t("del.k_records")}</li>
          <li>{t("del.k_messages")}</li>
          <li>{t("privacy.reports_outlive")}</li>
          <li>{t("del.k_photo")}</li>
        </ul>

        <h2>{t("rest.how_long")}</h2>
        <p>{t("del.how_long")}</p>

        <p className="muted" style={{ marginTop: 24 }}>
          {t("del.more_detail")} <Link href="/privacy">{t("rest.privacy")}</Link>
        </p>
      </div>
    </main>
  );
}
