#!/usr/bin/env bash
# cli/src/lib_model_wiring.sh — host-native model descriptor write-adapter.
#
# SOURCE this file; do NOT execute it directly.
# Requires lib.sh and lib_model_resolve.sh to have been sourced first.
#
# Public API:
#   model_wiring_patch_agent_file  HOST AGENT_FILE EFFECTIVE_MODEL [clobber]
#     Patch one host agent file with the managed model block.
#     FLAGS: pass "clobber" as 4th arg to override hand-authored model: lines
#     (used by explicit model commands). Default (sync-time) = warn-and-preserve.
#   model_wiring_apply_for_member  EIDOLON_ID [clobber]
#     Patch every (host, agent_file) for the given Eidolon with its resolved
#     effective model. Selects a compatible profile per host when no profile
#     was explicitly selected by the consumer.
#   model_wiring_apply_all         [clobber]
#     Re-apply model wiring for every installed Eidolon member.
#
# Managed sentinel: "# eidolons:managed model" immediately before the owned key.
# Idempotency: compare-before-write; byte-identical on repeat runs.
# Drift policy:
#   sync-time:        hand-authored model: (no sentinel) → warn-and-preserve.
#   explicit command: clobber mode → replace any existing model: with managed block.
#   doctor:           reports drift; does not auto-fix.
#
# Host support: Claude YAML frontmatter (.md) + Codex top-level TOML (.toml).
# Explicit NO-OP for copilot, cursor, opencode.
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# ═══════════════════════════════════════════════════════════════════════════

# Guard against double-source.
if [ -n "${_LIB_MODEL_WIRING_LOADED:-}" ]; then
  return 0
fi
_LIB_MODEL_WIRING_LOADED=1

MANAGED_SENTINEL="# eidolons:managed model"

# ─── Internal ────────────────────────────────────────────────────────────────

# _model_wiring_read_managed FILE
# Echo the managed model value if the sentinel is present; empty otherwise.
_model_wiring_read_managed() {
  local file="$1"
  case "$file" in
    *.toml) _model_wiring_read_managed_toml "$file"; return $? ;;
  esac
  # Look for the sentinel comment in frontmatter, then read the next model: line.
  awk '
  BEGIN { infm=0; seen_fence=0; found_sentinel=0 }
  /^---[[:space:]]*$/ {
    if (seen_fence==0) { seen_fence=1; infm=1; next }
    else { infm=0; next }
  }
  infm && $0 == "# eidolons:managed model" { found_sentinel=1; next }
  infm && found_sentinel && /^model:/ {
    val = substr($0, 7)
    # Trim leading whitespace
    while (substr(val,1,1)==" " || substr(val,1,1)=="\t") val = substr(val,2)
    print val
    exit
  }
  infm && found_sentinel { found_sentinel=0 }
  ' "$file" 2>/dev/null || true
}

# _model_wiring_read_managed_toml FILE
# Read only a sentinel-owned, quoted, top-level TOML model assignment. A model
# inside a table is deliberately ignored: Codex descriptors require this key at
# the document root.
_model_wiring_read_managed_toml() {
  local file="$1"
  awk '
  function decode_basic(s, out, i, ch, nextch) {
    out=""
    for (i=1; i<=length(s); i++) {
      ch=substr(s,i,1)
      if (ch != "\\" || i == length(s)) { out=out ch; continue }
      nextch=substr(s,++i,1)
      if (nextch == "n") out=out "\n"
      else if (nextch == "r") out=out "\r"
      else if (nextch == "t") out=out "\t"
      else out=out nextch
    }
    return out
  }
  BEGIN { top=1; owned=0 }
  /^[[:space:]]*\[/ { top=0 }
  top && $0 == "# eidolons:managed model" { owned=1; next }
  top && owned && /^[[:space:]]*model[[:space:]]*=[[:space:]]*"([^"\\]|\\.)*"[[:space:]]*(#.*)?$/ {
    val=$0
    sub(/^[[:space:]]*model[[:space:]]*=[[:space:]]*"/, "", val)
    sub(/"[[:space:]]*(#.*)?$/, "", val)
    print decode_basic(val)
    exit
  }
  top && owned { owned=0 }
  ' "$file" 2>/dev/null || true
}

# _model_wiring_has_unmanaged_model FILE
# Return 0 if the file has a model: line in frontmatter WITHOUT the sentinel.
_model_wiring_has_unmanaged_model() {
  local file="$1"
  case "$file" in
    *.toml) _model_wiring_has_unmanaged_model_toml "$file"; return $? ;;
  esac
  awk '
  BEGIN { infm=0; seen_fence=0; prev_sentinel=0; result=1 }
  /^---[[:space:]]*$/ {
    if (seen_fence==0) { seen_fence=1; infm=1; next }
    else { infm=0; next }
  }
  infm && $0 == "# eidolons:managed model" { prev_sentinel=1; next }
  infm && /^model:/ {
    if (prev_sentinel==0) { result=0 }
    exit
  }
  infm { prev_sentinel=0 }
  END { exit result }
  ' "$file" 2>/dev/null
}

# Return 0 for a top-level TOML model assignment not immediately owned by the
# sentinel. Assignments below the first table header are unrelated and ignored.
_model_wiring_has_unmanaged_model_toml() {
  local file="$1"
  awk '
  BEGIN { top=1; owned=0; model_count=0; result=1 }
  /^[[:space:]]*\[/ { top=0 }
  top && $0 == "# eidolons:managed model" { owned=1; next }
  top && /^[[:space:]]*model[[:space:]]*=/ {
    model_count++
    if (!owned) result=0
    owned=0
    next
  }
  top && owned { owned=0 }
  END {
    if (model_count > 1) result=0
    exit result
  }
  ' "$file" 2>/dev/null
}

# _model_wiring_patch_frontmatter FILE EFFECTIVE_MODEL CLOBBER
# Core awk surgery: insert/replace the managed block inside YAML frontmatter.
# CLOBBER: 1=replace any model: line; 0=warn-and-preserve on hand-authored model:.
_model_wiring_patch_frontmatter() {
  local file="$1"
  local model="$2"
  local clobber="${3:-0}"

  # Read current managed value for compare-before-write idempotency.
  local current_managed
  current_managed="$(_model_wiring_read_managed "$file" 2>/dev/null || true)"
  if [ "$current_managed" = "$model" ]; then
    # Already byte-identical — skip write.
    return 0
  fi

  # Drift check: unmanaged model: present?
  if _model_wiring_has_unmanaged_model "$file"; then
    if [ "$clobber" = "1" ]; then
      # Explicit command consent — clobber it.
      : # fall through to awk
    else
      # Sync-time: warn and preserve.
      warn "$(basename "$file"): hand-authored model: present (no sentinel) — preserving. Use 'eidolons model use' to take ownership."
      return 0
    fi
  fi

  local tmpfile
  tmpfile="$(mktemp)"

  # awk surgery: manage sentinel + model: within the YAML frontmatter only.
  # Handles three cases:
  #   A) sentinel already present → replace the following model: line.
  #   B) clobber=1 + unmanaged model: → replace with sentinel+model:.
  #   C) neither present → insert both lines immediately after opening ---.
  awk -v model="$model" -v sentinel="# eidolons:managed model" -v clobber="$clobber" '
  BEGIN {
    infm=0; seen_fence=0; done_key=0
    prev_sentinel=0
  }
  /^---[[:space:]]*$/ {
    if (seen_fence==0) {
      seen_fence=1; infm=1
      print
      # Case C: insert right after opening --- when we have no prior managed block
      # (check is deferred to after we see the rest of frontmatter, but we buffer
      # the insert-after-opening-fence here for the simplest single-pass approach:
      # do NOT insert here; handle at closing fence if still not done).
      next
    } else if (infm==1) {
      # Closing --- : if not yet done, insert before it (case C).
      if (done_key==0) {
        print sentinel
        print "model: " model
        done_key=1
      }
      infm=0
      print
      next
    }
    print
    next
  }
  infm && $0 == sentinel {
    # Case A: sentinel found — replace the next model: line.
    print
    prev_sentinel=1
    next
  }
  infm && prev_sentinel && /^model:/ {
    # Replace the model: line that follows the sentinel.
    print "model: " model
    done_key=1
    prev_sentinel=0
    next
  }
  infm && prev_sentinel {
    # Sentinel was present but no model: followed immediately — emit model: now.
    print "model: " model
    done_key=1
    prev_sentinel=0
    print
    next
  }
  infm && /^model:[[:space:]]/ {
    if (clobber == "1" && done_key==0) {
      # Case B: clobber unmanaged model: line.
      print sentinel
      print "model: " model
      done_key=1
      next
    }
    # Sync-time non-clobber: the caller already checked; just pass through.
    print
    next
  }
  { print }
  ' "$file" > "$tmpfile"

  # Preserve original permissions and do atomic mv.
  chmod --reference="$file" "$tmpfile" 2>/dev/null || \
    chmod "$(stat -f '%A' "$file" 2>/dev/null || echo 644)" "$tmpfile" 2>/dev/null || true
  mv "$tmpfile" "$file"
}

# _model_wiring_patch_toml FILE EFFECTIVE_MODEL CLOBBER
# Owns exactly one quoted top-level `model = "..."` assignment. Existing
# hand-authored assignments are preserved during sync and adopted only after an
# explicit model command passes CLOBBER=1.
_model_wiring_patch_toml() {
  local file="$1"
  local model="$2"
  local clobber="${3:-0}"
  local current_managed has_unmanaged=0 tmpfile

  current_managed="$(_model_wiring_read_managed_toml "$file" 2>/dev/null || true)"
  if _model_wiring_has_unmanaged_model_toml "$file"; then
    has_unmanaged=1
    if [ "$clobber" != "1" ]; then
      warn "$(basename "$file"): hand-authored top-level model present (no sentinel) — preserving. Use 'eidolons model use' to take ownership."
      return 0
    fi
  fi

  # Only short-circuit after scanning the complete top-level document. A
  # matching managed key followed by a duplicate user-owned key is invalid
  # TOML and must be reconciled in clobber mode (or preserved with a warning).
  if [ "$current_managed" = "$model" ] && [ "$has_unmanaged" = "0" ]; then
    return 0
  fi

  tmpfile="$(mktemp)"
  EIDOLONS_WIRING_TOML_MODEL="$model" awk -v sentinel="# eidolons:managed model" -v clobber="$clobber" '
  BEGIN {
    model=ENVIRON["EIDOLONS_WIRING_TOML_MODEL"]
    gsub(/\\/, "\\\\", model)
    gsub(/"/, "\\\"", model)
    gsub(/\t/, "\\t", model)
    gsub(/\r/, "\\r", model)
    gsub(/\n/, "\\n", model)
    top=1; owned=0; emitted=0
  }
  function emit() {
    if (!emitted) {
      print sentinel
      print "model = \"" model "\""
      emitted=1
    }
  }
  /^[[:space:]]*\[/ {
    if (top) { emit(); top=0 }
  }
  top && $0 == sentinel { owned=1; next }
  top && owned && /^[[:space:]]*model[[:space:]]*=/ { emit(); owned=0; next }
  top && owned { emit(); owned=0 }
  top && /^[[:space:]]*model[[:space:]]*=/ {
    if (clobber == "1") { emit(); next }
  }
  { print }
  END { emit() }
  ' "$file" > "$tmpfile" || { rm -f "$tmpfile"; return 1; }

  chmod --reference="$file" "$tmpfile" 2>/dev/null || \
    chmod "$(stat -f '%A' "$file" 2>/dev/null || echo 644)" "$tmpfile" 2>/dev/null || true
  mv "$tmpfile" "$file"
}

# ─── Public API ───────────────────────────────────────────────────────────────

# model_wiring_patch_agent_file HOST AGENT_FILE EFFECTIVE_MODEL [clobber]
# Dispatch to host-specific patcher (or no-op for unsupported hosts).
model_wiring_patch_agent_file() {
  local host="$1"
  local agent_file="$2"
  local effective_model="$3"
  local clobber="${4:-0}"

  if [ ! -f "$agent_file" ]; then
    if [ "$clobber" = "1" ]; then
      warn "model wiring: required descriptor ${agent_file} not found"
      return 1
    fi
    info "model wiring: ${agent_file} not found — skipping"
    return 0
  fi

  if [ ! -w "$agent_file" ]; then
    warn "model wiring: ${agent_file} is read-only — skipping"
    [ "$clobber" = "1" ] && return 1
    return 0
  fi

  case "$host" in
    claude-code)
      _model_wiring_patch_frontmatter "$agent_file" "$effective_model" "$clobber" || {
        warn "model wiring: patch failed for ${agent_file}"
        [ "$clobber" = "1" ] && return 1
        return 0
      }
      info "model wiring: $(basename "$agent_file") → $effective_model (host=$host)"
      ;;
    codex)
      _model_wiring_patch_toml "$agent_file" "$effective_model" "$clobber" || {
        warn "model wiring: patch failed for ${agent_file}"
        [ "$clobber" = "1" ] && return 1
        return 0
      }
      info "model wiring: $(basename "$agent_file") → $effective_model (host=$host)"
      ;;
    copilot|cursor|opencode)
      # Explicit no-op — these hosts have no standardized model: frontmatter field.
      info "model wiring: $host has no model frontmatter support — no-op"
      ;;
    *)
      info "model wiring: unknown host '$host' — skipping"
      ;;
  esac
}

# model_wiring_noop_host HOST
# Emit an info message and return 0. Used for hosts that are in wire but
# not in the profile's applies_to_hosts.
model_wiring_noop_host() {
  local host="$1"
  local profile="$2"
  info "model wiring: profile '$profile' does not apply to host '$host' — skipping model: wiring for this host"
}

# model_wiring_apply_for_member EIDOLON_ID [clobber]
# Patch every wired host agent file for the given Eidolon.
# Skips hosts where the active profile's applies_to_hosts doesn't include them.
model_wiring_apply_for_member() {
  local id="$1"
  local clobber="${2:-0}"

  # Determine wired hosts from CONSUMER_JSON / PROJECT_MANIFEST.
  local hosts_csv=""
  if [ -n "${CONSUMER_JSON:-}" ]; then
    hosts_csv="$(printf '%s' "$CONSUMER_JSON" \
      | jq -r '(.hosts.wire // []) | join(",")' 2>/dev/null || true)"
  fi
  if [ -z "$hosts_csv" ] && [ -f "${PROJECT_MANIFEST:-eidolons.yaml}" ]; then
    hosts_csv="$(yaml_to_json "${PROJECT_MANIFEST:-eidolons.yaml}" \
      | jq -r '(.hosts.wire // []) | join(",")' 2>/dev/null || true)"
  fi

  # Resolve and patch per host. This prevents the default Anthropic profile
  # from silently skipping Codex in a mixed-host project.
  local host wiring_rc=0 resolve_line effective_model tier profile source
  for host in $(printf '%s' "$hosts_csv" | tr ',' ' '); do
    [ -z "$host" ] && continue
    case "$host" in
      copilot|cursor|opencode)
        model_wiring_noop_host "$host" "n/a"
        continue
        ;;
      claude-code)
        local agent_file=".claude/agents/${id}.md"
        ;;
      codex)
        local agent_file=".codex/agents/${id}.toml"
        ;;
      *)
        info "model wiring: unknown host '$host' — skipping"
        continue
        ;;
    esac

    resolve_line="$(model_resolve_for_host "$id" "$host" 2>/dev/null || true)"
    if [ -z "$resolve_line" ]; then
      warn "model wiring: could not resolve model for '$id' on host '$host'"
      wiring_rc=1
      continue
    fi
    effective_model="$(printf '%s' "$resolve_line" | cut -f1)"
    tier="$(printf '%s' "$resolve_line" | cut -f2)"
    profile="$(printf '%s' "$resolve_line" | cut -f3)"
    source="$(printf '%s' "$resolve_line" | cut -f4)"

    # A concrete pin is intentionally host-specific. An explicitly selected
    # incompatible profile remains a supported partial-host configuration:
    # leave that descriptor alone, as the profile command must not fail merely
    # because another wired host has no mapping.
    if ! model_profile_applies_to_host "$profile" "$host"; then
      if [ "$source" != "pin" ]; then
        model_wiring_noop_host "$host" "$profile"
        continue
      fi
      info "model wiring: applying explicit model pin for '$id' on $host"
    fi

    model_wiring_patch_agent_file "$host" "$agent_file" "$effective_model" "$clobber" || wiring_rc=1
  done
  return "$wiring_rc"
}

# model_wiring_apply_all [clobber]
# Re-apply model wiring for all installed Eidolon members.
# Uses the member list from PROJECT_LOCK when present, else routing data.
model_wiring_apply_all() {
  local clobber="${1:-0}"

  local members_list=""
  if [ -f "${PROJECT_LOCK:-eidolons.lock}" ]; then
    members_list="$(yaml_to_json "${PROJECT_LOCK:-eidolons.lock}" \
      | jq -r '(.members // [])[].name' 2>/dev/null || true)"
  fi
  if [ -z "$members_list" ] && [ -n "${CONSUMER_JSON:-}" ]; then
    members_list="$(printf '%s' "$CONSUMER_JSON" \
      | jq -r '(.members // [])[].name' 2>/dev/null || true)"
  fi
  if [ -z "$members_list" ]; then
    members_list="$(model_list_ids 2>/dev/null || true)"
  fi

  local id wiring_rc=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    model_wiring_apply_for_member "$id" "$clobber" || wiring_rc=1
  done <<EOF
$members_list
EOF
  return "$wiring_rc"
}

# model_wiring_update_lock_for_member EIDOLON_ID
# Write the resolved model provenance into the member's lock entry.
# Uses jq to merge, writes YAML representation back to PROJECT_LOCK.
# This is best-effort (soft failure); lock update is non-critical.
model_wiring_update_lock_for_member() {
  local id="$1"

  local lock_file="${PROJECT_LOCK:-eidolons.lock}"
  if [ ! -f "$lock_file" ]; then
    return 0
  fi

  local resolve_line effective_model tier profile source
  resolve_line="$(model_resolve_for "$id" 2>/dev/null || true)"
  if [ -z "$resolve_line" ]; then
    return 0
  fi

  effective_model="$(printf '%s' "$resolve_line" | cut -f1)"
  tier="$(printf '%s' "$resolve_line" | cut -f2)"
  profile="$(printf '%s' "$resolve_line" | cut -f3)"
  source="$(printf '%s' "$resolve_line" | cut -f4)"

  # Read, patch, write lock using yq if available; fall back to grep-based
  # YAML append (simple but effective for the model block).
  # Strategy: use yq to update the member entry in-place.
  local tmplock
  tmplock="$(mktemp)"

  if command -v yq >/dev/null 2>&1; then
    # yq mikefarah syntax: update the model sub-object for this member.
    yq eval \
      "(.members[] | select(.name == \"${id}\")).model.effective_model = \"${effective_model}\" |
       (.members[] | select(.name == \"${id}\")).model.tier = \"${tier}\" |
       (.members[] | select(.name == \"${id}\")).model.profile = \"${profile}\" |
       (.members[] | select(.name == \"${id}\")).model.source = \"${source}\"" \
      "$lock_file" > "$tmplock" 2>/dev/null
    if [ $? -eq 0 ]; then
      chmod --reference="$lock_file" "$tmplock" 2>/dev/null || \
        chmod "$(stat -f '%A' "$lock_file" 2>/dev/null || echo 644)" "$tmplock" 2>/dev/null || true
      mv "$tmplock" "$lock_file"
      return 0
    fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$lock_file" "$tmplock" "$id" "$effective_model" "$tier" "$profile" "$source" <<'PY'
import sys
import yaml

source_path, output_path, member_id, model, tier, profile, provenance = sys.argv[1:]
with open(source_path, encoding="utf-8") as stream:
    document = yaml.safe_load(stream) or {}

found = False
for member in document.get("members", []):
    if member.get("name") == member_id:
        member["model"] = {
            "effective_model": model,
            "tier": tier,
            "profile": profile,
            "source": provenance,
        }
        found = True
        break

if not found:
    raise SystemExit(1)
with open(output_path, "w", encoding="utf-8") as stream:
    yaml.safe_dump(document, stream, sort_keys=False)
PY
    if [ $? -eq 0 ]; then
      chmod --reference="$lock_file" "$tmplock" 2>/dev/null || \
        chmod "$(stat -f '%A' "$lock_file" 2>/dev/null || echo 644)" "$tmplock" 2>/dev/null || true
      mv "$tmplock" "$lock_file"
      return 0
    fi
  fi

  # No safe write fallback: report failure so explicit commands cannot claim
  # success while leaving a stale lock. Passive sync deliberately softens this.
  rm -f "$tmplock"
  return 1
}

# model_wiring_update_lock_all
# Refresh model provenance for every member already present in the lock. This
# intentionally uses the lock's installed-member set, never the full routing
# roster, so profile/reset/sync cannot synthesize entries for absent Eidolons.
model_wiring_update_lock_all() {
  local lock_file="${PROJECT_LOCK:-eidolons.lock}"
  local members_list id update_rc=0
  [ -f "$lock_file" ] || return 0

  members_list="$(yaml_to_json "$lock_file" \
    | jq -r '(.members // [])[].name' 2>/dev/null || true)"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    model_wiring_update_lock_for_member "$id" || update_rc=1
  done <<EOF
$members_list
EOF
  return "$update_rc"
}
