#!/usr/bin/env bash
# eidolons roster — show detailed roster information
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

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
  # Team view — iterate each Eidolon, format with printf
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
  exit 0
fi

# Detail view for a single Eidolon
entry="$(roster_get "$NAME")"

case "$VIEW" in
  summary)
    disp="$(echo "$entry" | jq -r '.display_name')"
    role="$(echo "$entry" | jq -r '.capability_class')"
    meth="$(echo "$entry" | jq -r '.methodology.name + " v" + .methodology.version')"
    cycle="$(echo "$entry" | jq -r '.methodology.cycle')"
    summary="$(echo "$entry" | jq -r '.methodology.summary')"
    repo="$(echo "$entry" | jq -r '.source.repo')"
    latest="$(echo "$entry" | jq -r '.versions.latest')"
    status="$(echo "$entry" | jq -r '.status')"
    up="$(echo "$entry"   | jq -r '.handoffs.upstream   | if length == 0 then "—" else join(", ") end')"
    down="$(echo "$entry" | jq -r '.handoffs.downstream | if length == 0 then "—" else join(", ") end')"
    lat="$(echo "$entry"  | jq -r '(.handoffs.lateral // []) | if length == 0 then "—" else join(", ") end')"
    tok_entry="$(echo  "$entry" | jq -r '.working_set_tokens.entry  // "n/a"')"
    tok_target="$(echo "$entry" | jq -r '.working_set_tokens.target // "n/a"')"
    sec_read="$(echo   "$entry" | jq -r '.security.reads_repo')"
    sec_write="$(echo  "$entry" | jq -r '.security.writes_repo')"
    sec_net="$(echo    "$entry" | jq -r '.security.reads_network')"

    printf "%s%s%s — %s\n\n" "$BOLD" "$disp" "$RESET" "$role"
    printf "Methodology:  %s\n" "$meth"
    printf "Cycle:        %s\n" "$cycle"
    printf "Summary:      %s\n" "$summary"
    printf "Repo:         github.com/%s\n" "$repo"
    printf "Latest:       %s\n" "$latest"
    printf "Status:       %s\n\n" "$status"

    printf "Handoffs:\n"
    printf "  upstream:    %s\n" "$up"
    printf "  downstream:  %s\n" "$down"
    printf "  lateral:     %s\n\n" "$lat"

    printf "Token budget:\n"
    printf "  entry:            %s tokens\n" "$tok_entry"
    printf "  working set:      %s tokens\n\n" "$tok_target"

    printf "Security:\n"
    printf "  reads repo:    %s\n" "$sec_read"
    printf "  writes repo:   %s\n" "$sec_write"
    printf "  reads network: %s\n" "$sec_net"
    ;;
  methodology) echo "$entry" | jq '.methodology' ;;
  handoffs)    echo "$entry" | jq '.handoffs' ;;
  references)  echo "$entry" | jq -r '.references[]? // empty' ;;
  json)        echo "$entry" ;;
esac
