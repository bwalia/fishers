import type { Metadata } from "next";
import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  return {
    title: `${t("foot.terms")} — ${brand.name}`,
    description: t("terms.description", { brand: brand.name }),
    alternates: { canonical: "/terms" },
  };
}

/// The other half of what an app store, a club treasurer and anybody deciding
/// whether to trust us with a members' list all look for. Static for the same
/// reason the privacy policy is: terms that need the API up are no use to
/// somebody arguing with us about them.
///
/// TODO before submitting: replace CONTROLLER, CONTACT and JURISDICTION with
/// the legal entity that actually runs this, an address somebody answers, and
/// the place whose courts it answers in. The same three placeholders are in
/// `privacy/page.tsx`; changing one and not the other is the mistake to avoid.
const CONTROLLER = `[the operator of ${brand.name}]`;
const CONTACT = brand.supportEmail;
const JURISDICTION = "[England and Wales]";

export default async function TermsPage() {
  const t = await getT();
  return (
    <main id="main">
      <section className="hero">
        <h1>{t("foot.terms")}</h1>
        <p>{t("terms.intro", { brand: brand.name })}</p>
        <p className="muted">{t("terms.last_updated")}</p>
      </section>

      <div className="panel prose">
        <h2>{t("terms.who")}</h2>
        <p>{t("terms.who_body", { brand: brand.name, controller: CONTROLLER, contact: CONTACT })}</p>

        <h2>{t("terms.what_this_is")}</h2>
        <p>{t("terms.what_this_is_body")}</p>

        <h2>{t("terms.your_account")}</h2>
        <ul>
          <li>{t("terms.account_one_each")}</li>
          <li>{t("terms.account_password")}</li>
          <li>{t("terms.account_age")}</li>
        </ul>

        <h2>{t("terms.not_allowed")}</h2>
        <ul>
          <li>{t("terms.not_allowed_abuse")}</li>
          <li>{t("terms.not_allowed_uploads")}</li>
          <li>{t("terms.not_allowed_prying")}</li>
          <li>{t("terms.not_allowed_automation")}</li>
        </ul>

        <h2>{t("terms.your_content")}</h2>
        <p>{t("terms.your_content_yours")}</p>
        <p>{t("terms.your_content_shared_record")}</p>

        <h2>{t("terms.clubs")}</h2>
        <p>{t("terms.clubs_body")}</p>
        <p>
          {t("terms.clubs_privacy")} <Link href="/privacy">{t("rest.privacy")}</Link>.
        </p>

        <h2>{t("terms.paying")}</h2>
        <p>{t("terms.paying_body")}</p>
        <p>{t("terms.paying_cards")}</p>

        <h2>{t("terms.breaks")}</h2>
        <p>{t("terms.breaks_offline")}</p>
        <p>{t("terms.breaks_changes")}</p>

        <h2>{t("terms.ending")}</h2>
        <p>
          {t("terms.ending_you")}{" "}
          <Link href="/profile#delete">{t("foot.delete_account")}</Link>.
        </p>
        <p>{t("terms.ending_us")}</p>

        <h2>{t("terms.liability")}</h2>
        <p>{t("terms.liability_body")}</p>

        <h2>{t("terms.law")}</h2>
        <p>{t("terms.law_body", { jurisdiction: JURISDICTION })}</p>

        <h2>{t("terms.changes")}</h2>
        <p>{t("terms.changes_body")}</p>

        <h2>{t("terms.contact")}</h2>
        <p>
          {t("terms.contact_body")} <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>

        <p className="muted" style={{ marginTop: 24 }}>
          <Link href="/">{t("privacy.back_to_brand", { brand: brand.name })}</Link>
        </p>
      </div>
    </main>
  );
}
