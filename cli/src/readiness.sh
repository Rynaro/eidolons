#!/usr/bin/env bash
# eidolons readiness — capability receipt for the current project.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: eidolons readiness [--live] [--json]

Writes a versioned local receipt that distinguishes declared configuration,
discoverability, startup testing, and enforceable boundaries.  A configured
host is never reported ready merely because configuration exists.
EOF
}

LIVE=false
JSON=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) LIVE=true; shift ;;
    --json) JSON=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (see 'eidolons readiness --help')" ;;
  esac
done
manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

receipt_dir=".eidolons/.readiness"
receipt_path="$receipt_dir/receipt.json"
mkdir -p "$receipt_dir"
manifest_digest="$(sha256_file "$PROJECT_MANIFEST")"
lock_digest=""
[[ -f "$PROJECT_LOCK" ]] && lock_digest="$(sha256_file "$PROJECT_LOCK")"
config_digest="$(printf '%s\n%s\n' "$manifest_digest" "$lock_digest" | sha256_file /dev/stdin)"

if [[ "$LIVE" != true && -f "$receipt_path" ]] && jq -e --arg d "$config_digest" '.configuration_digest == $d' "$receipt_path" >/dev/null 2>&1; then
  if [[ "$JSON" == true ]]; then cat "$receipt_path"; else ok "readiness receipt cached: $receipt_path"; fi
  exit 0
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
hosts="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.wire[] // empty')"
entries='[]'
while IFS= read -r host; do
  [[ -n "$host" ]] || continue
  case "$host" in
    claude-code) surface=".claude/agents" ;;
    codex) surface=".codex/agents" ;;
    copilot) surface=".github/agents" ;;
    cursor) surface=".cursor/rules" ;;
    opencode) surface=".opencode/agents" ;;
    *) surface="" ;;
  esac
  discovered=false; [[ -n "$surface" && -d "$surface" ]] && discovered=true
  startup="unknown"; reason="no live probe requested"; next="run: eidolons readiness --live"
  if [[ "$LIVE" == true ]]; then
    startup="not_tested"; reason="no bounded startup probe is defined for $host"; next="use eidolons harness check where supported"
    if [[ "$host" == "claude-code" || "$host" == "codex" || "$host" == "copilot" ]]; then
      if bash "$SELF_DIR/harness_check.sh" >/dev/null 2>&1; then startup="passed"; reason="harness registration and syntax verified"; next=""; else startup="failed"; reason="harness registration or syntax check failed"; next="run: eidolons harness check"; fi
    fi
  fi
  enforceable="unknown"
  if [[ -f "$PROJECT_LOCK" ]]; then
    enforceable="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null | jq -r --arg h "$host" 'if ((.harness.strict // []) | index($h)) then "yes" else "no" end' 2>/dev/null || echo unknown)"
  fi
  entries="$(printf '%s' "$entries" | jq --arg h "$host" --arg s "$surface" --arg ts "$now" --argjson d "$discovered" --arg st "$startup" --arg r "$reason" --arg n "$next" --arg e "$enforceable" '. + [{host:$h, host_version:"unknown", configured:true, discovery:{state:(if $d then "present" else "missing" end),surface:$s}, startup_test:{state:$st,reason:$r,next_step:(if $n=="" then null else $n end)}, enforceable:$e, evidence_timestamp:$ts}]')"
done <<< "$hosts"

members='[]'
while IFS= read -r member; do
  [[ -n "$member" ]] || continue
  target=".eidolons/$member"
  present=false; [[ -d "$target" ]] && present=true
  members="$(printf '%s' "$members" | jq --arg n "$member" --arg t "$target" --argjson p "$present" '. + [{name:$n, configured:true, discoverable:(if $p then "present" else "missing" end), startup_test:"unknown", enforceable:"unknown", evidence:{target:$t}}]')"
done < <(manifest_members)

jq -n --arg v "1.0" --arg ts "$now" --arg d "$config_digest" --arg md "$manifest_digest" --arg ld "$lock_digest" --argjson live "$LIVE" --argjson hosts "$entries" --argjson members "$members" \
  '{receipt_version:$v, observed_at:$ts, configuration_digest:$d, manifest_digest:$md, lock_digest:(if $ld=="" then null else $ld end), live_probe:$live, hosts:$hosts, members:$members}' > "$receipt_path"
if [[ "$JSON" == true ]]; then cat "$receipt_path"; else ok "readiness receipt written: $receipt_path"; fi
