#!/usr/bin/env bash
# eidolons list — list available (from roster) or installed Eidolons
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

MODE="installed"  # default: show project state if we're in a project
[[ ! -f "eidolons.yaml" ]] && MODE="available"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --available|-a) MODE="available"; shift ;;
    --installed|-i) MODE="installed"; shift ;;
    --presets)      MODE="presets"; shift ;;
    --json)         MODE="json"; shift ;;
    -h|--help)
      cat <<EOF
eidolons list — list Eidolons

Usage: eidolons list [OPTIONS]

Options:
  --available, -a     List every Eidolon in the nexus roster
  --installed, -i     List only Eidolons installed in this project (default if cwd has eidolons.yaml)
  --presets           List named presets from the roster
  --json              JSON output (for scripting)
EOF
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  available)
    printf "${BOLD}%-10s %-12s %-8s %s${RESET}\n" "NAME" "ROLE" "STATUS" "METHODOLOGY"
    yaml_to_json "$ROSTER_FILE" | jq -r '
      .eidolons[] | [.name, .capability_class, .status, (.methodology.name + " v" + .methodology.version)] | @tsv' \
      | while IFS=$'\t' read -r n role status meth; do
          printf "%-10s %-12s %-8s %s\n" "$n" "$role" "$status" "$meth"
        done
    ;;

  installed)
    [[ -f "$PROJECT_MANIFEST" ]] || die "No eidolons.yaml here. Use 'eidolons list --available' or run 'eidolons init'."
    printf "${BOLD}%-10s %-12s %s${RESET}\n" "NAME" "VERSION" "TARGET"
    if [[ -f "$PROJECT_LOCK" ]]; then
      yaml_to_json "$PROJECT_LOCK" | jq -r '.members[]? | [.name, .version, .target] | @tsv' \
        | while IFS=$'\t' read -r n ver target; do
            printf "%-10s %-12s %s\n" "$n" "$ver" "$target"
          done
    else
      info "No eidolons.lock yet — run 'eidolons sync'"
      yaml_to_json "$PROJECT_MANIFEST" | jq -r '.members[] | [.name, .version, "(not installed)"] | @tsv' \
        | while IFS=$'\t' read -r n ver target; do
            printf "%-10s %-12s %s\n" "$n" "$ver" "$target"
          done
    fi
    ;;

  presets)
    yaml_to_json "$ROSTER_FILE" \
      | jq -r '.presets | to_entries[] |
          "\(.key)\t\(.value.description)\t\(.value.members | join(", "))"' \
      | while IFS=$'\t' read -r key desc members; do
          printf "%s%s%s\n  %s\n  Members: %s\n\n" "$BOLD" "$key" "$RESET" "$desc" "$members"
        done
    ;;

  json)
    yaml_to_json "$ROSTER_FILE"
    ;;
esac
