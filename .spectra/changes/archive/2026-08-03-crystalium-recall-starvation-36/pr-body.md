## Summary

Closes #36 — `recall` starved freshly committed crystals: they landed at `importance: 0.0`, the composer's eviction ordering considered **only** `(importance, last_access, id)` (query relevance never participated), `k` never capped anything (it only sized the candidate fetch), and `score` was structurally always `null`. Net effect: `commit` behaved as write-only storage, silently.

## What changed

**Retrieval (gated by `Config.recall_relevance_primary`, default ON — one flag, three seams + fetch width):**
- Seam 3 — `k` is now a real response cap: candidates truncate to the top-`k` of fused relevance before composition.
- Seam 3b — fetch/seed width decoupled from the cap: arm seeding uses `max(k, FETCH_WIDTH_FLOOR=10)`, so small `k` no longer shrinks the ranking universe (the response slice is the only consumer of caller `k`).
- Seam 4 — eviction ordering is relevance-primary: `(relevance_score, importance, last_access, id)`.
- Seam 5 — records emit in descending relevance (`id` tiebreak).
- Flag OFF restores the pre-fix composition byte-identically (and does not cap at `k`).

**Ungated companions (both modes):**
- `CrystalSummary.score` now carries the raw fused RRF score — ranking is inspectable.
- `RecallResult.budget` object: `{total_cap, slots, k_requested, k_applied, truncated_count}`; `k_applied`/`truncated_by_k` also in `explain`. `truncated_count` is derived from the actually-performed slice (never from intent); `evicted_count` keeps its exact prior meaning.
- Cold-start importance: commits now call the (previously dead) `importance_fn`, clamped by `COLD_START_IMPORTANCE_CEILING = 0.30` — under the legacy scorer the unclamped value (0.525) would have *inverted* the starvation. `utility.importance` only; no backfill; the computed value is echoed in the commit result. `execution`'s 0.5 stays (deliberate active-work special case).
- `k` clamped to `[1,100]`; non-coercible `k` degrades to the default 10 (server and CLI entry points).
- Oversized-summary advisory at commit when a summary exceeds its layer's slot cap (advisory-only, exception-safe).
- DX: `provenance.source` enum enumerated in the commit tool description; `TIER_VIOLATION` advice names the procedural fallback and makes no T2→semantic promotion promise (T2 candidates stay candidates per gate G2).
- Schema drift fixed: `schemas/recall-result.v1.json` gains `budget` (strict) and the previously missing `explain` (loose, diagnostic), with an unconditional-import jsonschema round-trip test.

## Evidence

- **RED-first**: the regression suite (`test_recall_starvation.py`, 40+ tests) was committed first and demonstrably fails at `af24493` (v1.8.1) — both as a collection `ImportError` and, under symbol shims, on each headline assertion for the right semantic reason. The seam-3b small-`k` test was likewise RED at the pre-patch HEAD.
- **Full suite**: 900 passed, 2 skipped (pre-existing root-permission skips), 0 failed.
- **Slow eval gates** (retrieval/evb/forgetting/prefetch/dream): 14 passed.
- **Adversarial verification (maker≠checker)**: two independent fresh-context attestations; induced-defect attacks on every load-bearing gate (schema round-trip, relevance-primary eviction, cold-start ceiling, k-cap, output ordering, slice-derived accounting) each turned the named test RED.

### `python -m evals retrieval-gate` — before (af24493) / after

| axis | before | after |
|---|---|---|
| multihop_f1.flat | 0.1212 | **0.3077** |
| multihop_f1.completion | 0.1765 | **0.4615** |
| context_rank (flat/context/both) | 2/2/4 | 2/2/4 (run-varying axis; non-gating) |
| completion_pass / context_pass / gate_pass | true / false / true | **unchanged** |

<details><summary>Raw eval JSON (before)</summary>

```json
{"axes":{"multihop_f1":{"flat":0.1212121212121212,"completion":0.17647058823529413,"both":0.17647058823529413},"context_rank":{"flat":2,"context":2,"both":4}},"graph_ok":true,"completion_pass":true,"context_pass":false,"gate_pass":true}
```
</details>

<details><summary>Raw eval JSON (after)</summary>

```json
{"axes":{"multihop_f1":{"flat":0.30769230769230765,"completion":0.4615384615384615,"both":0.4615384615384615},"context_rank":{"flat":2,"context":2,"both":4}},"graph_ok":true,"completion_pass":true,"context_pass":false,"gate_pass":true}
```
</details>

## Behavior notes

Default recall composition changes for every consumer (that is the fix). `recall_relevance_primary: false` restores the previous behavior exactly. Version: **1.9.0** (minor; the revert flag is why this is not a major).

Spec lifecycle: ESL change `crystalium-recall-starvation-36` (Eidolons nexus), full tier — RAMZA spec (32 frozen EARS criteria, tamper-evident amend chain), FORGE-deliberated trade-offs, independent critic, dual VIGIL attestations.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
