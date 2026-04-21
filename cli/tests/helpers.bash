#!/usr/bin/env bash
# cli/tests/helpers.bash — shared bats fixtures for the eidolons CLI.
#
# Every test sources this file, which sets up an isolated EIDOLONS_HOME
# pointing at the current checkout (so the CLI dispatcher can find
# roster/index.yaml) plus a tmp project dir that becomes $PWD for the
# test body. Teardown removes the tmp project dir.

# Absolute path to the checkout root (two levels up from this file).
EIDOLONS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export EIDOLONS_ROOT

# Path to the CLI entrypoint under test.
EIDOLONS_BIN="$EIDOLONS_ROOT/cli/eidolons"
export EIDOLONS_BIN

# Convenience: run the CLI. Bats captures output in $output and status in $status.
eidolons() {
  "$EIDOLONS_BIN" "$@"
}

setup() {
  # Point every CLI invocation at the current checkout as its "nexus".
  # The dispatcher checks EIDOLONS_HOME/nexus first; we bypass that with
  # EIDOLONS_NEXUS, which lib.sh honors directly (see lib.sh:11).
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_HOME="$BATS_TEST_TMPDIR/eidolons-home"
  mkdir -p "$EIDOLONS_HOME"

  # Each test runs in its own pristine project dir.
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
}

teardown() {
  cd "$EIDOLONS_ROOT"
}

# Write a minimal valid eidolons.yaml into $PWD.
seed_manifest() {
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [claude-code]
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
}

# Write a minimal valid eidolons.lock into $PWD (requires seed_manifest first).
seed_lock() {
  cat > eidolons.lock <<'EOF'
generated_at: "2026-04-21T00:00:00Z"
eidolons_cli_version: "1.0.0"
nexus_commit: "test"
members:
  - name: atlas
    version: "1.0.0"
    resolved: "github:Rynaro/ATLAS@test"
    target: "./agents/atlas"
    hosts_wired: ["claude-code"]
EOF
}

# Seed a per-Eidolon install manifest so doctor's per-member check passes.
seed_agent_install_manifest() {
  local name="$1"
  mkdir -p "agents/$name"
  cat > "agents/$name/install.manifest.json" <<EOF
{
  "name": "$name",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF
}
