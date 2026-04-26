#!/usr/bin/env bash
# eidolons upgrade — surface and apply nexus + member version upgrades.
#
# Spec: docs/specs/eidolons-upgrade/spec.md (decisions §4, tests §6).
#
# Two surfaces on a single command:
#   eidolons upgrade --check         read-only diff (nexus + members)
#   eidolons upgrade                 mutating: applies member upgrades
#
# Flags: --system, --project, --all, --check, --json, --yes,
#        --non-interactive, --dry-run.
# Positional: member name or comma-separated list (mutex with --system / --all).
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/ui/prompt.sh"

CHECK=false
SYSTEM_ONLY=false
PROJECT_ONLY=false
ALL=false
JSON=false
YES=false
NON_INTERACTIVE=false
DRY_RUN=false
TARGET_LIST=""   # comma-separated positional names (empty = all members)

usage() {
  cat <<EOF
eidolons upgrade — upgrade pinned Eidolon versions

Usage: eidolons upgrade [TARGET] [OPTIONS]                 # default: project (members)
       eidolons upgrade --check [SCOPE] [TARGET] [--json]  # read-only diff
       eidolons upgrade --system  [OPTIONS]                # nexus only
       eidolons upgrade --project [TARGET] [OPTIONS]       # explicit project scope
       eidolons upgrade --all     [OPTIONS]                # nexus then members

Modes:
  (bare)        Upgrade members in this project (requires eidolons.yaml).
  --check       Read-only: print upgrade availability. Without a scope flag
                inspects both surfaces; combine with --system or --project to
                narrow the report.
  --system      Upgrade only the nexus at \$EIDOLONS_HOME/nexus.
  --project     Operate on cwd members. Equivalent to bare \`eidolons upgrade\`
                when given alone; useful for explicit symmetry with --system.
  --all         Upgrade nexus first, then members (equivalent to
                --system --project). Mutex with TARGET.

Options:
  --json              JSON output on stdout (with --check).
  --yes, -y           Skip confirmation prompt.
  --non-interactive   Fail on prompts. Mutating runs require --yes.
  --dry-run           Show plan without fetching or invoking install.sh.
  -h, --help          Show this help.

Behavior:
  - Member upgrades respect ^/~/= constraints in eidolons.yaml. A latest
    that exceeds the constraint is reported as 'pinned-out' (no auto-jump).
  - Lockfile is rewritten only if at least one resolved version changed.
  - Per-member install failures are reported at the end; final exit is 1
    when any member upgrade failed, 0 otherwise.
EOF
}

# ─── Argument parsing ────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)            CHECK=true; shift ;;
    --system)           SYSTEM_ONLY=true; shift ;;
    --project)          PROJECT_ONLY=true; shift ;;
    --all)              ALL=true; shift ;;
    --json)             JSON=true; shift ;;
    --yes|-y)           YES=true; shift ;;
    --non-interactive)  NON_INTERACTIVE=true; shift ;;
    --dry-run)          DRY_RUN=true; shift ;;
    -h|--help)          usage; exit 0 ;;
    --*)                echo "Unknown option: $1" >&2
                        echo "Try: eidolons upgrade --help" >&2
                        exit 2 ;;
    *)
      if [[ -n "$TARGET_LIST" ]]; then
        echo "Unexpected extra positional argument: $1" >&2
        exit 2
      fi
      TARGET_LIST="$1"; shift
      ;;
  esac
done

# Mutex / equivalence rules (spec §11.5).
# --system + --project is the long-form of --all; collapse it before mutex checks.
if [[ "$SYSTEM_ONLY" == true && "$PROJECT_ONLY" == true ]]; then
  ALL=true
  SYSTEM_ONLY=false
  PROJECT_ONLY=false
fi
if [[ "$SYSTEM_ONLY" == true && -n "$TARGET_LIST" ]]; then
  echo "--system operates on the nexus only; member arguments belong to project scope." >&2
  echo "Drop one or use --all." >&2
  exit 2
fi
if [[ "$ALL" == true && -n "$TARGET_LIST" ]]; then
  echo "--all upgrades every member; drop the positional argument or use <member> without --all." >&2
  exit 2
fi
if [[ "$ALL" == true && "$SYSTEM_ONLY" == true ]]; then
  echo "--all and --system are mutually exclusive." >&2
  exit 2
fi

# Mutating, non-interactive runs without --yes refuse to proceed.
if [[ "$CHECK" != true && "$NON_INTERACTIVE" == true && "$YES" != true ]]; then
  echo "--non-interactive mutating run requires --yes (or use --check)." >&2
  exit 2
fi

# ─── Helpers (file-local) ────────────────────────────────────────────────

# json_string VALUE → echo the value as a JSON string literal (or "null").
json_string() {
  local v="$1"
  if [[ -z "$v" ]]; then
    echo "null"
    return 0
  fi
  printf '"%s"' "$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

# strip_constraint OPERATOR-PREFIXED-VERSION → bare X.Y.Z
strip_constraint() {
  local v="$1"
  v="${v#^}"; v="${v#~}"; v="${v#=}"
  echo "$v"
}

# normalize_target_list → echoes one canonical name per line resolved through
# roster_get (so aliases map to canonical names). Exits 2 with a hint when an
# entry is unknown.
normalize_target_list() {
  local list="$1"
  [[ -z "$list" ]] && return 0
  local IFS_=,
  local raw
  IFS="$IFS_" read -ra raw <<<"$list"
  local item entry name
  for item in "${raw[@]}"; do
    [[ -z "$item" ]] && continue
    if ! entry="$(roster_get "$item" 2>/dev/null)"; then
      echo "Eidolon '$item' not found in roster. Try: eidolons list" >&2
      return 2
    fi
    name="$(echo "$entry" | jq -r '.name')"
    echo "$name"
  done
}

# ─── Nexus check ─────────────────────────────────────────────────────────
# Echoes (on stdout) three space-separated tokens consumed by the report
# renderer:
#   <current_tag> <current_commit> <latest_tag_or_empty>
# The third token is empty when the probe failed (offline degradation).
collect_nexus_status() {
  local cur_tag cur_commit latest=""
  cur_tag="$(nexus_current_tag)"
  cur_commit="$(nexus_current_commit)"
  latest="$(nexus_latest_tag 2>/dev/null || true)"
  echo "$cur_tag|$cur_commit|$latest"
}

# Compare a current tag with a latest tag. Echoes one of:
#   up-to-date | upgrade-available | unknown
nexus_status_label() {
  local cur="$1" latest="$2"
  if [[ -z "$latest" ]]; then
    echo "unknown"
    return 0
  fi
  # Strip leading 'v' for SemVer comparison.
  local c="${cur#v}" l="${latest#v}"
  case "$c" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) echo "unknown"; return 0 ;;
  esac
  if [[ "$c" == "$l" ]]; then
    echo "up-to-date"
  elif semver_lt "$c" "$l"; then
    echo "upgrade-available"
  else
    echo "up-to-date"   # ahead of remote (dev checkout); treat as current
  fi
}

# ─── Member status collection ────────────────────────────────────────────
# Echoes one TSV line per member: name<TAB>installed<TAB>latest<TAB>constraint<TAB>status
# status ∈ {up-to-date, upgrade-available, pinned-out, not-installed}
# When a target list is provided, restricts to those names (canonical).
collect_member_rows() {
  manifest_exists || return 0
  local manifest_json members_json
  manifest_json="$(yaml_to_json "$PROJECT_MANIFEST")"
  members_json="$(echo "$manifest_json" | jq -c '.members[]')"

  local target_canon=""
  if [[ -n "$TARGET_LIST" ]]; then
    target_canon="$(normalize_target_list "$TARGET_LIST")" || return $?
  fi

  while IFS= read -r mline; do
    [[ -z "$mline" ]] && continue
    local name constraint roster_entry latest installed status
    name="$(echo "$mline" | jq -r '.name')"
    constraint="$(echo "$mline" | jq -r '.version')"
    if [[ -n "$target_canon" ]]; then
      if ! printf '%s\n' "$target_canon" | grep -Fxq "$name"; then
        continue
      fi
    fi
    roster_entry="$(roster_get "$name" 2>/dev/null || true)"
    if [[ -z "$roster_entry" ]]; then
      latest=""
    else
      latest="$(echo "$roster_entry" | jq -r '.versions.latest // empty')"
    fi
    installed="$(lock_member_version "$name")"
    if [[ -z "$installed" ]]; then
      status="not-installed"
    elif [[ -z "$latest" || "$installed" == "$latest" ]]; then
      status="up-to-date"
    elif semver_lt "$installed" "$latest"; then
      if semver_satisfies "$constraint" "$latest"; then
        status="upgrade-available"
      else
        status="pinned-out"
      fi
    else
      status="up-to-date"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${installed:-—}" "${latest:-—}" "$constraint" "$status"
  done <<<"$members_json"
}

# ─── Report rendering ────────────────────────────────────────────────────

render_human_report() {
  local nexus_line="$1"; shift
  local member_rows="$1"; shift   # multi-line TSV (may be empty)
  local scope="${1:-both}"        # both | system | project (controls narrowing)
  local cur_tag cur_commit latest nstatus

  IFS='|' read -r cur_tag cur_commit latest <<<"$nexus_line"
  nstatus="$(nexus_status_label "$cur_tag" "$latest")"

  say "Checking upgrades"

  if [[ "$scope" != "project" ]]; then
    echo ""
    echo "  NEXUS"
    echo "    current:  ${cur_tag}  (commit ${cur_commit:0:7})"
    if [[ -z "$latest" ]]; then
      echo "    latest:   unknown (offline)"
      warn "nexus upstream unreachable — showing local roster only"
    else
      echo "    latest:   ${latest}  (Rynaro/eidolons)"
    fi
    case "$nstatus" in
      up-to-date)
        echo "    status:   up-to-date"
        ;;
      upgrade-available)
        echo "    status:   upgrade available"
        echo "    action:   curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash"
        echo "              (or: eidolons upgrade --system)"
        ;;
      *)
        echo "    status:   unknown (offline)"
        ;;
    esac
  fi

  # Suppress the members block entirely when --system narrowed the scope.
  if [[ "$scope" == "system" ]]; then
    echo ""
    echo "  SUMMARY"
    case "$nstatus" in
      upgrade-available)
        echo "    1 nexus upgrade available"
        echo "    Run \`eidolons upgrade --system\` to apply."
        ;;
      up-to-date)
        echo "    Nexus is up-to-date."
        ;;
      *)
        echo "    Nexus status unknown (offline probe)."
        ;;
    esac
    return 0
  fi

  if [[ -z "$member_rows" ]]; then
    if ! manifest_exists; then
      echo ""
      echo "  No eidolons.yaml in cwd — members section omitted."
    fi
  else
    echo ""
    echo "  MEMBERS                                                       (from eidolons.lock)"
    printf "    %-12s %-12s %-12s %-15s %s\n" "NAME" "INSTALLED" "LATEST" "CONSTRAINT" "STATUS"
    while IFS=$'\t' read -r n inst lat con st; do
      [[ -z "$n" ]] && continue
      local pretty_status
      case "$st" in
        upgrade-available) pretty_status="upgrade available" ;;
        *) pretty_status="$st" ;;
      esac
      printf "    %-12s %-12s %-12s %-15s %s\n" "$n" "$inst" "$lat" "$con" "$pretty_status"
    done <<<"$member_rows"
  fi

  echo ""
  echo "  SUMMARY"
  local n_avail=0 n_pinned=0 n_missing=0 n_uptodate=0
  if [[ -n "$member_rows" ]]; then
    while IFS=$'\t' read -r _n _inst _lat _con st; do
      [[ -z "$st" ]] && continue
      case "$st" in
        upgrade-available) n_avail=$((n_avail+1)) ;;
        pinned-out)        n_pinned=$((n_pinned+1)) ;;
        not-installed)     n_missing=$((n_missing+1)) ;;
        up-to-date)        n_uptodate=$((n_uptodate+1)) ;;
      esac
    done <<<"$member_rows"
  fi
  if [[ "$scope" != "project" && "$nstatus" == "upgrade-available" ]]; then
    echo "    1 nexus upgrade available"
  fi
  echo "    $n_avail member upgrades available"
  if (( n_pinned > 0 )); then
    echo "    $n_pinned member(s) pinned-out (edit eidolons.yaml constraint to allow)"
  fi
  if (( n_missing > 0 )); then
    echo "    $n_missing member(s) declared but not installed (run: eidolons sync)"
  fi
  if (( n_avail == 0 && n_pinned == 0 )) && [[ -n "$member_rows" ]]; then
    echo "    All members up-to-date."
  fi
  if (( n_avail > 0 )); then
    echo "    Run \`eidolons upgrade\` to apply member upgrades."
  fi
}

render_json_report() {
  local nexus_line="$1"; shift
  local member_rows="$1"; shift
  local cur_tag cur_commit latest nstatus
  IFS='|' read -r cur_tag cur_commit latest <<<"$nexus_line"
  nstatus="$(nexus_status_label "$cur_tag" "$latest")"
  local nstatus_label
  case "$nstatus" in
    upgrade-available) nstatus_label="upgrade available" ;;
    up-to-date)        nstatus_label="up-to-date" ;;
    *)                 nstatus_label="unknown (offline)" ;;
  esac

  # Build JSON via jq for safe escaping.
  local members_json="[]"
  if [[ -n "$member_rows" ]]; then
    members_json="$(printf '%s\n' "$member_rows" | awk -F'\t' '
      BEGIN { print "[" }
      NR>1 { print "," }
      NF>=5 {
        gsub(/"/,"\\\"",$1); gsub(/"/,"\\\"",$2); gsub(/"/,"\\\"",$3); gsub(/"/,"\\\"",$4)
        printf "{\"name\":\"%s\",\"installed\":%s,\"latest\":\"%s\",\"constraint\":\"%s\",\"status\":\"%s\"}",
          $1, ($2=="—"?"null":"\""$2"\""), $3, $4, ($5=="upgrade-available"?"upgrade available":$5)
      }
      END { print "]" }
    ')"
  fi

  local summary
  local n_avail=0 n_pinned=0 n_missing=0
  if [[ -n "$member_rows" ]]; then
    while IFS=$'\t' read -r _n _inst _lat _con st; do
      [[ -z "$st" ]] && continue
      case "$st" in
        upgrade-available) n_avail=$((n_avail+1)) ;;
        pinned-out)        n_pinned=$((n_pinned+1)) ;;
        not-installed)     n_missing=$((n_missing+1)) ;;
      esac
    done <<<"$member_rows"
  fi
  local nexus_avail="false"
  [[ "$nstatus" == "upgrade-available" ]] && nexus_avail="true"
  summary=$(printf '{"nexus_upgrade_available":%s,"member_upgrades_available":%d,"member_upgrades_pinned_out":%d,"members_not_installed":%d}' \
    "$nexus_avail" "$n_avail" "$n_pinned" "$n_missing")

  local nexus_obj
  nexus_obj=$(printf '{"current":{"tag":%s,"commit":%s},"latest":{"tag":%s},"status":"%s"}' \
    "$(json_string "$cur_tag")" \
    "$(json_string "$cur_commit")" \
    "$(json_string "$latest")" \
    "$nstatus_label")

  printf '{"nexus":%s,"members":%s,"summary":%s}\n' \
    "$nexus_obj" "$members_json" "$summary"
}

# ─── Mutating per-member install ─────────────────────────────────────────
# Returns 0 on success, 1 on failure. Echoes a lockfile member fragment to
# stdout when successful.
upgrade_install_member() {
  local name="$1" target_version="$2" hosts_csv="$3" effective_dispatch="$4"
  local entry repo target clone_dir
  entry="$(roster_get "$name")"
  repo="$(echo "$entry" | jq -r '.source.repo')"
  target="./.eidolons/$name"

  say "Upgrading $name → $target_version"

  # Invalidate stale caches for this member (any version directory).
  if [[ -d "$CACHE_DIR" ]]; then
    local d
    for d in "$CACHE_DIR/$name@"*; do
      [[ -d "$d" ]] || continue
      rm -rf "$d"
    done
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "  [dry-run] would fetch and install $name@$target_version"
    return 0
  fi

  clone_dir="$(fetch_eidolon "$name" "$target_version")" || {
    warn "$name fetch failed"
    return 1
  }

  eiis_check "$clone_dir" "$name" || true

  if [[ ! -x "$clone_dir/install.sh" ]]; then
    warn "$name has no executable install.sh — skipping"
    return 1
  fi

  local shared_flag_args=()
  if grep -q -- '--no-shared-dispatch' "$clone_dir/install.sh" 2>/dev/null; then
    if [[ "$effective_dispatch" == "true" ]]; then
      shared_flag_args=(--shared-dispatch)
    else
      shared_flag_args=(--no-shared-dispatch)
    fi
  fi

  (
    cd "$(pwd)"
    bash "$clone_dir/install.sh" \
      --target "$target" \
      --hosts "$hosts_csv" \
      "${shared_flag_args[@]}" \
      ${NON_INTERACTIVE:+--non-interactive} \
      --force
  ) || { warn "$name install failed"; return 1; }

  # Override install.manifest.json's version with the actual git tag.
  if [[ -f "$target/install.manifest.json" ]]; then
    local actual_tag actual_ver tmp_m
    actual_tag="$(git -C "$clone_dir" describe --tags --exact-match HEAD 2>/dev/null \
                  || git -C "$clone_dir" describe --tags 2>/dev/null \
                  || echo "")"
    if [[ -n "$actual_tag" ]]; then
      actual_ver="${actual_tag#v}"
      tmp_m="$(mktemp)"
      if jq --arg v "$actual_ver" '.version = $v' "$target/install.manifest.json" > "$tmp_m"; then
        mv "$tmp_m" "$target/install.manifest.json"
      else
        rm -f "$tmp_m"
      fi
    fi
  fi

  ok "$name upgraded"
  return 0
}

# Emit a YAML lockfile fragment for a single member to stdout. Reused for
# both freshly upgraded members and members carried-over verbatim.
emit_lock_fragment_from_target() {
  local name="$1" target="./.eidolons/$1" repo="$2"
  if [[ -f "$target/install.manifest.json" ]]; then
    local ver hosts_wired
    ver="$(jq -r '.version' "$target/install.manifest.json" 2>/dev/null || echo "")"
    hosts_wired="$(jq -c '.hosts_wired // []' "$target/install.manifest.json")"
    cat <<LOCK
  - name: $name
    version: "$ver"
    resolved: "github:${repo}@$(git -C "$CACHE_DIR/$name@$ver" rev-parse HEAD 2>/dev/null || echo unknown)"
    target: "$target"
    hosts_wired: $hosts_wired
LOCK
  else
    cat <<LOCK
  - name: $name
    version: "unknown"
    resolved: "github:${repo}"
    target: "$target"
    manifest_missing: true
LOCK
  fi
}

# Carry forward the existing lockfile entry for a member untouched. Reads
# eidolons.lock and re-serialises. This preserves resolved commits the
# current run did not touch.
emit_lock_fragment_carry() {
  local name="$1"
  yaml_to_json "$PROJECT_LOCK" 2>/dev/null \
    | jq -r --arg n "$name" '
      (.members // [])[] | select(.name == $n) |
      [
        "  - name: \(.name)",
        "    version: \"\(.version // "")\"",
        "    resolved: \"\(.resolved // "")\"",
        "    target: \"\(.target // "")\"",
        if .hosts_wired then "    hosts_wired: \(.hosts_wired | tojson)" else empty end,
        if .manifest_missing then "    manifest_missing: \(.manifest_missing | tojson)" else empty end
      ] | join("\n")
    '
}

# ─── Top-level dispatch ──────────────────────────────────────────────────

# Validate target list early (before any network or report rendering) so a
# bad name fails fast with exit 2.
if [[ -n "$TARGET_LIST" && "$SYSTEM_ONLY" != true ]]; then
  if ! normalize_target_list "$TARGET_LIST" >/dev/null; then
    exit 2
  fi
fi

# Phase 0: --system only path (no member work). Mutating runs short-circuit
# here; --check --system flows through Phase 2 with scope narrowing.
if [[ "$SYSTEM_ONLY" == true && "$CHECK" != true ]]; then
  nx="$(collect_nexus_status)"
  IFS='|' read -r cur_tag cur_commit latest <<<"$nx"
  status_label="$(nexus_status_label "$cur_tag" "$latest")"
  if [[ "$JSON" == true ]]; then
    render_json_report "$nx" ""
  else
    echo "  NEXUS"
    echo "    current:  ${cur_tag}  (commit ${cur_commit:0:7})"
    if [[ -z "$latest" ]]; then
      echo "    latest:   unknown (offline)"
    else
      echo "    latest:   ${latest}"
    fi
  fi
  case "$status_label" in
    up-to-date)
      ok "Nexus already up-to-date."
      exit 0
      ;;
    unknown)
      die "Cannot determine latest nexus version (probe failed)."
      ;;
    upgrade-available)
      if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] would fetch + reset nexus to $latest"
        exit 0
      fi
      if nexus_self_update "$latest"; then
        ok "Nexus updated to $latest"
        info "Re-run 'eidolons upgrade --check' to see freshly visible member versions."
        exit 0
      fi
      die "Failed to fetch $latest from nexus remote. Nexus state unchanged."
      ;;
  esac
fi

# Phase 1: --all → upgrade nexus first, then fall through to members.
if [[ "$ALL" == true ]]; then
  nx="$(collect_nexus_status)"
  IFS='|' read -r _cur_tag _cur_commit latest <<<"$nx"
  status_label="$(nexus_status_label "$_cur_tag" "$latest")"
  case "$status_label" in
    upgrade-available)
      if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] would fetch + reset nexus to $latest"
      else
        nexus_self_update "$latest" \
          || die "Nexus fetch failed; aborting --all (member phase will not run)."
        ok "Nexus updated to $latest"
      fi
      ;;
    up-to-date)
      info "Nexus already up-to-date."
      ;;
    unknown)
      warn "Nexus probe failed; continuing with local roster only."
      ;;
  esac
fi

# Phase 2: --check (read-only) — render and exit 0.
if [[ "$CHECK" == true ]]; then
  scope="both"
  if [[ "$SYSTEM_ONLY" == true ]]; then
    scope="system"
  elif [[ "$PROJECT_ONLY" == true ]]; then
    scope="project"
  fi
  nx="$(collect_nexus_status)"
  rows=""
  if [[ "$scope" != "system" ]] && manifest_exists; then
    rows="$(collect_member_rows)" || exit $?
  fi
  if [[ "$JSON" == true ]]; then
    render_json_report "$nx" "$rows"
  else
    render_human_report "$nx" "$rows" "$scope"
  fi
  exit 0
fi

# Phase 3: mutating member upgrade.
manifest_exists || die "No eidolons.yaml found. Run 'eidolons init' first."

NX="$(collect_nexus_status)"
ROWS="$(collect_member_rows)" || exit $?

# Determine work list: rows whose status is upgrade-available.
WORK=""
PINNED=""
while IFS=$'\t' read -r n inst lat con st; do
  [[ -z "$n" ]] && continue
  case "$st" in
    upgrade-available) WORK="$WORK"$'\n'"$n"$'\t'"$lat" ;;
    pinned-out)        PINNED="$PINNED"$'\n'"$n"$'\t'"$lat"$'\t'"$con" ;;
  esac
done <<<"$ROWS"
WORK="${WORK#$'\n'}"
PINNED="${PINNED#$'\n'}"

# Show plan.
render_human_report "$NX" "$ROWS"

if [[ -z "$WORK" ]]; then
  echo ""
  ok "All members up-to-date."
  # Surface pinned-out as an informational note (already rendered in summary).
  exit 0
fi

# Confirmation.
if [[ "$YES" != true && "$NON_INTERACTIVE" != true ]]; then
  echo ""
  if ! ui_confirm "Proceed with upgrade?" default-y; then
    die "Upgrade aborted by user."
  fi
fi

# Compute hosts wiring + effective dispatch (mirrors sync.sh §codex override).
MANIFEST_JSON="$(yaml_to_json "$PROJECT_MANIFEST")"
HOSTS_CSV="$(echo "$MANIFEST_JSON" | jq -r '.hosts.wire | join(",")')"
SHARED_DISPATCH="$(echo "$MANIFEST_JSON" | jq -r '.hosts.shared_dispatch // false')"
EFFECTIVE_SHARED_DISPATCH="$SHARED_DISPATCH"
if [[ ",$HOSTS_CSV," == *",codex,"* ]] && [[ "$SHARED_DISPATCH" != "true" ]]; then
  warn "--no-shared-dispatch ignored for hosts.wire containing codex; AGENTS.md is Codex's primary instruction surface."
  EFFECTIVE_SHARED_DISPATCH="true"
fi

# Drive per-member installs.
FAILED=""
SUCCEEDED=""
while IFS=$'\t' read -r mname mver; do
  [[ -z "$mname" ]] && continue
  if upgrade_install_member "$mname" "$mver" "$HOSTS_CSV" "$EFFECTIVE_SHARED_DISPATCH"; then
    SUCCEEDED="$SUCCEEDED $mname"
  else
    FAILED="$FAILED $mname"
  fi
done <<<"$WORK"

# Lockfile rewrite (only if the resolved set actually changed).
if [[ "$DRY_RUN" != true && -n "$SUCCEEDED" ]]; then
  LOCK_TMP="$(mktemp)"
  cat > "$LOCK_TMP" <<EOF
# eidolons.lock — auto-generated by 'eidolons upgrade'. Commit to VCS.
generated_at: "$(date -u +%FT%TZ)"
eidolons_cli_version: "${EIDOLONS_VERSION:-1.0.0}"
nexus_commit: "$(git -C "$NEXUS" rev-parse HEAD 2>/dev/null || echo unknown)"
members:
EOF
  # For each member declared in the manifest: if it was upgraded this run,
  # emit fresh fragment from disk; otherwise carry forward the existing
  # lock entry verbatim (preserves untouched resolved commits).
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    entry="$(roster_get "$name" 2>/dev/null || true)"
    repo=""
    [[ -n "$entry" ]] && repo="$(echo "$entry" | jq -r '.source.repo')"
    if [[ " $SUCCEEDED " == *" $name "* ]]; then
      emit_lock_fragment_from_target "$name" "$repo" >> "$LOCK_TMP"
    else
      frag="$(emit_lock_fragment_carry "$name")"
      if [[ -n "$frag" ]]; then
        echo "$frag" >> "$LOCK_TMP"
      fi
    fi
  done <<<"$(manifest_members)"
  mv "$LOCK_TMP" "$PROJECT_LOCK"
  ok "Wrote $PROJECT_LOCK"
fi

# Summary.
echo ""
if [[ -n "$SUCCEEDED" ]]; then
  ok "Upgraded:$SUCCEEDED"
fi
if [[ -n "$FAILED" ]]; then
  warn "Failed:$FAILED"
  echo "  Recovery: fix the underlying issue and re-run 'eidolons upgrade$FAILED'." >&2
  exit 1
fi
exit 0
