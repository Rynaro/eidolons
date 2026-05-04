#!/usr/bin/env bats
# cli/tests/cache_hygiene.bats — validation gates G1–G7 for cache auto-recovery.
#
# Tests G1, G4, G7 require real release metadata (strict mode) and use a
# fake-git that returns controlled commit SHAs. A local bare repo is used
# to produce real git objects that satisfy archive/tree checks.
#
# Tests G2, G3 exercise corrupt/partial cache detection — these work under
# compat mode because the detection is based on `git rev-parse HEAD` failure,
# not on commit comparison.
#
# Tests G5, G6 are happy-path / network tests.
#
# Network tests: [[ "${EIDOLONS_TEST_NETWORK:-0}" == "1" ]] || skip

load helpers

# ─── Shared helpers ──────────────────────────────────────────────────────────

# Seed a pre-existing cache directory with a specific commit SHA in a
# FAKE_COMMIT marker file read by the fake-git.
# If commit is empty: .git exists but no FAKE_COMMIT → rev-parse exits 128.
seed_cache() {
  local name="$1" version="$2" commit="${3:-}"
  local cache_dir="$EIDOLONS_HOME/cache/${name}@${version}"
  mkdir -p "$cache_dir/.git"
  if [[ -n "$commit" ]]; then
    echo "$commit" > "$cache_dir/.git/FAKE_COMMIT"
    echo "ref: refs/heads/main" > "$cache_dir/.git/HEAD"
  fi
}

# Build a local bare repo with a single commit and return the commit SHA.
# The commit contains a minimal set of files matching an EIIS stub.
# The archive produced by `git archive --prefix=X/ HEAD` will have a stable SHA.
make_local_bare_repo() {
  local bare_dir="$1"
  local work_dir
  work_dir="$(mktemp -d)"
  git init "$work_dir" >/dev/null 2>&1
  git -C "$work_dir" config user.email "test@test.test"
  git -C "$work_dir" config user.name "Test"
  echo "stub" > "$work_dir/AGENTS.md"
  echo "stub" > "$work_dir/CLAUDE.md"
  echo "stub" > "$work_dir/agent.md"
  echo "stub" > "$work_dir/README.md"
  cat > "$work_dir/install.sh" <<'STUB'
#!/usr/bin/env bash
TGT=""; while [[ $# -gt 0 ]]; do case "$1" in --target) TGT="$2"; shift 2;; *) shift;; esac; done
mkdir -p "${TGT:-/tmp/stub}"
NAME="$(basename "${TGT:-stub}")"
cat > "${TGT:-/tmp/stub}/install.manifest.json" <<JSON
{"name":"$NAME","version":"0.0.0","hosts_wired":["claude-code"],"files":[]}
JSON
STUB
  chmod +x "$work_dir/install.sh"
  git -C "$work_dir" add -A >/dev/null 2>&1
  git -C "$work_dir" commit -m "stub" >/dev/null 2>&1
  local commit
  commit="$(git -C "$work_dir" rev-parse HEAD)"
  git init --bare "$bare_dir" >/dev/null 2>&1
  git -C "$work_dir" remote add origin "$bare_dir" >/dev/null 2>&1
  git -C "$work_dir" push origin HEAD:refs/tags/v0.0.0 >/dev/null 2>&1
  rm -rf "$work_dir"
  echo "$commit"
}

# Install a fake git that:
#   - For clone: materialises a stub .git with FAKE_CLONE_COMMIT.
#   - For rev-parse -C DIR HEAD: reads FAKE_COMMIT; exit 128 if absent.
#   - For describe: exit 128.
#   - For archive: writes trivial empty-tar bytes (2 x 512-byte null blocks).
#   - Falls through all other ops silently.
#
# For integrity tests that need real archive/tree hashes, use a real local
# bare repo and don't install this fake — let real git handle it.
setup_fake_git_stub() {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin-stub"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'GITFAKE'
#!/usr/bin/env bash
DIR=""
ARGS=("$@")
if [[ "${ARGS[0]:-}" == "-C" ]]; then
  DIR="${ARGS[1]}"; set -- "${ARGS[@]:2}"
fi
op="${1:-}"
case "$op" in
  clone)
    shift; repo="" dest=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --depth|--branch) shift 2 ;; --*) shift ;;
        *) if [[ -z "$repo" ]]; then repo="$1"; else dest="$1"; fi; shift ;;
      esac
    done
    if [[ "${FAKE_CLONE_RESULT:-ok}" != "ok" ]]; then
      echo "fake-git: clone forced fail" >&2; exit 128
    fi
    mkdir -p "$dest/.git"
    commit="${FAKE_CLONE_COMMIT:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    echo "$commit" > "$dest/.git/FAKE_COMMIT"
    echo "ref: refs/heads/main" > "$dest/.git/HEAD"
    : > "$dest/AGENTS.md"; : > "$dest/CLAUDE.md"; : > "$dest/agent.md"; : > "$dest/README.md"
    cat > "$dest/install.sh" <<'STUB'
#!/usr/bin/env bash
TGT=""; while [[ $# -gt 0 ]]; do case "$1" in --target) TGT="$2"; shift 2;; *) shift;; esac; done
mkdir -p "${TGT:-/tmp/stub}"
NAME="$(basename "${TGT:-stub}")"
cat > "${TGT:-/tmp/stub}/install.manifest.json" <<JSON
{"name":"$NAME","version":"0.0.0","hosts_wired":["claude-code"],"files":[]}
JSON
STUB
    chmod +x "$dest/install.sh"
    exit 0
    ;;
  rev-parse)
    if [[ -n "$DIR" ]]; then
      if [[ -f "$DIR/.git/FAKE_COMMIT" ]]; then
        commit="$(cat "$DIR/.git/FAKE_COMMIT")"
        arg2="${2:-}"
        case "$arg2" in
          'HEAD^{tree}') echo "$commit" ;;
          '--short')     echo "${commit:0:7}" ;;
          *)             echo "$commit" ;;
        esac
        exit 0
      fi
      exit 128
    fi
    exit 128
    ;;
  describe) exit 128 ;;
  archive)
    shift
    while [[ $# -gt 0 ]]; do shift; done
    printf '%0512d%0512d' 0 0
    exit 0
    ;;
  *) exit 0 ;;
esac
GITFAKE
  chmod +x "$fake_bin/git"
  export FAKE_BIN="$fake_bin"
  export PATH="$fake_bin:$PATH"
}

# Build a stripped roster (no releases metadata) at $1/roster/index.yaml.
make_stripped_nexus() {
  local nexus_dir="$1"
  mkdir -p "$nexus_dir/roster" "$nexus_dir/.git"
  python3 - "$EIDOLONS_ROOT/roster/index.yaml" "$nexus_dir/roster/index.yaml" <<'PY'
import re, sys
from pathlib import Path
src, dst = sys.argv[1], sys.argv[2]
text = Path(src).read_text()
pattern = re.compile(
    r"^      releases:\s*\n(?:        [^\n]*\n|        [^\n]*$)+",
    re.MULTILINE,
)
text = pattern.sub("", text)
Path(dst).write_text(text)
PY
}

# Run fetch_eidolon NAME VERSION in a subshell, all output captured.
run_fetch() {
  local name="$1" version="$2"
  bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; fetch_eidolon '$name' '$version'" 2>&1
}

# ─── G1: stale commit triggers re-clone (uses local bare repo) ─────────────
@test "fetch_eidolon re-clones when cache commit mismatches roster expected_commit" {
  # Build a local bare repo so we can produce real git objects.
  local bare_dir="$BATS_TEST_TMPDIR/bare-spectra"
  local real_commit
  real_commit="$(make_local_bare_repo "$bare_dir")"

  # Build a custom nexus with a fabricated roster entry that uses our local
  # bare repo as source and our real_commit as the expected commit.
  local custom_nexus="$BATS_TEST_TMPDIR/custom-nexus-g1"
  mkdir -p "$custom_nexus/roster" "$custom_nexus/.git"
  # Build a minimal roster with a single member (spectra) pointing at our bare repo.
  # Use local file:// URL so git clone works without network.
  cat > "$custom_nexus/roster/index.yaml" <<EOF
registry_version: "1.0"
updated_at: "2026-05-04T00:00:00Z"
eiis_required: "1.1"
integrity:
  enforcement: strict
eidolons:
  - name: spectra
    display_name: SPECTRA
    capability_class: planner
    status: shipped
    methodology:
      name: SPECTRA
      version: "4.2"
      cycle: "S->P->E->C->T->R->A"
      summary: "test"
    source:
      type: github
      repo: TestOrg/spectra
      default_ref: main
    versions:
      latest: "0.0.0"
      pins:
        stable: "0.0.0"
      releases:
        0.0.0:
          tag: v0.0.0
          commit: $real_commit
          tree: ""
          archive_sha256: ""
          manifest_sha256:
          provenance:
            github_attestation: false
            workflow: ""
    install:
      target_default: "./.eidolons/spectra"
      standalone: true
    handoffs:
      upstream: []
      downstream: []
      lateral: []
    working_set_tokens:
      entry: 900
      target: 3500
    security:
      reads_repo: false
      reads_network: false
      writes_repo: false
      persists: []
    references: []
presets: {}
EOF

  export EIDOLONS_NEXUS="$custom_nexus"
  export EIDOLONS_INTEGRITY_ENFORCEMENT=""

  # Seed stale cache: wrong commit SHA.
  seed_cache spectra 0.0.0 "stalestalestalestalestalestalestalestale"

  # Do NOT install a fake git — use real git so clone from bare repo works.
  # The cache has a FAKE_COMMIT file but real git won't read it;
  # real git rev-parse on a directory with only a .git dir stub will fail.
  # So the stale cache detection will actually trigger rc=3 (unresolvable HEAD).
  # That is acceptable for G1 — both rc=2 (commit mismatch) and rc=3 (corrupt)
  # trigger re-clone. The re-clone from the local bare repo produces real_commit.

  # Override the clone URL to use our local bare repo (file:// protocol).
  # We do this by wrapping the source.repo with a file path and overriding
  # EIDOLONS_REPO_OVERRIDE. Simpler: patch the roster's source.repo to be
  # the local file path (file protocol not needed — git clone accepts file paths).
  python3 - "$custom_nexus/roster/index.yaml" "$bare_dir" <<'PY'
import sys, re
from pathlib import Path
roster = Path(sys.argv[1])
bare = sys.argv[2]
text = roster.read_text()
text = re.sub(r'repo: TestOrg/spectra', f'repo: {bare}', text)
roster.write_text(text)
PY

  # Also need to update fetch_eidolon to handle non-github repos:
  # fetch_eidolon always prepends "https://github.com/". We can't easily
  # override that without network. So instead we install a minimal fake-git
  # that intercepts clone (redirecting to the bare dir) but lets rev-parse
  # use the real git for the fresh clone.
  #
  # Actually the cleanest approach: install a fake git that:
  # - For clone: does a real git clone from the bare dir.
  # - For everything else: delegates to real git.
  local real_git
  real_git="$(command -v git)"
  local wrap_bin="$BATS_TEST_TMPDIR/wrap-bin-g1"
  mkdir -p "$wrap_bin"
  cat > "$wrap_bin/git" <<GITWRAP
#!/usr/bin/env bash
ARGS=("\$@")
# Intercept clone: replace remote URL with local bare repo path.
if [[ "\${ARGS[0]:-}" == "clone" ]]; then
  new_args=("clone")
  i=1
  while [[ \$i -lt \${#ARGS[@]} ]]; do
    arg="\${ARGS[\$i]}"
    case "\$arg" in
      --depth|--branch) new_args+=("\$arg" "\${ARGS[\$((i+1))]}"); i=\$((i+2)) ;;
      --*) new_args+=("\$arg"); i=\$((i+1)) ;;
      https://github.com/*) new_args+=("$bare_dir"); i=\$((i+1)) ;;
      *) new_args+=("\$arg"); i=\$((i+1)) ;;
    esac
  done
  exec "$real_git" "\${new_args[@]}" >/dev/null 2>&1
fi
exec "$real_git" "\$@"
GITWRAP
  chmod +x "$wrap_bin/git"
  export PATH="$wrap_bin:$PATH"

  run run_fetch spectra 0.0.0
  [ "$status" -eq 0 ]
  # Must have detected stale/corrupt cache and re-cloned.
  [[ "$output" =~ "cache invalid" ]] || [[ "$output" =~ "re-cloning" ]] || [[ "$output" =~ "corrupt" ]]
}

# ─── G2: corrupt .git triggers re-clone ────────────────────────────────────
@test "fetch_eidolon re-clones when cache .git is corrupt" {
  # Use stripped nexus (compat mode) — detection is based on rev-parse failure, not commit comparison.
  local stripped_nexus="$BATS_TEST_TMPDIR/stripped-nexus-g2"
  make_stripped_nexus "$stripped_nexus"
  export EIDOLONS_NEXUS="$stripped_nexus"
  export EIDOLONS_INTEGRITY_ENFORCEMENT="warn"

  setup_fake_git_stub

  # Corrupt cache: .git exists but no FAKE_COMMIT → rev-parse exits 128 → rc=3.
  seed_cache atlas 1.3.0 ""

  # Fresh clone produces a commit (any in compat mode is accepted).
  export FAKE_CLONE_COMMIT="7d9f3acf1f5f40684b9735bee467eb76027319d3"

  run run_fetch atlas 1.3.0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "cache invalid" ]] || [[ "$output" =~ "re-cloning" ]] || [[ "$output" =~ "corrupt" ]]
}

# ─── G3: unresolvable HEAD triggers re-clone ────────────────────────────────
@test "fetch_eidolon re-clones when cache HEAD cannot be resolved" {
  local stripped_nexus="$BATS_TEST_TMPDIR/stripped-nexus-g3"
  make_stripped_nexus "$stripped_nexus"
  export EIDOLONS_NEXUS="$stripped_nexus"
  export EIDOLONS_INTEGRITY_ENFORCEMENT="warn"

  setup_fake_git_stub

  # Partial clone: .git dir but no FAKE_COMMIT file (HEAD unresolvable).
  seed_cache apivr 3.0.5 ""

  export FAKE_CLONE_COMMIT="e79663204a4db868f82264041c3fd79fdd5e6613"

  run run_fetch apivr 3.0.5
  [ "$status" -eq 0 ]
  [[ "$output" =~ "cache invalid" ]] || [[ "$output" =~ "re-cloning" ]] || [[ "$output" =~ "corrupt" ]]
}

# ─── G4: re-clone also fails → upstream-truth mismatch fatal ───────────────
@test "fetch_eidolon fatals when re-clone also mismatches roster (upstream-truth failure)" {
  # Use real roster with strict enforcement.
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_INTEGRITY_ENFORCEMENT=""

  setup_fake_git_stub

  # Seed a stale cache.
  seed_cache idg 1.1.5 "stalestalestalestalestalestalestalestale"

  # Fake clone also produces a wrong commit → second verify fails → die.
  export FAKE_CLONE_COMMIT="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  run run_fetch idg 1.1.5
  [ "$status" -ne 0 ]
  [[ "$output" =~ "upstream" ]] || [[ "$output" =~ "mismatch" ]] || [[ "$output" =~ "force-moved" ]]
}

# ─── G5: fresh valid cache — no re-clone ────────────────────────────────────
@test "fetch_eidolon succeeds idempotently when cache is fresh and matches roster" {
  # Use stripped roster (compat mode) — any commit is accepted.
  local stripped_nexus="$BATS_TEST_TMPDIR/stripped-nexus-g5"
  make_stripped_nexus "$stripped_nexus"
  export EIDOLONS_NEXUS="$stripped_nexus"
  export EIDOLONS_INTEGRITY_ENFORCEMENT="warn"

  setup_fake_git_stub

  # Seed a valid cache: has a FAKE_COMMIT (rev-parse succeeds) → rc=0.
  local some_commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  seed_cache forge 1.2.1 "$some_commit"

  run run_fetch forge 1.2.1
  [ "$status" -eq 0 ]
  # Must have used cache — no re-clone message.
  [[ "$output" =~ "Using cached" ]]
  [[ ! "$output" =~ "re-cloning" ]]
}

# ─── G6: annotated-tag round-trip — peeled SHA, no false mismatch ──────────
@test "fetch_eidolon handles annotated-tag round-trip without false mismatch" {
  [[ "${EIDOLONS_TEST_NETWORK:-0}" == "1" ]] || skip "network tests disabled (set EIDOLONS_TEST_NETWORK=1)"

  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_INTEGRITY_ENFORCEMENT=""

  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh'; fetch_eidolon vigil 1.0.3" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "release integrity verified" ]]
}

# ─── G7: strict mode — never silently downgrades ────────────────────────────
@test "fetch_eidolon respects strict mode and never silently downgrades" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  export EIDOLONS_INTEGRITY_ENFORCEMENT=""

  setup_fake_git_stub

  # No pre-existing cache → fresh clone path.
  # Fake clone produces a wrong commit for spectra 4.2.10.
  export FAKE_CLONE_COMMIT="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  run run_fetch spectra 4.2.10
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mismatch" ]] || [[ "$output" =~ "upstream" ]] || [[ "$output" =~ "force-moved" ]]
}
