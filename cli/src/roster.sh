#!/usr/bin/env bash
# eidolons roster — show detailed roster information
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/card.sh"

usage() {
  cat <<EOF
eidolons roster — show detailed information about the Eidolons team

Usage: eidolons roster [NAME] [OPTIONS]

  NAME              Eidolon name (e.g. atlas). If omitted, shows the full team.

Options:
  --methodology     Show methodology details only
  --handoffs        Show handoff contracts only
  --references      Show research references only
  --json            JSON output
  -h, --help        Show this help
EOF
}

NAME=""
VIEW="summary"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --methodology) VIEW="methodology"; shift ;;
    --handoffs)    VIEW="handoffs"; shift ;;
    --references)  VIEW="references"; shift ;;
    --json)        VIEW="json"; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            echo "Unknown: $1" >&2; exit 2 ;;
    *)             NAME="$1"; shift ;;
  esac
done

ROSTER_JSON="$(yaml_to_json "$ROSTER_FILE")"

if [[ -z "$NAME" ]]; then
  # Team view.
  # Fancy mode: stack a JRPG-style character card per Eidolon. Plain mode:
  # the original lowercase-key text dump — bats tests assert on `cycle:`
  # and `methodology:` (lowercase) which are unique to this view.
  if [[ "${EIDOLONS_FANCY:-0}" == "1" ]]; then
    ui_section "The Eidolons team"
    while IFS= read -r _name; do
      [[ -z "$_name" ]] && continue
      ui_card "$_name"
      echo ""
    done < <(echo "$ROSTER_JSON" | jq -r '.eidolons[].name')
  else
    printf "%sThe Eidolons team%s\n\n" "$BOLD" "$RESET"
    echo "$ROSTER_JSON" \
      | jq -r '.eidolons[] |
          [.display_name, .capability_class, .methodology.cycle,
           (.methodology.name + " v" + .methodology.version),
           .source.repo, .versions.latest, .status] | @tsv' \
      | while IFS=$'\t' read -r disp role cycle meth repo latest status; do
          printf "%s%s%s — %s\n" "$BOLD" "$disp" "$RESET" "$role"
          printf "  cycle:        %s\n" "$cycle"
          printf "  methodology:  %s\n" "$meth"
          printf "  repo:         github.com/%s\n" "$repo"
          printf "  latest:       %s\n" "$latest"
          printf "  status:       %s\n\n" "$status"
        done
  fi
  exit 0
fi

# Detail view for a single Eidolon
entry="$(roster_get "$NAME")"

case "$VIEW" in
  summary)
    # Fancy mode: JRPG-style character card. Plain mode: legacy text dump
    # (handled inside ui_card → _ui_card_plain to keep the substrings
    # tests assert on intact: Methodology:, Handoffs:, Security:, etc.).
    ui_card "$NAME"
    ;;
  methodology) echo "$entry" | jq '.methodology' ;;
  handoffs)    echo "$entry" | jq '.handoffs' ;;
  references)  echo "$entry" | jq -r '.references[]? // empty' ;;
  json)        echo "$entry" ;;
esac
