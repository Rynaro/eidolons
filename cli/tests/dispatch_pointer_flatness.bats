#!/usr/bin/env bats
# dispatch_pointer_flatness.bats — P0 invariant: every vendor file's
# dispatch-pointer block must reference only ./EIDOLONS.md (never another
# vendor file). R4-4 / D5 / SPEC INIT-R4.

load helpers

# setup_fake_git_no_clone: fake git that blocks clone (like init.bats).
setup_fake_git_no_clone() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/git" <<'FAKEGIT'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  echo "fake-git: clone blocked" >&2
  exit 128
fi
exec /usr/bin/env git-real "$@" 2>/dev/null || true
FAKEGIT
  chmod +x "$FAKE_BIN/git"
  export PATH="$FAKE_BIN:$PATH"
}

# Closed vendor file set.
VENDORS=(
  "CLAUDE.md"
  "AGENTS.md"
  "GEMINI.md"
  ".github/copilot-instructions.md"
)

# _assert_dp_targets_eidolons_md FILE
# Assert: dispatch-pointer block of $file references ./EIDOLONS.md (or backtick form).
_assert_dp_targets_eidolons_md() {
  local file="$1"
  local block
  block="$(awk '/<!-- eidolon:dispatch-pointer start -->/,/<!-- eidolon:dispatch-pointer end -->/' "$file" 2>/dev/null || true)"
  if [[ "$block" != *"./EIDOLONS.md"* ]] && [[ "$block" != *"\`EIDOLONS.md\`"* ]] && [[ "$block" != *"EIDOLONS.md"* ]]; then
    echo "FAIL: $file dispatch-pointer block does not reference EIDOLONS.md" >&2
    echo "Block content:" >&2
    echo "$block" >&2
    return 1
  fi
  return 0
}

# _assert_dp_no_vendor_crossref FILE
# Assert: dispatch-pointer block of $file does NOT reference any other vendor file.
_assert_dp_no_vendor_crossref() {
  local file="$1"
  local block
  block="$(awk '/<!-- eidolon:dispatch-pointer start -->/,/<!-- eidolon:dispatch-pointer end -->/' "$file" 2>/dev/null || true)"
  local other_path
  for other_path in \
    "./AGENTS.md" "./CLAUDE.md" "./GEMINI.md" "./copilot-instructions.md" \
    "AGENTS.md" "CLAUDE.md" "GEMINI.md" "copilot-instructions.md"; do
    # Self-reference is allowed (the file's own basename may appear in a comment).
    [[ "$other_path" == "./${file}" || "$other_path" == "$file" ]] && continue
    # Also skip when the other_path's basename matches the file's basename.
    local other_base file_base
    other_base="${other_path##*/}"
    file_base="${file##*/}"
    [[ "$file_base" == "$other_base" ]] && continue
    if printf '%s\n' "$block" | grep -qF "$other_path"; then
      echo "FAIL: $file dispatch-pointer block references $other_path" >&2
      echo "Block content:" >&2
      printf '%s\n' "$block" >&2
      return 1
    fi
  done
  return 0
}

# _check_vendor_files: run both assertions on all present vendor files.
_check_vendor_files() {
  local v
  for v in "${VENDORS[@]}"; do
    if [[ -f "$v" ]]; then
      if ! grep -q '<!-- eidolon:dispatch-pointer start -->' "$v" 2>/dev/null; then
        continue  # no dispatch-pointer block in this vendor file; skip
      fi
      _assert_dp_targets_eidolons_md "$v" || return 1
      _assert_dp_no_vendor_crossref "$v" || return 1
    fi
  done
  return 0
}

# seed_minimal_manifest_no_sync: write a valid eidolons.yaml with
# pointer_targets pre-set so sync doesn't need to re-derive.
_seed_manifest_pt() {
  local pt="$1" wire="${2:-claude-code}" sd="${3:-false}"
  {
    echo "version: 1"
    echo "hosts:"
    echo "  wire: [${wire}]"
    echo "  shared_dispatch: ${sd}"
    echo "  strict: false"
    echo "  pointer_targets: [$(printf '%s\n' "$pt" | sed 's/,/, /g')]"
    echo ""
    echo "members:"
    echo "  - name: atlas"
    echo "    version: \"^1.0.0\""
    echo "    source: github:Rynaro/ATLAS"
  } > eidolons.yaml
}

# ─── Test 1: claude-code wired ───────────────────────────────────────────────

@test "dispatch-pointer flatness: claude-code wired" {
  setup_fake_git_no_clone
  _seed_manifest_pt "CLAUDE.md" "claude-code" "false"
  run eidolons sync --yes --non-interactive
  # Sync may fail (fake git blocks clone). We only care about the vendor files.
  # Apply pointers manually to assert the flatness invariant.
  run bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md' 'claude-code'
  " 2>/dev/null
  [ -f CLAUDE.md ]
  _check_vendor_files
}

# ─── Test 2: codex wired (AGENTS-precedence) ─────────────────────────────────

@test "dispatch-pointer flatness: codex wired (AGENTS-precedence)" {
  setup_fake_git_no_clone
  _seed_manifest_pt "AGENTS.md" "codex" "false"
  run bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'AGENTS.md' 'codex'
  " 2>/dev/null
  [ -f AGENTS.md ]
  _check_vendor_files
}

# ─── Test 3: multi-pointer (AGENTS.md + CLAUDE.md) ───────────────────────────

@test "dispatch-pointer flatness: multi-pointer (AGENTS.md + CLAUDE.md)" {
  setup_fake_git_no_clone
  _seed_manifest_pt "AGENTS.md,CLAUDE.md" "claude-code" "false"
  run bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'AGENTS.md,CLAUDE.md' 'claude-code'
  " 2>/dev/null
  [ -f AGENTS.md ]
  [ -f CLAUDE.md ]
  _check_vendor_files
}

# ─── Test 4: shared_dispatch=true ────────────────────────────────────────────

@test "dispatch-pointer flatness: shared_dispatch=true" {
  setup_fake_git_no_clone
  _seed_manifest_pt "AGENTS.md" "claude-code" "true"
  run bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'AGENTS.md' 'claude-code'
  " 2>/dev/null
  [ -f AGENTS.md ]
  _check_vendor_files
}
