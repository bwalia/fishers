#!/usr/bin/env python3
"""Turns the cut film's index into the data behind the web page at /tour.

`scripts/tour-video.swift` writes `index.json` — every chapter and every caption
against the second it lands on in the finished film. The page shows the same
thing the contents PDF does, so it reads from the same arithmetic rather than a
second copy of it that can drift.

    ./scripts/cut-tour-video.sh                  # writes .dev/tour/index.json
    ./scripts/tour-page-data.py                  # …and this rewrites the page's data

    ./scripts/tour-page-data.py path/to/index.json --video AzYtyFYpedM
"""
import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_INDEX = ROOT / ".dev" / "tour" / "index.json"
OUT = ROOT / "web" / "src" / "app" / "tour" / "chapters.ts"


def stamp(seconds: float) -> str:
    """Round once, then split: 15:59.5 is 16:00, not 15:00."""
    whole = round(seconds)
    return f"{whole // 60}:{whole % 60:02d}"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("index", nargs="?", default=str(DEFAULT_INDEX),
                        help="the film's index.json (default .dev/tour/index.json)")
    parser.add_argument("--video", default="AzYtyFYpedM", metavar="ID",
                        help="the YouTube id the page embeds")
    parser.add_argument("--out", default=str(OUT), metavar="PATH")
    args = parser.parse_args()

    index = json.loads(pathlib.Path(args.index).read_text())
    lines = [
        "// Generated from the film's own index by scripts/tour-page-data.py, so every timestamp",
        "// here is the video's arithmetic rather than a second copy of it that can drift.",
        "//",
        "//   ./scripts/cut-tour-video.sh && ./scripts/tour-page-data.py",
        "",
        "export type TourBeat = { at: number; stamp: string; text: string };",
        "export type TourChapter = {",
        "  number: number;",
        "  title: string;",
        "  subtitle: string;",
        "  at: number;",
        "  stamp: string;",
        "  beats: TourBeat[];",
        "};",
        "",
        f'export const TOUR_VIDEO_ID = "{args.video}";',
        f'export const TOUR_DURATION = "{stamp(index["duration"])}";',
        f"export const TOUR_FOOTER = {json.dumps(index['footer'])};",
        "",
        "export const TOUR_CHAPTERS: TourChapter[] = [",
    ]
    for chapter in index["chapters"]:
        lines += [
            "  {",
            f'    number: {chapter["number"]},',
            f'    title: {json.dumps(chapter["title"])},',
            f'    subtitle: {json.dumps(chapter["subtitle"])},',
            f'    at: {round(chapter["cardAt"])},',
            f'    stamp: "{stamp(chapter["cardAt"])}",',
            "    beats: [",
        ]
        for beat in chapter["beats"]:
            lines.append(f'      {{ at: {round(beat["at"])}, stamp: "{stamp(beat["at"])}", '
                         f"text: {json.dumps(beat['text'])} }},")
        lines += ["    ],", "  },"]
    lines.append("];")

    pathlib.Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(args.out).write_text("\n".join(lines) + "\n")
    beats = sum(len(c["beats"]) for c in index["chapters"])
    print(f"{args.out}: {len(index['chapters'])} chapters, {beats} captions, {stamp(index['duration'])}")


if __name__ == "__main__":
    main()
