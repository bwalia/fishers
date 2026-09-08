#!/usr/bin/env bash
# Regenerate ios/Fishers.xcodeproj when the source tree has moved under it.
#
# The project is XcodeGen output and gitignored, so a pull that adds a Swift
# file leaves the file on disk but absent from the target — the compiler then
# reports "Cannot find 'Foo' in scope" for a type you can plainly see. This
# runs after checkout/merge/rebase and closes that gap.
#
# Regenerating rewrites the pbxproj, which makes an open Xcode reload the
# project — so only do it when something actually changed. A stamp of the
# source file list plus project.yml is the cheapest exact test: file contents
# do not affect project structure, only which files exist and how the spec
# lists them.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
IOS="$ROOT/ios"
SPEC="$IOS/project.yml"
PBXPROJ="$IOS/Fishers.xcodeproj/project.pbxproj"
STAMP="$IOS/.xcodegen-stamp"

# Not every checkout in this repo touches iOS, and not every clone has it.
[ -f "$SPEC" ] || exit 0

# The source paths XcodeGen globs, plus the spec that says how to glob them.
current_stamp() {
  {
    find "$IOS/Fishers" "$IOS/FishersTests" -type f 2>/dev/null | LC_ALL=C sort
    cat "$SPEC"
  } | shasum -a 256 | cut -d' ' -f1
}

now="$(current_stamp)"
if [ -f "$PBXPROJ" ] && [ -f "$STAMP" ] && [ "$now" = "$(cat "$STAMP")" ]; then
  exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  # A hook that fails a merge over a missing optional tool is worse than the
  # drift it is warning about.
  echo "fishers: ios sources changed but xcodegen is not installed." >&2
  echo "         brew install xcodegen, then: (cd ios && xcodegen generate)" >&2
  exit 0
fi

echo "fishers: ios sources changed — regenerating Fishers.xcodeproj"
if (cd "$IOS" && xcodegen generate --quiet); then
  # Stamp only on success, so a failed run is retried next time.
  current_stamp > "$STAMP"
else
  echo "fishers: xcodegen failed — run it by hand in ios/ to see why." >&2
fi
