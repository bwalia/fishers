#!/usr/bin/env bash
# Point this clone's hooks at the tracked scripts/git-hooks directory.
#
# Hooks live in .git/hooks, which git never transfers, so every clone has to opt
# in once. core.hooksPath is that opt-in: one config line, and the hooks stay
# under version control where they can be reviewed like any other code.
#
#   ./scripts/install-hooks.sh            install
#   ./scripts/install-hooks.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--uninstall" ]; then
  git config --unset core.hooksPath || true
  echo "Hooks uninstalled — this clone is back to .git/hooks."
  exit 0
fi

# Anything already in .git/hooks stops running once hooksPath is set, so say so
# rather than letting a hook someone relies on go quiet.
existing="$(find .git/hooks -maxdepth 1 -type f ! -name '*.sample' 2>/dev/null || true)"
if [ -n "$existing" ]; then
  echo "Note: core.hooksPath overrides .git/hooks; these stop running:" >&2
  echo "$existing" | sed 's/^/  /' >&2
fi

git config core.hooksPath scripts/git-hooks
echo "Installed. Hooks now run from scripts/git-hooks:"
for h in scripts/git-hooks/*; do
  case "$h" in */sync-xcodeproj.sh) continue ;; esac
  echo "  $(basename "$h")"
done
echo
echo "They keep ios/Fishers.xcodeproj in step with the source tree after a"
echo "pull, checkout or rebase. Needs xcodegen: brew install xcodegen"
