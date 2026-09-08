# Shared local-dev port helpers for Fishers.
# Sourced by scripts/start.sh (and optionally others). Not meant to be run alone.
#
# Defaults stay clear of 3000/8080/5432. Allocation is:
#   1. Prefer WEB=7311, API=7312, Postgres=7313
#   2. Never assign the same port twice
#   3. Hold API + web with real TCP binds until the real process takes over
#      so Docker / leftovers cannot steal them mid-boot
#   4. Persist the result in .dev/ports.env for smoke/seed scripts

: "${ROOT:?ROOT must be set before sourcing dev-ports.sh}"

FISHERS_DEV_DIR="${ROOT}/.dev"
FISHERS_PORTS_FILE="${FISHERS_DEV_DIR}/ports.env"
FISHERS_HOLD_DIR="${FISHERS_DEV_DIR}/holds"

FISHERS_DEFAULT_WEB_PORT=7311
FISHERS_DEFAULT_API_PORT=7312
FISHERS_DEFAULT_POSTGRES_PORT=7313

port_busy() {
  local p=$1
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    return 1
  fi
  ss -ltn 2>/dev/null | grep -Eq ":${p}\\b" && return 0
  return 1
}

# First free TCP port at or above $1, skipping any ports listed after it.
free_port() {
  local p=$1
  shift
  local skip=("$@")
  local guard=0
  while true; do
    guard=$((guard + 1))
    if [ "$guard" -gt 500 ]; then
      echo "no free TCP port near the requested range" >&2
      return 1
    fi
    local taken=0
    local s
    for s in "${skip[@]+"${skip[@]}"}"; do
      if [ -n "$s" ] && [ "$p" -eq "$s" ]; then taken=1; break; fi
    done
    if [ "$taken" -eq 0 ] && ! port_busy "$p"; then
      echo "$p"
      return 0
    fi
    p=$((p + 1))
  done
}

running_pg_port() {
  docker inspect fishers-postgres \
    --format '{{with index .NetworkSettings.Ports "5432/tcp"}}{{(index . 0).HostPort}}{{end}}' 2>/dev/null || true
}

# Bind 0.0.0.0:$1 and keep the socket until release_held_port. Writes a pid file
# under .dev/holds/$2.pid. Uses Python so macOS and Linux behave the same.
hold_port() {
  local port=$1
  local name=$2
  mkdir -p "$FISHERS_HOLD_DIR"
  local pidfile="${FISHERS_HOLD_DIR}/${name}.pid"
  if [ -f "$pidfile" ]; then
    local old
    old="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      kill "$old" 2>/dev/null || true
      sleep 0.2
    fi
    rm -f "$pidfile"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to reserve local ports" >&2
    return 1
  fi
  # SO_REUSEADDR off → exclusive bind for the hold window.
  python3 - "$port" "$pidfile" <<'PY' &
import os, socket, sys, time
port = int(sys.argv[1])
pidfile = sys.argv[2]
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind(("0.0.0.0", port))
except OSError as exc:
    sys.stderr.write(f"could not hold port {port}: {exc}\n")
    sys.exit(1)
sock.listen(1)
with open(pidfile, "w", encoding="utf-8") as fh:
    fh.write(str(os.getpid()))
    fh.flush()
    os.fsync(fh.fileno())
try:
    while True:
        time.sleep(3600)
finally:
    sock.close()
PY
  local holder=$!
  # Wait until the pid file exists (bind succeeded) or the holder exits.
  local i=0
  while [ ! -f "$pidfile" ]; do
    i=$((i + 1))
    if ! kill -0 "$holder" 2>/dev/null; then
      wait "$holder" 2>/dev/null || true
      echo "failed to reserve port ${port} (${name})" >&2
      return 1
    fi
    if [ "$i" -gt 50 ]; then
      kill "$holder" 2>/dev/null || true
      echo "timed out reserving port ${port} (${name})" >&2
      return 1
    fi
    sleep 0.05
  done
}

release_held_port() {
  local name=$1
  local pidfile="${FISHERS_HOLD_DIR}/${name}.pid"
  if [ -f "$pidfile" ]; then
    local old
    old="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "$old" ]; then
      kill "$old" 2>/dev/null || true
      # Brief pause so the kernel releases the listen socket.
      sleep 0.15
    fi
    rm -f "$pidfile"
  fi
}

release_all_held_ports() {
  release_held_port api
  release_held_port web
}

# Pick mutually exclusive Postgres / API / web ports and hold API + web.
# Sets: POSTGRES_PORT API_PORT WEB_PORT (exported).
# Caller overrides (env already set to a non-default before allocate) are honored
# as *preferred* starting points via PG_WANT / API_WANT / WEB_WANT if provided.
allocate_stack_ports() {
  local pg_want="${PG_WANT:-$FISHERS_DEFAULT_POSTGRES_PORT}"
  local api_want="${API_WANT:-$FISHERS_DEFAULT_API_PORT}"
  local web_want="${WEB_WANT:-$FISHERS_DEFAULT_WEB_PORT}"

  local pg_running
  pg_running="$(running_pg_port)"
  if [ -n "$pg_running" ]; then
    # Reuse the already-published host port — it looks "busy" because it is ours.
    POSTGRES_PORT="$pg_running"
  else
    POSTGRES_PORT="$(free_port "$pg_want")"
  fi

  if [ "$api_want" -eq "$POSTGRES_PORT" ]; then
    api_want="$FISHERS_DEFAULT_API_PORT"
    if [ "$api_want" -eq "$POSTGRES_PORT" ]; then
      api_want=$((POSTGRES_PORT + 1))
    fi
  fi
  if [ "$web_want" -eq "$POSTGRES_PORT" ] || [ "$web_want" -eq "$api_want" ]; then
    web_want="$FISHERS_DEFAULT_WEB_PORT"
    if [ "$web_want" -eq "$POSTGRES_PORT" ] || [ "$web_want" -eq "$api_want" ]; then
      web_want=$((POSTGRES_PORT + 2))
    fi
  fi

  # Hold failures retry the next free port so a race against another process
  # cannot leave us with a "chosen" port we do not own.
  local tries=0
  while true; do
    tries=$((tries + 1))
    if [ "$tries" -gt 20 ]; then
      echo "could not reserve distinct API/web ports" >&2
      return 1
    fi
    API_PORT="$(free_port "$api_want" "$POSTGRES_PORT")"
    WEB_PORT="$(free_port "$web_want" "$POSTGRES_PORT" "$API_PORT")"
    if hold_port "$API_PORT" api && hold_port "$WEB_PORT" web; then
      break
    fi
    release_all_held_ports
    api_want=$((API_PORT + 1))
    web_want=$((WEB_PORT + 1))
  done

  export POSTGRES_PORT API_PORT WEB_PORT
}

write_ports_file() {
  local lan_ip=$1
  mkdir -p "$FISHERS_DEV_DIR"
  cat > "$FISHERS_PORTS_FILE" <<EOF
# Generated by scripts/start.sh — do not commit. Re-run start.sh to refresh.
POSTGRES_PORT=${POSTGRES_PORT}
API_PORT=${API_PORT}
WEB_PORT=${WEB_PORT}
DATABASE_URL=postgres://fishers:fishers@127.0.0.1:${POSTGRES_PORT}/fishers
API_BASE=http://${lan_ip}:${API_PORT}
WEB_BASE=http://${lan_ip}:${WEB_PORT}
LAN_IP=${lan_ip}
EOF
}

# Load previously written ports if present (for seed/smoke helpers).
load_ports_file() {
  if [ -f "$FISHERS_PORTS_FILE" ]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$FISHERS_PORTS_FILE"
    set +a
    return 0
  fi
  return 1
}

detect_lan_ip() {
  local ip
  ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  if [ -z "${ip:-}" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  echo "${ip:-127.0.0.1}"
}

stop_leftover_api() {
  if pgrep -f 'target/debug/fishers-api' >/dev/null 2>&1; then
    echo "Stopping a leftover fishers-api process…"
    pkill -f 'target/debug/fishers-api' 2>/dev/null || true
    sleep 1
  fi
}
