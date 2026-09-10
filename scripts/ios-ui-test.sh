#!/usr/bin/env bash
# Run the iOS UI tour against a running local stack.
#
# The erase is not optional. XCTest's runner talks to the app over the
# accessibility server, and a Simulator that has been booted and rebooted a
# few times starts failing to bring it up:
#
#   The test runner failed to initialize for UI testing.
#   (Underlying Error: Timed out waiting for AX loaded notification)
#
# That is a stale Simulator, not a broken app — an erase clears it every time,
# and five minutes of a suite failing for that reason teaches people to ignore
# the suite. So the erase happens here, every run.
#
#   ./scripts/start.sh --no-ios     # the API these tests talk to
#   ./scripts/ios-ui-test.sh
set -euo pipefail

DEVICE="${FISHERS_SIM_DEVICE:-iPhone 17 Pro}"
DERIVED="${FISHERS_DERIVED_DATA:-/tmp/fishers-dd}"
RESULTS="${FISHERS_UI_RESULTS:-/tmp/fishers-ui.xcresult}"

cd "$(dirname "$0")/.."/ios

udid=$(xcrun simctl list devices available -j \
  | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):
    for device in data[runtime]:
        if device['name'] == name:
            print(device['udid'])
            raise SystemExit
raise SystemExit('no simulator called ' + name)
" "$DEVICE")

echo "==> resetting $DEVICE ($udid)"
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
killall Simulator >/dev/null 2>&1 || true
sleep 3
xcrun simctl erase "$udid"

echo "==> running the tour"
rm -rf "$RESULTS"
xcodebuild test \
  -scheme FishersUI \
  -destination "id=$udid" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULTS" \
  2>&1 | grep -E "Test Case|Executed .* test|Testing failed|error:" || true

echo
echo "screenshots: xcrun xcresulttool export attachments --path $RESULTS --output-path ./shots"
