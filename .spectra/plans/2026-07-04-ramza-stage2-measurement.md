---
eidolon: ramza
kind: spec
version: "1.0.0"
created_at: "2026-07-05T00:16:00Z"
target_repos: ["Rynaro/eidolons", "Rynaro/Ramza"]
stories_count: 3
---

# RAMZA Stage-2 Measurement — plan (dogfooded through RAMZA's own gates)

> This plan was produced by walking RAMZA's actual `bin/` gates — see
> `2026-07-04-ramza-stage2-measurement.state.json` (the audit trail) and
> `ramza-calibration.jsonl` (scored gates). Tier: **lite** (score 2: 4 files, med
> stakes). Complexity 7/12 → extended reasoning.

## Scope

**In:** the measurement that gates RAMZA's Stage-3 seat flip — (1) canary DSL runs
for ramza (incl. the two new missions: rightsize-gate, drift-tamper), (2) a scoped
planner A/B on the H-WIN instrument (ramza 0.2.0 vs spectra 4.11.0, planner-seat
tasks only), (3) calibration of the host model against `anchors/` before trusting
any rubric verdicts.
**Out:** routing.yaml/preset/cortex changes (Stage 3b), v1.0.0 release mechanics
(Stage 3a), any SPECTRA modification.
**Assumptions:** H-WIN harness runs on this box via the claude-headless driver
(risk-if-wrong: measurement moves to CI dispatch); PR #433 merged first
(risk-if-wrong: run against the branch nexus via EIDOLONS_NEXUS).

## Approach

Hypothesis B — **canary-first, then scoped A/B** (explore 79.5, solid). Run the
cheap conformance layer first (canaries catch wiring failures for cents), only then
spend on the A/B quality comparison, using the same scorecard store and baseline-diff
flow the nexus v2.0 eval waves established. Rejected: A "full H-WIN matrix now"
(62, weak — burns budget before wiring is proven), C "ship and measure in the wild"
(55, weak — no controlled baseline, gates the seat flip on anecdote).

## Stories

- **S2-1 — Calibrate the scorer.** Host model scores `anchors/*.md`; `ramza-calibrate`
  must return `calibrated` before any rubric-dependent measurement. Timebox ≤1d.
  Executor: economy tier (mechanical protocol). Output contract: scored.json + verdict.
- **S2-2 — Canary conformance run.** `eidolons canary ramza` across the DSL missions;
  all MUST-level checks green; failures triaged to wiring vs methodology. Timebox ≤2d.
  Executor: mid tier. Output contract: canary scorecard JSON in `.spectra/research/`.
- **S2-3 — Scoped planner A/B.** H-WIN instrument, planner-seat task set, ramza@0.2.0
  vs spectra@4.11.0, budget-matched, pass² with holdout gating (the Vivi Stage-2
  shape); `ramza-adherence` composite recorded per run as a secondary metric. Timebox
  ≤3d. Executor: frontier tier holds judging; economy executes missions.

## Acceptance Criteria

See `2026-07-04-ramza-stage2-measurement.criteria.md` (EARS, lint-clean, frozen —
sha256 in the state file).

## Confidence

Computed at Assemble via `ramza-score --rubric confidence` — recorded in the state
file's `gates[]`. Scope is declared (`ramza-drift`) over `evals/*`,
`.spectra/research/*`, `.spectra/plans/*` so Stage-2 execution drift is checkable.

## Notes

ECL envelope intentionally not emitted: the nexus checkout is not a RAMZA install
target (no `ECL_VERSION` consumer contract here); emission is exercised in the
consumer-path E2E instead.
