# RRF fusion is unweighted and arm-seeding is rank-blind — small-k relevance quality rests on a fetch-width floor

## Context

While fixing #36 (v1.9.0), adversarial verification surfaced a pre-existing weakness in the retrieval fusion layer (finding F-V1, `fix/recall-starvation-36` campaign):

- `rrf_merge` fuses arms **unweighted**: a record matched by many weak arms can outrank a record ranked #1 by the single arm that actually fits the query (two single-arm rank-1 entries tie at exactly 1/61).
- Arm seeding was historically sized by raw `k` (`seed_ids = dense_ranking[:k]`), so small `k` shrank the *ranking universe*, not just the response.

v1.9.0 contains a **guard, not a cure**: seam 3b decouples fetch width from the response cap (`fetch_width = max(k, FETCH_WIDTH_FLOOR=10)` under `recall_relevance_primary`). That makes the fresh-crystal regression unreachable at small `k`, but the underlying fusion is still rank-blind across arms.

## What to consider

- Weighted RRF (per-arm weights, or query-conditional weighting: distinctive-token queries should weight the lexical arm up).
- Seeding graph expansion from the *fused* order rather than the dense arm alone.
- Whether `FETCH_WIDTH_FLOOR` should scale with corpus size.

## Acceptance sketch

A distinctive-token query whose target is BM25-rank-1 but dense-rank-4 should win fusion at any `k`, without relying on the fetch-width floor.

Refs: `mcp-server/src/crystalium/aetheryte/retrieve.py` (`rrf_merge`, `rrf_merge_scored`, seam 3b), campaign artifacts in the Eidolons nexus under `.spectra/changes/crystalium-recall-starvation-36/` (verification.md F-V1, deliberation.md DP-R1).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
