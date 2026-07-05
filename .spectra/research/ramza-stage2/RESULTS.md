# RAMZA Stage-2 Measurement — Session 1 Results

> 2026-07-05 · Fable 5 coordinating (scorers/executors: Sonnet 5, Haiku 4.5).
> Plan of record: `.spectra/plans/2026-07-04-ramza-stage2-measurement.md` (dogfooded, confidence 82.5 VALIDATE).
> Scorecards + raw run outputs in this directory. Arms: ramza@0.2.0 (attested) vs spectra@4.11.0.

## S2-1 — Scorer calibration: **calibrated** (both models), after a real instrument catch

- Two clean scorers (Sonnet 5, Haiku 4.5) scored `anchors/*.md` blind (never saw references).
- **First run: both uncalibrated against the v1 references — but in perfect band agreement with each other** (solid/solid, weak/weak). Disagreement concentrated on the weak anchor (scorers 20–27 points harsher). Verdict: the v1 references, authored by the anchor designer, were the miscalibrated side — a maker≠checker violation in reference authoring, caught by the instrument built to catch exactly this.
- References revised to rounded two-scorer consensus (v2, Ramza main `evals` commit), per the scoring.md protocol (versioned, never silent). Re-run: **sonnet: calibrated · haiku: calibrated**.
- Files: `raw/scored-{sonnet,haiku}.json`, `calibration-log.jsonl`.

## S2-2 — Canary conformance: **3/3 missions PASS, 0 MUST failures**

| Mission | pass / fail / inconclusive | exit |
|---|---|---|
| smoke-default | 11 / 0 / 0 | 0 |
| rightsize-gate | 7 / 0 / 3 (SHOULD-NOT criteria — DSL gap, below) | 0 |
| drift-tamper | 9 / 0 / 1 | 0 |

Executors: fresh Sonnet sessions in the E2E consumer project (`eidolons init --members ramza`), running the real installed gate tools. drift-tamper reproduced the tamper scenario live and quoted the tool's real DRIFT output.

**Instrument fixes required first (the actual headline):** the mission-validation path had never been exercised end-to-end anywhere in the ecosystem. Three latent defects surfaced and fixed:
1. Criteria args are authored backtick-wrapped (`## Scope`) across ALL shipped mission files (SPECTRA's included) — the validator matched them literally. Fix: single-pair backtick strip in `parse_criterion` (+ regression CAN-BT).
2. Dash-leading phrases (`--verify`) were swallowed as grep options. Fix: `--` guards at all three grep call sites (+ regression CAN-OR).
3. The `` `X` OR `Y` `` authoring convention (inherited from SPECTRA's suite) had no evaluator support. Fix: DSL OR→ERE alternation (+ regression CAN-OR).
4. (Ramza-side) the ```` ```yaml ```` fence criterion authored with escaped backticks → rewritten as a `contain heading` exact-line match (Ramza main; session cache patched identically — v1.0.0 carries it).

**Known DSL gap (non-blocking, SHOULD-level):** `SHOULD NOT contain heading` negation isn't parsed → INCONCLUSIVE. Park for the nexus backlog.

## S2-3 — Planner A/B pilot (instrument validation, NOT the pre-registered run)

Same mission (Q-SPECTRA-1: `--dry-run` deployment-flag spec), same mechanical rubric, k=2 per arm, Sonnet executors in per-arm consumer projects:

| Arm | pass@1 | pass² | words (r1/r2) | confidence verdicts | machine audit trail |
|---|---|---|---|---|---|
| spectra@4.11.0 | 1.0 | **2/2** | 6666 / 5309 | VALIDATE 75 / VALIDATE 75 | self-reported cycle |
| ramza@0.2.0 | 1.0 | **2/2** | 2885 / 2760 | VALIDATE 76.25 / AUTO_PROCEED 87.5 | real gate outputs: rightsize→lite, explore scores incl. weak rejects, ears-lint 6-8/8, lint pass, freeze sha256, verify-emit pass, adherence composite 1.0 (run 2) |

Read: **contract-conformance parity at ~52% of the verbosity**, with RAMZA runs producing verifiable audit trails (every score quoted from a tool, weak hypotheses rejected on the record) where SPECTRA runs self-report. This is a k=2 single-task structural pilot — it validates the instrument and the direction, it does NOT satisfy AC-003 (the budget-matched, holdout-gated, non-inferiority pass² run on the planner-seat task set). AC-001 is satisfied; AC-002 satisfied for the three run missions.

## Acceptance-criteria status (vs the frozen set, sha256 423248b6…)

- **AC-001 (calibrate before rubric-dependent measurement): PASS** (S2-1).
- **AC-002 (canary MUST-level green): PASS** for smoke-default/rightsize-gate/drift-tamper; remaining 4 missions (dual-format, memory-round-trip, discovery-elicitation, parallel-spec-trance) not yet run — memory-round-trip needs a live CRYSTALIUM.
- **AC-003 (H-WIN non-inferiority A/B): OPEN** — pilot only; the pre-registered run is the remaining Stage-2 work.
- **AC-004 (adherence composite in archived scorecards): PARTIAL** — present for ramza run 2; wire into the A/B harness for the full run.
- **AC-005 (drift watch on Stage-2 scope): PASS so far** — all Stage-2 writes inside the declared globs.

## Verdict

Stage 2 is **half-delivered and unblocked**: scorer calibrated, conformance layer green, instrument bugs burned down (which was the point of canary-first sequencing — hypothesis B vindicated), pilot shows parity-at-lower-cost with auditability. The seat-flip decision still waits on the full AC-003 run.
