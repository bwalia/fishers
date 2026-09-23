"use client";

import { useCallback, useState } from "react";
import { Icon } from "@/components/Icon";
import {
  TOUR_CHAPTERS,
  TOUR_DURATION,
  TOUR_FOOTER,
  TOUR_VIDEO_ID,
  type TourChapter,
} from "@/app/tour/chapters";

/// The film, its chapters, and everything it says.
///
/// Picking a chapter or a line moves the player to that second rather than
/// opening YouTube in a new tab: somebody looking for "how does selection work"
/// should be watching it two taps later, still on this page.
export function TourFilm() {
  const [start, setStart] = useState<number | null>(null);
  const [playing, setPlaying] = useState(false);

  const play = useCallback((seconds: number) => {
    setStart(seconds);
    setPlaying(true);
    document.getElementById("tour-player")?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, []);

  // youtube-nocookie, and no cookies at all until it is played.
  const source =
    `https://www.youtube-nocookie.com/embed/${TOUR_VIDEO_ID}` +
    `?rel=0&modestbranding=1&start=${start ?? 0}${playing ? "&autoplay=1" : ""}`;

  return (
    <>
      <div className="tour-player" id="tour-player">
        {playing ? (
          <iframe
            src={source}
            title="Fishers — the video tour"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; picture-in-picture"
            allowFullScreen
          />
        ) : (
          <button className="tour-poster" type="button" onClick={() => play(0)}>
            {/* YouTube's own thumbnail, behind a click-to-play poster.
                next/image would mean listing i.ytimg.com in remotePatterns and
                proxying someone else's static JPEG through our server to
                optimise it. */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={`https://i.ytimg.com/vi/${TOUR_VIDEO_ID}/maxresdefault.jpg`}
              alt=""
              loading="lazy"
            />
            <span className="tour-play" aria-hidden="true">
              <Icon name="play" size={28} />
            </span>
            <span className="tour-poster-label">
              Play the tour <span className="muted">· {TOUR_DURATION}</span>
            </span>
          </button>
        )}
      </div>

      <ol className="tour-chapters">
        {TOUR_CHAPTERS.map((chapter) => (
          <li key={chapter.number}>
            <button type="button" className="tour-chapter" onClick={() => play(chapter.at)}>
              <span className="tour-chapter-num" aria-hidden="true">
                {String(chapter.number).padStart(2, "0")}
              </span>
              <span className="tour-chapter-copy">
                <strong>{chapter.title}</strong>
                <span className="muted">{chapter.subtitle}</span>
              </span>
              <span className="tour-stamp">{chapter.stamp}</span>
            </button>
          </li>
        ))}
      </ol>

      <section className="tour-contents" aria-labelledby="tour-contents-heading">
        <h2 id="tour-contents-heading">What is on screen, line by line</h2>
        <p className="muted">
          Every screen in the film, at the second it appears. Tap a line to watch that
          bit.
        </p>
        {TOUR_CHAPTERS.map((chapter) => (
          <Chapter key={chapter.number} chapter={chapter} onPlay={play} />
        ))}
        <p className="tour-fine">{TOUR_FOOTER}</p>
      </section>
    </>
  );
}

function Chapter({
  chapter,
  onPlay,
}: {
  chapter: TourChapter;
  onPlay: (seconds: number) => void;
}) {
  return (
    <div className="tour-contents-chapter">
      <h3>
        <span className="tour-stamp">{chapter.stamp}</span>
        {chapter.number}. {chapter.title}
      </h3>
      <p className="muted tour-contents-sub">{chapter.subtitle}</p>
      <ul>
        {chapter.beats.map((beat) => (
          <li key={beat.at}>
            <button type="button" onClick={() => onPlay(beat.at)}>
              <span className="tour-stamp">{beat.stamp}</span>
              <span>{beat.text}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
