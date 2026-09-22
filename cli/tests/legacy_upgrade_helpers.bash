# Reduced, immutable historical install-state snapshots; see fixtures/legacy-upgrade/sources.tsv.
# The patched updater is invoked directly: the dispatcher in a full old install
# would deliberately select its OLD updater. Never copy modern code into the old tree.
legacy_install() {
  local version="$1"
  export EIDOLONS_NEXUS="$EIDOLONS_HOME/nexus"
  mkdir -p "$EIDOLONS_NEXUS" "$EIDOLONS_HOME/cache"
  tar -xzf "$EIDOLONS_ROOT/cli/tests/fixtures/legacy-upgrade/$version.tar.gz" -C "$EIDOLONS_NEXUS"
  git -C "$EIDOLONS_NEXUS" init -q
  git -C "$EIDOLONS_NEXUS" config user.email fixture@example.invalid
  git -C "$EIDOLONS_NEXUS" config user.name Fixture
  git -C "$EIDOLONS_NEXUS" add -A
  git -C "$EIDOLONS_NEXUS" commit -qm "historical snapshot $version"
  git -C "$EIDOLONS_NEXUS" tag "v$version"
  printf 'v%s\n' "$version" > "$EIDOLONS_NEXUS/.install_ref"
  # v1.10 predates the split; the other fixtures retain a configured channel.
  if [[ "$version" != 1.10.0 ]]; then
    printf 'release/custom\n' > "$EIDOLONS_NEXUS/.roster_ref"
  fi
  export EIDOLONS_INTEGRITY_ENFORCEMENT=strict
  export EIDOLONS_REPO="file://$BATS_TEST_TMPDIR/target"
  export LEGACY_VERSION="$version"
}

legacy_target() {
  local target="$BATS_TEST_TMPDIR/target"
  mkdir -p "$target/cli/src/ui" "$target/roster"
  cp "$EIDOLONS_ROOT/cli/eidolons" "$target/cli/eidolons"
  cp "$EIDOLONS_ROOT/cli/src/"{lib,upgrade_self,upgrade}.sh "$target/cli/src/"
  cp -R "$EIDOLONS_ROOT/cli/src/ui/." "$target/cli/src/ui/"
  printf '9.0.0\n' > "$target/VERSION"
  # Deliberately no tracked .gitignore: metadata writes must not dirty the target.
  printf 'integrity:\n  enforcement: strict\nnexus:\n  versions:\n    releases: {}\n' > "$target/roster/index.yaml"
  if [[ "${1:-}" == smoke-failure ]]; then
    printf '#!/usr/bin/env bash\nprintf smoke-reached > "$BATS_TEST_TMPDIR/smoke-marker"\nexit 42\n' > "$target/cli/eidolons"
  elif [[ "${1:-}" == smoke-interrupt ]]; then
    printf '#!/usr/bin/env bash\nprintf smoke-reached > "$BATS_TEST_TMPDIR/smoke-marker"\nkill -TERM "$PPID"\nexit 42\n' > "$target/cli/eidolons"
  fi
  git -C "$target" init -qb main
  git -C "$target" config user.email fixture@example.invalid
  git -C "$target" config user.name Fixture
  git -C "$target" add -A
  git -C "$target" commit -qm target
  git -C "$target" tag v9.0.0
  local commit tree archive
  commit="$(git -C "$target" rev-parse HEAD)"
  tree="$(git -C "$target" rev-parse 'HEAD^{tree}')"
  archive="$(git -C "$target" archive --format=tar --prefix=eidolons-9.0.0/ HEAD | legacy_sha256)"
  cat >> "$target/roster/index.yaml" <<RECORD
      "9.0.0":
        commit: "$commit"
        tree: "$tree"
        archive_sha256: "$archive"
RECORD
  # Replace the empty mapping before adding the release record.
  sed 's/releases: {}/releases:/' "$target/roster/index.yaml" > "$target/roster/tmp"
  mv "$target/roster/tmp" "$target/roster/index.yaml"
  git -C "$target" add -A
  git -C "$target" commit -qm 'publish actual target hashes after tag'
}

legacy_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}';
  else shasum -a 256 | awk '{print $1}'; fi
}

legacy_snapshot() {
  python3 - "$1" <<'PY'
import hashlib, os, pathlib, sys
root=pathlib.Path(sys.argv[1]); digest=hashlib.sha256()
for current, dirs, files in os.walk(root):
    dirs[:]=sorted(d for d in dirs if d != '.git')
    for name in sorted(files):
        p=pathlib.Path(current)/name
        digest.update(str(p.relative_to(root)).encode()+b'\0')
        digest.update(p.read_bytes()+b'\0')
print(digest.hexdigest())
PY
}

legacy_settings() {
  export HOME="$BATS_TEST_TMPDIR/user-home"
  mkdir -p "$HOME/.codex" "$HOME/.claude" "$TEST_PROJECT/.eidolons/atlas"
  printf 'model = "my-model"\n' > "$HOME/.codex/config.toml"
  printf '{"theme":"custom"}\n' > "$HOME/.claude/settings.json"
  printf 'version: 1\n' > "$TEST_PROJECT/eidolons.yaml"
  printf 'user lock bytes\n' > "$TEST_PROJECT/eidolons.lock"
  printf 'personal agent edits\n' > "$TEST_PROJECT/.eidolons/atlas/agent.md"
  git -C "$TEST_PROJECT" init -q
  git -C "$TEST_PROJECT" -c user.name=Fixture -c user.email=fixture@example.invalid add -A
  git -C "$TEST_PROJECT" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm consumer
  printf '# dirty consumer\n' >> "$TEST_PROJECT/eidolons.yaml"
  OLD_TREE="$(legacy_snapshot "$EIDOLONS_NEXUS")"
  OLD_SETTINGS="$(legacy_snapshot "$HOME")"
  OLD_CONSUMER="$(legacy_snapshot "$TEST_PROJECT")"
}

legacy_assert_preserved() {
  [ "$(legacy_snapshot "$EIDOLONS_NEXUS")" = "$OLD_TREE" ]
  [ "$(legacy_snapshot "$HOME")" = "$OLD_SETTINGS" ]
  [ "$(legacy_snapshot "$TEST_PROJECT")" = "$OLD_CONSUMER" ]
  run bash "$EIDOLONS_NEXUS/cli/eidolons" --version --quiet
  [ "$status" -eq 0 ]
  [ "$output" = "eidolons $LEGACY_VERSION" ]
  [ ! -d "$EIDOLONS_HOME/nexus.prev" ]
}

legacy_upgrade() {
  bash -c 'export LEGACY_UPDATER_PID=$$; exec bash "$@"' _ "$EIDOLONS_ROOT/cli/src/upgrade_self.sh" "$@"
}

# Fault injection around the real clone transport/materialization boundary.
# The self-updater uses Git, not an archive extractor. Checkout faults clone
# objects without checking them out, then fail/interrupt before materialization.
legacy_clone_fault() {
  export LEGACY_REAL_GIT="${LEGACY_REAL_GIT:-$(command -v git)}" LEGACY_FAULT="$1"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == clone ]]; then
  printf '%s\n' "$LEGACY_FAULT" > "$BATS_TEST_TMPDIR/fault-marker"
  case "$LEGACY_FAULT" in
    checkout-*) "$LEGACY_REAL_GIT" clone --no-checkout "${@:2}" || exit $? ;;
  esac
  case "$LEGACY_FAULT" in
    *-interrupt) kill -TERM "$PPID"; exit 143 ;;
    *) exit 42 ;;
  esac
fi
exec "$LEGACY_REAL_GIT" "$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
