#!/usr/bin/env bash
# Official Arm-1 runner — 15 frozen missions x 3 runs, harness-v2.
set -u
NEXUS=/home/rynaro/workspace/oss/agents/eidolons
GATE=$NEXUS/.spectra/research/gilgamesh-gate
TOOLS='Read,Grep,Glob,Bash(eidolons sandbox:*),Bash(make:*),Bash(bats:*),Bash(rspec:*),Bash(jest:*),Bash(pytest:*),Bash(go test:*),Bash(shellcheck:*),Bash(shasum:*),Bash(wc:*),mcp__atlas-aci__*,mcp__crystalium__*,mcp__tonberry__*'
run_cell() {
  local run="$1" id="$2" prompt="$3"
  local dir="$GATE/arm1-runs/run$run"
  mkdir -p "$dir"
  local t0=$SECONDS
  # --model pinned explicitly: NEVER let headless runs inherit the session
  # default (Fable) — see memory no-fable-headless-runs. sonnet = the roster's
  # standard tier for gilgamesh (agent.md model pin), i.e. the production tier.
  ( cd "$NEXUS" && timeout 900 claude -p "$prompt" --agent gilgamesh --model claude-sonnet-5 --allowedTools "$TOOLS" \
      > "$dir/$id.report.md" 2> "$dir/$id.stderr.log" )
  local ec=$? secs=$((SECONDS-t0))
  echo "{\"mission_id\":\"$id\",\"run\":$run,\"exit\":$ec,\"secs\":$secs,\"model\":\"claude-sonnet-5\"}" >> "$GATE/arm1-runs/meta.jsonl"
  # oracle grade immediately (mechanical)
  local oec=0
  bash "$GATE/evals/oracle-check.sh" "$id" "$dir/$id.report.md" > "$dir/$id.oracle.log" 2>&1 || oec=$?
  local ver=false; [ "$oec" -eq 0 ] && ver=true
  echo "{\"mission_id\":\"$id\",\"run\":$run,\"verified\":$ver,\"oracle_exit\":$oec,\"harness_exit\":$ec,\"secs\":$secs}" >> "$GATE/arm1-results.jsonl"
}
export -f run_cell 2>/dev/null || true
mkdir -p "$GATE/arm1-runs"
echo 'harness-v2: claude -p "<prompt>" --agent gilgamesh --allowedTools "<gilgamesh allowlist>" (official rerun)' > "$GATE/arm1-runs/HARNESS.txt"
: > "$GATE/arm1-results.jsonl"; : > "$GATE/arm1-runs/meta.jsonl"
for run in 1 2 3; do
  # 3 concurrent within a run; runs sequential (independence across runs)
  pids=""
  n=0
  while IFS= read -r line; do
    id=$(printf '%s' "$line" | jq -r .id); prompt=$(printf '%s' "$line" | jq -r .prompt)
    run_cell "$run" "$id" "$prompt" &
    pids="$pids $!"; n=$((n+1))
    if [ $((n % 3)) -eq 0 ]; then wait $pids; pids=""; fi
  done < "$GATE/arm1-holdout.jsonl"
  [ -n "$pids" ] && wait $pids
done
echo "ALL RUNS DONE $(date -u +%H:%M:%SZ)" >> "$GATE/arm1-runs/meta.jsonl"
