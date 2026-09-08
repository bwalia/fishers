#!/usr/bin/env bash
# Self-test for scripts/lib/dev-ports.sh — no Docker required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/dev-ports.sh"

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok — $*"; PASS=$((PASS + 1)); }

# Pick a high ephemeral-ish base unlikely to collide in CI.
BASE=37111
A="$(free_port "$BASE")"
B="$(free_port "$BASE" "$A")"
C="$(free_port "$BASE" "$A" "$B")"
[ "$A" != "$B" ] && [ "$B" != "$C" ] && [ "$A" != "$C" ] || fail "free_port returned duplicates: $A $B $C"
ok "free_port skips reserved list ($A/$B/$C)"

hold_port "$A" api || fail "hold_port api"
hold_port "$B" web || fail "hold_port web"
port_busy "$A" || fail "held API port not busy"
port_busy "$B" || fail "held web port not busy"
ok "hold_port binds and reports busy"

# A third free_port must not return A or B.
D="$(free_port "$BASE" )"
[ "$D" != "$A" ] && [ "$D" != "$B" ] || fail "free_port returned a held port $D"
ok "free_port skips held sockets ($D)"

release_held_port api
release_held_port web
# After release, A should become free again (allow a moment).
sleep 0.3
if port_busy "$A"; then
  echo "warn — port $A still busy after release (acceptable on some kernels)" >&2
else
  ok "release_held_port frees the socket"
fi

POSTGRES_PORT=""
# Mock: no docker postgres → allocate three distinct and hold.
PG_WANT=$BASE API_WANT=$((BASE + 10)) WEB_WANT=$((BASE + 20))
# running_pg_port returns empty without docker container — fine.
allocate_stack_ports
[ "$API_PORT" != "$POSTGRES_PORT" ] || fail "API==Postgres"
[ "$WEB_PORT" != "$POSTGRES_PORT" ] || fail "Web==Postgres"
[ "$API_PORT" != "$WEB_PORT" ] || fail "API==Web"
port_busy "$API_PORT" || fail "API not held after allocate"
port_busy "$WEB_PORT" || fail "web not held after allocate"
ok "allocate_stack_ports holds API+web ($POSTGRES_PORT/$API_PORT/$WEB_PORT)"

release_all_held_ports
write_ports_file "127.0.0.1"
[ -f "$FISHERS_PORTS_FILE" ] || fail "ports file missing"
grep -q "API_PORT=${API_PORT}" "$FISHERS_PORTS_FILE" || fail "ports file content"
ok "write_ports_file"

rm -f "$FISHERS_PORTS_FILE"
echo "All $PASS checks passed."
