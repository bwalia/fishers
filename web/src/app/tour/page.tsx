import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";
import { Icon } from "@/components/Icon";
import { TourFilm } from "@/components/TourFilm";
import { TOUR_CHAPTERS, TOUR_DURATION, TOUR_VIDEO_ID } from "./chapters";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  const title = t("le.brand_video_tour", { brand: brand.name });
  return {
    title: t("sr.video_tour_brand", { brand: brand.name }),
    description: t("sr.tour_description", { brand: brand.name }),
    openGraph: {
      title,
      description: t("le.a_season_on_a_phone_joining_a_club_ava"),
      type: "video.other",
      images: [`https://i.ytimg.com/vi/${TOUR_VIDEO_ID}/maxresdefault.jpg`],
    },
  };
}

/// `/tour` — the film, its five chapters, and everything it says, with the same
/// contents as a PDF for anyone who would rather keep it than stream it.
///
/// Static on purpose: this is the page a club chairman opens on a phone signal
/// in a car park, so it asks nothing of the API.
export default async function TourPage() {
  const t = await getT();
  return (
    <main id="main" className="tour">
      <section className="tour-hero">
        <p className="lp-brand">
          <BrandMark size={36} />
          <span>{brand.name}</span>
        </p>
        <p className="lp-kicker">{t("tour.video_tour_duration", { duration: TOUR_DURATION })}</p>
        <h1>{t("rest.a_season_on_a_phone_from_sign_up_to_th")}</h1>
        <p className="lp-lead">
          {t("rest.one_run_through_the_app_as_a_club_actu")}
        </p>
        <div className="lp-actions">
          <a
            className="btn primary lp-btn"
            href="/fishers-video-tour-contents.pdf"
            download
          >
            <Icon name="download" size={18} /> {t("rest.contents_as_a_pdf")}
          </a>
          <a
            className="btn lp-btn"
            href={`https://youtu.be/${TOUR_VIDEO_ID}`}
            target="_blank"
            rel="noreferrer"
          >
            {t("rest.watch_on_youtube")}
          </a>
        </div>
        <p className="lp-fine">
          {t("tour.chapters_fine_print", { n: TOUR_CHAPTERS.length })}{" "}
          <Link href="/">{t("tour.back_to_brand", { brand: brand.name })}</Link>
        </p>
      </section>

      <TourFilm />

      <section className="tour-cta">
        <h2>{t("rest.run_your_own_club_on_it")}</h2>
        <p className="muted">
          {t("rest.everything_in_the_film_is_in_the_app_t")}
        </p>
        <div className="lp-actions">
          <Link className="btn primary lp-btn" href="/register?as=secretary">
            <Icon name="plus" size={18} /> {t("rest.start_your_club")}
          </Link>
          <Link className="btn lp-btn" href="/register?as=player">
            {t("le.i_play_for_a_club")}
          </Link>
        </div>
      </section>
    </main>
  );
}
