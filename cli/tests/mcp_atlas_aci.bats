#!/usr/bin/env bats
#
# mcp_atlas_aci.bats — generator-level tests for cli/src/mcp_atlas_aci.sh.
#
# These tests exercise the generator script directly (not via the CLI dispatcher)
# so no running Docker daemon is needed. All five cases from §5 T4 of the
# atlas-aci-sqlite-cross-project-fix spec are covered.
#
# Conventions:
#   - load 'helpers'        → helpers.bash sets EIDOLONS_ROOT, EIDOLONS_NEXUS,
#                             EIDOLONS_HOME, TEST_PROJECT, and cd's into it.
#   - BATS_TEST_TMPDIR      → bats-scoped temp directory; unique per test.
#   - run_generator [args]  → invoke mcp_atlas_aci.sh directly.
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no readarray.
# See CLAUDE.md §"Bash 3.2 compatibility".

load helpers

# ─── Helper: invoke the generator script directly ─────────────────────────
# We invoke cli/src/mcp_atlas_aci.sh directly (bypassing cli/eidolons) so
# the test does not rely on the dispatcher wiring from T3. EIDOLONS_NEXUS is
# already exported by helpers.bash's setup(), which makes lib.sh resolve the
# roster from the checkout. The template path inside the script is resolved
# relative to SELF_DIR (the script's own directory), so it always finds
# cli/templates/mcp/atlas-aci.mcp.json.tmpl regardless of cwd.
run_generator() {
  run bash "$EIDOLONS_ROOT/cli/src/mcp_atlas_aci.sh" "$@"
}

# ─── Portable md5 ─────────────────────────────────────────────────────────
# macOS ships `md5` (BSD); Linux ships `md5sum`. Both emit the hex digest
# as the first token on stdout.
file_md5() {
  local path="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$path" | awk '{print $1}'
  else
    md5 -q "$path"
  fi
}

# ─── Test 1: fresh project ─────────────────────────────────────────────────
@test "mcp atlas-aci: fresh project creates .mcp.json and .atlas/memex/.gitkeep" {
  local project="$BATS_TEST_TMPDIR/fresh-project"
  mkdir -p "$project"

  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # .mcp.json must exist and parse as valid JSON.
  [ -f "$project/.mcp.json" ]
  run bash -c "jq empty '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # .atlas/memex/.gitkeep must exist.
  [ -f "$project/.atlas/memex/.gitkeep" ]

  # The --name entry in the args array must equal "atlas-aci-<slug>".
  # Slug of "fresh-project" is "fresh-project".
  local name_val
  name_val="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--name"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"

  [ "$name_val" = "atlas-aci-fresh-project" ]
}

# ─── Test 2: idempotent rerun without --force ──────────────────────────────
@test "mcp atlas-aci: rerun without --force exits non-zero and stderr mentions --force" {
  local project="$BATS_TEST_TMPDIR/idempotent-project"
  mkdir -p "$project"

  # First run: must succeed.
  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # Capture md5 of the generated .mcp.json.
  local hash_before
  hash_before="$(file_md5 "$project/.mcp.json")"

  # Second run without --force: must exit non-zero.
  run_generator --project-root "$project"
  [ "$status" -ne 0 ]

  # stderr (merged into $output by bats) must mention --force.
  [[ "$output" =~ "--force" ]]

  # The file on disk must be bit-for-bit identical (md5 unchanged).
  local hash_after
  hash_after="$(file_md5 "$project/.mcp.json")"
  [ "$hash_before" = "$hash_after" ]
}

# ─── Test 3: --force regenerates .mcp.json but preserves codegraph.db ──────
@test "mcp atlas-aci: --force regenerates .mcp.json; pre-existing codegraph.db is preserved" {
  local project="$BATS_TEST_TMPDIR/force-project"
  mkdir -p "$project"

  # First run.
  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # Simulate a pre-existing codegraph DB (non-empty, so its md5 is meaningful).
  local db_path="$project/.atlas/memex/codegraph.db"
  printf "SQLITE" > "$db_path"
  local db_hash_before
  db_hash_before="$(file_md5 "$db_path")"

  # Capture md5 of the original .mcp.json.
  local mcp_hash_before
  mcp_hash_before="$(file_md5 "$project/.mcp.json")"

  # Use a different image digest on the --force run so the regenerated
  # .mcp.json is guaranteed to differ from the first run's output.
  local alt_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  run_generator --project-root "$project" --force --image-digest "$alt_digest"
  [ "$status" -eq 0 ]

  # .mcp.json must have changed (different digest means different content).
  local mcp_hash_after
  mcp_hash_after="$(file_md5 "$project/.mcp.json")"
  [ "$mcp_hash_before" != "$mcp_hash_after" ]

  # The new .mcp.json must contain the alt digest.
  grep -q "$alt_digest" "$project/.mcp.json"

  # codegraph.db must be intact and unchanged.
  [ -f "$db_path" ]
  local db_hash_after
  db_hash_after="$(file_md5 "$db_path")"
  [ "$db_hash_before" = "$db_hash_after" ]
}

# ─── Test 4: two distinct project roots → distinct --name and bind paths ───
@test "mcp atlas-aci: two distinct roots produce distinct --name values and bind-mount paths" {
  local project_a="$BATS_TEST_TMPDIR/project-alpha"
  local project_b="$BATS_TEST_TMPDIR/project-beta"
  mkdir -p "$project_a" "$project_b"

  run_generator --project-root "$project_a"
  [ "$status" -eq 0 ]
  run_generator --project-root "$project_b"
  [ "$status" -eq 0 ]

  # Extract --name values from each generated .mcp.json.
  local name_a name_b
  name_a="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--name"))[0] as $i |
    $a[$i + 1]
  ' "$project_a/.mcp.json")"
  name_b="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--name"))[0] as $i |
    $a[$i + 1]
  ' "$project_b/.mcp.json")"

  # Names must differ.
  [ "$name_a" != "$name_b" ]

  # Each --name must reference its own slug.
  [ "$name_a" = "atlas-aci-project-alpha" ]
  [ "$name_b" = "atlas-aci-project-beta" ]

  # The bind-mount source for /memex must be distinct in each file.
  # Extract the string that precedes ":/memex" from the args array.
  local mount_a mount_b
  mount_a="$(jq -r '
    .mcpServers."atlas-aci".args[] | select(endswith(":/memex"))
  ' "$project_a/.mcp.json")"
  mount_b="$(jq -r '
    .mcpServers."atlas-aci".args[] | select(endswith(":/memex"))
  ' "$project_b/.mcp.json")"

  [ "$mount_a" != "$mount_b" ]

  # Each mount must reference its own project root.
  [[ "$mount_a" == "$project_a"* ]]
  [[ "$mount_b" == "$project_b"* ]]
}

# ─── Test 5: slug edge cases (spaces, uppercase, underscores) ──────────────
@test "mcp atlas-aci: project root with spaces, uppercase, underscores produces valid slug" {
  # Create a directory whose name exercises all three normalisation rules:
  # uppercase → lowercase, underscore → dash, spaces → dash.
  local parent="$BATS_TEST_TMPDIR"
  # Bats runs inside a temp dir; we can create a subdir with a complex name.
  local project="$parent/My_Project Dir"
  mkdir -p "$project"

  run_generator --project-root "$project"
  [ "$status" -eq 0 ]

  # .mcp.json must be valid JSON.
  [ -f "$project/.mcp.json" ]
  run bash -c "jq empty '$project/.mcp.json'"
  [ "$status" -eq 0 ]

  # Extract the slug from the --name arg.
  local name_val
  name_val="$(jq -r '
    .mcpServers."atlas-aci".args as $a |
    ($a | indices("--name"))[0] as $i |
    $a[$i + 1]
  ' "$project/.mcp.json")"

  # Expected: "atlas-aci-my-project-dir"
  [ "$name_val" = "atlas-aci-my-project-dir" ]

  # The slug portion (strip leading "atlas-aci-") must match
  # the pattern: only lowercase letters, digits, and dashes.
  local slug="${name_val#atlas-aci-}"
  run bash -c "printf '%s' '$slug' | grep -Eq '^[a-z0-9-]+$'"
  [ "$status" -eq 0 ]

  # Must not start or end with a dash.
  run bash -c "printf '%s' '$slug' | grep -Eq '^-|--$'"
  [ "$status" -ne 0 ]
}
