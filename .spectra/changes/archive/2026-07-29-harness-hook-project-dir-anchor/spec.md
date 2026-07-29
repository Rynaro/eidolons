---
change_id: harness-hook-project-dir-anchor
tier: lite
status: proposed
author: RAMZA
intent_class: BUG_SPEC
repo: Rynaro/eidolons (nexus)
branch: fix/harness-hook-project-dir-anchor
---

# Anchor claude-code hook commands to `$CLAUDE_PROJECT_DIR`

## Problem

`cli/src/harness_install.sh` writes **project-relative** hook commands (`.eidolons/harness/hooks/claude-code-<event>.sh`) into a consumer project's `.claude/settings.json`. Claude Code executes hook commands via `/bin/sh -c` from the **session's shell cwd**, not the project root — so any session parked in a subdirectory gets exit-127 ENOENT on every hook firing ("Failed with non-blocking status code"), silently losing cortex routing injection and the ECM meter path. Confirmed in the field (`~/workspace/oss/ariramba`, shell cwd in `.ariramba/runs/<id>`) and reproducible by running the stored command string from any non-root cwd. Claude Code exports `$CLAUDE_PROJECT_DIR` (absolute project root) into every hook's environment for exactly this case.

**Second-order defect (found during scoping, not in the incoming evidence).** Anchoring the *command* fixes the ENOENT but not the outcome: the shim still runs with the drifted cwd, and the kernel resolves the project purely cwd-relatively (`cli/src/lib.sh:590-593` — `PROJECT_MANIFEST="eidolons.yaml"`, `manifest_exists() { [[ -f "$PROJECT_MANIFEST" ]]; }`, no upward walk). With `eidolons.yaml` unreachable, `run --hook` fail-opens to empty stdout / exit 0. Left unaddressed, this change trades a loud failure for a silent one. The shims must therefore also `cd "$CLAUDE_PROJECT_DIR"` before invoking the kernel.

## Scope

| File (anchor) | Required change |
|---|---|
| `cli/src/harness_install.sh:26` | Keep `HARNESS_SHIM_DIR` **relative** (it is also the on-disk write path and the `shim_paths` lock value). Add a separate constant for the *command* form, e.g. `HARNESS_SHIM_CMD_DIR='"$CLAUDE_PROJECT_DIR"/.eidolons/harness/hooks'` — a **literal**, single-quoted, never expanded at install time. |
| `cli/src/harness_install.sh:909-912` | `_ups_cmd` / `_ss_cmd` / `_ptu_cmd` built from the command-form constant (UserPromptSubmit, SessionStart, `--strict` PreToolUse). Fresh-write and merge branches (`:915-1013`) both carry the anchored literal. |
| `cli/src/harness_install.sh:1026` | ECM `_register_posttooluse_in_settings "$HARNESS_SHIM_DIR/claude-code-PostToolUse.sh"` — same bug, same fix. **Missed by the incoming evidence.** |
| `cli/src/harness_install.sh:1036-1041` | Telemetry `_tel_stop_cmd` / `_register_stop_in_settings` — same bug, same fix. **Missed.** |
| `cli/src/harness_install.sh` shim bodies (`_write_posttooluse_meter_shim:424-453`, Stop shim `:~340-374`, UPS/SessionStart/PreToolUse writers) | claude-code shims only: `cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0` before invoking the kernel, so `eidolons.yaml` resolves. Fail-open preserved (`exit 0` on any error). |
| `cli/src/harness_install.sh` SessionStart heal path (`--refresh-shims-only`, matcher upsert `:962-1002`) | The "is this entry ours?" test is exact-string on `$ss`; must recognise the old relative form so `--force` / `sync` heal **migrates** rather than appends. |
| `cli/src/harness_remove.sh:43,126-136` | Removal is a `startswith(".eidolons/harness/hooks/")` prefix filter — the anchored form does **not** match, so removal would silently orphan every entry. Match **both** forms (old prefix OR anchored prefix) across all events (UserPromptSubmit, SessionStart, PreToolUse, PostToolUse, Stop). |
| `cli/src/lib.sh:2290` | D12 doctor check `select(startswith(".eidolons/harness/"))` — **third detection surface, missed by the incoming evidence.** Left unfixed, `eidolons doctor` reports `D12 .claude/settings.json missing eidolons UserPromptSubmit entry` (a blocking `err`) on a correctly-fixed project. Accept both forms. |
| `cli/src/canary.sh:1040` | Same jq predicate in the canary host check; accept both forms (share one helper — do not hand-roll a second predicate). |
| `cli/src/telemetry.sh:1133-1135` + its `disable` removal path | `telemetry enable` writes the Stop command relative (note `$(cd "$(pwd)" && printf …)` is a no-op that still yields a relative string). Anchor it; `disable` must strip both forms. **Missed.** |
| `cli/src/lib.sh:2263-2274`, `cli/src/canary.sh:1012-1028` | **No change.** These `-f`/`-x` the lock's `shim_paths`, which stay **relative** on purpose. Anchoring them would break both checks. |
| `CHANGELOG.md` | Entry under the next patch release naming the defect and the anchored form. |

## Acceptance criteria

- **AC-1** — WHEN `eidolons harness install --hosts claude-code` runs in a project with no `.claude/settings.json`, THEN each of `.hooks.UserPromptSubmit`, `.hooks.SessionStart` (and `.hooks.PreToolUse` under `--strict`) SHALL contain exactly one entry whose `command` is the literal string `"$CLAUDE_PROJECT_DIR"/.eidolons/harness/hooks/claude-code-<event>.sh` — byte-identical, with `$CLAUDE_PROJECT_DIR` **unexpanded** in the file.
- **AC-2** — WHEN a claude-code shim is invoked with `CLAUDE_PROJECT_DIR=<abs project root>` and cwd set to a subdirectory of that project, THEN the shim SHALL resolve, execute, and reach the kernel with cwd at the project root (exit 0, no ENOENT), AND SHALL exit 0 without output when `CLAUDE_PROJECT_DIR` is unset or invalid (fail-open).
- **AC-3** — WHEN `eidolons.yaml` declares a `context:` block, THEN the ECM `PostToolUse` entry SHALL be written in the anchored form (AC-1 shape); AND WHEN `--with-telemetry` is passed, or `eidolons telemetry enable` is run, THEN the `Stop` entry SHALL be written in the anchored form.
- **AC-4** — WHEN `harness install --force` runs against a `.claude/settings.json` already carrying **old-form relative** entries, THEN each old-form entry SHALL be replaced in place (or removed and re-added) such that the resulting array contains the anchored entry and **zero** old-form entries — no duplicate pair for any event.
- **AC-5** — WHEN the AC-4 command is run a second time, THEN `jq -cS .` of `.claude/settings.json` SHALL be byte-identical to the first run's output and the CLI SHALL take the existing no-op log path (repo invariant: "Second install run is idempotent").
- **AC-6** — WHEN `eidolons harness remove` runs against a settings file containing anchored entries, old-form entries, or both, THEN all eidolons-written entries SHALL be removed across every event key (UserPromptSubmit, SessionStart, PreToolUse, PostToolUse, Stop), empty event keys and an empty `hooks` object SHALL be deleted, AND every non-eidolons entry SHALL be preserved byte-identically.
- **AC-7** — WHEN `eidolons doctor` (D12, `cli/src/lib.sh:2290`) or `eidolons canary` (`cli/src/canary.sh:1040`) inspects a project wired with the anchored form, THEN neither SHALL report a missing UserPromptSubmit entry; AND both SHALL still fail on a genuinely unwired project. Negative proof required: the pre-fix predicate must be demonstrated returning 0 against the anchored fixture.
- **AC-8** — WHEN a project is wired with the anchored form, THEN `eidolons.lock` `harness.shim_paths[]` SHALL remain **relative** on-disk paths and the D12 / canary `-f` / `-x` shim checks SHALL pass unchanged.
- **AC-9** — WHEN `harness install` wires copilot, cursor, opencode or codex, THEN their surfaces (`.github/hooks/eidolons.json`, `.codex/hooks.json`, `.opencode/plugins/eidolons.js`) SHALL be byte-identical to the pre-change output — `$CLAUDE_PROJECT_DIR` SHALL NOT appear in any non-claude-code artefact.
- **AC-10** — WHEN the suite runs, THEN new bats coverage SHALL exist for: (a) fresh install writes the anchored form (`cli/tests/harness.bats`); (b) re-install over an old-form fixture migrates without duplication and is a no-op on the second run (`cli/tests/harness.bats`, mirroring the existing old-form fixtures at `harness.bats:178-206` and `sync.bats:1999-2004`); (c) `harness remove` strips both forms (`cli/tests/harness.bats`); (d) cwd-drift simulation per AC-2 (`cli/tests/harness.bats`); (e) doctor / canary accept the anchored form (`cli/tests/canary.bats` — the old-form fixture at `canary.bats:572` gains an anchored twin); (f) telemetry Stop anchored + both-form removal (`cli/tests/telemetry_install.bats`, constant at `:17`).
- **AC-11** — WHEN `make lint` and the macOS `cli-tests` CI job run, THEN the change SHALL be clean: no bash-4isms (`declare -A`, `${var,,}`, `readarray` / `mapfile`, `&>>`), no `eval`, all `say/ok/info/warn/die` output on stderr, and `make schema` unchanged.
- **AC-12** — WHEN the change lands, THEN it SHALL arrive as a PR from branch `fix/harness-hook-project-dir-anchor` with a matching `CHANGELOG.md` entry.

## Out of scope

- Non-claude-code hosts (copilot / cursor / opencode / codex). No equivalent project-root variable is confirmed for them; they keep relative commands unchanged (AC-9). Codex's `.codex/hooks.json` (`harness_install.sh:1170-1176`) and copilot's `bash:` command (`:1052-1055`) carry the same latent cwd assumption — **recorded as a follow-up ESL change**, not fixed here.
- Consumer-project re-runs: already-wired projects migrate only when the user runs `harness install --force` / `eidolons sync` / `harness remove`. No auto-migration hook, no version-triggered rewrite.
- A general upward-walking project-root resolver in `lib.sh`. AC-2 solves the cwd problem locally in the shim; a global resolver has a much larger blast radius and is a separate change.
- `statusLine` (`harness_install.sh:545-593`) — its command is `eidolons statusline render` (PATH lookup, cwd-independent). Unaffected.
- `.eidolons/harness/` used as a **filesystem** location (`sync.sh`, `harness.sh`, `memory.sh` preflight cache, `lib.sh:1702-1741` gitignore / junction-marker logic, `eval_compliance.sh:608-609`, `context.bats`, `junction_marker.bats`, `memory.bats`). Those are `-f` / `-x` / `rm` targets relative to the project root and must not be anchored.

## Verification plan (what the checker runs)

1. `make test-file F=cli/tests/harness.bats` — AC-1, AC-2, AC-4, AC-5, AC-6, AC-10(a-d).
2. `make test-file F=cli/tests/canary.bats` and `make test-file F=cli/tests/telemetry_install.bats` — AC-3, AC-7, AC-10(e-f).
3. `make test-file F=cli/tests/sync.bats P="harness"` — SessionStart heal path over the old-form fixture (`sync.bats:1999-2004`), AC-4.
4. `make test JOBS=4` (matching CI) — full-suite regression, incl. `eval_compliance.bats`, `context.bats`, `junction_marker.bats`, `memory.bats`, which touch `.eidolons/harness` as a filesystem path (AC-8 side).
5. `make lint` + `make schema` — AC-11.
6. **Gate-integrity step (mandatory, AC-7 negative proof):** run the *pre-fix* jq predicate against the new anchored fixture and confirm it returns `0` (i.e. it would have failed), then confirm the fixed predicate returns `>= 1`. A detection surface that cannot go red on the defect it names is not a gate.
7. Manual field check on a real consumer project: `cd <project>/<subdir> && CLAUDE_PROJECT_DIR=<project> sh -c '<command string read from settings.json>' </dev/null; echo $?` => `0`; then `eidolons doctor` => no D12 error.
