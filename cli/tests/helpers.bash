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
    target: "./.eidolons/atlas"
    hosts_wired: ["claude-code"]
EOF
}

# Seed a per-Eidolon install manifest so doctor's per-member check passes.
seed_agent_install_manifest() {
  local name="$1"
  mkdir -p ".eidolons/$name"
  cat > ".eidolons/$name/install.manifest.json" <<EOF
{
  "name": "$name",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF
}

# Write an eidolons.yaml with a custom set of members & constraints.
# Args: name=constraint pairs, e.g.
#   seed_manifest_with atlas=^1.0.0 spectra=^4.2.0
seed_manifest_with() {
  local pairs=("$@")
  {
    echo "version: 1"
    echo "hosts:"
    echo "  wire: [claude-code]"
    echo "members:"
    local p name constraint repo
    for p in "${pairs[@]}"; do
      name="${p%%=*}"
      constraint="${p#*=}"
      case "$name" in
        atlas)   repo="github:Rynaro/ATLAS" ;;
        spectra) repo="github:Rynaro/SPECTRA" ;;
        apivr)   repo="github:Rynaro/APIVR-Delta" ;;
        idg)     repo="github:Rynaro/IDG" ;;
        forge)   repo="github:Rynaro/FORGE" ;;
        vigil)   repo="github:Rynaro/VIGIL" ;;
        *)       repo="github:Rynaro/$name" ;;
      esac
      echo "  - name: $name"
      echo "    version: \"$constraint\""
      echo "    source: $repo"
    done
  } > eidolons.yaml
}

# Write an eidolons.lock with a custom set of resolved versions.
# Args: name=version pairs, e.g.
#   seed_lock_with_versions atlas=1.0.0 spectra=4.2.8
seed_lock_with_versions() {
  local pairs=("$@")
  {
    echo "generated_at: \"2026-04-21T00:00:00Z\""
    echo "eidolons_cli_version: \"1.0.0\""
    echo "nexus_commit: \"test\""
    echo "members:"
    local p name version repo
    for p in "${pairs[@]}"; do
      name="${p%%=*}"
      version="${p#*=}"
      case "$name" in
        atlas)   repo="Rynaro/ATLAS" ;;
        spectra) repo="Rynaro/SPECTRA" ;;
        apivr)   repo="Rynaro/APIVR-Delta" ;;
        idg)     repo="Rynaro/IDG" ;;
        forge)   repo="Rynaro/FORGE" ;;
        vigil)   repo="Rynaro/VIGIL" ;;
        *)       repo="Rynaro/$name" ;;
      esac
      echo "  - name: $name"
      echo "    version: \"$version\""
      echo "    resolved: \"github:$repo@test\""
      echo "    target: \"./.eidolons/$name\""
      echo "    hosts_wired: [\"claude-code\"]"
    done
  } > eidolons.lock
}

# Install a fake `git` on PATH that controls remote tag listings + clone behaviour
# for upgrade tests. Reads control variables from the environment:
#   FAKE_LSREMOTE_TAGS  — newline-separated tag list returned for `git ls-remote`
#                         on the nexus repo. Each tag should be like "v1.0.0".
#   FAKE_NEXUS_HEAD_TAG — when set, `git describe --tags --exact-match` echoes it.
#   FAKE_CLONE_RESULT   — "ok" (default) or "fail" — clone behaviour.
#   FAKE_CLONE_LOG      — path to file appended with one line per `git clone` arg list.
#   FAKE_FETCH_RESULT   — "ok" (default) or "fail" — `git fetch` behaviour.
#   FAKE_FETCH_LOG      — path to file appended with one line per `git fetch`.
#   FAKE_RESET_LOG      — path to file appended with one line per `git reset`.
#   FAKE_INSTALL_LOG    — path to file appended on each per-Eidolon install.sh
#                         invocation (set by the fake clone, which materialises
#                         a stub install.sh that logs and produces a manifest).
setup_fake_git_for_upgrade() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"
  : "${FAKE_CLONE_LOG:=$BATS_TEST_TMPDIR/clone.log}"
  : "${FAKE_FETCH_LOG:=$BATS_TEST_TMPDIR/fetch.log}"
  : "${FAKE_RESET_LOG:=$BATS_TEST_TMPDIR/reset.log}"
  : "${FAKE_INSTALL_LOG:=$BATS_TEST_TMPDIR/install.log}"
  export FAKE_CLONE_LOG FAKE_FETCH_LOG FAKE_RESET_LOG FAKE_INSTALL_LOG
  : "${FAKE_CLONE_RESULT:=ok}"
  : "${FAKE_FETCH_RESULT:=ok}"
  export FAKE_CLONE_RESULT FAKE_FETCH_RESULT
  cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
# Fake git for upgrade tests. Falls back to the real git for any operation
# we don't model. Operations we model:
#   git ls-remote --tags ... <repo>     → echoes lines from $FAKE_LSREMOTE_TAGS
#   git -C DIR describe --tags --exact-match HEAD
#                                       → echoes $FAKE_NEXUS_HEAD_TAG (or fails)
#   git -C DIR rev-parse [--short] HEAD → echoes a stable test SHA
#   git -C DIR fetch ...                → logs + honors $FAKE_FETCH_RESULT
#   git -C DIR reset --hard FETCH_HEAD  → logs + always succeeds
#   git clone ... <repo> <dest>         → logs + when ok, materialises a stub
#                                         Eidolon at <dest>
DIR=""
ARGS=("$@")
# Extract -C DIR if present.
if [[ "${ARGS[0]:-}" == "-C" ]]; then
  DIR="${ARGS[1]}"
  set -- "${ARGS[@]:2}"
fi
op="${1:-}"
case "$op" in
  ls-remote)
    # Always echo the FAKE_LSREMOTE_TAGS as if from the nexus repo.
    if [[ -n "${FAKE_LSREMOTE_TAGS:-}" ]]; then
      while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        printf "0000000000000000000000000000000000000000\trefs/tags/%s\n" "$tag"
      done <<<"$FAKE_LSREMOTE_TAGS"
    fi
    exit 0
    ;;
  describe)
    # Per-clone tag marker takes precedence over the global nexus head tag.
    if [[ -n "$DIR" && -f "$DIR/.git/_fake_tag" ]]; then
      cat "$DIR/.git/_fake_tag"
      exit 0
    fi
    if [[ -n "${FAKE_NEXUS_HEAD_TAG:-}" ]]; then
      echo "$FAKE_NEXUS_HEAD_TAG"
      exit 0
    fi
    exit 128
    ;;
  rev-parse)
    # Honor --short
    if [[ "${2:-}" == "--short" ]]; then
      echo "abc1234"
    else
      echo "abc1234567890abcdef1234567890abcdef123456"
    fi
    exit 0
    ;;
  fetch)
    printf "fetch %s -- %s\n" "$DIR" "$*" >> "$FAKE_FETCH_LOG"
    [[ "${FAKE_FETCH_RESULT:-ok}" == "ok" ]] && exit 0 || exit 128
    ;;
  reset)
    printf "reset %s -- %s\n" "$DIR" "$*" >> "$FAKE_RESET_LOG"
    exit 0
    ;;
  init)
    exit 0
    ;;
  remote)
    exit 0
    ;;
  checkout)
    exit 0
    ;;
  clone)
    # Find dest = last positional after stripping flags.
    shift
    repo=""
    dest=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --depth|--branch) shift 2 ;;
        --*) shift ;;
        *)
          if [[ -z "$repo" ]]; then repo="$1"
          else dest="$1"
          fi
          shift
          ;;
      esac
    done
    printf "clone %s -> %s\n" "$repo" "$dest" >> "$FAKE_CLONE_LOG"
    if [[ "${FAKE_CLONE_RESULT:-ok}" != "ok" ]]; then
      echo "fake-git: clone forced fail" >&2
      exit 128
    fi
    # Materialise a minimal EIIS-conformant Eidolon at $dest.
    mkdir -p "$dest/.git"
    : > "$dest/AGENTS.md"
    : > "$dest/CLAUDE.md"
    : > "$dest/agent.md"
    : > "$dest/README.md"
    cat > "$dest/install.sh" <<'STUB'
#!/usr/bin/env bash
# Stub installer used by upgrade.bats. Logs invocation and emits a manifest.
LOG="${FAKE_INSTALL_LOG:-/dev/null}"
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
mkdir -p "$TGT"
NAME="$(basename "$TGT")"
# The version recorded by the Eidolon's installer (not the git tag).
cat > "$TGT/install.manifest.json" <<JSON
{
  "name": "$NAME",
  "version": "0.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
JSON
echo "install $NAME at $TGT (hosts=$HOSTS)" >> "$LOG"
exit 0
STUB
    chmod +x "$dest/install.sh"
    # Make `git -C $dest describe --tags ...` return a tag from the version
    # encoded in the dest name (e.g. atlas@1.0.5 → v1.0.5). Stash it in a
    # marker file the fake-git reads back below.
    ver=""
    case "$dest" in
      *@*) ver="${dest##*@}" ;;
    esac
    if [[ -n "$ver" ]]; then
      echo "v$ver" > "$dest/.git/_fake_tag"
    fi
    exit 0
    ;;
esac
# Fallback: if a clone marker exists, satisfy describe/rev-parse from it.
if [[ -n "$DIR" && -f "$DIR/.git/_fake_tag" ]]; then
  case "$op" in
    describe) cat "$DIR/.git/_fake_tag"; exit 0 ;;
    rev-parse)
      if [[ "${2:-}" == "--short" ]]; then echo "abc1234"; else echo "abc1234567890abcdef1234567890abcdef123456"; fi
      exit 0 ;;
  esac
fi
# Anything we don't model is a soft no-op so dependent commands don't hang.
exit 0
EOF
  chmod +x "$FAKE_BIN/git"
  export PATH="$FAKE_BIN:$PATH"
}
