# V4-14 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-14 — Freeze candidates and qualify protected acceptance

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-05`, `V4-12`, `V4-13`.

**Starting points:** V4-05 evidence contract, existing sandbox/apply/loop code under `cli/src/`, V4-06 workspace/runner interfaces. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Protect candidate execution, journal, verification definitions, credentials, and optional signing keys with an actual supported boundary. Worktree, directory, process name, and hash are insufficient. Separate execution integrity from acceptance adequacy. The acceptance package names requested behavior, exclusions, oracle origin, environment, review obligations, and required evidence. Check that it rejects representative plausible defects, not only that a reference passes. No universal correctness claim or new custom test framework.

**Implementation sequence.** Freeze candidate/criteria/environment manifests; isolate build/temp outputs and runner credentials; produce actual receipts; qualify oracles with expected-pass and expected-fail cases; review changed tests; revalidate integration against the actual target base.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-14-R01 | WHEN mandatory verification begins, the runner SHALL bind the check to a frozen candidate and acceptance/environment identities. | **V4-14-T01:** Concurrent maker edits and tracked/untracked/config/mode changes; logs identify the exact snapshot tested. |
| V4-14-R02 | WHILE candidate execution is active, the execution boundary SHALL deny writes to authoritative evidence and protected verification definitions. | **V4-14-T02:** Candidate-controlled shell/build script attempts journal, receipt, oracle, and key writes; test actual filesystem/process controls. |
| V4-14-R03 | WHEN a runner finishes a check, the evidence producer SHALL record its actual outcome and invocation provenance. | **V4-14-T03:** Pass/fail/error/cancelled/skipped fixtures; authored success prose cannot replace observation. |
| V4-14-R04 | IF required runner isolation or provenance is unavailable, THEN acceptance SHALL withhold the corresponding trusted verification grade. | **V4-14-T04:** Separate label/directory without access enforcement; absent context provenance; supported isolation control. |
| V4-14-R05 | IF the target base has changed before authorized candidate application, THEN the application gate SHALL require revalidation of the integration candidate. | **V4-14-T05:** Base moved, dirty target, and conflicts after green checks; no unchecked application. |
| V4-14-R06 | WHEN a receipt is projected into a human report, the renderer SHALL preserve distinct integrity, provenance, and acceptance fields. | **V4-14-T06:** Canonical-record round-trip; digest equality does not authenticate author or prove semantic correctness. |
| V4-14-R07 | WHEN an acceptance package is qualified, the verifier SHALL record its behavior coverage and outcomes on both acceptable and representative defective candidates. | **V4-14-T07:** Known valid solution plus plausible stub, missing edge behavior, and regression fixture; inadequate discrimination prevents qualification, not arbitrary mutation-score targets. |
| V4-14-R08 | IF maker changes affect required tests or verification definitions, THEN acceptance SHALL require a recorded review by their authorized acceptance owner. | **V4-14-T08:** Test deletion, relaxed assertion, and legitimate expectation change; maker approval alone cannot replace owner review or old evidence invalidation. |
| V4-14-R09 | WHEN a task requires observable application behavior, the verifier SHALL execute that behavior in the declared environment before accepting it. | **V4-14-T09:** Start app and exercise affected interaction/persistent effect or compatibility surface; unit-only and fabricated-log candidates fail the behavior gate. |
| V4-14-R10 | IF acceptance criteria cannot distinguish the requested result from a plausible incomplete result, THEN the verifier SHALL report an acceptance-definition blocker. | **V4-14-T10:** Ambiguous brief/oracle and missing behavioral discriminator; no silent requirement invention or weakening to manufacture a pass. |

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** No automatic push, merge, release, or deployment. Candidate build scripts cannot inherit checker credentials. A qualified oracle remains scoped and fallible. Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

## Bounded decision

See [decision.md](decision.md). Schema-2 additive acceptance namespaces. Fixture FS/process isolation with real deny. Integrity ≠ adequacy. Reuse V4-05 projection fields. No V4-15+.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Reuse V4-05 evidence projection, V4-12 dispatch locks, and V4-13 assignment IDs. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-15 delivery loop.
