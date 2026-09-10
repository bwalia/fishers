#!/usr/bin/env bash
# Undo a dev stack that was started with sudo.
#
# Running ./scripts/start.sh under sudo leaves root-owned build output behind.
# The next non-root run then cannot write it, which makes sudo look like the
# only thing that works — and every sudo run deepens the hole. This stops the
# root processes, hands the repo back, and drops the build output so the next
# ordinary `./scripts/start.sh` starts clean.
#
#   sudo bash scripts/fix-root-ownership.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ME="${SUDO_USER:-$(id -un)}"
GROUP="$(id -gn "$ME")"

[ "$(id -u)" -eq 0 ] || { echo "Run me with sudo: sudo bash scripts/fix-root-ownership.sh"; exit 1; }

echo "==> stopping the stack"
"$ROOT/scripts/start.sh" --stop >/dev/null 2>&1 || true
pkill -f "next dev"    2>/dev/null || true
pkill -f "next-server" 2>/dev/null || true
sleep 1

echo "==> handing $ROOT back to $ME:$GROUP"
chown -R "$ME:$GROUP" "$ROOT"

echo "==> removing build output (all of it regenerates)"
rm -rf "$ROOT/web/.next" "$ROOT/web/.next-dev" "$ROOT"/web/.next-root-*
rm -rf "$ROOT/.dev/DerivedData"

left=$(find "$ROOT" -user root 2>/dev/null | wc -l | tr -d ' ')
echo "==> root-owned files left: $left"
[ "$left" = "0" ] && echo "==> clean. Now start it WITHOUT sudo:  ./scripts/start.sh"
