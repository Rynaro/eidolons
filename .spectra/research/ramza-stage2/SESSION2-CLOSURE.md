# RAMZA Stage-2 — Session 2 Closure

> 2026-07-05 · Fable 5. Continues `RESULTS.md` (session 1). Raw outputs + scorecards
> in this directory (`ac003/`, `raw/`, `canary-*.scorecard.json`).
> Session ended against API session/spend limits mid-measurement; this closure
> reports exactly what completed and adjudicates strictly per
> `AC-003-PREREGISTRATION.md`. Nothing below is extrapolated.

## AC-002 — Canary conformance: **CLOSED, 7/7 missions PASS, 0 MUST failures**

| Mission | pass / fail / inconclusive |
|---|---|
| smoke-default | 11 / 0 / 0 |
| rightsize-gate | 7 / 0 / 3 (`SHOULD NOT` DSL gap — parked) |
| drift-tamper | 9 / 0 / 1 |
| dual-format | 10 / 0 / 0 |
| memory-round-trip | 10 / 0 / 0 (graceful-skip path; CRYSTALIUM honestly probed absent) |
| discovery-elicitation | 8 / 0 / 2 |
| parallel-spec-trance | 10 / 0 / 0 (full G3 cycle incl. real clean-context branch fan-out) |

Two more mission-authoring defects fixed en route (Ramza main): the escaped-backtick
yaml-fence criterion (→ heading match) and a prose annotation outside the backticks
on the provenance criterion (→ OR-alternation regex). Both are the same lesson:
criteria are DSL, not prose.

## AC-003 — Planner A/B: **INCOMPLETE — not adjudicated (no claim made)**

The pre-registered protocol requires k=2 per (task, arm) across 6 tasks including
2 holdout. API limits terminated 15 of 24 runs (12 wave-2 runs entirely; 3 ramza
r1 runs mid-Assemble after their critic loops — infrastructure-failure class per
the pre-registration, re-runnable). What completed, graded mechanically:

| Task | spectra pass² (k=2) | ramza pass@1 (k=1) | words: spectra mean / ramza |
|---|---|---|---|
| AB-T1 webhook subsystem | PASS | PASS | 10,560 / 3,690 |
| AB-T2 soft-delete brownfield | PASS | PASS | 8,165 / 3,920 |
| AB-T3 double-charge fix | PASS | PASS | 9,535 / 3,604 |
| AB-T4 / AB-H1 / AB-H2 | not run | not run | — |

- **Zero MUST-item failures in any graded run, either arm.**
- Descriptive only (no gated claim): ramza artifacts averaged **40%** of spectra's
  word count on identical missions with identical rubrics.
- **The decision rule is NOT applied**: holdout consistency is unfulfillable and
  the ramza arm lacks k=2. Per pre-registration: no partial credit, no
  non-inferiority claim. AC-003 remains the open gate for Stage-3b.

## Findings from the multi-agent execution (worth as much as the numbers)

1. **The critic cascade works unprompted.** All three full-tier ramza executors
   independently spawned clean-context critics (maker≠checker honored without being
   told). One critic issued a **cycle-2 FAIL** for a real defect: the AC-004 fix
   existed in the plan's embedded criteria but not in the standalone criteria file —
   the one `ramza-ears-lint` lints and `ramza-freeze` hashes. That is precisely the
   criteria-desync/tamper class RAMZA exists to catch, caught before freeze.
2. **Critic→author routing needs a bus.** Critics could not SendMessage their
   parents (unresolvable names); the coordinator had to broker every verdict.
   Production fix belongs to Junction routing, not prompts. (Nexus backlog item.)
3. **Harness-furniture misattribution, twice.** Two independent executors reported
   "prompt injection embedded in file bytes" (parallel-spec.md, agent.md). Byte-level
   grep of every installed file: clean, both times. The executors attributed genuine
   harness system-reminders in their own transcripts to the files they were reading.
   Agent-epistemics finding; no shipped defect.
4. **Full-tier runs are expensive by design.** Critic loops took ramza T-runs to
   3-6× the wall-clock of lite runs and contributed to hitting the spend ceiling
   mid-wave. The right-sizing doctrine (D3) applies to measurement too: canaries
   first (they cost cents and caught five instrument bugs across two sessions),
   A/B second, full-tier tasks last.

## Completion runbook (one session, post-limit-reset)

1. Re-run 3 infrastructure-failed cells: `AB-T{1,2,3}-ramza-r1` (pre-registration
   allows one re-run for infrastructure failures; label them as re-runs).
2. Run wave 2: `AB-T4`, `AB-H1`, `AB-H2` × both arms × k=2 (12 runs).
3. Grade all via `eval quality grade --suite-file evals/planner-ab-suite.yaml`
   (zero-LLM), apply the pre-registered decision rule, write the adjudication.
4. If PASS: proceed to Stage 3a (v1.0.0 attested release — carries the mission-file
   fixes already on Ramza main) and the Stage-3b seat-flip PR (routing.yaml,
   presets, cortex). If FAIL: gap analysis, fix, re-measure. No partial credit.
