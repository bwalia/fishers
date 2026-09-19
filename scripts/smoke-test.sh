#!/usr/bin/env bash
# What a ring looks like from outside: the dashboard, the API, the docs and the
# media bucket, over its own public host. Run it after a deploy, and after any
# change to what sits in front of the API — a Kong cutover, say, where every
# path below still has to answer exactly as it did before.
#
#   BASE_URL=https://int.fishers.cloud ./scripts/smoke-test.sh
#   ./scripts/smoke-test.sh https://www.fishers.cloud
#
# Public surface only: nothing here signs in, so it is safe against any ring,
# including production. A non-zero exit means at least one check failed.
set -uo pipefail

BASE="${1:-${BASE_URL:-}}"
[ -n "$BASE" ] || { echo "usage: BASE_URL=https://<host> $0" >&2; exit 2; }
BASE="${BASE%/}"

fail=0
pass=0

# name, path, expected status, what a failure would mean
check() {
  local name="$1" path="$2" want="$3" why="$4"
  local code
  code="$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$BASE$path" || echo 000)"
  if [ "$code" = "$want" ]; then
    printf '  ok    %-22s %s\n' "$name" "$path"
    pass=$((pass + 1))
  else
    printf '  FAIL  %-22s %s — got %s, wanted %s: %s\n' "$name" "$path" "$code" "$want" "$why"
    fail=$((fail + 1))
  fi
}

echo "== $BASE"

# The dashboard. /login renders without the API, so it isolates the web process.
check dashboard       /login            200 "the Next.js pod is down, or the ingress lost its / route"
check landing         /                 200 "the landing page is not being served"

# The API, through whatever is in front of it. These are the paths the ingress
# hands to the API — or to Kong, where a ring has it — so they prove the whole
# chain a browser uses, not just that a pod is running.
check api-health      /health           200 "nothing is answering for the API: pod, ingress route, or the gateway in front of it"
check api-ready       /health/ready     200 "the API is up but cannot reach Postgres"
check swagger         /swagger-ui       200 "the API's docs route is not reaching the API"

# 404 rather than 200: this asks the API a real question about a club that does
# not exist, which only the API can answer. A 502 or a timeout here with the
# health checks green means something in front is passing some paths and not
# others.
check api-not-found   /api/v1/public/clubs/definitely-not-a-club 404 \
  "the API is not handling real requests, only its health route"

echo
if [ "$fail" -eq 0 ]; then
  echo "$pass checks passed."
else
  echo "$fail of $((pass + fail)) checks failed." >&2
fi
exit $((fail > 0))
