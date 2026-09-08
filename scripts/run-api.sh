#!/usr/bin/env bash
# Start Postgres + Fishers API for Simulator/local client use.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/dev-ports.sh"

# Prefer ports last written by ./scripts/start.sh when present.
if load_ports_file; then
  echo "Using ports from .dev/ports.env (API :${API_PORT}, Postgres :${POSTGRES_PORT})"
fi

export POSTGRES_PORT="${POSTGRES_PORT:-$FISHERS_DEFAULT_POSTGRES_PORT}"
docker compose up -d
until docker exec fishers-postgres pg_isready -U fishers -d fishers >/dev/null 2>&1; do sleep 1; done

# If compose remapped Postgres, trust the published host port.
PG_NOW="$(running_pg_port)"
if [ -n "$PG_NOW" ]; then
  POSTGRES_PORT="$PG_NOW"
fi

cd "$ROOT/backend"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/backend/target}"
export DATABASE_URL="postgres://fishers:fishers@127.0.0.1:${POSTGRES_PORT}/fishers"
export API_HOST="${API_HOST:-0.0.0.0}"
export API_PORT="${API_PORT:-$FISHERS_DEFAULT_API_PORT}"
if [ -z "${DLS_RESOURCE_TABLE:-}" ]; then unset DLS_RESOURCE_TABLE; fi

echo "Building fishers-api…"
cargo build -p fishers-api
BIN="$CARGO_TARGET_DIR/debug/fishers-api"

if port_busy "$API_PORT"; then
  echo "Something already listens on :$API_PORT — leaving it alone."
  curl -sf "http://127.0.0.1:${API_PORT}/health" && echo && exit 0
  echo "Port busy but /health failed; stop the other process and retry." >&2
  exit 1
fi

echo "Fishers API → http://127.0.0.1:${API_PORT}  (Simulator uses this)"
exec "$BIN"
