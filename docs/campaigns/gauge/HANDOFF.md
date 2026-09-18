# Coding-harness handoff

This is the common execution contract for the Gauge campaign. It does not execute work by itself. Load this file, [README.md](README.md), the selected entry in [plan.yaml](plan.yaml), and only the corresponding work-package section. Additional source reading should follow the package's starting paths and observed failures.

## Copyable assignment

```text
Implement Gauge work package G01 in Rynaro/eidolons.

Read docs/campaigns/gauge/README.md, HANDOFF.md, plan.yaml,
and the G01 section of 01-foundations.md. Treat those files as
requirements, not proof of current behavior. Read applicable repository
instructions and inspect the actual checkout before editing.

Do only this package. Reproduce the relevant defect with a regression
fixture, implement the smallest coherent correction, and run the named
mechanical and regression checks. Record observed evidence separately
from assumptions and unavailable checks. Do not rewrite the campaign,
implement successor packages, change model defaults, relax acceptance,
or expand permissions to get a pass.

Use an isolated branch/worktree. Preserve pre-existing user changes.
Return a reviewable PR and a compact completion/blocker receipt. Do not
merge, publish a release, deploy, or run paid model trials without a
separate explicit allowance. Stop after the package's exit gate.
```

Replace the package ID, repository, and phase filename for subsequent assignments. Where a package contains repository-specific integration slices, name exactly one slice; a cross-repository package is not permission to modify every listed repository in one session. The operator supplies any live-trial account/pool, spending ceiling, permitted models, and time allowance; absent allowance means fixture-only validation, not inferred access to money.

## Start and scope

Check predecessor completion against actual merged/reviewed code and recorded test evidence, not the campaign's initial `proposed` status. Pin the actual repository SHA, host versions when relevant, and applicable producer/consumer versions. Keep the frozen control baseline distinct from the implementation's current base. An already-correct behavior needs a passing regression and a scoped explanation, not a redundant rewrite.

Use the target project's existing ESL/right-sizing process where applicable. This campaign adds no requirement to create a full plan, critique, or lifecycle artifact for every micro-change. A short implementation note suffices unless a genuine design or contract decision needs more. Do not change archived historical records to make today's checks pass.

When an acceptance criterion cannot fit the current contract, identify the smallest producer-side amendment and its dependent consumer slice. Complete the safe independent work and report the exact blocker. Do not invent an envelope field, host flag, native capability, or sibling release and silently depend on it.

## Work loop

Reproduce or characterize before editing. Establish the named external verification command and relevant test anchors. Implement in the allowed tree, run syntax/schema/lint checks before slower tests, and use localized failure evidence to repair. Keep one maker responsible for the coherent patch. Consult another specialist only for a concrete unresolved need; do not automatically run the entire roster.

Do not repeat an identical failed approach without new evidence. Preserve useful progress when a limit is reached. A permission boundary, changed acceptance, missing credential, necessary external spend, or unresolvable contract incompatibility can require human input. Routine internal phases do not require another 'continue' prompt.

For nexus work, inspected baseline entrypoints include:

```bash
EIDOLONS_NEXUS="$PWD" bash cli/eidolons --help
make test-file F=cli/tests/<actual-relevant-file>.bats
make lint
make schema
make token-budget
# At the package's final regression checkpoint, when dependencies exist:
make test JOBS=4
```

The placeholder test path is not a command to run verbatim. Inspect the current Makefile, actual tests, and `.github/workflows/ci.yml` before selecting commands. CI is not identical to the Makefile. New gates must be exercised by the real PR workflow as well as local validation. Do not claim a green workflow from a local command or an unexecuted workflow edit. Sibling repositories use their own declared development/container workflow.

## Completion receipt

Return one compact receipt, not several independently maintained reports:

```text
Package and repository:
Base and candidate revision / workspace identity:
Predecessor evidence:
Implemented behavior:
Acceptance criteria -> observed checks and evidence references:
Checks not run, with reason:
Independent verification method and its limitations:
Compatibility / migration / rollback:
Remaining acceptance blockers:
Out-of-scope follow-ups (nonblocking):
PR:
Status: ready-for-review | blocked | partial
```

Use runtime-generated records once G03 is available; before then, record actual commands and results once. A package is not independently verified merely because the same harness writes 'checker' under another name. Run deterministic checks and use a genuinely separate verification invocation/context where required. Report missing independent verification honestly.

Do not self-merge or mark the whole campaign complete. A reviewable candidate is different from an accepted package, a shipped feature, or a released product. New acceptance-affecting edits invalidate the relevant evidence and must be rechecked.

## Review and rollback

Block on acceptance failure, regression, incorrect evidence, unsafe authority, or incompatible contracts. Turn unrelated style preferences and optional architecture improvements into separate follow-ups. Group mechanical corrections into one pass, regenerate derived views, and rerun only invalidated checks before final regression.

Rollback removes/disables the new behavior without destroying journals, accounting, audit evidence, user settings, or unrelated work. No automatic destructive migration. A rollback that would permit previously blocked overspending is not safe; preserve the stop state until accounting is reconciled.
