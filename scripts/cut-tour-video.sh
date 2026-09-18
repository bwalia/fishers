#!/usr/bin/env bash
# Cuts and captions a recording made by scripts/record-tour-video.sh. Split out so the film can be
# re-cut — different captions, a different title — without filming the tour again, which takes
# twenty minutes and plays a match that can only be played once.
#
#   ./scripts/cut-tour-video.sh [out-dir]          # default .dev/tour
#
# Expects, in that directory: raw.mov, result.xcresult and record-start.txt (the epoch seconds the
# recorder started at, or the recording's own creation time as a fallback).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-${OUT_DIR:-$ROOT/.dev/tour}}"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
TITLE="${TITLE:-Fishers}"
SUBTITLE="${SUBTITLE:-Club cricket: the season, the selection and the scorebook}"
RAW="$OUT_DIR/raw.mov"
RESULT="$OUT_DIR/result.xcresult"
[ -f "$RAW" ] || { echo "No $RAW" >&2; exit 1; }
[ -d "$RESULT" ] || { echo "No $RESULT" >&2; exit 1; }

if [ -f "$OUT_DIR/record-start.txt" ]; then
  RECORD_START=$(cat "$OUT_DIR/record-start.txt")
else
  # When the recorder did not note it, the file's own creation time is within a second of it, and
  # the captions are lined up against the tour's screenshots anyway.
  RECORD_START=$(stat -f %B "$RAW")
  echo "note: no record-start.txt; using the recording's creation time ($RECORD_START)" >&2
fi

SHOTS="$OUT_DIR/screenshots"
rm -rf "$SHOTS" "$OUT_DIR/attachments"
mkdir -p "$SHOTS" "$OUT_DIR/attachments"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT_DIR/attachments" >/dev/null

MARK="$ROOT/ios/Fishers/Resources/Assets.xcassets/FishersMark.imageset/fishers-mark.png"
python3 - "$OUT_DIR" "$SHOTS" "$RAW" "$RECORD_START" "$TITLE" "$SUBTITLE" "$MARK" <<'PY'
"""Turns the tour's markers and screenshots into a spec for scripts/tour-video.swift."""
import json, pathlib, shutil, sys

out, shots, raw, record_start, title, subtitle, mark = sys.argv[1:8]
out, shots = pathlib.Path(out), pathlib.Path(shots)
source = out / "attachments"

# Every screenshot the tour takes is named for the beat it belongs to; these are the chapters.
PREFIXES = ("onb-", "avail-", "sel-", "t20-", "ckt-")

markers, stills = [], {}
for test in json.loads((source / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName") or attachment["exportedFileName"]
        path = source / attachment["exportedFileName"]
        if name.startswith("tour-markers"):
            markers += json.loads(path.read_text())
        else:
            # Xcode appends "_<index>_<uuid>"; the snapshot's own name is what is wanted.
            stem = name.rsplit(".", 1)[0].split("_")[0]
            if stem.startswith(PREFIXES):
                shutil.copy(path, shots / f"{stem}.png")
                stills[stem] = str(shots / f"{stem}.png")
# A cut is marked by the stretch it covers rather than a moment, so it sorts on where it starts.
markers.sort(key=lambda marker: marker.get("at", marker.get("from", 0)))

sections, section = [], None
for marker in markers:
    kind = marker["kind"]
    if kind == "section":
        section = {"title": marker["title"], "subtitle": marker.get("subtitle"),
                   "start": marker["at"], "end": marker["at"], "beats": [], "cuts": []}
        sections.append(section)
    elif section is None:
        continue
    elif kind == "sectionEnd":
        section["end"] = marker["at"]
        section = None
    elif kind == "beat":
        section["beats"].append({"at": marker["at"], "text": marker["text"], "id": marker["id"]})
        section["end"] = marker["at"]
    elif kind == "cut":
        section["cuts"].append({"from": marker["from"], "to": marker["to"]})

sections = [s for s in sections if s["beats"]]
if not sections:
    sys.exit("no chapters were marked — did the tour skip for want of a seeded season?")

# Spread the alignment samples across the run, over beats whose screenshot came out.
candidates = [{"at": beat["at"], "image": stills[beat["id"]]}
              for section in sections for beat in section["beats"] if beat["id"] in stills]
step = max(1, len(candidates) // 8)
align = candidates[::step][:8]

spec = {
    "video": raw, "out": str(out / "fishers-tour.mp4"), "recordStart": float(record_start),
    "title": title, "subtitle": subtitle, "brandMark": mark,
    "footer": "Recorded on the iOS Simulator against a seeded demo season. "
              "Invented clubs and invented players, not a real club's records.",
    "chaptersFile": str(out / "chapters.txt"), "indexFile": str(out / "index.json"),
    "align": align, "sections": sections,
}
(out / "spec.json").write_text(json.dumps(spec, indent=2))
print(f"{len(sections)} chapters, {sum(len(s['beats']) for s in sections)} captions, "
      f"{len(stills)} screenshots")
PY

# -suppress-warnings: AVFoundation deprecated half of the composition API in macOS 26 and the
# replacement is not in every toolchain yet; errors still print.
swift -suppress-warnings "$ROOT/scripts/tour-video.swift" "$OUT_DIR/spec.json"

# The contents sheet that goes out with the film.
swift -suppress-warnings "$ROOT/scripts/tour-chapters-pdf.swift" "$OUT_DIR/index.json" \
  "$OUT_DIR/fishers-tour-contents.pdf"
echo
echo "Film:       $OUT_DIR/fishers-tour.mp4"
echo "Contents:   $OUT_DIR/fishers-tour-contents.pdf"
echo "Chapters:   $OUT_DIR/chapters.txt"
echo "Stills:     $SHOTS"
