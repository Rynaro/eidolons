# AC-361 resolution — the wire baseline was STALE, not the product

The v2.1.0 checker REJECTED partly on AC-361: `compare_wire.py` reported **11 unmasked
differences** against the archived golden capture — 9 tool names dropping the `crystalium.`
prefix, `isError` flipping `false→true` on the UNKNOWN_TOOL path, and a differing
`content_ref`. The checker was RIGHT to refuse to wave that through undocumented.

## Root cause: the golden capture is from v1.11.0

Those 11 differences are **deliberate v2.0.0 changes**, shipped months before this campaign:
single-segment tool names and the `isError` semantics change (crystalium #35/#33, tagged
v2.0.0). The archived baseline `golden-wire-v1.11.0.json` predates them. AC-361 was comparing
v2.1.0 against a pre-v2.0.0 wire and correctly reporting that v2.0.0 happened.

The checker independently confirmed via `git diff b7f1a47..HEAD -- server.py` that none of it
is caused by W-45/W-44/W-42.

## The measurement that actually answers AC-361

The meaningful question for a v2.1.0 release is: **does the wire change between v2.0.2 and
v2.1.0?** Captured with the archived `golden_wire.py` driving a real subprocess on BOTH trees:

| property | v2.0.2 (`973ab73`) | v2.1.0 (`d243789`) | identical |
|---|---|---|---|
| tool names (9) | `commit, graph_export, ingest, plan_checkpoint, plan_replan, recall, session_end, skill_invoke, update` | same | **yes** |
| `inputSchema` (all 9) | — | — | **yes** |
| `isError` map (4 call paths) | `{commit:false, recall:false, schema_violation:true, unknown_tool:true}` | same | **yes** |
| full normalised diff | — | — | **0 differences** |

**AC-361 PASSES against the correct baseline.**

## A contaminated first attempt, and why it is recorded

The first run reported ONE diff: `status: "committed"` vs `status: "merged"` with `merged_into`
set. That was **not** a product difference — it was fixture contamination. The checker had
already run a golden-wire capture in that worktree's volume, so committing the identical
payload a second time hit the near-duplicate/dedup path. Re-running both captures with fresh
`CRYSTALIUM_DATA_DIR` values gave **0 differences**.

Recorded because it is the campaign's own recurring lesson in miniature: an artefact that looks
like a finding but is an artefact of how it was measured. The fix was a fresh data dir, not an
exclusion rule — masking `status`/`merged_into` would have hidden a real dedup regression later.

## The comparator's known defect was fixed before use

`compare_wire.py` stamps a sentinel over excluded keys **regardless of value**, and its presence
guard tests `"version" not in si` — which a `null` satisfies. So a null version or null commit
id reported WIRE IDENTICAL. The comparison above uses a **shape guard first**: `serverInfo.version`
and `.name` must be non-empty strings, `tools` must be non-empty with non-empty string names,
and volatile keys are only masked when they are non-null. Both captures passed the guard.

## Follow-ups (not blocking v2.1.0)
1. Re-baseline the archived golden capture to v2.0.2 so the next release compares against its
   real predecessor. The v1.11.0 capture stays as a historical record.
2. Land the shape guard into `compare_wire.py` itself, and its null red-check.
