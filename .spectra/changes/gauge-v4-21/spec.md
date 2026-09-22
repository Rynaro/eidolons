# V4-21 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority.

## V4-21 — Expand the early instrument into auditable evaluation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-09`, `V4-15`.

**Starting points:** V4-09 recorder/protocol, `evals/`, `.github/workflows/live-eval.yml`; inspect actual vivi-measurement runners/RESULTS before reuse. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Extend the early instrument into auditable evaluation. Compare native / original-v3 / v4 fixed-model / structural-only when each exists; structural after V4-10 stays pending (not zero). Keep development / calibration / holdout separate. Unknown outcome/cost remains visible. No paid trial without allowance.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-21-R01 | WHEN evaluation arms are executed, the evaluator SHALL record their actual model, harness, policy, environment, acceptance and billing identities. | **V4-21-T01:** Requested-versus-observed model, mismatched arm, and pinned controls; expose confounds. |
| V4-21-R02 | WHEN cost per accepted task is computed, the evaluator SHALL include consumption from all attempted tasks in each compatible unit. | **V4-21-T02:** Failures, abandonment, cancellations, timeouts, checking, and zero acceptance; undefined ratio is not zero and unknown exposure prevents a complete-cost claim. |
| V4-21-R03 | WHEN a held-out task runs, the evaluation boundary SHALL isolate its answers from maker-accessible memory, reference patches, and prior run artifacts. | **V4-21-T03:** Leakage canaries and visible-test controls; tuning failures stay development material. |
| V4-21-R04 | IF a run uses a gold patch or simulated host, THEN the evaluator SHALL classify it as plumbing evidence rather than model capability. | **V4-21-T04:** Existing smoke workflow versus actual live-run discriminator; unavailable credentials remain blocked. |
| V4-21-R05 | WHEN results are reported, the evaluator SHALL include completion, runnable latency, total latency, interventions, invalid acceptance, and quality-review outcomes with uncertainty. | **V4-21-T05:** Independent known-data recomputation, censored/small samples, and declared delayed-rework observation window. |
| V4-21-R06 | WHEN an evaluation task is admitted, the evaluator SHALL record its requirement sufficiency, oracle qualification, and exclusion or defect-review status. | **V4-21-T06:** Underspecified prompt, overly restrictive test, inadequate behavior coverage, and valid control; post-outcome exclusions retain audit trail and sensitivity results. |
| V4-21-R07 | IF arm environments or effective permissions differ materially from the frozen protocol, THEN the evaluator SHALL flag the comparison as confounded. | **V4-21-T07:** Resource guarantees, ceilings, network, dependency/cache, timeout, and sandbox differences; do not hide them in pooled averages. |
| V4-21-R08 | WHEN repeated attempts or candidate search are evaluated, the report SHALL distinguish candidate success, selection success, autonomous completion, and repeated-run reliability. | **V4-21-T08:** Passing patch in a cancelled run and success among multiple failed candidates do not count as identical operational outcomes. |
| V4-21-R09 | IF evaluation material has influenced method, memory, or routing tuning, THEN the evaluator SHALL remove that material from the untouched promotion set. | **V4-21-T09:** Holdout feedback used in a playbook/route adjustment becomes development evidence; forward set remains inaccessible until the candidate is frozen. |

**Exit.** Apply the common exit and package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** No benchmark score or private-suite label implies productivity, contamination freedom, or universal superiority. Preserve failed/ineligible/censored runs and incomplete telemetry.

## Bounded decision

See [decision.md](decision.md). Schema-2 additive evaluation namespaces. Extend V4-09; reuse V4-15 comparison hooks. No V4-20 / V4-22 / V4-10.

## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Reuse V4-09 instrument and V4-15 demonstrator comparison. Freeze named conformance anchors before implementation. Keep fixture evidence separate from live host and provider qualification. No new paid probes, release, deployment or merge approval is implied. No V4-20 / V4-22 / V4-10.
