#!/usr/bin/env bats

load helpers

@test "doctor: fails without eidolons.yaml" {
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ eidolons\.yaml\ missing ]]
}

@test "doctor: reports missing lock" {
  seed_manifest
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ eidolons\.lock\ missing ]]
}

@test "doctor: reports missing per-member install when .eidolons dir absent" {
  seed_manifest
  seed_lock
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ installed ]]
}

@test "doctor: reports missing host dispatch files" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  run eidolons doctor
  # manifest wires claude-code but .claude/agents/atlas.md is absent.
  [ "$status" -ne 0 ]
  [[ "$output" =~ \.claude/agents/atlas\.md\ missing|claude-code\ declared\ but ]]
}

@test "doctor: passes on a fully wired project" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  # Per-vendor self-sufficient file satisfies the claude-code host check.
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ All\ checks\ passed ]]
}

@test "doctor -h: help prints" {
  run eidolons doctor -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ doctor ]]
}

# ─── Release integrity surface (Story 5.G) ────────────────────────────────

@test "doctor: surfaces verified release integrity from lock" {
  seed_manifest
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@deadbeef"
    commit: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    tree: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    archive_sha256: ""
    manifest_sha256: ""
    verification: "verified"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Release integrity" ]]
  [[ "$output" =~ "atlas@1.0.0 release integrity verified" ]]
}

@test "doctor: surfaces legacy compatibility entries non-fatally" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "no roster release metadata (legacy)" ]]
}

@test "doctor: flags missing release integrity as error" {
  seed_manifest
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@deadbeef"
    verification: "missing"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ "MISMATCH" ]]
}

@test "doctor: codex host passes when .codex/agents/*.md present" {
  # Write a manifest wired for codex only.
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .codex/agents
  echo "---" > .codex/agents/atlas.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "codex wired (.codex/agents/*.md present)" ]]
}

@test "doctor: codex host passes via AGENTS.md shared dispatch" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  seed_agent_install_manifest atlas
  echo "# shared dispatch" > AGENTS.md
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "codex wired (AGENTS.md shared dispatch)" ]]
}

@test "doctor: codex host fails when no wiring surface found" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  seed_lock
  seed_agent_install_manifest atlas
  # No .codex/agents/ and no AGENTS.md — should fail.
  run eidolons doctor
  [ "$status" -ne 0 ]
  [[ "$output" =~ "codex declared but no .codex/agents/*.md or AGENTS.md found" ]]
}

# ─── ghcr.io registry reachability probe (T10) ────────────────────────────
#
# Fake-curl harness: a curl shim is installed into $BATS_TEST_TMPDIR/fake-bin
# and prepended to PATH before each T10 test. The shim reads control env vars
# at invocation time so per-test overrides take effect immediately.
#
# Control env-vars:
#   FAKE_CURL_TOKEN_RESULT     — "ok" (default): return {"token":"fake-tok"}
#                                "fail": exit non-zero (network error)
#   FAKE_CURL_MANIFEST_STATUS  — "200" (default): write "200" to stdout when
#                                   -w '%{http_code}' is present
#                                "404": write "404" to stdout
#                                "fail": exit non-zero (network error)
#
# The shim dispatches on whether the URL contains "token?" (step 1) or
# "manifests/" (step 2). It is Bash 3.2 compatible.
#
# A helper seed_mcp_json_ghcr writes a .mcp.json with a ghcr.io-prefixed ref
# (the shape produced by T6's template flip).

setup_fake_curl() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin-curl"
  mkdir -p "$fake_bin"

  # Fake docker shim: always responds as if docker is present, daemon is up,
  # and any image inspect succeeds. This lets Check 6 (MCP servers) pass so
  # ERRORS stays at 0 and doctor exits 0 for the probe tests.
  cat > "$fake_bin/docker" <<'DSHIM'
#!/usr/bin/env bash
set -u
subcmd="${1:-}"
case "$subcmd" in
  info)
    exit 0 ;;
  image)
    action="${2:-}"
    case "$action" in
      inspect) exit 0 ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
DSHIM
  chmod +x "$fake_bin/docker"

  cat > "$fake_bin/curl" <<'SHIM'
#!/usr/bin/env bash
# Fake curl shim for doctor T10 tests.
# Dispatches on the URL (last non-flag positional argument).
set -u

TOKEN_RESULT="${FAKE_CURL_TOKEN_RESULT:-ok}"
MANIFEST_STATUS="${FAKE_CURL_MANIFEST_STATUS:-200}"

# Parse args: collect the URL (last non-flag arg) and detect -w / -o / -s flags.
url=""
write_format=""
output_file=""
i=0
args=("$@")
while [ $i -lt ${#args[@]} ]; do
  arg="${args[$i]}"
  case "$arg" in
    -w)
      i=$((i + 1))
      write_format="${args[$i]}"
      ;;
    -o)
      i=$((i + 1))
      output_file="${args[$i]}"
      ;;
    -fsSL|-fsI|-fsSI|-fsS|-fs|-fL|-f|-s|-sS|-sL|-i|-I|-L)
      ;;
    -H)
      # Skip the header value.
      i=$((i + 1))
      ;;
    http://*|https://*)
      url="$arg"
      ;;
  esac
  i=$((i + 1))
done

# Dispatch on URL pattern.
case "$url" in
  *token?*)
    if [ "$TOKEN_RESULT" = "ok" ]; then
      printf '{"token":"fake-test-token"}'
      exit 0
    else
      exit 6
    fi
    ;;
  */manifests/*)
    if [ "$MANIFEST_STATUS" = "fail" ]; then
      exit 6
    fi
    # Honour -w '%{http_code}' — write the status code to stdout.
    if [ -n "$write_format" ]; then
      status_out="${write_format/\%\{http_code\}/$MANIFEST_STATUS}"
      printf '%s' "$status_out"
    fi
    # Honour -o /dev/null (just suppress body; already no body emitted).
    if [ "$MANIFEST_STATUS" = "200" ]; then
      exit 0
    else
      exit 22
    fi
    ;;
  *)
    # Unknown URL — fall through harmlessly.
    exit 0
    ;;
esac
SHIM

  chmod +x "$fake_bin/curl"
  export PATH="$fake_bin:$PATH"
  export BATS_TEST_TMPDIR
}

# Write a minimal .mcp.json with a ghcr.io-prefixed atlas-aci ref.
# The digest used is a recognisable test value (64 hex 'a' chars).
seed_mcp_json_ghcr() {
  local digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  cat > .mcp.json <<EOF
{
  "mcpServers": {
    "atlas-aci": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "--name",
        "atlas-aci-test",
        "ghcr.io/rynaro/atlas-aci@${digest}",
        "serve"
      ]
    }
  }
}
EOF
}

# ─── T10 test: happy path — 200 OK ────────────────────────────────────────
@test "doctor probe: atlas-aci image reachable on ghcr.io (200 OK)" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  seed_mcp_json_ghcr

  export FAKE_CURL_TOKEN_RESULT=ok
  export FAKE_CURL_MANIFEST_STATUS=200
  setup_fake_curl

  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas-aci image reachable on ghcr.io" ]]
}

# ─── T10 test: unreachable — 404 ──────────────────────────────────────────
@test "doctor probe: atlas-aci image not reachable (404 — digest yanked)" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  seed_mcp_json_ghcr

  export FAKE_CURL_TOKEN_RESULT=ok
  export FAKE_CURL_MANIFEST_STATUS=404
  setup_fake_curl

  # Probe is non-fatal — doctor should still exit 0 (no ERRORS incremented).
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas-aci image not reachable" ]]
  [[ "$output" =~ "--build-locally" ]]
}

# ─── T10 test: unreachable — network error ────────────────────────────────
@test "doctor probe: atlas-aci image not reachable (network error)" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  seed_mcp_json_ghcr

  export FAKE_CURL_TOKEN_RESULT=fail
  export FAKE_CURL_MANIFEST_STATUS=fail
  setup_fake_curl

  # Probe is non-fatal — doctor should still exit 0.
  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ "$output" =~ "atlas-aci image not reachable" ]]
  [[ "$output" =~ "--build-locally" ]]
}

# ─── T10 test: skip — no .mcp.json ────────────────────────────────────────
@test "doctor probe: skipped when no .mcp.json present" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  # No .mcp.json written.

  # Even if curl were misconfigured, doctor must still pass without
  # touching the probe code path.
  run eidolons doctor
  [ "$status" -eq 0 ]
  # The reachability section should NOT emit the pass/warn probe message.
  [[ ! "$output" =~ "atlas-aci image reachable" ]]
  [[ ! "$output" =~ "atlas-aci image not reachable" ]]
}

# ─── T10 test: skip — .mcp.json present but no atlas-aci entry ───────────
@test "doctor probe: skipped when .mcp.json has no atlas-aci entry" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  # Write a .mcp.json with a different server name (not atlas-aci).
  cat > .mcp.json <<'EOF'
{
  "mcpServers": {
    "some-other-server": {
      "command": "node",
      "args": ["server.js"]
    }
  }
}
EOF

  run eidolons doctor
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "atlas-aci image reachable" ]]
  [[ ! "$output" =~ "atlas-aci image not reachable" ]]
}

# ─── T10 test: graceful degradation — curl unavailable ───────────────────
# When curl is unavailable (either absent from PATH or failing to reach the
# network), the probe degrades gracefully: doctor still exits 0 and emits
# a non-fatal warn message. Tests 14 and 15 cover the 404 and network-error
# cases; this test covers the case where the probe itself is non-fatal by
# verifying doctor's exit code remains 0 even when the probe warns.
@test "doctor probe: probe is non-fatal — doctor exits 0 when probe warns" {
  seed_manifest
  seed_lock
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md
  seed_mcp_json_ghcr

  # Simulate curl present but token fetch fails (network unreachable).
  # This exercises the same non-fatal code path as "curl absent" from
  # doctor's perspective: _probe_rc != 0 → warn emitted → ERRORS unchanged.
  export FAKE_CURL_TOKEN_RESULT=fail
  export FAKE_CURL_MANIFEST_STATUS=fail
  setup_fake_curl

  run eidolons doctor
  # Probe is non-fatal — overall exit must be 0 (ERRORS still 0).
  [ "$status" -eq 0 ]
  # The warn message must appear (probe ran and degraded gracefully).
  [[ "$output" =~ "atlas-aci image not reachable" ]]
  [[ "$output" =~ "--build-locally" ]]
  # The pass message must NOT appear.
  [[ ! "$output" =~ "atlas-aci image reachable on ghcr.io" ]]
}
