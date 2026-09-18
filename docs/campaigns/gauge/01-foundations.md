# Phase 1 — Evidence and accounting foundations

Entry: campaign accepted for planning; no runtime Gauge feature is required. Exit: G01–G03 accepted with observed regression evidence. These are correctness/chore packages, not model-performance experiments. Use [HANDOFF.md](HANDOFF.md); dependencies are owned by [plan.yaml](plan.yaml).

## G01 — Make the execution journal ordered, atomic, and recoverable

**Primary repository:** Rynaro/eidolons. **Scope:** `cli/src/ledger.sh`, relevant `cli/tests/` fixtures, directly associated schema/CLI documentation. Start with `commit_event` and the `open|record|status` handlers. New helper/test filenames must follow the actual tree; none is assumed to exist.

**Source finding to reproduce:** sequence allocation counts files, predecessor discovery sorts filenames lexicographically, and writers have no shared transaction. The inspection suggests races and incorrect predecessor selection beyond single-digit sequences; write tests before asserting their exact effects.

Implement one serialized append boundary, deterministic numeric ordering, explicit event identity/idempotency, and bounded recovery. Choose the least invasive mechanism that is valid on supported macOS/Linux filesystems and Bash 3.2. Document lock/transaction ownership, timeout, stale-owner recovery, and the supported filesystem boundary. Do not introduce a database or daemon merely because it is convenient. Reuse this append primitive later rather than building competing journals.

Atomic publication must not be described as power-loss durability unless sync and recovery behavior actually support that claim. Unknown-run reads must not create directories. Incomplete/corrupt records remain visible as recovery errors, not silently discarded successful history. Retain a non-destructive legacy-read/import story and never overwrite an existing event with another writer's event.

| Acceptance | Required verification |
|---|---|
| G01-A1: Sequential appends preserve one numeric order and correct predecessor linkage past 9 and 99. | Append at least 120 events; independently recompute the chain and verify every event. |
| G01-A2: Concurrent accepted appends are lossless; duplicate request IDs are idempotent. | Concurrent writers with distinct IDs plus repeated identical IDs; compare the resulting ID set, not merely a count. |
| G01-A3: Interrupted append/lock ownership recovers deterministically without accepting partial JSON or losing published records. | Fault injection before publication, after publication, and during lock ownership; inspect exit status and recovery output. |
| G01-A4: A read of an unknown run has no filesystem side effects. | Snapshot the fixture tree before/after `status` and compare. |
| G01-A5: Legacy and platform behavior are explicit. | Read legacy fixtures; run supported Bash/macOS/Linux gates; unsupported filesystems produce a diagnostic rather than an invented guarantee. |

**Stop/rollback:** no reservations, host control, or routing changes. Preserve original records during migration and allow disabling the new writer only with a documented compatible reader. Return the focused regression suite and a PR.

## G02 — Bind completion to current artifacts and real verification provenance

**Primary repository:** Rynaro/eidolons. Start with `cli/src/ledger.sh`, `cli/src/run.sh`, ledger/checkpoint schemas under `schemas/`, and existing independent-check fixtures. Depends on G01.

**Source finding to reproduce:** `status` remembers an earlier passing checker event even after a later failed check. The checker-independence calculation compares a caller label with an optional environment variable. Neither establishes a current verified candidate or trusted invocation separation.

Define a candidate identity over the declared acceptance-affecting inputs: base revision, tracked and relevant untracked content, test/criteria identity, relevant file modes/symlinks, and verification environment/configuration. A Git HEAD alone is insufficient for a dirty worktree. Exclude the receipt's own output by an explicit rule to avoid recursive hashes; do not exclude actual acceptance-affecting docs or fixtures. Define the latest applicable outcome for each mandatory check and fail conservatively on missing, stale, contradictory, or unreconciled evidence.

Separate caller claims, tool-observed tests, and trusted adapter-observed checker invocations. Missing maker identity or unverifiable checker provenance cannot earn an independent grade. Phase 1 may exercise a trusted fixture adapter; live host provenance remains unavailable until G08. Document the threat boundary: local hashes detect changed bytes; they do not authenticate meaning or defeat an attacker with unrestricted access to the coordinator's files.

| Acceptance | Required verification |
|---|---|
| G02-A1: A pass followed by an applicable fail is not complete; a later valid recheck can recover. | Exercise pass→fail→pass against the same candidate and mandatory check set. |
| G02-A2: Candidate/criteria/environment mutation invalidates the affected evidence. | Change tracked code, a required untracked file, protected criteria, and relevant verification configuration independently. |
| G02-A3: Renamed/missing identities do not manufacture checker independence. | Same invocation with two labels; absent maker; forged caller metadata; genuine separate fixture invocation/context. |
| G02-A4: All mandatory checks must pass for the current candidate. | Mixed old/new candidate receipts, missing check, cancelled check, unknown side effect, unrelated old failures. |
| G02-A5: Status remains a projection of evidence rather than model prose. | Change narrative claims without evidence; replay events in valid order; malformed evidence gives a non-success state. |

**Stop/rollback:** no new ESL lifecycle states, permissions, or live host claims. Preserve legacy receipts as legacy/unverified rather than laundering them into the new grade. Rollback may remove a new view but must not reintroduce stale-green acceptance.

## G03 — Generate evidence views and run cheap gates before review

**Primary repository:** Rynaro/eidolons. Start with `cli/src/check_change_specs.sh`, `Makefile`, `.github/workflows/ci.yml`, `schemas/`, existing ECL builder/verification entrypoints, and the archived `chain-scout-debug-fix/verification.md` referenced by the campaign README. Depends on G02.

Create a minimal canonical completion/evidence record using G02's identities. Record actual commands, exit status, timestamps, environment/version references, check scope, and evidence paths once. Generate volatile summaries from that record rather than hand-maintaining counts, hashes, and verdicts in multiple Markdown/YAML files. Reuse ECL/tonberry builders when they are installed; retain a local file path without requiring an MCP. Record unavailable commands honestly.

Add parsing, actual schema validation, duplicate-key rejection for the new configuration/evidence surfaces, reference checks, and generated-view drift checks where relevant. Syntax-only `jq empty` is not schema validation. Coordinate with existing issue #564 rather than silently broadening this package into a repo-wide YAML-parser migration. Wire each new gate into both the local entrypoint and the real PR workflow; prove a broken fixture fails the actual gate. Leave frozen archived records unchanged.

Before any behavioral change or paid trial, record the original nexus control SHA from README plus actual installed sibling/host/model/config versions and a development-task manifest. Freeze metric definitions: accepted completion, runnable milestone, total usage including failures, elapsed/active/human-wait time, avoidable user intervention, correctness/maintainability review, and invalid completion. This prepares the baseline, not an optimization result. Detailed trial parameters must be frozen in G06 before live comparisons.

| Acceptance | Required verification |
|---|---|
| G03-A1: Identical semantic inputs generate stable views; genuine changes update all derived views. | Golden fixtures and repeat generation; volatile time is an explicit injected input. |
| G03-A2: Invalid/missing/duplicate-key evidence and stale references cannot pass validation. | Independent negative fixtures; test shape, required nonempty checks, and cross-reference identity, not parsing alone. |
| G03-A3: Generated counts and verdicts cannot drift silently. | Mutate a source check result and a generated view separately; regeneration/check mode detects the discrepancy. |
| G03-A4: New gates execute in local validation and the PR workflow. | Targeted command evidence plus actual workflow outcome; workflow absence remains a blocker to this criterion. |
| G03-A5: The pre-change control and measurement definitions survive later implementation. | Validate the recorded baseline manifest; ensure no model calls, credentials, or raw private transcripts are required. |

**Stop/rollback:** no historical cleanup campaign, fabricated test results, automatic workflow dispatch spending, or default routing changes. The producer record is authoritative; derived output can be rebuilt. Exit Phase 1 only when current-candidate correctness and journal integrity are demonstrated.
