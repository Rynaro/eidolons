#!/usr/bin/env bash
# eidolons release — one-touch Eidolon release + Roster Intake orchestration.
#
# Usage:
#   eidolons release <eidolon> <version> [OPTIONS]
#
# Flags:
#   --check              Validate plan only; no dispatches.
#   --resume             Skip Release dispatch when tag already exists.
#   --force              Allow version equal to or less than roster latest.
#   --auto-merge         Hint to Roster Intake: enable auto-merge on the PR.
#   --yes, -y            Skip interactive confirmation prompt.
#   --non-interactive    Fail on prompts (requires --yes for mutating runs).
#   --release-timeout=N  Seconds to wait for tag (default 600).
#   --intake-timeout=N   Seconds to wait for Roster Intake PR (default 300).
#   -h, --help           Show this help.
#
# Exit codes:
#   0  success
#   1  generic failure
#   2  usage / validation error
#   4  network / timeout
#   5  dispatch failure (gh API error)
#
# Spec: .spectra/plans/eidolons-update-flow-2026-05-05.md (Bucket A, S1-S5, S10-S12)
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib.sh"

# ─── Argument parsing (bash 3.2 safe — case-statement, no getopt) ─────────
EIDOLON_ARG=""
VERSION_ARG=""
CHECK=false
RESUME=false
FORCE=false
AUTO_MERGE=false
YES=false
NON_INTERACTIVE=false
RELEASE_TIMEOUT=600
INTAKE_TIMEOUT=300

usage() {
  cat <<'HELP'
eidolons release — one-touch Eidolon release + Roster Intake orchestration

Usage: eidolons release <eidolon> <version> [OPTIONS]

Options:
  --check              Validate plan only; no workflows dispatched.
  --resume             Skip Release dispatch when tag already exists upstream.
  --force              Allow version <= roster.versions.latest (overrides guard).
  --auto-merge         Pass auto-merge hint to Roster Intake workflow.
  --yes, -y            Skip confirmation prompt.
  --non-interactive    Fail on prompts (requires --yes for mutating runs).
  --release-timeout=N  Seconds to wait for the Release workflow tag (default 600).
  --intake-timeout=N   Seconds to wait for Roster Intake PR to open (default 300).
  -h, --help           Show this help.

Exit codes:
  0  success
  1  generic failure
  2  usage / validation error
  4  network / timeout
  5  dispatch failure (gh API error)

This command requires maintainer access (repo + workflow scope) to both
Rynaro/<EIDOLON> and Rynaro/eidolons. Run 'gh auth refresh -h github.com -s repo'
if authentication fails.
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)           CHECK=true;          shift ;;
    --resume)          RESUME=true;         shift ;;
    --force)           FORCE=true;          shift ;;
    --auto-merge)      AUTO_MERGE=true;     shift ;;
    --yes|-y)          YES=true;            shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --release-timeout=*)
      RELEASE_TIMEOUT="${1#*=}"
      shift ;;
    --intake-timeout=*)
      INTAKE_TIMEOUT="${1#*=}"
      shift ;;
    -h|--help)
      usage; exit 0 ;;
    --*)
      echo "Unknown option: $1" >&2
      echo "Run: eidolons release --help" >&2
      exit 2 ;;
    *)
      if [[ -z "$EIDOLON_ARG" ]]; then
        EIDOLON_ARG="$1"
      elif [[ -z "$VERSION_ARG" ]]; then
        VERSION_ARG="$1"
      else
        echo "Unexpected argument: $1" >&2
        echo "Usage: eidolons release <eidolon> <version> [OPTIONS]" >&2
        exit 2
      fi
      shift ;;
  esac
done

# ─── Required positionals ─────────────────────────────────────────────────
if [[ -z "$EIDOLON_ARG" || -z "$VERSION_ARG" ]]; then
  echo "Usage: eidolons release <eidolon> <version> [OPTIONS]" >&2
  echo "" >&2
  echo "Missing: $([ -z "$EIDOLON_ARG" ] && echo "eidolon name"; [ -z "$VERSION_ARG" ] && echo "version")" >&2
  exit 2
fi

# Mutating, non-interactive runs without --yes refuse to proceed.
if [[ "$CHECK" != true && "$NON_INTERACTIVE" == true && "$YES" != true ]]; then
  echo "--non-interactive mutating run requires --yes (or use --check)." >&2
  exit 2
fi

# ─── Validation block ─────────────────────────────────────────────────────

say "Validating release plan"

# V1: SemVer regex
if [[ ! "$VERSION_ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "✗ Version '$VERSION_ARG' is not valid SemVer (expected X.Y.Z)." >&2
  exit 2
fi

# V2: gh CLI version check (need >= 2.20.0 for --auto merge support).
_gh_ver="$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"
_gh_major="${_gh_ver%%.*}"
_gh_rest="${_gh_ver#*.}"
_gh_minor="${_gh_rest%%.*}"
_gh_req_major=2
_gh_req_minor=20
_gh_ok=false
if [[ "$_gh_major" -gt "$_gh_req_major" ]]; then
  _gh_ok=true
elif [[ "$_gh_major" -eq "$_gh_req_major" && "$_gh_minor" -ge "$_gh_req_minor" ]]; then
  _gh_ok=true
fi
if [[ "$_gh_ok" != "true" ]]; then
  echo "✗ gh CLI version ${_gh_ver} is below the required 2.20.0 (needed for --auto merge support)." >&2
  echo "  Upgrade with: gh upgrade" >&2
  exit 2
fi

# V3: Roster lookup — resolve canonical name and source repo.
_roster_entry=""
if ! _roster_entry="$(roster_get "$EIDOLON_ARG" 2>/dev/null)"; then
  echo "✗ '$EIDOLON_ARG' not found in roster. Try: eidolons list" >&2
  exit 2
fi
EIDOLON_NAME="$(echo "$_roster_entry" | jq -r '.name')"
EIDOLON_DISPLAY="$(echo "$_roster_entry" | jq -r '.display_name // .name')"
EIDOLON_REPO="$(echo "$_roster_entry" | jq -r '.source.repo')"
ROSTER_LATEST="$(echo "$_roster_entry" | jq -r '.versions.latest // "0.0.0"')"

info "· roster: $EIDOLON_NAME ${ROSTER_LATEST}  →  ${VERSION_ARG}  ($(echo "$_roster_entry" | jq -r '.status // "unknown"'))"

# V4: Version-precedence check (S3, S4).
if [[ "$VERSION_ARG" == "$ROSTER_LATEST" && "$RESUME" == "false" && "$FORCE" == "false" ]]; then
  echo "✗ Version ${VERSION_ARG} already in roster (current latest is ${ROSTER_LATEST})." >&2
  echo "  If this is a re-run of an interrupted release, pass --resume." >&2
  echo "  If you intended a different version, check: gh release list -R ${EIDOLON_REPO}" >&2
  exit 2
fi
if semver_lt "$VERSION_ARG" "$ROSTER_LATEST" && [[ "$FORCE" == "false" ]]; then
  echo "✗ Refusing to release ${VERSION_ARG}: would downgrade roster latest from ${ROSTER_LATEST}." >&2
  echo "  Roster downgrades require --force. Recommended path: open a manual roster PR" >&2
  echo "  that pins versions.latest to the older release (no Release run needed — the tag" >&2
  echo "  already exists upstream). See docs/cli-reference.md#release." >&2
  exit 2
fi

# V5: gh auth check for both repos.
info "· gh auth: checking Rynaro/eidolons and ${EIDOLON_REPO}"
if ! release_check_gh_auth "Rynaro/eidolons" "repo"; then
  exit 2
fi
if ! release_check_gh_auth "${EIDOLON_REPO}" "repo"; then
  exit 2
fi
info "· gh auth: ok for ${EIDOLON_REPO}, Rynaro/eidolons"

# V6: Workflow file existence check.
RELEASE_WF="release.yml"
if ! gh api "repos/${EIDOLON_REPO}/contents/.github/workflows/${RELEASE_WF}" --silent 2>/dev/null; then
  echo "✗ .github/workflows/${RELEASE_WF} not found in ${EIDOLON_REPO}." >&2
  echo "  Cannot dispatch Release ${EIDOLON_DISPLAY} without the workflow file." >&2
  exit 2
fi
info "· workflow: ${EIDOLON_REPO}/.github/workflows/${RELEASE_WF} exists"

# ─── Dry-run exit (--check) ───────────────────────────────────────────────
if [[ "$CHECK" == "true" ]]; then
  echo ""
  ok "Plan validated. Re-run without --check to execute."
  echo "  Would dispatch: gh workflow run 'Release ${EIDOLON_DISPLAY}' -R ${EIDOLON_REPO} -f version=${VERSION_ARG}"
  echo "  Then dispatch:  gh workflow run 'Roster Intake' -R Rynaro/eidolons -f eidolon=${EIDOLON_NAME} -f version=${VERSION_ARG}"
  exit 0
fi

# ─── Interactive confirmation (S12) ───────────────────────────────────────
if [[ "$YES" == "false" && "$NON_INTERACTIVE" == "false" ]]; then
  # Only prompt if stdin is a TTY.
  if [[ -t 0 ]]; then
    printf "Dispatch Release %s v%s + Roster Intake? [y/N] " "$EIDOLON_DISPLAY" "$VERSION_ARG" >&2
    read -r _confirm
    case "$_confirm" in
      y|Y|yes|YES) : ;;
      *)
        echo "Aborted by user." >&2
        exit 0
        ;;
    esac
  fi
fi

# ─── Resume detection (S10) ───────────────────────────────────────────────
TAG="v${VERSION_ARG}"
RESUME_DETECTED=false
if gh release view "$TAG" -R "${EIDOLON_REPO}" --json tagName -q '.tagName' >/dev/null 2>&1; then
  RESUME_DETECTED=true
fi

# Honour explicit --resume or auto-detected tag.
if [[ "$RESUME" == "true" || "$RESUME_DETECTED" == "true" ]]; then
  info "· Tag ${TAG} already exists upstream — skipping Release dispatch"
else
  # ─── Dispatch Release workflow ────────────────────────────────────────
  say "Dispatching Release ${EIDOLON_DISPLAY}  (${EIDOLON_REPO}, version=${VERSION_ARG})"
  _dispatch_rc=0
  gh workflow run "Release ${EIDOLON_DISPLAY}" -R "${EIDOLON_REPO}" -f "version=${VERSION_ARG}" 2>/dev/null \
    || _dispatch_rc=$?
  if [[ "$_dispatch_rc" -ne 0 ]]; then
    echo "✗ Failed to dispatch 'Release ${EIDOLON_DISPLAY}' in ${EIDOLON_REPO} (gh exit ${_dispatch_rc})." >&2
    echo "  Check gh auth and that the workflow name matches exactly." >&2
    exit 5
  fi

  # Capture run ID for the Actions URL (best-effort; failure is non-fatal).
  _run_id=""
  _run_id="$(release_workflow_run_id "${EIDOLON_REPO}" "Release ${EIDOLON_DISPLAY}" 2>/dev/null || true)"
  if [[ -n "$_run_id" ]]; then
    ok "Release run started — https://github.com/${EIDOLON_REPO}/actions/runs/${_run_id}"
  else
    ok "Release run started — https://github.com/${EIDOLON_REPO}/actions"
  fi
fi

# ─── Poll for tag (S5 timeout path) ──────────────────────────────────────
say "Waiting for tag ${TAG} (timeout ${RELEASE_TIMEOUT}s) ..."

_poll_tag() {
  while true; do
    if gh release view "$TAG" -R "${EIDOLON_REPO}" --json tagName -q '.tagName' >/dev/null 2>/dev/null; then
      return 0
    fi
    sleep 10
  done
}

_tag_rc=0
with_timeout "$RELEASE_TIMEOUT" _poll_tag || _tag_rc=$?

if [[ "$_tag_rc" -eq 124 ]]; then
  # Timeout (with_timeout returns 124 on kill).
  _run_id_t="$(release_workflow_run_id "${EIDOLON_REPO}" "Release ${EIDOLON_DISPLAY}" 2>/dev/null || true)"
  echo "✗ Tag ${TAG} did not appear within ${RELEASE_TIMEOUT}s." >&2
  if [[ -n "$_run_id_t" ]]; then
    echo "  Release run id ${_run_id_t} — check its log:" >&2
    echo "  https://github.com/${EIDOLON_REPO}/actions/runs/${_run_id_t}" >&2
  fi
  echo "  The Release run may still be in flight upstream. Once it tags, re-run:" >&2
  echo "    eidolons release ${EIDOLON_NAME} ${VERSION_ARG} --resume" >&2
  exit 4
elif [[ "$_tag_rc" -ne 0 ]]; then
  echo "✗ Tag poll failed unexpectedly (rc=${_tag_rc})." >&2
  exit 1
fi

ok "Tagged ${TAG}"

# ─── Dispatch Roster Intake ───────────────────────────────────────────────
say "Dispatching Roster Intake (Rynaro/eidolons, eidolon=${EIDOLON_NAME}, version=${VERSION_ARG})"
_intake_args=(-R Rynaro/eidolons -f "eidolon=${EIDOLON_NAME}" -f "version=${VERSION_ARG}")
if [[ "$AUTO_MERGE" == "true" ]]; then
  _intake_args+=(-f "auto_merge=true")
fi
_intake_rc=0
gh workflow run "Roster Intake" "${_intake_args[@]}" 2>/dev/null || _intake_rc=$?
if [[ "$_intake_rc" -ne 0 ]]; then
  echo "✗ Failed to dispatch Roster Intake (gh exit ${_intake_rc})." >&2
  echo "  Check gh auth for Rynaro/eidolons and retry:" >&2
  echo "    eidolons release ${EIDOLON_NAME} ${VERSION_ARG} --resume" >&2
  exit 5
fi
_intake_run_id=""
_intake_run_id="$(release_workflow_run_id "Rynaro/eidolons" "Roster Intake" 2>/dev/null || true)"
if [[ -n "$_intake_run_id" ]]; then
  ok "Intake run started — https://github.com/Rynaro/eidolons/actions/runs/${_intake_run_id}"
else
  ok "Intake run started — https://github.com/Rynaro/eidolons/actions"
fi

# ─── Poll for Roster Intake PR (S1 final confirmation) ───────────────────
say "Waiting for PR (timeout ${INTAKE_TIMEOUT}s) ..."

_pr_branch="codex/roster-${EIDOLON_NAME}-${VERSION_ARG//./-}"
_poll_pr() {
  while true; do
    _pr_json="$(gh pr list -R Rynaro/eidolons \
      --search "head:${_pr_branch}" \
      --json number,url \
      --limit 1 2>/dev/null || true)"
    _pr_url="$(echo "$_pr_json" | jq -r '.[0].url // empty' 2>/dev/null || true)"
    if [[ -n "$_pr_url" ]]; then
      echo "$_pr_url"
      return 0
    fi
    sleep 10
  done
}

_pr_rc=0
_found_url=""
_found_url="$(with_timeout "$INTAKE_TIMEOUT" _poll_pr)" || _pr_rc=$?

if [[ "$_pr_rc" -eq 124 || ( "$_pr_rc" -ne 0 && -z "$_found_url" ) ]]; then
  echo "" >&2
  echo "  Intake workflow dispatched but PR not yet visible." >&2
  echo "  Check: https://github.com/Rynaro/eidolons/actions" >&2
  echo "  Once the PR opens, re-run with --resume if needed:" >&2
  echo "    eidolons release ${EIDOLON_NAME} ${VERSION_ARG} --resume" >&2
  exit 4
fi

# ─── Final summary ────────────────────────────────────────────────────────
echo ""
ok "PR opened: ${_found_url}"

_pr_num="$(gh pr list -R Rynaro/eidolons \
  --search "head:${_pr_branch}" \
  --json number --limit 1 \
  -q '.[0].number // empty' 2>/dev/null || true)"
if [[ -n "$_pr_num" ]]; then
  ok "Auto-merge enabled (waits for required checks: ci, roster-health)"
  info "· Track: gh pr checks ${_pr_num} -R Rynaro/eidolons --watch"
fi
info "· Consumers can now run: eidolons upgrade ${EIDOLON_NAME}"
