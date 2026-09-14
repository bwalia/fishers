#!/usr/bin/env bash
# seed-ios-vault.sh — create/update secret/fishers/ios for TestFlight releases.
#
# Run on a machine that can reach Vault (typically the Mac Studio runner):
#
#   export VAULT_TOKEN_FILE=$HOME/.secrets/acc-vault/login-token.json
#   export ASC_KEY_ID=...
#   export ASC_ISSUER_ID=...
#   export ASC_P8_PATH=$HOME/AuthKey_XXXXXX.p8
#   export APPLE_TEAM_ID=...
#   # optional: APP_STORE_APP_ID=...
#   ./ios/ci/seed-ios-vault.sh
#
set -euo pipefail

VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-$HOME/.secrets/acc-vault/login-token.json}"
VAULT_SECRET_PATH="${FISHERS_IOS_VAULT_PATH:-secret/fishers/ios}"

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
export VAULT_TOKEN_FILE VAULT_SECRET_PATH VAULT_ADDR="${VAULT_ADDR:-}" VAULT_TOKEN="${VAULT_TOKEN:-}"

python3 - <<'PY'
import json, os, sys, urllib.request, urllib.error

def resolve_auth():
    addr = os.environ.get("VAULT_ADDR") or ""
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
        sys.exit("ERROR: Vault auth unavailable — set VAULT_ADDR/VAULT_TOKEN or VAULT_TOKEN_FILE")
    return addr.rstrip("/"), token

addr, token = resolve_auth()
secret_path = os.environ.get("VAULT_SECRET_PATH", "secret/fishers/ios")
api_path = secret_path if secret_path.startswith("secret/data/") else (
    "secret/data/" + secret_path.removeprefix("secret/")
)
url = addr + "/v1/" + api_path

payload = {
    "data": {
        "ASC_KEY_ID": os.environ["ASC_KEY_ID"],
        "ASC_ISSUER_ID": os.environ["ASC_ISSUER_ID"],
        "ASC_PRIVATE_KEY_B64": os.environ["ASC_PRIVATE_KEY_B64"],
        "APPLE_TEAM_ID": os.environ["APPLE_TEAM_ID"],
    }
}
if os.environ.get("APP_STORE_APP_ID"):
    payload["data"]["APP_STORE_APP_ID"] = os.environ["APP_STORE_APP_ID"]
if os.environ.get("CERT_PRIVATE_KEY_B64"):
    payload["data"]["CERT_PRIVATE_KEY_B64"] = os.environ["CERT_PRIVATE_KEY_B64"]

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

print("OK: wrote %s (ASC_KEY_ID=%s)" % (secret_path, os.environ["ASC_KEY_ID"]))
print("Re-run the iOS Release workflow to upload to TestFlight.")
PY
