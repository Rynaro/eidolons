# v2.0 Audit — Crystalium Runtime Memory Defects (live store, 2026-07-02)

> Orchestrator-verified against the live project store `~/.crystalium/eidolons`
> (created 2026-06-24; 9 crystals, 40 tool_calls, 15 dream_runs). Not a code audit —
> a *consumption-side* audit of what recall actually returns.

## Symptom

`crystalium_recall(scope={project: eidolons}, query=…)` returns **zero records for every
query tried**, including exact-token matches against stored summaries ("plan_checkpoint")
and layer-pinned queries. The store is not empty.

## Store contents

- 8 execution-layer plan checkpoints — **all `status: deprecated`** (7 riverdale-migration,
  1 eidolons/eidolons-v2-go-migration).
- 1 episodic crystal, `status: active`, scope `project: "eidolons-v2-go-migration-2026-06-24"`.
- `embedding_ref` is **null for all 9 crystals** — no vectors were ever computed
  (vectors.lance exists but is unused).

## Three compounding defects

1. **Lifecycle over-deprecation.** The *only* checkpoint for the eidolons v2 plan is
   `deprecated` (plausibly by session_end/Dream consolidation — 15 dream_runs — or a
   checkpoint-supersede rule firing wrongly on a single-checkpoint plan). Recall filters
   deprecated ⇒ the plan is permanently invisible to agents. Nothing ever re-surfaced it.
2. **Scope-key fragmentation.** Writers used `project: eidolons`,
   `project: eidolons-v2-go-migration-2026-06-24`, and `project: riverdale-migration`
   in the same store. There is no canonical project-key derivation (e.g. from cwd or
   eidolons.yaml), so scope-filtered recall silently partitions memory.
3. **Recall signal starvation.** Summaries are terse machine labels
   (`plan_checkpoint:08234787`); blob content (rich JSON) is not FTS-indexed; embeddings
   never computed. Hybrid BM25+dense+graph recall therefore operates on ~2 tokens of BM25
   with no dense arm. Even correct-scope, correct-status queries would rank on noise.

## Consequence (proven by incident)

The 2026-06-24 v2.0 Go-migration TRANCE plan (complexity 10/12, 16 acceptance criteria,
4 ECL envelopes) is unrecoverable: its file artifacts were never committed to git and its
memory trace is a deprecated checkpoint plus an active-but-misscoped digest that recall
cannot rank. **The system's own flagship project lost a frontier-model plan.** This is the
exact failure mode v2.0 must eliminate: memory-by-luck even with the memory system installed.

## v2.0 implications

- Recall must have a **fail-loud diagnostic** (`memory preflight --explain`: n candidates,
  filtered-by-status n, filtered-by-scope n) instead of silent empty results.
- Canonical project-key derivation must be mechanical (one function, used by every writer).
- Summaries must be sentence-grade at write time (schema-enforced min length / content
  requirements), because summaries are the only indexed text.
- Embedding computation must either work or be visibly reported as degraded
  (doctor probe: "N crystals, M embedded, dense arm INACTIVE").
- Deprecation rules need a "never deprecate the last checkpoint of a plan" guard.
- Plan/spec artifacts must ALSO live in committed files (ESL change dirs), with crystalium
  as index — not as the only copy.
