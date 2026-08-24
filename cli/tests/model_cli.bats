#!/usr/bin/env bats
#
# cli/tests/model_cli.bats — coverage for 'eidolons model' CLI surface.
# Mirrors mcp_use.bats test structure.
#
# Stories:
#   HELP         --help exits 0 with usage text.
#   LIST         model list shows profiles + marks active.
#   SHOW         model show table + --json; unknown eidolon → 2.
#   USE-TIER     model use spectra@standard sets members.spectra.tier.
#   USE-PIN      model use apivr@sonnet sets pin; source=pin.
#   PROFILE      model profile openai updates profile; unknown → 2.
#   RESET-ONE    model reset spectra clears members.spectra.
#   RESET-ALL    model reset (no arg) clears all overrides.
#   NON-INTER    --non-interactive bare prints usage, exits 0, no prompt.
#   DRY-RUN      --dry-run does not mutate eidolons.yaml.
#
# Bash 3.2 compatible; no associative arrays, no ${var,,}, no readarray.

load helpers

# ─── Setup: minimal eidolons.yaml + model-profiles available ─────────────────

setup_model_project() {
  seed_manifest
  # Start with no models block.
  mkdir -p .claude/agents
  local id
  for id in atlas spectra apivr; do
    cat > ".claude/agents/${id}.md" <<EOF
---
name: $id
description: Test agent
---

Test agent.
EOF
  done
}

# ─── HELP ─────────────────────────────────────────────────────────────────────

@test "model: --help exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model --help
  [ "$status" -eq 0 ]
}

@test "model: help subcommand exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model help
  [ "$status" -eq 0 ]
}

@test "model: --help includes 'list' and 'show' and 'use'" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "list" ]]
  [[ "$output" =~ "show" ]]
  [[ "$output" =~ "use" ]]
}

# ─── LIST ─────────────────────────────────────────────────────────────────────

@test "model list: exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model list
  [ "$status" -eq 0 ]
}

@test "model list: shows anthropic profile" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "anthropic" ]]
}

@test "model list: shows openai profile" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "openai" ]]
}

@test "model list: --json exits 0 with JSON" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model list --json
  [ "$status" -eq 0 ]
  # Must be valid JSON.
  printf '%s' "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

@test "model list: --json includes active_profile" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model list --json
  [ "$status" -eq 0 ]
  local ap
  ap="$(printf '%s' "$output" | jq -r '.active_profile')"
  [ -n "$ap" ] && [ "$ap" != "null" ]
}

# ─── SHOW ─────────────────────────────────────────────────────────────────────

@test "model show: exits 0 with table" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model show
  [ "$status" -eq 0 ]
}

@test "model show: table includes 'spectra'" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model show
  [ "$status" -eq 0 ]
  [[ "$output" =~ "spectra" ]]
}

@test "model show: --json exits 0 and is valid JSON array" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model show --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq '. | type == "array"' | grep -q true
}

@test "model show spectra: exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model show spectra
  [ "$status" -eq 0 ]
}

@test "model show spectra: shows deep tier" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model show spectra
  [ "$status" -eq 0 ]
  [[ "$output" =~ "deep" ]]
}

@test "model show: unknown eidolon exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model show no-such-eidolon-xyz
  [ "$status" -eq 2 ]
}

# ─── USE-TIER ─────────────────────────────────────────────────────────────────

@test "model use: missing @ exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model use spectra
  [ "$status" -eq 2 ]
}

@test "model use: unknown eidolon exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model use no-such@deep
  [ "$status" -eq 2 ]
}

@test "model use spectra@standard: exits 0 and sets tier" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model use spectra@standard
  [ "$status" -eq 0 ]
  # eidolons.yaml should now contain members.spectra.tier = standard.
  local tier
  if command -v yq >/dev/null 2>&1; then
    tier="$(yq eval '.models.members.spectra.tier' eidolons.yaml 2>/dev/null || true)"
  else
    tier="$(python3 -c "import yaml; d=yaml.safe_load(open('eidolons.yaml').read()); print(d.get('models',{}).get('members',{}).get('spectra',{}).get('tier',''))" 2>/dev/null || true)"
  fi
  [ "$tier" = "standard" ]
}

@test "model use spectra@deep: model show reflects deep tier" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model use spectra@deep
  [ "$status" -eq 0 ]
  run eidolons model show spectra
  [ "$status" -eq 0 ]
  [[ "$output" =~ "deep" ]]
}

# ─── USE-PIN ──────────────────────────────────────────────────────────────────

@test "model use apivr@sonnet: sets pin in eidolons.yaml" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model use apivr@sonnet
  [ "$status" -eq 0 ]
  local pin
  if command -v yq >/dev/null 2>&1; then
    pin="$(yq eval '.models.members.apivr.model' eidolons.yaml 2>/dev/null || true)"
  else
    pin="$(python3 -c "import yaml; d=yaml.safe_load(open('eidolons.yaml').read()); print(d.get('models',{}).get('members',{}).get('apivr',{}).get('model',''))" 2>/dev/null || true)"
  fi
  [ "$pin" = "sonnet" ]
}

@test "model use apivr@custom-model: show reports source=pin" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model use apivr@my-custom-model
  [ "$status" -eq 0 ]
  run eidolons model show apivr --json
  [ "$status" -eq 0 ]
  local src
  src="$(printf '%s' "$output" | jq -r '.source')"
  [ "$src" = "pin" ]
}

# ─── PROFILE ──────────────────────────────────────────────────────────────────

@test "model profile openai: exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model profile openai
  [ "$status" -eq 0 ]
}

@test "model profile openai: sets profile in eidolons.yaml" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model profile openai
  [ "$status" -eq 0 ]
  local prof
  if command -v yq >/dev/null 2>&1; then
    prof="$(yq eval '.models.profile' eidolons.yaml 2>/dev/null || true)"
  else
    prof="$(python3 -c "import yaml; d=yaml.safe_load(open('eidolons.yaml').read()); print(d.get('models',{}).get('profile',''))" 2>/dev/null || true)"
  fi
  [ "$prof" = "openai" ]
}

@test "model profile openai: refreshes effective model provenance for every lock member" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  seed_lock
  run eidolons model profile openai
  [ "$status" -eq 0 ]
  [ "$(yq eval '.members[] | select(.name == "atlas") | .model.effective_model' eidolons.lock)" = "gpt-5.6-terra" ]
  [ "$(yq eval '.members[] | select(.name == "atlas") | .model.tier' eidolons.lock)" = "standard" ]
  [ "$(yq eval '.members[] | select(.name == "atlas") | .model.profile' eidolons.lock)" = "openai" ]
}

@test "model profile: unknown profile exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model profile no-such-profile-xyz
  [ "$status" -eq 2 ]
}

# ─── RESET ────────────────────────────────────────────────────────────────────

@test "model reset spectra: exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  # Set then reset.
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  run eidolons model reset spectra
  [ "$status" -eq 0 ]
}

@test "model reset spectra: clears per-member tier" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  run eidolons model reset spectra
  [ "$status" -eq 0 ]
  local tier
  if command -v yq >/dev/null 2>&1; then
    tier="$(yq eval '.models.members.spectra.tier // ""' eidolons.yaml 2>/dev/null || true)"
  else
    tier=""
  fi
  [ -z "$tier" ] || [ "$tier" = "null" ]
}

@test "model reset: unknown eidolon exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model reset no-such-eidolon-xyz
  [ "$status" -eq 2 ]
}

@test "model reset (all): exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  run eidolons model reset
  [ "$status" -eq 0 ]
}

@test "model reset one: refreshes the member's lock provenance" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  seed_lock
  eidolons model use atlas@light >/dev/null 2>&1
  [ "$(yq eval '.members[] | select(.name == "atlas") | .model.effective_model' eidolons.lock)" = "haiku" ]
  run eidolons model reset atlas
  [ "$status" -eq 0 ]
  [ "$(yq eval '.members[] | select(.name == "atlas") | .model.effective_model' eidolons.lock)" = "sonnet" ]
  [ "$(yq eval '.members[] | select(.name == "atlas") | .model.tier' eidolons.lock)" = "standard" ]
}

@test "model use: missing canonical Codex TOML descriptor exits 4" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  cat > eidolons.yaml <<'EOF'
version: 1
hosts:
  wire: [codex]
models:
  profile: openai
members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
EOF
  mkdir -p .codex/agents
  printf '%s\n' '---' 'model: legacy-only' '---' > .codex/agents/atlas.md
  run eidolons model use atlas@standard
  [ "$status" -eq 4 ]
  [[ "$output" =~ "required descriptor .codex/agents/atlas.toml not found" ]]
  [[ ! "$output" =~ "Re-applied model wiring" ]]
}

@test "model use: lock write failure exits 4 without success claim" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  seed_lock
  local real_yq fake_bin
  real_yq="$(command -v yq || true)"
  [ -n "$real_yq" ] || skip "yq required for deterministic failure shim"
  fake_bin="$BATS_TEST_TMPDIR/failing-yq"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/yq" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    *eidolons.lock) exit 1 ;;
  esac
done
exec "$REAL_YQ" "$@"
SH
  chmod +x "$fake_bin/yq"
  export REAL_YQ="$real_yq"
  export PATH="$fake_bin:$PATH"
  run eidolons model use atlas@deep
  [ "$status" -eq 4 ]
  [[ "$output" =~ "Lock model provenance update failed" ]]
  [[ ! "$output" =~ "Re-applied model wiring" ]]
}

# ─── NON-INTERACTIVE ──────────────────────────────────────────────────────────

@test "model --non-interactive (bare): prints usage, exits 0, no prompt" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  # Ensure we're in a non-TTY context (bats always is).
  run eidolons model --non-interactive
  [ "$status" -eq 0 ]
  # Should contain usage / help text.
  [[ "$output" =~ "model" ]]
}

@test "model (bare, no TTY): prints usage, exits 0" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  # Bats runs in non-TTY — bare invocation should be non-interactive.
  run eidolons model
  [ "$status" -eq 0 ]
}

# ─── DRY-RUN ──────────────────────────────────────────────────────────────────

@test "model use --dry-run: no mutation to eidolons.yaml" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  local before
  before="$(cat eidolons.yaml)"
  run eidolons model use spectra@standard --dry-run
  [ "$status" -eq 0 ]
  local after
  after="$(cat eidolons.yaml)"
  [ "$before" = "$after" ]
}

@test "model reset --dry-run: no mutation" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  setup_model_project
  eidolons model use spectra@standard >/dev/null 2>&1 || true
  local before
  before="$(cat eidolons.yaml)"
  run eidolons model reset spectra --dry-run
  [ "$status" -eq 0 ]
  local after
  after="$(cat eidolons.yaml)"
  [ "$before" = "$after" ]
}

# ─── UNKNOWN SUBCOMMAND ───────────────────────────────────────────────────────

@test "model: unknown subcommand exits 2" {
  export EIDOLONS_NEXUS="$EIDOLONS_ROOT"
  run eidolons model no-such-sub
  [ "$status" -eq 2 ]
}
