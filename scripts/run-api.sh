#!/usr/bin/env bash
# Postgres + the Fishers API, nothing else.
#
# Kept as a shorthand; the work is all in start.sh, so there is one place that
# knows how to bring the API up, which port it uses and how to tell that it is
# actually serving rather than merely listening.
exec "$(dirname "$0")/start.sh" --api-only "$@"
