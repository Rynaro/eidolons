# Stage 5 — Evaluation, bounded adaptation, and evidence-scoped rollout

V4-21 follows V4-15 directly and precedes broad adoption; V4-22 evaluates only implemented arms; V4-23 gates release. Stage numbers are navigation, not all-to-all dependency barriers.

Read [HANDOFF.md](HANDOFF.md) and the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries. [plan.yaml](plan.yaml) owns dependencies and source routing; these tables own requirement text. [RESEARCH.md](RESEARCH.md) explains the evidence-to-design mapping without adding hidden obligations.

**Common exit for every package:** map every applicable Rxx to its planned Txx and actual observed evidence. Exercise relevant rejection paths and the intended gate. Mark unavailable required evidence blocked; mark optional cases not applicable only with their feature/scope condition recorded. Authored requirements, authored tests, executed fixtures, observed CI, and live-host qualification are distinct. A fixture-only candidate can be ready for review without a live-managed claim. See HANDOFF.md for receipts and acceptance.

---

<a id="v4-21"></a>

## V4-21 — Expand the early instrument into auditable evaluation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-09`, `V4-15`.

**Starting points:** V4-09 recorder/protocol, `evals/`, `.github/workflows/live-eval.yml`; inspect actual vivi-measurement runners/RESULTS before reuse. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Run after the demonstrator and before broad consolidation; no V4-20 or roster prerequisite. Extend, do not replace, the early instrument. Compare strong feasible native, original-v3, v4 fixed-model workflow, and structural-only arms when each exists. Add the structural-only arm after V4-10 with a pinned ref or isolated flags; pending is not a zero score. Keep development, calibration, and untouched forward/holdout data separate. Unknown outcome/cost coverage remains visible. No paid trial without explicit allowance.

**Implementation sequence.** Validate metric arithmetic and leakage controls; preregister arm/environment/evaluator versions; perform bounded authorized comparisons; include censored outcomes and uncertainty. Re-run newly eligible arms later without rewriting previously observed results or criteria.

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

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** No benchmark score or private-suite label implies productivity, contamination freedom, or universal superiority. Preserve failed/ineligible/censored runs and incomplete telemetry.

---

<a id="v4-22"></a>

## V4-22 — Calibrate strategies and gate experience-driven adaptation

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-21`.

**Starting points:** `evals/`, V4-09 frozen protocol, approved strategy flags from V4-16/V4-17/V4-18/V4-19 and the selected adapter. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Ablate one mechanism at a time: method fusion/isolation, lean planning, maker continuity, context/tool economy, parallelism, then model/effort routing. Each arm requires its mechanism implementation accepted; do not force every optional experiment before core release. State-conditioned routing may select only registered strategies under frozen authority and limits. Optional offline adaptation produces versioned proposals, not self-modifying production control. No learning framework, weight training, or autonomous harness evolution is a mandatory v4 dependency.

**Implementation sequence.** Run matched bounded development/calibration batches; capture state/reason/configuration and full task costs; freeze candidate parameters before forward/holdout access. Test promotion/rollback with known outcomes. Optional offline proposals receive a fixed dataset, allowed edit surface, trial budget, regression suite, and explicit operator approval before any promotion.

**Assignment slices:** `workflow-ablations`, `routing-calibration`, `optional-offline-adaptation`. Assign one slice at a time; package acceptance covers its declared required slices. Optional deferral is explicit, not a silent pass.

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

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** A null result completes an investigation without a default flip. No oracle/margin changes after outcomes; no self-promoted policy, executable harness, or permission changes.

---

<a id="v4-23"></a>

## V4-23 — Evidence-scoped migration, release, and optional retirement

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-02`, `V4-03`, `V4-10`, `V4-16`, `V4-17`, `V4-18`, `V4-19`, `V4-20`, `V4-22`.

**Starting points:** `cli/install.sh`, `cli/src/upgrade_self.sh`, `MIGRATION.md`, `.github/workflows/release-nexus.yml`, `roster/`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Prepare v4.0.0 only for actually implemented breaks. Preserve verified binary installation plus an optional developer build path, modular contracts, optional memory/UI, and migration compatibility. Selected core slices have explicit acceptance; optional experiments and clients may remain deferred. Separate correctness, managed-operation qualification, and performance promotion. A governance-only improvement can be described as such, not as measured speed/cost superiority.

**Implementation sequence.** Test fresh/legacy/v3 upgrades and rollback/offline modes; assemble the exact supported-configuration matrix and held-out evidence; require explicit authorization for merge/tag/release/deploy/archival. No such action is authorized by this planning PR.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-23-R01 | WHEN a supported migration is authorized, the migrator SHALL stage and verify the replacement before switching the active installation. | **V4-23-T01:** Affected pre-v1.41.1, v2.20, v3.3.1, fresh/dirty/interrupted fixtures; no force-integrity bypass. |
| V4-23-R02 | IF migration or post-switch validation fails, THEN recovery SHALL preserve a usable previous installation and user state. | **V4-23-T02:** Staging/switch/smoke failure, repeat migration, native sessions, and pending reservations. |
| V4-23-R03 | WHEN a release candidate is evaluated, the release gate SHALL require the declared deterministic checks and applicable authorized live evidence. | **V4-23-T03:** Distinguish code/behavior versus docs-only candidate; missing required live evidence is not replaced by smoke success. |
| V4-23-R04 | IF promotion evidence is insufficient or approval absent, THEN release automation SHALL leave behavioral defaults unchanged. | **V4-23-T04:** No-win/inconclusive/missing approval; prepared report does not authorize tag, merge, or publication. |
| V4-23-R05 | IF a component still has an unmigrated supported consumer, THEN repository retirement SHALL remain blocked. | **V4-23-T05:** Tested replacement plus inventory/license/history/support/rollback evidence and explicit archive authorization. |
| V4-23-R06 | WHEN a supported host version changes, the capability catalogue SHALL invalidate affected qualification until rechecked. | **V4-23-T06:** Cancellation, usage, and tool-boundary version drift stops the affected managed claims. |
| V4-23-R07 | WHEN release readiness is reported, the release gate SHALL report correctness, managed-operation qualification, and performance promotion as separate decisions. | **V4-23-T07:** Deterministic suite passes but live probe blocked or performance null; no composite green badge conceals either limitation. |
| V4-23-R08 | WHEN a promoted method or strategy is rolled back, the controller SHALL retain task lineage, evidence history, and outstanding obligations under the still-authorized contract. | **V4-23-T08:** Rollback with active candidate, pending cancellation, unknown usage, and later failure; no stale acceptance, budget refill, or wider authority. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user settings/sessions/candidates/evidence and unresolved exposure. Repository retirement, release, and behavioral defaults always need their own accepted evidence and authorization.
