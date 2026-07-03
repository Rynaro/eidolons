# evals/results/ — the scorecard store

This directory is written by `eidolons eval swe --matrix <arms.json>` and is
**committed** — it is the persistent, diffable measurement log the H-WIN
campaign (and any future eval matrix) reads from.

## What lands here

For every arm in an `arms.json` (schema: `../../schemas/eval-arms.schema.json`),
the matrix runner writes one scorecard:

```
evals/results/<UTC-date>-<suite>-<label>.scorecard.json
```

- `<UTC-date>` — `date -u '+%Y-%m-%d'` at run start.
- `<suite>` — the suite file's basename without `.yaml` (e.g. `swe-suite`,
  `kupo-keep-suite`).
- `<label>` — the arm's `label` from `arms.json`.

After every arm has run, one matrix summary is written alongside them:

```
evals/results/<UTC-date>-<suite>-matrix.json
```

It compares every non-control arm against the first `control: true` arm:
resolved-rate delta, pass^k delta, and a per-task flip table (newly-resolved /
regressed). Scorecards conform to `../../schemas/eval-scorecard.schema.json`.

Re-running the same `(date, suite, label)` on the same UTC day overwrites the
prior file for that day — this store is a daily log, not a run-by-run
archive. Pass `--no-store` to `eidolons eval swe --matrix` to skip writing
entirely (useful for local iteration).

## Reading the store

`eidolons eval baseline <suite> [--label <l>] [--against <file>]` diffs the
two most recent scorecards for a `(suite, label)` pair (or the latest vs an
explicit `--against` file) and exits non-zero (5) on regression. See
`eidolons eval baseline --help`.

## ⚠️ Smoke scorecards are NOT capability claims

A scorecard with `harness.smoke: true` was produced by `--matrix --smoke`:
every arm's fix was the suite's own `gold_fix` reference patch, not a model.
A 100% `resolved_rate` there proves the ORCHESTRATION works end-to-end
(arm dispatch → suite run → scorecard shape), never that a model solved an
unseen task. This is exactly the same honest-scope distinction
`evals/swe-suite.yaml` and `evals/kupo-keep-suite.yaml` already document for
the underlying `eidolons eval swe` harness — it just also applies per-arm
here. Only `harness.smoke: false` scorecards (a real `--fix-hook`, e.g. one
of `evals/hooks/keep-bare.sh` / `evals/hooks/keep-system.sh`) are evidence
for a headline claim like H-WIN.
