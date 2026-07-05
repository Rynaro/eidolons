# Acceptance criteria — RAMZA Stage-2 measurement (EARS)

### AC-001 (state-driven)
GIVEN a host model that has not yet scored the anchor plans this session
WHEN any rubric-dependent Stage-2 measurement is about to run
THEN ramza-calibrate reports verdict "calibrated" for that model
VERIFY: bin/ramza-calibrate --anchors anchors --scored <model-scores>.json ; exit 0

### AC-002 (event-driven)
GIVEN the ramza canary DSL missions including rightsize-gate and drift-tamper
WHEN `eidolons canary ramza` completes
THEN every MUST-level validation criterion passes
VERIFY: canary scorecard JSON shows zero MUST-level failures

### AC-003 (event-driven)
GIVEN the budget-matched planner-seat H-WIN task set
WHEN the ramza@0.2.0 vs spectra@4.11.0 A/B completes
THEN ramza's pass² on the holdout-gated set is non-inferior to spectra's
VERIFY: scorecard baseline-diff report, non-inferiority margin recorded pre-run

### AC-004 (ubiquitous)
GIVEN any Stage-2 A/B run
WHEN the run's artifacts are archived
THEN the run's ramza-adherence composite is present in the archived scorecard
VERIFY: jq '.adherence.composite' on each archived run scorecard

### AC-005 (unwanted-behavior)
GIVEN the frozen Stage-2 execution scope
WHEN Stage-2 work modifies files outside evals/, .spectra/research/, or .spectra/plans/
THEN ramza-drift reports the uncovered paths and the run is flagged for scope review
VERIFY: bin/ramza-drift --state <state> --range <base>..<head> ; exit 1 on violation
