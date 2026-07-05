# AC-003 Pre-registration — Planner A/B, ramza@0.2.0 vs spectra@4.11.0

> Committed BEFORE any A/B run of this suite executes; the commit hash of this file
> is the pre-registration timestamp. Suite: `evals/planner-ab-suite.yaml` (6 tasks:
> AB-T1..T4 public, AB-H1..H2 holdout). Plan of record:
> `.spectra/plans/2026-07-04-ramza-stage2-measurement.md` (frozen criteria 423248b6…).

## Protocol

- **Arms:** spectra@4.11.0 (installed at a dedicated consumer project) vs
  ramza@0.2.0 (installed at a dedicated consumer project). Same executor model for
  both arms (Sonnet 5), same mission text verbatim, same instruction shape ("read
  your installed agent.md, follow your methodology, produce the specification").
  Executors never see the rubrics.
- **k = 2** independent runs per (task, arm) → 24 runs total.
- **Primary metric:** per-task pass² (both runs pass all MUST rubric items),
  graded mechanically by `eidolons eval quality grade --suite-file` (grep-based,
  no LLM judge). Aggregate = number of tasks with pass² true, out of 6.
- **Non-inferiority margin (the claim being tested):** RAMZA is non-inferior if
  `ramza_tasks_pass2 >= spectra_tasks_pass2 - 1`. Superiority is NOT claimed at
  this sample size regardless of outcome.
- **Holdout gating:** AB-H1/AB-H2 were authored in the same commit and excluded
  from any tuning; the aggregate claim is void if either arm's holdout results
  diverge in direction from its public-task results by more than 1 task
  (overfitting guard, Vivi Stage-2 shape). Honesty note: the suite author (Fable 5)
  can see the holdout rubrics; blindness applies to the executor sessions, which
  receive mission text only.
- **Secondary metrics (descriptive, not gated):** mean words per artifact
  (ceremony), count of machine-verifiable gate citations (audit-trail density),
  `ramza-adherence` composite where a state file exists, confidence verdict
  distribution.
- **Budget matching:** one executor session per run, no retries, no
  cross-pollination between runs (fresh agent context each).
- **Exclusions:** a run that fails for infrastructure reasons (tool crash,
  truncated output file) is re-run once and noted; content failures are never
  re-run.

## Decision rule

- Non-inferiority met + holdout consistent → AC-003 **PASS**; Stage-3b seat-flip
  proposal proceeds (with these numbers quoted, not embellished).
- Otherwise → AC-003 **FAIL**; ramza stays `in_construction`, gaps analyzed,
  re-measure after fixes. No partial credit.
