#!/usr/bin/env bash
# The narrated video tour: records the Simulator while FishersTourUITests drives the app, then
# cuts the recording into a captioned film with a chapter per part of the game.
#
#   ./scripts/start.sh --no-ios && ./scripts/seed-area.py     # the season it walks through
#   ./scripts/record-tour-video.sh                            # the whole tour
#   ./scripts/record-tour-video.sh -only-testing:FishersUITests/FishersTourUITests/test4TwentyOverMatch
#
# Against a ring instead of the local stack:
#   FISHERS_API_URL=https://int.fishers.cloud FISHERS_SEED_MANIFEST=.dev/seed-int.json \
#     ./scripts/record-tour-video.sh
#
# Output, all under .dev/tour (which git ignores):
#
#   fishers-tour.mp4            the film, 1920x1080
#   fishers-tour-contents.pdf   every chapter and caption against the second it lands on
#   chapters.txt                chapter timestamps, for a player that takes them
#   raw.mov                     the untouched Simulator recording
#   screenshots/                the same tour as stills
#
# The app is built before recording starts, so no compile output is filmed. Filming happens on a
# Simulator of this script's own: erasing somebody's everyday one would take every other app with
# it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${FISHERS_RECORDING_DEVICE:-Fishers Area Tour}"
MODEL="${FISHERS_RECORDING_MODEL:-iPhone 17 Pro}"
DERIVED="${FISHERS_DERIVED_DATA:-/tmp/fishers-dd}"
OUT_DIR="${OUT_DIR:-$ROOT/.dev/tour}"
TITLE="${TITLE:-Fishers}"
SUBTITLE="${SUBTITLE:-Club cricket: the season, the selection and the scorebook}"

api_port="$(sed -nE 's/^API_PORT=([0-9]+).*/\1/p' "$ROOT/.env" 2>/dev/null | tail -1)"
API_URL="${FISHERS_API_URL:-http://127.0.0.1:${api_port:-7312}}"
MANIFEST="${FISHERS_SEED_MANIFEST:-$ROOT/.dev/seed-area.json}"
curl -sf -m 10 "$API_URL/health/ready" >/dev/null || {
  echo "No API at $API_URL — ./scripts/start.sh --no-ios first." >&2
  exit 1
}
[ -f "$MANIFEST" ] || {
  echo "No seed manifest at $MANIFEST — API_BASE=$API_URL ./scripts/seed-area.py first." >&2
  exit 1
}

udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):
    for device in data[runtime]:
        if device['name'] == name:
            print(device['udid'])
            raise SystemExit
" "$DEVICE")
if [ -z "$udid" ]; then
  runtime=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
ios = [r for r in json.load(sys.stdin)['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']]
print(sorted(ios, key=lambda r: [int(x) for x in r['version'].split('.')])[-1]['identifier'])
")
  echo "==> making a Simulator for filming: $DEVICE ($MODEL)"
  udid=$(xcrun simctl create "$DEVICE" "$MODEL" "$runtime")
fi

echo "==> resetting $DEVICE ($udid)"
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
xcrun simctl erase "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$udid"
# A tidy status bar for the film. The clock stays real: the fixtures are relative to now.
xcrun simctl status_bar "$udid" override --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi --operatorName ""
trap 'xcrun simctl status_bar "$udid" clear 2>/dev/null || true' EXIT

mkdir -p "$OUT_DIR"
RESULT="$OUT_DIR/result.xcresult"; rm -rf "$RESULT"
RAW="$OUT_DIR/raw.mov"; rm -f "$RAW"
LOG="$OUT_DIR/test.log"

echo "==> building"
(cd "$ROOT/ios" && xcodegen generate >/dev/null)
xcodebuild -project "$ROOT/ios/Fishers.xcodeproj" -scheme FishersUI -destination "id=$udid" \
  -derivedDataPath "$DERIVED" build-for-testing >"$OUT_DIR/build.log" 2>&1 \
  || { tail -30 "$OUT_DIR/build.log"; echo "build failed — see $OUT_DIR/build.log" >&2; exit 1; }

echo "==> recording"
REC_LOG="$OUT_DIR/record.log"; : >"$REC_LOG"
xcrun simctl io "$udid" recordVideo --codec h264 --force "$RAW" >"$REC_LOG" 2>&1 &
REC=$!
trap 'kill -INT $REC 2>/dev/null || true; xcrun simctl status_bar "$udid" clear 2>/dev/null || true' EXIT
# The recorder takes a moment to open the file; note when it says it is running. Whatever lag is
# left is measured against the tour's own screenshots when the video is cut.
for _ in $(seq 100); do grep -q "Recording started" "$REC_LOG" && break; sleep 0.1; done
RECORD_START=$(python3 -c 'import time; print(f"{time.time():.3f}")')
echo "$RECORD_START" >"$OUT_DIR/record-start.txt"   # so the film can be re-cut without refilming
sleep 1

set +e
TEST_RUNNER_FISHERS_API_URL="$API_URL" \
TEST_RUNNER_FISHERS_SEED_MANIFEST="$MANIFEST" \
TEST_RUNNER_TOUR_VIDEO=1 \
xcodebuild -project "$ROOT/ios/Fishers.xcodeproj" -scheme FishersUI -destination "id=$udid" \
  -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 2700 \
  $(printf '%s\n' "$@" | grep -q -- '-only-testing' || echo -only-testing:FishersUITests/FishersTourUITests) \
  test-without-building "$@" 2>&1 | tee "$LOG" | grep -E "Test Case|error:|Executed|TOURMARK.*section"
STATUS=${PIPESTATUS[0]}
set -e

# Stop the recording and let it finish writing before anything reads the file.
kill -INT $REC 2>/dev/null || true
wait $REC 2>/dev/null || true
trap 'xcrun simctl status_bar "$udid" clear 2>/dev/null || true' EXIT

echo "==> cutting the film"
OUT_DIR="$OUT_DIR" TITLE="$TITLE" SUBTITLE="$SUBTITLE" "$ROOT/scripts/cut-tour-video.sh" "$OUT_DIR"

[ "$STATUS" -eq 0 ] || echo "note: the tour reported failures — see $LOG" >&2
exit $STATUS
