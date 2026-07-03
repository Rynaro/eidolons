#!/usr/bin/env bats
#
# cli/tests/memory.bats — coverage for 'eidolons memory preflight' (R27/R29).
#
# Uses fake docker PATH stub; tests TTL cache hit/expiry, --no-cache,
# timeout kill, absent crystalium, absent docker, digest format, and
# docker arg transformation.
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Seed a .mcp.json with a crystalium entry that mirrors the real structure.
seed_mcp_with_crystalium() {
  cat > .mcp.json <<'JSON'
{
  "mcpServers": {
    "crystalium": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "--name",
        "crystalium-test-project",
        "--label",
        "eidolons.project=test-project",
        "-v",
        "/Users/test/.crystalium/test-project:/root/.crystalium/test-project",
        "-e",
        "CRYSTALIUM_DATA_DIR=/root/.crystalium/test-project",
        "-e",
        "CRYSTALIUM_CALLER_TIER=T1",
        "--cap-drop",
        "ALL",
        "--security-opt",
        "no-new-privileges",
        "ghcr.io/rynaro/crystalium@sha256:9f49f98bdb8a6628fec92d554a34680edc32c4034e293512dcc1004486252894",
        "python",
        "-m",
        "crystalium",
        "serve"
      ]
    }
  }
}
JSON
}

# Seed an eidolons.mcp.lock with a crystalium entry.
seed_mcp_lock_with_crystalium() {
  cat > eidolons.mcp.lock <<'LOCK'
generated_at: "2026-06-11T00:00:00Z"
eidolons_cli_version: "1.36.0"
catalogue_version: "1.2"
mcps:
  - name: crystalium
    kind: oci-image
    version: "1.3.0"
    source:
      image: "ghcr.io/rynaro/crystalium"
    integrity:
      algo: oci-digest
      value: "sha256:9f49f98bdb8a6628fec92d554a34680edc32c4034e293512dcc1004486252894"
    target: ".mcp.json"
    installed_at: "2026-06-11T00:00:00Z"
LOCK
}

# A valid RecallResult JSON with one record.
VALID_RECALL_JSON='{"records":[{"id":"c1","layer":"semantic","trust_tier":"T1","summary":"Prior spec: harness mechanization shipped v1.36.0","validation_state":"valid","importance":0.8,"last_access":"2026-06-11T00:00:00Z","content_ref":null,"score":0.9}],"slot_breakdown":{"semantic":1},"total_tokens":42,"evicted_count":0}'

# Setup a fake docker that prints a valid RecallResult JSON when invoked.
setup_fake_docker_recall() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  # The FAKE_DOCKER_OUTPUT env var controls what the fake docker prints.
  cat > "$fake_bin/docker" <<DSHIM
#!/usr/bin/env bash
OUTPUT="\${FAKE_DOCKER_OUTPUT:-}"
ARGV_LOG="\${FAKE_DOCKER_ARGV_LOG:-}"
SLEEP_SEC="\${FAKE_DOCKER_SLEEP:-0}"
[ -n "\$ARGV_LOG" ] && printf '%s\n' "\$*" >> "\$ARGV_LOG"
if [ "\$SLEEP_SEC" != "0" ]; then
  sleep "\$SLEEP_SEC"
fi
if [ -n "\$OUTPUT" ]; then
  printf '%s\n' "\$OUTPUT"
  exit 0
fi
exit 1
DSHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"
}

# ─── R6-style dispatcher tests ────────────────────────────────────────────────

@test "memory: dispatcher routes 'memory preflight' (--help exit 0)" {
  seed_manifest
  run eidolons memory preflight --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "preflight" ]]
}

@test "memory: unknown subcommand exits 2" {
  seed_manifest
  run eidolons memory bogus
  [ "$status" -eq 2 ]
  [[ "$output" =~ "Unknown memory subcommand" ]]
  [[ "$output" =~ "Available: preflight" ]]
}

@test "memory: bare 'eidolons memory' shows help and exits 0" {
  seed_manifest
  run eidolons memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ "preflight" ]]
}

# ─── AC-R27-1: crystalium absent → empty stdout exit 0 ───────────────────────

@test "memory: crystalium absent from .mcp.json -> empty stdout exit 0" {
  seed_manifest
  # .mcp.json exists but no crystalium entry.
  printf '{"mcpServers":{"junction":{"command":"junction","args":[]}}}\n' > .mcp.json
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  # EIDOLONS_QUIET=1 silences info() to keep stdout clean for assertion.
  run env EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "memory: crystalium absent from eidolons.mcp.lock -> empty stdout exit 0" {
  seed_manifest
  seed_mcp_with_crystalium
  # Lock has no crystalium entry.
  cat > eidolons.mcp.lock <<'LOCK'
generated_at: "2026-06-11T00:00:00Z"
mcps:
  - name: junction
    kind: binary
    version: "0.3.0"
LOCK
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  run env EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "memory: no .mcp.json at all -> empty stdout exit 0" {
  seed_manifest
  # No .mcp.json written.
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  run env EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── AC-R27-2: docker absent → empty stdout exit 0 ───────────────────────────

@test "memory: docker absent from PATH -> empty stdout exit 0" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  # Shadow docker with a non-existent path so command -v docker fails.
  # We create a PATH where the first entry is a dir with NO docker binary.
  # The remaining PATH entries keep bash/jq/etc. but if docker was in them,
  # we place a shadow directory BEFORE them. Since we can't know all paths,
  # we explicitly hide docker by placing a non-executable 'docker' file
  # at the front of PATH — command -v skips non-executable files.
  local shadow_bin="$BATS_TEST_TMPDIR/shadow-bin"
  mkdir -p "$shadow_bin"
  # Create a non-executable 'docker' placeholder: command -v will not report it.
  printf '#!/usr/bin/env bash\n' > "$shadow_bin/docker"
  # Not chmod +x → not executable → command -v docker ignores it.
  run env PATH="$shadow_bin:$PATH" EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── AC-R27-3: fake docker valid JSON → digest ────────────────────────────────

@test "memory: fake docker valid JSON -> [layer/tier] summary digest" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --no-cache
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Digest must match [layer/tier] summary format.
  [[ "$output" =~ "[semantic/T1]" ]]
  [[ "$output" =~ "Prior spec: harness mechanization shipped v1.36.0" ]]
}

# ─── AC-R27-4: malformed JSON → empty stdout ──────────────────────────────────

@test "memory: malformed JSON from docker -> empty stdout exit 0" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="this is not json {"
  run env EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --no-cache
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── AC-R27-5: cache hit within TTL skips docker ─────────────────────────────

@test "memory: cache hit within TTL skips docker" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  # Compute the same slug the preflight would use.
  _slug="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
  _query="project ${_slug} recent context"
  # Seed a fresh cache file.
  mkdir -p .eidolons/harness/cache
  _now="$(date +%s)"
  _digest_str="[semantic/T1] cached summary"
  _digest_json="$(printf '%s' "$_digest_str" | jq -Rs '.')"
  _query_json="$(printf '%s' "$_query" | jq -Rs '.')"
  printf '{"cached_at":%s,"query":%s,"digest":%s}\n' \
    "$_now" "$_query_json" "$_digest_json" > .eidolons/harness/cache/preflight.json

  # Set up a sentinel to detect if docker was called.
  local argv_log="$BATS_TEST_TMPDIR/docker-argv.log"
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  export FAKE_DOCKER_ARGV_LOG="$argv_log"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" =~ "cached summary" ]]
  # Docker must NOT have been called.
  [ ! -f "$argv_log" ]
}

# ─── AC-R27-6: cache expiry reruns docker ────────────────────────────────────

@test "memory: cache older than TTL -> docker called, cache rewritten" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  _slug="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
  _query="project ${_slug} recent context"
  # Seed a stale cache (timestamp 0 = epoch, definitely expired).
  mkdir -p .eidolons/harness/cache
  _query_json="$(printf '%s' "$_query" | jq -Rs '.')"
  printf '{"cached_at":0,"query":%s,"digest":"[old/T0] old summary"}\n' \
    "$_query_json" > .eidolons/harness/cache/preflight.json

  local argv_log="$BATS_TEST_TMPDIR/docker-argv.log"
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  export FAKE_DOCKER_ARGV_LOG="$argv_log"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Must show fresh result (not old cached summary).
  [[ "$output" =~ "Prior spec: harness mechanization shipped v1.36.0" ]]
  # Docker must have been called.
  [ -f "$argv_log" ]
  # Cache must have been rewritten with new content.
  _new_digest="$(jq -r '.digest' .eidolons/harness/cache/preflight.json)"
  [[ "$_new_digest" =~ "Prior spec" ]]
}

# ─── AC-R27-7: --no-cache bypasses read and write ────────────────────────────

@test "memory: --no-cache bypasses cache (docker called; no cache write)" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  _slug="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
  _query="project ${_slug} recent context"
  # Seed a fresh cache that would normally be a HIT.
  mkdir -p .eidolons/harness/cache
  _now="$(date +%s)"
  _query_json="$(printf '%s' "$_query" | jq -Rs '.')"
  printf '{"cached_at":%s,"query":%s,"digest":"[cached/T0] should not appear"}\n' \
    "$_now" "$_query_json" > .eidolons/harness/cache/preflight.json

  local argv_log="$BATS_TEST_TMPDIR/docker-argv.log"
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  export FAKE_DOCKER_ARGV_LOG="$argv_log"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --no-cache
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Must show live result, not the cached string.
  ! [[ "$output" =~ "should not appear" ]]
  # Docker must have been called.
  [ -f "$argv_log" ]
  # Cache must NOT have been rewritten (same content as before).
  _cache_digest="$(jq -r '.digest' .eidolons/harness/cache/preflight.json)"
  [[ "$_cache_digest" == "[cached/T0] should not appear" ]]
}

# ─── AC-R27-8: timeout kills slow docker ─────────────────────────────────────

@test "memory: --timeout kills slow docker -> empty stdout exit 0 within ~3s" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium

  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/docker" <<'DSHIM'
#!/usr/bin/env bash
sleep 5
printf 'this should not appear\n'
DSHIM
  chmod +x "$fake_bin/docker"
  export PATH="$fake_bin:$PATH"

  _start="$(date +%s)"
  run env EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --timeout 1 --no-cache
  _end="$(date +%s)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Must have returned within ~3 seconds (timeout=1 + overhead).
  _elapsed=$(( _end - _start ))
  [ "$_elapsed" -lt 4 ]
}

# ─── AC-R27-9: docker args strip -i and --name, end with recall ──────────────

@test "memory: docker args strip -i and --name; end with recall subcommand" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium

  local argv_log="$BATS_TEST_TMPDIR/docker-argv.log"
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"
  export FAKE_DOCKER_ARGV_LOG="$argv_log"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --no-cache
  [ "$status" -eq 0 ]
  [ -f "$argv_log" ]
  _argv="$(cat "$argv_log")"

  # ── PREFIX shape: argv must begin "run --rm" (not "run run --rm") ──────────
  # The fake docker receives $* so word 1 must be "run" and word 2 must be "--rm".
  # This pins against the doubled-run bug where the header hardcoded "exec docker run"
  # while args already started with "run".
  _first_word="$(printf '%s' "$_argv" | awk '{print $1}')"
  _second_word="$(printf '%s' "$_argv" | awk '{print $2}')"
  [ "$_first_word" = "run" ]
  [ "$_second_word" = "--rm" ]

  # ── Negative assertions with position awareness ────────────────────────────
  # Must NOT contain bare -i flag (standalone, not part of another flag).
  ! printf '%s' "$_argv" | grep -qE '(^| )-i( |$)'
  # Must NOT contain --name (which would be followed by the serve container name).
  ! printf '%s' "$_argv" | grep -q -- '--name'
  # Must NOT contain "serve" (replaced by recall subcommand).
  ! [[ "$_argv" =~ " serve" ]]

  # ── Must contain recall subcommand and flags ───────────────────────────────
  [[ "$_argv" =~ "recall" ]]
  [[ "$_argv" =~ "--format" ]]
  [[ "$_argv" =~ "json" ]]
  [[ "$_argv" =~ "--scope-project" ]]
  [[ "$_argv" =~ "--query" ]]
}

# ─── digest format + 1500-char cap ────────────────────────────────────────────

@test "memory: digest format is [layer/tier] summary; <=1500 chars" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  # JSON with a long summary (>1500 chars worth of records).
  _long_summary="$(printf '%0.s x' $(seq 1 200))"
  _many_records='{"records":['
  for _i in $(seq 1 5); do
    [ "$_i" -gt 1 ] && _many_records="${_many_records},"
    _many_records="${_many_records}{\"id\":\"c${_i}\",\"layer\":\"semantic\",\"trust_tier\":\"T1\",\"summary\":\"${_long_summary}\",\"validation_state\":\"valid\",\"importance\":0.5,\"last_access\":\"2026-06-11T00:00:00Z\",\"content_ref\":null,\"score\":0.9}"
  done
  _many_records="${_many_records}]}"
  # Quick check: the JSON is valid.
  printf '%s' "$_many_records" | jq empty
  export FAKE_DOCKER_OUTPUT="$_many_records"
  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --no-cache
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Must match [layer/tier] format on first line.
  _first_line="$(printf '%s' "$output" | head -1)"
  [[ "$_first_line" =~ ^\[semantic/T1\] ]]
  # Must be <=1500 chars.
  _len="${#output}"
  [ "$_len" -le 1500 ]
}

# ─── empty records → empty stdout ─────────────────────────────────────────────

@test "memory: empty records in RecallResult -> empty stdout exit 0" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT='{"records":[],"slot_breakdown":{},"total_tokens":0,"evicted_count":0}'
  run env EIDOLONS_QUIET=1 bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --no-cache
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── --explain: human diagnostic report (GAP: silent-empty-recall incident) ──

@test "memory: --explain prints gate/cache/invocation/exit-code/records/total_tokens fields" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --explain
  [ "$status" -eq 0 ]

  # Gate status.
  [[ "$output" =~ "Gate:" ]]
  [[ "$output" =~ ".mcp.json has mcpServers.crystalium     PASS" ]]
  [[ "$output" =~ "eidolons.mcp.lock has crystalium entry  PASS" ]]

  # Cache status (informational).
  [[ "$output" =~ "Cache:" ]]
  [[ "$output" =~ "status  MISS" ]]

  # Resolved docker invocation (redacted nothing — must show the real args).
  [[ "$output" =~ "Resolved invocation:" ]]
  [[ "$output" =~ "recall" ]]
  [[ "$output" =~ "--scope-project" ]]

  # Recall outcome: exit code, records, total_tokens, scope/layers used.
  [[ "$output" =~ "Recall:" ]]
  [[ "$output" =~ "exit code      0" ]]
  [[ "$output" =~ "records        1" ]]
  [[ "$output" =~ "total_tokens   42" ]]
  [[ "$output" =~ "scope.project" ]]
  [[ "$output" =~ "layers" ]]
}

@test "memory: --explain on zero-record recall prints the explicit diagnostic line" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT='{"records":[],"slot_breakdown":{},"total_tokens":0,"evicted_count":0}'

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --explain
  [ "$status" -eq 0 ]
  [[ "$output" =~ "records        0" ]]
  [[ "$output" =~ "0 records returned — store may be empty, mis-scoped, or filtered (status/scope); see crystalium recall defaults (active-only)." ]]
}

@test "memory: --explain never writes the TTL cache (pre-existing cache left untouched)" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"

  # Pre-seed a stale cache file with a sentinel digest.
  mkdir -p .eidolons/harness/cache
  printf '{"cached_at":0,"query":"sentinel","digest":"[sentinel/T0] must not change"}\n' \
    > .eidolons/harness/cache/preflight.json
  local before; before="$(cat .eidolons/harness/cache/preflight.json)"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --explain
  [ "$status" -eq 0 ]

  local after; after="$(cat .eidolons/harness/cache/preflight.json)"
  [ "$before" = "$after" ]
}

@test "memory: --explain does not create a cache file when none existed" {
  seed_manifest
  seed_mcp_with_crystalium
  seed_mcp_lock_with_crystalium
  setup_fake_docker_recall
  export FAKE_DOCKER_OUTPUT="$VALID_RECALL_JSON"

  run bash "$EIDOLONS_ROOT/cli/src/memory.sh" preflight --explain
  [ "$status" -eq 0 ]
  [ ! -f .eidolons/harness/cache/preflight.json ]
}
