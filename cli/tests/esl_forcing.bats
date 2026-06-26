#!/usr/bin/env bats
#
# cli/tests/esl_forcing.bats — static gates for the ESL forcing-function build.
#
#   G-NO-HARDGATE-YET — the M3 hard gate (PreToolUse deny-path) is DEFERRED this
#                       iteration; assert no ESL-introduced deny / block decision
#                       leaked into the shipped hook or the install auto-fire.
#   M4-S3 doc-agree   — methodology/cortex/esl-protocol.md and the install
#                       behaviour must agree: assess auto-fires on install.
#
# These are static greps over the shipped artifacts (no project fixtures needed),
# mirroring the no-verb static idiom in mcp_assess.bats:361-377. Bash 3.2 safe.

load helpers

HOOK="cli/src/harness_hook.sh"
INSTALL="cli/src/mcp_install.sh"
DOC="methodology/cortex/esl-protocol.md"

# ─── G-NO-HARDGATE-YET (guards the M3 deferral) ──────────────────────────────

@test "G-NO-HARDGATE-YET: shipped hook introduces no PreToolUse deny-path" {
  # No PreToolUse event handling in the hook.
  run grep -nF 'PreToolUse' "$EIDOLONS_ROOT/$HOOK"
  [ "$status" -ne 0 ] || return 1
  # No permission-deny decision field.
  run grep -nF 'permissionDecision' "$EIDOLONS_ROOT/$HOOK"
  [ "$status" -ne 0 ] || return 1
  # No hook-control '"decision": "block"' emit. (The enforcement-MODE string
  # 'block' is allowed — only the deny/block hook DECISION JSON is forbidden.)
  run grep -nE '"decision"[[:space:]]*:[[:space:]]*"?block' "$EIDOLONS_ROOT/$HOOK"
  [ "$status" -ne 0 ] || return 1
  run grep -nE '"permissionDecision"[[:space:]]*:[[:space:]]*"?deny' "$EIDOLONS_ROOT/$HOOK"
  [ "$status" -ne 0 ]
}

@test "G-NO-HARDGATE-YET: install auto-fire surface introduces no deny-path either" {
  run grep -nE 'permissionDecision|PreToolUse|"decision"[[:space:]]*:[[:space:]]*"?block' "$EIDOLONS_ROOT/$INSTALL"
  [ "$status" -ne 0 ]
}

# NOTE (scope): a strict-tier (TRANCE) PreToolUse delegate-or-deny shim already
# pre-exists in cli/src/harness_install.sh (R18/R19/R20). That is NOT part of the
# ESL forcing-function and is untouched by this iteration. G-NO-HARDGATE-YET is
# scoped — per spec §6 — to the shipped hook + the new ESL code, asserting no
# *ESL-introduced* deny-path; it deliberately does not police the pre-existing
# strict-tier shim.

# ─── M4-S3 — doc / behaviour agreement (no drift) ────────────────────────────

@test "M4-S3: esl-protocol.md no longer claims assess does NOT fire on install" {
  run grep -nF 'does NOT fire on' "$EIDOLONS_ROOT/$DOC"
  [ "$status" -ne 0 ]
}

@test "M4-S3: esl-protocol.md states the install auto-fire cadence" {
  run grep -nE 'fires .?.?automatically.?.? at .?.?eidolons mcp install' "$EIDOLONS_ROOT/$DOC"
  [ "$status" -eq 0 ]
}

@test "M4-S3: the install behaviour the doc describes actually exists (auto-fire wired)" {
  # The doc claim must be backed by real code: install gates assess to tonberry,
  # invokes mcp_assess.sh, and honors the EIDOLONS_SKIP_AUTO_ASSESS opt-out.
  run grep -nF 'mcp_name" = "tonberry' "$EIDOLONS_ROOT/$INSTALL"
  [ "$status" -eq 0 ] || return 1
  run grep -nF 'mcp_assess.sh' "$EIDOLONS_ROOT/$INSTALL"
  [ "$status" -eq 0 ] || return 1
  run grep -nF 'EIDOLONS_SKIP_AUTO_ASSESS' "$EIDOLONS_ROOT/$INSTALL"
  [ "$status" -eq 0 ]
}

@test "M4-S3: doc documents the EIDOLONS_SKIP_AUTO_ASSESS opt-out" {
  run grep -nF 'EIDOLONS_SKIP_AUTO_ASSESS' "$EIDOLONS_ROOT/$DOC"
  [ "$status" -eq 0 ]
}
