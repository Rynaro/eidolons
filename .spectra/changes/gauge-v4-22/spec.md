# V4-22 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-22 — Calibrate strategies and gate experience-driven adaptation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-21`.

**Starting points:** `evals/`, V4-09 frozen protocol, approved strategy flags from V4-16/V4-17/V4-18/V4-19 and the selected adapter. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Ablate one mechanism at a time: method fusion/isolation, lean planning, maker continuity, context/tool economy, parallelism, then model/effort routing. Each arm requires its mechanism implementation accepted; do not force every optional experiment before core release. State-conditioned routing may select only registered strategies under frozen authority and limits. Optional offline adaptation produces versioned proposals, not self-modifying production control. No learning framework, weight training, or autonomous harness evolution is a mandatory v4 dependency.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-22-R01 | WHEN a mechanism is evaluated, the comparison SHALL hold mandatory acceptance and authority constant across its arms. | **V4-22-T01:** Compare oracle/permission digests and manifests; weaker acceptance invalidates the purported improvement. |
| V4-22-R02 | WHEN preset parameters are selected, calibration SHALL use only the designated development and calibration data. | **V4-22-T02:** Freeze-before-holdout chronology and memory controls; prohibit holdout-driven tuning. |
| V4-22-R03 | WHEN a performance benefit is claimed, the report SHALL identify the isolated mechanism and include its coordination and reconstruction costs. | **V4-22-T03:** Warm/fresh, strong-first/escalation, and parallel candidates include integration/checker and rebuild costs. |
| V4-22-R04 | IF a mechanism lacks supported benefit under the frozen criteria, THEN promotion SHALL leave it unpromoted. | **V4-22-T04:** No-win, inconclusive, quality regression, and incomplete-cost fixtures; no cherry-picked winner summary. |
| V4-22-R05 | WHEN a trial reaches its authorized resource or safety boundary, the evaluator SHALL stop further trial dispatch. | **V4-22-T05:** Overspend, unknown exposure, authority violation, and late usage; retain partial data without self-authorized overage. |
| V4-22-R06 | WHEN an adaptive strategy decision is made, the recorder SHALL bind its selected action to the observed execution state, allowed alternatives, policy version, and decision reason. | **V4-22-T06:** Same prompt after success versus failed verification/context pressure; distinguish observation from estimate, log no hidden reasoning, and retain a fixed-policy control. |
| V4-22-R07 | WHEN an experience-derived method change is proposed, the adaptation record SHALL identify its evidence sources, allowed scope, parent version, and rollback target. | **V4-22-T07:** Failed/stale/self-attested experience cannot silently become an active rule; immutable diff and source references remain inspectable. |
| V4-22-R08 | IF a candidate was adapted using an evaluation batch, THEN the evaluator SHALL require qualifying evidence from later untouched tasks before reporting generalization. | **V4-22-T08:** Same-batch improvement is labeled adaptation; frozen candidate on separate forward tasks with compute-matched control qualifies only for its measured scope. |
| V4-22-R09 | WHEN an adapted strategy is promoted, the registry SHALL bind its supported model, harness, task scope, and revalidation conditions to the promoted version. | **V4-22-T09:** Model/harness/task-distribution change invalidates affected benefit claims; unrelated pinned configurations retain their own evidence. |
| V4-22-R10 | WHERE offline harness-adaptation experiments are enabled, the experiment boundary SHALL isolate proposed edits from active policy, production execution, and protected acceptance definitions. | **V4-22-T10:** Proposal attempts to alter permission gate/oracle or live controller fail; allowed skill/configuration proposal is tested in a bounded sandbox and cannot self-approve promotion. |

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** A null result completes an investigation without a default flip. No oracle/margin changes after outcomes; no self-promoted policy, executable harness, or permission changes.

## Bounded decision

See [decision.md](decision.md). Schema-2 additive calibration namespaces. Extend V4-21; required slices `workflow-ablations` + `routing-calibration`; `optional-offline-adaptation` delivers R10 fixture isolation without production self-mod. No V4-18 / V4-23.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Reuse V4-21 evaluation. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-18 / V4-23.
