import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";
import { Icon } from "@/components/Icon";
import { TourFilm } from "@/components/TourFilm";
import { TOUR_CHAPTERS, TOUR_DURATION, TOUR_VIDEO_ID } from "./chapters";

export const metadata: Metadata = {
  title: "Video tour — Fishers",
  description:
    "Twenty minutes of Fishers on a phone: a player joining a club, availability, a captain " +
    "picking the side, a whole T20 scored ball by ball, and the rest of the cricket section.",
  openGraph: {
    title: "Fishers — the video tour",
    description:
      "A season on a phone: joining a club, availability, selection, a T20 scored ball by ball, " +
      "and everything the cricket section does.",
    type: "video.other",
    images: [`https://i.ytimg.com/vi/${TOUR_VIDEO_ID}/maxresdefault.jpg`],
  },
};

/// `/tour` — the film, its five chapters, and everything it says, with the same
/// contents as a PDF for anyone who would rather keep it than stream it.
///
/// Static on purpose: this is the page a club chairman opens on a phone signal
/// in a car park, so it asks nothing of the API.
export default function TourPage() {
  return (
    <main id="main" className="tour">
      <section className="tour-hero">
        <p className="lp-brand">
          <BrandMark size={36} />
          <span>Fishers</span>
        </p>
        <p className="lp-kicker">Video tour · {TOUR_DURATION}</p>
        <h1>A season on a phone, from sign-up to the last ball</h1>
        <p className="lp-lead">
          One run through the app as a club actually uses it: a player joining, the
          Saturday availability, a captain picking the side, a whole twenty-over match
          scored ball by ball, and everything else the cricket section does. Five
          chapters — start wherever you like.
        </p>
        <div className="lp-actions">
          <a
            className="btn primary lp-btn"
            href="/fishers-video-tour-contents.pdf"
            download
          >
            <Icon name="download" size={18} /> Contents as a PDF
          </a>
          <a
            className="btn lp-btn"
            href={`https://youtu.be/${TOUR_VIDEO_ID}`}
            target="_blank"
            rel="noreferrer"
          >
            Watch on YouTube
          </a>
        </div>
        <p className="lp-fine">
          {TOUR_CHAPTERS.length} chapters · every screen listed with its timestamp ·{" "}
          <Link href="/">back to Fishers</Link>
        </p>
      </section>

      <TourFilm />

      <section className="tour-cta">
        <h2>Run your own club on it</h2>
        <p className="muted">
          Everything in the film is in the app today. A club takes about a minute to
          start, and players join from a link.
        </p>
        <div className="lp-actions">
          <Link className="btn primary lp-btn" href="/register?as=secretary">
            <Icon name="plus" size={18} /> Start your club
          </Link>
          <Link className="btn lp-btn" href="/register?as=player">
            I play for a club
          </Link>
        </div>
      </section>
    </main>
  );
}
