#!/usr/bin/env bash
# Film the area tours on a Simulator, one .mov per test:
#
#   testKeyFeaturesAsHemelsCaptain   Home, the live T20, shop, fixtures, calendar,
#                                    results, chat, club, stats, QR, profile
#   testFiveOverMatchBallByBall      Hemel Hempstead Town v Watford Town, scored
#                                    ball by ball through the app, then checked
#                                    against the server
#
#   ./scripts/start.sh --no-ios                    # the API
#   API_BASE=http://127.0.0.1:7312 ./scripts/seed-area.py
#   ./scripts/record-area-tour.sh                  # both
#   ./scripts/record-area-tour.sh testFiveOverMatchBallByBall
#
# Films go to docs/screenshots/recordings/, which git ignores. The match can
# only be played once: for another take, start from a clean database
# (./scripts/start.sh --reset) and seed again.
#
# It films on a Simulator of its own, made on first use and erased before
# every run (for the reason scripts/ios-ui-test.sh gives). Erasing somebody's
# everyday Simulator would take every other app they have installed on it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${FISHERS_RECORDING_DEVICE:-Fishers Area Tour}"
MODEL="${FISHERS_RECORDING_MODEL:-iPhone 17 Pro}"
DERIVED="${FISHERS_DERIVED_DATA:-/tmp/fishers-dd}"
OUT="${FISHERS_RECORDINGS:-$ROOT/docs/screenshots/recordings}"
RESULTS="${FISHERS_UI_RESULTS:-/tmp/fishers-area-tour}"

api_port="$(sed -nE 's/^API_PORT=([0-9]+).*/\1/p' "$ROOT/.env" 2>/dev/null | tail -1)"
API_URL="${FISHERS_API_URL:-http://127.0.0.1:${api_port:-7312}}"
curl -sf -m 5 "$API_URL/health/ready" >/dev/null || {
  echo "No API at $API_URL — ./scripts/start.sh --no-ios first." >&2
  exit 1
}
[ -f "$ROOT/.dev/seed-area.json" ] || {
  echo "No seed manifest — API_BASE=$API_URL ./scripts/seed-area.py first." >&2
  exit 1
}

if [ "$#" -gt 0 ]; then
  TESTS=("$@")
else
  TESTS=(testKeyFeaturesAsHemelsCaptain testFiveOverMatchBallByBall)
fi

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
# An evening kick-off, a full battery, no carrier clutter.
xcrun simctl status_bar "$udid" override --time "18:02" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState charged --batteryLevel 100

echo "==> building"
(cd "$ROOT/ios" && xcodegen generate >/dev/null)
xcodebuild build-for-testing \
  -project "$ROOT/ios/Fishers.xcodeproj" -scheme FishersUI \
  -destination "id=$udid" -derivedDataPath "$DERIVED" -quiet

mkdir -p "$OUT"
failed=0
for test in "${TESTS[@]}"; do
  film="$OUT/$(date +%Y%m%d-%H%M)-$test.mov"
  rm -rf "$RESULTS-$test.xcresult"
  echo "==> $test → $film"

  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$film" 2>/dev/null &
  recorder=$!
  sleep 3

  set +e
  TEST_RUNNER_FISHERS_API_URL="$API_URL" \
  TEST_RUNNER_FISHERS_SEED_MANIFEST="$ROOT/.dev/seed-area.json" \
  xcodebuild test-without-building \
    -project "$ROOT/ios/Fishers.xcodeproj" -scheme FishersUI \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    -resultBundlePath "$RESULTS-$test.xcresult" \
    -only-testing:"FishersUITests/AreaTour/$test" 2>&1 \
    | grep -E "Test Case|error:|XCTAssert|Skipped|Executed"
  status=${PIPESTATUS[0]}
  set -e

  sleep 2
  # SIGINT is how recordVideo is told to finish the file; anything harder
  # leaves a .mov with no index that nothing will play.
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true

  if [ "$status" -ne 0 ]; then
    failed=1
    echo "x $test failed — screenshots in $RESULTS-$test.xcresult" >&2
  fi
  echo "   $(du -h "$film" | cut -f1)  $film"
done

xcrun simctl status_bar "$udid" clear
exit "$failed"
