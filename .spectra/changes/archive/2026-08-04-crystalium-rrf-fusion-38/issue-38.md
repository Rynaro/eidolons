# Issue #38: RRF fusion is unweighted and arm-seeding is rank-blind — small-k relevance quality rests on a fetch-width floor

## Summary

`recall()` fuses up to four ranked lists with Reciprocal Rank Fusion, but three compounding defects prevent the query's relevance signal from dominating the fused ranking:

1. **P1 — unweighted fusion.** The fusion sums arms as if they were independent (`score(id) = Σ 1/(60 + rank)`), so a record's score grows with the *number* of arms that mention it, regardless of how well any single arm fits the query. A 3-arm graph neighbor outranks a 2-arm exact lexical match.

2. **P2 — correlated arms.** The graph and completion arms are not independent voters. Both seed from `dense_ranking[:fetch_width]`, making them functions of the dense arm; each vote is dense arm opinion counted directly once and twice more through its own neighborhood.

3. **P3 — non-deterministic rank order.** Graph and completion arms return sets; rank order is set-iteration order, which Python randomizes per process via `PYTHONHASHSEED`. The same query returns different fused rankings across runs.

Worked example from issue's acceptance sketch: target `T` (BM25 rank 1, dense rank 4) vs. competitors `N1..N3` (dense ranks 1–3):

```
today (unweighted): N1 0.049180  N2 0.048387  N3 0.047619  T 0.032018  → rank(T) = 3
```

`T` is the only record the *lexical* arm ranks first and loses to three records it never lexically matched.

## What v1.9.0 shipped, and why it is not a fix

Commit `56c8510` (v1.9.0, CRYSTALIUM #36 campaign) introduced `FETCH_WIDTH_FLOOR = 10` to stabilize which records seed graph/completion expansion. This is a **guard**, not a cure:

- The floor stabilizes *which* records vote (addresses part of P3 on the gated path)
- The floor changes **nothing** about *how much* each vote counts
- P1 remains: unweighted fusion still lets a 3-arm distractor outvote exact matches
- P2 remains: derived arms are still seeded from dense, not from a true base-arm preliminary fusion

The guard's own gate (`test_fresh_crystal_returned_at_k3`) asserts only set membership; its fixture empties the graph and completion arms once `len(seed_ids) > 3`, so the criterion cannot observe P1.

## Context — evidence gaps and anomalies

Three successive models of the dense arm were offered, and all three were wrong:

- Revision 1.0.0 (proposal) modeled both graph/completion spokes absent from dense_ranking
- Vigil's F1 critique corrected it to model them at positions 25/26–29/30
- Real-stack measurement found the truth: spoke1 at dense rank 17, spoke2 absent from dense entirely (30-element cap against 31-crystal corpus)

Measurement fixed this. The issue was: does static per-arm down-weighting (H-A: `w_graph=0.35, w_comp=0.25`) solve it, or does the issue need weighted fusion with query-conditional sparse boost (H-B)?

Answer: H-A fails the shipped evaluation gate at all 6 hash seeds. `f1.completion` collapses 0.4615 → 0.3077 (33% regression), and `gate_pass` goes false. Mechanism: spoke2's only vote is the completion arm; H-A pays it `0.25/62 = 0.004032`, an order of magnitude below the distractor band. Critically, **down-weighting the derived arms cannot demote the top-of-dense competitors the issue names** — any record outside the seed set is structurally barred from derived arms, so the down-weight reaches only multi-hop targets, not the single-hop inversions P1 describes.

## What-to-consider

1. **Weighted RRF mechanism** — replace unweighted summation with per-arm weights, yielding `score(id) = Σ (w_arm / (60 + rank))`. Support per-arm config with sensible defaults (dense 1.0, derived 1.0).

2. **Query-conditional sparse weight** — observe that the sparse arm's value varies with query selectivity: a distinctive-token query narrowing the corpus to 1 record should boost sparse confidence; a generic query returning all records has no signal to act on. Implement `w_sparse = 1.0 + alpha * selectivity` where `selectivity = clamp(1 - n_sparse/N_scoped, 0, 1)` and `alpha` is configurable (default 1.0).

3. **Seed from base-arm fusion, not dense alone** — replace `seed_ids = dense_ranking[:fetch_width]` with `prelim = weighted_fuse(sparse, dense)` then `seed_ids = prelim[:fetch_width]`. This makes graph/completion expansion topic-appropriate (sparse arm participates) rather than embedding-appropriate (dense arm alone).

4. **Merge correlated derived arms** — collapse graph and completion into one voter via min-rank before fusion, correcting P2's triple-counting. `derived_ranking = [cid for cid, _ in sorted(minrank.items(), key=lambda kv: (kv[1], kv[0]))]` where `minrank[cid] = min(minrank.get(cid, inf), rank_in_arm_i)`.

5. **Deterministic rank order** — replace set iteration order with sorted order. Two lines: `sorted(neighbour_ids)` on graph expansion and `sorted(walked.items(), key=lambda kv: (-kv[1], kv[0]))` for completion walk — id-ascending tie-break, not insertion-order.

6. **Diagnosability** — surface the weights and the query signal that produced them in `result.explain.fusion`, including `n_sparse`, `N_scoped`, `selectivity`, and per-arm sizes. Make the denominator's status population explicit (`n_scoped_status: "active_only"` or `"all_statuses"`).

## Known residual

When the target is visible *only* to the sparse arm (dense misses it entirely), no bounded weight reliably outranks a two-arm competitor — the one-arm candidate's signal is insufficient. This is outside the issue's stated acceptance sketch (which specifies dense rank 4, i.e., two arms). No acceptance criterion is written on this scenario; a criterion resting on an exact float tie is a flake generator.

## Acceptance — resolution by crystalium v1.10.0

**Fixed by:** Rynaro/crystalium PR #49, merge `56c8510` → `v1.10.0`, released 2026-08-04.

All four fixes landed and shipped ON via `recall_weighted_fusion=True` (default, subsumed by `recall_relevance_primary`). The issue's acceptance sketch now resolves: target ranks 0 across the selectivity range except the neutral limit (generic query with no sparse signal).

**Follow-ups (numbered #41–#48):** deferring cross-layer rank blocking, corpus-scaling `candidate_k`, and the minor surface refinements.

---

## References

- **Upstream issue:** Rynaro/crystalium#38
- **Specification:** `.spectra/changes/archive/2026-08-04-crystalium-rrf-fusion-38/spec.md` (ramza 1.4.0)
- **Verification:** `.spectra/changes/archive/2026-08-04-crystalium-rrf-fusion-38/verification.md` (vigil, 1152 lines, fresh-context attestation + gate probes + multi-seed forensics)
- **Measurement:** `.spectra/changes/archive/2026-08-04-crystalium-rrf-fusion-38/measurement.md` (26 gate runs + 2 targeted probes; real stack, real evaluation fixture)
- **Deliberation:** `.spectra/changes/archive/2026-08-04-crystalium-rrf-fusion-38/deliberation.md` (FORGE, 9 DP rulings, measurement-driven)
- **Key artifact:** `retrieve.py` weighted RRF functions (`weighted_rrf_merge_scored`), base-arm seeding (D4), deterministic sorts (D5), `explain.fusion` diagnosability
