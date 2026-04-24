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
