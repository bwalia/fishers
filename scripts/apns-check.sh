#!/usr/bin/env bash
# Does the APNs key actually work?
#
#   ./scripts/apns-check.sh                       # check the key and the JWT
#   ./scripts/apns-check.sh <device-token>        # …and send a real push
#
# Reads APNS_* from .env, the same as the API does. Three things go wrong with
# APNs setups and all three look identical from the app (nothing arrives):
#
#   1. The key is the wrong sort. A .p8 from "Keys" with APNs ticked is not
#      the same file as a push *certificate*, and both end in .p8-ish things
#      people have lying around.
#   2. The ids are swapped. Key ID and Team ID are both ten characters of
#      the same alphabet, and reversing them is a 403 with no explanation.
#   3. The environment is the wrong way round. A development build's token is
#      only valid against the sandbox host and an App Store build's only
#      against production — the same token returns BadDeviceToken on the
#      other one. This is the usual reason a correct-looking setup is silent.
#
# So this talks to Apple rather than checking the file parses. With no device
# token it stops after proving the credentials; with one it sends a real
# notification and prints exactly what APNs said.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# .env fills in what the environment has not already said, which is what
# dotenvy does for the API — `APNS_ENVIRONMENT=production ./scripts/apns-check.sh`
# has to mean production, not whatever .env happens to hold. A `set -a` source
# would do the opposite, and an empty line in .env would blank a real value.
if [ -f .env ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"
    case "$key" in *[!A-Za-z0-9_]*|'') continue ;; esac
    value="${line#*=}"
    value="${value%\"}"; value="${value#\"}"
    [ -n "${!key:-}" ] || export "$key=$value"
  done < .env
fi

if [ -t 1 ]; then
  B=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; N=$'\033[0m'
else
  B=""; RED=""; GRN=""; YEL=""; DIM=""; N=""
fi
ok()   { printf '    %s✓%s %s\n' "$GRN" "$N" "$*"; }
bad()  { printf '    %sx%s %s\n' "$RED" "$N" "$*"; }
warn() { printf '    %s!%s %s\n' "$YEL" "$N" "$*"; }
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
die()  { bad "$*"; exit 1; }

DEVICE_TOKEN="${1:-}"
BUNDLE_ID="${APNS_BUNDLE_ID:-com.fishers.app}"
ENVIRONMENT="${APNS_ENVIRONMENT:-sandbox}"
case "$ENVIRONMENT" in
  production|prod) HOST="https://api.push.apple.com" ;;
  *)               HOST="https://api.sandbox.push.apple.com"; ENVIRONMENT="sandbox" ;;
esac

step "Configuration"
[ -n "${APNS_KEY_ID:-}" ]  || die "APNS_KEY_ID is not set — see .env.example"
[ -n "${APNS_TEAM_ID:-}" ] || die "APNS_TEAM_ID is not set — see .env.example"

# The key, from the variable or the file the variable points at.
if [ -n "${APNS_PRIVATE_KEY:-}" ]; then
  KEY_PEM="$APNS_PRIVATE_KEY"
  KEY_FROM="APNS_PRIVATE_KEY"
elif [ -n "${APNS_PRIVATE_KEY_PATH:-}" ]; then
  [ -f "$APNS_PRIVATE_KEY_PATH" ] || die "APNS_PRIVATE_KEY_PATH points at nothing: $APNS_PRIVATE_KEY_PATH"
  KEY_PEM="$(cat "$APNS_PRIVATE_KEY_PATH")"
  KEY_FROM="$APNS_PRIVATE_KEY_PATH"
else
  die "neither APNS_PRIVATE_KEY nor APNS_PRIVATE_KEY_PATH is set"
fi
# .env cannot hold a newline, so a pasted key arrives with literal \n in it.
KEY_PEM="${KEY_PEM//\\n/$'\n'}"

printf '    %-12s %s\n' "key id"  "$APNS_KEY_ID"
printf '    %-12s %s\n' "team id" "$APNS_TEAM_ID"
printf '    %-12s %s\n' "bundle"  "$BUNDLE_ID"
printf '    %-12s %s %s\n' "host" "$HOST" "${DIM}($ENVIRONMENT)${N}"
printf '    %-12s %s\n' "key from" "$KEY_FROM"

case "${#APNS_KEY_ID}" in 10) ok "key id is ten characters" ;;
  *) warn "key id is ${#APNS_KEY_ID} characters — Apple's are ten" ;; esac
case "${#APNS_TEAM_ID}" in 10) ok "team id is ten characters" ;;
  *) warn "team id is ${#APNS_TEAM_ID} characters — Apple's are ten" ;; esac

step "The key itself"
case "$KEY_PEM" in
  *"BEGIN PRIVATE KEY"*) ok "PKCS#8 private key, which is what a .p8 holds" ;;
  *"BEGIN CERTIFICATE"*) die "that is a certificate, not a key — download the .p8 from Keys, not Certificates" ;;
  *"BEGIN RSA PRIVATE KEY"*) die "that is an RSA key — APNs token auth wants the P-256 key from a .p8" ;;
  *) die "does not look like a PEM private key (no BEGIN PRIVATE KEY line)" ;;
esac
CURVE="$(printf '%s' "$KEY_PEM" | openssl pkey -noout -text 2>/dev/null | grep -i "NIST CURVE\|ASN1 OID" | head -1 || true)"
case "$CURVE" in
  *P-256*|*prime256v1*) ok "elliptic curve P-256${DIM} — ${CURVE##*: }${N}" ;;
  "") die "openssl could not read the key — it is not a usable .p8" ;;
  *) warn "unexpected curve: $CURVE (APNs expects P-256)" ;;
esac

step "Signing a provider token"
b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
NOW="$(date +%s)"
HEADER="$(printf '{"alg":"ES256","kid":"%s"}' "$APNS_KEY_ID" | b64url)"
CLAIMS="$(printf '{"iss":"%s","iat":%s}' "$APNS_TEAM_ID" "$NOW" | b64url)"
KEY_FILE="$(mktemp)"; trap 'rm -f "$KEY_FILE" "${SIG_FILE:-}"' EXIT
printf '%s\n' "$KEY_PEM" > "$KEY_FILE"
SIG_FILE="$(mktemp)"
# ES256 is a raw 64-byte r||s pair; openssl signs to DER, so it is converted.
printf '%s.%s' "$HEADER" "$CLAIMS" \
  | openssl dgst -sha256 -sign "$KEY_FILE" -binary > "$SIG_FILE" 2>/dev/null \
  || die "could not sign with this key"
SIG="$(openssl asn1parse -inform DER -in "$SIG_FILE" 2>/dev/null \
      | awk -F: '/INTEGER/ {printf "%s", substr($4,8)}' \
      | python3 -c 'import sys,base64;h=sys.stdin.read();h=h.rjust(128,"0") if len(h)<128 else h[-128:];print(base64.urlsafe_b64encode(bytes.fromhex(h)).decode().rstrip("="))')"
JWT="$HEADER.$CLAIMS.$SIG"
ok "signed an ES256 provider token${DIM} (${#JWT} chars)${N}"

if [ -z "$DEVICE_TOKEN" ]; then
  step "Not sending"
  warn "no device token given, so nothing was sent to a phone."
  printf '    %s\n' "The credentials are well-formed, but only APNs can say whether"
  printf '    %s\n' "it accepts them. Register a device, then:"
  printf '\n      %s./scripts/apns-check.sh <device-token>%s\n\n' "$B" "$N"
  printf '    %sThe token is the hex string the app sends to /notifications/register-device;%s\n' "$DIM" "$N"
  printf '    %sit is in device_tokens.device_token for a signed-in account.%s\n' "$DIM" "$N"
  exit 0
fi

step "Sending to $HOST"
BODY='{"aps":{"alert":{"title":"Fishers","body":"APNs is working."},"sound":"default"},"apns_check":true}'
RESPONSE="$(curl -sS --http2 -o /tmp/apns-check.out -w '%{http_code}' \
  -H "authorization: bearer $JWT" \
  -H "apns-topic: $BUNDLE_ID" \
  -H "apns-push-type: alert" \
  -H "apns-priority: 10" \
  -d "$BODY" \
  "$HOST/3/device/$DEVICE_TOKEN" 2>/tmp/apns-check.err)" || {
    bad "curl failed: $(cat /tmp/apns-check.err)"
    grep -q "HTTP/2" /tmp/apns-check.err 2>/dev/null \
      && warn "this curl may lack HTTP/2 — APNs speaks nothing else. brew install curl"
    exit 1
  }
REASON="$(python3 -c 'import json,sys
try: print(json.load(open("/tmp/apns-check.out")).get("reason",""))
except Exception: print(open("/tmp/apns-check.out").read().strip())' 2>/dev/null || true)"

case "$RESPONSE" in
  200) ok "APNs accepted it — the phone should have buzzed."; exit 0 ;;
esac

bad "APNs refused it: HTTP $RESPONSE ${REASON:+($REASON)}"
case "$REASON" in
  BadDeviceToken)
    OTHER=sandbox; [ "$ENVIRONMENT" = sandbox ] && OTHER=production
    warn "Usually the environment, not the token: this is the $ENVIRONMENT host."
    printf '    %s\n' "A Debug/TestFlight build's token only works against the sandbox;"
    printf '    %s\n' "an App Store build's only against production. Try APNS_ENVIRONMENT=$OTHER." ;;
  DeviceTokenNotForTopic)
    warn "The token belongs to a different app than $BUNDLE_ID — check APNS_BUNDLE_ID." ;;
  InvalidProviderToken|ExpiredProviderToken)
    warn "The credentials are wrong, not the device."
    printf '    %s\n' "Key ID and Team ID are both ten characters — check they are not swapped," ;
    printf '    %s\n' "and that this key has APNs enabled in the Apple Developer portal." ;;
  TopicDisallowed)
    warn "This key is not entitled to push for $BUNDLE_ID." ;;
  TooManyRequests|ServiceUnavailable|InternalServerError)
    warn "APNs itself is unhappy. Nothing to fix here — try again shortly." ;;
esac
exit 1
