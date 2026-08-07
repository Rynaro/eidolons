# Drift check at record-close — 2 undeclared source files, ESCALATED then resolved

Run 2026-08-07 as the `verified -> archived` precondition. **The check had never been run.**
It found real drift on the first execution.

## Verdict 1 — MISMATCH (escalate to `in_progress`)

Comparing `declared_scope` (frozen `2026-08-05T21:35:48Z`) against the actual tree
`b7f1a47..d243789` (campaign base v2.0.1 -> shipped v2.1.0): 27 paths changed, **25
in-scope, 2 out-of-scope.**

| path | diff | what it does |
|---|---|---|
| `mcp-server/src/crystalium/server.py` | +15/-2 | wires `recall_seed_derived_credit` from config into `_build_components`; widens `_NullGraphStore.neighbor_expand` / `decaying_walk` signatures to match `graph.py`'s new `rel_filter` / `exclude_seeds` params |
| `mcp-server/src/crystalium/__main__.py` | +1 | wires `recall_seed_derived_credit` from config into the CLI recall path |

Neither file appears in `declared_scope`. Neither appears in FORGE D2's authoritative site
table, which enumerates **`graph.py` only** (`:225`, `:271`, `:272`, `:302`, `:305`, plus
docstrings at `:203`, `:247`, `:292`, and `:266` deliberately unchanged under a proof
obligation).

## Why this is a scope-DECLARATION defect, not scope creep

Three things were established before the verdict was resolved, each by measurement:

1. **The changes are required consequences of in-scope changes.** `#42` adds
   `recall_seed_derived_credit` to `config.py` (in scope) and new parameters to `graph.py`
   (in scope). A config flag that no production entry point passes through is dead; a
   `_NullGraphStore` whose signature does not match the real store breaks the no-graph path
   specifically — the path least likely to be covered.
2. **The implementation named the sites openly.** `retrieve.py:396` carries a comment
   naming `server.py` and `__main__.py` as the explicit wiring sites. This was never hidden;
   it simply never propagated back into `declared_scope`.
3. **The wiring is verified, not merely present.**
   - `test_weight_discrimination.py:235` asserts `result["recall_seed_derived_credit"] is True`
     — a readback off the instance, so the flag is proven to *arrive*, not just to be passed
     (K-C-N6, "the weight readback becomes a real pin").
   - `test_config.py:534` covers the config surface.
   - `_NullGraphStore` is exercised by 7 test files (`test_completion`, `test_cli`,
     `test_recall_cli`, `test_context_match`, `test_diagnosability`, `test_graph_export`,
     `test_storage_graph`).
   - The v2.1.0 wire check (AC-361) reports **0 differences** vs v2.0.2 across all 9 tools,
     all `inputSchema`s and all 4 `isError` paths — so `server.py`'s external surface did
     not move.

`declared_scope` was frozen at `2026-08-05T21:35:48Z`. FORGE D2 and Kupo's K-B2 — which
between them defined #42's threading — landed **after** that freeze. The scope declaration
was never widened to match a design that had legitimately grown.

## Resolution

`declared_scope` (plan-state.json) and `files_touched` (spec.yaml) are amended to include
both paths, with this finding recorded rather than absorbed.

**This artifact is the control on that amendment.** Widening a scope declaration until the
drift check goes green is precisely the "gate that cannot fail" species this campaign
exists to document. What makes this amendment legitimate and not vacuous:

- the mismatch verdict is recorded permanently here and in the manifest's drift history,
  not overwritten;
- the two paths were justified on evidence **before** the scope was widened, not after;
- the amendment is additive-only — no criterion, threshold or assertion changed;
- had either file contained behaviour unrelated to `#42`'s flag, the correct outcome would
  have been ESCALATE and stay escalated.

## Verdict 2 — clean, against the corrected declaration

Re-run after the amendment: 27 changed paths, 27 in scope, 0 mismatches.

## The lesson

`declared_scope` is frozen at plan time; the design keeps moving through the amendment
chain. Nothing reconciled the two until the archive gate forced it — **five amendments and
two shipped releases later.** This is the same shape as the ECM campaign, whose ESL record
sat unmoved for five releases and whose first drift check also found real drift behind a
fully green suite.

A drift check deferred to archive time is a drift check that cannot influence the work it
describes. It should run at every `in_progress -> verified` hop, not once at the end.
