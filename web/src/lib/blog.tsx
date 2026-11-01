import type { ReactNode } from "react";
import { brand } from "@/brand.generated";

/// The blog: a list of posts, each written for one brand.
///
/// In code rather than a CMS because there is one post and a CMS is a service
/// to run. A post belongs to brands by id — each brand is its own site with
/// its own readers, and Fishers' readers have no use for a Gully Cricket
/// launch. A brand with no posts has no blog: `/blog` is a 404 there and
/// nothing links to it.
///
/// The bodies are English in every language for now. The chrome around them
/// is translated; translating a post is a second body, not a dictionary key.
export type Post = {
  slug: string;
  brands: readonly string[];
  title: string;
  summary: string;
  /// ISO date, the day it went out.
  date: string;
  body: () => ReactNode;
};

const POSTS: Post[] = [
  {
    slug: "gully-cricket-on-the-app-store",
    brands: ["gullycricket"],
    title: "Gully Cricket is on the App Store",
    summary:
      "Version 1.0 for iPhone and iPad is out in every country the App Store serves. Free, no adverts, no in-app purchases.",
    date: "2026-11-01",
    body: () => (
      <>
        <p>
          Gully Cricket 1.0 is out on the App Store. It passed Apple&apos;s review on 28 October and went live on
          31 October, in every country the App Store serves. It runs on iPhone and iPad with iOS 17 or later.
          It&apos;s free, with no adverts and no in-app purchases.
        </p>

        <h2>Why we built it</h2>
        <p>
          A side doesn&apos;t need a pavilion to need a scorer. Most gully and weekend teams already run on a group
          chat: who&apos;s playing goes up in a hundred messages, the score lives on whoever&apos;s phone the notes
          app was open on, and by the end of the season everyone remembers their own average a little differently.
          Gully Cricket keeps those three things for the whole team: who&apos;s turning up, what the score is, and
          what everyone averaged.
        </p>

        <h2>What&apos;s in 1.0</h2>
        <ul>
          <li>
            <strong>Who&apos;s playing.</strong> Everyone marks themselves available, unavailable or doubtful for a
            match, and you pick the side from the answers.
          </li>
          <li>
            <strong>Matches.</strong> Every match with its ground, time and opposition, in one list everyone can see.
          </li>
          <li>
            <strong>Live scoring, ball by ball.</strong> Score from the side of the pitch on your phone: every ball,
            extras, wickets and how each one fell. Anyone who isn&apos;t there can follow it live.
          </li>
          <li>
            <strong>The full scorecard.</strong> Batting, bowling, partnerships and the result, laid out the way a
            scorebook does it.
          </li>
          <li>
            <strong>The season&apos;s numbers.</strong> Averages, strike rates, economy and best figures, by player
            and by team.
          </li>
          <li>
            <strong>A chat for each match.</strong> Threads for each side and each match, so the talk about Sunday
            doesn&apos;t get lost under everything else.
          </li>
          <li>
            <strong>English and Punjabi.</strong> All of the app, including the scoring words, not just the menus.
            You can switch whenever you like.
          </li>
        </ul>
        <p>Tape ball or leather, matting or turf, a park or a maidan: it&apos;s built for all of them.</p>

        <h2>Same account on the web</h2>
        <p>
          The app and this website share one account. Sign in on either and your team, your matches and your
          numbers are already there. If you score on the phone, the rest of the team can follow along here in a
          browser.
        </p>

        <h2>Tell us what&apos;s missing</h2>
        <p>
          This is the first version, and what goes into the next one depends on the teams using it. Write to{" "}
          <a href={`mailto:${brand.supportEmail}`}>{brand.supportEmail}</a> with what works, what doesn&apos;t and
          what your side needs. If you like it, a rating on the App Store helps the next team find it.
        </p>
      </>
    ),
  },
];

/// This brand's posts, newest first.
export function postsForBrand(): Post[] {
  return POSTS.filter((p) => p.brands.includes(brand.id)).sort((a, b) => b.date.localeCompare(a.date));
}

export function postBySlug(slug: string): Post | undefined {
  return postsForBrand().find((p) => p.slug === slug);
}

export function formatDate(iso: string, locale: string) {
  // Noon UTC, so no timezone moves the date a day either way.
  return new Date(`${iso}T12:00:00Z`).toLocaleDateString(locale === "pa" ? "pa-IN" : "en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}
