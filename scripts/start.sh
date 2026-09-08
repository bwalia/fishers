#!/usr/bin/env bash
# Start the whole local dev stack: Postgres, the Fishers API and the Next.js
# dashboard on 7311/7312/7313 — chosen to stay clear of the usual
# 3000/8080/5432 crowd. Anything occupied is stepped over automatically.
#
#   ./scripts/start.sh          start everything (Ctrl-C stops API + web)
#   ./scripts/start.sh --stop   stop everything, Postgres included
#
# Override any port up front: WEB_PORT=4000 ./scripts/start.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

API_CONTAINER=fishers-api-dev

if [ "${1:-}" = "--stop" ]; then
  docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true
  docker compose down
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

[ -f .env ] || { cp .env.example .env; echo "Created .env from .env.example"; }

set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

# First free TCP port at or above $1.
free_port() {
  local p=$1
  while lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; do p=$((p + 1)); done
  echo "$p"
}

# Reuse the running container's published port so we never recreate the DB just
# because its old port is now "busy" (it is busy because it is ours).
running_pg_port() {
  docker inspect fishers-postgres \
    --format '{{with index .NetworkSettings.Ports "5432/tcp"}}{{(index . 0).HostPort}}{{end}}' 2>/dev/null || true
}

# Keep the running container's port only when it is already the one we want:
# otherwise free_port would see our own Postgres as "busy" and walk past it.
# If the wanted port has changed, compose recreates the container on it and the
# named volume keeps the data.
PG_WANT="${POSTGRES_PORT:-7313}"
PG_RUNNING="$(running_pg_port)"
if [ -n "$PG_RUNNING" ] && [ "$PG_RUNNING" = "$PG_WANT" ]; then
  POSTGRES_PORT="$PG_WANT"
else
  POSTGRES_PORT="$(free_port "$PG_WANT")"
fi
API_PORT="$(free_port "${API_PORT:-7312}")"
WEB_PORT="$(free_port "${WEB_PORT:-7311}")"
export POSTGRES_PORT API_PORT WEB_PORT

# Share links and the iOS app need an address reachable from other devices.
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)"
WEB_BASE="http://${LAN_IP}:${WEB_PORT}"
API_BASE="http://${LAN_IP}:${API_PORT}"

echo "==> Postgres"
docker compose up -d
until docker exec fishers-postgres pg_isready -U fishers -d fishers >/dev/null 2>&1; do sleep 1; done

echo "==> API"
docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true

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
  "DLS_RESOURCE_TABLE=${DLS_RESOURCE_TABLE:-}"
  "DLS_G50=${DLS_G50:-245}"
  "OLLAMA_URL=${OLLAMA_URL:-}"
  "OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.1:8b}"
)

if command -v cargo >/dev/null 2>&1; then
  export DATABASE_URL="postgres://fishers:fishers@localhost:${POSTGRES_PORT}/fishers"
  for kv in "${API_ENV[@]}"; do export "${kv?}"; done
  (cd backend && cargo run -p fishers-api) &
  API_PID=$!
else
  # No local Rust toolchain — build and run in the same container image CI uses.
  # The cargo volumes keep rebuilds incremental across runs.
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
  echo "Postgres left running — ./scripts/start.sh --stop to stop it too."
}
trap cleanup EXIT INT TERM

printf '    waiting for the API'
until curl -sf -m 2 "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1; do
  if [ -n "${API_PID:-}" ] && ! kill -0 "$API_PID" 2>/dev/null; then
    echo; echo "API exited — see the output above." >&2; exit 1
  fi
  if [ -z "${API_PID:-}" ] && [ -z "$(docker ps -q -f name="$API_CONTAINER")" ]; then
    echo; echo "API container exited:" >&2
    docker logs "$API_CONTAINER" 2>&1 | tail -20 >&2; exit 1
  fi
  printf '.'; sleep 2
done
echo " ok"

echo "==> Web"
# `next build` and `next dev` share .next. A production build left in there makes
# dev serve stale server chunks and die with "Cannot find module './NNN.js'".
# Only a build writes BUILD_ID, so it is a safe thing to test for.
if [ -e web/.next/BUILD_ID ]; then
  echo "    clearing a production build out of .next so dev can use it"
  rm -rf web/.next
fi
[ -d web/node_modules ] || (cd web && npm install)
# Only the port is pinned. The browser derives the host from the page it loaded,
# so the dashboard keeps working when DHCP changes this machine's address —
# which silently broke it before, because the LAN IP was baked in at build time.
cat > web/.env.local <<EOF
# Generated by scripts/start.sh — re-run it after changing ports.
NEXT_PUBLIC_API_PORT=${API_PORT}
EOF

cat <<EOF

  Dashboard   http://127.0.0.1:${WEB_PORT}       (LAN: ${WEB_BASE})
  API         http://127.0.0.1:${API_PORT}       (LAN: ${API_BASE})
  Swagger     http://127.0.0.1:${API_PORT}/swagger-ui
  Postgres    postgres://fishers:fishers@localhost:${POSTGRES_PORT}/fishers

  Score a match at http://127.0.0.1:${WEB_PORT}/score — the iOS app is the one
  that works offline. Point the app at ${API_BASE}.

  Ctrl-C stops the API and web. Postgres keeps running.

EOF

# Not exec'd: the shell has to survive to run the cleanup trap on Ctrl-C.
(cd web && npx next dev --hostname 0.0.0.0 -p "${WEB_PORT}")
