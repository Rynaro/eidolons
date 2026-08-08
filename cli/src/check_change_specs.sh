#!/usr/bin/env bash
# cli/src/check_change_specs.sh — parse guard for LIVE ESL change records.
#
# Fails (exit 1) if any .spectra/changes/<change-id>/spec.yaml is not valid YAML.
#
# Why this exists: `chain-scout-debug-fix` carried an unparseable spec.yaml
# through four checker rounds. Nothing in the repo ever read the file — `make
# schema` covered schemas/*.json and roster/index.yaml only — so the change's
# seven acceptance criteria were mechanically invisible, while its change.json
# carried `acceptance_checks: []`. The criteria could not be read from either
# file by any tool. A record that no gate parses is not a record.
#
# It was not a one-off: the two predecessor records in the same lineage
# (chain-three-class, routing-recall-gap) also fail to parse.
#
# ONE root cause, verified by falsification rather than inspection: a ": "
# embedded in a multi-line PLAIN scalar list entry. Only the colon's POSITION
# changes the parser message, which is why the three looked like two defects:
#   * colon on the entry's FIRST line -> the entry becomes a mapping, and the
#     continuation at that key's indent reads as a new key:
#     "could not find expected ':'"
#   * colon on a CONTINUATION line -> "mapping values are not allowed in this
#     context"
# Indentation alone is NOT the cause: the same entry with identical indentation
# and the colon removed parses cleanly. A block scalar ('- >') parses with both
# hazards present. Use one for ANY multi-line list entry.
#
# SCOPE, so nobody mistakes this for more than it is: it checks that the file
# PARSES, not that it is a well-formed record. An empty file, '---', a bare
# scalar, duplicate keys, and acceptance_checks: [] all pass. It also reports OK
# when the glob matches nothing (no records, or a record naming its spec
# something other than spec.yaml), and the depth-1 glob skips any record nested
# below .spectra/changes/<id>/ — no such record exists; depth-1 is the
# convention.
#
# ARCHIVED records (.spectra/changes/archive/**) are deliberately NOT checked:
# they are frozen lifecycle history and are not rewritten to satisfy a gate
# added after they shipped. The two known-bad ones are recorded in
# .spectra/changes/chain-scout-debug-fix/verification.md rather than repaired.
# The glob below is depth-1 under .spectra/changes, so archive/ is excluded
# structurally rather than by a name filter.
#
# Usage:
#   bash cli/src/check_change_specs.sh [NEXUS_ROOT]
#
# NEXUS_ROOT defaults to the directory two levels above this script (i.e. the
# repo root when invoked as cli/src/check_change_specs.sh).
#
# Requires: yq (mikefarah Go or compatible) or python3+yaml, via yaml_to_json
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXUS_ROOT="${1:-"$(cd "$SELF_DIR/../.." && pwd)"}"

# shellcheck source=cli/src/lib.sh
. "$SELF_DIR/lib.sh"

CHANGES_DIR="${NEXUS_ROOT}/.spectra/changes"

# ESL is opt-in — a checkout without change records is not a failure.
if [ ! -d "$CHANGES_DIR" ]; then
  echo "check_change_specs: no .spectra/changes — nothing to check"
  exit 0
fi

_seen=0
_bad=0

for _spec in "$CHANGES_DIR"/*/spec.yaml; do
  # Unmatched glob expands to itself; skip it.
  [ -f "$_spec" ] || continue
  _seen=$((_seen + 1))

  if ! yaml_to_json "$_spec" >/dev/null 2>&1; then
    _bad=$((_bad + 1))
    echo "check_change_specs: FAIL ${_spec#"${NEXUS_ROOT}"/}" >&2
    # Surface the parser's own message; it carries the offending line number.
    yaml_to_json "$_spec" 2>&1 >/dev/null | head -2 >&2 || true
  fi
done

if [ "$_bad" -ne 0 ]; then
  echo "check_change_specs: ${_bad} of ${_seen} live change spec(s) do not parse" >&2
  echo "A multi-line list entry needs a block scalar ('- >'), not a plain scalar." >&2
  exit 1
fi

echo "check_change_specs: ${_seen} live change spec(s) parse — OK"
