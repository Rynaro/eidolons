#!/usr/bin/env bash
set -euo pipefail
cd "${GAUGE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}/gauge"
listing="$(go test -mod=readonly ./... -list '^TestV410T0[17]$')"
for id in 01 07; do
  count="$(printf '%s\n' "$listing" | awk -v name="TestV410T$id" '$0 == name {n++} END {print n+0}')"
  [[ "$count" -eq 1 ]] || { printf 'Missing or duplicate V4-10 inventory anchor %s: %s\n' "$id" "$count" >&2; exit 1; }
done
GAUGE_REPO="${GAUGE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}" \
  go test -mod=readonly -race -count=1 ./... -run '^TestV410' -v
