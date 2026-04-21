#!/usr/bin/env bats

load helpers

setup_fake_git() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  echo "fake-git: clone blocked in tests" >&2
  exit 128
fi
exec /usr/bin/env git-real "$@" 2>/dev/null || true
EOF
  chmod +x "$FAKE_BIN/git"
  export PATH="$FAKE_BIN:$PATH"
}

@test "add: fails without existing manifest" {
  run eidolons add atlas
  [ "$status" -ne 0 ]
  [[ "$output" =~ No\ eidolons\.yaml ]]
}

@test "add: appends a new member entry" {
  setup_fake_git
  seed_manifest
  # seed_manifest only includes atlas — add spectra.
  run eidolons add spectra
  # sync will fail — but the manifest-append happens before sync.
  run cat eidolons.yaml
  [[ "$output" =~ spectra ]]
  [[ "$output" =~ atlas ]]
}

@test "add: skips members already in manifest" {
  setup_fake_git
  seed_manifest
  run eidolons add atlas
  # Count atlas occurrences — should still be exactly one name entry.
  count=$(grep -c '^  - name: atlas' eidolons.yaml)
  [ "$count" -eq 1 ]
}

@test "add: rejects unknown Eidolon" {
  seed_manifest
  run eidolons add not-a-real-eidolon
  [ "$status" -ne 0 ]
  [[ "$output" =~ not\ found ]]
}

@test "add: with no arguments prints usage and exits 2" {
  seed_manifest
  run eidolons add
  [ "$status" -eq 2 ]
  [[ "$output" =~ Usage:\ eidolons\ add ]]
}

@test "add -h: help prints" {
  run eidolons add -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage:\ eidolons\ add ]]
}
