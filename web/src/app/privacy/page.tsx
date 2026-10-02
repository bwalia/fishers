import type { Metadata } from "next";
import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  return {
    title: `${t("rest.privacy")} — ${brand.name}`,
    description: t("sr.privacy_description", { brand: brand.name }),
    alternates: { canonical: "/privacy" },
  };
}

/// The policy App Store Connect asks for a link to, and the one the app links
/// to from Profile. Static on purpose: a privacy policy that needs the API up
/// is no use to somebody who has just deleted their account.
///
/// TODO before submitting: replace CONTROLLER and CONTACT below with the legal
/// entity that actually runs this and an address somebody answers.
const CONTROLLER = `[the operator of ${brand.name}]`;
const CONTACT = "[privacy@your-domain]";

export default async function PrivacyPage() {
  const t = await getT();
  return (
    <main id="main">
      <section className="hero">
        <h1>{t("rest.privacy")}</h1>
        <p>
          {t("privacy.brand_is_a_club_app", { brand: brand.name })}
        </p>
        <p className="muted">{t("rest.last_updated_17_september_2026")}</p>
      </section>

      <div className="panel">
        <h2>{t("rest.who_holds_it")}</h2>
        <p>
          {t("privacy.is_the_data_controller", { controller: CONTROLLER })}{" "}
          <strong>{CONTACT}</strong>.
        </p>

        <h2>{t("rest.what_we_record")}</h2>
        <ul>
          <li>
            <strong>{t("rest.who_you_are")}</strong>{t("privacy.who_you_are_detail")}
          </li>
          <li>
            <strong>{t("rest.what_you_play")}</strong>{t("privacy.what_you_play_detail")}
          </li>
          <li>
            <strong>{t("rest.where_you_can_get_to")}</strong>{t("privacy.where_you_can_get_to_detail")}
          </li>
          <li>
            <strong>{t("rest.what_you_do_in_a_club")}</strong>{t("privacy.what_you_do_in_a_club_detail")}
          </li>
          <li>
            <strong>{t("rest.messages")}</strong> {t("rest.you_send_in_club_chat")}
          </li>
          <li>
            <strong>{t("rest.payments")}</strong>{t("privacy.payments_detail")}
          </li>
          <li>
            <strong>{t("rest.a_device_token")}</strong> {t("rest.if_you_turn_notifications_on_so_we_can")}
          </li>
        </ul>

        <h2>{t("privacy.why")}</h2>
        <p>
          {t("rest.to_run_the_club_you_joined_selecting_s")}
        </p>

        <h2>{t("rest.who_else_sees_it")}</h2>
        <ul>
          <li><strong>{t("rest.your_club")}</strong> {t("rest.members_and_officials_see_what_the_app")}</li>
          <li><strong>{t("rest.stripe")}</strong>{t("privacy.stripe_for_payments")}</li>
          <li><strong>{t("rest.google")}</strong>{t("privacy.google_only_if_you_choose")}</li>
          <li><strong>{t("privacy.apple_and_push")}</strong>{t("privacy.to_deliver_notifications")}</li>
          <li>{t("rest.our_email_and_messaging_providers_to_s")}</li>
        </ul>
        <p>
          {t("rest.the_assistant_features_run_on_a_model")}
        </p>

        <h2>{t("rest.how_long")}</h2>
        <p>
          {t("rest.for_as_long_as_your_account_exists_bac")}
        </p>

        <h2>{t("rest.deleting_your_account")}</h2>
        <p>
          <strong>{t("privacy.profile_delete_account")}</strong>
          {t("privacy.immediate_cannot_be_undone")}
        </p>
        <p>
          {t("rest.everything_that_identifies_you_goes_na")}
        </p>

        <h2>{t("rest.your_rights")}</h2>
        <p>
          {t("privacy.your_rights_detail", { contact: CONTACT })}{" "}
          <a href="https://ico.org.uk" target="_blank" rel="noreferrer">{t("rest.ico_org_uk")}</a>.
        </p>

        <h2>{t("rest.children")}</h2>
        <p>
          {t("rest.junior_members_are_a_normal_part_of_a")}
        </p>

        <p className="muted" style={{ marginTop: 24 }}>
          <Link href="/">{t("privacy.back_to_brand", { brand: brand.name })}</Link>
        </p>
      </div>
    </main>
  );
}
