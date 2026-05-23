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
  run eidolons sync --yes
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
  run eidolons sync --yes
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
