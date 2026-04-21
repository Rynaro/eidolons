#!/usr/bin/env bats

# install.bats — verifies cli/install.sh:
#   * succeeds when EIDOLONS_REPO is a local file:// URL (no github fetch)
#   * symlinks the CLI into EIDOLONS_BIN_DIR
#   * is idempotent on re-run
#   * detects and uses a pre-existing yq (short-circuiting the download path)
#   * errors cleanly when the nexus repo is unreachable
#
# The full "yq absent → auto-download from github" path needs network and
# is covered in CI's install-e2e job (.github/workflows/ci.yml) rather
# than here, to keep the bats suite fast and offline-safe. Every test
# below shadows PATH with a fake yq so the installer's "yq already
# present" branch is the one exercised.

load helpers

setup() {
  export HOME_TMP="$BATS_TEST_TMPDIR/home"
  export EIDOLONS_HOME="$HOME_TMP/.eidolons"
  export EIDOLONS_BIN_DIR="$HOME_TMP/.local/bin"
  export EIDOLONS_REPO="file://$EIDOLONS_ROOT"
  # Use the checkout's current HEAD SHA rather than a branch name.
  # GitHub Actions' actions/checkout produces a detached HEAD with no
  # `main` branch locally, and install.sh now accepts SHAs in
  # EIDOLONS_REF — so this works uniformly on dev boxes and in CI.
  EIDOLONS_REF="$(git -C "$EIDOLONS_ROOT" rev-parse HEAD)"
  export EIDOLONS_REF
  mkdir -p "$HOME_TMP" "$EIDOLONS_BIN_DIR"

  # Shadow a fake yq into PATH so we never hit github during tests.
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/yq" <<'EOF'
#!/usr/bin/env bash
echo "yq version 4.0.0 (fake)"
EOF
  chmod +x "$FAKE_BIN/yq"
  export PATH="$FAKE_BIN:$PATH"
}

@test "install.sh: succeeds end-to-end with local repo" {
  run bash "$EIDOLONS_ROOT/cli/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$EIDOLONS_BIN_DIR/eidolons" ]
  [ -f "$EIDOLONS_HOME/nexus/cli/eidolons" ]
  [[ "$output" =~ Done ]]
}

@test "install.sh: installed CLI reports correct version" {
  bash "$EIDOLONS_ROOT/cli/install.sh" >/dev/null
  run "$EIDOLONS_BIN_DIR/eidolons" version
  [ "$status" -eq 0 ]
  [[ "$output" =~ eidolons ]]
}

@test "install.sh: second run is idempotent" {
  bash "$EIDOLONS_ROOT/cli/install.sh" >/dev/null
  run bash "$EIDOLONS_ROOT/cli/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$EIDOLONS_BIN_DIR/eidolons" ]
}

@test "install.sh: short-circuits when yq already present" {
  run bash "$EIDOLONS_ROOT/cli/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ yq\ already\ present ]]
  [[ ! "$output" =~ Downloading\ yq ]]
}

@test "install.sh: fails cleanly if EIDOLONS_REPO is unreachable" {
  EIDOLONS_REPO="file:///nonexistent/path/that/doesnt/exist" run bash "$EIDOLONS_ROOT/cli/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" =~ Failed\ to\ fetch ]]
}

@test "install.sh: accepts a commit SHA in EIDOLONS_REF" {
  # Run git in the checkout to get a valid SHA we can pin to.
  local sha
  sha="$(git -C "$EIDOLONS_ROOT" rev-parse HEAD)"
  EIDOLONS_REF="$sha" run bash "$EIDOLONS_ROOT/cli/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$EIDOLONS_BIN_DIR/eidolons" ]
}
