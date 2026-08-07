# v2.1.0 — GitHub Actions did not run; CI's exact invocation reproduced locally instead

## What happened
PR #62 (`release/v2.1.0`) opened MERGEABLE with **no checks reported**. PR #61 had received
four green checks about an hour earlier on the same repo, `actions/permissions` reports
`{"enabled": true, "allowed_actions": "all"}`, and `ci.yml` triggers on `push: branches: ["**"]`
and `pull_request: branches: [main]` — so the branch push should have triggered it. No run was
created at all (`/actions/runs` shows nothing for this branch). Most consistent with an
exhausted runner-minutes quota. Not something this campaign can force.

## Why "make test / make test-ci are green" was NOT sufficient
K-N11 established that **`make test-ci` is not CI's invocation**:

| | invocation | source of truth | PYTHONPATH |
|---|---|---|---|
| `make test-ci` | `docker compose run` | bind mount `.:/app` shadows the image | `/app/mcp-server/src:/app` |
| **CI** | `docker run` on the **baked** image | image contents | `/app/src:/app` |

Same test set, different source of truth. A bind-mounted run cannot detect a packaging or
baked-source defect. The campaign's own memory records cached images hiding dependency breaks
for weeks while every local target stayed green.

## What was run instead — CI's literal steps
```
docker compose build crystalium                      # ci.yml "Build dev image"
docker run --rm -e CRYSTALIUM_SKIP_SLOW=1 \          # ci.yml "Run pytest suite", verbatim
  crystalium:dev pytest tests/ -v --tb=short -p no:cacheprovider
```
Result: **1093 passed, 8 skipped, 1 xfailed, EXIT=0**, 0 `FAILED`/`ERROR` lines.

### The baked source was ASSERTED, not assumed
A stale image would produce a convincing green for the wrong tree, so the image was interrogated
before the result was accepted:
```
metadata version:                        2.1.0
baked _FALLBACK_VERSION:                 2.1.0
baked recall_seed_derived_credit default: False    <- FORGE's ruling is in the image
baked has sparse_topup:                  True      <- #44 is in the image
```

### A false start, recorded
The first attempt used a guessed image name and returned **exit 125** —
`pull access denied for wt-checker21-crystalium`. That is a docker error, not a test result:
the suite never ran. Had the exit code been read as "non-zero, therefore red", or worse had
stderr been discarded, it would have been indistinguishable from a real failure. Compose pins
`image: crystalium:dev` explicitly regardless of project directory.

## Honest limits
This reproduces the `pytest (container)` job only. CI's other three jobs — conformance suite,
JSON schema validation, install.sh idempotency — did **not** run and were **not** reproduced
here. They passed on PR #61 (v2.0.2) and this batch touches no installer, schema or conformance
surface, but that is an argument, not a measurement.

**Follow-up:** re-run CI on `main` once runner minutes are available, and confirm all four jobs
green post-merge. If any of the three unreproduced jobs fails, this release needs a fix-forward.
