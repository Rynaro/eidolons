# Coding-harness execution contract and EARS guide

## Assignment

Implement one V4-xx package and one named slice when applicable. Read README.md, ARCHITECTURE.md, this file, plan.yaml, and only the assigned section. The campaign defines requested behavior; it does not prove current defects or authorize the entire roadmap. Retired Gxx IDs must be resolved through the README mapping, not executed as current instructions.

```text
Implement V4-01 from Rynaro/eidolons PR #598.

Read docs/campaigns/gauge/README.md, ARCHITECTURE.md, HANDOFF.md,
plan.yaml, and the V4-01 section in 00-stabilization.md.
If the planning PR is unmerged, read its branch without merging it.
Pin the plan commit and actual implementation base. Inspect applicable
repository instructions and current source before editing.

Do only V4-01. Reproduce the relevant behavior, implement the smallest
coherent correction, and map each V4-01-Rxx to its planned Txx case and
observed evidence. Preserve user work, current unrelated behavior,
authority, and strict integrity semantics. Do not implement successors,
rewrite the campaign, or manufacture a passing check.

Use an isolated implementation branch/worktree and return a reviewable
PR plus the compact receipt below. Do not merge, release, deploy,
archive repositories, or run paid model trials without explicit
separate authorization. Stop at the assigned package boundary.
```

Replace package, stage file and target repository/slice for later work. The planning branch is `docs/gauge-verified-delivery-plan`; implementations use their own branches. Proposed Go interfaces, flags and filenames must be resolved in the actual implementation; do not pretend they already exist. Source ownership follows plan.yaml until a tested V4-10 relocation is recorded. Imported and external code do not both become editable sources of truth.

## EARS authoring and meaning

These are original requirements using the patterns described in [Alistair Mavin's EARS guide](https://alistairmavin.com/ears/). An event requirement starts with WHEN; a maintained state uses WHILE; an optional feature uses WHERE; unwanted behavior uses IF ... THEN; a ubiquitous obligation names the system directly. Each row names a subject and SHALL response. Combinations preserve condition-before-trigger order. Requirements describe observable behavior, not instructions to think a particular hidden thought.

IDs are stable within this revision: `V4-xx-Rnn` is the requirement; `V4-xx-Tnn` is its planned verification case. A Txx describes input/conditions, operation and expected witness; it is not a test that already exists. Use the appropriate native test framework and record the actual executable test/command later. Do not replace EARS with Given/When/Then prose or claim parser validation means executable acceptance. Structural pattern lint is not proof of semantic completeness.

The phase Markdown owns requirement text. plan.yaml references IDs and owns dependency metadata. Receipt/test code refers to IDs instead of copying requirement wording into competing specs. A changed requirement needs a reviewed amendment and affected-check invalidation, not an unannounced edit to fit an implementation. Qualitative human judgments remain labeled; a mechanical proxy is not proof of a semantic claim.

## Start and authority

Pin plan/base/candidate revisions and relevant host/sibling versions. Establish predecessors from their actual accepted code and evidence, not `status: proposed` in the planning manifest. Preserve a frozen original control for evaluation. Stage gates and package dependencies both apply. Within-stage parallel work requires nonoverlapping mutable paths and independently scoped workspaces.

For split packages, the inventory freezes required core slices before implementation; absent optional clients/services are explicitly deferred and do not block core acceptance. Each integration slice has one primary owner and one PR per external repository. The package's final integration gate covers all required selected slices. Do not treat a small slice as completion of the whole package.

An already-fixed behavior needs regression evidence and a scoped explanation, not a redundant rewrite. Inspect source and run the relevant fixture rather than assuming an open issue is still live. Keep current Bash 3.2 compatibility and stdout/stderr/idempotency rules on legacy paths. New Go components use the approved module/build conventions and share protocol fixtures; native coding loops remain host-owned.

## Work and verification

Use existing project right-sizing/ESL where required, without adding a full ceremony to every micro-fix. Start with a reproducible case and named verification. Run cheap syntax/schema/lint before expensive integration tests. Use a continuing maker for a coherent change, and consult only for a concrete unresolved need. Do not repeat an unchanged failed approach without new evidence.

For current nexus paths, inspect Makefile and the actual PR workflow before choosing commands. Existing commands include `make test-file F=<actual-test>`, `make lint`, `make schema`, `make token-budget`, and `make test JOBS=4`. Placeholders are not runnable commands. New Go tests normally use the selected module's test, race and fault-injection commands after the module exists. Sibling repositories retain their declared container/development workflow unless an approved relocation changes it.

Map every Rxx to observed positive and applicable negative evidence. Where a requirement introduces a blocking gate, demonstrate that a relevant broken fixture actually reaches and fails that gate; any nonzero exit is not sufficient evidence. Tests must discriminate the intended failure rather than be generated solely from the implementation's output.

Keep these grades separate: authored requirement; planned case; test authored; test executed; CI observed; live-host observed; independent review observed. A fixture-only implementation can be ready for review without a live claim. If a required live check or actual workflow run is unavailable, return a named blocker and preserve the runnable fixture suite. Downstream acceptance or publication requiring that evidence cannot proceed by relabeling the result.

No paid model run is authorized by this plan. The operator supplies allowed account/billing mode, models, task scope, ceiling and retention policy. Do not switch from subscription-backed work to API spending silently. Registration/syntax success does not demonstrate host execution; fake/gold-patch tests do not demonstrate coding quality.

## Completion receipt

```text
Package / selected slice / source owner:
Plan commit / implementation base / candidate identity:
Predecessor evidence:
Changes delivered:
Rxx -> Txx -> actual test/command -> observed result/evidence reference:
Checks not run and exact reasons:
Independent review method and context/provenance limitations:
Compatibility / migration / rollback:
Outstanding reservations or uncertain side effects, if relevant:
Acceptance blockers:
Nonblocking out-of-scope follow-ups:
Implementation PR:
Status: ready-for-review | partial | blocked
```

Generate volatile evidence from canonical records once V4-05 is available. Before that, record it once. The same invocation writing another checker name is not an independent reviewer. New acceptance-affecting edits invalidate their relevant evidence. `Ready-for-review` is not accepted, merged, shipped or released.

Block on acceptance failure, regression, authority violation, incompatible contracts or invalid evidence. Keep unrelated style/preferences separate. Group mechanical corrections, regenerate derived output and rerun invalidated checks before final regression. A review may find a real defect; it must not silently redefine the assignment to chase an unbounded improvement list.

Rollback disables the new behavior while preserving user work, state, journal, native sessions and uncertain economic exposure. It never restores stale-green acceptance or permission to overspend. Publication, merges, releases, repository retirement and deployment need separate explicit authorization.
