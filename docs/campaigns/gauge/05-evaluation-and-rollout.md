# Stage 5 — Evaluation, migration, and evidence-scoped rollout

Separate structural changes from workflow changes and model routing. An inconclusive investigation can finish without authorizing a default flip or release.

Read [HANDOFF.md](HANDOFF.md) and [ARCHITECTURE.md](ARCHITECTURE.md). [plan.yaml](plan.yaml) owns package identities, dependencies and source routing. Each table below owns its EARS requirements; verification entries are planned cases, not executed results. Assign one package, and one named slice where applicable.

<a id="v4-21"></a>

## V4-21 — Evaluation instrument with auditable denominators

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-09`, `V4-15`, `V4-20`. Stage gates also apply.

**Starting points:** `evals/`, `.github/workflows/live-eval.yml`, `vivi-measurement: RESULTS.md and runners (locate)`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Implement the V4-09 preregistered protocol. Compare native host, original Eidolons, structural-only consolidation, and Gauge/workflow changes before adaptive model selection. A structural-only arm needs its recorded intermediate ref or valid isolated flags; do not infer a structural gain from a bundled treatment. Import measurement fixtures only with provenance/rights. Keep public regressions, calibration and untouched holdout distinct.

**Implementation sequence.** Build known-outcome metric fixtures and leakage checks. Add pinned arm/environment/permission/billing manifests. Run live trials only within explicit allowances and report blocked or inconclusive results honestly.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-21-R01 | WHEN evaluation arms are executed, the evaluator SHALL record their actual model, harness, policy, environment, acceptance and billing identities. | **V4-21-T01:** Intentional mismatched arm, pinned control and requested-versus-observed model fixtures; report confounds. |
| V4-21-R02 | WHEN cost per accepted task is computed, the evaluator SHALL include consumption from all attempted tasks in each compatible unit. | **V4-21-T02:** Failures, abandoned/cancelled/timeouts, checker work and zero successes; zero-success ratio is undefined, not zero. |
| V4-21-R03 | WHEN a held-out task runs, the evaluation boundary SHALL isolate its answers from maker-accessible memory, reference patches, and prior run artifacts. | **V4-21-T03:** Leakage canaries and visible-test positive controls; production failures used for tuning remain development cases. |
| V4-21-R04 | IF a run uses a gold patch or simulated host, THEN the evaluator SHALL classify it as plumbing evidence rather than model capability. | **V4-21-T04:** Existing --smoke workflow plus actual live-run discriminator; unavailable live credentials remain blocked. |
| V4-21-R05 | WHEN results are reported, the evaluator SHALL include completion, runnable latency, total latency, interventions, invalid acceptance, and quality-review outcomes with uncertainty. | **V4-21-T05:** Independent recomputation of known datasets, censored outcomes, small-sample limitations and delayed-rework observation window. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** No smoke/gold-patch run counted as capability evidence. Private tasks are not assumed contamination-free.

---

<a id="v4-22"></a>

## V4-22 — Ablate heuristics and calibrate economic presets

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-21`. Stage gates also apply.

**Starting points:** `evals/`, `V4-09 frozen protocol`, `V4-16/V4-17/V4-18 strategy flags`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Compare one mechanism at a time on development/calibration tasks: generated evidence, method fusion, lean planning, maker continuity, targeted context, and deliberate parallelism; model/effort selection follows workflow isolation. Heuristics have applicability and retirement conditions. Do not buy reduced cost by removing mandatory verification.

**Implementation sequence.** Run bounded matched batches in preregistered order. Freeze candidate parameters before holdout access. Produce win/no-win/inconclusive findings per supported task/host configuration.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-22-R01 | WHEN a mechanism is evaluated, the comparison SHALL hold mandatory acceptance and authority constant across its arms. | **V4-22-T01:** Oracle/permission digests and budget/host manifest comparison; lowered acceptance invalidates the claim. |
| V4-22-R02 | WHEN preset parameters are selected, calibration SHALL use only the designated development and calibration data. | **V4-22-T02:** Freeze-before-holdout chronology, memory state controls and prohibited holdout-driven tuning test. |
| V4-22-R03 | WHEN a performance benefit is claimed, the report SHALL identify the isolated mechanism and include its coordination and reconstruction costs. | **V4-22-T03:** Warm/fresh contexts, strong-first/sequential escalation and parallel branches include integration/reviewer overhead. |
| V4-22-R04 | IF a mechanism lacks supported benefit under the frozen criteria, THEN promotion SHALL leave it unpromoted. | **V4-22-T04:** No-win, inconclusive, quality regression and incomplete-cost fixtures; no cherry-picked winning-task summary. |
| V4-22-R05 | WHEN a trial reaches its authorized resource or safety boundary, the evaluator SHALL stop further trial dispatch. | **V4-22-T05:** Injected overspend/unknown exposure/authority violation and late usage; preserve partial data without self-authorized overage. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** A null result can complete the investigation while keeping defaults off. Do not change oracles or margins after observing results.

---

<a id="v4-23"></a>

## V4-23 — Evidence-scoped migration, release, and optional repository retirement

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-02`, `V4-03`, `V4-10`, `V4-22`. Stage gates also apply.

**Starting points:** `cli/install.sh`, `cli/src/upgrade_self.sh`, `MIGRATION.md`, `.github/workflows/release-nexus.yml`, `roster/`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Prepare a v4.0.0-compatible migration only for actually implemented breaks; this planning PR changes no version. Use a staged verified binary path plus an optional developer go install path. Publish modular contracts and approved package versions before dependent adoption. Archive only explicitly authorized, migrated components after replacement and rollback evidence. Retain optional memory/UI deployment.

**Implementation sequence.** Test fresh install, affected legacy recovery, v3 migration, rollback and offline/no-service modes. Review held-out promotion scope and compile the release evidence. Perform publication/archival only under separate explicit operator authorization.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-23-R01 | WHEN a supported migration is authorized, the migrator SHALL stage and verify the replacement before switching the active installation. | **V4-23-T01:** Affected pre-v1.41.1, v2.20, v3.3.1, fresh, dirty and interrupted upgrade fixtures; no force-integrity bypass. |
| V4-23-R02 | IF migration or post-switch validation fails, THEN recovery SHALL preserve a usable previous installation and user state. | **V4-23-T02:** Failure at staging/switch/smoke plus repeat migration, native session and pending reservation controls. |
| V4-23-R03 | WHEN a release candidate is evaluated, the release gate SHALL require the declared deterministic checks and applicable authorized live evidence. | **V4-23-T03:** RC matrix distinguishes code/behavior change from docs-only; missing required live evidence cannot be replaced by smoke success. |
| V4-23-R04 | IF promotion evidence is insufficient or approval absent, THEN release automation SHALL leave behavioral defaults unchanged. | **V4-23-T04:** Inconclusive/no-win and missing operator approval; prepared report is not permission to tag, merge or publish. |
| V4-23-R05 | IF a component still has an unmigrated supported consumer, THEN repository retirement SHALL remain blocked. | **V4-23-T05:** Inventory plus tested replacement, licenses/history, support window and rollback; explicit archive authorization required. |
| V4-23-R06 | WHEN a supported host version changes, the capability catalogue SHALL invalidate affected qualification until rechecked. | **V4-23-T06:** Version-sensitive cancellation/usage/tool behavior; managed claims stop where required controls are no longer established. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Preserve user settings, native sessions, candidate work, evidence and outstanding reservations. A rollback cannot restore permissions to overspend or accept stale evidence.

---
