#!/usr/bin/env bash
#
# load-ios-vault-secrets.sh — resolve Fishers iOS signing material for fastlane.
#
# Order of preference:
#   1. Already-exported ASC_* / APPLE_TEAM_ID env vars (e.g. GitHub Actions secrets)
#   2. Vault KV v2 secret at secret/fishers/ios (override with FISHERS_IOS_VAULT_PATH)
#
# Always materialises ASC_PRIVATE_KEY_B64 into a file and exports ASC_KEY_FILEPATH.
#
#   CI:    ./ci/load-ios-vault-secrets.sh           # appends to $GITHUB_ENV
#   local: eval "$(./ci/load-ios-vault-secrets.sh)" # exports to shell
#
set -euo pipefail

VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-$HOME/.secrets/vault/token.json}"
VAULT_SECRET_PATH="${FISHERS_IOS_VAULT_PATH:-secret/fishers/ios}"
WORKDIR="${IOS_SECRETS_DIR:-${RUNNER_TEMP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.ios-secrets}}"
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR"
export VAULT_ADDR="${VAULT_ADDR:-}" VAULT_TOKEN="${VAULT_TOKEN:-}" VAULT_TOKEN_FILE WORKDIR VAULT_SECRET_PATH

python3 - <<'PY'
import base64, json, os, sys, urllib.request, urllib.error

REQUIRED = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_B64", "APPLE_TEAM_ID")

def emit(env_lines):
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a") as fh:
            for key, value in env_lines:
                fh.write("%s=%s\n" % (key, value))
    else:
        for key, value in env_lines:
            sys.stdout.write("export %s=%s\n" % (key, value))

def write_secret_file(name, b64_value):
    path = os.path.join(os.environ["WORKDIR"], name)
    raw = base64.b64decode(b64_value, validate=True)
    with open(path, "wb") as fh:
        fh.write(raw)
    os.chmod(path, 0o600)
    return path

def publish(data, source):
    missing = [k for k in REQUIRED if not data.get(k)]
    if missing:
        sys.exit("ERROR: %s is missing required key(s): %s" % (source, ", ".join(missing)))

    asc_key_path = write_secret_file("asc_api_key.p8", data["ASC_PRIVATE_KEY_B64"])
    env_lines = [
        ("ASC_KEY_ID", data["ASC_KEY_ID"]),
        ("ASC_ISSUER_ID", data["ASC_ISSUER_ID"]),
        ("ASC_KEY_FILEPATH", asc_key_path),
        ("APPLE_TEAM_ID", data["APPLE_TEAM_ID"]),
    ]
    if data.get("CERT_PRIVATE_KEY_B64"):
        env_lines.append((
            "DIST_CERT_KEY_FILEPATH",
            write_secret_file("dist_cert_key.pem", data["CERT_PRIVATE_KEY_B64"]),
        ))
    if data.get("APP_STORE_APP_ID"):
        env_lines.append(("APP_STORE_APP_ID", data["APP_STORE_APP_ID"]))

    emit(env_lines)
    sys.stderr.write("OK: loaded iOS signing material from %s into %s\n"
                     % (source, os.environ["WORKDIR"]))

# 1) Prefer env already provided by the workflow (GitHub Actions secrets).
from_env = {k: os.environ.get(k, "").strip() for k in REQUIRED}
if all(from_env.values()):
    data = dict(from_env)
    for optional in ("CERT_PRIVATE_KEY_B64", "APP_STORE_APP_ID"):
        if os.environ.get(optional):
            data[optional] = os.environ[optional]
    publish(data, "environment")
    raise SystemExit(0)

# 2) Fall back to Vault.
def resolve_auth():
    addr = os.environ.get("VAULT_ADDR") or ""
    token = os.environ.get("VAULT_TOKEN") or ""
    path = os.environ.get("VAULT_TOKEN_FILE") or ""
    if (not addr or not token) and path and os.path.isfile(path):
        with open(path) as fh:
            payload = json.load(fh)
        if not isinstance(payload, dict):
            sys.exit("ERROR: %s is not a JSON object" % path)

        def pick(keys):
            for key in keys:
                if payload.get(key):
                    return payload[key]
            return ""

        addr = addr or pick(("VAULT_ADDR", "VAULT_URI", "vault_addr", "addr", "url"))
        token = token or pick(("VAULT_TOKEN", "vault_token", "token", "client_token"))
        if not token and isinstance(payload.get("auth"), dict):
            token = payload["auth"].get("client_token") or ""
    if not addr or not token:
        sys.exit(
            "ERROR: signing secrets unavailable.\n"
            "  • Set GitHub Actions secrets ASC_KEY_ID, ASC_ISSUER_ID,\n"
            "    ASC_PRIVATE_KEY_B64, APPLE_TEAM_ID — or\n"
            "  • Seed Vault at secret/fishers/ios (see ios/ci/seed-ios-vault.sh)\n"
            "  • and ensure VAULT_ADDR/VAULT_TOKEN or %s is readable"
            % (path or "$VAULT_TOKEN_FILE")
        )
    return addr.rstrip("/"), token

addr, token = resolve_auth()
secret_path = os.environ.get("VAULT_SECRET_PATH", "secret/fishers/ios")
if not secret_path.startswith("secret/data/"):
    secret_path = "secret/data/" + secret_path.removeprefix("secret/")
url = addr + "/v1/" + secret_path

req = urllib.request.Request(url, method="GET")
req.add_header("X-Vault-Token", token)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", "replace")[:500]
    if exc.code == 404:
        sys.exit(
            "ERROR: Vault secret missing at %s (HTTP 404).\n"
            "Create it on the Mac Studio with:\n"
            "  cd ios && ./ci/seed-ios-vault.sh\n"
            "Or add GitHub Actions secrets ASC_KEY_ID, ASC_ISSUER_ID,\n"
            "ASC_PRIVATE_KEY_B64, APPLE_TEAM_ID and re-run iOS Release."
            % url
        )
    sys.exit("ERROR: Vault GET %s -> HTTP %s: %s" % (url, exc.code, detail))
except urllib.error.URLError as exc:
    sys.exit("ERROR: Vault GET %s -> %s" % (url, exc))

try:
    payload = json.loads(raw)
except ValueError:
    sys.exit("ERROR: Vault response from %s is not JSON" % url)

data = (payload.get("data") or {}).get("data")
if not isinstance(data, dict):
    sys.exit("ERROR: unexpected Vault response at %s (no .data.data map)" % url)

publish(data, secret_path)
PY
