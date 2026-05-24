#!/usr/bin/env bash
# eidolons doctor — health-check installed Eidolons and host wiring
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"

usage() {
  cat <<EOF
eidolons doctor — health-check installed Eidolons and host wiring

Usage: eidolons doctor [OPTIONS]

Options:
  --fix         Attempt to auto-repair simple issues (missing symlinks, lockfile drift)
  -h, --help    Show this help

Checks:
  - eidolons.yaml present and valid
  - eidolons.lock present and consistent with manifest
  - Each installed Eidolon has its files in .eidolons/<n>/
  - Each installed Eidolon's install.manifest.json is valid
  - Host dispatch files exist for every host listed in eidolons.yaml
  - Release-integrity status per lock entry (verified / legacy / missing)
EOF
}

FIX=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)    FIX=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)        echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

ERRORS=0
err() { ERRORS=$((ERRORS + 1)); printf "  %s✗%s %s\n" "$RED" "$RESET" "$*"; }
pass() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$*"; }

say "eidolons doctor — checking $(pwd)"
echo ""

# ─── Check 1: manifest + lock ────────────────────────────────────────────
ui_section_out "Manifest + lock"
if [[ -f "$PROJECT_MANIFEST" ]]; then
  pass "eidolons.yaml present"
else
  err "eidolons.yaml missing — run 'eidolons init'"
  exit 1
fi

if [[ -f "$PROJECT_LOCK" ]]; then
  pass "eidolons.lock present"
else
  err "eidolons.lock missing — run 'eidolons sync'"
fi

# ─── Check 2: per-member installs ───────────────────────────────────────
ui_section_out "Installed members"
CLAUDE_WIRED=false
if yaml_to_json "$PROJECT_MANIFEST" | jq -e '.hosts.wire | index("claude-code")' >/dev/null 2>&1; then
  CLAUDE_WIRED=true
fi
manifest_members | while read -r name; do
  target="./.eidolons/$name"
  if [[ ! -d "$target" ]]; then
    err "$name declared but not installed at $target (per-Eidolon install.sh didn't run or failed)"
    continue
  fi
  if [[ ! -f "$target/install.manifest.json" ]]; then
    err "$name installed at $target but install.manifest.json is missing (not EIIS-conformant — report upstream)"
  elif ! jq -e . "$target/install.manifest.json" >/dev/null 2>&1; then
    err "$name has corrupt install.manifest.json at $target/install.manifest.json"
  else
    pass "$name installed with valid manifest"
  fi
  if [[ "$CLAUDE_WIRED" == "true" ]] && [[ ! -f ".claude/agents/$name.md" ]]; then
    err "$name installed but .claude/agents/$name.md missing (per-Eidolon installer didn't wire claude-code)"
  fi
done

# Read shared_dispatch preference — defaults to false when the key is absent.
SHARED_DISPATCH="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.shared_dispatch // false')"

# ─── Check 3: host wiring ───────────────────────────────────────────────
ui_section_out "Host wiring"
hosts="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.wire[]')"
for host in $hosts; do
  case "$host" in
    claude-code)
      # Per-vendor self-sufficient files live under .claude/agents/ and .claude/skills/.
      # Root CLAUDE.md is only required when shared_dispatch is opted in.
      if [[ -d ".claude/agents" ]] && ls .claude/agents/*.md >/dev/null 2>&1; then
        pass "claude-code wired (.claude/agents/*.md present)"
      elif [[ "$SHARED_DISPATCH" == "true" && -f "CLAUDE.md" ]]; then
        pass "claude-code wired (CLAUDE.md shared dispatch)"
      else
        err "claude-code declared but no .claude/agents/*.md found"
      fi
      ;;
    copilot)
      # Per-vendor files: .github/instructions/<eidolon>-<skill>.instructions.md
      if [[ -d ".github/instructions" ]] && ls .github/instructions/*.instructions.md >/dev/null 2>&1; then
        pass "copilot wired (.github/instructions/*.instructions.md present)"
      elif [[ "$SHARED_DISPATCH" == "true" ]] && [[ -f ".github/copilot-instructions.md" || -f "AGENTS.md" ]]; then
        pass "copilot wired (shared dispatch)"
      else
        err "copilot declared but no .github/instructions/ content found"
      fi
      ;;
    cursor)
      if [[ -d ".cursor/rules" ]] && ls .cursor/rules/*.mdc >/dev/null 2>&1; then
        pass "cursor wired (.cursor/rules/*.mdc present)"
      elif [[ -f ".cursorrules" ]]; then
        pass "cursor wired (legacy .cursorrules)"
      else
        err "cursor declared but no .cursor/rules/*.mdc found"
      fi
      ;;
    opencode)
      if [[ -d ".opencode/agents" ]] && ls .opencode/agents/*.md >/dev/null 2>&1; then
        pass "opencode wired (.opencode/agents/*.md present)"
      else
        err "opencode declared but no .opencode/agents/*.md found"
      fi
      ;;
    codex)
      # Per-vendor files live under .codex/agents/<name>.md. AGENTS.md is
      # the shared dispatch surface (always wired when codex is declared,
      # per the T.12 override in sync.sh). Accept either as sufficient.
      if [[ -d ".codex/agents" ]] && ls .codex/agents/*.md >/dev/null 2>&1; then
        pass "codex wired (.codex/agents/*.md present)"
      elif [[ "$SHARED_DISPATCH" == "true" ]] && [[ -f "AGENTS.md" ]]; then
        pass "codex wired (AGENTS.md shared dispatch)"
      else
        err "codex declared but no .codex/agents/*.md or AGENTS.md found"
      fi
      ;;
  esac
done

# ─── Check 4: dispatch freshness ────────────────────────────────────────
# Catches leftover pre-v1.1 wiring that survived reinstalls: legacy
# `agents/<name>/` pointers, symlinked shared files, and legacy IDG name
# references (scribe). Warns, doesn't block — the files may still work,
# but are stale and confusing.
ui_section_out "Dispatch freshness"
FRESHNESS_FILES=("AGENTS.md" "CLAUDE.md" ".github/copilot-instructions.md" ".cursorrules")
for f in "${FRESHNESS_FILES[@]}"; do
  [[ -e "$f" ]] || continue
  if [[ -L "$f" ]]; then
    err "$f is a symlink — shared dispatch files must be real composable files. Re-run 'eidolons sync --force'."
    continue
  fi
  if grep -Eq '@?\.?/?agents/(atlas|apivr|spectra|idg|scribe|forge)/' "$f" 2>/dev/null; then
    err "$f contains legacy agents/<name>/ pointers (pre-v1.1 paths). Delete the Eidolon block(s) and re-run 'eidolons sync --force'."
    continue
  fi
  if grep -q '@?\.?/?agents/scribe\|scribe/agent\.md' "$f" 2>/dev/null; then
    err "$f references legacy 'scribe' identifier (renamed to 'idg' in v1.1.1)."
    continue
  fi
  pass "$f clean (no stale pointers)"
done

# ─── Check 5: release integrity ─────────────────────────────────────────
# Read-only summary derived from eidolons.lock's `verification` field. We do
# not re-fetch the roster or recompute hashes here — that's `eidolons verify`'s
# job. Doctor surfaces what was recorded at sync/upgrade time so a stale lock
# is visible without leaving cwd. A `MISMATCH` outcome is treated as a hard
# error (something has drifted since sync); `verified` and `legacy-warning`
# are informational.
ui_section_out "Release integrity"
if [[ -f "$PROJECT_LOCK" ]]; then
  LOCK_JSON_DOCTOR="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null || echo '{}')"
  member_names="$(echo "$LOCK_JSON_DOCTOR" | jq -r '(.members // [])[].name')"
  if [[ -z "$member_names" ]]; then
    pass "No members locked — integrity check skipped"
  else
    while IFS= read -r mname; do
      [[ -n "$mname" ]] || continue
      mver="$(echo "$LOCK_JSON_DOCTOR" | jq -r --arg n "$mname" \
        '(.members // [])[] | select(.name == $n) | .version // ""')"
      mverif="$(echo "$LOCK_JSON_DOCTOR" | jq -r --arg n "$mname" \
        '(.members // [])[] | select(.name == $n) | .verification // ""')"
      case "$mverif" in
        verified)
          pass "$mname@$mver release integrity verified"
          ;;
        legacy-warning|"")
          # Compatibility mode or pre-integrity lock — informational, not blocking.
          printf "  %s·%s %s@%s no roster release metadata (legacy)\n" \
            "${YELLOW:-}" "${RESET:-}" "$mname" "$mver"
          ;;
        missing)
          err "$mname@$mver MISMATCH — release metadata missing under strict enforcement"
          ;;
        *)
          err "$mname@$mver unknown verification status: $mverif"
          ;;
      esac
    done <<< "$member_names"
  fi
else
  printf "  %s·%s eidolons.lock missing — integrity check deferred\n" \
    "${YELLOW:-}" "${RESET:-}"
fi

# ─── Check 6: Cache hygiene ─────────────────────────────────────────────
# Read-only check: for each member in eidolons.lock, verify the cache entry
# at $CACHE_DIR/$name@$version matches the roster's recorded commit. This
# surfaces stale caches before the next sync without triggering a re-clone
# (re-clone happens automatically on the next 'eidolons sync').
# Does NOT call cache_invalidate here — that is sync's job.
ui_section_out "Cache hygiene"
if [[ -f "$PROJECT_LOCK" ]]; then
  LOCK_JSON_CACHE="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null || echo '{}')"
  cache_member_names="$(echo "$LOCK_JSON_CACHE" | jq -r '(.members // [])[].name')"
  if [[ -z "$cache_member_names" ]]; then
    printf "  %s·%s No members locked — cache check skipped\n" \
      "${YELLOW:-}" "${RESET:-}"
  else
    while IFS= read -r cname; do
      [[ -n "$cname" ]] || continue
      cver="$(echo "$LOCK_JSON_CACHE" | jq -r --arg n "$cname" \
        '(.members // [])[] | select(.name == $n) | .version // ""')"
      cache_entry="$CACHE_DIR/${cname}@${cver}"
      if [[ ! -d "$cache_entry/.git" ]]; then
        printf "  %s·%s %s@%s cache absent (run 'eidolons sync' to fetch)\n" \
          "${YELLOW:-}" "${RESET:-}" "$cname" "$cver"
        continue
      fi
      # Check HEAD resolution first (detects corrupt/partial clones).
      actual_cache_commit="$(git -C "$cache_entry" rev-parse HEAD 2>/dev/null || echo "")"
      if [[ -z "$actual_cache_commit" ]]; then
        printf "  %s·%s %s@%s cache corrupt (HEAD unresolvable) — run 'eidolons sync' to auto-recover\n" \
          "${YELLOW:-}" "${RESET:-}" "$cname" "$cver"
        continue
      fi
      # Compare against roster expected commit.
      expected_cache_commit="$(roster_get "$cname" 2>/dev/null \
        | jq -r --arg v "$cver" '.versions.releases[$v].commit // empty' 2>/dev/null || echo "")"
      if [[ -n "$expected_cache_commit" && "$actual_cache_commit" != "$expected_cache_commit" ]]; then
        printf "  %s·%s %s@%s cache stale (got %s, roster expects %s) — run 'eidolons sync' to auto-recover, or rm -rf '%s' to force\n" \
          "${YELLOW:-}" "${RESET:-}" "$cname" "$cver" \
          "${actual_cache_commit:0:12}" "${expected_cache_commit:0:12}" "$cache_entry"
      else
        pass "$cname@$cver cache fresh"
      fi
    done <<< "$cache_member_names"
  fi
else
  printf "  %s·%s eidolons.lock missing — cache check deferred\n" \
    "${YELLOW:-}" "${RESET:-}"
fi

# ─── Check 7: MCP servers ─────────────────────────────────────────────────
# Iterates eidolons.mcp.lock (if present) and calls the per-MCP health driver
# for each installed MCP. When the lockfile is absent, surfaces a hint.
# This block replaces the legacy hard-coded atlas-aci probe.
ui_section_out "MCP servers"
_mcp_lock="$(mcp_lockfile)"
if [[ ! -f "$_mcp_lock" ]]; then
  printf "  %s·%s no MCPs installed — run 'eidolons mcp list' to see the catalogue\n" \
    "${YELLOW:-}" "${RESET:-}"
elif ! command -v jq >/dev/null 2>&1; then
  printf "  %s·%s jq not on PATH — MCP server check skipped\n" \
    "${YELLOW:-}" "${RESET:-}"
else
  _mcp_lock_json="$(mcp_lock_read 2>/dev/null || echo '{}')"
  _mcp_names="$(printf '%s' "$_mcp_lock_json" \
    | jq -r '(.mcps // [])[] | .name' 2>/dev/null || true)"
  if [[ -z "$_mcp_names" ]]; then
    printf "  %s·%s eidolons.mcp.lock has no entries\n" \
      "${YELLOW:-}" "${RESET:-}"
  else
    while IFS= read -r _mcp_n; do
      [[ -n "$_mcp_n" ]] || continue
      _mcp_kind="$(printf '%s' "$_mcp_lock_json" \
        | jq -r --arg n "$_mcp_n" '(.mcps // [])[] | select(.name == $n) | .kind' \
        2>/dev/null || true)"

      # Call the driver health hook and summarise the OVERALL line.
      _health_output=""
      case "$_mcp_kind" in
        oci-image)
          _health_output="$(mcp_driver_oci_image_health "$_mcp_n" 2>/dev/null || true)"
          ;;
        binary)
          _health_output="$(mcp_driver_binary_health "$_mcp_n" 2>/dev/null || true)"
          ;;
        *)
          _health_output="${_mcp_n}  OVERALL  degraded  unsupported kind: ${_mcp_kind}"
          ;;
      esac

      # Extract the OVERALL line and map to pass/err/warn.
      _overall="$(printf '%s' "$_health_output" \
        | grep 'OVERALL' | awk '{print $3}' | head -1 || true)"
      case "$_overall" in
        ok)
          pass "$_mcp_n: healthy"
          ;;
        degraded)
          _reason="$(printf '%s' "$_health_output" \
            | grep 'OVERALL' | cut -d' ' -f4- | head -1 || true)"
          printf "  %s·%s %s: degraded — %s\n" \
            "${YELLOW:-}" "${RESET:-}" "$_mcp_n" "${_reason:-see eidolons mcp health $_mcp_n}"
          ;;
        missing)
          err "$_mcp_n: missing — run 'eidolons mcp install $_mcp_n'"
          ;;
        not-installed)
          printf "  %s·%s %s: not installed — run 'eidolons mcp install %s'\n" \
            "${YELLOW:-}" "${RESET:-}" "$_mcp_n" "$_mcp_n"
          ;;
        *)
          printf "  %s·%s %s: unknown health status (%s)\n" \
            "${YELLOW:-}" "${RESET:-}" "$_mcp_n" "${_overall:-no output}"
          ;;
      esac
    done <<< "$_mcp_names"
  fi
fi

# ─── Check 8: MCP catalogue drift ─────────────────────────────────────────
# Non-fatal: surfaces MCPs in eidolons.mcp.lock that are behind catalogue stable.
# Does not increment ERRORS — informational / advisory only.
ui_section_out "MCP catalogue drift"
if [[ ! -f "$_mcp_lock" ]]; then
  printf "  %s·%s no lockfile — drift check skipped\n" \
    "${YELLOW:-}" "${RESET:-}"
elif ! command -v jq >/dev/null 2>&1; then
  printf "  %s·%s jq not on PATH — drift check skipped\n" \
    "${YELLOW:-}" "${RESET:-}"
else
  _mcp_lock_json2="$(mcp_lock_read 2>/dev/null || echo '{}')"
  _mcp_names2="$(printf '%s' "$_mcp_lock_json2" \
    | jq -r '(.mcps // [])[] | .name' 2>/dev/null || true)"
  _drift_found=false
  if [[ -n "$_mcp_names2" ]]; then
    while IFS= read -r _mcp_n2; do
      [[ -n "$_mcp_n2" ]] || continue
      _inst_ver="$(printf '%s' "$_mcp_lock_json2" \
        | jq -r --arg n "$_mcp_n2" '(.mcps // [])[] | select(.name == $n) | .version' \
        2>/dev/null || true)"
      _stable_ver="$(mcp_catalogue_get_field "$_mcp_n2" '.versions.pins.stable' 2>/dev/null || true)"
      if [[ -n "$_stable_ver" && "$_inst_ver" != "$_stable_ver" ]]; then
        printf "  %s·%s  %-16s %s  →  %s  (run 'eidolons mcp upgrade %s')\n" \
          "${YELLOW:-}" "${RESET:-}" "$_mcp_n2" "$_inst_ver" "$_stable_ver" "$_mcp_n2"
        _drift_found=true
      fi
    done <<< "$_mcp_names2"
  fi
  if [[ "$_drift_found" = "false" ]]; then
    pass "All installed MCPs at catalogue stable"
  fi
fi

# ─── Check 9: Pending upgrades ──────────────────────────────────────────
# Informational only — does NOT increment ERRORS. Degrades gracefully when
# offline or when eidolons.yaml is absent.
# (Bucket C / D-NOTIFY — spec: eidolons-update-flow-2026-05-05.md §4.3)
ui_section_out "Pending upgrades"
if ! manifest_exists; then
  printf "  %s·%s eidolons.yaml missing — pending upgrades skipped\n" "${YELLOW:-}" "${RESET:-}"
else
  _pending_rows=""
  _pending_offline=false
  if ! _pending_rows="$(collect_member_upgrade_rows 2>/dev/null)"; then
    _pending_offline=true
  fi
  if [[ "$_pending_offline" == "true" ]]; then
    printf "  %s·%s unknown (offline — could not reach roster upstream)\n" "${YELLOW:-}" "${RESET:-}"
  elif [[ -z "$_pending_rows" ]]; then
    pass "All members up-to-date"
  else
    _n_avail=0
    _n_pinned=0
    while IFS="$(printf '\t')" read -r _pu_name _pu_inst _pu_lat _pu_con _pu_st; do
      [[ -z "$_pu_name" ]] && continue
      case "$_pu_st" in
        upgrade-available)
          _n_avail=$((_n_avail + 1))
          printf "  %s·%s  %-14s %s  →  %s  (within %s)\n" \
            "${YELLOW:-}" "${RESET:-}" "$_pu_name" "$_pu_inst" "$_pu_lat" "$_pu_con"
          ;;
        pinned-out)
          _n_pinned=$((_n_pinned + 1))
          printf "  %s·%s  %-14s %s  →  %s  (constraint %s — bump to allow)\n" \
            "${YELLOW:-}" "${RESET:-}" "$_pu_name" "$_pu_inst" "$_pu_lat" "$_pu_con"
          ;;
        up-to-date|not-installed)
          : ;;
      esac
    done <<<"$_pending_rows"
    if [[ "$_n_avail" -eq 0 && "$_n_pinned" -eq 0 ]]; then
      pass "All members up-to-date"
    elif [[ "$_n_avail" -gt 0 ]]; then
      printf "  %s·%s  Run \`eidolons upgrade\` to apply.\n" "${YELLOW:-}" "${RESET:-}"
    fi
  fi
fi

# ─── Check 10: Orphaned host-vendor files ────────────────────────────────
# Warns when a vendor file exists on disk but its corresponding host is not
# in hosts.wire. This typically happens after upgrading from v1.4.x where
# the CLI created GEMINI.md / copilot-instructions.md unconditionally.
# The remedy is manual deletion — the CLI never deletes user-tracked files.
# Warn-only; exit code unaffected (ERRORS not incremented).
ui_section_out "Orphaned host-vendor files"

DOCTOR_HOSTS_CSV="$(yaml_to_json "$PROJECT_MANIFEST" | jq -r '.hosts.wire | join(",")')"

_DOCTOR_VENDOR_HOST_MAP="GEMINI.md:gemini
.github/copilot-instructions.md:copilot"

while IFS=: read -r _vfile _vhost; do
  [[ -n "$_vfile" ]] || continue
  if [[ -f "$_vfile" ]] && [[ ",${DOCTOR_HOSTS_CSV}," != *",${_vhost},"* ]]; then
    warn "$_vfile exists but host '$_vhost' is not in hosts.wire."
    warn "  remedy: delete $_vfile if you no longer use the $_vhost host;"
    warn "          OR add '$_vhost' to hosts.wire in eidolons.yaml and re-sync."
  else
    pass "$_vfile orphan check passed"
  fi
done <<EOF
$_DOCTOR_VENDOR_HOST_MAP
EOF

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
if (( ERRORS == 0 )); then
  ok "All checks passed."
  exit 0
else
  warn "$ERRORS issue(s) found."
  if [[ "$FIX" == "true" ]]; then
    say "Attempting repairs via 'eidolons sync'..."
    exec bash "$SELF_DIR/sync.sh"
  else
    echo ""
    echo "Run 'eidolons doctor --fix' to attempt repairs, or 'eidolons sync' manually."
    exit 1
  fi
fi
