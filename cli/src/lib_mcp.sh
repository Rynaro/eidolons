#!/usr/bin/env bash
# cli/src/lib_mcp.sh — shared helpers for eidolons mcp subcommands.
#
# SOURCE this file; do NOT execute it directly.
# Requires lib.sh to have been sourced first (for yaml_to_json, CACHE_DIR, etc.)
#
# Exported helpers:
#   mcp_catalogue_file          → path to roster/mcps.yaml
#   mcp_lockfile                → path to eidolons.mcp.lock (project-local)
#   mcp_catalogue_list_names    → one name per line
#   mcp_catalogue_get NAME      → JSON object for that MCP (or empty)
#   mcp_lock_read               → JSON string of the full lockfile (or '{}')
#   mcp_lock_entry NAME         → JSON for one lock entry (or empty)
#   mcp_lock_upsert NAME JSON   → atomically upsert one entry; sorts by name
#   mcp_lock_remove NAME        → remove one entry; re-write the lockfile
#   mcp_lock_write JSON_ARRAY   → write a full mcps[] array (sorted); preserves installed_at
#
# Driver protocol (kind-switch):
#   mcp_driver_oci_image_install   NAME VERSION [--force] [--project-root PATH]
#   mcp_driver_oci_image_refresh   NAME VERSION
#   mcp_driver_oci_image_uninstall NAME [--project-root PATH]
#   mcp_driver_oci_image_version   NAME  → installed version to stdout (or empty)
#   mcp_driver_oci_image_health    NAME  → status lines to stdout; exit 0 always
#
#   mcp_driver_binary_install      NAME VERSION [--force]
#   mcp_driver_binary_refresh      NAME VERSION
#   mcp_driver_binary_uninstall    NAME
#   mcp_driver_binary_version      NAME  → installed version to stdout (or empty)
#   mcp_driver_binary_health       NAME  → status lines to stdout; exit 0 always
#
# Bash 3.2 compatible — no declare -A, no ${var,,}/^^, no readarray/mapfile, no &>>.
# See CLAUDE.md §"Bash 3.2 compatibility".
# ═══════════════════════════════════════════════════════════════════════════

# Guard against double-source.
if [ -n "${_LIB_MCP_LOADED:-}" ]; then
  return 0
fi
_LIB_MCP_LOADED=1

# Source lib_mcp_atlas_aci.sh for the oci-image driver helpers.
# SELF_DIR may not be set here since this is sourced; derive from BASH_SOURCE.
_LIB_MCP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_LIB_MCP_DIR/lib_mcp_atlas_aci.sh"

# ─── Paths ────────────────────────────────────────────────────────────────────
mcp_catalogue_file() {
  echo "$NEXUS/roster/mcps.yaml"
}

mcp_lockfile() {
  echo "./eidolons.mcp.lock"
}

# ─── Catalogue helpers ────────────────────────────────────────────────────────

# mcp_catalogue_list_names — list catalogue MCP names, one per line.
mcp_catalogue_list_names() {
  local cat_file
  cat_file="$(mcp_catalogue_file)"
  if [ ! -f "$cat_file" ]; then
    return 0
  fi
  yaml_to_json "$cat_file" | jq -r '.mcps[].name'
}

# mcp_catalogue_get NAME — emit JSON for one catalogue entry (or empty on miss).
mcp_catalogue_get() {
  local name="$1"
  local cat_file
  cat_file="$(mcp_catalogue_file)"
  if [ ! -f "$cat_file" ]; then
    return 0
  fi
  yaml_to_json "$cat_file" \
    | jq --arg n "$name" '.mcps[] | select(.name == $n)'
}

# mcp_catalogue_get_field NAME JQPATH — emit one field from a catalogue entry.
mcp_catalogue_get_field() {
  local name="$1" field="$2"
  mcp_catalogue_get "$name" | jq -r "$field // empty"
}

# ─── Lockfile helpers ─────────────────────────────────────────────────────────

# mcp_lock_read — emit the full lockfile as JSON; '{}' when absent or unreadable.
mcp_lock_read() {
  local lf
  lf="$(mcp_lockfile)"
  if [ ! -f "$lf" ]; then
    echo '{}'
    return 0
  fi
  yaml_to_json "$lf" 2>/dev/null || echo '{}'
}

# mcp_lock_entry NAME — emit the JSON object for one installed MCP; empty on miss.
mcp_lock_entry() {
  local name="$1"
  mcp_lock_read \
    | jq --arg n "$name" '(.mcps // [])[] | select(.name == $n)'
}

# mcp_lock_carry_enforcement NAME ENTRY_JSON
# Merge any pre-existing ESL enforcement fields from the current lock entry for
# NAME onto a freshly-built ENTRY_JSON, emitting the augmented entry on stdout.
#
# THE TRAP (ESL escalation auto-flip, FORGE H5 / G-IDEMPOTENT): the OCI/binary
# install + refresh entry-builders rebuild the lock entry from the catalogue,
# and that rebuild does NOT know about the enforcement* fields written by
# 'eidolons mcp assess'. mcp_lock_upsert's no-op signature (kind/version/source/
# integrity/target/hosts_wired) also excludes them. So absent this carry-forward,
# a plain 'mcp install'/'mcp refresh' would silently DROP a recorded escalation.
# Install/refresh drivers MUST funnel their rebuilt entry through this helper
# before upsert so a re-install never clears a recorded enforcement.
#
# Carried fields (only when present on the old entry):
#   enforcement, enforcement_signals, enforcement_thresholds, enforcement_assessed_at
# If no old entry / no enforcement fields exist, ENTRY_JSON is emitted unchanged.
# Bash 3.2 safe (jq only).
mcp_lock_carry_enforcement() {
  local name="$1"
  local new_entry="$2"

  local old_entry
  old_entry="$(mcp_lock_entry "$name")"
  if [ -z "$old_entry" ]; then
    printf '%s' "$new_entry"
    return 0
  fi

  # Project just the enforcement* keys that exist on the old entry, then merge
  # them onto the new entry (new entry's own keys win for everything else).
  printf '%s' "$new_entry" \
    | jq --argjson old "$old_entry" '
        ($old
          | with_entries(select(.key
              | test("^enforcement($|_signals$|_thresholds$|_assessed_at$)")))) as $carry
        | . + $carry'
}

# mcp_lock_set_enforcement NAME MODE SIGNALS_JSON THRESHOLDS_JSON ASSESSED_AT
# Record the ESL enforcement decision onto NAME's existing lock entry. This is
# the nexus-side lock-write for 'eidolons mcp assess' (tonberry NEVER writes the
# lock — C-OWNER). It does a direct read-modify-write that DELIBERATELY bypasses
# mcp_lock_upsert: that helper's no-op signature excludes the enforcement* fields,
# so routing an enforcement-only change through it would falsely no-op and never
# persist the flip. Returns 1 (no write) when NAME is not installed.
# MODE: "advisory" | "block". SIGNALS_JSON / THRESHOLDS_JSON: compact JSON objects.
# Bash 3.2 safe (jq only).
mcp_lock_set_enforcement() {
  local name="$1"
  local mode="$2"
  # NOTE: do NOT default these with ${3:-{}} — bash closes the ${...} at the
  # first '}' and appends a literal '}', corrupting a non-empty JSON arg into
  # invalid JSON. Default in a separate statement instead.
  local signals_json="${3:-}"
  local thresholds_json="${4:-}"
  local assessed_at="${5:-}"
  [ -n "$signals_json" ] || signals_json='{}'
  [ -n "$thresholds_json" ] || thresholds_json='{}'

  local existing_arr old_entry
  existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"
  old_entry="$(printf '%s' "$existing_arr" \
    | jq --arg n "$name" '.[] | select(.name == $n)')"

  if [ -z "$old_entry" ]; then
    return 1
  fi

  local updated
  updated="$(printf '%s' "$old_entry" \
    | jq \
        --arg mode "$mode" \
        --argjson sig "$signals_json" \
        --argjson thr "$thresholds_json" \
        --arg at "$assessed_at" '
        .enforcement = $mode
        | .enforcement_signals = $sig
        | .enforcement_thresholds = $thr
        | (if $at == "" then . else .enforcement_assessed_at = $at end)')"

  local new_arr
  new_arr="$(printf '%s' "$existing_arr" \
    | jq --arg n "$name" 'map(select(.name != $n))')"
  new_arr="$(printf '%s' "$new_arr" \
    | jq --argjson e "$updated" '. + [$e]')"

  mcp_lock_write_from_array "$new_arr"
}

# mcp_driver_oci_image_assess NAME PROJECT_ROOT
# Run the MCP's one-shot `assess` op as a container CLI invocation and emit the
# raw JSON the tool prints on stdout. The lock-write is NOT done here — the
# caller (mcp_assess.sh) records the result so the nexus owns the lock-write.
#
# Invocation shape (read-only bind, no caps, no net): the project root is
# bind-mounted read-only at /workspace and the tool is asked to assess it.
# A FAKE override hook (EIDOLONS_MCP_ASSESS_CMD) lets tests inject a stub
# without a live docker pull; when set, it is run verbatim with PROJECT_ROOT
# as $1 and its stdout is used as the assess JSON.
#
# Returns:
#   0  + JSON on stdout when assess produced parseable JSON
#   3  when the image/digest is unresolved or the assess op could not run
# All diagnostics go to stderr.
mcp_driver_oci_image_assess() {
  local name="$1"
  local project_root="$2"

  # Test/CI override: a stub command that emits the assess JSON. Keeps bats
  # off a live docker pull (mirrors the fake-docker pattern but for the
  # one-shot assess path, which the generic fake-docker shim does not model).
  if [ -n "${EIDOLONS_MCP_ASSESS_CMD:-}" ]; then
    local _out
    if _out="$(eval "${EIDOLONS_MCP_ASSESS_CMD}" "$project_root" 2>/dev/null)"; then
      printf '%s' "$_out"
      return 0
    fi
    return 3
  fi

  # Resolve image + locked digest (prefer lock, fall back to catalogue pin).
  local source_image digest
  source_image="$(mcp_catalogue_get_field "$name" '.source.image')"
  digest="$(mcp_lock_entry "$name" | jq -r '.integrity.value // empty')"
  if [ -z "$digest" ]; then
    local pinned
    pinned="$(mcp_catalogue_get_field "$name" '.versions.pins.stable')"
    digest="$(mcp_catalogue_get "$name" \
      | jq -r --arg v "$pinned" '.versions.releases[$v].digest // empty')"
  fi

  if [ -z "$source_image" ] || [ -z "$digest" ]; then
    warn "${name}: cannot resolve image@digest for assess — skipping"
    return 3
  fi

  if ! atlas_aci_check_docker_cli; then return 3; fi
  if ! atlas_aci_check_docker_daemon; then return 3; fi

  local image_ref="${source_image}@${digest}"
  local _out
  if _out="$(docker run --rm \
      -v "${project_root}:/workspace:ro" \
      -w /workspace \
      --cap-drop ALL \
      --security-opt no-new-privileges \
      "$image_ref" assess /workspace 2>/dev/null)"; then
    printf '%s' "$_out"
    return 0
  fi
  warn "${name}: assess op did not run (image ${image_ref}); ESL assessment skipped"
  return 3
}

# _mcp_now — current UTC timestamp in RFC 3339 / ISO 8601 format.
# Bash 3.2 safe: uses 'date -u'.
_mcp_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# _mcp_cli_version — read from VERSION file or fallback.
_mcp_cli_version() {
  local _vf="$NEXUS/VERSION"
  if [ -f "$_vf" ]; then
    tr -d '[:space:]' < "$_vf"
  else
    echo "0.0.0-dev"
  fi
}

# mcp_lock_write_from_array JSON_ARRAY_STR — write the lockfile from a JSON array
# of mcp entries. Sorts entries by name. Preserves installed_at for entries whose
# other fields (kind, version, source, integrity, target) are unchanged.
#
# This is the canonical write path. All other writes funnel through here to
# guarantee sorted, deterministic output (F3.4 invariant).
mcp_lock_write_from_array() {
  local new_arr="$1"
  local lf generated cat_ver cli_ver

  lf="$(mcp_lockfile)"
  generated="$(_mcp_now)"
  cat_ver="$(yaml_to_json "$(mcp_catalogue_file)" 2>/dev/null \
    | jq -r '.catalogue_version // "1.0"' 2>/dev/null || echo '1.0')"
  cli_ver="$(_mcp_cli_version)"

  # Sort array by name (lexicographic) and write as YAML.
  # We write YAML manually because yq write is not a hard dep at runtime.
  local sorted_json
  sorted_json="$(printf '%s' "$new_arr" \
    | jq 'sort_by(.name) | map(.hosts_wired |= sort)')"

  # Build the lockfile in a tmpfile first, then atomically replace.
  local tmpfile
  tmpfile="$(mktemp)"

  {
    printf '# eidolons.mcp.lock — auto-generated by '\''eidolons mcp install/upgrade/sync'\''. Commit to VCS.\n'
    printf 'generated_at: "%s"\n' "$generated"
    printf 'eidolons_cli_version: "%s"\n' "$cli_ver"
    printf 'catalogue_version: "%s"\n' "$cat_ver"
    printf 'mcps:\n'

    printf '%s' "$sorted_json" | jq -c '.[]' | while IFS= read -r entry; do
      local ename ekind eversion
      ename="$(printf '%s' "$entry" | jq -r '.name')"
      ekind="$(printf '%s' "$entry" | jq -r '.kind')"
      eversion="$(printf '%s' "$entry" | jq -r '.version')"
      einstalled="$(printf '%s' "$entry" | jq -r '.installed_at')"
      etarget="$(printf '%s' "$entry" | jq -r '.target // ""')"
      eintegrity_algo="$(printf '%s' "$entry" | jq -r '.integrity.algo // "none"')"
      eintegrity_val="$(printf '%s' "$entry" | jq -r '.integrity.value // ""')"

      printf '  - name: %s\n' "$ename"
      printf '    kind: %s\n' "$ekind"
      printf '    version: "%s"\n' "$eversion"

      # source block (kind-specific)
      local esrc_image esrc_repo esrc_url
      esrc_image="$(printf '%s' "$entry" | jq -r '.source.image // ""')"
      esrc_repo="$(printf '%s' "$entry" | jq -r '.source.repo // ""')"
      esrc_url="$(printf '%s' "$entry" | jq -r '.source.url // ""')"
      printf '    source:\n'
      if [ -n "$esrc_image" ]; then
        printf '      image: "%s"\n' "$esrc_image"
      fi
      if [ -n "$esrc_repo" ]; then
        printf '      repo: "%s"\n' "$esrc_repo"
      fi
      if [ -n "$esrc_url" ]; then
        printf '      url: "%s"\n' "$esrc_url"
      fi

      # integrity block
      printf '    integrity:\n'
      printf '      algo: %s\n' "$eintegrity_algo"
      printf '      value: "%s"\n' "$eintegrity_val"

      # target
      if [ -n "$etarget" ]; then
        printf '    target: "%s"\n' "$etarget"
      fi

      # hosts_wired
      local ehosts
      ehosts="$(printf '%s' "$entry" | jq -r '(.hosts_wired // [])[]')"
      if [ -n "$ehosts" ]; then
        printf '    hosts_wired:\n'
        while IFS= read -r hw; do
          [ -n "$hw" ] && printf '      - "%s"\n' "$hw"
        done <<< "$ehosts"
      fi

      printf '    installed_at: "%s"\n' "$einstalled"

      # ESL enforcement block (only emitted when recorded by 'mcp assess').
      # The enforcement* fields are sticky, VCS-committed policy state; they are
      # NOT rebuilt by the catalogue-driven install path (see
      # mcp_lock_carry_enforcement) so the writer must serialize them verbatim
      # when present, or a re-write would silently drop a recorded escalation.
      local eenforce
      eenforce="$(printf '%s' "$entry" | jq -r '.enforcement // ""')"
      if [ -n "$eenforce" ]; then
        printf '    enforcement: "%s"\n' "$eenforce"
        # signals / thresholds are JSON objects → emit as compact JSON flow
        # mappings (valid YAML, round-trips cleanly through yaml_to_json).
        local esignals ethresholds eassessed
        esignals="$(printf '%s' "$entry" | jq -c '.enforcement_signals // empty')"
        ethresholds="$(printf '%s' "$entry" | jq -c '.enforcement_thresholds // empty')"
        eassessed="$(printf '%s' "$entry" | jq -r '.enforcement_assessed_at // ""')"
        if [ -n "$esignals" ]; then
          printf '    enforcement_signals: %s\n' "$esignals"
        fi
        if [ -n "$ethresholds" ]; then
          printf '    enforcement_thresholds: %s\n' "$ethresholds"
        fi
        if [ -n "$eassessed" ]; then
          printf '    enforcement_assessed_at: "%s"\n' "$eassessed"
        fi
      fi
    done
  } > "$tmpfile"

  mv "$tmpfile" "$lf"
}

# mcp_lock_upsert NAME ENTRY_JSON
# Insert or update one entry in the lockfile. Preserves installed_at if the
# entry is otherwise unchanged (idempotency: F3.4 invariant).
mcp_lock_upsert() {
  local name="$1"
  local new_entry="$2"

  local existing_arr
  existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"

  # Check if entry exists and if it's changed.
  local old_entry
  old_entry="$(printf '%s' "$existing_arr" \
    | jq --arg n "$name" '.[] | select(.name == $n)')"

  local new_entry_final
  if [ -n "$old_entry" ]; then
    # Compare fields that matter for idempotency (all except installed_at).
    # Canonicalize for an order-insensitive comparison: -S sorts object keys and
    # `hosts_wired|sort` normalizes the array — the lockfile writer sorts that
    # array on write, so a freshly-built (insertion-order) entry would otherwise
    # never match the re-read (sorted) one, defeating the no-op and re-stamping
    # installed_at on every install.
    local old_sig new_sig
    old_sig="$(printf '%s' "$old_entry" \
      | jq -cS '{kind,version,source,integrity,target,hosts_wired:(.hosts_wired // [] | sort)}')"
    new_sig="$(printf '%s' "$new_entry" \
      | jq -cS '{kind,version,source,integrity,target,hosts_wired:(.hosts_wired // [] | sort)}')"

    if [ "$old_sig" = "$new_sig" ]; then
      # No-op: preserve the original installed_at. Skip write.
      return 0
    fi

    # Changed: preserve name but update installed_at.
    new_entry_final="$new_entry"
  else
    new_entry_final="$new_entry"
  fi

  # Build the new array: remove the old entry (if any) and add the new one.
  local new_arr
  new_arr="$(printf '%s' "$existing_arr" \
    | jq --arg n "$name" 'map(select(.name != $n))')"
  new_arr="$(printf '%s' "$new_arr" \
    | jq --argjson e "$new_entry_final" '. + [$e]')"

  mcp_lock_write_from_array "$new_arr"
}

# mcp_lock_remove NAME — remove an entry from the lockfile.
mcp_lock_remove() {
  local name="$1"
  local lf
  lf="$(mcp_lockfile)"

  if [ ! -f "$lf" ]; then
    return 0
  fi

  local new_arr
  new_arr="$(mcp_lock_read | jq --arg n "$name" '(.mcps // []) | map(select(.name != $n))')"

  if [ "$(printf '%s' "$new_arr" | jq 'length')" -eq 0 ]; then
    # Last entry removed — delete the lockfile rather than leaving an empty one.
    rm -f "$lf"
    return 0
  fi

  mcp_lock_write_from_array "$new_arr"
}

# ─── oci-image driver ─────────────────────────────────────────────────────────

# mcp_driver_oci_image_pull NAME [--image-digest DIGEST] [--build-locally] [--git-ref REF]
# Generic, catalogue-pin-driven pull driver for any kind=oci-image MCP.
# Reuses atlas_aci_check_docker_cli/daemon/image from lib_mcp_atlas_aci.sh.
#
# INVARIANT (P0): the --build-locally branch is the air-gap escape hatch for
# buildable MCPs. It must never be removed. See .spectra/plans/
# 2026-06-02-mcp-image-management-spec.md §"P0 build-locally invariant".
#
# Exit codes:
#   0  image present (already, or after pull/build)
#   1  docker CLI/daemon failure, pull failure, or build failure
#   2  bad usage (unknown MCP, wrong kind, --build-locally on pull-only MCP,
#      --git-ref without --build-locally, bootstrap-placeholder digest)
mcp_driver_oci_image_pull() {
  local name="$1"
  shift

  local override_digest=""
  local build_locally=false
  local git_ref=""
  local digest_explicit=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --image-digest)
        [ -z "${2:-}" ] && { printf '%s\n' "--image-digest requires an argument" >&2; return 2; }
        override_digest="$2"
        digest_explicit=true
        shift 2
        ;;
      --build-locally)
        build_locally=true
        shift
        ;;
      --git-ref)
        [ -z "${2:-}" ] && { printf '%s\n' "--git-ref requires an argument" >&2; return 2; }
        git_ref="$2"
        shift 2
        ;;
      *)
        printf '%s\n' "mcp_driver_oci_image_pull: unknown option $1" >&2
        return 2
        ;;
    esac
  done

  # --git-ref without --build-locally is a usage error.
  if [ -n "$git_ref" ] && [ "$build_locally" = "false" ]; then
    printf '%s\n' "--git-ref requires --build-locally" >&2
    return 2
  fi

  # Validate name is in catalogue.
  local kind
  kind="$(mcp_catalogue_get_field "$name" '.kind')"
  if [ -z "$kind" ]; then
    printf '%s\n' "MCP '${name}' not found in catalogue. Try: eidolons mcp list" >&2
    return 2
  fi
  if [ "$kind" != "oci-image" ]; then
    printf '%s\n' "mcp pull only supports oci-image MCPs; '${name}' is kind=${kind}" >&2
    return 2
  fi

  # Resolve source.image and pinned digest.
  local source_image
  source_image="$(mcp_catalogue_get_field "$name" '.source.image')"

  local pinned_digest
  pinned_digest="$(mcp_catalogue_get "$name" \
    | jq -r '.versions.releases[.versions.pins.stable].digest // empty')"

  # Determine effective digest.
  local digest
  if [ "$digest_explicit" = "true" ]; then
    digest="$override_digest"
  else
    digest="${pinned_digest:-}"
  fi

  # Bootstrap-placeholder guard: refuse if digest is all-zeros and no override/build path.
  local _BOOTSTRAP_PLACEHOLDER="sha256:0000000000000000000000000000000000000000000000000000000000000000"
  if [ "$digest_explicit" = "false" ] && [ "$build_locally" = "false" ] && [ "$digest" = "$_BOOTSTRAP_PLACEHOLDER" ]; then
    printf '%s\n' \
      "The pinned digest for '${name}' is still the bootstrap placeholder." \
      "The first registry release has not landed yet (or the digest constant has not been updated). Either:" \
      "  1. Run 'eidolons mcp pull ${name} --build-locally' to build from source (air-gap escape hatch)." \
      "  2. Pass --image-digest sha256:<real-digest> to override." \
      "  3. Wait for the first published release and the corresponding digest-bump PR." \
      >&2
    return 2
  fi

  # --build-locally gate: requires source.build to be present in catalogue.
  if [ "$build_locally" = "true" ]; then
    local build_git_url
    build_git_url="$(mcp_catalogue_get_field "$name" '.source.build.git_url')"
    if [ -z "$build_git_url" ]; then
      printf '%s\n' \
        "'${name}' does not declare a buildable source; --build-locally is not supported." \
        "Pull from the registry or load a tarball." \
        >&2
      return 2
    fi

    local build_context build_default_ref
    build_context="$(mcp_catalogue_get_field "$name" '.source.build.context')"
    build_default_ref="$(mcp_catalogue_get_field "$name" '.source.build.default_ref')"
    local effective_git_ref="${git_ref:-${build_default_ref:-main}}"

    # Docker CLI + daemon checks.
    if ! atlas_aci_check_docker_cli; then return 1; fi
    if ! atlas_aci_check_docker_daemon; then return 1; fi

    local _build_tag="${source_image}:locally-built-$(date +%Y%m%d-%H%M%S)"
    local _build_url="${build_git_url}#${effective_git_ref}:${build_context}"

    say "Building locally: docker build -t ${_build_tag} ${_build_url}"
    if docker build -t "$_build_tag" "$_build_url" >&2; then
      ok "Local build complete. Image tagged: ${_build_tag}"
      warn "Note: locally-built images cannot match the upstream registry digest (${digest:-<unknown>})."
      warn "To use this image, pass --image-digest to override the pinned digest, or reference"
      warn "the locally-built tag directly in your docker run command: ${_build_tag}"
      return 0
    else
      warn "Local build failed."
      return 1
    fi
  fi

  # Registry pull path: need a digest.
  if [ -z "$digest" ]; then
    printf '%s\n' "No digest pinned for '${name}' in catalogue (no release for pins.stable)" >&2
    return 1
  fi

  local image_ref="${source_image}@${digest}"

  # Docker CLI + daemon checks.
  if ! atlas_aci_check_docker_cli; then return 1; fi
  if ! atlas_aci_check_docker_daemon; then return 1; fi

  # Idempotency: no-op if image already present.
  if atlas_aci_check_image "$image_ref" 2>/dev/null; then
    info "Image '${name}' already present at ${image_ref} — nothing to do"
    return 0
  fi

  # Pull from registry.
  say "Attempting: docker pull ${image_ref}"
  local _pull_tmpfile
  _pull_tmpfile="$(mktemp)"
  if docker pull "$image_ref" >"$_pull_tmpfile" 2>&1; then
    rm -f "$_pull_tmpfile"
    if atlas_aci_check_image "$image_ref" 2>/dev/null; then
      ok "Image '${name}' pulled and verified: ${image_ref}"
      return 0
    else
      die "docker pull reported success but the image is still not in the local store for '${image_ref}'. Try 'docker image inspect ${image_ref}' to diagnose."
    fi
  fi
  # Surface docker's actual error (last lines) — it carries the real cause
  # (e.g. "no matching manifest for linux/arm64" for a single-arch image), which
  # a generic "network/air-gap" message would otherwise hide.
  local _pull_err
  _pull_err="$(tail -n 3 "$_pull_tmpfile" 2>/dev/null)"
  rm -f "$_pull_tmpfile"

  # Pull failure: emit name-aware fallback block.
  # Include --build-locally alternative only when the MCP declares source.build.
  local has_build
  has_build="$(mcp_catalogue_get_field "$name" '.source.build.git_url')"

  printf '%s\n' \
    "'${name}' image could not be pulled from ${source_image}." \
    >&2
  if [ -n "$_pull_err" ]; then
    printf 'docker reported:\n  %s\n' "$_pull_err" >&2
  fi
  printf '%s\n' \
    "Likely cause: the image has no manifest for this host architecture ($(uname -m)), or a private/unauthenticated registry, network restriction, or air-gap." \
    "" \
    "To obtain the image, do ONE of:" \
    "" \
    >&2
  if [ -n "$has_build" ]; then
    printf '%s\n' \
      "  1. Build locally (recommended air-gap / offline escape hatch):" \
      "       eidolons mcp pull ${name} --build-locally [--git-ref REF]" \
      "" \
      "  2. Load from a tarball someone shared with you:" \
      "       docker load -i ${name}.tar" \
      "" \
      "  3. Pull from a private registry mirror (if your org publishes one):" \
      "       docker pull <registry>/${name}@${digest}" \
      "       docker tag <registry>/${name}@${digest} ${image_ref}" \
      "" \
      "Then re-run 'eidolons mcp pull ${name}' to verify." \
      >&2
  else
    printf '%s\n' \
      "  1. Load from a tarball someone shared with you:" \
      "       docker load -i ${name}.tar" \
      "" \
      "  2. Pull from a private registry mirror (if your org publishes one):" \
      "       docker pull <registry>/${name}@${digest}" \
      "       docker tag <registry>/${name}@${digest} ${image_ref}" \
      "" \
      "Then re-run 'eidolons mcp pull ${name}' to verify." \
      >&2
  fi

  return 1
}

# _mcp_host_is_wired HOST [PROJECT_ROOT]
# Returns 0 (true) if HOST is in hosts.wire of eidolons.yaml in PROJECT_ROOT.
# PROJECT_ROOT defaults to $(pwd). Bash 3.2 safe.
_mcp_host_is_wired() {
  local host="$1"
  local project_root="${2:-$(pwd)}"
  local manifest="${project_root}/eidolons.yaml"
  if [ ! -f "$manifest" ]; then
    return 1
  fi
  yaml_to_json "$manifest" \
    | jq -e --arg h "$host" '(.hosts.wire // []) | any(. == $h)' \
    >/dev/null 2>&1
}

# _mcp_merge_into_json_file RENDERED TARGET_FILE NAME [FORCE]
# Idempotent jq-merge of a rendered MCP JSON entry into a target JSON file.
# RENDERED is a JSON string (mcpServers top-level). TARGET_FILE is the path.
# NAME is for logging only. FORCE (optional, "true") bypasses the canonical
# no-op guard so the file is always re-written even when content is identical.
# Merge semantics:
#   - Missing file → write fresh file (normalised through jq for canonical form).
#   - Present valid JSON → jq-merge: existing mcpServers preserved + new entry added.
#       · canonical form unchanged AND not FORCE → skip the swap (no mtime/inode
#         churn → no harness MCP re-prompt).
#   - Present invalid JSON → warn + skip (soft-fail, no data loss).
# Bash 3.2 compatible.
_mcp_merge_into_json_file() {
  local rendered="$1"
  local target="$2"
  local name="$3"
  local force="${4:-false}"
  local tmp
  tmp="$(mktemp)"

  if [ ! -f "$target" ]; then
    if printf '%s\n' "$rendered" | jq '.' > "$tmp" 2>/dev/null; then
      mv "$tmp" "$target"
      ok "${name} entry written at ${target}"
    else
      rm -f "$tmp"
      warn "jq failed to normalise ${name} template — skipping ${target} write"
    fi
    return 0
  fi

  if ! jq empty "$target" 2>/dev/null; then
    rm -f "$tmp"
    warn "${target} is not valid JSON — skipping ${name} server registration (manual merge required)"
    return 0
  fi

  if printf '%s\n' "$rendered" \
    | jq -s '.[0].mcpServers as $new | (.[1] // {}) | .mcpServers = ((.mcpServers // {}) + $new)' \
        - "$target" \
    > "$tmp" 2>/dev/null; then
    # Canonical no-op guard (matches harness_install.sh's `jq -cS` pattern):
    # only swap the file in when the merge actually changed its canonical form.
    # A repeat merge of the same entry is byte-identical, so this skips the `mv`
    # entirely — the file keeps its inode AND its mtime (no churn → no harness
    # MCP re-prompt). This makes the write path idempotent even when the caller's
    # higher-level digest guard is bypassed (e.g. a concurrent re-render).
    # FORCE bypasses the guard so an explicit --force always re-writes.
    local _existing_canonical _merged_canonical
    _existing_canonical="$(jq -cS . "$target" 2>/dev/null || printf '')"
    _merged_canonical="$(jq -cS . "$tmp" 2>/dev/null || printf '')"
    if [ "$force" != "true" ] \
       && [ "$_existing_canonical" = "$_merged_canonical" ] \
       && [ -n "$_merged_canonical" ]; then
      rm -f "$tmp"
      info "${name} entry already present in ${target} (unchanged, no rewrite)"
    else
      mv "$tmp" "$target"
      ok "${name} entry merged into ${target}"
    fi
  else
    rm -f "$tmp"
    warn "jq merge failed for ${target} — skipping ${name} server registration"
  fi
}

# _mcp_merge_into_opencode_json RENDERED TARGET_FILE NAME
# Idempotent jq-merge of a rendered MCP JSON entry into opencode.json under the
# top-level "mcp" key. OpenCode's local-MCP shape differs from .mcp.json:
#   opencode.json: { "mcp": { "<name>": { "type": "local",
#                                         "command": ["<cmd>","<arg>",...],
#                                         "enabled": true } } }
# The RENDERED JSON uses the standard mcpServers shape; this function transforms it.
# All sibling keys (agent, permission, plugin, model, mcp.<other>) are preserved.
# Bash 3.2 compatible.
_mcp_merge_into_opencode_json() {
  local rendered="$1"
  local target="$2"
  local name="$3"
  local tmp
  tmp="$(mktemp)"

  # Build the transformed entry: command array = [.command] + (.args // []).
  local entry_json
  entry_json="$(printf '%s\n' "$rendered" \
    | jq -c --arg n "$name" \
        '.mcpServers[$n] as $s |
         {type:"local",
          command:([$s.command] + ($s.args // [])),
          enabled:true}' 2>/dev/null)" || {
    rm -f "$tmp"
    warn "_mcp_merge_into_opencode_json: jq failed to transform ${name} entry — skipping ${target} write"
    return 0
  }

  if [ ! -f "$target" ]; then
    # Fresh file — write the mcp object directly.
    if printf '%s\n' "{\"mcp\":{\"${name}\":${entry_json}}}" | jq '.' > "$tmp" 2>/dev/null; then
      mv "$tmp" "$target"
      ok "${name} entry written at ${target} (opencode)"
    else
      rm -f "$tmp"
      warn "jq failed to write ${target} (opencode) — skipping"
    fi
    return 0
  fi

  if ! jq empty "$target" 2>/dev/null; then
    rm -f "$tmp"
    warn "${target} is not valid JSON — skipping ${name} opencode registration (manual merge required)"
    return 0
  fi

  # Merge: preserve all sibling keys; update only .mcp[$name].
  if printf '%s\n' "$entry_json" \
    | jq -s --arg n "$name" \
        '.[1].mcp = ((.[1].mcp // {}) + {($n): .[0]}) | .[1]' \
        - "$target" \
    > "$tmp" 2>/dev/null; then
    mv "$tmp" "$target"
    ok "${name} entry merged into ${target} (opencode)"
  else
    rm -f "$tmp"
    warn "jq merge failed for ${target} (opencode) — skipping ${name} registration"
  fi
}

# _mcp_codex_config_toml_merge NAME PROJECT_ROOT RENDERED_JSON
# Writes/updates the [mcp_servers.<name>] table in .codex/config.toml using
# a marker-bounded managed-section rewrite (no TOML parser).
# Markers: # eidolon:mcp start / # eidolon:mcp end
# Rebuild-from-lock strategy: reads all installed MCPs from eidolons.mcp.lock
# and regenerates the full managed section (AC-R11-3, R11-6).
# Only called when codex is in hosts.wire.
# Bash 3.2 compatible.
_mcp_codex_config_toml_merge() {
  local name="$1"
  local project_root="$2"
  local rendered_json="$3"

  local toml_file="${project_root}/.codex/config.toml"
  mkdir -p "${project_root}/.codex"

  # Print [ASSUMPTION A3] info at install time.
  info "  [ASSUMPTION A3] .codex/config.toml project-scope mcp_servers assumed allowed; verify with 'eidolons doctor'"

  # Build the managed section content from ALL installed MCPs (rebuild-from-lock).
  # This handles multi-MCP coexistence and makes uninstall trivially correct.
  local lock_file="${project_root}/eidolons.mcp.lock"
  local section_body=""

  # First, build the entry for the current MCP being installed from rendered_json.
  # We build a map of name→rendered for all installed MCPs.
  # For the current install, use rendered_json directly.
  # For other already-installed MCPs, read from the lockfile target (.mcp.json)
  # and re-derive from the template. Since we only have rendered_json for the
  # current MCP, we read all installed names from the lock and derive their
  # TOML tables from the lockfile info (command + args).

  # Helper: build a single TOML table block for mcp_servers entry.
  # Uses jq to extract command/args/env from the rendered JSON.
  _build_toml_table_for_rendered() {
    local mcp_name="$1"
    local rjson="$2"
    local entry_json
    entry_json="$(printf '%s' "$rjson" | jq -c --arg n "$mcp_name" '.mcpServers[$n] // empty' 2>/dev/null)"
    if [ -z "$entry_json" ]; then
      return 0
    fi
    local cmd args_json
    cmd="$(printf '%s' "$entry_json" | jq -r '.command // ""' 2>/dev/null)"
    args_json="$(printf '%s' "$entry_json" | jq -c '.args // []' 2>/dev/null)"
    local env_json
    env_json="$(printf '%s' "$entry_json" | jq -c '.env // empty' 2>/dev/null)"

    printf '[mcp_servers.%s]\n' "$mcp_name"
    printf 'command = "%s"\n' "$cmd"
    printf 'args = %s\n' "$args_json"
    if [ -n "$env_json" ] && [ "$env_json" != "null" ]; then
      printf 'env = %s\n' "$env_json"
    fi
    printf '\n'
  }

  # Build table for the current MCP (always use freshly rendered JSON).
  local current_table
  current_table="$(_build_toml_table_for_rendered "$name" "$rendered_json")"

  # Build tables for all other already-installed MCPs from lockfile.
  local other_tables=""
  if [ -f "$lock_file" ]; then
    local other_names
    other_names="$(yaml_to_json "$lock_file" 2>/dev/null \
      | jq -r --arg n "$name" '.mcps // [] | map(select(.name != $n)) | .[].name' 2>/dev/null || true)"
    for _oname in $other_names; do
      [ -z "$_oname" ] && continue
      # Read the other MCP's .mcp.json entry from the project's .mcp.json.
      local other_mcp_json="${project_root}/.mcp.json"
      if [ -f "$other_mcp_json" ]; then
        local other_entry_json
        other_entry_json="$(jq -c --arg n "$_oname" '.mcpServers[$n] // empty' "$other_mcp_json" 2>/dev/null || true)"
        if [ -n "$other_entry_json" ] && [ "$other_entry_json" != "null" ]; then
          # Wrap as mcpServers object for the helper.
          local other_rendered
          other_rendered="$(jq -n --arg n "$_oname" --argjson e "$other_entry_json" '{mcpServers: {($n): $e}}')"
          local other_table
          other_table="$(_build_toml_table_for_rendered "$_oname" "$other_rendered")"
          if [ -n "$other_table" ]; then
            other_tables="${other_tables}${other_table}"
          fi
        fi
      fi
    done
  fi

  section_body="${current_table}${other_tables}"

  # Strip trailing newline from section body for clean marker placement.
  local new_section
  new_section="# eidolon:mcp start
${section_body}# eidolon:mcp end"

  if [ ! -f "$toml_file" ]; then
    printf '%s\n' "$new_section" > "$toml_file"
    ok "${name} .codex/config.toml managed section written"
    return 0
  fi

  # File exists: check for existing markers.
  if grep -qF "# eidolon:mcp start" "$toml_file" 2>/dev/null; then
    # Rebuild-from-markers: replace the marker-bounded region with new_section.
    local tmp_toml
    tmp_toml="$(mktemp)"
    awk '
      /^# eidolon:mcp start/ { skip=1; next }
      /^# eidolon:mcp end/ { skip=0; next }
      !skip { print }
    ' "$toml_file" > "$tmp_toml"

    # Build final file: user content + new section.
    # Determine if user content has trailing newline.
    local user_content
    user_content="$(cat "$tmp_toml")"
    rm -f "$tmp_toml"

    local final_content
    if [ -n "$user_content" ]; then
      final_content="${user_content}
${new_section}"
    else
      final_content="$new_section"
    fi

    # Idempotency check.
    local existing_content
    existing_content="$(cat "$toml_file")"
    if [ "$existing_content" = "$final_content" ]; then
      info ".codex/config.toml managed section unchanged (no-op)"
    else
      printf '%s\n' "$final_content" > "$toml_file"
      ok "${name} .codex/config.toml managed section updated"
    fi
  else
    # No markers yet: append the new section.
    printf '\n%s\n' "$new_section" >> "$toml_file"
    ok "${name} .codex/config.toml managed section appended"
  fi
}

# _mcp_oci_mcpjson_digest NAME PROJECT_ROOT
# Emit the OCI digest currently baked into PROJECT_ROOT/.mcp.json for NAME's
# server entry (the `@sha256:...` suffix on the image arg), or empty if the
# entry / file / digest is absent. Used by the no-op idempotency guard so a
# repeat install with an unchanged digest does not re-write .mcp.json at all
# (which would churn the file's mtime and re-trigger the host harness's
# per-project MCP file-change detection — the "MCP disabled after sync" symptom).
# Bash 3.2 safe (jq + sed only; no associative arrays / ${var,,}).
_mcp_oci_mcpjson_digest() {
  local name="$1"
  local project_root="$2"
  local mcpjson="${project_root}/.mcp.json"

  [ -f "$mcpjson" ] || return 0
  jq empty "$mcpjson" 2>/dev/null || return 0

  # Pull every arg of this server entry, find the image ref, emit its @digest.
  jq -r --arg n "$name" \
    '(.mcpServers[$n].args // [])[]
      | select(type == "string" and test("@sha256:"))' \
    "$mcpjson" 2>/dev/null \
    | sed -n 's|.*@\(sha256:[0-9a-f]\{1,\}\).*|\1|p' \
    | head -1
}

# _mcp_oci_render_and_merge NAME PROJECT_ROOT DIGEST TEMPLATE_PATH [FORCE]
# Internal helper: renders a template with placeholder substitution and
# jq-merges the resulting server entry into PROJECT_ROOT/.mcp.json.
# FORCE (optional, "true") forces a re-write even when content is unchanged.
#
# Placeholder substitution (all safe for bash 3.2; uses sed, no eval):
#   __HOME__          → $HOME
#   __PROJECT_ROOT__  → resolved absolute project root path
#   __PROJECT_SLUG__  → slug derived from basename($PROJECT_ROOT)
#   __IMAGE_DIGEST__  → OCI digest from catalogue (e.g. sha256:...)
#
# Merge semantics (idempotent by construction — see INV-1 in _mcp_binary_merge_mcp_json):
#   - Missing .mcp.json → write fresh file (normalised through jq for canonical form).
#   - Present valid JSON → jq-merge new server entry; all sibling keys preserved.
#   - Present invalid JSON → warn + skip (soft-fail; no data loss).
#
# All log output goes to stderr per the lib.sh invariant; only paths are emitted
# to stdout by callers that capture them.
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile, no &>>.
_mcp_oci_render_and_merge() {
  local name="$1"
  local project_root="$2"
  local digest="$3"
  local tmpl_rel="$4"
  local force="${5:-false}"

  # Resolve template path: tmpl_rel is relative to NEXUS root (as stored in catalogue).
  local tmpl
  tmpl="${NEXUS}/${tmpl_rel}"
  if [ ! -f "$tmpl" ]; then
    warn "_mcp_oci_render_and_merge: template not found at ${tmpl} — skipping .mcp.json write"
    return 0
  fi

  # Compute project slug: lowercase, replace non-alnum with '-', collapse + trim edges.
  # 'tr' is bash 3.2 safe (no ${var,,}).
  local _basename _project_slug
  _basename="$(basename "$project_root")"
  _project_slug="$(printf '%s' "$_basename" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' \
    | sed -e 's|^-||' -e 's|-$||')"

  # Render: substitute all known placeholders via sed (| delimiter — safe for paths).
  # Order: longest/most-specific first to avoid partial matches.
  local rendered
  rendered="$(sed \
    -e "s|__PROJECT_ROOT__|${project_root}|g" \
    -e "s|__PROJECT_SLUG__|${_project_slug}|g" \
    -e "s|__IMAGE_DIGEST__|${digest}|g" \
    -e "s|__HOME__|${HOME}|g" \
    "$tmpl")"

  # Write .mcp.json (primary target).
  _mcp_merge_into_json_file "$rendered" "${project_root}/.mcp.json" "${name}" "$force"

  # Write .cursor/mcp.json when cursor is in hosts.wire (R10).
  if _mcp_host_is_wired "cursor" "$project_root"; then
    mkdir -p "${project_root}/.cursor"
    _mcp_merge_into_json_file "$rendered" "${project_root}/.cursor/mcp.json" "${name} .cursor" "$force"
  fi

  # Write .codex/config.toml managed section when codex is in hosts.wire (R11).
  if _mcp_host_is_wired "codex" "$project_root"; then
    _mcp_codex_config_toml_merge "$name" "$project_root" "$rendered"
  fi

  # Write opencode.json under .mcp key when opencode is in hosts.wire (R16).
  if _mcp_host_is_wired "opencode" "$project_root"; then
    _mcp_merge_into_opencode_json "$rendered" "${project_root}/opencode.json" "${name}"
  fi
}

# mcp_driver_oci_image_install NAME VERSION [--force] [--project-root PATH]
# Generalized OCI image install driver. Supports all oci-image catalogue entries
# (atlas-aci, crystalium, and any future additions).
#
# For atlas-aci: delegates to mcp_atlas_aci.sh for Docker pre-flight + memex
# directory setup. mcp_atlas_aci.sh now performs a jq-merge (not sed-overwrite),
# so sibling entries in .mcp.json (e.g. crystalium) are always preserved.
# For all other oci-image MCPs (e.g. crystalium): runs Docker pre-flight directly
# via lib_mcp_atlas_aci.sh helpers, then calls _mcp_oci_render_and_merge.
#
# Placeholder substitution (bash 3.2 safe, sed-only, no eval):
#   __HOME__          → $HOME
#   __PROJECT_ROOT__  → absolute project root
#   __PROJECT_SLUG__  → slug from basename(project root)
#   __IMAGE_DIGEST__  → OCI digest from catalogue
#
# Idempotency: re-running install with the same version/digest produces an
# identical .mcp.json (jq-merge of the same entry = no diff).
mcp_driver_oci_image_install() {
  local name="$1"
  local version="$2"
  shift 2

  local force=false
  local project_root=""
  local no_pull=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)         force=true; shift ;;
      --project-root)  project_root="$2"; shift 2 ;;
      --no-pull)       no_pull=true; shift ;;
      *)               warn "mcp_driver_oci_image_install: unknown option $1"; shift ;;
    esac
  done

  project_root="${project_root:-$(pwd)}"

  # Resolve to absolute path.
  project_root="$(cd "$project_root" 2>/dev/null && pwd)" \
    || { warn "mcp_driver_oci_image_install: project root does not exist: ${project_root}"; return 1; }

  # Get the digest for the requested version from catalogue.
  local digest
  digest="$(mcp_catalogue_get "$name" \
    | jq -r --arg v "$version" '.versions.releases[$v].digest // empty')"

  # Get the install template path from catalogue.
  local tmpl_rel
  tmpl_rel="$(mcp_catalogue_get_field "$name" '.install.template')"

  if [ "$name" = "atlas-aci" ]; then
    # atlas-aci: auto-pull support (OQ-2) — when image is missing and --no-pull is
    # not set, auto-pull before delegating to mcp_atlas_aci.sh.
    # mcp_atlas_aci.sh handles Docker pre-flight, memex dir creation, bootstrap-
    # placeholder guard, slug computation, and jq-merge into .mcp.json.
    if [ "$no_pull" = "false" ] && [ -n "$digest" ]; then
      local aci_img
      aci_img="$(mcp_catalogue_get_field "$name" '.source.image')"
      if ! atlas_aci_check_docker_cli 2>/dev/null; then
        return 1
      fi
      if ! atlas_aci_check_docker_daemon 2>/dev/null; then
        return 1
      fi
      if ! atlas_aci_check_image "${aci_img}@${digest}" 2>/dev/null; then
        mcp_driver_oci_image_pull "$name" --image-digest "$digest" || return $?
      fi
    fi
    local aci_args="--project-root ${project_root}"
    if [ "$force" = "true" ]; then
      aci_args="${aci_args} --force"
    fi
    if [ -n "$digest" ]; then
      aci_args="${aci_args} --image-digest ${digest}"
    fi
    # shellcheck disable=SC2086
    bash "$_LIB_MCP_DIR/mcp_atlas_aci.sh" $aci_args || return $?
  else
    # Generic oci-image path (e.g. crystalium): Docker pre-flight + render + merge.
    # Auto-pull fires BEFORE .mcp.json wiring (ordering invariant).
    if ! atlas_aci_check_docker_cli; then return 1; fi
    if ! atlas_aci_check_docker_daemon; then return 1; fi
    if [ -n "$digest" ]; then
      local source_image_check
      source_image_check="$(mcp_catalogue_get_field "$name" '.source.image')"
      if ! atlas_aci_check_image "${source_image_check}@${digest}" 2>/dev/null; then
        if [ "$no_pull" = "true" ]; then
          # --no-pull: preserve existing abort behavior with name-aware message.
          printf '%s\n' \
            "Image for ${name} is not present on this host: ${source_image_check}@${digest}." \
            "Pull it with 'eidolons mcp pull ${name}' and re-run 'eidolons mcp install ${name}'." \
            >&2
          return 1
        fi
        # Auto-pull the image.
        mcp_driver_oci_image_pull "$name" --image-digest "$digest" || return $?
      fi
    fi
    # Idempotency early-exit (no-op guard): if not --force, the .mcp.json entry
    # already exists AND its baked-in digest matches the freshly-resolved digest,
    # skip the render+merge entirely so .mcp.json is not re-written (no mtime
    # churn → no harness MCP re-prompt). A genuine digest bump, --force, a
    # missing .mcp.json, or a missing digest all fall through to re-render.
    if [ "$force" = "false" ] && [ -n "$digest" ]; then
      local existing_mcpjson_digest
      existing_mcpjson_digest="$(_mcp_oci_mcpjson_digest "$name" "$project_root")"
      if [ -n "$existing_mcpjson_digest" ] && [ "$existing_mcpjson_digest" = "$digest" ]; then
        info "${name}: .mcp.json digest unchanged (${digest}) — unchanged, skipping render"
      else
        _mcp_oci_render_and_merge "$name" "$project_root" "${digest:-}" "$tmpl_rel" "$force"
      fi
    else
      _mcp_oci_render_and_merge "$name" "$project_root" "${digest:-}" "$tmpl_rel" "$force"
    fi
  fi

  # Build and upsert lockfile entry.
  local source_image_lf installed_at
  source_image_lf="$(mcp_catalogue_get_field "$name" '.source.image')"
  installed_at="$(_mcp_now)"

  # Derive hosts_wired from actual writes (R10 AC-4): always .mcp.json;
  # append .cursor/mcp.json iff cursor wired; append .codex/config.toml iff codex wired;
  # append opencode.json iff opencode wired (R16 AC-4).
  # Drop the aspirational .github/agents/* entry (no writer exists — it was a lie).
  local _hw_json
  _hw_json='[".mcp.json"]'
  if _mcp_host_is_wired "cursor" "$project_root"; then
    _hw_json="$(printf '%s' "$_hw_json" | jq '. + [".cursor/mcp.json"]')"
  fi
  if _mcp_host_is_wired "codex" "$project_root"; then
    _hw_json="$(printf '%s' "$_hw_json" | jq '. + [".codex/config.toml"]')"
  fi
  if _mcp_host_is_wired "opencode" "$project_root"; then
    _hw_json="$(printf '%s' "$_hw_json" | jq '. + ["opencode.json"]')"
  fi
  # Sort for canonical order.
  _hw_json="$(printf '%s' "$_hw_json" | jq 'sort')"

  local entry
  entry="$(jq -n \
    --arg nm "$name" \
    --arg kd "oci-image" \
    --arg ver "$version" \
    --arg img "$source_image_lf" \
    --arg algo "oci-digest" \
    --arg digv "${digest:-}" \
    --arg tgt ".mcp.json" \
    --argjson hw "$_hw_json" \
    --arg iat "$installed_at" \
    '{
      name: $nm,
      kind: $kd,
      version: $ver,
      source: {image: $img},
      integrity: {algo: $algo, value: $digv},
      target: $tgt,
      hosts_wired: $hw,
      installed_at: $iat
    }')"

  # ESL enforcement carry-forward (G-IDEMPOTENT): preserve any recorded
  # enforcement* fields the catalogue-driven rebuild above does not know about,
  # so a plain re-install never clears a recorded escalation.
  entry="$(mcp_lock_carry_enforcement "$name" "$entry")"

  mcp_lock_upsert "$name" "$entry"
}

# mcp_driver_oci_image_refresh NAME VERSION
# Re-pull the image at the locked digest. Does NOT regenerate .mcp.json.
# Updates installed_at in the lockfile.
mcp_driver_oci_image_refresh() {
  local name="$1"
  local version="$2"

  # Get locked digest (prefer lockfile, fallback to catalogue).
  local digest
  digest="$(mcp_lock_entry "$name" | jq -r '.integrity.value // empty')"
  if [ -z "$digest" ]; then
    digest="$(mcp_catalogue_get "$name" \
      | jq -r --arg v "$version" '.versions.releases[$v].digest // empty')"
  fi

  local source_image
  source_image="$(mcp_catalogue_get_field "$name" '.source.image')"
  local full_ref="${source_image}@${digest}"

  # Run docker pre-flight.
  if ! atlas_aci_check_docker_cli; then return 1; fi
  if ! atlas_aci_check_docker_daemon; then return 1; fi

  say "Refreshing image: $full_ref"
  if ! atlas_aci_check_image "$full_ref" 2>/dev/null; then
    # Route through the generic pull driver (MCP-agnostic — fixes crystalium refresh).
    mcp_driver_oci_image_pull "$name" --image-digest "$digest" || return $?
  else
    info "Image already present, confirming..."
  fi

  # Update installed_at to mark refresh.
  local old_entry installed_at
  old_entry="$(mcp_lock_entry "$name")"
  installed_at="$(_mcp_now)"
  if [ -n "$old_entry" ]; then
    local updated
    updated="$(printf '%s' "$old_entry" \
      | jq --arg iat "$installed_at" '.installed_at = $iat')"
    # Force-update the lockfile even if no other field changed.
    local existing_arr new_arr
    existing_arr="$(mcp_lock_read | jq '(.mcps // [])')"
    new_arr="$(printf '%s' "$existing_arr" \
      | jq --arg n "$name" 'map(select(.name != $n))')"
    new_arr="$(printf '%s' "$new_arr" \
      | jq --argjson e "$updated" '. + [$e]')"
    mcp_lock_write_from_array "$new_arr"
  fi

  ok "${name} refresh complete"
}

# mcp_driver_oci_image_uninstall NAME [--project-root PATH]
# Remove marker-bounded sections for atlas-aci from host files. Does NOT
# delete the Docker image or .atlas/memex/codegraph.db.
mcp_driver_oci_image_uninstall() {
  local name="$1"
  shift

  local project_root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-root)  project_root="$2"; shift 2 ;;
      *)               shift ;;
    esac
  done

  project_root="${project_root:-$(pwd)}"

  # Check if installed at all.
  local entry
  entry="$(mcp_lock_entry "$name")"
  if [ -z "$entry" ]; then
    info "${name} not installed (nothing to remove)"
    return 0
  fi

  # Remove the marker key from .mcp.json (if it exists and is valid JSON).
  local mcp_json="${project_root}/.mcp.json"
  if [ -f "$mcp_json" ] && command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    if jq 'del(.mcpServers["'"${name}"'"])' "$mcp_json" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$mcp_json"
      info "Removed ${name} from .mcp.json"
    else
      rm -f "$tmp"
      warn "Could not parse .mcp.json — manual cleanup may be required"
    fi
    # Remove the _eidolon sentinel key if atlas-aci was the last entry.
    local remaining
    remaining="$(jq '.mcpServers | length' "$mcp_json" 2>/dev/null || echo 0)"
    if [ "$remaining" -eq 0 ]; then
      info ".mcp.json now has no MCP servers; leaving the empty shell"
    fi
  fi

  # Remove from .cursor/mcp.json if present.
  local cursor_mcp="${project_root}/.cursor/mcp.json"
  if [ -f "$cursor_mcp" ] && command -v jq >/dev/null 2>&1; then
    local tmp2
    tmp2="$(mktemp)"
    if jq 'del(.mcpServers["'"${name}"'"])' "$cursor_mcp" > "$tmp2" 2>/dev/null; then
      mv "$tmp2" "$cursor_mcp"
      info "Removed ${name} from .cursor/mcp.json"
    else
      rm -f "$tmp2"
    fi
  fi

  # Remove from opencode.json if present (R16 AC-5: delete only .mcp[$name]).
  local opencode_json="${project_root}/opencode.json"
  if [ -f "$opencode_json" ] && command -v jq >/dev/null 2>&1; then
    local tmp_oc
    tmp_oc="$(mktemp)"
    if jq 'del(.mcp["'"${name}"'"])' "$opencode_json" > "$tmp_oc" 2>/dev/null; then
      mv "$tmp_oc" "$opencode_json"
      info "Removed ${name} from opencode.json"
    else
      rm -f "$tmp_oc"
    fi
  fi

  # Remove lockfile entry.
  mcp_lock_remove "$name"
  ok "${name} uninstalled"
}

# mcp_driver_oci_image_version NAME → installed version (from lockfile) to stdout.
mcp_driver_oci_image_version() {
  local name="$1"
  mcp_lock_entry "$name" | jq -r '.version // empty'
}

# _mcp_driver_oci_uid_bind_probes NAME → UID/GID and bind-path probe lines to stdout.
#
# Reads .mcp.json in CWD. If absent, malformed, or missing the atlas-aci key,
# this function silently no-ops (zero output, exit 0). This preserves the
# D-T3.6/D-T3.7/D-T3.8 semantics.
#
# When the atlas-aci entry is found, three probe classes run:
#
#   mcp_uid_pin  ok    — -u UID:GID present and matches id -u:id -g
#   mcp_uid_pin  err   — -u UID:GID present but mismatches current user
#   mcp_uid_pin  warn  — no -u flag at all (includes the 'eidolons atlas aci wire' hint)
#
#   mcp_bind_path_exists     err — a -v host:container arg's host path does not exist
#   mcp_bind_path_readable   err — host path exists but is not readable
#
# Output format per probe: "<name>  <probe>  ok|err|warn  [reason]"
# Callers that increment error counters should filter on status word "err";
# callers that surface warnings should filter on "warn".
#
# Bash 3.2 compatible: no declare -A, no ${var,,}, no readarray/mapfile.
_mcp_driver_oci_uid_bind_probes() {
  local name="$1"

  # Require jq; if absent caller can't parse JSON anyway.
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi

  # .mcp.json must exist in CWD.
  if [ ! -f ".mcp.json" ]; then
    return 0
  fi

  # Check that atlas-aci key exists and has an args array.
  # jq -e exits non-zero when the value is null/false/missing.
  if ! jq -e '.mcpServers["atlas-aci"].args | arrays' .mcp.json >/dev/null 2>&1; then
    # Malformed JSON, no mcpServers, or no atlas-aci key — silent skip.
    return 0
  fi

  # ── probe: mcp_uid_pin ──────────────────────────────────────────────────
  # Find the value following "-u" in the args array.
  # Strategy: to_entries on the args array, select entries whose value is "-u",
  # then return $arr at (key+1) — that's the UID:GID value.
  local _pinned_uid_gid
  _pinned_uid_gid="$(jq -r '
    .mcpServers["atlas-aci"].args as $arr
    | $arr | to_entries
    | map(select(.value == "-u") | .key + 1)
    | map($arr[.])
    | .[0] // empty
  ' .mcp.json 2>/dev/null || true)"

  local _cur_uid _cur_gid _cur_uidgid
  _cur_uid="$(id -u)"
  _cur_gid="$(id -g)"
  _cur_uidgid="${_cur_uid}:${_cur_gid}"

  if [ -z "$_pinned_uid_gid" ]; then
    # No -u flag at all.
    printf '%s  mcp_uid_pin       warn      no -u UID:GID pin in .mcp.json — re-run '"'"'eidolons atlas aci wire'"'"' to rebuild with current UID:GID\n' "$name"
  elif [ "$_pinned_uid_gid" = "$_cur_uidgid" ]; then
    printf '%s  mcp_uid_pin       ok\n' "$name"
  else
    printf '%s  mcp_uid_pin       err       pins --user %s but current user is %s\n' \
      "$name" "$_pinned_uid_gid" "$_cur_uidgid"
  fi

  # ── probe: mcp_bind_path_exists / mcp_bind_path_readable ───────────────
  # Collect host paths from all -v <host>:<container> args.
  # Strategy: to_entries on args, select entries whose value is "-v",
  # return $arr at (key+1) — that's the host:container bind spec.
  local _bind_specs _bspec _host_path
  _bind_specs="$(jq -r '
    .mcpServers["atlas-aci"].args as $arr
    | $arr | to_entries
    | map(select(.value == "-v") | .key + 1)
    | map($arr[.])
    | .[]
  ' .mcp.json 2>/dev/null || true)"

  if [ -n "$_bind_specs" ]; then
    while IFS= read -r _bspec; do
      [ -n "$_bspec" ] || continue
      # host_path is everything before the first colon.
      _host_path="${_bspec%%:*}"
      [ -n "$_host_path" ] || continue

      if [ ! -e "$_host_path" ]; then
        printf '%s  mcp_bind_path_exists      err   %s does not exist\n' \
          "$name" "$_host_path"
      elif [ ! -r "$_host_path" ]; then
        printf '%s  mcp_bind_path_readable    err   %s is not readable by current user\n' \
          "$name" "$_host_path"
      fi
    done <<< "$_bind_specs"
  fi

  return 0
}

# mcp_driver_oci_image_health NAME → probe status lines to stdout; exit 0 always.
# Output format per line: "<name>  <probe>  ok|degraded|missing  [reason]"
# New UID/GID and bind-path probes (mcp_uid_pin, mcp_bind_path_exists,
# mcp_bind_path_readable) use err|warn|ok status words and run when .mcp.json
# exists with an atlas-aci key. They fire after image_local and before
# registry_reachable. Callers should scan per-probe lines for err/warn.
mcp_driver_oci_image_health() {
  local name="$1"
  local overall="ok"

  # probe: docker_cli
  local cli_rc=0
  atlas_aci_check_docker_cli 2>/dev/null || cli_rc=$?
  if [ "$cli_rc" -eq 0 ]; then
    printf '%s  docker_cli       ok\n' "$name"
  else
    printf '%s  docker_cli       missing   docker not on PATH\n' "$name"
    overall="missing"
  fi

  # probe: docker_daemon (only if cli present)
  if [ "$cli_rc" -eq 0 ]; then
    local daemon_rc=0
    atlas_aci_check_docker_daemon 2>/dev/null || daemon_rc=$?
    if [ "$daemon_rc" -eq 0 ]; then
      printf '%s  docker_daemon    ok\n' "$name"
    else
      printf '%s  docker_daemon    degraded  docker daemon unreachable\n' "$name"
      overall="degraded"
    fi

    # probe: image_local (only if daemon reachable)
    if [ "$daemon_rc" -eq 0 ]; then
      local digest source_image locked_entry
      locked_entry="$(mcp_lock_entry "$name")"
      digest="$(printf '%s' "$locked_entry" | jq -r '.integrity.value // empty')"
      source_image="$(printf '%s' "$locked_entry" | jq -r '.source.image // empty')"

      if [ -n "$source_image" ] && [ -n "$digest" ]; then
        local full_ref="${source_image}@${digest}"
        local image_rc=0
        atlas_aci_check_image "$full_ref" 2>/dev/null || image_rc=$?
        if [ "$image_rc" -eq 0 ]; then
          printf '%s  image_local      ok    %s\n' "$name" "${digest:0:20}..."
        else
          printf '%s  image_local      missing   run eidolons mcp refresh %s\n' "$name" "$name"
          overall="degraded"
        fi
      else
        printf '%s  image_local      missing   no lockfile entry\n' "$name"
        overall="missing"
      fi

      # probes: mcp_uid_pin, mcp_bind_path_exists, mcp_bind_path_readable
      # Reads .mcp.json in CWD; silently no-ops if absent/malformed/no atlas-aci key.
      # The probe lines use err|warn|ok status words (separate from ok|degraded|missing).
      _mcp_driver_oci_uid_bind_probes "$name"

      # probe: registry_reachable (soft; if full_ref available)
      if [ -n "${full_ref:-}" ]; then
        local reg_rc=0
        atlas_aci_check_registry_reachable "$full_ref" 2>/dev/null || reg_rc=$?
        if [ "$reg_rc" -eq 0 ]; then
          printf '%s  registry_reachable  ok\n' "$name"
        else
          printf '%s  registry_reachable  degraded  ghcr.io unreachable or digest yanked\n' "$name"
          # registry unreachable is not fatal for OVERALL if image is local
        fi
      fi
    fi
  fi

  printf '%s  OVERALL          %s\n' "$name" "$overall"
}

# ─── binary driver ────────────────────────────────────────────────────────────
# These wrap the logic from cli/src/harness.sh without duplicating it.
# harness.sh functions (_harness_install, _harness_up, _harness_uninstall,
# _harness_verify) are still invoked from harness.sh for the legacy path.
# The driver functions here call the relevant harness.sh sub-functions by
# sourcing harness.sh and invoking them.

# _mcp_source_harness — source harness.sh once (idempotent).
_mcp_source_harness() {
  if [ -n "${_MCP_HARNESS_LOADED:-}" ]; then
    return 0
  fi
  _MCP_HARNESS_LOADED=1
  # shellcheck disable=SC1091
  . "$_LIB_MCP_DIR/harness.sh" || true
}

# _mcp_binary_merge_mcp_json NAME BIN PROJECT_ROOT
# Merge (not overwrite) the junction MCP server entry into PROJECT_ROOT/.mcp.json.
#
# Behaviour:
#   - If .mcp.json is absent: write a fresh file with the junction entry only.
#   - If .mcp.json is present and valid JSON: jq-merge so that .mcpServers["junction"]
#     is added/updated while ALL sibling keys (atlas-aci, etc.) are preserved.
#   - If .mcp.json is present but NOT valid JSON: warn and do not write (soft-fail).
# Binary-present gate (INV-7): callers MUST only call this when $BIN is non-empty and
# the binary exists. The die at lib_mcp.sh:743-745 enforces this before reaching here.
_mcp_binary_merge_mcp_json() {
  local name="$1"
  local bin="$2"
  local project_root="$3"

  # Locate and render the template.
  local tmpl rendered
  tmpl="${_LIB_MCP_DIR}/../templates/mcp/junction.mcp.json.tmpl"
  if [ ! -f "$tmpl" ]; then
    warn "_mcp_binary_merge_mcp_json: template not found at ${tmpl} — skipping .mcp.json write"
    return 0
  fi

  # Render: substitute __JUNCTION_BIN__ with the resolved binary path (INV-3: sed, no eval).
  rendered="$(sed -e "s|__JUNCTION_BIN__|${bin}|g" "$tmpl")"

  # Write .mcp.json (primary target).
  _mcp_merge_into_json_file "$rendered" "${project_root}/.mcp.json" "${name}"

  # Write .cursor/mcp.json when cursor is in hosts.wire (R10).
  if _mcp_host_is_wired "cursor" "$project_root"; then
    mkdir -p "${project_root}/.cursor"
    _mcp_merge_into_json_file "$rendered" "${project_root}/.cursor/mcp.json" "${name} .cursor"
  fi

  # Write .codex/config.toml managed section when codex is in hosts.wire (R11).
  if _mcp_host_is_wired "codex" "$project_root"; then
    _mcp_codex_config_toml_merge "$name" "$project_root" "$rendered"
  fi

  # Write opencode.json under .mcp key when opencode is in hosts.wire (R16).
  if _mcp_host_is_wired "opencode" "$project_root"; then
    _mcp_merge_into_opencode_json "$rendered" "${project_root}/opencode.json" "${name}"
  fi
}

# mcp_driver_binary_install NAME VERSION [--force]
# Installs junction via its install.sh. Idempotent.
#
# TODO(FU1): promote algo: none → algo: sha256 once Junction install.sh publishes
# a binary digest. Track upstream at: https://github.com/Rynaro/Junction — when
# install.sh exposes a stable SHA-256 of the downloaded binary, wire it here and
# update the lockfile schema to require algo: sha256 for kind=binary in nexus v1.4.
mcp_driver_binary_install() {
  local name="$1"
  local version="$2"
  shift 2

  local force=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=true; shift ;;
      *)       shift ;;
    esac
  done

  # Strip version prefix if present (e.g. "0.2.0" or "v0.2.0").
  local ver="${version#v}"

  local cache_dir="${CACHE_DIR}/junction@${ver}"

  # Idempotency gate: if already installed and not --force, skip.
  if [ -d "$cache_dir" ]; then
    local existing_bin
    existing_bin=""
    if [ -x "$cache_dir/junction" ]; then
      existing_bin="$cache_dir/junction"
    elif [ -x "$cache_dir/bin/junction" ]; then
      existing_bin="$cache_dir/bin/junction"
    fi
    if [ -n "$existing_bin" ] && [ "$force" = "false" ]; then
      ok "junction@${ver} already installed at $existing_bin (use --force to reinstall)"
      # Still upsert lockfile in case it's missing.
      _mcp_binary_upsert_lock "$name" "$ver" "$cache_dir"
      # Idempotent .mcp.json merge: a project fresh-cloned may have the binary
      # cached but no .mcp.json yet — register the bus entry (merge is safe to
      # call repeatedly; jq merge is order-stable and single-entry).
      _mcp_binary_merge_mcp_json "$name" "$existing_bin" "$(pwd)"
      return 0
    fi
    if [ "$force" = "true" ]; then
      rm -rf "$cache_dir"
    fi
  fi

  mkdir -p "$cache_dir"

  local install_url
  install_url="$(mcp_catalogue_get_field "$name" '.source.install_url')"
  if [ -z "$install_url" ]; then
    install_url="https://raw.githubusercontent.com/Rynaro/Junction/main/install.sh"
  fi

  say "Installing junction@${ver} into ${cache_dir}"

  if command -v curl >/dev/null 2>&1; then
    JUNCTION_INSTALL_DIR="$cache_dir" JUNCTION_VERSION="$ver" \
      bash <(curl -fsSL "$install_url") >/dev/null 2>&1 \
      || { rm -rf "$cache_dir"; die "Failed to install junction@${ver}."; }
  elif command -v wget >/dev/null 2>&1; then
    JUNCTION_INSTALL_DIR="$cache_dir" JUNCTION_VERSION="$ver" \
      bash <(wget -qO- "$install_url") >/dev/null 2>&1 \
      || { rm -rf "$cache_dir"; die "Failed to install junction@${ver}."; }
  else
    die "Neither curl nor wget found. Install one to bootstrap junction."
  fi

  local bin
  bin=""
  if [ -x "$cache_dir/junction" ]; then
    bin="$cache_dir/junction"
  elif [ -x "$cache_dir/bin/junction" ]; then
    bin="$cache_dir/bin/junction"
  fi
  if [ -z "$bin" ]; then
    rm -rf "$cache_dir"
    die "Junction install completed but binary not found in $cache_dir"
  fi

  ok "junction@${ver} installed at $bin"

  _mcp_binary_upsert_lock "$name" "$ver" "$cache_dir"
  # Register the junction MCP server entry in the project .mcp.json (merge,
  # not overwrite — atlas-aci and any sibling keys are preserved). Only called
  # when $bin is confirmed present (binary-present gate INV-7 satisfied above).
  _mcp_binary_merge_mcp_json "$name" "$bin" "$(pwd)"
}

# _mcp_binary_upsert_lock NAME VERSION CACHE_DIR — write/update the lockfile
# entry for a binary MCP. Shared by install and refresh.
_mcp_binary_upsert_lock() {
  local name="$1" version="$2" cache_dir="$3"

  local source_repo installed_at target
  source_repo="$(mcp_catalogue_get_field "$name" '.source.repo')"
  installed_at="$(_mcp_now)"

  # Locate binary for target path.
  target=""
  if [ -x "$cache_dir/junction" ]; then
    target="$cache_dir/junction"
  elif [ -x "$cache_dir/bin/junction" ]; then
    target="$cache_dir/bin/junction"
  else
    target="$cache_dir"
  fi

  # Derive hosts_wired from actual writes (R10 AC-4): always .mcp.json;
  # append .cursor/mcp.json iff cursor wired; append .codex/config.toml iff codex wired;
  # append opencode.json iff opencode wired (R16 AC-4).
  local _hw_json
  _hw_json='[".mcp.json"]'
  if _mcp_host_is_wired "cursor"; then
    _hw_json="$(printf '%s' "$_hw_json" | jq '. + [".cursor/mcp.json"]')"
  fi
  if _mcp_host_is_wired "codex"; then
    _hw_json="$(printf '%s' "$_hw_json" | jq '. + [".codex/config.toml"]')"
  fi
  if _mcp_host_is_wired "opencode"; then
    _hw_json="$(printf '%s' "$_hw_json" | jq '. + ["opencode.json"]')"
  fi
  _hw_json="$(printf '%s' "$_hw_json" | jq 'sort')"

  local entry
  entry="$(jq -n \
    --arg nm "$name" \
    --arg kd "binary" \
    --arg ver "$version" \
    --arg repo "$source_repo" \
    --arg tgt "$target" \
    --argjson hw "$_hw_json" \
    --arg iat "$installed_at" \
    '{
      name: $nm,
      kind: $kd,
      version: $ver,
      source: {repo: $repo},
      integrity: {algo: "none", value: ""},
      target: $tgt,
      hosts_wired: $hw,
      installed_at: $iat
    }')"

  # ESL enforcement carry-forward (G-IDEMPOTENT): preserve any recorded
  # enforcement* fields the catalogue-driven rebuild above does not know about.
  entry="$(mcp_lock_carry_enforcement "$name" "$entry")"

  mcp_lock_upsert "$name" "$entry"
}

# mcp_driver_binary_refresh NAME VERSION
# Re-fetch the junction binary at the locked version. Updates installed_at.
mcp_driver_binary_refresh() {
  local name="$1"
  local version="${2:-}"

  # Prefer lockfile version if not specified.
  if [ -z "$version" ]; then
    version="$(mcp_lock_entry "$name" | jq -r '.version // empty')"
  fi
  if [ -z "$version" ]; then
    version="$(mcp_catalogue_get_field "$name" '.versions.pins.stable')"
  fi

  local ver="${version#v}"
  local cache_dir="${CACHE_DIR}/junction@${ver}"

  # Remove existing cache dir to force re-fetch.
  if [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
  fi

  mcp_driver_binary_install "$name" "$ver" --force
}

# mcp_driver_binary_uninstall NAME
# Remove all junction@* cache dirs and the .eidolons/harness/ marker dir.
mcp_driver_binary_uninstall() {
  local name="$1"

  local entry
  entry="$(mcp_lock_entry "$name")"
  if [ -z "$entry" ]; then
    info "${name} not installed (nothing to remove)"
    return 0
  fi

  local dir
  for dir in "${CACHE_DIR}/junction@"*/; do
    if [ -d "$dir" ]; then
      rm -rf "${dir%/}"
      info "Removed cache: ${dir%/}"
    fi
  done

  if [ -d "./.eidolons/harness" ]; then
    rm -rf "./.eidolons/harness"
    info "Removed marker: .eidolons/harness"
  fi

  # Remove the junction server entry from .mcp.json (symmetric with install).
  local mcp_json="./.mcp.json"
  if [ -f "$mcp_json" ] && command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    if jq 'del(.mcpServers["'"${name}"'"])' "$mcp_json" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$mcp_json"
      info "Removed ${name} from .mcp.json"
    else
      rm -f "$tmp"
      warn "Could not parse .mcp.json — manual cleanup may be required"
    fi
  fi

  # Remove from .cursor/mcp.json if present (R10 AC-5, binary symmetric).
  local cursor_mcp="./.cursor/mcp.json"
  if [ -f "$cursor_mcp" ] && command -v jq >/dev/null 2>&1; then
    local tmp2
    tmp2="$(mktemp)"
    if jq 'del(.mcpServers["'"${name}"'"])' "$cursor_mcp" > "$tmp2" 2>/dev/null; then
      mv "$tmp2" "$cursor_mcp"
      info "Removed ${name} from .cursor/mcp.json"
    else
      rm -f "$tmp2"
    fi
  fi

  # Remove from opencode.json if present (R16 AC-5: delete only .mcp[$name]).
  local opencode_json="./opencode.json"
  if [ -f "$opencode_json" ] && command -v jq >/dev/null 2>&1; then
    local tmp_oc2
    tmp_oc2="$(mktemp)"
    if jq 'del(.mcp["'"${name}"'"])' "$opencode_json" > "$tmp_oc2" 2>/dev/null; then
      mv "$tmp_oc2" "$opencode_json"
      info "Removed ${name} from opencode.json"
    else
      rm -f "$tmp_oc2"
    fi
  fi

  # Remove from .codex/config.toml managed section if present (R11 AC-6).
  local codex_toml="./.codex/config.toml"
  if [ -f "$codex_toml" ] && grep -qF "# eidolon:mcp start" "$codex_toml" 2>/dev/null; then
    # Rebuild managed section without this MCP: read remaining MCPs from lockfile
    # (before the remove), strip our entry from the mcp.json and re-run the helper.
    # Simpler: strip the entire managed section and re-write without the removed MCP.
    # Since we're about to remove the lockfile entry, rebuild from current lock minus this name.
    local tmp_toml
    tmp_toml="$(mktemp)"
    awk '
      /^# eidolon:mcp start/ { skip=1; next }
      /^# eidolon:mcp end/ { skip=0; next }
      !skip { print }
    ' "$codex_toml" > "$tmp_toml"
    local user_content
    user_content="$(cat "$tmp_toml")"
    rm -f "$tmp_toml"
    # Check if any other MCPs remain in lockfile (excluding current name).
    local remaining_mcps
    remaining_mcps="$(yaml_to_json "$(mcp_lockfile)" 2>/dev/null \
      | jq -r --arg n "$name" '.mcps // [] | map(select(.name != $n)) | .[].name' 2>/dev/null || true)"
    if [ -z "$remaining_mcps" ]; then
      # No other MCPs: just strip the managed section.
      if [ -n "$user_content" ]; then
        printf '%s\n' "$user_content" > "$codex_toml"
      else
        rm -f "$codex_toml"
      fi
      info "Removed ${name} managed section from .codex/config.toml"
    else
      # Other MCPs remain: rebuild section from their .mcp.json entries.
      local other_section=""
      for _oname in $remaining_mcps; do
        [ -z "$_oname" ] && continue
        local other_entry
        other_entry="$(jq -c --arg n "$_oname" '.mcpServers[$n] // empty' "./.mcp.json" 2>/dev/null || true)"
        if [ -n "$other_entry" ] && [ "$other_entry" != "null" ]; then
          local other_rendered
          other_rendered="$(jq -n --arg n "$_oname" --argjson e "$other_entry" '{mcpServers: {($n): $e}}')"
          local cmd args_json env_json
          cmd="$(printf '%s' "$other_entry" | jq -r '.command // ""')"
          args_json="$(printf '%s' "$other_entry" | jq -c '.args // []')"
          env_json="$(printf '%s' "$other_entry" | jq -c '.env // empty' 2>/dev/null || true)"
          other_section="${other_section}[mcp_servers.${_oname}]
command = \"${cmd}\"
args = ${args_json}
"
          if [ -n "$env_json" ] && [ "$env_json" != "null" ]; then
            other_section="${other_section}env = ${env_json}
"
          fi
          other_section="${other_section}
"
        fi
      done
      local new_section
      new_section="# eidolon:mcp start
${other_section}# eidolon:mcp end"
      if [ -n "$user_content" ]; then
        printf '%s\n%s\n' "$user_content" "$new_section" > "$codex_toml"
      else
        printf '%s\n' "$new_section" > "$codex_toml"
      fi
      info "Updated .codex/config.toml managed section (removed ${name})"
    fi
  fi

  mcp_lock_remove "$name"
  ok "${name} uninstalled"
}

# mcp_driver_binary_version NAME → installed version to stdout (or empty).
mcp_driver_binary_version() {
  local name="$1"
  # Prefer lockfile.
  local ver
  ver="$(mcp_lock_entry "$name" | jq -r '.version // empty')"
  if [ -n "$ver" ]; then
    printf '%s\n' "$ver"
    return 0
  fi
  # Fallback: scan cache dir.
  local dir
  for dir in "${CACHE_DIR}/junction@"*/; do
    if [ -d "$dir" ]; then
      local base
      base="$(basename "${dir%/}")"
      printf '%s\n' "${base#junction@}"
      return 0
    fi
  done
}

# mcp_driver_binary_health NAME → probe status lines to stdout; exit 0 always.
mcp_driver_binary_health() {
  local name="$1"
  local overall="ok"

  # probe: binary_present
  local any_dir bin
  any_dir=""
  bin=""
  local d
  for d in "${CACHE_DIR}/junction@"*/; do
    if [ -d "$d" ]; then
      any_dir="${d%/}"
      break
    fi
  done

  if [ -z "$any_dir" ]; then
    printf '%s  binary_present   missing   run: eidolons mcp install %s\n' "$name" "$name"
    overall="missing"
  else
    if [ -x "$any_dir/junction" ]; then
      bin="$any_dir/junction"
    elif [ -x "$any_dir/bin/junction" ]; then
      bin="$any_dir/bin/junction"
    fi
    if [ -z "$bin" ]; then
      printf '%s  binary_present   missing   cache dir found but binary absent\n' "$name"
      overall="missing"
    else
      printf '%s  binary_present   ok    %s\n' "$name" "$bin"

      # probe: binary_version
      local bver=""
      bver="$("$bin" --version 2>/dev/null | head -1 || true)"
      if [ -n "$bver" ]; then
        printf '%s  binary_version   ok    %s\n' "$name" "$bver"
      else
        printf '%s  binary_version   degraded  could not get version\n' "$name"
        overall="degraded"
      fi
    fi
  fi

  # probe: docker_daemon_optional (soft warn, non-fatal)
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      printf '%s  docker_daemon_optional  ok\n' "$name"
    else
      printf '%s  docker_daemon_optional  degraded  Docker daemon unreachable (junction --no-container still works)\n' "$name"
      # Not fatal for OVERALL
    fi
  else
    printf '%s  docker_daemon_optional  degraded  Docker not found (junction --no-container still works)\n' "$name"
  fi

  printf '%s  OVERALL          %s\n' "$name" "$overall"
}

# mcp_assert_version_published NAME VER
# Asserts that VER exists as a published release in the catalogue for NAME.
# Calls die() (exit 1) with an actionable message listing available versions
# when the release record is absent.
# Bash 3.2 safe: uses a plain for/while loop; no readarray/mapfile.
mcp_assert_version_published() {
  local name="$1"
  local ver="$2"

  # Check the release record exists (kind-agnostic: works for oci-image + binary).
  local release_check
  release_check="$(mcp_catalogue_get "$name" \
    | jq -r --arg v "$ver" '.versions.releases[$v] // empty')"

  if [ -z "$release_check" ]; then
    # Build a newline-separated list of published versions for the error message.
    local published_list
    published_list="$(mcp_catalogue_get_field "$name" '.versions.releases | keys[]' 2>/dev/null || true)"

    local published_display=""
    if [ -n "$published_list" ]; then
      local v
      while IFS= read -r v; do
        [ -z "$v" ] && continue
        published_display="${published_display}${published_display:+, }${v}"
      done <<< "$published_list"
    fi

    if [ -n "$published_display" ]; then
      die "${name}@${ver} is not published in the roster catalogue. Publish it via a roster bump first. Published versions: ${published_display}"
    else
      die "${name}@${ver} is not published in the roster catalogue. Publish it via a roster bump first."
    fi
  fi
}

# ─── Generic dispatch helpers ─────────────────────────────────────────────────

# mcp_dispatch_driver KIND HOOK NAME [...]
# Calls mcp_driver_<kind>_<hook> with trailing args.
# KIND: oci-image | binary | script
# HOOK: install | refresh | uninstall | version | health
mcp_dispatch_driver() {
  local kind="$1" hook="$2" name="$3"
  shift 3

  # Convert kind to a valid bash function name component (replace '-' with '_').
  local kind_fn
  kind_fn="$(printf '%s' "$kind" | tr '-' '_')"

  local fn="mcp_driver_${kind_fn}_${hook}"
  if command -v "$fn" >/dev/null 2>&1 || type "$fn" >/dev/null 2>&1; then
    "$fn" "$name" "$@"
  else
    die "No driver for kind='$kind' hook='$hook'"
  fi
}

# mcp_resolve_kind NAME → emit kind from catalogue (or die).
mcp_resolve_kind() {
  local name="$1"
  local k
  k="$(mcp_catalogue_get_field "$name" '.kind')"
  if [ -z "$k" ]; then
    die "MCP '${name}' not found in catalogue. Try: eidolons mcp list"
  fi
  printf '%s\n' "$k"
}

# mcp_resolve_version NAME [requested_version]
# Resolve to a concrete version. If requested is empty or "@latest", use
# catalogue pins.stable. If in form "name@version", strip the name prefix.
mcp_resolve_version() {
  local name="$1"
  local requested="${2:-}"

  # Strip "name@version" form.
  case "$requested" in
    *@*)
      requested="${requested#*@}"
      ;;
  esac

  if [ -z "$requested" ] || [ "$requested" = "latest" ]; then
    mcp_catalogue_get_field "$name" '.versions.pins.stable'
  else
    printf '%s\n' "$requested"
  fi
}
