# ESL Change Lifecycle Chronicle: harness-hook-project-dir-anchor

**Change ID:** `harness-hook-project-dir-anchor`  
**Archived:** 2026-07-29  
**Tier:** lite  
**Status:** archived

## Provenance (CHT-verified)

| Signal | Value | Source |
|--------|-------|--------|
| Maker (author) | vivi | change.json |
| Checker | kupo | change.json |
| Drift verified | true | change.json, drift_checked=true |
| ESL version | 1.1 | change.json |
| Archive path | `.spectra/changes/archive/2026-07-29-harness-hook-project-dir-anchor` | change.json, tonberry archive completed |
| Memory preflight | ran=true, records=3 | change.json |
| Has code | true | change.json |

## Defects (Primary + Secondary)

### Primary Defect
`harness install` wrote **project-relative** hook command paths (e.g. `.eidolons/harness/hooks/claude-code-UserPromptSubmit.sh`) into a consumer project's `.claude/settings.json`. Claude Code execs hook commands via `/bin/sh -c` from the **session's shell cwd**, not the project root. Result: any session parked in a subdirectory got exit-127 ENOENT on every hook firing ("Failed with non-blocking status code"), silently losing cortex routing injection and ECM meter path. Confirmed in the field (~/workspace/oss/ariramba; shell cwd in `.ariramba/runs/<id>`), reproducible by running the stored command string from any non-root cwd.

**Fix:** Command form is now the literal, unexpanded string `"$CLAUDE_PROJECT_DIR"/.eidolons/harness/hooks/claude-code-<event>.sh` for UserPromptSubmit, SessionStart, PreToolUse (--strict), PostToolUse (ECM), and Stop (--with-telemetry). Claude Code exports `$CLAUDE_PROJECT_DIR` into every hook's environment.

### Secondary Defect (Found during scoping, not in incoming evidence)
Anchoring the command alone fixes the ENOENT but not the outcome: the shim still ran with the drifted cwd, and the kernel resolves the project purely cwd-relatively (`cli/src/lib.sh:590-593` — `PROJECT_MANIFEST="eidolons.yaml"`, `manifest_exists() { [[ -f "$PROJECT_MANIFEST" ]]; }`, no upward walk). With `eidolons.yaml` unreachable, `run --hook` silent fail-opened to empty stdout / exit 0.

**Fix:** Every claude-code shim now `cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0` before invoking the kernel, so `eidolons.yaml` resolves. Fail-open preserved (exit 0 on any error).

## Scope & Acceptance Criteria

**12 Acceptance Checks** (AC-1 through AC-12, spec.md §"Acceptance criteria"):

- **AC-1:** Fresh install writes anchored form (literal `$CLAUDE_PROJECT_DIR` unexpanded)
- **AC-2:** Shim reaches kernel with correct cwd when invoked from subdirectory; fail-open when `CLAUDE_PROJECT_DIR` unset/invalid
- **AC-3:** ECM PostToolUse and telemetry Stop entries written in anchored form
- **AC-4:** `harness install --force` migrates old-form entries in place (zero duplicates)
- **AC-5:** Repeat `--force` is idempotent (byte-identical jq output)
- **AC-6:** `harness remove` strips both old and anchored forms; empty keys deleted; non-eidolons entries preserved
- **AC-7:** `eidolons doctor` (D12) and `eidolons canary` accept anchored form; pre-fix predicate confirmed to fail against new fixture
- **AC-8:** `eidolons.lock` `harness.shim_paths[]` remain relative; D12/canary `-f`/`-x` checks pass unchanged
- **AC-9:** Non-claude-code hosts (copilot, cursor, opencode, codex) byte-identical; no `$CLAUDE_PROJECT_DIR` appears in their surfaces
- **AC-10:** New bats coverage for fresh install, migration, removal, cwd-drift simulation, doctor/canary acceptance, telemetry
- **AC-11:** No bash-4isms, no `eval`, stderr-only output, `make schema` unchanged
- **AC-12:** Lands via PR from `fix/harness-hook-project-dir-anchor` with matching `CHANGELOG.md` entry

## Verification Outcome

**Checker:** kupo  
**Verification date:** 2026-07-29 (before archiving)

Per spec.md §"Verification plan":
1. `make test-file F=cli/tests/harness.bats` — AC-1, AC-2, AC-4, AC-5, AC-6, AC-10(a-d) ✓
2. `make test-file F=cli/tests/canary.bats` + `cli/tests/telemetry_install.bats` — AC-3, AC-7, AC-10(e-f) ✓
3. `make test-file F=cli/tests/sync.bats P="harness"` — SessionStart heal path, AC-4 ✓
4. `make test JOBS=4` — full-suite regression incl. eval_compliance.bats, context.bats, junction_marker.bats, memory.bats ✓ (1690/1690 per brief)
5. `make lint` + `make schema` — AC-11 ✓
6. **Gate-integrity step:** pre-fix jq predicate confirmed to return 0 against anchored fixture; fixed predicate returns ≥1 ✓
7. Manual field verification: cwd-drift simulation passed; `eidolons doctor` confirms no D12 error ✓

**All 12 ACs passed.** Drift check clean (checker kupo, zero mismatches reported).

## Manifest Discrepancy

**Noted:** `change.json` serializes `acceptance_checks: []` (empty array), despite 12 ACs being fully documented in spec.md. The ACs are present as specification requirements but not stored as structured records in the manifest. This is not a conformance failure (spec.md is the authoritative AC reference per ESL v1.1), but represents a gap between the manifest schema's optional array field and its actual content.

## Delivery

- **Branch:** `fix/harness-hook-project-dir-anchor`
- **Squash commit:** 816ae14 (rebased, landed as PR #522 squash)
- **CHANGELOG entry:** Added to `[Unreleased]` / `### Fixed`
- **Promotion intent:** INFORM envelope to CRYSTALIUM (Semantic layer)
  - Source: IDG (esl-hop)
  - Target: orchestrator → mcp__crystalium__ingest (Semantic)
  - Envelope: `promotion.envelope.json` (v1.0)

## Right-Sizing Summary

- **Tier:** lite (signals: files_touched=8, rubric_score=6/12, tradeoff=false)
- **Actual footprint:** 10 files touched, +677/−36 lines
- **Rationale:** Targeted harness and shim changes with comprehensive, parallel bats coverage; no architectural upheaval; secondary defect scoped within primary fix
