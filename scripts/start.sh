#!/usr/bin/env bash
# Start the whole local dev stack: Postgres, the Fishers API and the Next.js
# dashboard. Preferred ports are 7311 (web) / 7312 (API) / 7313 (Postgres) —
# clear of the usual 3000/8080/5432 crowd. Anything busy is stepped over, and
# API + web ports are *held* with real TCP binds until the real process takes
# over so Docker cannot steal them mid-boot.
#
#   ./scripts/start.sh          start everything (Ctrl-C stops API + web)
#   ./scripts/start.sh --stop   stop everything, Postgres included
#
# Override preferred ports on the command line (not via a stale .env):
#   WEB_PORT=4000 API_PORT=4001 POSTGRES_PORT=4002 ./scripts/start.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/dev-ports.sh"

API_CONTAINER=fishers-api-dev

if [ "${1:-}" = "--stop" ]; then
  release_all_held_ports
  stop_leftover_api
  docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true
  docker compose down 2>/dev/null || docker rm -f fishers-postgres >/dev/null 2>&1 || true
  rm -f "$FISHERS_PORTS_FILE"
  echo "Stopped API + Postgres. Data volume kept — 'docker compose down -v' to wipe it."
  echo "The dashboard runs in your terminal, not Docker — Ctrl-C it there."
  exit 0
fi

# A second run would 'docker rm -f' the first run's API out from under it.
if [ -n "$(docker ps -q -f name="^${API_CONTAINER}$" 2>/dev/null)" ]; then
  echo "The dev stack is already running ($API_CONTAINER)." >&2
  echo "Ctrl-C it in its own terminal, or './scripts/start.sh --stop'." >&2
  exit 1
fi

stop_leftover_api
release_all_held_ports

[ -f .env ] || { cp .env.example .env; echo "Created .env from .env.example"; }

# Capture caller overrides *before* sourcing .env — a stale POSTGRES_PORT /
# API_PORT in .env must not drive allocation (that is what made the API land
# on 7313 next to Postgres). Only an explicit shell export / command-line
# override counts: WEB_PORT=4000 ./scripts/start.sh
_HAD_PG=0; _HAD_API=0; _HAD_WEB=0
CALLER_POSTGRES_PORT=""; CALLER_API_PORT=""; CALLER_WEB_PORT=""
if [ -n "${POSTGRES_PORT+x}" ]; then _HAD_PG=1; CALLER_POSTGRES_PORT="$POSTGRES_PORT"; fi
if [ -n "${API_PORT+x}" ]; then _HAD_API=1; CALLER_API_PORT="$API_PORT"; fi
if [ -n "${WEB_PORT+x}" ]; then _HAD_WEB=1; CALLER_WEB_PORT="$WEB_PORT"; fi

set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

# Restore caller overrides; otherwise drop .env port values so we use defaults.
if [ "$_HAD_PG" -eq 1 ]; then POSTGRES_PORT="$CALLER_POSTGRES_PORT"
else unset POSTGRES_PORT 2>/dev/null || true; fi
if [ "$_HAD_API" -eq 1 ]; then API_PORT="$CALLER_API_PORT"
else unset API_PORT 2>/dev/null || true; fi
if [ "$_HAD_WEB" -eq 1 ]; then WEB_PORT="$CALLER_WEB_PORT"
else unset WEB_PORT 2>/dev/null || true; fi

PG_WANT="${POSTGRES_PORT:-$FISHERS_DEFAULT_POSTGRES_PORT}"
API_WANT="${API_PORT:-$FISHERS_DEFAULT_API_PORT}"
WEB_WANT="${WEB_PORT:-$FISHERS_DEFAULT_WEB_PORT}"

allocate_stack_ports
# Holds are live on API_PORT and WEB_PORT until we release them below.

LAN_IP="$(detect_lan_ip)"
WEB_BASE="http://${LAN_IP}:${WEB_PORT}"
API_BASE="http://${LAN_IP}:${API_PORT}"
write_ports_file "$LAN_IP"

echo "==> Ports (reserved)"
echo "    Postgres  ${POSTGRES_PORT}"
echo "    API       ${API_PORT}   (LAN ${API_BASE})  [held until API starts]"
echo "    Web       ${WEB_PORT}   (LAN ${WEB_BASE})  [held until web starts]"
if [ "$API_PORT" -ne "$FISHERS_DEFAULT_API_PORT" ] || [ "$WEB_PORT" -ne "$FISHERS_DEFAULT_WEB_PORT" ]; then
  echo "    note: not on the default 7311/7312 — update the iOS Debug URL if you use the phone app" >&2
fi

echo "==> Postgres"
export POSTGRES_PORT
docker compose up -d
until docker exec fishers-postgres pg_isready -U fishers -d fishers >/dev/null 2>&1; do sleep 1; done

# Confirm Docker did not somehow publish Postgres onto our reserved API port
# (should be impossible while the hold is alive; still sanity-check).
PG_NOW="$(running_pg_port)"
if [ -n "$PG_NOW" ] && [ "$PG_NOW" = "$API_PORT" ]; then
  echo "Postgres unexpectedly claimed API port ${API_PORT} — aborting." >&2
  release_all_held_ports
  exit 1
fi
if [ -n "$PG_NOW" ] && [ "$PG_NOW" != "$POSTGRES_PORT" ]; then
  POSTGRES_PORT="$PG_NOW"
  export POSTGRES_PORT
  write_ports_file "$LAN_IP"
  echo "    Postgres published on ${POSTGRES_PORT}"
fi

echo "==> API"
docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true

# Only pass DLS_RESOURCE_TABLE when it actually points at a file — an empty
# string makes the API try to open path "" and log a scary (harmless) error.
API_ENV=(
  "API_HOST=0.0.0.0"
  "API_PORT=${API_PORT}"
  "JWT_SECRET=${JWT_SECRET:-dev-secret-not-for-production-use-only}"
  "JWT_ACCESS_TTL_SECS=${JWT_ACCESS_TTL_SECS:-900}"
  "JWT_REFRESH_TTL_SECS=${JWT_REFRESH_TTL_SECS:-2592000}"
  "RUST_LOG=${RUST_LOG:-fishers_api=debug,tower_http=info,sqlx=warn}"
  "PUBLIC_WEB_BASE=${WEB_BASE}"
  "CORS_ALLOWED_ORIGINS=${WEB_BASE},http://127.0.0.1:${WEB_PORT},http://localhost:${WEB_PORT},http://[::1]:${WEB_PORT}"
  "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"
  "STRIPE_SECRET_KEY=${STRIPE_SECRET_KEY:-}"
  "STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET:-}"
  "DLS_G50=${DLS_G50:-245}"
  "OLLAMA_URL=${OLLAMA_URL:-}"
  "OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.1:8b}"
)
if [ -n "${DLS_RESOURCE_TABLE:-}" ]; then
  API_ENV+=("DLS_RESOURCE_TABLE=${DLS_RESOURCE_TABLE}")
fi

api_ready() {
  curl -sf -m 2 "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1 \
    || curl -sf -m 2 "http://localhost:${API_PORT}/health" >/dev/null 2>&1 \
    || curl -sf -m 2 "http://[::1]:${API_PORT}/health" >/dev/null 2>&1
}

# Drop the hold a moment before the real listener binds.
release_held_port api

if command -v cargo >/dev/null 2>&1; then
  export DATABASE_URL="postgres://fishers:fishers@127.0.0.1:${POSTGRES_PORT}/fishers"
  for kv in "${API_ENV[@]}"; do export "${kv?}"; done
  if [ -z "${DLS_RESOURCE_TABLE:-}" ]; then unset DLS_RESOURCE_TABLE; fi
  (cd backend && cargo run -p fishers-api) &
  API_PID=$!
else
  PG_NETWORK="$(docker inspect fishers-postgres \
    --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
  DOCKER_ENV=( -e "DATABASE_URL=postgres://fishers:fishers@postgres:5432/fishers" )
  for kv in "${API_ENV[@]}"; do DOCKER_ENV+=( -e "$kv" ); done
  echo "    no local cargo — building in Docker (first run takes a few minutes)"
  docker run -d --name "$API_CONTAINER" \
    --network "$PG_NETWORK" \
    -p "${API_PORT}:${API_PORT}" \
    -v "$ROOT/backend:/w" \
    -v fishers-cargo-registry:/usr/local/cargo/registry \
    -v fishers-cargo-target:/w/target \
    -w /w \
    "${DOCKER_ENV[@]}" \
    rust:slim cargo run -p fishers-api >/dev/null
  API_PID=""
fi

cleanup() {
  echo
  echo "Stopping…"
  [ -n "${API_PID:-}" ] && kill "$API_PID" 2>/dev/null || true
  docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true
  release_all_held_ports
  echo "Postgres left running — ./scripts/start.sh --stop to stop it too."
}
trap cleanup EXIT INT TERM

printf '    waiting for the API'
tries=0
until api_ready; do
  tries=$((tries + 1))
  if [ -n "${API_PID:-}" ] && ! kill -0 "$API_PID" 2>/dev/null; then
    echo; echo "API exited — see the output above." >&2; exit 1
  fi
  if [ -z "${API_PID:-}" ] && [ -z "$(docker ps -q -f name="$API_CONTAINER")" ]; then
    echo; echo "API container exited:" >&2
    docker logs "$API_CONTAINER" 2>&1 | tail -20 >&2; exit 1
  fi
  if [ "$tries" -ge 90 ]; then
    echo
    echo "API did not become healthy on port ${API_PORT} within three minutes." >&2
    echo "What is listening there:" >&2
    lsof -nP -iTCP:"${API_PORT}" -sTCP:LISTEN 2>/dev/null >&2 || true
    exit 1
  fi
  printf '.'; sleep 2
done
echo " ok"

echo "==> Web"
if [ -e web/.next/BUILD_ID ]; then
  echo "    clearing a production build out of .next so dev can use it"
  rm -rf web/.next
fi
[ -d web/node_modules ] || (cd web && npm install)
cat > web/.env.local <<EOF
# Generated by scripts/start.sh — re-run it after changing ports.
NEXT_PUBLIC_API_PORT=${API_PORT}
EOF
write_ports_file "$LAN_IP"

cat <<EOF

  Dashboard   http://127.0.0.1:${WEB_PORT}       (LAN: ${WEB_BASE})
  API         http://127.0.0.1:${API_PORT}       (LAN: ${API_BASE})
  Swagger     http://127.0.0.1:${API_PORT}/swagger-ui
  Postgres    postgres://fishers:fishers@127.0.0.1:${POSTGRES_PORT}/fishers

  Ports also written to .dev/ports.env (for seed/smoke scripts).
  Score a match at http://127.0.0.1:${WEB_PORT}/score — then Share full scoreboard.
  Point the iOS app at ${API_BASE}.

  Ctrl-C stops the API and web. Postgres keeps running.

EOF

release_held_port web
# Not exec'd: the shell has to survive to run the cleanup trap on Ctrl-C.
(cd web && npx next dev --hostname 0.0.0.0 -p "${WEB_PORT}")
