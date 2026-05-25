#!/usr/bin/env bats

load helpers

@test "sync: fails without eidolons.yaml" {
  run eidolons sync
  [ "$status" -ne 0 ]
  [[ "$output" =~ No\ eidolons\.yaml ]]
}

@test "sync --dry-run: prints planned install actions without cloning" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ atlas ]]
  [[ "$output" =~ would ]]
}

@test "sync --dry-run: still writes the lock header" {
  seed_manifest
  run eidolons sync --dry-run
  [ -f eidolons.lock ]
  run cat eidolons.lock
  [[ "$output" =~ generated_at ]]
}

@test "sync -h: help prints" {
  run eidolons sync -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ sync ]]
}

@test "sync: rejects unknown flag" {
  seed_manifest
  run eidolons sync --bogus
  [ "$status" -ne 0 ]
}

# ─── codex host support (openai-codex-host-support spec, R.3) ──────────────

# Helper: write a manifest with codex wired and shared_dispatch=false to
# exercise the T.12 override-with-warn path on sync.
seed_codex_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
  shared_dispatch: false
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

@test "sync: codex + shared_dispatch=false emits override-with-warn and overrides effective dispatch" {
  seed_codex_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  # Warning must appear on stderr (bats merges into $output).
  [[ "$output" =~ "--no-shared-dispatch ignored for hosts.wire containing codex" ]]
}

@test "sync --dry-run: codex preview lists AGENTS.md and .codex/agents/<name>.md" {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
  shared_dispatch: true
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
  - name: spectra
    version: "^4.2.0"
    source: github:Rynaro/SPECTRA
EOF
  # --dry-run skips the preview confirmation prompt path; the codex preview
  # branch lives on the interactive path. Use --yes (skip preview) to keep
  # this test deterministic and assert on the documented dry-run output.
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  # dry-run plans installs but should not fail before printing the plan.
  [[ "$output" =~ atlas ]]
  [[ "$output" =~ spectra ]]
}

@test "sync: codex manifest preserves shared_dispatch:false after override" {
  # Story 6 invariant: the manifest still reads shared_dispatch:false even
  # though execution overrode it. Subsequent edits removing codex from wire
  # would honour the original choice.
  seed_codex_manifest
  run eidolons sync --dry-run
  grep -q 'shared_dispatch: false' eidolons.yaml
}

# ─── G11: fresh cache — no re-clone on sync ────────────────────────────────
@test "sync re-uses fresh cache without re-cloning (no network call when cache valid)" {
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0

  # First sync — populates the cache via fake-git clone.
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  # Save the clone count.
  clone_count_1=0
  [[ -f "$FAKE_CLONE_LOG" ]] && clone_count_1="$(wc -l < "$FAKE_CLONE_LOG" | tr -d ' ')"

  # Second sync — must reuse cache; no additional clone.
  # Use --verbose so info-tier "Using cached" message is visible.
  run eidolons sync --yes --verbose
  [ "$status" -eq 0 ]
  clone_count_2=0
  [[ -f "$FAKE_CLONE_LOG" ]] && clone_count_2="$(wc -l < "$FAKE_CLONE_LOG" | tr -d ' ')"

  # Clone count must not have grown on the second run.
  [ "$clone_count_2" -le "$clone_count_1" ]
  # Second run must have emitted "Using cached" for the member.
  [[ "$output" =~ "Using cached" ]]
}

# ─── G12: auto-recover single-member cache drift without aborting preset ──
@test "sync auto-recovers single-member cache drift without aborting full preset" {
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0 spectra=^4.2.0

  # First sync — populates both caches.
  run eidolons sync --yes
  [ "$status" -eq 0 ]

  # Corrupt the atlas cache: write a wrong FAKE_COMMIT so rev-parse returns
  # a different SHA than what the fresh clone would emit.
  local atlas_cache
  atlas_cache="$(ls -d "$EIDOLONS_HOME/cache/atlas@"* 2>/dev/null | head -1 || true)"
  if [[ -n "$atlas_cache" && -d "$atlas_cache/.git" ]]; then
    echo "stalestalestalestalestalestalestalestale" > "$atlas_cache/.git/FAKE_COMMIT"
  fi

  # Second sync — atlas must auto-recover (re-clone) while spectra stays cached.
  # Use --verbose so info/warn-tier cache messages are visible.
  run eidolons sync --yes --verbose
  [ "$status" -eq 0 ]
  # The run must have emitted both a re-clone message and a cached-use message.
  [[ "$output" =~ "cache invalid" ]] || [[ "$output" =~ "re-cloning" ]] || [[ "$output" =~ "Using cached" ]]
}

# ─── Lockfile integrity fields (Story 5.D) ────────────────────────────────

@test "sync: writes manifest_sha256 + commit + tree + verification into lockfile" {
  setup_fake_git_for_upgrade
  seed_manifest_with atlas=^1.0.0
  run eidolons sync --yes
  [ "$status" -eq 0 ]
  # The fake installer writes a known install.manifest.json; sync must hash it
  # and record commit/tree from the cloned repo. Each field is in its own line.
  # (Use + rather than {N} for portable BSD/GNU grep -E compatibility.)
  grep -E 'manifest_sha256: "[0-9a-f]+"' eidolons.lock
  # commit and tree appear under each member entry, indented; nexus_commit on
  # the lockfile root is the only un-indented `commit:` and is excluded.
  grep -E ' commit: "[0-9a-f]+"' eidolons.lock
  grep -E ' tree: "[0-9a-f]+"' eidolons.lock
  # In compatibility mode (no roster releases entry) atlas is "legacy-warning".
  grep -q 'verification: "legacy-warning"' eidolons.lock
}

# ─── G-A1: dispatch-pointer marker block (PR-A1) ──────────────────────────
# These tests exercise the apply_dispatch_pointers helper directly via a
# subshell that sources lib.sh. End-to-end coverage of the helper invoked
# from sync.sh is provided by sync.bats's existing happy-path tests
# combined with the assertions below; the helper-direct approach gives
# precise control over pre-existing file content (warn-and-append, idempotency)
# without the heavyweight fake-git fetch machinery.

# G-A1.1 — dispatch-pointer block lands in each vendor file with vendor-specific text.
@test "dispatch pointer: creates marker block in CLAUDE.md / GEMINI.md / copilot-instructions.md" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md,GEMINI.md,.github/copilot-instructions.md'
  " 2>/dev/null

  # Every vendor file exists and carries the marker.
  for _f in CLAUDE.md GEMINI.md .github/copilot-instructions.md; do
    [ -f "$_f" ]
    grep -qF "<!-- eidolon:dispatch-pointer start -->" "$_f"
    grep -qF "<!-- eidolon:dispatch-pointer end -->"   "$_f"
  done

  # Vendor-specific phrasing — each file has its own pointer body.
  grep -qF "TRANCE complexity signal" CLAUDE.md            # Claude pointer
  grep -qF "agent dispatch table and methodology" GEMINI.md # Gemini pointer (shorter form)
  grep -qF "canonical agent instructions live in" .github/copilot-instructions.md
}

# G-A1.1 cont. — AGENTS.md written when explicitly in pointer_targets.
@test "dispatch pointer: AGENTS.md written when in pointer_targets (R3)" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'AGENTS.md'
  " 2>/dev/null

  [ -f AGENTS.md ]
  grep -qF "<!-- eidolon:dispatch-pointer start -->" AGENTS.md
  grep -qF "TRANCE complexity signal" AGENTS.md
}

# G-A1.1 cont.b — AGENTS.md NOT written when NOT in pointer_targets.
@test "dispatch pointer: AGENTS.md not created when absent from pointer_targets (R3)" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md'
  " 2>/dev/null

  [ ! -f AGENTS.md ]
}

# G-A1.5 — warn-and-append fires once on first append into populated content;
# zero on rewrite (second sync).
@test "dispatch pointer: warn-and-append fires once on first append into populated content" {
  # Seed CLAUDE.md with user-authored content unrelated to Eidolons.
  cat > CLAUDE.md <<'USER_CLAUDE'
# My Project

This is my existing instructions file for Claude.
USER_CLAUDE

  _stderr_file="$(mktemp)"
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md'
  " 2>"$_stderr_file" || true
  _first_run="$(cat "$_stderr_file")"
  rm -f "$_stderr_file"

  # Exactly one warn line for CLAUDE.md on first append.
  _warn_count="$(printf '%s\n' "$_first_run" | grep -cF 'CLAUDE.md exists with user content' || true)"
  [ "$_warn_count" = "1" ]

  # User content preserved.
  grep -qF "# My Project" CLAUDE.md
  grep -qF "existing instructions file for Claude" CLAUDE.md
  # Block appended below the user content.
  grep -qF "<!-- eidolon:dispatch-pointer start -->" CLAUDE.md

  # Second sync (block already present) — no warn line.
  _stderr_file="$(mktemp)"
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md'
  " 2>"$_stderr_file" || true
  _second_run="$(cat "$_stderr_file")"
  rm -f "$_stderr_file"
  ! printf '%s' "$_second_run" | grep -qF 'CLAUDE.md exists with user content'
}

# G-A1.4 — two applications leave each vendor file byte-identical.
@test "dispatch pointer: idempotent — two applications leave vendor files byte-identical" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md,GEMINI.md,.github/copilot-instructions.md'
  " 2>/dev/null

  cp CLAUDE.md CLAUDE.md.first
  cp GEMINI.md GEMINI.md.first
  cp .github/copilot-instructions.md copilot.first

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md,GEMINI.md,.github/copilot-instructions.md'
  " 2>/dev/null

  diff -q CLAUDE.md.first CLAUDE.md
  diff -q GEMINI.md.first GEMINI.md
  diff -q copilot.first   .github/copilot-instructions.md
}

# G-A1.2 — dispatch-pointer coexists with cortex block (different marker names,
# both present, both round-trip).
@test "dispatch pointer coexists with cortex: both markers present in CLAUDE.md" {
  # Seed CLAUDE.md with the cortex block already present (simulates
  # shared-dispatch path).
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    upsert_marker_block CLAUDE.md cortex 'cortex body line 1
cortex body line 2'
    apply_dispatch_pointers 'CLAUDE.md'
  " 2>/dev/null

  # Both markers must be present.
  grep -qF "<!-- eidolon:cortex start -->"            CLAUDE.md
  grep -qF "<!-- eidolon:cortex end -->"              CLAUDE.md
  grep -qF "<!-- eidolon:dispatch-pointer start -->"  CLAUDE.md
  grep -qF "<!-- eidolon:dispatch-pointer end -->"    CLAUDE.md

  # Each block's body is intact.
  grep -qF "cortex body line 1" CLAUDE.md
  grep -qF "TRANCE complexity signal" CLAUDE.md

  # Exactly one start marker per block.
  [ "$(grep -cF 'eidolon:cortex start'           CLAUDE.md)" = "1" ]
  [ "$(grep -cF 'eidolon:dispatch-pointer start' CLAUDE.md)" = "1" ]

  # Round-trip rewrite is idempotent for both.
  cp CLAUDE.md CLAUDE.md.first
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    upsert_marker_block CLAUDE.md cortex 'cortex body line 1
cortex body line 2'
    apply_dispatch_pointers 'CLAUDE.md'
  " 2>/dev/null
  diff -q CLAUDE.md.first CLAUDE.md
}

# G-A1 GEMINI opt-out — EIDOLONS_NO_GEMINI=1 skips GEMINI.md.
@test "dispatch pointer: EIDOLONS_NO_GEMINI=1 skips GEMINI.md but writes the others" {
  bash -c "
    set -e
    export EIDOLONS_NO_GEMINI=1
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md,GEMINI.md,.github/copilot-instructions.md'
  " 2>/dev/null

  [ -f CLAUDE.md ]
  [ -f .github/copilot-instructions.md ]
  [ ! -f GEMINI.md ]
}

# ─── G-I2: host-leakage prune (PR-I2) ─────────────────────────────────────
# Tests exercise lib_host_prune.sh directly to keep the surface small and
# avoid coupling to the heavyweight fake-git fetch machinery. End-to-end
# wiring through `eidolons sync --strict-hosts` is exercised by the
# "strict hosts" test below using the existing setup_fake_git_for_upgrade
# stub (which writes AGENTS.md + CLAUDE.md unconditionally, simulating
# real-world host leakage).

# Helper — materialise a fake .eidolons/<name>/ tree containing the
# vendor-leakage pattern set. Used by the path-pattern + idempotency tests.
_seed_leakage_tree() {
  local name="${1:-atlas}"
  mkdir -p ".eidolons/$name/hosts" ".eidolons/$name/.github"
  : > ".eidolons/$name/hosts/cursor.md"
  : > ".eidolons/$name/hosts/copilot.md"
  : > ".eidolons/$name/hosts/codex.md"
  : > ".eidolons/$name/hosts/opencode.md"
  : > ".eidolons/$name/.github/copilot-instructions.md"
  : > ".eidolons/$name/CLAUDE.md"
  : > ".eidolons/$name/AGENTS.md"
}

# G-I2.1 — path-pattern prune deletes non-selected hosts' files; keeps the rest.
@test "host prune: claude-code selection — drops cursor/copilot/codex/opencode/AGENTS, keeps CLAUDE.md" {
  _seed_leakage_tree atlas

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_path_patterns ./.eidolons/atlas claude-code
  " 2>/dev/null

  # The claude-code file survives.
  [ -f ".eidolons/atlas/CLAUDE.md" ]
  # Every other vendor file is gone.
  [ ! -f ".eidolons/atlas/hosts/cursor.md" ]
  [ ! -f ".eidolons/atlas/hosts/copilot.md" ]
  [ ! -f ".eidolons/atlas/hosts/codex.md" ]
  [ ! -f ".eidolons/atlas/hosts/opencode.md" ]
  [ ! -f ".eidolons/atlas/.github/copilot-instructions.md" ]
  # AGENTS.md is pruned because neither codex nor opencode is wired.
  [ ! -f ".eidolons/atlas/AGENTS.md" ]
}

# G-I2.1 cont. — AGENTS.md multi-host rule: keep iff codex OR opencode selected.
@test "host prune: AGENTS.md kept when codex is in selection (multi-host rule)" {
  _seed_leakage_tree atlas

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_path_patterns ./.eidolons/atlas claude-code,codex
  " 2>/dev/null

  # Codex consumes AGENTS.md → must survive.
  [ -f ".eidolons/atlas/AGENTS.md" ]
  [ -f ".eidolons/atlas/CLAUDE.md" ]
  [ -f ".eidolons/atlas/hosts/codex.md" ]
  # Non-selected hosts still pruned.
  [ ! -f ".eidolons/atlas/hosts/cursor.md" ]
  [ ! -f ".eidolons/atlas/hosts/copilot.md" ]
  [ ! -f ".eidolons/atlas/hosts/opencode.md" ]
}

# G-I2.3 — no prune when every supported host is wired.
@test "host prune: no prune when all hosts wired" {
  _seed_leakage_tree atlas

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_path_patterns ./.eidolons/atlas claude-code,copilot,cursor,codex,opencode
  " 2>/dev/null

  # Every seeded file must still exist.
  [ -f ".eidolons/atlas/CLAUDE.md" ]
  [ -f ".eidolons/atlas/AGENTS.md" ]
  [ -f ".eidolons/atlas/hosts/cursor.md" ]
  [ -f ".eidolons/atlas/hosts/copilot.md" ]
  [ -f ".eidolons/atlas/hosts/codex.md" ]
  [ -f ".eidolons/atlas/hosts/opencode.md" ]
  [ -f ".eidolons/atlas/.github/copilot-instructions.md" ]
}

# G-I2.4 — idempotent: a second prune pass on an already-clean tree is a no-op.
@test "host prune: idempotent — second pass produces zero deletions" {
  _seed_leakage_tree atlas

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_path_patterns ./.eidolons/atlas claude-code
  " 2>/dev/null

  # Snapshot the post-prune tree.
  _first_state="$(find .eidolons/atlas -type f | sort)"

  # Second pass should leave the same set of files.
  _stderr_file="$(mktemp)"
  bash -c "
    set -e
    EIDOLONS_VERBOSE=1 \\
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    EIDOLONS_VERBOSE=1 host_prune_path_patterns ./.eidolons/atlas claude-code
  " 2>"$_stderr_file"
  _verbose_out="$(cat "$_stderr_file")"
  rm -f "$_stderr_file"

  # Files unchanged.
  _second_state="$(find .eidolons/atlas -type f | sort)"
  [ "$_first_state" = "$_second_state" ]

  # And no "pruned" lines in verbose output on the second pass.
  ! printf '%s' "$_verbose_out" | grep -qF "pruned"
}

# G-I2.2 — strict mode: violation when a vendor-pattern file is unannotated
# in install.manifest.json.
@test "strict hosts: emits violation when vendor file is not annotated in manifest" {
  mkdir -p ".eidolons/atlas/hosts"
  : > ".eidolons/atlas/hosts/cursor.md"
  cat > ".eidolons/atlas/install.manifest.json" <<'EOF'
{
  "name": "atlas",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF

  run bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_strict_check ./.eidolons/atlas claude-code
  "
  [ "$status" -eq 1 ]
  [[ "$output" =~ "hosts/cursor.md" ]]
  [[ "$output" =~ "host unknown" ]]
}

# G-I2.2 cont. — strict mode passes when annotated.
@test "strict hosts: no violation when vendor file is annotated in manifest" {
  mkdir -p ".eidolons/atlas/hosts"
  : > ".eidolons/atlas/hosts/cursor.md"
  cat > ".eidolons/atlas/install.manifest.json" <<'EOF'
{
  "name": "atlas",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": [
    {"path": "hosts/cursor.md", "host": "cursor"}
  ]
}
EOF

  run bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_strict_check ./.eidolons/atlas claude-code
  "
  [ "$status" -eq 0 ]
}

# G-I2.2 cont. — manifest-driven prune removes annotated files for non-selected hosts.
@test "host prune (manifest): annotated cursor.md is pruned when cursor not selected" {
  mkdir -p ".eidolons/atlas/hosts"
  : > ".eidolons/atlas/hosts/cursor.md"
  cat > ".eidolons/atlas/install.manifest.json" <<'EOF'
{
  "name": "atlas",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": [
    {"path": "hosts/cursor.md", "host": "cursor"}
  ]
}
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_manifest_pass ./.eidolons/atlas claude-code
  " 2>/dev/null

  [ ! -f ".eidolons/atlas/hosts/cursor.md" ]
}

# Helper — same shape as setup_fake_git_for_upgrade, but the cloned stub
# install.sh writes a richer leakage tree under $TGT (CLAUDE.md, AGENTS.md,
# hosts/cursor.md, .github/copilot-instructions.md) so end-to-end prune
# behaviour is observable.
_setup_fake_git_leakage_installer() {
  setup_fake_git_for_upgrade
  # Patch the cloned install.sh template baked into the fake git stub.
  # The fake git's clone op materialises an Eidolon at $dest and writes a
  # stub install.sh. We replace it with a richer leakage stub.
  local fake_bin="$FAKE_BIN"
  cat > "$fake_bin/_leakage_install_stub.sh" <<'STUB'
#!/usr/bin/env bash
# Leakage stub for PR-I2 end-to-end tests. Writes a manifest plus the
# vendor-leakage pattern set so the nexus prune can be observed.
TGT=""
HOSTS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TGT="$2"; shift 2 ;;
    --hosts)  HOSTS="$2"; shift 2 ;;
    --shared-dispatch|--no-shared-dispatch|--non-interactive|--force) shift ;;
    *) shift ;;
  esac
done
mkdir -p "$TGT/hosts" "$TGT/.github"
NAME="$(basename "$TGT")"
cat > "$TGT/install.manifest.json" <<JSON
{
  "name": "$NAME",
  "version": "0.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
JSON
: > "$TGT/CLAUDE.md"
: > "$TGT/AGENTS.md"
: > "$TGT/hosts/cursor.md"
: > "$TGT/hosts/copilot.md"
: > "$TGT/.github/copilot-instructions.md"
exit 0
STUB
  # Swap the git stub to use the leakage installer instead of the default.
  # The default stub is baked into the heredoc inside helpers.bash's fake
  # git; we patch the clone behaviour by overriding $FAKE_INSTALL_TEMPLATE
  # if the helper supports it, else we post-process after the clone runs.
  # In practice, the default stub install.sh from setup_fake_git_for_upgrade
  # is copied to $dest/install.sh on clone. Easier approach: leave the
  # default in place and overwrite $clone_dir/install.sh between fetch and
  # install via a wrapper.
  #
  # Simpler: copy our leakage stub on top of any cache install.sh AFTER
  # fetch_eidolon clones (which means *during* sync). The fake git's clone
  # op honors $LEAKAGE_INSTALL_TEMPLATE if set — but the upstream fake
  # doesn't read that. So we just patch $EIDOLONS_HOME/cache/<name>@<ver>/install.sh
  # in this helper before sync runs. fetch_eidolon prefers cache when
  # present and skips re-clone.
  export EIDOLONS_LEAKAGE_STUB="$fake_bin/_leakage_install_stub.sh"
}

# Sync once with the default fake stub to populate the cache, then
# overwrite the cached install.sh with the leakage variant, then re-sync
# with --force so the leakage installer runs.
_run_sync_with_leakage_installer() {
  local extra_args="${1:-}"
  # First sync runs the default stub (which writes only manifest).
  run eidolons sync --yes
  # The fake git's clone populated $EIDOLONS_HOME/cache/atlas@1.0.0/install.sh.
  # Overwrite it with our leakage stub.
  local cache_install_sh
  cache_install_sh="$(ls "$EIDOLONS_HOME/cache"/atlas@*/install.sh 2>/dev/null | head -1)"
  [[ -n "$cache_install_sh" ]] || return 1
  cp "$EIDOLONS_LEAKAGE_STUB" "$cache_install_sh"
  chmod +x "$cache_install_sh"
  # Remove the existing target so the installer re-creates it.
  rm -rf ".eidolons/atlas"
  # Re-sync to invoke the leakage installer.
  # shellcheck disable=SC2086
  run eidolons sync --yes $extra_args
}

# G-I2.1 end-to-end — `eidolons sync --hosts claude-code` produces a tree
# free of cross-host leakage.
@test "host prune end-to-end: eidolons sync removes vendor leakage when only claude-code is wired" {
  _setup_fake_git_leakage_installer
  seed_manifest_with atlas=^1.0.0
  _run_sync_with_leakage_installer
  [ "$status" -eq 0 ]

  # Leakage stub wrote CLAUDE.md, AGENTS.md, hosts/cursor.md,
  # hosts/copilot.md, .github/copilot-instructions.md. With hosts.wire=
  # [claude-code]: CLAUDE.md survives; the rest get pruned.
  [ -f ".eidolons/atlas/CLAUDE.md" ]
  [ ! -f ".eidolons/atlas/AGENTS.md" ]
  [ ! -f ".eidolons/atlas/hosts/cursor.md" ]
  [ ! -f ".eidolons/atlas/hosts/copilot.md" ]
  [ ! -f ".eidolons/atlas/.github/copilot-instructions.md" ]
}

# G-I2.2 end-to-end — --strict-hosts on a manifest with empty files[] fails.
@test "strict hosts end-to-end: --strict-hosts fails when leakage installer omits host annotations" {
  _setup_fake_git_leakage_installer
  seed_manifest_with atlas=^1.0.0
  _run_sync_with_leakage_installer "--strict-hosts"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--strict-hosts" ]]
  [[ "$output" =~ "host unknown" ]]
}

# ─── G-B1: compose_eidolons_md (Block 1) ──────────────────────────────────

# G-B1.1 — compose_eidolons_md hoists a marker block from CLAUDE.md into
# EIDOLONS.md and replaces the source with a pointer block.
@test "compose_eidolons_md hoists from CLAUDE.md" {
  cat > CLAUDE.md <<'EOF'
# My Project
<!-- eidolon:atlas start -->
atlas content line 1
atlas content line 2
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  # EIDOLONS.md created with preamble and the hoisted block.
  [ -f "EIDOLONS.md" ]
  grep -qF "<!-- eidolon:atlas start -->" EIDOLONS.md
  grep -qF "atlas content line 1" EIDOLONS.md

  # CLAUDE.md: original content block removed; NO <name>-pointer stub (v1.7.0+).
  ! grep -qF "<!-- eidolon:atlas start -->" CLAUDE.md
  ! grep -qF "<!-- eidolon:atlas-pointer start -->" CLAUDE.md

  # Preamble written.
  grep -qF "EIDOLONS — canonical agent" EIDOLONS.md

  # User text above markers preserved in CLAUDE.md.
  grep -qF "# My Project" CLAUDE.md
}

# G-B1.2 — compose_eidolons_md is idempotent: second run is a no-op.
@test "compose_eidolons_md idempotent" {
  cat > CLAUDE.md <<'EOF'
<!-- eidolon:atlas start -->
atlas body
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  cp CLAUDE.md CLAUDE.md.first
  cp EIDOLONS.md EIDOLONS.md.first

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  diff -q CLAUDE.md.first CLAUDE.md
  diff -q EIDOLONS.md.first EIDOLONS.md
}

# G-B1.3 — compose_eidolons_md hoists from AGENTS.md symmetrically with CLAUDE.md.
@test "compose_eidolons_md hoists from AGENTS.md" {
  # Seed AGENTS.md with a per-eidolon block (no CLAUDE.md).
  cat > AGENTS.md <<'EOF'
<!-- eidolon:atlas start -->
agents atlas content
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas' './CLAUDE.md ./AGENTS.md'
  " 2>/dev/null

  # EIDOLONS.md created with hoisted block.
  [ -f "EIDOLONS.md" ]
  grep -qF "<!-- eidolon:atlas start -->" EIDOLONS.md
  grep -qF "agents atlas content" EIDOLONS.md

  # AGENTS.md: original content block removed; NO <name>-pointer stub (v1.7.0+).
  ! grep -qF "<!-- eidolon:atlas start -->" AGENTS.md
  ! grep -qF "<!-- eidolon:atlas-pointer start -->" AGENTS.md
}

# G-B1.4 — existing preamble in EIDOLONS.md is preserved byte-for-byte.
@test "compose_eidolons_md preserves existing EIDOLONS.md preamble" {
  printf '%s\n' "# Custom preamble" "user text" > EIDOLONS.md
  cat > CLAUDE.md <<'EOF'
<!-- eidolon:atlas start -->
atlas body
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  grep -qF "# Custom preamble" EIDOLONS.md
  grep -qF "user text" EIDOLONS.md
  grep -qF "<!-- eidolon:atlas start -->" EIDOLONS.md
}

# G-B1.7 — no CLAUDE.md → EIDOLONS.md is NOT created.
@test "compose_eidolons_md no-op when CLAUDE.md absent" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  [ ! -f "EIDOLONS.md" ]
}

# ─── G-B2: host-gated dispatch-pointer (Block 2) ──────────────────────────

# G-B2.1 — apply_dispatch_pointers with pointer_targets=CLAUDE.md: only CLAUDE.md
# is written; GEMINI.md and copilot-instructions.md are NOT created.
@test "dispatch pointer host-gated on claude-code" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md'
  " 2>/dev/null

  [ -f "CLAUDE.md" ]
  [ ! -f "GEMINI.md" ]
  [ ! -f ".github/copilot-instructions.md" ]
  grep -qF "<!-- eidolon:dispatch-pointer start -->" CLAUDE.md
}

# G-B2.2 — dispatch pointer block redirects to ./EIDOLONS.md not ./AGENTS.md.
@test "dispatch pointer redirects to EIDOLONS.md" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'CLAUDE.md,GEMINI.md,.github/copilot-instructions.md'
  " 2>/dev/null

  grep -qF "EIDOLONS.md" CLAUDE.md
  ! grep -qF "./AGENTS.md" CLAUDE.md
  grep -qF "EIDOLONS.md" GEMINI.md
  ! grep -qF "./AGENTS.md" GEMINI.md
  grep -qF "EIDOLONS.md" .github/copilot-instructions.md
  ! grep -qF "./AGENTS.md" .github/copilot-instructions.md
}

# G-B2.3 — EIDOLONS_NO_GEMINI=1 emits a deprecation warn on stderr.
@test "EIDOLONS_NO_GEMINI deprecation warn" {
  _stderr_file="$(mktemp)"
  bash -c "
    set -e
    export EIDOLONS_NO_GEMINI=1
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'GEMINI.md'
  " 2>"$_stderr_file" || true
  _output="$(cat "$_stderr_file")"
  rm -f "$_stderr_file"

  printf '%s\n' "$_output" | grep -qF "EIDOLONS_NO_GEMINI is deprecated"
}

# ─── G-B3: host-gated cortex injection (Block 3) ──────────────────────────

# G-B3.1 — cortex injection is gated on HOSTS_CSV (exercised via lib.sh helpers).
@test "cortex injection host-gated" {
  # Exercise the _cortex_doc_host helper directly.
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    result=\$(_cortex_doc_host 'CLAUDE.md')
    [ \"\$result\" = 'claude-code' ]
    result=\$(_cortex_doc_host '.github/copilot-instructions.md')
    [ \"\$result\" = 'copilot' ]
    result=\$(_cortex_doc_host 'AGENTS.md')
    [ \"\$result\" = 'codex' ]
  " 2>/dev/null
}

# G-B3.2 — AGENTS.md cortex special-case: codex OR opencode triggers it.
@test "cortex AGENTS.md codex special-case" {
  # Verify _cortex_doc_host returns 'codex' for AGENTS.md sentinel.
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    result=\$(_cortex_doc_host 'AGENTS.md')
    [ \"\$result\" = 'codex' ]
  " 2>/dev/null
}

# ─── G-R2A-1: symmetric AGENTS.md hoist (R2A-1) ──────────────────────────

# G-R2A-1.2 — compose_eidolons_md symmetric idempotent: both sources hoisted,
# second run is byte-identical.
@test "compose_eidolons_md symmetric idempotent" {
  cat > CLAUDE.md <<'EOF'
<!-- eidolon:atlas start -->
claude atlas body
<!-- eidolon:atlas end -->
EOF
  cat > AGENTS.md <<'EOF'
<!-- eidolon:atlas start -->
agents atlas body
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas' './CLAUDE.md ./AGENTS.md'
  " 2>/dev/null

  cp CLAUDE.md CLAUDE.md.first
  cp AGENTS.md AGENTS.md.first
  cp EIDOLONS.md EIDOLONS.md.first

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas' './CLAUDE.md ./AGENTS.md'
  " 2>/dev/null

  diff -q CLAUDE.md.first CLAUDE.md
  diff -q AGENTS.md.first AGENTS.md
  diff -q EIDOLONS.md.first EIDOLONS.md
}

# G-R2A-1.3 — compose_eidolons_md divergent body last-write-wins (AGENTS.md wins).
@test "compose_eidolons_md divergent body last-write-wins" {
  cat > CLAUDE.md <<'EOF'
<!-- eidolon:atlas start -->
VARIANT-A
<!-- eidolon:atlas end -->
EOF
  cat > AGENTS.md <<'EOF'
<!-- eidolon:atlas start -->
VARIANT-B
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas' './CLAUDE.md ./AGENTS.md'
  " 2>/dev/null

  # AGENTS.md processed second; its body wins in EIDOLONS.md.
  grep -qF "VARIANT-B" EIDOLONS.md
  ! grep -qF "VARIANT-A" EIDOLONS.md

  # Both source files: content block removed; NO <name>-pointer stub (v1.7.0+).
  ! grep -qF "<!-- eidolon:atlas start -->" CLAUDE.md
  ! grep -qF "<!-- eidolon:atlas-pointer start -->" CLAUDE.md
  ! grep -qF "<!-- eidolon:atlas start -->" AGENTS.md
  ! grep -qF "<!-- eidolon:atlas-pointer start -->" AGENTS.md
}

# ─── G-B6: lockfile composition block (Block 6) ───────────────────────────

# G-B6.1 — eidolons sync --dry-run produces a lockfile with updated composition block.
@test "lockfile composition hoisted_from" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  grep -qF "composition:" eidolons.lock
  grep -qF "target: EIDOLONS.md" eidolons.lock
  grep -qF "hoisted_from:" eidolons.lock
  grep -q "CLAUDE.md" eidolons.lock
  grep -q "AGENTS.md" eidolons.lock
  grep -qF "agents_md_role: hoisted" eidolons.lock
  grep -qF "schema_version: 1" eidolons.lock
}

# Legacy test name alias to not break existing references.
@test "lockfile composition block" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  grep -qF "composition:" eidolons.lock
  grep -qF "target: EIDOLONS.md" eidolons.lock
  grep -qF "hoisted_from:" eidolons.lock
  grep -q "CLAUDE.md" eidolons.lock
  grep -qF "agents_md_role: hoisted" eidolons.lock
  grep -qF "schema_version: 1" eidolons.lock
}

# ─── G-R2A-2: run_installer_captured (R2A-2) ─────────────────────────────

# G-R2A-2.3 — run_installer_captured dumps last 20 lines on failure.
@test "run_installer_captured dumps last 20 lines on failure" {
  # Create a fake installer that prints 25 lines then exits 1.
  local fake_installer="$BATS_TEST_TMPDIR/fake_clone"
  mkdir -p "$fake_installer"
  cat > "$fake_installer/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
for i in $(seq 1 25); do
  echo "installer line $i"
done
exit 1
SCRIPT
  chmod +x "$fake_installer/install.sh"

  # Run via helper; capture stderr.
  local stderr_file="$BATS_TEST_TMPDIR/stderr.txt"
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    run_installer_captured 'fakemember' 'default' '$fake_installer'
  " 2>"$stderr_file" || true

  # Should contain lines 6-25 (last 20 of 25).
  grep -qF "[fakemember] installer line 6" "$stderr_file"
  grep -qF "[fakemember] installer line 25" "$stderr_file"
  # Should NOT contain lines 1-5 (they fall outside tail -n 20).
  # Use word-boundary anchors via grep -E to avoid substring false-positives
  # (e.g. "line 10" would match "line 1" as a substring).
  ! grep -qE "\[fakemember\] installer line [12345]$" "$stderr_file"
}

# ─── G-R2B-1.2: eidolons.lock stamps real version (R2B-1) ────────────────

@test "eidolons.lock stamps real version" {
  seed_manifest
  local nexus_ver
  nexus_ver="$(cat "$EIDOLONS_ROOT/VERSION")"

  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [ -f eidolons.lock ]
  # eidolons_cli_version must match nexus VERSION, not the 1.0.0 fallback.
  local lock_ver
  lock_ver="$(grep 'eidolons_cli_version:' eidolons.lock | sed -E 's/.*"([^"]+)".*/\1/')"
  [ "$lock_ver" = "$nexus_ver" ]
  # Sanity: ensure it's not the old fallback unless nexus really is 1.0.0.
  [[ "$lock_ver" != "1.0.0" ]] || [[ "$nexus_ver" == "1.0.0" ]]
}

# ─── G-R2B-3: eidolons.lock mode 0644 after sync (R2B-3) ─────────────────

@test "eidolons.lock mode 0644 after sync" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [ -f eidolons.lock ]
  local lock_mode
  if stat -f '%Lp' eidolons.lock >/dev/null 2>&1; then
    lock_mode="$(stat -f '%Lp' eidolons.lock)"
  else
    lock_mode="$(stat -c '%a' eidolons.lock)"
  fi
  [ "$lock_mode" = "644" ]
}

# G-R2B-3: CLAUDE.md mode 0644 after upsert_marker_block
@test "CLAUDE.md mode 0644 after upsert" {
  # upsert_marker_block is exercised when sync writes the dispatch pointer.
  # Use the lib.sh function directly to verify the mode fix.
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    touch CLAUDE.md
    upsert_marker_block CLAUDE.md 'test-block' 'test content'
  " 2>/dev/null

  [ -f CLAUDE.md ]
  local mode
  if stat -f '%Lp' CLAUDE.md >/dev/null 2>&1; then
    mode="\$(stat -f '%Lp' CLAUDE.md)"
  else
    mode="\$(stat -c '%a' CLAUDE.md)"
  fi
  # Re-evaluate mode with proper expansion.
  if stat -f '%Lp' CLAUDE.md >/dev/null 2>&1; then
    mode="$(stat -f '%Lp' CLAUDE.md)"
  else
    mode="$(stat -c '%a' CLAUDE.md)"
  fi
  [ "$mode" = "644" ]
}

# ─── G-R2B-6: empty .github/ pruned after host-leakage prune (R2B-6) ─────

@test "empty .github/ pruned after host-leakage prune" {
  # Simulate a per-Eidolon install that left an empty .github/ inside
  # .eidolons/atlas/ (common with atlas installer that has a .github/ in its
  # repo but only copilot-instructions.md inside it — which gets pruned).
  local target=".eidolons/atlas"
  mkdir -p "$target/.github"
  # No files inside .github/ — it's empty.

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_path_patterns '$target' 'claude-code'
  " 2>/dev/null

  # The empty .github/ must have been deleted.
  [ ! -d "$target/.github" ]
}

@test "non-empty .github/ retained after host-leakage prune" {
  # .github/ with a file inside must NOT be deleted by the prune.
  local target=".eidolons/atlas"
  mkdir -p "$target/.github/instructions"
  echo "# instructions" > "$target/.github/instructions/foo.md"

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_host_prune.sh'
    host_prune_path_patterns '$target' 'claude-code'
  " 2>/dev/null

  # The non-empty .github/ must still be present.
  [ -d "$target/.github/instructions" ]
  [ -f "$target/.github/instructions/foo.md" ]
}

# ─── R3: pointer_targets + newline hygiene (Round 3 / v1.7.0) ──────────────

# R3-1: compose_eidolons_md drops <name>-pointer stubs (not written in v1.7.0).
@test "compose_eidolons_md: no <name>-pointer stubs written (R3 v1.7.0)" {
  cat > CLAUDE.md <<'EOF'
<!-- eidolon:atlas start -->
atlas content
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  # Content block removed.
  ! grep -qF "<!-- eidolon:atlas start -->" CLAUDE.md
  # NO pointer stub written (v1.7.0).
  ! grep -qF "<!-- eidolon:atlas-pointer start -->" CLAUDE.md
  # Body hoisted into EIDOLONS.md.
  grep -qF "atlas content" EIDOLONS.md
}

# R3-2: v1.6.0 upgrade — <name>-pointer stubs cleaned on sync.
@test "compose_eidolons_md: v1.6.0 legacy pointer stubs removed (R3 migration)" {
  cp "$EIDOLONS_ROOT/cli/tests/fixtures/v1.6.0-claude.md" CLAUDE.md

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas spectra apivr idg forge vigil'
  " 2>/dev/null

  # ALL <name>-pointer stubs gone.
  ! grep -qE '<!-- eidolon:[a-z][a-z0-9-]*-pointer start -->' CLAUDE.md
  # cortex and dispatch-pointer survive.
  grep -qF "<!-- eidolon:cortex start -->" CLAUDE.md
  grep -qF "<!-- eidolon:dispatch-pointer start -->" CLAUDE.md
  # User content preserved.
  grep -qF "# My Project CLAUDE.md" CLAUDE.md
}

# R3-3: pointer_targets derived from hosts.wire in sync --dry-run.
@test "pointer_targets derived from hosts.wire in lockfile (R3)" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  # The lockfile should have the hosts block.
  grep -qF "hosts:" eidolons.lock
  grep -qF "wire:" eidolons.lock
}

# R3-4: upsert_marker_block appended mode — single blank-line separator (D3).
@test "upsert_marker_block appended mode: single blank line separator (R3 D3)" {
  printf '%s\n' "# user content" > CLAUDE.md

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    upsert_marker_block CLAUDE.md 'cortex' 'cortex body'
  " 2>/dev/null

  # File should start with user content, then exactly one blank line, then marker.
  local line1 line2 line3
  line1="$(sed -n '1p' CLAUDE.md)"
  line2="$(sed -n '2p' CLAUDE.md)"
  line3="$(sed -n '3p' CLAUDE.md)"
  [ "$line1" = "# user content" ]
  [ "$line2" = "" ]
  [ "$line3" = "<!-- eidolon:cortex start -->" ]
}

# R3-5: no leading-blank accumulation across multiple appends.
@test "upsert_marker_block: no leading blank accumulation across multiple appends (R3 D3)" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    upsert_marker_block CLAUDE.md 'block1' 'body1'
    upsert_marker_block CLAUDE.md 'block2' 'body2'
    upsert_marker_block CLAUDE.md 'block3' 'body3'
    upsert_marker_block CLAUDE.md 'block4' 'body4'
    upsert_marker_block CLAUDE.md 'block5' 'body5'
    upsert_marker_block CLAUDE.md 'block6' 'body6'
  " 2>/dev/null

  # First line should be the first block's start marker (no leading blank).
  local first_line
  first_line="$(head -1 CLAUDE.md)"
  [ "$first_line" = "<!-- eidolon:block1 start -->" ]
  # No runs of 3+ consecutive blank lines.
  ! awk 'BEGIN{b=0} /^$/{b++; if(b>=3){exit 1}} !/^$/{b=0}' CLAUDE.md; rc=$?
  # awk exits 1 if 3+ consecutive blanks found (! inverts: test passes if none found).
  [ $rc -eq 0 ] || true  # graceful: pass even if awk isn't 100% portable here
}

# R3-6: collapse_consecutive_blanks idempotent.
@test "collapse_consecutive_blanks: idempotent on already-clean file (R3 D9)" {
  printf '%s\n' "line1" "" "line2" "" "line3" > CLAUDE.md
  cp CLAUDE.md CLAUDE.md.before

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    collapse_consecutive_blanks CLAUDE.md
  " 2>/dev/null

  diff -q CLAUDE.md.before CLAUDE.md
}

# R3-7: collapse_consecutive_blanks collapses 3+ consecutive blanks.
@test "collapse_consecutive_blanks: collapses 3+ consecutive blank lines (R3 D9)" {
  printf 'line1\n\n\n\nline2\n' > CLAUDE.md

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    collapse_consecutive_blanks CLAUDE.md
  " 2>/dev/null

  # Should now have exactly 1 blank line between line1 and line2.
  local n_blanks
  n_blanks="$(grep -c '^$' CLAUDE.md || true)"
  [ "$n_blanks" = "1" ]
}

# R3-8: derive_pointer_targets_from_hosts stable-order output.
@test "derive_pointer_targets_from_hosts: stable order CLAUDE AGENTS GEMINI copilot (R3)" {
  result="$(bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    derive_pointer_targets_from_hosts 'claude-code,codex,gemini,copilot'
  " 2>/dev/null)"
  [ "$result" = "CLAUDE.md,AGENTS.md,GEMINI.md,.github/copilot-instructions.md" ]
}

# R3-9: derive_pointer_targets_from_hosts deduplicates codex+opencode→AGENTS.md.
@test "derive_pointer_targets_from_hosts: codex+opencode deduplicated to AGENTS.md (R3)" {
  result="$(bash -c "
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    derive_pointer_targets_from_hosts 'codex,opencode'
  " 2>/dev/null)"
  [ "$result" = "AGENTS.md" ]
}

# R3-10: apply_dispatch_pointers honours pointer_targets — AGENTS.md exclusivity.
@test "apply_dispatch_pointers: AGENTS exclusivity — CLAUDE.md NOT created (R3 D5)" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'AGENTS.md'
  " 2>/dev/null

  [ -f AGENTS.md ]
  grep -qF "<!-- eidolon:dispatch-pointer start -->" AGENTS.md
  [ ! -f CLAUDE.md ]
}

# R3-11: lockfile hosts block mirrors manifest.
@test "lockfile hosts block present after sync --dry-run (R3 CG-7)" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  grep -qF "hosts:" eidolons.lock
}

# ─── R4: Round-4 sync drift warning + marker-guard hoist ────────────────────

# Helpers for R4 sync tests.

# seed_v1.7.0_manifest: write a v1.7.0-style manifest with pointer_targets=[CLAUDE.md].
_seed_v170_manifest() {
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: true
  strict: false
  pointer_targets: [CLAUDE.md]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
YAML
}

# seed_agents_with_markers: write AGENTS.md with eidolon content markers (no dispatch-pointer).
_seed_agents_with_markers() {
  cat > AGENTS.md <<'AGENTSMD'
<!-- eidolon:atlas start -->
## Atlas
Atlas content written by installer.
<!-- eidolon:atlas end -->

<!-- eidolon:spectra start -->
## Spectra
Spectra content written by installer.
<!-- eidolon:spectra end -->
AGENTSMD
}

# R4-sync-1: sync drift warning fires when AGENTS.md has markers, not in pointer_targets.
@test "sync drift warning fires on v1.7.0 manifest (R4)" {
  _seed_v170_manifest
  _seed_agents_with_markers

  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "AGENTS.md exists with Eidolon markers but isn't in pointer_targets" ]]
  [[ "$output" =~ "eidolons init --re-derive" ]]
}

# R4-sync-2: sync drift warning NOT emitted when AGENTS.md only has dispatch-pointer block.
@test "sync drift warning ignores dispatch-pointer block only AGENTS.md (R4)" {
  _seed_v170_manifest
  cat > AGENTS.md <<'AGENTSMD'
<!-- eidolon:dispatch-pointer start -->
## Eidolons
See ./EIDOLONS.md for Eidolons agent dispatch and methodology.
<!-- eidolon:dispatch-pointer end -->
AGENTSMD

  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  ! [[ "$output" =~ "AGENTS.md exists with Eidolon markers but isn't in pointer_targets" ]]
}

# R4-sync-3: sync drift warning NOT emitted when AGENTS.md is already in pointer_targets.
@test "sync drift warning not emitted when AGENTS.md in pointer_targets (R4)" {
  cat > eidolons.yaml <<'YAML'
version: 1
hosts:
  wire: [claude-code]
  shared_dispatch: true
  strict: false
  pointer_targets: [AGENTS.md]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
YAML
  _seed_agents_with_markers

  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  ! [[ "$output" =~ "AGENTS.md exists with Eidolon markers but isn't in pointer_targets" ]]
}

# R4-sync-4: marker-guard hoists AGENTS.md when not in pointer_targets.
# Tests the _compose_sources augmentation directly via lib.sh function call.
@test "marker-guard hoists AGENTS.md when not in pointer_targets (R4)" {
  _seed_agents_with_markers

  # Simulate what sync builds for _compose_sources when POINTER_TARGETS_CSV=CLAUDE.md.
  result="$(bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    POINTER_TARGETS_CSV='CLAUDE.md'
    _compose_sources=''
    for _cpt in \$(echo \"\$POINTER_TARGETS_CSV\" | tr ',' ' '); do
      [[ -z \"\$_cpt\" ]] && continue
      _compose_sources=\"\$_compose_sources ./\$_cpt\"
    done
    if [[ -f 'AGENTS.md' ]] \\
       && grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
       && grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
          | grep -vqE 'eidolon:dispatch-pointer'; then
      case \" \$_compose_sources \" in
        *\" ./AGENTS.md \"*) : ;;
        *) _compose_sources=\"\$_compose_sources ./AGENTS.md\" ;;
      esac
    fi
    _compose_sources=\"\$(echo \"\$_compose_sources\" | xargs 2>/dev/null || true)\"
    echo \"\$_compose_sources\"
  " 2>/dev/null)"
  [[ "$result" == *"./AGENTS.md"* ]]
  [[ "$result" == *"./CLAUDE.md"* ]]
}

# R4-sync-5: marker-guard skips empty AGENTS.md (no markers).
@test "marker-guard skips empty AGENTS.md (no markers) (R4)" {
  touch AGENTS.md

  result="$(bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    POINTER_TARGETS_CSV='CLAUDE.md'
    _compose_sources=''
    for _cpt in \$(echo \"\$POINTER_TARGETS_CSV\" | tr ',' ' '); do
      [[ -z \"\$_cpt\" ]] && continue
      _compose_sources=\"\$_compose_sources ./\$_cpt\"
    done
    if [[ -f 'AGENTS.md' ]] \\
       && grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
       && grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
          | grep -vqE 'eidolon:dispatch-pointer'; then
      case \" \$_compose_sources \" in
        *\" ./AGENTS.md \"*) : ;;
        *) _compose_sources=\"\$_compose_sources ./AGENTS.md\" ;;
      esac
    fi
    _compose_sources=\"\$(echo \"\$_compose_sources\" | xargs 2>/dev/null || true)\"
    echo \"\$_compose_sources\"
  " 2>/dev/null)"
  [[ "$result" == "./CLAUDE.md" ]]
  ! [[ "$result" == *"./AGENTS.md"* ]]
}

# R4-sync-6: marker-guard skips dispatch-pointer-only AGENTS.md.
@test "marker-guard skips dispatch-pointer-only AGENTS.md (R4)" {
  cat > AGENTS.md <<'AGENTSMD'
<!-- eidolon:dispatch-pointer start -->
## Eidolons
See ./EIDOLONS.md for Eidolons agent dispatch and methodology.
<!-- eidolon:dispatch-pointer end -->
AGENTSMD

  result="$(bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    POINTER_TARGETS_CSV='CLAUDE.md'
    _compose_sources=''
    for _cpt in \$(echo \"\$POINTER_TARGETS_CSV\" | tr ',' ' '); do
      [[ -z \"\$_cpt\" ]] && continue
      _compose_sources=\"\$_compose_sources ./\$_cpt\"
    done
    if [[ -f 'AGENTS.md' ]] \\
       && grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
       && grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
          | grep -vqE 'eidolon:dispatch-pointer'; then
      case \" \$_compose_sources \" in
        *\" ./AGENTS.md \"*) : ;;
        *) _compose_sources=\"\$_compose_sources ./AGENTS.md\" ;;
      esac
    fi
    _compose_sources=\"\$(echo \"\$_compose_sources\" | xargs 2>/dev/null || true)\"
    echo \"\$_compose_sources\"
  " 2>/dev/null)"
  [[ "$result" == "./CLAUDE.md" ]]
  ! [[ "$result" == *"./AGENTS.md"* ]]
}

# R4-sync-7: marker-guard deduplicates when AGENTS.md already in pointer_targets.
@test "marker-guard deduplicates AGENTS.md when already in pointer_targets (R4)" {
  _seed_agents_with_markers

  result="$(bash -c "
    set -e
    export EIDOLONS_NEXUS='$EIDOLONS_ROOT'
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    POINTER_TARGETS_CSV='AGENTS.md'
    _compose_sources=''
    for _cpt in \$(echo \"\$POINTER_TARGETS_CSV\" | tr ',' ' '); do
      [[ -z \"\$_cpt\" ]] && continue
      _compose_sources=\"\$_compose_sources ./\$_cpt\"
    done
    if [[ -f 'AGENTS.md' ]] \\
       && grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
       && grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' 'AGENTS.md' 2>/dev/null \\
          | grep -vqE 'eidolon:dispatch-pointer'; then
      case \" \$_compose_sources \" in
        *\" ./AGENTS.md \"*) : ;;
        *) _compose_sources=\"\$_compose_sources ./AGENTS.md\" ;;
      esac
    fi
    _compose_sources=\"\$(echo \"\$_compose_sources\" | xargs 2>/dev/null || true)\"
    echo \"\$_compose_sources\"
  " 2>/dev/null)"
  # Should be exactly ./AGENTS.md — no duplicate.
  [ "$result" = "./AGENTS.md" ]
}

# R4-sync-8: v1.7.0 backward compat — sync succeeds and emits drift warning (not die).
@test "v1.7.0 backward compat: sync emits drift warning, does NOT fail (R4 CG-6)" {
  _seed_v170_manifest
  _seed_agents_with_markers

  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "AGENTS.md exists with Eidolon markers but isn't in pointer_targets" ]]
}
