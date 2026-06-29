#!/usr/bin/env bats
#
# junction_marker.bats — covers remove_junction_marker (lib.sh).
#
# Regression guard for the harness/Junction directory collision: the host-hook
# shims written by 'eidolons harness install' live under .eidolons/harness/hooks/,
# the same parent dir as the Junction marker (.eidolons/harness/manifest.json) and
# the memory preflight cache (.eidolons/harness/cache/). Junction teardown
# ('eidolons mcp uninstall junction', 'eidolons sync' with Junction absent, legacy
# 'eidolons harness uninstall') previously did `rm -rf .eidolons/harness`, which
# deleted the shims too — orphaning the .claude/settings.json hook entries so every
# prompt failed with ".../claude-code-UserPromptSubmit.sh: not found".
# remove_junction_marker removes ONLY the marker and reclaims the dir if empty.
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

# Run remove_junction_marker against a freshly-built layout under the test tmpdir.
# Usage: _run_rjm <layout-setup-commands...> ; assertions follow.
_seed_harness_dir() {
  mkdir -p .eidolons/harness/hooks .eidolons/harness/cache
  printf '#!/usr/bin/env bash\nexit 0\n' > .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  printf '#!/usr/bin/env bash\nexit 0\n' > .eidolons/harness/hooks/claude-code-SessionStart.sh
  chmod +x .eidolons/harness/hooks/*.sh
  echo '{"preflight":true}' > .eidolons/harness/cache/preflight.json
  echo '{"name":"junction","version":"0.3.0"}' > .eidolons/harness/manifest.json
}

# ─── RJM-1: marker removed, hook shims + cache preserved ──────────────────
@test "RJM-1: remove_junction_marker preserves hook shims and memory cache" {
  cd "$BATS_TEST_TMPDIR"
  _seed_harness_dir

  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && remove_junction_marker './.eidolons/harness'"
  [ "$status" -eq 0 ]

  [ -x ".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
  [ -x ".eidolons/harness/hooks/claude-code-SessionStart.sh" ]
  [ -f ".eidolons/harness/cache/preflight.json" ]
  [ ! -f ".eidolons/harness/manifest.json" ]
}

# ─── RJM-2: junction-only dir is fully reclaimed when left empty ───────────
@test "RJM-2: remove_junction_marker reclaims an otherwise-empty harness dir" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .eidolons/harness
  echo '{"name":"junction"}' > .eidolons/harness/manifest.json

  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && remove_junction_marker './.eidolons/harness'"
  [ "$status" -eq 0 ]
  [ ! -d ".eidolons/harness" ]
}

# ─── RJM-3: idempotent — calling on an absent dir is a clean no-op ─────────
@test "RJM-3: remove_junction_marker is a no-op when the dir is absent" {
  cd "$BATS_TEST_TMPDIR"
  # No .eidolons/harness at all.
  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && remove_junction_marker './.eidolons/harness'"
  [ "$status" -eq 0 ]
  [ ! -d ".eidolons/harness" ]
}

# ─── RJM-4: hooks-only dir (no marker) is left intact ─────────────────────
@test "RJM-4: remove_junction_marker leaves a hooks-only dir untouched" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .eidolons/harness/hooks
  printf '#!/usr/bin/env bash\nexit 0\n' > .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
  chmod +x .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh

  run bash -c ". '$EIDOLONS_ROOT/cli/src/lib.sh' && remove_junction_marker './.eidolons/harness'"
  [ "$status" -eq 0 ]
  [ -x ".eidolons/harness/hooks/claude-code-UserPromptSubmit.sh" ]
}
