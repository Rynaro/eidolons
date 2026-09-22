#!/usr/bin/env bash
set -euo pipefail
cd "${GAUGE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}/gauge"
listing="$(go test -mod=readonly ./... -list '^TestV417T0[1-6]$')"
for id in 01 02 03 04 05 06; do
  count="$(printf '%s\n' "$listing" | awk -v name="TestV417T$id" '$0 == name {n++} END {print n+0}')"
  [[ "$count" -eq 1 ]] || { printf 'Missing or duplicate V4-17 anchor %s: %s\n' "$id" "$count" >&2; exit 1; }
done
go test -mod=readonly -race -count=1 ./... -run '^TestV417' -v
