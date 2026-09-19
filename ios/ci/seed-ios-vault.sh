#!/usr/bin/env bash
# seed-ios-vault.sh — create/update kv/fishers/ios in WSLVault for TestFlight.
#
# Uses https://vault.workstation.co.uk only (same vault as ring deploys).
#
#   export VAULT_ADDR=https://vault.workstation.co.uk
#   export VAULT_TOKEN=...   # or VAULT_TOKEN_FILE=$HOME/.secrets/wslvault/token.json
#   export ASC_KEY_ID=...
#   export ASC_ISSUER_ID=...
#   export ASC_P8_PATH=$HOME/AuthKey_XXXXXX.p8
#   export APPLE_TEAM_ID=...
#   # optional: APP_STORE_APP_ID=...
#   # optional: GOOGLE_IOS_CLIENT_ID=... GOOGLE_REVERSED_CLIENT_ID=...
#   ./ios/ci/seed-ios-vault.sh
#
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.workstation.co.uk}"
VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-$HOME/.secrets/wslvault/token.json}"
VAULT_SECRET_PATH="${FISHERS_IOS_VAULT_PATH:-kv/fishers/ios}"

need() {
  local name=$1
  if [ -z "${!name:-}" ]; then
    echo "ERROR: set $name before running this script" >&2
    exit 1
  fi
}

need ASC_KEY_ID
need ASC_ISSUER_ID
need APPLE_TEAM_ID

if [ -n "${ASC_PRIVATE_KEY_B64:-}" ]; then
  :
elif [ -n "${ASC_P8_PATH:-}" ]; then
  [ -f "$ASC_P8_PATH" ] || { echo "ERROR: ASC_P8_PATH not found: $ASC_P8_PATH" >&2; exit 1; }
  ASC_PRIVATE_KEY_B64="$(base64 < "$ASC_P8_PATH" | tr -d '\n')"
else
  echo "ERROR: set ASC_PRIVATE_KEY_B64 or ASC_P8_PATH" >&2
  exit 1
fi

export ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_B64 APPLE_TEAM_ID
export APP_STORE_APP_ID="${APP_STORE_APP_ID:-}" CERT_PRIVATE_KEY_B64="${CERT_PRIVATE_KEY_B64:-}"
export GOOGLE_IOS_CLIENT_ID="${GOOGLE_IOS_CLIENT_ID:-}" GOOGLE_REVERSED_CLIENT_ID="${GOOGLE_REVERSED_CLIENT_ID:-}"
export VAULT_TOKEN_FILE VAULT_SECRET_PATH VAULT_ADDR VAULT_TOKEN="${VAULT_TOKEN:-}"

python3 - <<'PY'
import json, os, sys, urllib.request, urllib.error

FORBIDDEN_HOSTS = ("vault.diytaxreturn.co.uk",)

def kv_v2_api_path(path: str) -> str:
    path = path.strip().strip("/")
    if "/data/" in path:
        return path
    mount, _, rest = path.partition("/")
    return f"{mount}/data/{rest}" if rest else f"{mount}/data"

def resolve_auth():
    addr = (os.environ.get("VAULT_ADDR") or "").rstrip("/")
    token = os.environ.get("VAULT_TOKEN") or ""
    path = os.environ.get("VAULT_TOKEN_FILE") or ""
    if (not addr or not token) and path and os.path.isfile(path):
        with open(path) as fh:
            data = json.load(fh)
        def pick(keys):
            for key in keys:
                if data.get(key):
                    return data[key]
            return ""
        addr = addr or pick(("VAULT_ADDR", "VAULT_URI", "vault_addr", "addr", "url"))
        token = token or pick(("VAULT_TOKEN", "vault_token", "token", "client_token"))
        if not token and isinstance(data.get("auth"), dict):
            token = data["auth"].get("client_token") or ""
    if not addr or not token:
        sys.exit(
            "ERROR: Vault auth unavailable — set VAULT_TOKEN "
            "(or VAULT_TOKEN_FILE for WSLVault) and VAULT_ADDR=https://vault.workstation.co.uk"
        )
    addr = addr.rstrip("/")
    for host in FORBIDDEN_HOSTS:
        if host in addr:
            sys.exit(
                "ERROR: refusing Vault host %s — use https://vault.workstation.co.uk only."
                % host
            )
    return addr, token

addr, token = resolve_auth()
logical = os.environ.get("VAULT_SECRET_PATH", "kv/fishers/ios")
url = addr + "/v1/" + kv_v2_api_path(logical)

# Merge with any existing secret so re-seeding ASC fields does not wipe Google ids.
existing = {}
req_get = urllib.request.Request(url, method="GET")
req_get.add_header("X-Vault-Token", token)
try:
    with urllib.request.urlopen(req_get, timeout=30) as resp:
        raw = resp.read()
    try:
        payload_get = json.loads(raw)
        vault_data = (payload_get.get("data") or {}).get("data")
        if isinstance(vault_data, dict):
            existing = dict(vault_data)
    except ValueError:
        pass
except urllib.error.HTTPError as exc:
    if exc.code != 404:
        detail = exc.read().decode("utf-8", "replace")[:500]
        sys.exit("ERROR: Vault GET %s -> HTTP %s: %s" % (url, exc.code, detail))
except urllib.error.URLError as exc:
    sys.exit("ERROR: Vault GET %s -> %s" % (url, exc))

data = dict(existing)
data.update({
    "ASC_KEY_ID": os.environ["ASC_KEY_ID"],
    "ASC_ISSUER_ID": os.environ["ASC_ISSUER_ID"],
    "ASC_PRIVATE_KEY_B64": os.environ["ASC_PRIVATE_KEY_B64"],
    "APPLE_TEAM_ID": os.environ["APPLE_TEAM_ID"],
})
if os.environ.get("APP_STORE_APP_ID"):
    data["APP_STORE_APP_ID"] = os.environ["APP_STORE_APP_ID"]
if os.environ.get("CERT_PRIVATE_KEY_B64"):
    data["CERT_PRIVATE_KEY_B64"] = os.environ["CERT_PRIVATE_KEY_B64"]
if os.environ.get("GOOGLE_IOS_CLIENT_ID"):
    data["GOOGLE_IOS_CLIENT_ID"] = os.environ["GOOGLE_IOS_CLIENT_ID"]
if os.environ.get("GOOGLE_REVERSED_CLIENT_ID"):
    data["GOOGLE_REVERSED_CLIENT_ID"] = os.environ["GOOGLE_REVERSED_CLIENT_ID"]

payload = {"data": data}
body = json.dumps(payload).encode()
req = urllib.request.Request(url, data=body, method="POST")
req.add_header("X-Vault-Token", token)
req.add_header("Content-Type", "application/json")
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", "replace")[:500]
    sys.exit("ERROR: Vault POST %s -> HTTP %s: %s" % (url, exc.code, detail))

print("OK: wrote %s on %s (ASC_KEY_ID=%s)" % (logical, addr, os.environ["ASC_KEY_ID"]))
print("Re-run the iOS Release workflow to upload to TestFlight.")
PY
