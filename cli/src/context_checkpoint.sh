#!/usr/bin/env bash
# Verifiable local context checkpoint (PL-04). Durable means local atomic rename.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/lib.sh"
. "$SELF_DIR/lib_context.sh"
usage(){ echo "Usage: eidolons context checkpoint create|recover --payload FILE [--run-id ID] [--id ID] [--json]"; }
sub="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$sub" in create|recover) ;; *) usage; exit 2;; esac
payload=""; run_id=""; id=""; json=false
while [[ $# -gt 0 ]]; do case "$1" in --payload) payload="${2:-}"; shift 2;; --run-id) run_id="${2:-}"; shift 2;; --id) id="${2:-}"; shift 2;; --json) json=true; shift;; *) die "Unknown option: $1";; esac; done
[[ -n "$id" ]] || id="ckpt-$(context_now_epoch_ts)-$$"
[[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid checkpoint id"
dir="$(context_sidecar_dir "$(pwd)")/checkpoints"; mkdir -p "$dir"
required='["constraints","anchors","decisions","failed_approaches","open_variables","pending_checks","lineage"]'
if [[ "$sub" == create ]]; then
  [[ -f "$payload" ]] || die "create requires --payload JSON file"
  jq -e --argjson r "$required" '. as $payload | type=="object" and ([ $r[] as $key | $payload | has($key) ] | all)' "$payload" >/dev/null || die "checkpoint payload lacks required protected fields"
  digest="$(context_sha256_file "$payload")"; [[ -n "$digest" ]] || die "cannot hash checkpoint payload"
  dest="$dir/$id.payload.json"; receipt="$dir/$id.receipt.json"
  tmp="$dest.$$"; cp "$payload" "$tmp"; mv "$tmp" "$dest"
  jq -n --arg id "$id" --arg run "$run_id" --arg ref "checkpoints/$id.payload.json" --arg d "$digest" --arg ts "$(context_now_iso8601)" --argjson req "$required" '{schema_version:"1.0",checkpoint_id:$id,run_id:(if $run=="" then null else $run end),payload_ref:$ref,payload_digest:$d,required_fields:$req,storage:"local-filesystem",durability:"atomic-rename",recovery_check:"pending",created_at:$ts}' > "$receipt.$$.tmp"
  mv "$receipt.$$.tmp" "$receipt"
  [[ "$json" == true ]] && cat "$receipt" || ok "checkpoint created: $receipt"
else
  receipt="$dir/$id.receipt.json"; [[ -f "$receipt" ]] || die "checkpoint receipt not found: $id"
  ref="$(jq -r '.payload_ref' "$receipt")"; file="$(dirname "$dir")/$ref"; [[ -f "$file" ]] || die "checkpoint payload missing"
  expected="$(jq -r '.payload_digest' "$receipt")"; actual="$(context_sha256_file "$file")"
  [[ "$actual" == "$expected" ]] || die "checkpoint digest mismatch; recovery is blocked"
  jq -e --argjson r "$required" '. as $payload | type=="object" and ([ $r[] as $key | $payload | has($key) ] | all)' "$file" >/dev/null || die "checkpoint payload incomplete; recovery is blocked"
  [[ "$json" == true ]] && cat "$file" || ok "checkpoint recovered: $id"
fi
