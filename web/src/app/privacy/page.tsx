import type { Metadata } from "next";
import Link from "next/link";
import { brand } from "@/brand.generated";

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

export default function PrivacyPage() {
  return (
    <main id="main">
      <section className="hero">
        <h1>Privacy</h1>
        <p>
          {brand.name} is a club app: it keeps the things a club needs to put a side out
          on a Saturday. This is all of it, in plain terms.
        </p>
        <p className="muted">Last updated 17 September 2026.</p>
      </section>

      <div className="panel">
        <h2>Who holds it</h2>
        <p>
          {CONTROLLER} is the data controller. Questions, corrections and complaints
          go to <strong>{CONTACT}</strong>.
        </p>

        <h2>What we record</h2>
        <ul>
          <li>
            <strong>Who you are</strong> — name, email address, mobile number, and an
            emergency contact if you give one. Your profile picture if you upload one.
          </li>
          <li>
            <strong>What you play</strong> — sports, positions, self-rated standard,
            and the career figures you choose to enter.
          </li>
          <li>
            <strong>Where you can get to</strong> — the area, postcode, travel radius
            and preferred days you enter, so a club can work out lifts and selection.
          </li>
          <li>
            <strong>What you do in a club</strong> — memberships, fixtures, whether you
            said you could play, whether you turned up, and ball-by-ball scoring for
            matches you take part in.
          </li>
          <li>
            <strong>Messages</strong> you send in club chat.
          </li>
          <li>
            <strong>Payments</strong> — match fees and shop orders. Card details never
            reach us; Stripe handles those and we keep only the record that you paid.
          </li>
          <li>
            <strong>A device token</strong> if you turn notifications on, so we can
            send them.
          </li>
        </ul>

        <h2>Why</h2>
        <p>
          To run the club you joined: selecting sides, telling you about fixtures,
          scoring matches, taking subs. We do not sell it, we do not advertise against
          it, and we do not profile you for anything beyond the availability and
          reliability figures your own club can already see.
        </p>

        <h2>Who else sees it</h2>
        <ul>
          <li><strong>Your club.</strong> Members and officials see what the app shows them.</li>
          <li><strong>Stripe</strong>, for payments.</li>
          <li><strong>Google</strong>, only if you choose to sign in with Google.</li>
          <li><strong>Apple and your browser&apos;s push service</strong>, to deliver notifications.</li>
          <li>Our email and messaging providers, to send you codes and reminders.</li>
        </ul>
        <p>
          The assistant features run on a model we host ourselves. Your messages are
          not sent to a third-party AI service.
        </p>

        <h2>How long</h2>
        <p>
          For as long as your account exists. Backups are kept for 14 days and roll off
          on their own.
        </p>

        <h2>Deleting your account</h2>
        <p>
          <strong>Profile → Delete account</strong>, in the app or on the web. It is
          immediate and cannot be undone.
        </p>
        <p>
          Everything that identifies you goes: name, email, phone, password, picture,
          location, your player profile, every signed-in session and every device
          token. What stays is the scorecards and club history you were part of, under
          a name that no longer points at anybody — those records belong to the other
          players too, and a match that loses a batter stops adding up.
        </p>

        <h2>Your rights</h2>
        <p>
          Under UK GDPR you can ask for a copy of your data, ask us to correct it, ask
          us to delete it, or object to how we use it. Write to {CONTACT} and we will
          answer within a month. You can also complain to the ICO at{" "}
          <a href="https://ico.org.uk" target="_blank" rel="noreferrer">ico.org.uk</a>.
        </p>

        <h2>Children</h2>
        <p>
          Junior members are a normal part of a cricket club. Where a member is under
          13, the club is expected to have the parent or guardian set the account up
          and agree to this policy.
        </p>

        <p className="muted" style={{ marginTop: 24 }}>
          <Link href="/">Back to {brand.name}</Link>
        </p>
      </div>
    </main>
  );
}
