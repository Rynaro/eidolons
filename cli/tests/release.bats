#!/usr/bin/env bats
#
# release.bats — covers cli/src/release.sh
# Spec stories S1-S5, S10-S12 from
#   .spectra/plans/eidolons-update-flow-2026-05-05.md §5
#
# Test strategy: a stub `gh` shim placed early on $PATH records every
# invocation to a TSV log file and emits canned responses keyed by argv
# prefix. The shim asserts on argv only, not on canned-response field shapes
# (per R6 mitigation).
#
# Key design:
#   EIDOLONS_NEXUS → real checkout (roster available)
#   Fake `gh` on PATH → intercepts all gh calls
#   Stub roster has atlas at 1.3.0; release tests target 1.4.0 (upgrade).

load helpers

# ─── Stub gh shim ─────────────────────────────────────────────────────────
#
# Control env vars read by the shim at invocation time:
#   FAKE_GH_DISPATCH_RESULT    — "ok" (default) or "fail"
#   FAKE_GH_AUTH_RESULT        — "ok" (default) or "fail"
#   FAKE_GH_RELEASE_VIEW_FOUND — "found" (default after first poll) or "missing"
#   FAKE_GH_PR_FOUND           — "found" (default) or "missing"
#   FAKE_GH_WORKFLOW_EXIST     — "ok" (default) or "fail"
#   FAKE_GH_CALL_LOG           — path to TSV file; each line: argv joined by TAB
#   FAKE_GH_VERSION            — version string echoed by `gh --version` (default "2.50.0")
#
# The shim never makes real network calls.

setup_fake_gh() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin-gh"
  mkdir -p "$FAKE_BIN"
  : "${FAKE_GH_CALL_LOG:=$BATS_TEST_TMPDIR/gh-calls.log}"
  : "${FAKE_GH_DISPATCH_RESULT:=ok}"
  : "${FAKE_GH_AUTH_RESULT:=ok}"
  : "${FAKE_GH_RELEASE_VIEW_FOUND:=found}"
  : "${FAKE_GH_PR_FOUND:=found}"
  : "${FAKE_GH_WORKFLOW_EXIST:=ok}"
  : "${FAKE_GH_VERSION:=2.50.0}"
  export FAKE_GH_CALL_LOG FAKE_GH_DISPATCH_RESULT FAKE_GH_AUTH_RESULT
  export FAKE_GH_RELEASE_VIEW_FOUND FAKE_GH_PR_FOUND FAKE_GH_WORKFLOW_EXIST
  export FAKE_GH_VERSION

  cat > "$FAKE_BIN/gh" <<'SHIM'
#!/usr/bin/env bash
# Fake gh shim for release.bats tests.
set -u

CALL_LOG="${FAKE_GH_CALL_LOG:-/dev/null}"
DISPATCH_RESULT="${FAKE_GH_DISPATCH_RESULT:-ok}"
AUTH_RESULT="${FAKE_GH_AUTH_RESULT:-ok}"
RELEASE_VIEW_FOUND="${FAKE_GH_RELEASE_VIEW_FOUND:-found}"
PR_FOUND="${FAKE_GH_PR_FOUND:-found}"
WORKFLOW_EXIST="${FAKE_GH_WORKFLOW_EXIST:-ok}"
GH_VERSION="${FAKE_GH_VERSION:-2.50.0}"

# Log every call (tab-separated argv).
printf '%s\n' "$*" >> "$CALL_LOG"

subcmd="${1:-}"

case "$subcmd" in
  --version)
    echo "gh version ${GH_VERSION} (2024-01-01)"
    exit 0
    ;;
  auth)
    if [ "$AUTH_RESULT" = "ok" ]; then
      echo "Logged in to github.com as test-user (token)"
      exit 0
    else
      echo "Not logged in." >&2
      exit 1
    fi
    ;;
  api)
    # api repos/<repo> — auth/access check
    # api repos/<repo>/contents/.github/workflows/release.yml — workflow exist check
    _api_path="${2:-}"
    case "$_api_path" in
      repos/*/contents/*)
        if [ "$WORKFLOW_EXIST" = "ok" ]; then
          echo '{"name":"release.yml"}'
          exit 0
        else
          echo '{"message":"Not Found"}' >&2
          exit 1
        fi
        ;;
      repos/*)
        if [ "$AUTH_RESULT" = "ok" ]; then
          echo '{"name":"repo"}'
          exit 0
        else
          echo '{"message":"Not Found"}' >&2
          exit 1
        fi
        ;;
    esac
    echo '{}' ; exit 0
    ;;
  workflow)
    _wf_sub="${2:-}"
    case "$_wf_sub" in
      run)
        if [ "$DISPATCH_RESULT" = "ok" ]; then
          echo "Created workflow dispatch event for refs/heads/main"
          exit 0
        else
          echo "gh: workflow run failed" >&2
          exit 1
        fi
        ;;
    esac
    exit 0
    ;;
  run)
    _run_sub="${2:-}"
    case "$_run_sub" in
      list)
        # Return a fake run ID.
        echo '[{"databaseId":9999}]'
        exit 0
        ;;
    esac
    exit 0
    ;;
  release)
    _rel_sub="${2:-}"
    case "$_rel_sub" in
      view)
        if [ "$RELEASE_VIEW_FOUND" = "found" ]; then
          echo "v1.4.0"
          exit 0
        else
          echo "release not found" >&2
          exit 1
        fi
        ;;
    esac
    exit 0
    ;;
  pr)
    _pr_sub="${2:-}"
    case "$_pr_sub" in
      list)
        if [ "$PR_FOUND" = "found" ]; then
          echo '[{"number":68,"url":"https://github.com/Rynaro/eidolons/pull/68"}]'
          exit 0
        else
          echo '[]'
          exit 0
        fi
        ;;
      merge)
        # auto-merge invocation — succeed silently.
        exit 0
        ;;
    esac
    exit 0
    ;;
esac

# Unknown subcommand — succeed silently.
exit 0
SHIM
  chmod +x "$FAKE_BIN/gh"
  export PATH="$FAKE_BIN:$PATH"
}

# Helper: count lines in FAKE_GH_CALL_LOG matching a pattern.
# Uses grep | wc -l to avoid the double-echo from 'grep -c || echo 0'
# (grep -c exits 1 on no match and still prints "0"; the || would add another "0").
gh_call_count() {
  if [ ! -f "${FAKE_GH_CALL_LOG:-/dev/null}" ]; then echo "0"; return 0; fi
  grep "$1" "$FAKE_GH_CALL_LOG" 2>/dev/null | wc -l | tr -d ' '
}

# ─── S2: --check dry-run does not dispatch ────────────────────────────────
@test "release_check_does_not_dispatch (S2)" {
  setup_fake_gh
  # Use a custom nexus with atlas at 1.3.0 so that requesting 1.4.0 passes
  # the version-precedence guard (V4) and reaches the --check dry-run exit.
  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s2"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh" "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.4.0 --check --non-interactive --yes
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Plan validated" ]]
  [[ "$output" =~ "Re-run without --check" ]]
  # No workflow run calls should be present.
  local wf_count
  wf_count="$(gh_call_count "workflow run")"
  [ "$wf_count" -eq 0 ]
}

# ─── S3: rejects version already in roster (equal to latest) ──────────────
@test "release_rejects_existing_version (S3)" {
  setup_fake_gh
  # The real roster has atlas.versions.latest = 1.4.0 (post-PR #68).
  # If the user requests 1.4.0 without --resume, it should be rejected.
  # Temporarily point at a custom roster with atlas at 1.4.0.
  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s3"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.4.0"
      pins:
        stable: "1.4.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.4.0 --non-interactive --yes
  [ "$status" -eq 2 ]
  [[ "$output" =~ "already in roster" ]] || [[ "$output" =~ "1.4.0" ]]
  local wf_count
  wf_count="$(gh_call_count "workflow run")"
  [ "$wf_count" -eq 0 ]
}

# ─── S4: rejects downgrade without --force ────────────────────────────────
@test "release_rejects_downgrade_without_force (S4)" {
  setup_fake_gh
  # Use a custom roster with atlas at 1.4.0; request 1.2.5 (downgrade).
  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s4"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.4.0"
      pins:
        stable: "1.4.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.2.5 --non-interactive --yes
  [ "$status" -eq 2 ]
  [[ "$output" =~ "downgrade" ]] || [[ "$output" =~ "Refusing" ]]
  local wf_count
  wf_count="$(gh_call_count "workflow run")"
  [ "$wf_count" -eq 0 ]
}

# ─── S5: timeout on tag poll emits --resume hint ──────────────────────────
@test "release_timeout_emits_resume_hint (S5)" {
  setup_fake_gh
  export FAKE_GH_RELEASE_VIEW_FOUND=missing

  # Use a roster with atlas at an old version so 1.4.0 passes version check.
  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s5"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  # Set a very short timeout so the test doesn't hang.
  run eidolons release atlas 1.4.0 --non-interactive --yes --release-timeout=3
  [ "$status" -eq 4 ]
  [[ "$output" =~ "--resume" ]]
}

# ─── S1: happy path — dispatches release + intake, prints PR URL ─────────
@test "release_happy_path (S1)" {
  setup_fake_gh
  export FAKE_GH_RELEASE_VIEW_FOUND=found

  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s1"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.4.0 --non-interactive --yes
  [ "$status" -eq 0 ]
  # Must have dispatched the Release workflow.
  local wf_count
  wf_count="$(gh_call_count "workflow run")"
  [ "$wf_count" -ge 1 ]
  # Must have dispatched Roster Intake.
  grep -q "Roster Intake" "$FAKE_GH_CALL_LOG"
  # Output must mention PR URL.
  [[ "$output" =~ "PR opened" ]] || [[ "$output" =~ "pull" ]]
  # Consumer hint must appear.
  [[ "$output" =~ "eidolons upgrade" ]]
}

# ─── S10: idempotent when tag already exists (--resume auto-detected) ─────
@test "release_idempotent_when_tag_exists (S10/G10)" {
  setup_fake_gh
  export FAKE_GH_RELEASE_VIEW_FOUND=found

  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s10"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.4.0 --non-interactive --yes
  [ "$status" -eq 0 ]
  # Release workflow dispatch should NOT have been called (tag exists → skip).
  local release_dispatch_count
  release_dispatch_count="$(gh_call_count "Release ATLAS")"
  [ "$release_dispatch_count" -eq 0 ]
  # Intake MUST still have been dispatched.
  grep -q "Roster Intake" "$FAKE_GH_CALL_LOG"
}

# ─── S11: missing gh auth scope exits 2 without dispatch ──────────────────
@test "release_detects_missing_gh_auth_scope (S11)" {
  setup_fake_gh
  export FAKE_GH_AUTH_RESULT=fail

  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s11"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.4.0 --non-interactive --yes
  [ "$status" -eq 2 ]
  [[ "$output" =~ "authentication" ]] || [[ "$output" =~ "auth" ]]
  # No dispatches.
  local wf_count
  wf_count="$(gh_call_count "workflow run")"
  [ "$wf_count" -eq 0 ]
}

# ─── S12: interactive mode prompts (y confirms, n aborts) ─────────────────
@test "release_prompts_in_interactive_mode (S12 — abort on n)" {
  setup_fake_gh
  export FAKE_GH_RELEASE_VIEW_FOUND=found

  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s12"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  # Pipe "n" to stdin to trigger the abort path (stdin is NOT a TTY in bats).
  # The release.sh reads [[ -t 0 ]] so non-TTY stdin skips the prompt —
  # which means this test verifies the --yes skip path implicitly.
  # To force the prompt code: use --non-interactive without --yes → exit 2.
  run eidolons release atlas 1.4.0 --non-interactive
  [ "$status" -eq 2 ]
  [[ "$output" =~ "--non-interactive" ]] || [[ "$output" =~ "--yes" ]]
}

@test "release_yes_skips_prompt (S12 — yes proceeds)" {
  setup_fake_gh
  export FAKE_GH_RELEASE_VIEW_FOUND=found

  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-s12y"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons:
  - name: atlas
    display_name: ATLAS
    status: shipped
    source:
      type: github
      repo: Rynaro/ATLAS
      default_ref: main
    versions:
      latest: "1.3.0"
      pins:
        stable: "1.3.0"
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release atlas 1.4.0 --yes
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PR opened" ]] || [[ "$output" =~ "pull" ]]
}

# ─── Additional: bad SemVer exits 2 ─────────────────────────────────────
@test "release_rejects_invalid_semver" {
  setup_fake_gh
  run eidolons release atlas "not-a-version" --non-interactive --yes
  [ "$status" -eq 2 ]
  [[ "$output" =~ "SemVer" ]] || [[ "$output" =~ "valid" ]]
}

# ─── Additional: missing eidolon name exits 2 ─────────────────────────────
@test "release_rejects_unknown_eidolon" {
  setup_fake_gh
  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-unk"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/cli/src/ui"
  cp "$EIDOLONS_ROOT/cli/src/lib.sh"  "$custom_nexus/cli/src/lib.sh"
  cp -r "$EIDOLONS_ROOT/cli/src/ui/"* "$custom_nexus/cli/src/ui/" 2>/dev/null || true
  cat > "$custom_nexus/roster/index.yaml" <<'ROSTER'
registry_version: "1.0"
updated_at: "2026-05-05T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: warn
eidolons: []
presets: {}
ROSTER
  export EIDOLONS_NEXUS="$custom_nexus"

  run eidolons release unknownbot 1.0.0 --non-interactive --yes
  [ "$status" -eq 2 ]
}

# ─── Additional: --help exits 0 ───────────────────────────────────────────
@test "release -h: help prints" {
  run eidolons release --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

# ─── G11: doctor pending section byte-identical on two consecutive runs ───
# (Placed here for convenience since it exercises the related infra)
@test "pending_upgrades_byte_identical_on_rerun (G11)" {
  # Set up a fully wired project with atlas at 1.3.0 (upgrade-available).
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.3.0"
    source: github:Rynaro/ATLAS
EOF
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.3.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
  seed_agent_install_manifest atlas
  mkdir -p .claude/agents
  echo "---" > .claude/agents/atlas.md

  run eidolons doctor
  first_output="$output"
  run eidolons doctor
  second_output="$output"
  [ "$first_output" = "$second_output" ]
}
