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
    apply_dispatch_pointers
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

# G-A1.1 cont. — AGENTS.md is NOT written by the dispatch-pointer pass.
@test "dispatch pointer: AGENTS.md is not created (it is the target of pointers)" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers
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
    apply_dispatch_pointers
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
    apply_dispatch_pointers
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
    apply_dispatch_pointers
  " 2>/dev/null

  cp CLAUDE.md CLAUDE.md.first
  cp GEMINI.md GEMINI.md.first
  cp .github/copilot-instructions.md copilot.first

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers
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
    apply_dispatch_pointers
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
    apply_dispatch_pointers
  " 2>/dev/null
  diff -q CLAUDE.md.first CLAUDE.md
}

# G-A1 GEMINI opt-out — EIDOLONS_NO_GEMINI=1 skips GEMINI.md.
@test "dispatch pointer: EIDOLONS_NO_GEMINI=1 skips GEMINI.md but writes the others" {
  bash -c "
    set -e
    export EIDOLONS_NO_GEMINI=1
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers
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

  # CLAUDE.md now has atlas-pointer block, not the original content block.
  [ ! "$(grep -cF '<!-- eidolon:atlas start -->' CLAUDE.md)" = "0" ] || true
  grep -qF "<!-- eidolon:atlas-pointer start -->" CLAUDE.md
  ! grep -qF "<!-- eidolon:atlas start -->" CLAUDE.md

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

# G-B1.3 — compose_eidolons_md does NOT hoist from AGENTS.md.
@test "compose_eidolons_md leaves AGENTS.md untouched" {
  # Seed AGENTS.md with a per-eidolon block.
  cat > AGENTS.md <<'EOF'
<!-- eidolon:atlas start -->
agents atlas content
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    . '$EIDOLONS_ROOT/cli/src/lib_eidolons_md.sh'
    compose_eidolons_md 'atlas'
  " 2>/dev/null

  # AGENTS.md must be byte-identical (composition does NOT hoist from AGENTS.md).
  grep -qF "<!-- eidolon:atlas start -->" AGENTS.md
  grep -qF "agents atlas content" AGENTS.md
  ! grep -qF "<!-- eidolon:atlas-pointer start -->" AGENTS.md

  # EIDOLONS.md not created (no source content in CLAUDE.md).
  [ ! -f "EIDOLONS.md" ]
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

# G-B2.1 — apply_dispatch_pointers with hosts_csv=claude-code: only CLAUDE.md
# is written; GEMINI.md and copilot-instructions.md are NOT created.
@test "dispatch pointer host-gated on claude-code" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_dispatch_pointers 'claude-code'
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
    apply_dispatch_pointers 'claude-code,gemini,copilot'
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
    apply_dispatch_pointers 'gemini'
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

# ─── G-B4: AGENTS.md supplementary pointer (Block 4) ─────────────────────

# G-B4.1 — apply_agents_md_pointer injects eidolons-md-pointer when AGENTS.md exists.
@test "AGENTS.md supplementary pointer" {
  # Create AGENTS.md (simulating codex writer).
  cat > AGENTS.md <<'EOF'
<!-- eidolon:atlas start -->
atlas methodology
<!-- eidolon:atlas end -->
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_agents_md_pointer
  " 2>/dev/null

  grep -qF "<!-- eidolon:eidolons-md-pointer start -->" AGENTS.md
  grep -qF "EIDOLONS.md" AGENTS.md
  # Per-eidolon blocks still present (not hoisted from AGENTS.md).
  grep -qF "<!-- eidolon:atlas start -->" AGENTS.md
  grep -qF "atlas methodology" AGENTS.md
}

# G-B4.2 — apply_agents_md_pointer does NOT create AGENTS.md when absent.
@test "AGENTS.md not created when codex absent" {
  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_agents_md_pointer
  " 2>/dev/null

  [ ! -f "AGENTS.md" ]
}

# G-B4.3 — apply_agents_md_pointer is idempotent.
@test "AGENTS.md supplementary pointer idempotent" {
  cat > AGENTS.md <<'EOF'
atlas content
EOF

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_agents_md_pointer
  " 2>/dev/null

  cp AGENTS.md AGENTS.md.first

  bash -c "
    set -e
    . '$EIDOLONS_ROOT/cli/src/lib.sh' >/dev/null 2>&1
    apply_agents_md_pointer
  " 2>/dev/null

  diff -q AGENTS.md.first AGENTS.md
}

# ─── G-B6: lockfile composition block (Block 6) ───────────────────────────

# G-B6.1 — eidolons sync --dry-run produces a lockfile with a composition: block.
@test "lockfile composition block" {
  seed_manifest
  run eidolons sync --dry-run
  [ "$status" -eq 0 ]
  grep -qF "composition:" eidolons.lock
  grep -qF "target: EIDOLONS.md" eidolons.lock
  grep -qF "hoisted_from:" eidolons.lock
  grep -q "CLAUDE.md" eidolons.lock
  grep -qF "agents_md_role: canonical-with-pointer" eidolons.lock
  grep -qF "schema_version: 1" eidolons.lock
}
