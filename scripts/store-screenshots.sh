#!/usr/bin/env bash
# The App Store screenshots, on the sizes App Store Connect asks for.
#
#   ./scripts/start.sh --no-ios                    # the API
#   API_BASE=http://127.0.0.1:7312 ./scripts/seed-area.py
#   ./scripts/store-screenshots.sh
#
# Runs FishersUITests/StoreScreenshots on a 6.9" iPhone and a 13" iPad, each a
# Simulator of its own (made on first use, erased every run — the same reason
# scripts/record-area-tour.sh gives), and writes the PNGs to
# docs/screenshots/store/<brand>/<device>/, which git ignores.
#
# BRAND picks which app is photographed and defaults to fishers:
#
#   BRAND=gullycricket ./scripts/store-screenshots.sh
#
# It generates the brand before xcodegen, because this script used to shoot
# whatever happened to be generated already — so a run you believed was
# GullyCricket filed Fishers' screenshots under its name, which is the same
# way a TestFlight build once shipped entirely as the wrong brand.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${FISHERS_DERIVED_DATA:-/tmp/fishers-dd}"
BRAND="${BRAND:-fishers}"
OUT="${FISHERS_STORE_SCREENSHOTS:-$ROOT/docs/screenshots/store/$BRAND}"
RESULTS="${FISHERS_UI_RESULTS:-/tmp/fishers-store-screenshots}"

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

# name on disk | Simulator name | model
DEVICES=(
  "iphone-6.9|Fishers Store iPhone|iPhone 17 Pro Max"
  "ipad-13|Fishers Store iPad|iPad Pro 13-inch (M5)"
)

runtime=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
ios = [r for r in json.load(sys.stdin)['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']]
print(sorted(ios, key=lambda r: [int(x) for x in r['version'].split('.')])[-1]['identifier'])
")

echo "==> brand: $BRAND"
(cd "$ROOT" && node tools/brand/index.mjs generate "$BRAND" --ios >/dev/null)

# Read it back rather than trust the generate. The name in the xcconfig is what
# the screenshots will show in the tab bar and the status bar.
want="$(cd "$ROOT" && node tools/brand/index.mjs mobile "$BRAND" | sed -nE 's/^BRAND_NAME=(.*)$/\1/p')"
got="$(sed -nE 's/^PRODUCT_NAME *= *(.*)$/\1/p' "$ROOT/ios/Fishers/Brand/Generated/brand.xcconfig" | tail -1)"
if [ -n "$want" ] && [ "$want" != "$got" ]; then
  echo "Generated brand is '$got' but $BRAND is '$want' — refusing to shoot the wrong app." >&2
  exit 1
fi

(cd "$ROOT/ios" && xcodegen generate >/dev/null)

failed=0
for entry in "${DEVICES[@]}"; do
  IFS='|' read -r slug name model <<<"$entry"
  udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == sys.argv[1]:
            print(d['udid']); raise SystemExit
" "$name")
  if [ -z "$udid" ]; then
    echo "==> making a Simulator: $name ($model)"
    udid=$(xcrun simctl create "$name" "$model" "$runtime")
  fi

  echo "==> $name ($udid)"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl erase "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # Apple's own marketing status bar: 9:41, full signal, full battery.
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" \
    --batteryState charged --batteryLevel 100

  xcodebuild build-for-testing \
    -project "$ROOT/ios/Fishers.xcodeproj" -scheme FishersUI \
    -destination "id=$udid" -derivedDataPath "$DERIVED" -quiet

  result="$RESULTS-$slug.xcresult"
  rm -rf "$result"
  set +e
  TEST_RUNNER_FISHERS_API_URL="$API_URL" \
  TEST_RUNNER_FISHERS_SEED_MANIFEST="$MANIFEST" \
  xcodebuild test-without-building \
    -project "$ROOT/ios/Fishers.xcodeproj" -scheme FishersUI \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    -resultBundlePath "$result" \
    -only-testing:FishersUITests/StoreScreenshots/testStoreScreenshots 2>&1 \
    | grep -E "Test Case|error:|XCTAssert|Skipped|Executed"
  [ "${PIPESTATUS[0]}" -eq 0 ] || failed=1
  set -e

  dest="$OUT/$slug"
  rm -rf "$dest" "$dest.tmp"
  mkdir -p "$dest"
  xcrun xcresulttool export attachments --path "$result" --output-path "$dest.tmp" >/dev/null
  # The export names files by UUID; the manifest maps them back to the
  # names the test gave them.
  python3 - "$dest.tmp" "$dest" <<'PY'
import json, shutil, sys, pathlib
src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for test in json.loads((src / "manifest.json").read_text()):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", a["exportedFileName"])
        stem = name.split("_")[0] if name[:2].isdigit() else name
        shutil.copy(src / a["exportedFileName"], dest / f"{pathlib.Path(stem).stem}.png")
PY
  rm -rf "$dest.tmp"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  echo "   $(ls "$dest" | wc -l | tr -d ' ') screenshots in $dest"
done

exit "$failed"
