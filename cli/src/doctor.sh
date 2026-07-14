#!/usr/bin/env bash
# eidolons doctor — health-check installed Eidolons and host wiring
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_mcp.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_resolve.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_model_wiring.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib_memory_probe.sh"

usage() {
  cat <<EOF
eidolons doctor — health-check installed Eidolons and host wiring

Usage: eidolons doctor [OPTIONS]

Options:
  --fix         Attempt to auto-repair simple structural issues (lockfile drift,
                missing host wiring). Read-only for methodology gates (D1..D11).
  --deep        Run methodology-integrity gates (D1..D11) after the fast checks.
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
  - Agent files missing explicit tools: line (warn — inherits ALL tools)

Deep checks (--deep):
  D1   agent.md token budget                    MUST <= 1000 tokens
  D2   agent.md outbound link resolution         all (skills|templates|schemas)/*.{md,json,y[a]ml} refs MUST resolve
  D3   SPEC.md outbound link resolution          same as D2 against SPEC.md
  D4   manifest_sha256 vs lock                   MUST match (WARN-skip on legacy)
  D5   host-vendor agent body contract           MUST reference agent.md + SPEC.md, zero legacy <UPPER>.md refs
  D6   skills/ dual-write SHA parity             MUST match between .eidolons/<n>/skills/*.md and .claude/skills/<n>-<basename>/SKILL.md
  D7   ACI boundary conformance                 roster security block MUST match the capability class's ACI contract (roster/aci.yaml; SWE-agent rubric)
  D8   ECL receiver verify-incoming             every installed receiver Eidolon MUST ship a blocking verify-incoming skill (roster/ecl.yaml; ECL 6.2.2, frontier N3)
  D9   Model frontmatter drift                 managed model: in agent files MUST match lock's effective_model (SKIP when no models block)
  D10  host-tier gate structural check          when ≥2 coders exist and one requires a host_tier, assert a conservative fallback coder is present (routing tiebreak invariant)
  D11  coder edit-gate ACI conformance          coder-class members MUST declare requires_edit_gate:true in ACI + reference the lint gate in SPEC.md (S1.3 declarative contract)
  D12  harness lock⇄files consistency           shims exist+exec, settings/hooks/opencode.json valid+entries present, strict surfaces only on verified-sound hosts, effective-tier report
  D13  memory recallability probe                crystalium doctor + a probe recall via the docker transform; SKIP when crystalium not gated in; WARN (never FAIL) on 0 records or unreachable
  D14  routing.yaml 1.1 shape                    nexus-level: routing_version present, degraded_mode/fallback/reroute_to/escalation/trance shape conformance; FAIL on violation (data integrity, not an environment probe)
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
    err "$f is a symlink — shared dispatch files must be real composable files. Re-run 'eidolons sync'."
    continue
  fi
  if grep -Eq '@?\.?/?agents/(atlas|apivr|spectra|idg|scribe|forge)/' "$f" 2>/dev/null; then
    err "$f contains legacy agents/<name>/ pointers (pre-v1.1 paths). Delete the Eidolon block(s) and re-run 'eidolons sync'."
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

# ─── Check 7b: OCI-server .mcp.json UID/GID + bind-path sanity ────────────
# Reads .mcp.json directly (not via eidolons.mcp.lock) to surface UID/GID pin
# and bind-path issues even when a server is wired as an MCP but the lockfile
# entry is absent. Requires jq. Silently skips per-name when .mcp.json is
# absent, malformed, or carries no key for that name (D-T3.6/3.7/3.8 semantics).
#
# Iterates every workspace-binding OCI MCP name (tonberry, atomos, atlas-aci —
# the three servers that bind-mount the project root read-write and therefore
# need a --user pin matching the host UID/GID). This used to hardcode a single
# call to _mcp_driver_oci_uid_bind_probes "atlas-aci", so doctor silently
# never probed tonberry/atomos even when their .mcp.json entries had no --user
# pin at all — every write inside those distroless containers was failing
# while doctor reported green. Keep this list in sync with the OCI templates
# under cli/templates/mcp/*.mcp.json.tmpl that bind __PROJECT_ROOT__.
#
# err probe lines → increment ERRORS (exit non-zero per D-T3.2/3.4/3.5).
# warn probe lines → print yellow warning without incrementing ERRORS (D-T3.3).
if command -v jq >/dev/null 2>&1 && [ -f ".mcp.json" ]; then
  for _dt3_name in atlas-aci tonberry atomos; do
    _dt3_probe_output="$(_mcp_driver_oci_uid_bind_probes "$_dt3_name" 2>/dev/null || true)"
    if [ -n "$_dt3_probe_output" ]; then
      while IFS= read -r _dt3_line; do
        [ -n "$_dt3_line" ] || continue
        # Extract the status word (3rd whitespace-separated field).
        _dt3_status="$(printf '%s' "$_dt3_line" | awk '{print $3}')"
        # Extract the reason (everything after the first 3 fields).
        _dt3_reason="$(printf '%s' "$_dt3_line" | awk '{$1=$2=$3=""; sub(/^[[:space:]]+/,""); print}')"
        case "$_dt3_status" in
          err)
            err "${_dt3_name}: ${_dt3_reason}"
            ;;
          warn)
            printf "  %s·%s %s: %s\n" "${YELLOW:-}" "${RESET:-}" "$_dt3_name" "$_dt3_reason"
            ;;
        esac
      done <<< "$_dt3_probe_output"
    fi
  done
fi

# ─── Check 7c: MCP wiring integrity ───────────────────────────────────────
# ESL change mcp-verify-lock-vs-artifact (R9): the lock is intent, .mcp.json
# is effect — the previous checks (7/7b) trust the lock; this one verifies
# the artifact via 'eidolons mcp verify --json' (F1: verify never repairs).
# Fast path (NOT --deep) — F2: fail-open is a hot-path doctrine (ECM fires
# every prompt, autonomously); doctor is explicitly invoked and waiting for
# an answer, so a diagnostic that cannot say NO is a printf. The check costs
# one extra jq-only subprocess reading files doctor already opens: no docker,
# no network, no --probe.
#
# BLOCK findings increment ERRORS (exit non-zero). INDETERMINATE (e.g. a
# fresh clone with no .mcp.json yet) does NOT — that is the normal state
# 'mcp verify' itself reports as exit 3, never a doctor failure (AC-6).
#
# This is a DIFFERENT question from "MCP catalogue drift" below (lock vs
# pins.stable — "you could upgrade"): this asks "you are lying" (lock vs the
# artifact it claims to describe). Both stay in the fast path; neither
# subsumes the other (AC-5).
ui_section_out "MCP wiring integrity"
if ! command -v jq >/dev/null 2>&1; then
  printf "  %s·%s jq not on PATH — MCP wiring integrity check skipped\n" \
    "${YELLOW:-}" "${RESET:-}"
else
  _verify_json="$(bash "$SELF_DIR/mcp_verify.sh" --json 2>/dev/null || true)"
  if [[ -z "$_verify_json" ]] || ! jq empty <<< "$_verify_json" >/dev/null 2>&1; then
    printf "  %s·%s MCP wiring integrity check unavailable (mcp verify produced no parseable output)\n" \
      "${YELLOW:-}" "${RESET:-}"
  else
    _verify_block_count="$(jq -r '.summary.block // 0' <<< "$_verify_json" 2>/dev/null || echo 0)"
    _verify_warn_count="$(jq -r '.summary.warn // 0' <<< "$_verify_json" 2>/dev/null || echo 0)"
    _verify_indet_count="$(jq -r '.summary.indeterminate // 0' <<< "$_verify_json" 2>/dev/null || echo 0)"
    if [[ "$_verify_block_count" -gt 0 ]]; then
      while IFS= read -r _vfinding; do
        [[ -z "$_vfinding" ]] && continue
        _vmcp="$(jq -r '.mcp' <<< "$_vfinding")"
        _vmsg="$(jq -r '.message' <<< "$_vfinding")"
        _vremedy="$(jq -r '.remedy // empty' <<< "$_vfinding")"
        err "${_vmcp}: ${_vmsg}"
        if [[ -n "$_vremedy" ]]; then
          printf "      remedy: %s\n" "$_vremedy"
        fi
      done < <(jq -c '.findings[] | select(.severity == "block")' <<< "$_verify_json")
    elif [[ "$_verify_indet_count" -gt 0 ]]; then
      printf "  %s·%s could not fully verify MCP wiring (%s indeterminate — run 'eidolons mcp verify' for detail; typically a fresh clone with no .mcp.json yet)\n" \
        "${YELLOW:-}" "${RESET:-}" "$_verify_indet_count"
    else
      pass "All locked MCPs verified against .mcp.json (wired matches locked)"
    fi
    if [[ "$_verify_warn_count" -gt 0 ]] && [[ "$_verify_block_count" -eq 0 ]]; then
      printf "  %s·%s %s advisory finding(s) — run 'eidolons mcp verify' for details\n" \
        "${YELLOW:-}" "${RESET:-}" "$_verify_warn_count"
    fi
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

# ─── Check 12b: Roster freshness ────────────────────────────────────────────
# Non-fatal informational probe: compare the local nexus cache roster against
# the HEAD of the roster channel (origin/<channel>). Warns when behind and hints
# "eidolons nexus refresh". Never increments ERRORS — purely advisory.
# Skipped when EIDOLONS_NEXUS is set (local checkout) or EIDOLONS_SKIP_REFRESH=1.
ui_section_out "Roster freshness"

if [[ -n "${EIDOLONS_NEXUS:-}" ]]; then
  printf "  %s·%s roster freshness check skipped (local checkout — EIDOLONS_NEXUS set)\n" \
    "${YELLOW:-}" "${RESET:-}"
elif [[ "${EIDOLONS_SKIP_REFRESH:-0}" == "1" ]]; then
  printf "  %s·%s roster freshness check skipped (EIDOLONS_SKIP_REFRESH=1)\n" \
    "${YELLOW:-}" "${RESET:-}"
elif [[ ! -d "$NEXUS/.git" ]]; then
  printf "  %s·%s roster freshness check skipped (nexus has no .git — not a managed cache)\n" \
    "${YELLOW:-}" "${RESET:-}"
else
  # Resolve channel and effective ref.
  nexus_ensure_roster_ref 2>/dev/null || true
  _rfc_channel="$(nexus_roster_ref 2>/dev/null || echo main)"
  _rfc_effective="$_rfc_channel"
  if [[ "$_rfc_channel" == "stable" ]]; then
    _rfc_resolved="$(nexus_latest_tag 2>/dev/null || true)"
    if [[ -n "$_rfc_resolved" ]]; then
      _rfc_effective="$_rfc_resolved"
    else
      _rfc_effective=""
    fi
  fi

  if [[ -z "$_rfc_effective" ]]; then
    printf "  %s·%s roster freshness check skipped (stable channel: offline or no tags reachable)\n" \
      "${YELLOW:-}" "${RESET:-}"
  else
    _rfc_repo="${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}"
    _rfc_cache_sha="$(git -C "$NEXUS" rev-parse HEAD 2>/dev/null || true)"
    _rfc_upstream_sha=""
    _rfc_upstream_sha="$(with_timeout 8 git ls-remote --refs "$_rfc_repo" "$_rfc_effective" \
      2>/dev/null | awk '{print $1}' | head -1 || true)"

    if [[ -z "$_rfc_upstream_sha" ]]; then
      printf "  %s·%s roster freshness unknown (offline — could not probe origin/%s)\n" \
        "${YELLOW:-}" "${RESET:-}" "$_rfc_channel"
    elif [[ "$_rfc_upstream_sha" == "$_rfc_cache_sha" ]]; then
      pass "roster cache fresh ($_rfc_channel)"
    else
      warn "roster cache behind $_rfc_channel — run: eidolons nexus refresh"
    fi
  fi
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

# ─── Check 15: Agent files missing explicit tools: line ─────────────────────
# Warn-only (non-fatal): for each installed member whose .claude/agents/<name>.md
# exists and has no `tools:` line in frontmatter, remind that the agent inherits
# ALL tools (Claude Code semantics) and that the upstream template should ship an
# explicit allowlist. This is the scenario that the MCP wiring driver now skips
# instead of synthesizing a crystalium-only allowlist (FORGE decision D2).
#
# ERRORS not incremented — purely advisory.
ui_section_out "Agent tools: line coverage"

_c15_claude_wired=false
if [[ -f "$PROJECT_MANIFEST" ]]; then
  if yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
       | jq -e '.hosts.wire | index("claude-code")' >/dev/null 2>&1; then
    _c15_claude_wired=true
  fi
fi

_c15_warned=false
if [[ "$_c15_claude_wired" == "true" ]] && [[ -f "$PROJECT_LOCK" ]]; then
  _c15_members="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r '(.members // [])[].name' 2>/dev/null || true)"
  while IFS= read -r _c15_m; do
    [[ -n "$_c15_m" ]] || continue
    _c15_agent=".claude/agents/${_c15_m}.md"
    [[ -f "$_c15_agent" ]] || continue
    # Check for tools: line in frontmatter (between first and second ---).
    _c15_has_tools="$(awk '
      /^---$/ { fc++; if (fc==1) { in_fm=1; next } if (fc==2) { exit } }
      in_fm && /^tools:[[:space:]]/ { print "1"; exit }
    ' "$_c15_agent" 2>/dev/null || true)"
    if [[ "${_c15_has_tools:-}" != "1" ]]; then
      warn "${_c15_agent}: no tools: line — agent inherits ALL tools (Claude Code semantics)."
      warn "  The upstream ${_c15_m} template should ship an explicit tools: allowlist."
      warn "  MCP wiring will skip allowlist injection for this agent until a tools: line is present."
      _c15_warned=true
    fi
  done <<< "$_c15_members"
  unset _c15_members _c15_m _c15_agent _c15_has_tools
fi

if [[ "$_c15_warned" == "false" ]]; then
  pass "All installed claude-code agent files have an explicit tools: line"
fi
unset _c15_claude_wired _c15_warned

#
# D13: memory recallability probe (crystalium round-trip liveness)
# Project-level gate (not per-member): when crystalium is gated in (same gate
# as 'eidolons memory preflight' — .mcp.json AND eidolons.mcp.lock; shared via
# lib_memory_probe.sh, NOT lib.sh), runs the crystalium CLI `doctor`
# subcommand and a probe `recall --k 3` via the same docker-args transform as
# memory preflight. Hard 10s timeout per invocation (with_timeout, lib.sh).
#
# This is a DIAGNOSTIC surface, not a release gate: it NEVER fails the run.
#   - crystalium not gated in           -> SKIP (pass, informational)
#   - docker absent / build / timeout   -> WARN "crystalium unreachable for probe"
#   - probe recall returns 0 records    -> WARN (store may be write-only)
#   - probe recall returns >0 records   -> PASS with the count
# Always returns 0 (rc is not accumulated into ERRORS beyond warn's no-op).
deep_check_memory_recallability() {
  local root; root="$(pwd)"

  if ! memory_probe_gated_in "$root"; then
    pass "D13 memory recallability: crystalium not gated in (skip)"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    warn "D13 memory recallability: crystalium unreachable for probe (docker not on PATH)"
    return 0
  fi

  # ── crystalium doctor ────────────────────────────────────────────────────
  local doctor_script; doctor_script="$(mktemp)"
  if memory_probe_build_docker_script "$root" "doctor" "$doctor_script"; then
    local doctor_out doctor_exit=0
    doctor_out="$(with_timeout 10 bash "$doctor_script" 2>/dev/null)" || doctor_exit=$?
    if [[ "$doctor_exit" -eq 0 ]]; then
      local verdict
      verdict="$(printf '%s' "$doctor_out" \
        | grep -E 'all P0 checks passed|P0 checks FAILED' | tail -1)"
      pass "D13 crystalium doctor: ${verdict:-ran (exit 0)}"
    else
      warn "D13 crystalium doctor: crystalium unreachable for probe (exit $doctor_exit)"
    fi
  else
    warn "D13 crystalium doctor: crystalium unreachable for probe ('serve' not found in .mcp.json args)"
  fi
  rm -f "$doctor_script"

  # ── probe recall (--k 3, generic query) ──────────────────────────────────
  local recall_script; recall_script="$(mktemp)"
  local slug; slug="$(memory_probe_project_slug "$root")"
  local q_query q_slug recall_args
  q_query="$(memory_probe_quote "project")"
  q_slug="$(memory_probe_quote "$slug")"
  recall_args="recall --query $q_query --scope-project $q_slug --k 3 --format json"

  if ! memory_probe_build_docker_script "$root" "$recall_args" "$recall_script"; then
    warn "D13 memory recallability probe: crystalium unreachable for probe ('serve' not found in .mcp.json args)"
    rm -f "$recall_script"
    return 0
  fi

  local recall_out recall_exit=0
  recall_out="$(with_timeout 10 bash "$recall_script" 2>/dev/null)" || recall_exit=$?
  rm -f "$recall_script"

  if [[ "$recall_exit" -ne 0 ]]; then
    warn "D13 memory recallability probe: crystalium unreachable for probe (exit $recall_exit)"
    return 0
  fi

  if ! printf '%s' "$recall_out" | jq empty >/dev/null 2>&1; then
    warn "D13 memory recallability probe: crystalium unreachable for probe (malformed output)"
    return 0
  fi

  local count
  count="$(printf '%s' "$recall_out" | jq -r '(.records // []) | length' 2>/dev/null || echo "0")"
  if [[ "$count" -eq 0 ]]; then
    warn "D13 memory recallability probe: crystalium store returns 0 records — memory is effectively write-only (check scope keys, crystal status, embeddings)"
  else
    pass "D13 memory recallability probe: crystalium returned $count record(s)"
  fi

  return 0
}

#
# D14: routing.yaml 1.1 shape validation (nexus data integrity)
# Nexus-level gate, not project-level: routing.yaml is nexus-side data (like
# roster/index.yaml), not something a consumer project owns, so this check
# does not iterate installed members — it validates the single nexus
# roster/routing.yaml file directly (mirrors D10's `dirname "$ROSTER_FILE"`
# resolution, cli/src/lib.sh:2141).
#
# Validates the v1.1 shape mechanically (jq/yq, no eval — I-C2):
#   - routing_version is present (non-empty)
#   - every eidolons.<n>.degraded_mode ∈ {fanout, sample-select}
#   - every eidolons.<n>.fallback / escalation.reroute_to names an existing
#     eidolons key (referential integrity)
#   - eidolons.<n>.escalation.on_fail ∈ {reroute, escalate-tier}
#   - eidolons.<n>.escalation.max_escalations is an integer >= 1
#   - trance.lead_tier / trance.workers_tier ∈ {light, standard, deep}
#
# This is nexus DATA integrity, not an environment probe (unlike D13): FAIL
# is correct here (fatal), mirroring D10's severity for a structural routing
# misconfiguration. Returns the violation count (0 = pass, >=1 = fatal).
deep_check_routing_shape() {
  local routing_file; routing_file="$(dirname "$ROSTER_FILE")/routing.yaml"
  if [[ ! -f "$routing_file" ]]; then
    pass "D14 routing shape: no routing.yaml — skip"
    return 0
  fi

  local routing_json; routing_json="$(yaml_to_json "$routing_file" 2>/dev/null || true)"
  if [[ -z "$routing_json" ]]; then
    warn "D14 routing shape: could not parse routing.yaml — skip"
    return 0
  fi

  local violations
  violations="$(printf '%s' "$routing_json" | jq -r '
    . as $r
    | ($r.eidolons // {}) as $E
    | ($E | keys) as $names
    | (if (($r.routing_version // "") == "") then "routing_version missing" else empty end),
      ( $E | to_entries[] as $e |
        ( ($e.value.degraded_mode // null) as $dm
          | if $dm != null and ($dm != "fanout" and $dm != "sample-select")
            then "\($e.key).degraded_mode invalid: \($dm) (expected fanout|sample-select)"
            else empty end
        ),
        ( ($e.value.fallback // null) as $fb
          | if $fb != null and ($names | index($fb) | not)
            then "\($e.key).fallback references unknown eidolon: \($fb)"
            else empty end
        ),
        ( ($e.value.escalation // null) as $esc
          | if $esc != null then
              ( ($esc.reroute_to // null) as $rt
                | if $rt != null and ($names | index($rt) | not)
                  then "\($e.key).escalation.reroute_to references unknown eidolon: \($rt)"
                  else empty end
              ),
              ( ($esc.on_fail // null) as $of
                | if $of != null and ($of != "reroute" and $of != "escalate-tier")
                  then "\($e.key).escalation.on_fail invalid: \($of) (expected reroute|escalate-tier)"
                  else empty end
              ),
              ( ($esc.max_escalations // null) as $me
                | if $me != null and (($me | type) != "number" or ($me | floor) != $me or $me < 1)
                  then "\($e.key).escalation.max_escalations invalid: \($me) (expected integer >= 1)"
                  else empty end
              )
            else empty end
        )
      ),
      ( ($r.trance // null) as $tr
        | if $tr != null then
            ( ($tr.lead_tier // null) as $lt
              | if $lt != null and ($lt != "light" and $lt != "standard" and $lt != "deep")
                then "trance.lead_tier invalid: \($lt) (expected light|standard|deep)"
                else empty end
            ),
            ( ($tr.workers_tier // null) as $wt
              | if $wt != null and ($wt != "light" and $wt != "standard" and $wt != "deep")
                then "trance.workers_tier invalid: \($wt) (expected light|standard|deep)"
                else empty end
            )
          else empty end
      )
  ' 2>/dev/null)"

  local rc=0
  if [[ -n "$violations" ]]; then
    while IFS= read -r _v; do
      [[ -z "$_v" ]] && continue
      err "D14 routing shape: $_v"
      rc=$((rc + 1))
    done <<< "$violations"
  else
    pass "D14 routing shape: routing.yaml conforms to the 1.1 shape"
  fi
  return "$rc"
}

# ─── Methodology integrity (--deep) ─────────────────────────────────────
# D1..D7 run only when --deep is passed. The fast checks (1..14) always run
# first. Within this section, checks do NOT short-circuit on early failures:
# each member is iterated through all 6 gates independently so a broken
# Eidolon does not mask drift in another.
#
# --fix is read-only here: methodology drift requires re-install via
# 'eidolons sync' (re-installs each member) or 'eidolons remove <member> && eidolons add <member>'.
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

      # D7 — ACI boundary conformance (SWE-agent ACI rubric, R8-02)
      echo "  D7 — ACI boundary conformance"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d7_rc=0
        deep_check_aci_conformance "$_dm" || _d7_rc=$?
        ERRORS=$((ERRORS + _d7_rc))
      done <<< "$_deep_members"

      # D8 — ECL receiver verify-incoming conformance (frontier N3, ECL 6.2.2)
      echo "  D8 — ECL receiver verify-incoming"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d8_rc=0
        deep_check_verify_incoming_conformance "$_dm" || _d8_rc=$?
        ERRORS=$((ERRORS + _d8_rc))
      done <<< "$_deep_members"

      # D9 — Model frontmatter drift (model management gate)
      # SKIP when no models block is present in eidolons.yaml.
      # PASS  — every applicable managed model: == lock effective_model.
      # WARN  — hand-authored model: without sentinel, or host-inapplicable managed line.
      # FAIL  — managed model: (sentinel present) != lock effective_model (fatal in --deep).
      echo "  D9 — Model frontmatter drift"
      _d9_model_block=false
      model_resolve_init 2>/dev/null || true
      if model_has_block 2>/dev/null; then
        _d9_model_block=true
      fi
      if [[ "$_d9_model_block" == "false" ]]; then
        printf "  %s·%s D9 — no models block in eidolons.yaml — skipping\n" \
          "${YELLOW:-}" "${RESET:-}"
      else
        _d9_active_profile="$(model_active_profile 2>/dev/null || echo 'anthropic')"
        _d9_hosts_csv="$(yaml_to_json "$PROJECT_MANIFEST" 2>/dev/null \
          | jq -r '(.hosts.wire // []) | join(",")' 2>/dev/null || true)"

        while IFS= read -r _dm; do
          [[ -z "$_dm" ]] && continue

          # Resolve expected model from lock.
          _d9_lock_model="$(yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
            | jq -r --arg n "$_dm" \
              '(.members // [])[] | select(.name == $n) | .model.effective_model // empty' \
              2>/dev/null || true)"

          # If lock has no model entry yet, skip (not a fail — just needs sync).
          if [[ -z "$_d9_lock_model" ]]; then
            printf "  %s·%s D9 %s — no lock model entry (run 'eidolons sync' or 'eidolons model use')\n" \
              "${YELLOW:-}" "${RESET:-}" "$_dm"
            continue
          fi

          # Check each wired host.
          for _d9_host in $(printf '%s' "$_d9_hosts_csv" | tr ',' ' '); do
            [[ -z "$_d9_host" ]] && continue
            case "$_d9_host" in
              claude-code) _d9_agent_file=".claude/agents/${_dm}.md" ;;
              codex)       _d9_agent_file=".codex/agents/${_dm}.md" ;;
              *)           continue ;;
            esac

            [[ -f "$_d9_agent_file" ]] || continue

            # Check applies_to_hosts.
            if ! model_profile_applies_to_host "$_d9_active_profile" "$_d9_host" 2>/dev/null; then
              # If the file has a managed model block, that's a warning.
              _d9_managed="$(_model_wiring_read_managed "$_d9_agent_file" 2>/dev/null || true)"
              if [[ -n "$_d9_managed" ]]; then
                printf "  %s·%s D9 WARN %s (%s): profile '%s' does not apply but managed model: present\n" \
                  "${YELLOW:-}" "${RESET:-}" "$_dm" "$_d9_host" "$_d9_active_profile"
              fi
              continue
            fi

            # Read managed model from file.
            _d9_file_model="$(_model_wiring_read_managed "$_d9_agent_file" 2>/dev/null || true)"

            if [[ -z "$_d9_file_model" ]]; then
              # No managed line — check for unmanaged.
              if _model_wiring_has_unmanaged_model "$_d9_agent_file" 2>/dev/null; then
                printf "  %s·%s D9 WARN %s (%s): hand-authored model: without eidolons sentinel\n" \
                  "${YELLOW:-}" "${RESET:-}" "$_dm" "$_d9_host"
              else
                printf "  %s·%s D9 %s (%s): no managed model: line (run 'eidolons sync' to write)\n" \
                  "${YELLOW:-}" "${RESET:-}" "$_dm" "$_d9_host"
              fi
              continue
            fi

            # Compare managed value vs lock.
            if [[ "$_d9_file_model" == "$_d9_lock_model" ]]; then
              pass "D9 ${_dm} (${_d9_host}): model: matches lock (${_d9_lock_model})"
            else
              err "D9 ${_dm} (${_d9_host}): managed model: '${_d9_file_model}' != lock effective_model '${_d9_lock_model}'. Run 'eidolons model use ${_dm}@${_d9_lock_model}' or 'eidolons sync' to fix."
            fi
          done
        done <<< "$_deep_members"
      fi
      unset _d9_model_block _d9_active_profile _d9_hosts_csv _d9_host _d9_agent_file _d9_file_model _d9_lock_model _d9_managed

      # D10 — host-tier gate structural check (S1.7, G1)
      # Project-level check: not per-member. Verifies routing tiebreak invariant
      # when ≥2 coders exist and one declares requires_host_tier.
      echo "  D10 — host-tier gate"
      _d10_rc=0
      deep_check_host_tier_gate || _d10_rc=$?
      ERRORS=$((ERRORS + _d10_rc))

      # D11 — coder edit-gate ACI conformance (S1.3, declarative contract)
      # Per-member: coder-class members MUST declare requires_edit_gate:true in
      # ACI + reference the lint gate in SPEC.md. Non-coder members are exempt.
      echo "  D11 — coder edit-gate ACI conformance"
      while IFS= read -r _dm; do
        [[ -z "$_dm" ]] && continue
        _d11_rc=0
        deep_check_coder_edit_gate "$_dm" || _d11_rc=$?
        ERRORS=$((ERRORS + _d11_rc))
      done <<< "$_deep_members"

      # D12 — harness lock⇄files consistency (R22)
      # Project-level gate: lock claims ⇄ on-disk surfaces + effective-tier report.
      # D12 is NOT D10 (D10/D11 are shipped; D12 is the next free number).
      echo "  D12 — harness lock⇄files consistency"
      _d12_rc=0
      deep_check_harness_consistency || _d12_rc=$?
      ERRORS=$((ERRORS + _d12_rc))

      # D13 — memory recallability probe (crystalium round-trip liveness)
      # Project-level gate: SKIP when crystalium not gated in; WARN (never
      # FAIL) on 0 records or unreachable — a diagnostic surface, not a
      # release gate. Always returns 0; not accumulated into ERRORS.
      echo "  D13 — memory recallability probe"
      deep_check_memory_recallability || true

      # D14 — routing.yaml 1.1 shape validation (nexus data integrity)
      # Nexus-level gate (not per-member): validates roster/routing.yaml's
      # degraded_mode/fallback/escalation/trance shape + referential
      # integrity. Fatal — data integrity, not an environment probe.
      echo "  D14 — routing.yaml shape"
      _d14_rc=0
      deep_check_routing_shape || _d14_rc=$?
      ERRORS=$((ERRORS + _d14_rc))
    fi

    # Remedy hint when methodology errors were found.
    if (( ERRORS > 0 )); then
      echo ""
      echo "  Methodology issues found. Remedy: 'eidolons sync' (re-installs each"
      echo "  member) or remove + re-add: 'eidolons remove <name> && eidolons add <name>'."
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
