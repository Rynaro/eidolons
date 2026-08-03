# Issue #36: recall: newly committed crystals are unretrievable — single-slot budget + importance-dominated ranking starves importance=0.0 writes

## Summary

`commit` succeeds but the committed crystal is then **unretrievable via `recall`** — including when the query is composed of exact, distinctive substrings lifted from that crystal's own `summary`. Across ~9 `recall` calls in one session, every call returned an *unrelated* older record and never the newly committed one.

Net effect: `commit` behaves as write-only storage. Because it returns `{"status": "committed", "id": ..., "content_ref": ...}`, the failure is completely silent at write time and only shows up as "memory has no record of this" in a later session — which is indistinguishable from never having committed at all.

## Environment

- Crystalium wired as an MCP server via `.mcp.json` (`mcpServers.crystalium`), driven from Claude Code
- Caller trust tier: **T2**
- Single project scope, passed identically to both `commit` and `recall`: `{"project": "<redacted>"}`
- Layers exercised: `episodic` (commit + update), `procedural` (commit)

## Observed behaviour

Every `recall` call in the session, regardless of query or `k`:

- returned **exactly one** record, never more, with `k` values of 3, 4, 5, 6, 8, 10 and 15
- reported `total_tokens` of ~500–720 and a `slot_breakdown` where `episodic` held the entire budget
- reported `evicted_count` between 2 and 14

The single returned record was, across different queries, one of only ~5 distinct old records — and in each case it was topically unrelated to the query. Queries about a CI/container-build topic returned records about unrelated feature specs and a code-review grounding-facts record.

`importance` on the returned records ranged ~0.15–0.42. **Every freshly committed record came back with `importance: 0.0`.**

`slot_breakdown.procedural` was `0` even on a query that matched a just-committed `procedural` crystal closely, so that layer appears not to have been allocated a slot at all rather than losing on score.

`score` was `null` on every returned record, so I could not inspect ranking directly.

## Reproduction

1. `commit` an episodic crystal containing several distinctive, low-frequency tokens (I used repo branch names and an internal tag string that appear nowhere else in the corpus). Note the returned `id` and `importance: 0.0`.
2. `recall` with `scope` identical to the committed crystal's scope, and a `query` consisting of those exact distinctive tokens, `k: 5`.
3. The new crystal is not returned. An unrelated older record is returned instead, with `evicted_count > 0`.

## What I ruled out

**Not a size problem.** My first crystal had a ~1,500-token `summary`, larger than the whole observed slot budget, so I assumed it simply could not fit. I used `update` to shrink it to ~300 tokens and split the detail into two smaller companion crystals. Retrieval behaviour did not change — the shrunk crystal is still never returned. So oversized summaries are not the cause (though see the suggestion below about surfacing that case).

**Not a scope mismatch.** The same `scope` object was used for `commit` and `recall`, and the records that *do* return come back under that same scope.

**Not a write failure.** `commit` returned `id` + `content_ref`; `update` correctly reported `supersedes` pointing at the prior id.

## Hypotheses

1. **Ranking is dominated by `importance` rather than query relevance.** New crystals land at `importance: 0.0`, so they can never win a slot against records that have accumulated access history — a cold-start starvation problem. The fact that returned records are consistently *topically unrelated* to the query suggests the BM25/dense relevance component is contributing little or nothing to the final ordering.
2. **The per-call slot budget is effectively capping at one record.** `k` appears to have no influence on the number of records returned; a ~500–700 token budget against ~500-token summaries yields exactly one slot. If that budget is fixed rather than derived from `k`, then `k` is misleading as an API and recall is structurally limited to a single record per call no matter how many relevant crystals exist.

If both hold, they compound: one slot, awarded by accumulated importance, which new writes have none of.

## Suggestions

- Give query relevance decisive weight over `importance`, or floor new crystals above 0.0 / apply a recency boost so they are reachable before they have any access history.
- Make the slot budget scale with `k`, or document that `k` is an upper bound subject to a token budget and return that budget in the response.
- Populate `score` in `CrystalSummary` so ranking is inspectable from the client side.
- Consider having `commit` warn when a `summary` exceeds what a single recall slot can hold — it is currently accepted silently.

## Two smaller things noticed in passing

- `provenance.source` rejects `"session"` with a Pydantic `literal_error`; the accepted values are `human` / `verified_agent` / `unverified_agent` / `environment`. The enum is only discoverable by triggering the error, since the tool description doesn't list it.
- `commit` to `semantic` from a T2 caller returns `TIER_VIOLATION` with `advice: "Use a lower-trust layer or escalate caller identity above T2"`, but there's no documented mechanism for escalating caller identity. Falling back to `procedural` worked and set `validation_state: "candidate"`, which seems like the intended path — worth saying so in the advice string.

