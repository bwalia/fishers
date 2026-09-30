import type { Metadata } from "next";
import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

export const metadata: Metadata = {
  title: `Privacy — ${brand.name}`,
  description: `What ${brand.name} records about you, why, and how to have it deleted.`,
};

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
          {brand.name} is a club app: it keeps the things a club needs to put a side out
          on a Saturday. This is all of it, in plain terms.
        </p>
        <p className="muted">{t("rest.last_updated_17_september_2026")}</p>
      </section>

      <div className="panel">
        <h2>{t("rest.who_holds_it")}</h2>
        <p>
          {CONTROLLER} is the data controller. Questions, corrections and complaints
          go to <strong>{CONTACT}</strong>.
        </p>

        <h2>{t("rest.what_we_record")}</h2>
        <ul>
          <li>
            <strong>{t("rest.who_you_are")}</strong> — name, email address, mobile number, and an
            emergency contact if you give one. Your profile picture if you upload one.
          </li>
          <li>
            <strong>{t("rest.what_you_play")}</strong> — sports, positions, self-rated standard,
            and the career figures you choose to enter.
          </li>
          <li>
            <strong>{t("rest.where_you_can_get_to")}</strong> — the area, postcode, travel radius
            and preferred days you enter, so a club can work out lifts and selection.
          </li>
          <li>
            <strong>{t("rest.what_you_do_in_a_club")}</strong> — memberships, fixtures, whether you
            said you could play, whether you turned up, and ball-by-ball scoring for
            matches you take part in.
          </li>
          <li>
            <strong>{t("rest.messages")}</strong> {t("rest.you_send_in_club_chat")}
          </li>
          <li>
            <strong>{t("rest.payments")}</strong> — match fees and shop orders. Card details never
            reach us; Stripe handles those and we keep only the record that you paid.
          </li>
          <li>
            <strong>{t("rest.a_device_token")}</strong> {t("rest.if_you_turn_notifications_on_so_we_can")}
          </li>
        </ul>

        <h2>Why</h2>
        <p>
          {t("rest.to_run_the_club_you_joined_selecting_s")}
        </p>

        <h2>{t("rest.who_else_sees_it")}</h2>
        <ul>
          <li><strong>{t("rest.your_club")}</strong> {t("rest.members_and_officials_see_what_the_app")}</li>
          <li><strong>{t("rest.stripe")}</strong>, for payments.</li>
          <li><strong>{t("rest.google")}</strong>, only if you choose to sign in with Google.</li>
          <li><strong>Apple and your browser&apos;s push service</strong>, to deliver notifications.</li>
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
          <strong>Profile → Delete account</strong>, in the app or on the web. It is
          immediate and cannot be undone.
        </p>
        <p>
          {t("rest.everything_that_identifies_you_goes_na")}
        </p>

        <h2>{t("rest.your_rights")}</h2>
        <p>
          Under UK GDPR you can ask for a copy of your data, ask us to correct it, ask
          us to delete it, or object to how we use it. Write to {CONTACT} and we will
          answer within a month. You can also complain to the ICO at{" "}
          <a href="https://ico.org.uk" target="_blank" rel="noreferrer">{t("rest.ico_org_uk")}</a>.
        </p>

        <h2>{t("rest.children")}</h2>
        <p>
          {t("rest.junior_members_are_a_normal_part_of_a")}
        </p>

        <p className="muted" style={{ marginTop: 24 }}>
          <Link href="/">Back to {brand.name}</Link>
        </p>
      </div>
    </main>
  );
}
