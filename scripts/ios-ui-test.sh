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

# xcodebuild's exit status, not grep's. This pipeline used to end in `|| true`,
# which handed the script grep's status and made every run look like a pass —
# a failing build and a suite that never ran read the same as a green one.
# grep matching nothing is not an error; xcodebuild failing is.
log="$(mktemp -t fishers-ui)"
trap 'rm -f "$log"' EXIT

set +e
xcodebuild test \
  -scheme FishersUI \
  -destination "id=$udid" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULTS" \
  2>&1 | tee "$log" | grep -E "Test Case|Executed .* test|Testing failed|error:"
status=${PIPESTATUS[0]}
set -e

# A run where every test skipped proves nothing, and xcodebuild still exits 0:
# the tours skip themselves when the API is unreachable or verification is off,
# so a misconfigured stack is indistinguishable from a healthy one by exit code
# alone. Say it plainly and fail, rather than bank a pass nothing earned.
summary="$(grep -E "Executed [0-9]+ tests?," "$log" | tail -1 || true)"
if [ -n "$summary" ]; then
  total="$(sed -E 's/.*Executed ([0-9]+) tests?,.*/\1/' <<<"$summary")"
  skipped="$(sed -nE 's/.*with ([0-9]+) tests? skipped.*/\1/p' <<<"$summary")"
  skipped="${skipped:-0}"
  if [ "$total" -gt 0 ] && [ "$skipped" -eq "$total" ]; then
    echo
    echo "x all $total tests skipped — nothing was tested." >&2
    echo "  The tours skip when they cannot reach the API or verification is off:" >&2
    echo "    ./scripts/start.sh --status                 is the stack up, and on which port" >&2
    echo "    TEST_RUNNER_FISHERS_API_URL=http://127.0.0.1:<api-port>   reaches the test runner" >&2
    echo "      (a plain FISHERS_API_URL does not: it is read on the Simulator, not here)" >&2
    status=1
  fi
fi

echo
echo "screenshots: xcrun xcresulttool export attachments --path $RESULTS --output-path ./shots"

exit "$status"
