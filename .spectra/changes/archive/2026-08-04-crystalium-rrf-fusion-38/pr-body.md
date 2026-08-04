## Weighted RRF fusion + derived-family merge + arm-order determinism — v1.10.0

Fixes #38.

### The defect

`rrf_merge` fused arms unweighted, and the graph + completion arms are both *derived
from* the dense arm's neighbourhood — so the dense arm effectively voted three times.
Measured live in the shipped eval fixture: a record with **zero lexical match**
(spoke1, fused 0.0450) outranked the exact-match hub (BM25 rank 1 + dense rank 1,
fused 0.0328) — the exact P1 inversion #38 names. v1.9.0's `FETCH_WIDTH_FLOOR` was a
guard, not a cure (per #36's DP-R1, which deferred the root to #38).

### The fix (flag `recall_weighted_fusion`, default ON, subsumed by `recall_relevance_primary`)

- **D1/D2 — derived-family merge**: `graph_ranking` + `completion_ranking` collapse
  into ONE derived voter by min-rank before fusion (`derived_family_merge`), fused at
  `fusion_weight_derived = 1.0`. With the family inactive the fusion is **measured
  bitwise-identical** to v1.9.0 (20/20 comparisons, max score diff exactly 0.0).
- **D3 — query-conditional sparse boost**: `w_sparse = 1 + α·(1 − n_sparse/N_scoped)`,
  populations **active-only on both ends** (tracking `recall_active_only`), numerator
  counted within `sparse_ranking` (no status predicate on the shared `bm25_search`),
  censoring on the **raw** count so a censored fetch can never draw a boost.
- **D5 — arm-order determinism**: consumer-side sorts on `neighbor_expand` /
  `decaying_walk` output (unconditional). This is the *ordering* half of the #36-era
  flakiness; the *membership* half is a pre-existing store bug, now filed as #41.
- **D7/D8 — observability**: `CrystalSummary.score` is now the weighted fused value
  (semantics change, documented in the manifest + CHANGELOG), with a full
  `explain.fusion` object (`w_sparse`, `n_sparse`, `n_scoped`, `n_scoped_layers`,
  `n_scoped_status`, `fetch_width`, `candidate_k`, per-arm weights).
- Config: 4 new fields wired into env **and** YAML allowlists (both sources tested).

### Why these choices (measured, not modelled)

The campaign's binding real-stack measurement (26 gate runs; archived in the nexus
change folder) settled the design after three successive *models* of the dense arm all
proved wrong:

- Static per-arm down-weighting (the "obvious" weighted RRF) **fails the shipped
  retrieval gate at 6/6 hash seeds** (F1 0.4615 → 0.3077): spoke2's only vote is the
  completion arm, and down-weighting it evicts the multi-hop target.
- `fusion_weight_derived = 0.95` is not a margin trade but a **flake** — red at
  `PYTHONHASHSEED=5` only (the completion rank it depends on is hash-random until #41
  lands). 1.0 passes 7/7 and carries the bitwise identity property.
- The issue's own acceptance sketch (a 3-arm competitor at dense rank 1–3) is
  structurally unbuildable — seeds are excluded from their own derived arms (#42) —
  which makes "a base-arm rank-1 record cannot be outvoted by derived-only votes" a
  theorem of the family merge, not a bolted-on guard.

### Guard-vs-cure, demonstrated

With the floor lowered to `1` (far below shipped), the target still holds fused rank 0
at k ∈ {1,3,5}, unanimous across 5 seeds — and the falsifiability precondition was
measured too: the *reverted* build fails the same probe, so the test can actually
fail. The floor stays shipped at 10 for eval reproducibility (corpus scaling is #47's
question — the measured ceiling is `candidate_k`, not the floor).

### Verification (maker≠checker, ESL full tier)

Spec: 42 frozen acceptance criteria (5-revision tamper-evident amend chain), 4
adversarial critique rounds, FORGE-ruled decision points, independent VIGIL
verification: round 1 **FAIL** (a determinism gate could not fail on its own defect —
fixed by measuring 201 candidate fixture id-sets and pinning one with a recorded
disagreeing seed pair), delta round **PASS-WITH-FINDINGS**:

- **40 green / 0 red / 2 INDETERMINATE** (AC-138/139, criteria-legal per their own
  escape hatch; attribution measured and disclosed — see #48).
- Full suite **950 passed / 4 skipped / 1 xfail (strict, by design) / 0 failed**.
- #36 non-regression re-measured on the real embedding stack: fresh crystal at
  position 0 in every flag-on cell, k ∈ {1,3,5,10} × 2 runs, byte-stable.
- Retrieval gate byte-identical before/after at seeds {0,1,5} (non-inferiority
  tripwire reading — the fixture's known confound is #43).

### Known limitations (disclosed in CHANGELOG + BENCH-NOTES)

- `neighbor_expand` expands only the first seed (pre-existing, **#41**, high) — every
  eval figure here was measured on a one-seed expansion; #41 mandates a re-baseline.
- Cross-layer rank blocking unchanged (**#45**); `evals/fusion_gate.py` lands the
  measuring axis first, per the spec's sequencing condition.
- AC-138/139 floor-inflation pair recorded-not-discharged (**#48**, deliberate
  disclosed trade-off protecting the reliability of a contingency gate).

Follow-ups filed before this tag: #41 #42 #43 #44 #45 (MUST) + #46 #47 #48.

Campaign artifacts (spec, criteria, critique, deliberation, measurement,
verification) live in the Eidolons nexus under
`.spectra/changes/crystalium-rrf-fusion-38/`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
