#!/usr/bin/env bash
set -euo pipefail
cd "${GAUGE_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}/gauge"
listing="$(go test -mod=readonly ./... -list '^TestV419T(0[1-9]|1[0-2])$')"
for id in 01 02 03 04 05 06 07 08 09 10 11 12; do
  count="$(printf '%s\n' "$listing" | awk -v name="TestV419T$id" '$0 == name {n++} END {print n+0}')"
  [[ "$count" -eq 1 ]] || { printf 'Missing or duplicate V4-19 anchor %s: %s\n' "$id" "$count" >&2; exit 1; }
done
go test -mod=readonly -race -count=1 ./... -run '^TestV419' -v
