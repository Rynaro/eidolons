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
  --fix         Attempt to auto-repair simple structural issues (lockfile drift,
                missing host wiring). Read-only for methodology gates (D1..D6).
  --deep        Run methodology-integrity gates (D1..D6) after the fast checks.
                Required to catch broken outbound links, token-budget overruns,
                and content drift vs the release manifest.
  -h, --help    Show this help.

Checks:
  - eidolons.yaml present and valid
  - eidolons.lock present and consistent with manifest
  - Each installed Eidolon has its files in .eidolons/<n>/
  - Each installed Eidolon's install.manifest.json is valid
  - Host dispatch files exist for every host listed in eidolons.yaml
  - Release-integrity status per lock entry (verified / legacy / missing)

Deep checks (--deep):
  D1   agent.md token budget                    MUST <= 1000 tokens
  D2   agent.md outbound link resolution         all (skills|templates|schemas)/*.{md,json,y[a]ml} refs MUST resolve
  D3   SPEC.md outbound link resolution          same as D2 against SPEC.md
  D4   manifest_sha256 vs lock                   MUST match (WARN-skip on legacy)
  D5   host-vendor agent body contract           MUST reference agent.md + SPEC.md, zero legacy <UPPER>.md refs
  D6   skills/ dual-write SHA parity             MUST match between .eidolons/<n>/skills/*.md and .claude/skills/<n>-<basename>/SKILL.md
EOF
}

FIX=false
DEEP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)    FIX=true; shift ;;
    --deep)   DEEP=true; shift ;;
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

# ─── Check 11: AGENTS.md drift ────────────────────────────────────────────
# Warns when AGENTS.md still contains substantive per-Eidolon content blocks
# (i.e., <!-- eidolon:<name> start --> for any member in the lockfile) that
# should have been hoisted into EIDOLONS.md by the compose pass. Also surfaces
# the stale v1.5.0 `eidolons-md-pointer` block, which is no longer written by
# sync under v1.6.0+.
#
# Warn-only; ERRORS unaffected. Remedy: re-run `eidolons sync`, or for the
# v1.5.0 supplementary block, delete the marker pair manually.
ui_section_out "AGENTS.md drift"

if [[ ! -f "AGENTS.md" ]]; then
  pass "AGENTS.md not present — drift check N/A"
else
  # Collect member names from the lockfile (.members[].name).
  _doctor_members=""
  if [[ -f "$PROJECT_LOCK" ]]; then
    _doctor_members="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
      | jq -r '(.members // [])[].name' 2>/dev/null || true)"
  fi

  _drift_count=0
  if [[ -n "$_doctor_members" ]]; then
    while IFS= read -r _m; do
      [[ -n "$_m" ]] || continue
      # Substantive content block: <!-- eidolon:<m> start --> WITHOUT -pointer suffix.
      # Note: a -pointer marker is <!-- eidolon:<m>-pointer start --> — the exact
      # match on `<m> start -->` is what discriminates.
      if grep -qF "<!-- eidolon:${_m} start -->" AGENTS.md 2>/dev/null; then
        warn "AGENTS.md still contains <!-- eidolon:${_m} --> content block (expected: hoisted into EIDOLONS.md)."
        warn "  remedy: run 'eidolons sync' to re-hoist."
        _drift_count=$((_drift_count + 1))
      fi
    done <<< "$_doctor_members"
  fi

  # Stale v1.5.0 supplementary pointer block.
  if grep -qF "<!-- eidolon:eidolons-md-pointer start -->" AGENTS.md 2>/dev/null; then
    warn "AGENTS.md contains a stale <!-- eidolon:eidolons-md-pointer --> block from v1.5.0."
    warn "  remedy: delete the marker pair (and the body lines between them) manually;"
    warn "          the per-member <name>-pointer blocks already redirect to EIDOLONS.md."
  fi

  if [[ "$_drift_count" -eq 0 ]] && ! grep -qF "<!-- eidolon:eidolons-md-pointer start -->" AGENTS.md 2>/dev/null; then
    pass "AGENTS.md drift check passed (only pointer blocks present)"
  fi
fi

# ─── Check 12: Version-stamp drift ───────────────────────────────────────
# Warns when eidolons.lock's eidolons_cli_version (or eidolons.yaml's header
# comment) does not match the current nexus VERSION. Caught when a user
# upgrades the nexus CLI but their project's stamps are stale.
#
# Warn-only; ERRORS unaffected. Remedy: `eidolons migrate-stamp` (see R2B-5).
ui_section_out "Version-stamp drift"

_nexus_ver=""
if [[ -f "$NEXUS/VERSION" ]]; then
  _nexus_ver="$(tr -d '[:space:]' < "$NEXUS/VERSION")"
fi

if [[ -z "$_nexus_ver" ]]; then
  printf "  %s·%s nexus VERSION unreadable — version-stamp check skipped\n" \
    "${YELLOW:-}" "${RESET:-}"
elif [[ -f "$PROJECT_LOCK" ]]; then
  _stamp_lock="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r '.eidolons_cli_version // empty' 2>/dev/null || true)"
  if [[ -n "$_stamp_lock" ]] && [[ "$_stamp_lock" != "$_nexus_ver" ]]; then
    warn "eidolons.lock eidolons_cli_version is '$_stamp_lock' but nexus VERSION is '$_nexus_ver'."
    warn "  remedy: run 'eidolons migrate-stamp' to rewrite eidolons.yaml and eidolons.lock stamps to '$_nexus_ver'."
  else
    pass "eidolons.lock version stamp matches nexus ($_nexus_ver)"
  fi
elif [[ -f "$PROJECT_MANIFEST" ]]; then
  # No lockfile but manifest exists — scan the header comment as fallback.
  _stamp_yaml="$(sed -n '2p' "$PROJECT_MANIFEST" 2>/dev/null \
    | sed -E 's/^# Generated by eidolons v([^ ]+) at .*$/\1/' \
    | sed -E 's/.*[^0-9.]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true)"
  if [[ -n "$_stamp_yaml" ]] && [[ "$_stamp_yaml" != "$_nexus_ver" ]]; then
    warn "eidolons.yaml header comment stamps version '$_stamp_yaml' but nexus VERSION is '$_nexus_ver'."
    warn "  remedy: run 'eidolons migrate-stamp' to rewrite the header comment to '$_nexus_ver'."
  else
    pass "eidolons.yaml version stamp matches nexus ($_nexus_ver)"
  fi
else
  printf "  %s·%s no eidolons.yaml or eidolons.lock — version-stamp check skipped\n" \
    "${YELLOW:-}" "${RESET:-}"
fi

# ─── Check 13: Legacy <name>-pointer stubs ────────────────────────────────
# Warn-only: detects leftover <name>-pointer blocks from v1.6.0 installs
# that have not yet been cleaned by eidolons sync (D10).
ui_section_out "Legacy pointer stubs"

POINTER_TARGETS_FOR_DOCTOR="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
  | jq -r '.hosts.pointer_targets // [] | join(" ")' 2>/dev/null || true)"

# Fallback: scan the closed vendor file set when pointer_targets is absent.
if [[ -z "$POINTER_TARGETS_FOR_DOCTOR" ]]; then
  POINTER_TARGETS_FOR_DOCTOR="CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md"
fi

LEGACY_STUBS_FOUND=false
for _vfile in $POINTER_TARGETS_FOR_DOCTOR; do
  [[ -f "$_vfile" ]] || continue
  # Match <!-- eidolon:<name>-pointer start --> blocks, but exclude
  # <!-- eidolon:dispatch-pointer start --> which is the v1.7.0 canonical form.
  if grep -E '<!-- eidolon:[a-z][a-z0-9-]*-pointer start -->' "$_vfile" 2>/dev/null \
       | grep -qvF '<!-- eidolon:dispatch-pointer start -->'; then
    LEGACY_STUBS_FOUND=true
    warn "$_vfile contains legacy <name>-pointer stubs (v1.6.0 → v1.7.0 migration)"
  fi
done

if [[ "$LEGACY_STUBS_FOUND" == "true" ]]; then
  warn "Remedy: run \`eidolons sync\` to clean up legacy pointer stubs (v1.6.0 → v1.7.0 migration)."
else
  pass "no legacy <name>-pointer stubs detected"
fi

# ─── Check 14: Wired-host vendor file unhoisted markers (Round 5) ────────
# Warns when a vendor file in the closed set carries substantive Eidolon
# content markers (i.e., non-dispatch-pointer markers) AND its host is in
# hosts.wire AND the file is NOT in hosts.pointer_targets. Surfaces the
# drift introduced when --no-multi-pointer is explicit OR when v1.8.0
# projects migrate to v1.8.1 before --re-derive runs.
#
# Severity: warn by default; die under hosts.strict=true (consistent with
# Round-4 strict-host validation).
ui_section_out "Wired vendor file marker drift"

# Read manifest fields needed for the check.
_r5_hosts_csv="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
  | jq -r '.hosts.wire // [] | join(",")' 2>/dev/null || true)"
_r5_pt_csv="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
  | jq -r '.hosts.pointer_targets // [] | join(",")' 2>/dev/null || true)"
_r5_strict="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
  | jq -r '.hosts.strict // "false"' 2>/dev/null || true)"

_r5_drift_count=0
# Hardcoded closed vendor set; must match _validate_pointer_targets_csv (lib.sh).
# Cross-reference: both lists must stay in sync when new vendor files are added.
# Format: "<file>:<host_name>" — host slug matched against hosts.wire CSV.
_R5_VENDOR_HOST_MAP="CLAUDE.md:claude-code
AGENTS.md:codex
GEMINI.md:gemini
.github/copilot-instructions.md:copilot"

while IFS=: read -r _r5_vfile _r5_vhost; do
  [[ -n "$_r5_vfile" ]] || continue
  [[ -f "$_r5_vfile" ]] || continue
  # AGENTS.md is wired by EITHER codex OR opencode (EIIS §4.1.0).
  if [[ "$_r5_vfile" == "AGENTS.md" ]]; then
    case ",$_r5_hosts_csv," in
      *",codex,"*|*",opencode,"*) : ;;
      *) continue ;;
    esac
  else
    case ",$_r5_hosts_csv," in
      *",${_r5_vhost},"*) : ;;
      *) continue ;;
    esac
  fi
  # File must be NOT in pointer_targets.
  case ",$_r5_pt_csv," in
    *",${_r5_vfile},"*) continue ;;
  esac
  # File must carry at least one non-dispatch-pointer Eidolon marker.
  grep -qE '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' "$_r5_vfile" 2>/dev/null || continue
  grep -E '<!-- eidolon:[a-z][a-z0-9-]*[[:space:]]+start[[:space:]]+-->' "$_r5_vfile" 2>/dev/null \
    | grep -vqE 'eidolon:dispatch-pointer' || continue

  _r5_drift_count=$((_r5_drift_count + 1))
  if [[ "$_r5_strict" == "true" ]]; then
    die "$_r5_vfile carries Eidolon content markers but is not in hosts.pointer_targets (host '$_r5_vhost' wired). Run 'eidolons init --re-derive --multi-pointer' to include it, or 'eidolons sync' to hoist content into EIDOLONS.md. (--strict-hosts=true)"
  else
    warn "$_r5_vfile carries Eidolon content markers but is not in hosts.pointer_targets (host '$_r5_vhost' wired)."
    warn "  remedy: 'eidolons init --re-derive --multi-pointer' to include this file in pointer_targets,"
    warn "          or 'eidolons sync' to hoist content into EIDOLONS.md (vendor file will be emptied)."
  fi
done <<EOF
$_R5_VENDOR_HOST_MAP
EOF

if [[ "$_r5_drift_count" -eq 0 ]]; then
  pass "no wired vendor file marker drift detected"
fi
unset _r5_hosts_csv _r5_pt_csv _r5_strict _r5_drift_count _r5_vfile _r5_vhost _R5_VENDOR_HOST_MAP

# ─── Methodology integrity (--deep) ─────────────────────────────────────
# D1..D6 run only when --deep is passed. The fast checks (1..14) always run
# first. Within this section, checks do NOT short-circuit on early failures:
# each member is iterated through all 6 gates independently so a broken
# Eidolon does not mask drift in another.
#
# --fix is read-only here: methodology drift requires re-install via
# 'eidolons sync --force' or 'eidolons add <member> --force'.
if [[ "$DEEP" == "true" ]]; then
  if ! manifest_exists; then
    printf "  %s·%s 0 Eidolons to check (run eidolons init first)\n" \
      "${YELLOW:-}" "${RESET:-}"
  else
    ui_section_out "Methodology integrity (--deep)"

    # Read the member list from the lockfile (covers resolved versions).
    _deep_members=""
    if [[ -f "$PROJECT_LOCK" ]]; then
      _deep_members="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
        | jq -r '(.members // [])[].name' 2>/dev/null || true)"
    fi

    if [[ -z "$_deep_members" ]]; then
      printf "  %s·%s 0 Eidolons to check (eidolons.lock is empty or missing)\n" \
        "${YELLOW:-}" "${RESET:-}"
    else
      # D1 — agent.md token budget
      echo "  D1 — agent.md token budget"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d1_rc=0
        deep_check_agent_token_budget "$_dm" || _d1_rc=$?
        ERRORS=$((ERRORS + _d1_rc))
      done <<< "$_deep_members"

      # D2 — agent.md outbound link resolution
      echo "  D2 — agent.md outbound links"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d2_rc=0
        deep_check_agent_links "$_dm" || _d2_rc=$?
        ERRORS=$((ERRORS + _d2_rc))
      done <<< "$_deep_members"

      # D3 — SPEC.md outbound link resolution
      echo "  D3 — SPEC.md outbound links"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d3_rc=0
        deep_check_spec_links "$_dm" || _d3_rc=$?
        ERRORS=$((ERRORS + _d3_rc))
      done <<< "$_deep_members"

      # D4 — Content integrity vs release manifest
      echo "  D4 — Content integrity vs lock"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d4_ver="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
          | jq -r --arg n "$_dm" '(.members // [])[] | select(.name == $n) | .version // ""' \
          2>/dev/null || true)"
        _d4_rc=0
        deep_check_manifest_integrity "$_dm" "${_d4_ver:-unknown}" || _d4_rc=$?
        ERRORS=$((ERRORS + _d4_rc))
      done <<< "$_deep_members"

      # D5 — Host-vendor agent body contract
      echo "  D5 — Host-vendor agent bodies"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d5_rc=0
        deep_check_host_agent_body "$_dm" || _d5_rc=$?
        ERRORS=$((ERRORS + _d5_rc))
      done <<< "$_deep_members"

      # D6 — Skills dual-write SHA parity
      echo "  D6 — Skills dual-write parity"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d6_rc=0
        deep_check_skills_dual_write "$_dm" || _d6_rc=$?
        ERRORS=$((ERRORS + _d6_rc))
      done <<< "$_deep_members"
    fi

    # Remedy hint when methodology errors were found.
    if (( ERRORS > 0 )); then
      echo ""
      echo "  Methodology issues found. Remedy: 'eidolons sync --force' or"
      echo "  'eidolons add <member> --force' to re-install affected members."
    fi
  fi
fi

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
