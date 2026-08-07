# Baseline capture (VP-B1..VP-B5) — crystalium @ b7f1a47

Captured 2026-08-05, container-only (`docker compose run --rm crystalium`), bind mount active.
This baseline never existed before (Kupo K-N13); the plan made it a Wave-0 entry precondition.

| id | measurement | result | verdict |
|---|---|---|---|
| VP-B5 | `git rev-parse HEAD` | `b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc` | matches required `b7f1a47` |
| VP-B1 | `make test` | `998 passed, 2 skipped, 1 xfailed` in 848.76s | GREEN |
| VP-B2 | `make test-ci` | `994 passed, 6 skipped, 1 xfailed` in 299.41s | GREEN |
| VP-B3 | fusion-gate x 7 seeds | 7/7 `gate_pass: true`, `weighted.target_rank == 0` on all 7, one distinct verdict | GREEN — **S-6 does not fire** |
| VP-B4 | `retrieval-gate` | SKIP_SLOW=1 -> `verdict: "inconclusive"`, `gate_pass: null`; default -> `gate_pass: true` | as predicted — honesty branch works |

## S-9 check (make test vs make test-ci)

They differ in COUNTS (998/2 vs 994/6) but not in OUTCOME: both green, zero failures, zero
errors. The 4-test delta is SKIP_SLOW converting slow tests to skips. S-9 fires on
DISAGREEMENT (one green, one red), which did not occur. Recorded so the delta is not
rediscovered later and misread as drift.

## Method notes (two capture defects found and corrected)

1. **Exit-code capture failed silently.** The first attempt wrote `### VP-B1 exit: ${PIPESTATUS[0]}`
   inside a redirected group; it expanded EMPTY for both suites. The green verdict above rests on
   the pytest summary lines (`998 passed` / `994 passed` with no `failed`/`error` token anywhere in
   either capture), not on a captured exit status. Stated plainly rather than implied.

2. **structlog contaminates stdout** — see `kb15-stdout-contamination.md`. The first VP-B3 attempt
   returned `rc=0` on all 7 seeds with an EMPTY `gate_pass`, because `| jq` hit a parse error on the
   log lines preceding the JSON. Re-captured with `awk '/^\{/{f=1} f'` extraction. **This affects
   8 shipped acceptance criteria** and must be fixed in the amendment.

Both defects share one shape: a command that exited 0 while telling us nothing. Neither would
have been caught by reading the plan.

## VP-B4 settles spec.md §0.3 by measurement, not by reading

§0.3 is the load-bearing justification for building all four new gates on the **fusion-gate**
template rather than the retrieval-gate template. It is now MEASURED:

```
CRYSTALIUM_SKIP_SLOW=1  ->  {"verdict": "inconclusive", "gate_pass": null}    rc=0
default (real embedder) ->  {"verdict": "completion lifts multi-hop F1...", "gate_pass": true}  rc=0
```

A gate built on the retrieval-gate template therefore contributes **nothing** under `make test-ci`,
which is the mode CI actually runs. §0.3 is CONFIRMED and NC-3 stands.

**Trap recorded:** the CI-mode result is `gate_pass: null`, not `false`. Any criterion written as
`jq -e '.gate_pass != false'` passes on it. This is the campaign's named recurring defect
("two acceptance criteria once exited 0 while comparing null to null") sitting live in the
baseline artefact. Every criterion in the amendment must assert the POSITIVE value
(`== true`), never the negation of the failure value.
