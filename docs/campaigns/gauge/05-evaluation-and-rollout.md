# Phase 5 — Evaluation, calibration, and controlled rollout

Entry: Phase 4's required slices accepted, the G06 protocol frozen, and operator-authorized live allowances supplied when needed. Exit: G16–G18 accepted for the evidence-supported scope. An inconclusive/no-win evaluation can complete the investigation without authorizing default promotion. Read [HANDOFF.md](HANDOFF.md); [plan.yaml](plan.yaml) owns dependencies.

## G16 — Build the acceptance-and-economics evaluation harness

**Primary repository:** Rynaro/eidolons. Start with existing `evals/`, CLI eval runners, live-eval workflow, G03 evidence records, G05 telemetry, and G06's frozen protocol. Depends on G15.

Implement the prerecorded protocol without tuning its success margins after seeing outcomes. The main comparison arms are native host without Eidolons, original Eidolons control pinned before this campaign, Gauge Balanced, and Gauge Conserve. Accelerate is a separate candidate comparison when its intended latency benefit and extra budget are authorized. Keep host/model/version, task, environment, acceptance oracle, timeout, permissions, and billing mode comparable. Report any unavoidable difference as a confound rather than attributing it to Gauge.

Start with the same model to isolate workflow effects; model selection is evaluated separately in G17. Stratify tasks across localized repairs, unfamiliar bugs, multi-file features, environment failures, flaky/nondeterministic tests, and higher-risk changes in disposable environments. The primary pilot scope remains bounded brownfield work. Hidden/held-out checks must be independent of the maker and inaccessible for editing; useful visible tests remain available to the maker. Separate development, calibration, and held-out task sets. Prevent online memory or repeated exposure from leaking held-out answers; test realistic warm-memory performance separately with controlled state.

Measure the original task outcome, not merely the first easy slice. Count all attempted tasks and all associated resources, including planning, failed runs, checkers, cancelled/abandoned work, and reconstruction. Report total consumption divided by independently accepted tasks in each compatible unit; if none are accepted, report undefined/no accepted completions rather than a misleading zero. Do not blend opaque subscription allowance with token or money estimates. Report completion rate, time to first runnable behavior, end-to-end and active/human-wait latency, avoidable user interventions, invalid-completion rate, regressions, and maintainability/delayed-rework review with its observation window.

Use paired/randomized order where appropriate, repeated trials for stochastic behavior, uncertainty intervals, and a clear treatment of censored/timeout runs. Small samples may be descriptive only; a p95 from insufficient observations is not a stable service claim. An extra review has a recorded cost. Fixture runs are labeled simulated and never counted as real model outcomes. No provider trial runs without explicit account/pool, limit, allowed models, and retention authorization.

| Acceptance | Required verification |
|---|---|
| G16-A1: Every arm uses the intended pinned implementation/configuration and original task/oracle. | Provenance manifest, differential fixtures, baseline clone verification, and hidden-check isolation test. |
| G16-A2: Failed, interrupted, and zero-success runs remain in the metrics. | Synthetic known-outcome dataset with independent expected totals, denominators, censoring, and mixed-unit negatives. |
| G16-A3: Scope, model, memory, and environment confounds are surfaced. | Deliberately mismatched arm and contamination fixtures; reports refuse unsupported equivalence. |
| G16-A4: Protocol/margins/stopping rules precede comparative outcome inspection. | Verify G06 protocol digest/timestamp and calibration/holdout access history; deviations are recorded before a new trial. |
| G16-A5: Budget/authority caps and privacy are preserved during evaluation. | Budget-exhaustion and sandbox escape controls, log redaction, no-credential fixture mode, and separately authorized real run. |

**Stop/rollback:** no public performance claims or default flips from synthetic, confounded, or insufficient results. Missing live allowance produces a runnable evaluator and a blocked live-evaluation criterion, not fabricated data.

## G17 — Ablate overhead and calibrate the candidate presets

**Primary repository:** Rynaro/eidolons; targeted member changes only for already-defined flags in RAMZA/Vivi or other accepted Phase 4 slices. Depends on G16.

Run experiments in bounded batches on development/calibration tasks before the untouched held-out evaluation. Isolate the mechanisms rather than changing everything simultaneously: generated versus manual evidence workflow; lean versus current planning; continuing versus fresh maker context; need-based versus current specialist chains; reuse versus rediscovery; and only then adaptive model/effort selection. Hold acceptance, authority, and the external oracle constant. Keep negative/inconclusive results, not just winning tasks.

Evaluate sequential escalation versus deliberate strong-model-first execution on task strata. A small per-call saving is not enough when retries or user intervention erase it. Test parallelism only on genuinely independent work and measure both critical-path latency and total usage; include merge/coordination cost. Preserve an explicit requested specialist or deliverable even when a cheaper route exists. Routing confidence is heuristic until calibration supports an interpretation; do not present arbitrary rubric thresholds as success probabilities.

Derive conservative candidate limits and reserves from observed distributions on the calibration set. Record sample size, task/host scope, model availability, capability granularity, and uncertainty. Keep the three presets understandable and their quality floor unchanged. An unqualified model or unavailable host feature is excluded; do not silently substitute and then attribute results to the selected configuration. Freeze selected parameters before using holdout outcomes.

The decision report must state win/no-win/inconclusive per mechanism and per task stratum, the actual quality/cost/latency trade-off, and which changes should remain off. Publish only redacted permitted evidence; do not expose native session transcripts, credentials, private repository contents, or hidden evaluation answers prematurely.

| Acceptance | Required verification |
|---|---|
| G17-A1: Each claimed benefit is linked to a specific controlled comparison. | Machine-readable arm/flag/config IDs, actual observed model, all attempt records, and independent metric recomputation. |
| G17-A2: Preset calibration does not relax acceptance or exploit holdout leakage. | Compare oracle/authority digests and parameter-freeze history; inspect memory/task-set isolation. |
| G17-A3: Lower-cost policy is evaluated on end-to-end accepted work, not only cheap responses. | Include rework, specialist/checker consumption, failures, and user interventions; stratified quality review. |
| G17-A4: Parallelism and context claims include their actual overhead. | Wall/active time, critical-path trace, total consumption, merge/reconstruction cost, and no-progress controls. |
| G17-A5: Negative/inconclusive results remain visible and defaults unchanged. | Full task/arm manifest and decision report; reject missing failed arms and cherry-picked summaries. |

**Stop/rollback:** stop a trial at its predeclared budget or safety/quality boundary. Revert candidate flags, not test expectations. A mechanism that fails to earn adoption stays off; the investigation is still valuable.

## G18 — Scope-limited rollout, migration, and operational acceptance

**Primary repository:** Rynaro/eidolons. Conditional producer/consumer release slices use the repository versions actually adopted in Phase 4. Depends on G17.

Prepare an explicit promotion decision based on G06's predefined criteria and G16/G17's results: promote for a named host/task/configuration scope, retain opt-in, or decline promotion. Include held-out evidence with uncertainty, unresolved limitations, support levels, and a maintenance plan for version-sensitive host interfaces. Do not claim cross-host savings, exact quota control, or all-project completion from one pilot. A research citation or a green fixture suite cannot authorize promotion.

Test fresh install, no-Gauge existing project, upgraded opt-in project, legacy journal/receipt migration, independently versioned members/contracts, optional-server absence, dirty worktrees, interruption, and rollback with outstanding reservations. Preserve user settings and native credentials/sessions. Idempotent migration is non-destructive and reports unsupported legacy state honestly. Package/release producer changes before consuming their exact tags/hashes in the nexus; publication and merge require separate operator authorization.

Document Conserve/Balanced/Accelerate behavior, actual enforceable units/granularity, unsupported capabilities, setup, diagnostics, interpretation of unknown quota, recovery, and escalation. Show one runnable example from an authorized observed result, plus a budget-limited partial example that does not claim success. Optional GUIs must not become installation prerequisites.

Roll out opt-in first, then only the approved scope/defaults. Add regression fixtures for observed failures and a reversible feature switch. Accounting uncertainty, invalid completion, authority violation, or material quality regression triggers a stop/review according to the frozen protocol. Provider/host upgrades invalidate affected capability assumptions until requalification. Preserve remaining budgets and uncertain reservations through disable/rollback; never turn an accounting error into permission to spend.

| Acceptance | Required verification |
|---|---|
| G18-A1: Promotion scope and verdict follow the preregistered evidence criteria. | Independent review of protocol, holdout report, trade-offs, limitations, and decision; no-win/inconclusive has no default flip. |
| G18-A2: Installation/migration/rollback preserve opt-out behavior and user data. | Supported platform matrix, repeated operations, dirty workspace, legacy state, and outstanding reservation scenarios. |
| G18-A3: Published documentation matches tested capabilities and actual package versions. | CLI/README/host matrix comparison; concrete producer/consumer refs and denied unsupported controls. |
| G18-A4: Release and default changes occur only with explicit approval. | Inspect PR/release sequence and approvals; no automated self-promotion from a benchmark result. |
| G18-A5: Operational regressions have an effective stop, recovery, and requalification path. | Fault injection for lost telemetry, stale host capabilities, invalid completion, and rollback during a run. |

**Campaign exit:** accepted implementation artifacts and an evidence-backed adoption decision for a declared scope. Remaining optional integrations, greenfield expansion, further models, and future research become separate work, not unbounded prerequisites for shipping the proven path.
