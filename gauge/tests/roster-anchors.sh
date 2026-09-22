#!/usr/bin/env bash
set -euo pipefail
cd "${GAUGE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}/gauge"
listing="$(GOTOOLCHAIN=local go test -mod=readonly ./... -list '^TestV418T0[1-7]$')"
for id in 01 02 03 04 05 06 07; do
  count="$(printf '%s\n' "$listing" | awk -v name="TestV418T$id" '$0 == name {n++} END {print n+0}')"
  [[ "$count" -eq 1 ]] || { printf 'Missing or duplicate V4-18 anchor %s: %s\n' "$id" "$count" >&2; exit 1; }
done
GOTOOLCHAIN=local go test -mod=readonly -race -count=1 ./... -run '^TestV418' -v
