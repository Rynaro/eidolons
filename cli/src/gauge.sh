#!/usr/bin/env bash
# Optional compiled controller: ordinary CLI commands never load a Go runtime.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary="${EIDOLONS_GAUGE_BIN:-$SELF_DIR/../../gauge/bin/eidolons-gauge}"
if [[ ! -f "$binary" || ! -x "$binary" ]]; then
  printf '%s\n' 'Gauge binary unavailable. Build with make gauge-build, or set EIDOLONS_GAUGE_BIN to an explicitly installed executable. No legacy write fallback is performed.' >&2
  exit 1
fi
exec "$binary" "$@"
