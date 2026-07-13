#!/usr/bin/env bats
#
# cli/tests/context.bats — coverage for 'eidolons context' verb family (ECM P1)
#
# ECM P1 — context-lifecycle kernel: status|policy|externalize|handoff verbs,
# the meter/policy-log/budget-ledger sidecars, and the harness_install.sh /
# harness_hook.sh / run.sh recipes (SessionStart pin+handoff digest,
# UserPromptSubmit meter/policy line, PostToolUse meter refresh,
# compactThreshold don't-clobber). AC-4/AC-9 (handoff round-trip + the D5
# quarantine-vs-recall regression) are verified by 'eidolons canary
# --context-handoff' (a live-crystalium canary), not bats — see canary.sh.
#
# Design (mirrors harness.bats/memory.bats conventions, FINDING-030-034):
#   - load helpers; seed_manifest/seed_lock from shared helpers.bash.
#   - LOCAL seed helpers below (seed_manifest_ecm_on, seed_lock_with_context,
#     fake docker/eidolons stubs) — do NOT edit shared helpers.bash (FINDING-031).
#   - jq -cS / sha256 comparisons for idempotency and determinism checks.
#   - # ─── AC-N ─── block headers, one test per frozen acceptance criterion.

bats_require_minimum_version 1.5.0

load helpers

# ─── Local seed helpers (FINDING-031: do NOT edit shared helpers.bash) ───────

# seed_manifest_ecm_on — eidolons.yaml with a 'context:' block present
# (ECM opt-in, AC-15's positive case).
seed_manifest_ecm_on() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
context:
  enabled: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# seed_lock_with_context — eidolons.lock already carrying a context: block
# (used by refresh-shims-only style tests; local per FINDING-031).
seed_lock_with_context() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-07-07T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
context:
  schema_version: 1
  ecm_version: "0.1"
  host_tier: "T3"
  thresholds:
    amber: 0.50
    red: 0.75
    critical: 0.90
  compactthreshold_managed: true
EOF
}

# seed_mcp_crystalium_local — .mcp.json + eidolons.mcp.lock crystalium
# entries (trimmed local copy of memory.bats's fixture, FINDING-031: bats
# test files do not share functions across files, only shared helpers.bash).
seed_mcp_crystalium_local() {
  cat > .mcp.json <<'JSON'
{
  "mcpServers": {
    "crystalium": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "--name", "crystalium-test", "ghcr.io/rynaro/crystalium@sha256:deadbeef", "python", "-m", "crystalium", "serve"]
    }
  }
}
JSON
  cat > eidolons.mcp.lock <<'LOCK'
generated_at: "2026-07-07T00:00:00Z"
eidolons_cli_version: "1.36.0"
catalogue_version: "1.2"
mcps:
  - name: crystalium
    kind: oci-image
    version: "1.7.0"
    target: ".mcp.json"
LOCK
}

# setup_fake_docker_argv_log — a fake docker on PATH that logs its argv to
# $FAKE_DOCKER_ARGV_LOG and always "succeeds" with a minimal JSON object
# (so callers treat every one-shot invocation as a success).
setup_fake_docker_argv_log() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-docker-bin"
  mkdir -p "$fake_bin"
  local log="$BATS_TEST_TMPDIR/docker-argv.log"
  export FAKE_DOCKER_ARGV_LOG="$log"
  cat > "$fake_bin/docker" <<DSHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
printf '{"id":"fake-id"}\n'
exit 0
DSHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

# setup_fake_eidolons_bin — a fake 'eidolons' on PATH that delegates
# everything to the real checkout CLI. Needed because harness_hook.sh's
# ECM additions resolve their own binary via `command -v eidolons`, which
# is otherwise unresolvable from inside a spawned hook subprocess in a dev
# checkout (mirrors harness.bats's setup_fake_eidolons_for_memory, local copy).
setup_fake_eidolons_bin() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-eidolons-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/eidolons" <<STUB
#!/usr/bin/env bash
exec bash "$EIDOLONS_ROOT/cli/eidolons" "\$@"
STUB
  chmod +x "$fake_bin/eidolons"
  export PATH="$fake_bin:$PATH"
}

# ─── Dispatcher sanity ────────────────────────────────────────────────────

@test "context: dispatcher routes context --help" {
  run eidolons context --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "eidolons context" ]]
}

@test "context: unknown subcommand exits 2 with usage hint" {
  run eidolons context bogus
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown context subcommand" ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# fix-ecm-meter-race-atlas-sync (D1) — AC-1 (concurrent-write race) / AC-2
# (corrupt-meter self-heal). Global spec AC numbering — distinct from this
# file's OWN internal "AC-1"/"AC-2" section labels below, which predate this
# change and cover unrelated status/policy behaviour.
#
# Both writers feeding .eidolons/.context/meter.json (statusline.sh every 2s,
# harness_hook.sh on SessionStart/UserPromptSubmit) invoke
# cli/src/context_status.sh directly, so these tests do the same — spawning
# the script itself, not going through the `eidolons context status`
# dispatcher — to reproduce the exact concurrency shape that corrupted the
# real meter.json on disk.
# ═══════════════════════════════════════════════════════════════════════════

# ─── AC-1: 40 concurrent differing-length write pairs -> 0 corrupt meters ────
# Pre-fix: the write at context_status.sh's old `printf ... > "$METER_PATH"`
# was a plain (non-atomic) redirect — a short write landing over an
# in-flight long write leaves the long write's tail behind. Measured 9/40
# (and independently reproduced 2-5/40 across repeated runs) corrupt files
# pre-fix; this asserts 0/40 post-fix.

@test "fix-ecm-meter-race AC-1: 40 concurrent differing-length write pairs never corrupt meter.json" {
  mkdir -p .eidolons/.context
  local corrupt=0
  local i p1 p2
  for i in $(seq 1 40); do
    rm -f .eidolons/.context/meter.json
    bash "$EIDOLONS_ROOT/cli/src/context_status.sh" \
      --session-id "race-sid-${i}-0123456789abcdef0123456789abcdef" \
      --used-percentage 22 --window-tokens 1000000 >/dev/null 2>&1 &
    p1=$!
    bash "$EIDOLONS_ROOT/cli/src/context_status.sh" --used-percentage 7 >/dev/null 2>&1 &
    p2=$!
    wait "$p1" 2>/dev/null || true
    wait "$p2" 2>/dev/null || true
    if [ ! -f .eidolons/.context/meter.json ] || ! jq empty .eidolons/.context/meter.json 2>/dev/null; then
      corrupt=$((corrupt + 1))
    fi
  done
  [ "$corrupt" -eq 0 ]
}

# ─── AC-2: a corrupt prior meter self-heals on the next write ────────────────
# Pre-fix: the inherit-prior-meter reads were `jq -r '...' 2>/dev/null ||
# echo 0` — on a corrupt file jq prints ITS partial output AND exits 5, so
# the shell captures both -> a two-line value where --argjson demands a
# single JSON scalar -> the compose fails -> METER_JSON="" -> the kernel
# bails BEFORE the write, so the corrupt file is never overwritten (wedged
# forever). Fixture below is the real shape: a complete JSON object directly
# followed by the orphaned tail of a longer previous write.

@test "fix-ecm-meter-race AC-2: corrupt meter.json (valid object + orphaned tail) self-heals on next write" {
  mkdir -p .eidolons/.context
  cat > .eidolons/.context/meter.json <<'EOF'
{"ecm_version":"0.1","session_id":null,"window_tokens":200000,"used_tokens_est":14000,"utilization":0.07,"estimate_source":"host","zone":"green","tool_result_share_est":0,"compaction_count":0,"externalize_age_turns":0,"budget":{"ceiling_tokens":null,"spent_tokens_est":14000},"updated_at":"2026-07-12T00:00:00Z"}
"session_id":"sl-abcdefgh-1234-5678-90ab-cdef01234567","window_tokens":200000,"used_tokens_est":114000,"utilization":0.57,"estimate_source":"host","zone":"amber","tool_result_share_est":0.1,"compaction_count":0,"externalize_age_turns":0,"budget":{"ceiling_tokens":null,"spent_tokens_est":114000},"updated_at":"2026-07-12T00:00:05Z"}
EOF
  # Sanity: the seeded fixture really is invalid JSON (the bug's precondition).
  run jq empty .eidolons/.context/meter.json
  [ "$status" -ne 0 ]

  run eidolons context status --used-percentage 34
  [ "$status" -eq 0 ]

  run jq empty .eidolons/.context/meter.json
  [ "$status" -eq 0 ]
  run jq -r '.zone' .eidolons/.context/meter.json
  [ "$status" -eq 0 ]
  [ "$output" = "green" ]
}

# ─── AC-1: status writes meter.json with a zone field, exit 0 ───────────────

@test "status_writes_meter_and_zone" {
  printf '%s' "some transcript content for the bytes heuristic" > transcript.jsonl
  run eidolons context status --transcript transcript.jsonl
  [ "$status" -eq 0 ]
  [ -f .eidolons/.context/meter.json ]
  run jq -e 'has("zone")' .eidolons/.context/meter.json
  [ "$status" -eq 0 ]
}

# ─── AC-2: policy --json is deterministic (same meter in, same verdict out) ─

@test "policy_is_deterministic" {
  mkdir -p .eidolons/.context
  cat > .eidolons/.context/meter.json <<'EOF'
{"ecm_version":"0.1","zone":"amber","compaction_count":0,"tool_result_share_est":0.10,"budget":{"ceiling_tokens":null,"spent_tokens_est":100}}
EOF
  run eidolons context policy --json
  [ "$status" -eq 0 ]
  first="$output"
  run eidolons context policy --json
  [ "$status" -eq 0 ]
  second="$output"
  [ "$first" = "$second" ]
  op1="$(jq -r '.operation' <<< "$first")"
  op2="$(jq -r '.operation' <<< "$second")"
  [ "$op1" = "$op2" ]
  [ "$op1" = "externalize" ]  # zone=amber, tool_result_share < 0.40 -> P6
}

# ─── AC-3: externalize writes file-floor manifest when crystalium absent ────

@test "externalize_file_floor_when_crystalium_absent" {
  # No .mcp.json / eidolons.mcp.lock -> memory_probe_gated_in fails.
  # --separate-stderr: the warn() line goes to stderr, keeping $output pure JSON.
  run --separate-stderr eidolons context externalize --summary "checkpoint before compaction" --json
  [ "$status" -eq 0 ]
  gated="$(jq -r '.gated_in' <<< "$output")"
  [ "$gated" = "false" ]
  floor_path="$(jq -r '.file_floor_path' <<< "$output")"
  [ "$floor_path" != "null" ]
  [ -f "$floor_path" ]
  run jq -e '.summary == "checkpoint before compaction"' "$floor_path"
  [ "$status" -eq 0 ]
}

# ─── AC-5: harness install writes ECM recipes idempotently ──────────────────

@test "harness_install_idempotent" {
  seed_manifest_ecm_on
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]
  [ -f .claude/settings.json ]
  [ -f .eidolons/harness/hooks/claude-code-PostToolUse.sh ]

  settings1="$(jq -cS . .claude/settings.json)"
  lock1="$(cat eidolons.lock)"
  shim1_sum="$(context_sha256_of .eidolons/harness/hooks/claude-code-PostToolUse.sh)"

  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]

  settings2="$(jq -cS . .claude/settings.json)"
  lock2="$(cat eidolons.lock)"
  shim2_sum="$(context_sha256_of .eidolons/harness/hooks/claude-code-PostToolUse.sh)"

  [ "$settings1" = "$settings2" ]
  [ "$lock1" = "$lock2" ]
  [ "$shim1_sum" = "$shim2_sum" ]
}

# local helper (defined after use is fine in bash; kept near its single caller)
context_sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# ─── AC-6: D1 rung-1 host telemetry preferred over bytes/4 estimation ───────

@test "meter_prefers_host_telemetry" {
  printf '%s' "some transcript content" > transcript.jsonl
  run eidolons context status --used-percentage 42 --transcript transcript.jsonl --json
  [ "$status" -eq 0 ]
  src="$(jq -r '.estimate_source' <<< "$output")"
  [ "$src" = "host" ]
  util="$(jq -r '.utilization' <<< "$output")"
  [ "$util" = "0.420000" ]
}

# ─── AC-7: D1 rung-3 unknown -> policy continue (fail-open floor) ───────────

@test "meter_fail_open_unknown" {
  run eidolons context status --json
  [ "$status" -eq 0 ]
  zone="$(jq -r '.zone' <<< "$output")"
  [ "$zone" = "unknown" ]

  run eidolons context policy --json
  [ "$status" -eq 0 ]
  op="$(jq -r '.operation' <<< "$output")"
  [ "$op" = "continue" ]
}

# ─── AC-8: brief over the 1500-token advisory target is logged, never truncated

@test "brief_advisory_target_never_truncates" {
  big="$(python3 -c "print('lorem ipsum dolor sit amet ' * 400 + 'THE_VERY_LAST_WORD')" 2>/dev/null || perl -e 'print "lorem ipsum dolor sit amet " x 400 . "THE_VERY_LAST_WORD"')"
  # --separate-stderr: the oversize warn() line goes to stderr, keeping $output pure JSON.
  run --separate-stderr eidolons context handoff --narrative "$big" --json
  [ "$status" -eq 0 ]
  oversize="$(jq -r '.oversize' <<< "$output")"
  [ "$oversize" = "true" ]
  brief_path="$(jq -r '.brief_path' <<< "$output")"
  [ -f "$brief_path" ]
  # Never truncated: the last word of the oversized narrative survives verbatim.
  grep -q "THE_VERY_LAST_WORD" "$brief_path"
  # The oversize event was logged to the policy log, not silently dropped.
  grep -q '"event":"handoff_brief_oversize"' .eidolons/.context/policy-log.jsonl
}

# ─── AC-10: D6 don't-clobber an existing non-75 compactThreshold ────────────

@test "compactthreshold_dont_clobber" {
  seed_manifest_ecm_on
  seed_lock
  mkdir -p .claude
  printf '{"compactThreshold": 42}\n' > .claude/settings.json
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]
  val="$(jq -r '.compactThreshold' .claude/settings.json)"
  [ "$val" = "42" ]
  managed="$(yaml_to_json_local eidolons.lock | jq -r '.context.compactthreshold_managed')"
  [ "$managed" = "false" ]
}

yaml_to_json_local() {
  yq -o=json eval '.' "$1" 2>/dev/null || yq . "$1"
}

# ─── AC-11: D6 absent compactThreshold -> write 75, managed=true in lock ────

@test "compactthreshold_written_when_absent" {
  seed_manifest_ecm_on
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]
  val="$(jq -r '.compactThreshold' .claude/settings.json)"
  [ "$val" = "75" ]
  managed="$(yaml_to_json_local eidolons.lock | jq -r '.context.compactthreshold_managed')"
  [ "$managed" = "true" ]
}

# ─── AC-12: C-4 UserPromptSubmit injected artifact <= 200 tokens ────────────

@test "ups_inject_within_200_tokens" {
  seed_manifest_ecm_on
  setup_fake_eidolons_bin
  # A readable transcript gives the meter a real (non-unknown) zone.
  dd if=/dev/zero of=transcript.jsonl bs=1 count=400000 2>/dev/null
  stdin_json="$(jq -n --arg p "implement the authentication flow" --arg tp "$PWD/transcript.jsonl" '{prompt:$p, transcript_path:$tp}')"
  run bash -c "printf '%s' '$stdin_json' | '$EIDOLONS_ROOT/cli/eidolons' run --hook claude-code --stdin"
  [ "$status" -eq 0 ]
  if [[ -n "$output" ]]; then
    ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<< "$output")"
    [[ "$ctx" == *"Context: zone="* ]] || return 1
    line="$(printf '%s' "$ctx" | grep -o 'Context: zone=[^.]*\.' | head -1)"
    len="$(printf '%s' "$line" | wc -m | tr -d ' ')"
    [ "$len" -le 800 ]
  fi
}

# ─── AC-13: D3 subagent remaps handoff_fresh -> finish_and_return ───────────

@test "subagent_remaps_handoff_fresh" {
  mkdir -p .eidolons/.context
  cat > .eidolons/.context/meter-sub1.json <<'EOF'
{"ecm_version":"0.1","zone":"critical","compaction_count":0,"tool_result_share_est":0,"budget":{"ceiling_tokens":null,"spent_tokens_est":0}}
EOF
  run eidolons context policy --session-id sub1 --subagent --json
  [ "$status" -eq 0 ]
  op="$(jq -r '.operation' <<< "$output")"
  raw="$(jq -r '.raw_operation' <<< "$output")"
  [ "$raw" = "handoff_fresh" ]
  [ "$op" = "finish_and_return" ]
}

# ─── AC-14: D3 budget-ledger is append-only JSONL, never rewritten in place ─

@test "budget_ledger_is_append_only" {
  run eidolons context externalize --summary "first checkpoint" --json
  [ "$status" -eq 0 ]
  [ "$(wc -l < .eidolons/.context/budget-ledger.jsonl | tr -d ' ')" -eq 1 ]
  first_line="$(head -1 .eidolons/.context/budget-ledger.jsonl)"

  run eidolons context externalize --summary "second checkpoint" --json
  [ "$status" -eq 0 ]
  [ "$(wc -l < .eidolons/.context/budget-ledger.jsonl | tr -d ' ')" -eq 2 ]
  # The first line is untouched (append-only, never rewritten in place).
  [ "$(head -1 .eidolons/.context/budget-ledger.jsonl)" = "$first_line" ]
}

# ─── AC-15: opt-in — eidolons.yaml with no context block => ECM off ─────────

@test "ecm_opt_in_absent_block" {
  seed_manifest   # no 'context:' block
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]
  # No ECM artifacts written when the project never opted in.
  [ ! -f .eidolons/harness/hooks/claude-code-PostToolUse.sh ]
  if [ -f .claude/settings.json ]; then
    run jq -e 'has("compactThreshold")' .claude/settings.json
    [ "$status" -ne 0 ]
  fi
  run yaml_to_json_local eidolons.lock
  [ "$status" -eq 0 ]
  run bash -c "yaml_to_json_local eidolons.lock | jq -e 'has(\"context\")'"
  [ "$status" -ne 0 ]
}

# ─── AC-16: D5 crystalium_ingest is canonical, no commit fallback branch ────

@test "handoff_ingest_is_canonical" {
  seed_mcp_crystalium_local
  setup_fake_docker_argv_log
  run eidolons context handoff --task-state "shipping ECM P1" --json
  [ "$status" -eq 0 ]
  gated="$(jq -r '.gated_in' <<< "$output")"
  [ "$gated" = "true" ]
  attempted="$(jq -r '.ingest_attempted' <<< "$output")"
  ok="$(jq -r '.ingest_ok' <<< "$output")"
  [ "$attempted" = "true" ]
  [ "$ok" = "true" ]
  # The one-shot docker invocation used 'ingest' — and NEVER 'commit' (AC-16:
  # no commit-fallback branch for the handoff artifact).
  grep -q ' ingest ' "$FAKE_DOCKER_ARGV_LOG"
  ! grep -qE '(^| )commit( |$)' "$FAKE_DOCKER_ARGV_LOG"
}

# ─── AC-17: GAP-003 — eidolons.lock context block covered by the schema ─────

@test "lock_schema_covers_context" {
  run jq -e '.properties.context.properties | keys | length > 0' \
    "$EIDOLONS_ROOT/schemas/eidolons.lock.schema.json"
  [ "$status" -eq 0 ]

  seed_manifest_ecm_on
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]

  # Every key the installer wrote under context: must be a declared schema
  # property (structural coverage check — mirrors 'make schema's jq-based
  # parse-and-shape checks; this repo has no full JSON-Schema validator wired).
  written_keys="$(yaml_to_json_local eidolons.lock | jq -r '.context | keys[]' | sort)"
  schema_keys="$(jq -r '.properties.context.properties | keys[]' "$EIDOLONS_ROOT/schemas/eidolons.lock.schema.json" | sort)"
  for k in $written_keys; do
    printf '%s\n' "$schema_keys" | grep -qx "$k" || { echo "undeclared key: $k"; return 1; }
  done
}

# ═══════════════════════════════════════════════════════════════════════════
# ECM P2 — Host-Adapter Recipes (.spectra/changes/ecm-p2-host-adapters,
# acceptance-criteria.md SHA 629b0f10…). Tracks A–G only; Track H is RETIRED.
#
# This file keeps the "run --hook <host>" / kernel-behavior style ACs (the
# SAME style as AC-12's UPS parity test above). Host-install-WIRING ACs
# (hooks.json shape, marker-block files, removal, lock schema keys) live in
# harness.bats, matching that file's existing host-adapter convention.
# ═══════════════════════════════════════════════════════════════════════════

# seed_cortex_min — minimal cortex EIDOLONS.md (local per FINDING-031; harness.bats
# has its own identical 'seed_cortex' helper that bats does not let us share).
seed_cortex_min() {
  mkdir -p .eidolons/cortex
  cat > .eidolons/cortex/EIDOLONS.md <<'EOF'
# Eidolons Routing Cortex

## Roster Index (always-loaded)

| Eidolon | Role |
|---------|------|
| ATLAS   | scout |

## Dispatch Protocol (always-loaded)

Route all non-trivial work through the Eidolons pipeline.
EOF
}

# ─── AC-CDX-3: codex PostToolUse envelope shape parity with claude-code ─────

@test "AC-CDX-3: codex post-tool-use emits the same hookSpecificOutput PostToolUse envelope" {
  seed_manifest_ecm_on
  setup_fake_eidolons_bin
  mkdir -p .eidolons/.context
  cat > .eidolons/.context/meter.json <<'EOF'
{"ecm_version":"0.1","zone":"green","compaction_count":0,"tool_result_share_est":0,"budget":{"ceiling_tokens":null,"spent_tokens_est":0}}
EOF
  # A used_percentage of 60 crosses green -> amber (amber threshold 0.50),
  # a genuine zone transition (harness_hook.sh only injects on transition).
  stdin_json="$(jq -n '{context_window:{used_percentage:60}}')"
  run bash -c "printf '%s' '$stdin_json' | '$EIDOLONS_ROOT/cli/eidolons' run --hook codex --post-tool-use"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  ev="$(jq -r '.hookSpecificOutput.hookEventName' <<< "$output")"
  [ "$ev" = "PostToolUse" ]
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<< "$output")"
  [[ "$ctx" == *"zone changed"* ]]
}

# ─── AC-CDX-4: codex UserPromptSubmit meter/policy line parity ──────────────

@test "AC-CDX-4: codex UserPromptSubmit carries the Context: zone= meter/policy line" {
  seed_manifest_ecm_on
  setup_fake_eidolons_bin
  dd if=/dev/zero of=transcript.jsonl bs=1 count=400000 2>/dev/null
  stdin_json="$(jq -n --arg p "implement the authentication flow" --arg tp "$PWD/transcript.jsonl" '{prompt:$p, transcript_path:$tp}')"
  run bash -c "printf '%s' '$stdin_json' | '$EIDOLONS_ROOT/cli/eidolons' run --hook codex --stdin"
  [ "$status" -eq 0 ]
  # The primary failure mode this AC guards against is an EMPTY payload (the
  # meter line never injected) — that must be a hard failure, not a vacuous
  # pass. The old `if [[ -n "$output" ]]` guard let an empty $output skip
  # the assertion entirely (drift fix).
  [ -n "$output" ]
  ctx="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<< "$output")"
  [[ "$ctx" == *"Context: zone="* ]]
}

# ─── AC-CDX-5: codex SessionStart carries the "## Context policy" pins block ─

@test "AC-CDX-5: codex session-start carries the Context policy pins-and-handoff block" {
  seed_manifest_ecm_on
  seed_cortex_min
  run bash "$EIDOLONS_ROOT/cli/eidolons" run --hook codex --session-start
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<< "$output")"
  [[ "$ctx" == *"Pins (must survive"* ]]
}

# ─── AC-FO-2: zone=unknown resolves to policy=continue for ANY host ────────
# (policy has no host parameter at all — this is a HOST-AGNOSTIC guarantee,
# proven once here explicitly; AC-7 above already exercises the same code
# path incidentally).

@test "AC-FO-2: unknown zone resolves to continue regardless of which host asks" {
  mkdir -p .eidolons/.context
  cat > .eidolons/.context/meter.json <<'EOF'
{"ecm_version":"0.1","zone":"unknown","compaction_count":0,"tool_result_share_est":0,"budget":{"ceiling_tokens":null,"spent_tokens_est":0}}
EOF
  run eidolons context policy --json
  [ "$status" -eq 0 ]
  op="$(jq -r '.operation' <<< "$output")"
  [ "$op" = "continue" ]
}

# ─── AC-LK-3: schema validates both a P1 lock and a P2-augmented lock ──────

@test "AC-LK-3: eidolons.lock.schema.json validates a P1 lock and a P2 lock" {
  run jq empty "$EIDOLONS_ROOT/schemas/eidolons.lock.schema.json"
  [ "$status" -eq 0 ]

  # P1 lock fixture (context: present, no per_host / codex_autocompact_managed).
  seed_lock_with_context
  p1_keys="$(yaml_to_json_local eidolons.lock | jq -r '.context | keys[]' | sort)"
  schema_keys="$(jq -r '.properties.context.properties | keys[]' "$EIDOLONS_ROOT/schemas/eidolons.lock.schema.json" | sort)"
  for k in $p1_keys; do
    printf '%s\n' "$schema_keys" | grep -qx "$k" || { echo "P1 lock: undeclared key $k"; return 1; }
  done

  # P2 lock fixture (adds per_host + codex_autocompact_managed via a live install).
  seed_manifest_ecm_on
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code, codex]
context:
  enabled: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  run eidolons harness install --hosts claude-code,codex
  [ "$status" -eq 0 ]
  p2_keys="$(yaml_to_json_local eidolons.lock | jq -r '.context | keys[]' | sort)"
  for k in $p2_keys; do
    printf '%s\n' "$schema_keys" | grep -qx "$k" || { echo "P2 lock: undeclared key $k"; return 1; }
  done
  lock_json="$(yaml_to_json_local eidolons.lock)"
  run jq -e '.context.per_host.codex.tier == "T3"' <<< "$lock_json"
  [ "$status" -eq 0 ]
  run jq -e '.context.codex_autocompact_managed | type == "boolean"' <<< "$lock_json"
  [ "$status" -eq 0 ]
}

# ─── Drift-fence guard: a claude-code-only install is unaffected by P2 ─────
# (spec.md drift fence: "a harness install --hosts claude-code run must
# produce BYTE-IDENTICAL output before and after your change"). This asserts
# the STRUCTURAL half of that guarantee — no P2 host artifact leaks into a
# claude-code-only project — while AC-5's existing idempotency test above
# (harness_install_idempotent, unmodified by this change) proves the P1
# claude-code shape itself did not shift.

@test "AC-DRIFT-1: claude-code-only ECM install writes no codex/opencode/copilot/cursor artifacts" {
  seed_manifest_ecm_on
  seed_lock
  run eidolons harness install --hosts claude-code
  [ "$status" -eq 0 ]

  [ ! -d ".codex" ]
  [ ! -d ".opencode" ]
  [ ! -f ".github/copilot-instructions.md" ]
  [ ! -d ".cursor" ]

  # .claude/settings.json keeps exactly its P1 hooks shape (no stray keys).
  run jq -r '.hooks | keys | sort | join(",")' .claude/settings.json
  [ "$status" -eq 0 ]
  [ "$output" = "PostToolUse,SessionStart,UserPromptSubmit" ]

  # per_host in the lock has ONLY claude-code — no phantom hosts.
  run jq -r '.context.per_host | keys | join(",")' <<< "$(yaml_to_json_local eidolons.lock)"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-code" ]
}

# ─── fix-ecm-meter-hot-path-spawns: CC3 prompt-path budget (<= 300ms) ───────
#
# The meter is fed on EVERY statusline render (refreshInterval 2s) and every
# UserPromptSubmit, so each fork on this path is paid constantly — and fork/exec
# is dear on macOS, where the 300ms budget (AC-SL-6) actually binds. The first
# cut of the atomicity fix took the path from 4 spawns to 7 (jq empty + 3x jq -r
# + jq -n + mktemp + mv) and tipped AC-SL-6 red on macos-latest CI.
#
# Wall-clock is the wrong gate here — it is exactly what flaked. SPAWN COUNT is
# the deterministic invariant, so that is what we pin. A counting shim wraps the
# real binary and tallies invocations.

_spawn_counter_shim() {   # $1=binary name, $2=tally file
  local d="$BATS_TEST_TMPDIR/shimbin"
  mkdir -p "$d"
  local real; real="$(command -v "$1")"
  cat > "$d/$1" <<SHIM
#!/usr/bin/env bash
echo "$1" >> "$2"
exec "$real" "\$@"
SHIM
  chmod +x "$d/$1"
  export PATH="$d:$PATH"
}

@test "fix-ecm-meter-hot-path-spawns: meter write costs <= 2 jq spawns (was 4)" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .eidolons/.context
  local tally="$BATS_TEST_TMPDIR/jq.tally"

  # Seed a valid prior meter FIRST (un-shimmed), so the run under test takes the
  # expensive inherit-prior-meter path — the path that actually runs in a session.
  run bash "$EIDOLONS_ROOT/cli/src/context_status.sh" --used-percentage 30 --window-tokens 1000000
  [ "$status" -eq 0 ]
  jq empty .eidolons/.context/meter.json

  : > "$tally"
  _spawn_counter_shim jq "$tally"
  run bash "$EIDOLONS_ROOT/cli/src/context_status.sh" --used-percentage 31 --window-tokens 1000000
  [ "$status" -eq 0 ]

  # 1 to read+validate the prior meter, 1 to compose the new one. No more.
  local n; n="$(wc -l < "$tally" | tr -d ' ')"
  echo "jq spawns: $n" >&3
  [ "$n" -le 2 ]

  # and the meter is still correct
  jq empty .eidolons/.context/meter.json
  [ "$(jq -r .zone .eidolons/.context/meter.json)" = "green" ]
}

@test "fix-ecm-meter-hot-path-spawns: meter write adds no mktemp/dirname fork over the bootstrap floor" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .eidolons/.context
  local tally="$BATS_TEST_TMPDIR/fork.tally"
  : > "$tally"
  _spawn_counter_shim mktemp "$tally"
  _spawn_counter_shim dirname "$tally"

  run bash "$EIDOLONS_ROOT/cli/src/context_status.sh" --used-percentage 30 --window-tokens 1000000
  [ "$status" -eq 0 ]
  jq empty .eidolons/.context/meter.json

  # The floor is NOT zero: `dirname` is forked 4x at bootstrap, before any meter
  # work — SELF_DIR resolution in context_status.sh, plus lib.sh sourcing its ui/
  # modules. That floor is pre-existing and out of scope here. What this gate pins
  # is that the meter WRITE adds nothing on top of it: parameter expansion
  # (${METER_PATH%/*}) and $$ replace the `dirname` and `mktemp` the first cut of
  # the atomicity fix introduced. Measured: v2.9.1 = 4/0, first cut = 5/1 (the
  # regression), this = 4/0.
  local n_dirname n_mktemp
  n_dirname="$(grep -c '^dirname$' "$tally" 2>/dev/null || true)"; : "${n_dirname:=0}"
  n_mktemp="$(grep -c '^mktemp$' "$tally" 2>/dev/null || true)";  : "${n_mktemp:=0}"
  echo "dirname=$n_dirname mktemp=$n_mktemp" >&3
  [ "$n_mktemp" -eq 0 ]
  [ "$n_dirname" -le 4 ]
}
