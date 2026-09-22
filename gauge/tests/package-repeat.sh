#!/usr/bin/env bash
set -euo pipefail
# Run as an ordinary user: root can overwrite 0444 files and conceal the defect.
[[ $(id -u) != 0 ]] || { echo 'nonroot package test required' >&2; exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT
make -C "$root" gauge-package GAUGE_OUT="$output/package"
cp "$output/package/eidolons-gauge" "$output/first"
# Existing package outputs may already carry cache-inherited read-only modes.
chmod 0444 "$output/package/licenses/"*
make -C "$root" gauge-package GAUGE_OUT="$output/package"
cmp "$output/first" "$output/package/eidolons-gauge"
for name in Go-LICENSE go.etcd.io_bbolt-LICENSE golang.org_x_sys-LICENSE; do
  test -s "$output/package/licenses/$name"
done
echo 'F003 repeat package refresh and executable reproducibility passed'
