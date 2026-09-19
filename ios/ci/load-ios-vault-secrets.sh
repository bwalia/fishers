#!/usr/bin/env bash
#
# load-ios-vault-secrets.sh — resolve Fishers iOS signing material for fastlane.
#
# Order of preference:
#   1. Already-exported ASC_* / APPLE_TEAM_ID env vars (e.g. GitHub Actions secrets)
#   2. WSLVault KV v2 at kv/fishers/ios (https://vault.workstation.co.uk)
#
# Private key (.p8) resolution (first hit wins):
#   a. ASC_P8_PATH (explicit file on the runner, e.g. $HOME/AuthKey_6KVVV27G4Q.p8)
#   b. $HOME/AuthKey_${ASC_KEY_ID}.p8
#   c. the only $HOME/AuthKey_*.p8 if exactly one exists
#   d. ASC_PRIVATE_KEY_B64 / ASC_PRIVATE_KEY (GitHub secret or Vault)
#
# On the Mac Studio self-hosted runner, dropping Apple's downloaded
# AuthKey_<KEY_ID>.p8 in $HOME is enough — no need to re-base64 into GitHub
# when the file is already on disk.
#
#   CI:    ./ci/load-ios-vault-secrets.sh           # appends to $GITHUB_ENV
#   local: eval "$(./ci/load-ios-vault-secrets.sh)" # exports to shell
#
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.workstation.co.uk}"
VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-$HOME/.secrets/wslvault/token.json}"
VAULT_SECRET_PATH="${FISHERS_IOS_VAULT_PATH:-kv/fishers/ios}"
WORKDIR="${IOS_SECRETS_DIR:-${RUNNER_TEMP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.ios-secrets}}"
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR"
export VAULT_ADDR VAULT_TOKEN="${VAULT_TOKEN:-}" VAULT_TOKEN_FILE WORKDIR VAULT_SECRET_PATH
export ASC_P8_PATH="${ASC_P8_PATH:-}" HOME

python3 - <<'PY'
import base64, glob, json, os, re, sys, urllib.request, urllib.error

REQUIRED_IDS = ("ASC_KEY_ID", "ASC_ISSUER_ID", "APPLE_TEAM_ID")
# Public OAuth client ids for Continue with Google — still kept out of git and
# injected into project.yml at xcodegen time from Vault / env.
OPTIONAL_GOOGLE = ("GOOGLE_IOS_CLIENT_ID", "GOOGLE_REVERSED_CLIENT_ID")
FORBIDDEN_HOSTS = ("vault.diytaxreturn.co.uk",)
KEY_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
ISSUER_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I
)
TEAM_RE = re.compile(r"^[A-Z0-9]{10}$")

def kv_v2_api_path(path: str) -> str:
    """kv/fishers/ios → kv/data/fishers/ios; leave …/data/… unchanged."""
    path = path.strip().strip("/")
    if "/data/" in path:
        return path
    mount, _, rest = path.partition("/")
    return f"{mount}/data/{rest}" if rest else f"{mount}/data"

def clean(value: str) -> str:
    """Strip whitespace and a single layer of wrapping quotes from secret UI pastes."""
    if value is None:
        return ""
    s = str(value).strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        s = s[1:-1].strip()
    return s

def emit(env_lines):
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a") as fh:
            for key, value in env_lines:
                fh.write("%s=%s\n" % (key, value))
    else:
        for key, value in env_lines:
            sys.stdout.write("export %s=%s\n" % (key, value))

def decode_p8(raw_value: str) -> bytes:
    """Accept base64(AuthKey.p8) or the PEM itself (common secret-UI mistake)."""
    text = clean(raw_value)
    if "BEGIN PRIVATE KEY" in text:
        return text.encode("utf-8")
    compact = re.sub(r"\s+", "", text)
    try:
        decoded = base64.b64decode(compact, validate=False)
    except Exception as exc:
        sys.exit("ERROR: ASC_PRIVATE_KEY_B64 is not valid base64: %s" % exc)
    if b"BEGIN PRIVATE KEY" in decoded:
        return decoded
    try:
        again = base64.b64decode(re.sub(rb"\s+", b"", decoded), validate=False)
        if b"BEGIN PRIVATE KEY" in again:
            return again
    except Exception:
        pass
    sys.exit(
        "ERROR: ASC_PRIVATE_KEY_B64 decoded but is not an AuthKey .p8 PEM "
        "(no BEGIN PRIVATE KEY). Prefer placing AuthKey_<KEY_ID>.p8 in $HOME "
        "on the Mac Studio runner, or re-encode:\n"
        "  base64 -i AuthKey_<KEY_ID>.p8 | tr -d '\\n'"
    )

def resolve_p8(key_id: str, data: dict):
    """Return (pem_bytes, source_label). Prefer runner-local AuthKey_*.p8."""
    candidates = []
    explicit = clean(os.environ.get("ASC_P8_PATH", "") or data.get("ASC_P8_PATH", ""))
    if explicit:
        candidates.append(explicit)
    home = os.path.expanduser("~")
    if key_id:
        candidates.append(os.path.join(home, "AuthKey_%s.p8" % key_id))
    matches = sorted(glob.glob(os.path.join(home, "AuthKey_*.p8")))
    if len(matches) == 1:
        candidates.append(matches[0])

    seen = set()
    for path in candidates:
        if not path or path in seen:
            continue
        seen.add(path)
        if not os.path.isfile(path):
            continue
        raw = open(path, "rb").read()
        # Reject empty / non-PEM files (e.g. a placeholder) and keep looking —
        # GitHub ASC_PRIVATE_KEY_B64 is the fallback so a bad $HOME copy does
        # not block releases that already have a valid secret.
        if b"BEGIN PRIVATE KEY" not in raw:
            sys.stderr.write(
                "WARN: %s exists but is not a PEM AuthKey (.p8) — ignoring\n" % path
            )
            continue
        base = os.path.basename(path)
        m = re.match(r"AuthKey_([A-Z0-9]{10})\.p8$", base)
        if m and key_id and m.group(1) != key_id:
            sys.stderr.write(
                "WARN: %s Key ID %s does not match ASC_KEY_ID=%s — ignoring\n"
                % (path, m.group(1), key_id)
            )
            continue
        return raw, "file:%s" % path

    if data.get("ASC_PRIVATE_KEY_B64") or data.get("ASC_PRIVATE_KEY"):
        pem = decode_p8(data.get("ASC_PRIVATE_KEY_B64") or data.get("ASC_PRIVATE_KEY"))
        return pem, "ASC_PRIVATE_KEY_B64"

    sys.exit(
        "ERROR: no App Store Connect .p8 found.\n"
        "  • On the Mac Studio: place a real AuthKey_%s.p8 PEM in $HOME, or\n"
        "  • Set GitHub secret ASC_PRIVATE_KEY_B64 (base64 of the .p8).\n"
        "  (If $HOME/AuthKey_*.p8 exists but is not PEM, replace it with the "
        "file Apple downloaded — it must start with -----BEGIN PRIVATE KEY-----.)"
        % (key_id or "<KEY_ID>")
    )

def write_secret_file(name, content: bytes):
    path = os.path.join(os.environ["WORKDIR"], name)
    with open(path, "wb") as fh:
        fh.write(content)
    os.chmod(path, 0o600)
    return path

def validate_shapes(data):
    key_id = data["ASC_KEY_ID"]
    issuer = data["ASC_ISSUER_ID"]
    team = data["APPLE_TEAM_ID"]
    if not KEY_ID_RE.match(key_id):
        hint = ""
        if ISSUER_RE.match(key_id):
            hint = " That value looks like ASC_ISSUER_ID."
        elif TEAM_RE.match(key_id) and key_id == team:
            hint = " That value looks like APPLE_TEAM_ID."
        sys.exit(
            "ERROR: ASC_KEY_ID=%r must be the 10-character Key ID from "
            "App Store Connect → Integrations → App Store Connect API.%s"
            % (key_id, hint)
        )
    if not ISSUER_RE.match(issuer):
        hint = ""
        if KEY_ID_RE.match(issuer):
            hint = " That value looks like a Key ID / Team ID, not Issuer ID."
        sys.exit(
            "ERROR: ASC_ISSUER_ID=%r must be the UUID Issuer ID at the top of "
            "the App Store Connect API keys page.%s" % (issuer, hint)
        )
    if not TEAM_RE.match(team):
        sys.exit(
            "ERROR: APPLE_TEAM_ID=%r must be the 10-character Apple Team ID "
            "(Membership details / Xcode Accounts)." % team
        )
    if key_id == team:
        sys.stderr.write(
            "WARN: ASC_KEY_ID and APPLE_TEAM_ID are identical — usually wrong. "
            "Key ID comes from the API key row; Team ID from Membership.\n"
        )

def publish(data, source):
    data = {k: clean(v) if isinstance(v, str) else v for k, v in data.items()}
    for k in REQUIRED_IDS:
        data[k] = clean(data.get(k, ""))

    missing = [k for k in REQUIRED_IDS if not data.get(k)]
    if missing:
        sys.exit("ERROR: %s is missing required key(s): %s" % (source, ", ".join(missing)))

    validate_shapes(data)
    pem, p8_source = resolve_p8(data["ASC_KEY_ID"], data)
    asc_key_path = write_secret_file("asc_api_key.p8", pem)
    env_lines = [
        ("ASC_KEY_ID", data["ASC_KEY_ID"]),
        ("ASC_ISSUER_ID", data["ASC_ISSUER_ID"]),
        ("ASC_KEY_FILEPATH", asc_key_path),
        ("APPLE_TEAM_ID", data["APPLE_TEAM_ID"]),
    ]
    if data.get("CERT_PRIVATE_KEY_B64"):
        cert_raw = clean(data["CERT_PRIVATE_KEY_B64"])
        if "BEGIN" in cert_raw:
            cert_bytes = cert_raw.encode()
        else:
            cert_bytes = base64.b64decode(re.sub(r"\s+", "", cert_raw), validate=False)
        env_lines.append((
            "DIST_CERT_KEY_FILEPATH",
            write_secret_file("dist_cert_key.pem", cert_bytes),
        ))
    if data.get("APP_STORE_APP_ID"):
        env_lines.append(("APP_STORE_APP_ID", clean(str(data["APP_STORE_APP_ID"]))))
    for key in OPTIONAL_GOOGLE:
        if data.get(key):
            env_lines.append((key, clean(str(data[key]))))

    emit(env_lines)
    sys.stderr.write(
        "OK: loaded iOS signing material from %s into %s "
        "(ASC_KEY_ID …%s, .p8 %d bytes via %s)\n"
        % (source, os.environ["WORKDIR"], data["ASC_KEY_ID"][-4:], len(pem), p8_source)
    )

def env_has_ids():
    return all(clean(os.environ.get(k, "")) for k in REQUIRED_IDS)

def resolve_auth(required=True):
    addr = (os.environ.get("VAULT_ADDR") or "").rstrip("/")
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
        if not required:
            return None, None
        sys.exit(
            "ERROR: signing secrets unavailable.\n"
            "  • Set GitHub Actions secrets ASC_KEY_ID, ASC_ISSUER_ID, APPLE_TEAM_ID\n"
            "    and place AuthKey_<KEY_ID>.p8 in $HOME on the Mac Studio — or\n"
            "  • Seed WSLVault at kv/fishers/ios (see ios/ci/seed-ios-vault.sh)\n"
            "  • VAULT_ADDR=%s and a readable token (%s)"
            % (os.environ.get("VAULT_ADDR") or "https://vault.workstation.co.uk",
               path or "$VAULT_TOKEN_FILE")
        )
    addr = addr.rstrip("/")
    for host in FORBIDDEN_HOSTS:
        if host in addr:
            sys.exit(
                "ERROR: refusing Vault host %s — Fishers uses WSLVault at "
                "https://vault.workstation.co.uk only. Set VAULT_ADDR accordingly."
                % host
            )
    return addr, token

def fetch_optional_google(data):
    """Fill OPTIONAL_GOOGLE from WSLVault when missing from the current env map."""
    missing = [k for k in OPTIONAL_GOOGLE if not clean(str(data.get(k, "")))]
    if not missing:
        return
    addr, token = resolve_auth(required=False)
    if not addr or not token:
        return
    logical = os.environ.get("VAULT_SECRET_PATH", "kv/fishers/ios")
    url = addr + "/v1/" + kv_v2_api_path(logical)
    req = urllib.request.Request(url, method="GET")
    req.add_header("X-Vault-Token", token)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except (urllib.error.HTTPError, urllib.error.URLError):
        return
    try:
        payload = json.loads(raw)
    except ValueError:
        return
    vault_data = (payload.get("data") or {}).get("data")
    if not isinstance(vault_data, dict):
        return
    for key in missing:
        if vault_data.get(key):
            data[key] = vault_data[key]

# 1) Prefer env already provided by the workflow (GitHub Actions secrets + local .p8).
if env_has_ids():
    data = {k: clean(os.environ.get(k, "")) for k in REQUIRED_IDS}
    for optional in ("ASC_PRIVATE_KEY_B64", "ASC_PRIVATE_KEY", "ASC_P8_PATH",
                     "CERT_PRIVATE_KEY_B64", "APP_STORE_APP_ID") + OPTIONAL_GOOGLE:
        if os.environ.get(optional):
            data[optional] = os.environ[optional]
    fetch_optional_google(data)
    publish(data, "environment")
    raise SystemExit(0)

# 2) Fall back to WSLVault (vault.workstation.co.uk).
addr, token = resolve_auth(required=True)
logical = os.environ.get("VAULT_SECRET_PATH", "kv/fishers/ios")
api_path = kv_v2_api_path(logical)
url = addr + "/v1/" + api_path

req = urllib.request.Request(url, method="GET")
req.add_header("X-Vault-Token", token)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", "replace")[:500]
    if exc.code == 404:
        sys.exit(
            "ERROR: WSLVault secret missing at %s (HTTP 404).\n"
            "Create it with:\n"
            "  cd ios && ASC_P8_PATH=$HOME/AuthKey_XXXXXX.p8 ./ci/seed-ios-vault.sh\n"
            "Or set GitHub secrets ASC_KEY_ID / ASC_ISSUER_ID / APPLE_TEAM_ID and\n"
            "keep AuthKey_<KEY_ID>.p8 in $HOME on the Mac Studio runner."
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

publish(data, logical)
PY
