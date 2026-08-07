# Checker report — crystalium v2.1.0 release candidate (AC-365)

Checker: independent (maker != checker). Worktree: detached at `release/v2.1.0` =
`d243789a4940418c48428ca0437777a4b8fef57c`, isolated compose project `wt-checker21`,
container-only (`/app/.venv/bin/python`), `git` used on the HOST only where the mandate
requires it (AC-349, AC-353 part 2/3). Worktree left CLEAN at every step (`git status
--porcelain` empty after every perturbation, verified before writing this report).

## AC-365 — three axis-independent red-checks (`checker-redcheck-v2.1.0.json`)

**Preliminary: read the makers' own evidence first**, per the mandate. `red-evidence-w45.json`,
`red-evidence-w44.json`, `red-evidence-w42.json` were read in full before any axis was chosen.
Spent maker axes: W-45 = {AC-342 whole-hunk revert, AC-355/AC-378 backstop-trigger `if False`
disable}; W-44 = {AC-347 call-delete+dishonest-counter, AC-379 backstop's-own-widen disable,
AC-356 flag-check delete}; W-42 = {AC-351 signature-default flip, AC-354 `:272` subtraction
severed}. FORGE's D8 v2.1.0 table (3 rows) was read and **not used verbatim** — its own #42 row
(sever `:272`) is in fact identical in mechanism to the maker's own already-executed AC-354
red-check in `red-evidence-w42.json` (labelled there "the D8-mandated checker perturbation"),
confirming the campaign's own warning that D8 replayed spent maker axes.

### Gate 1 — #45 (layer merge / fetch-shape)
**Axis:** corrupt the fetch-shape SELECTION logic (`_is_single_layer = len(target_layers) == 1`
→ `>= 1`), not the merge or the backstop trigger — a 2-layer strict-subset request gets
misrouted onto the single-layer branch, silently dropping one target layer and skipping the
K-N12 backstop entirely.
**Differs from maker:** maker attacked either the whole feature (AC-342 revert) or the
backstop's firing condition (AC-355/378 `if False`); neither touches path classification.
**Result:** `test_subset_censoring_signal_is_the_global_fetch[censored]` (AC-377) and
`TestCallBudgetPerPath::test_call_budget_per_path[subset]` (AC-348) both go RED, exit 1.
Notably `test_subset_layer_recall_no_regression` (the task's suggested target) stayed GREEN —
measured, not assumed: this fixture's semantic layer has exactly `candidate_k` rows total, so
the misrouted fetch still happens to return the target by corpus-size coincidence. AC-377/AC-348
are the criteria that actually catch this axis.
**Restore:** `git checkout -- mcp-server/src/crystalium/aetheryte/retrieve.py`; full
`test_retrieve_layer_merge.py` re-run green (7 passed).

### Gate 2 — #44 (status top-up)
**Axis:** attack the composition step of the censoring recompute rather than call presence, the
backstop's own trigger, or the flag check. On the single-layer widen path, the `_topup_widen`
call fires, `raw_n_sparse_signal`/`cap_signal` are left HONESTLY updated to the widened fetch's
true numbers — but `bm25_hits = _merge_bm25_order(bm25_hits, wide_hits)` is skipped, so the
widened rows are fetched and truthfully counted but never routed into the ranked candidate set.
**Differs from maker:** none of the three maker axes touch the merge step; the closest
(AC-347) makes the counter dishonest with no call at all — this axis is the inverse failure
mode (honest call, honest counter, wrong data).
**A negative result reported honestly first:** I tested the task's literally-suggested axis
(freeze `raw_n_sparse_signal`/`cap_signal` at pre-widen values across all three widen sites —
default, single-layer, strict-subset-head — leaving the call/merge/counter untouched) and it
reddened **zero** criteria across `test_sparse_status_topup.py` + `test_retrieve_layer_merge.py`
+ `test_cross_layer_gate.py` (22 passed, 1 xfailed, both before and after). This is a genuine
coverage gap, not a mistake: only AC-377 checks the post-widen censoring signal, and AC-377's
own fixture runs with `recall_active_only=False`, so it never exercises #44's widen at all — no
existing criterion connects #44's own censoring-signal recompute to an observable outcome on any
of its 3 widen sites. **Flagging this as a real finding**, then pivoting to the merge-skip
variant above, which DOES flip a gate.
**Result:** `test_topup_recovers_active_hits` (AC-346) → RED, exit 1
(`AssertionError: assert 'active-target' in []`).
**Restore:** `git checkout -- mcp-server/src/crystalium/aetheryte/retrieve.py`; full
`test_sparse_status_topup.py` re-run green (7 passed, 1 xfailed).

### Gate 3 — #42 (seed exclusion)
**Axis:** sever the PASS-THROUGH at `decaying_walk`'s inner `neighbor_expand` call (D2's site
table row `graph.py:305`) rather than the `:272` subtraction the maker already used — hardcode
`exclude_seeds=True` on that inner call so `decaying_walk(..., exclude_seeds=False)` still
internally calls `neighbor_expand` as if the flag were True.
**Differs from maker:** AC-351 flips the function's own signature default (a different site);
AC-354 (already D8-mandated, already executed by the maker) severs the `:272` subtraction inside
`neighbor_expand` itself. This axis touches neither site.
**Result:** `test_exclude_seeds_false_expected_sets[T3-variant]` → RED, exit 1
(`assert {} == {'t3v-s2': 0.5}`). AC-350 (True-branch byte-identity, all 4 topologies) stays
fully GREEN, as required. **Measured, not assumed:** T3-variant reds but T3-proper stays green —
at hop ≥2 the walk-level `visited` set (line 335, unaffected by this perturbation) already
excludes previously-visited original seeds via `new = nxt - visited`, so this specific axis is
only observable when a seed is reachable from another seed within the SAME hop-1 frontier
(T3-variant's shape), not at deeper hops. A narrower, more precise finding than "T3 reddens."
**Restore:** `git checkout -- mcp-server/src/crystalium/storage/graph.py`; full
`test_storage_graph.py -k exclude_seeds` re-run green (8 passed).

### Independence proof
All three perturbations are at code sites the maker's own red-evidence never touches (verified
by direct file inspection of all three `red-evidence-*.json`, plus `grep -F` of each mutated
line against all three files). The one substring hit (the `_is_single_layer == 1` line appearing
inside AC-342's red-evidence-w45.json entry) is explained: AC-342 is a ~150-line whole-hunk
revert of the entire #45 feature, and the pre-mutation line necessarily appears as content being
removed by that revert — the two `perturbation_patch` texts are not identical (single 1-line
boolean-operator flip vs. a full multi-hunk feature revert), so this is not a replay under D8's
identical-patch anti-replay test.

## AC-360 — full suite, both modes
```
make test     -> 1097 passed, 4 skipped, 1 xfailed   EXIT=0   (867.02s)
make test-ci  -> 1093 passed, 8 skipped, 1 xfailed   EXIT=0   (331.74s)
```
Exact match to the expected counts. Modes agree; no S-9. Host disk checked before and after
(`df -h /`: 55–56% used, 102–105G free throughout) — no repeat of the documented disk-pressure
event.

## AC-361 / VP-M8 wire non-regression — **FAIL, real findings, but pre-existing (not caused by W-45/44/42)**
Ran `golden_wire.py` (from the archived `2026-08-05-crystalium-mcp-sdk-2x-39` change) against
this build inside the container, then added the mandated shape-assertion guard
(non-null/non-empty/typed on `serverInfo.{name,version}` and `call_commit`'s `id`) **before**
using `compare_wire.py`, and red-checked the guard itself by poisoning a fresh capture's
`serverInfo.version` to `null`: the guard correctly fails (exit 1) on the poisoned copy, while
`compare_wire.py` run on the SAME poisoned copy reports its usual differences with **zero**
mention of `serverInfo.version` — proving the documented defect (unconditional sentinel-stamping
+ a `"version" not in si` presence check that a `null` value satisfies) is real and would have
silently passed a null through.

On the REAL (non-poisoned) v2.1.0 capture, `compare_wire.py` reports **11 real differences**,
none of them masked by the defect:
- **9× tool name changes** — every tool in `tools/list` dropped its `crystalium.` prefix
  (`crystalium.recall` → `recall`, etc.) since the v1.11.0 golden baseline.
- **1× `isError` flip on the UNKNOWN_TOOL path** — golden: `isError: false` (errors returned as
  ordinary content); candidate: `isError: true`. `golden_wire.py`'s own comment states
  **"FORGE R4 hinges on its current shape"** — this is exactly the kind of consumer-visible
  break AC-361 exists to catch.
- **1× `call_commit`'s `content_ref` hash differs** on byte-identical input text, a field not on
  either script's documented exclusion list.

**This did NOT fail the stated pass bar** ("differences confined to `result.content` payload
ordering; NO change to tool names, `inputSchema`, or `isError`"). **However, it is not a
regression introduced by W-45/W-44/W-42**: `git diff b7f1a47..HEAD -- mcp-server/src/crystalium/server.py`
shows the ONLY change in this RC's 5-commit range is W-42's unrelated
`recall_seed_derived_credit` wiring + two `GraphStore` stand-in signature fixes — nothing
touching tool registration, naming, or the UNKNOWN_TOOL error path. `build_tool_manifest()`
already returns unprefixed names and the dispatcher already flips `isError` for unknown tools at
the RC's base commit, so this drift pre-dates this campaign's own changes (most likely inherited
from the already-archived #39 SDK migration, or some other change between v1.11.0 and v2.0.1
that was never re-verified against the golden baseline with a real candidate until this hop).
**Reported as a real, currently-true finding that the release process should address**, but it
does not implicate the mechanism under this checker's mandate (#45/#44/#42) and pre-dates the
already-published v2.0.2.

## AC-350/AC-352/AC-353 — all green
- AC-350: `test_exclude_seeds_default_is_byte_identical` — 4/4 topologies (T1/T2/T3/T3-variant)
  byte-identical, exit 0.
- AC-352: both parts green. Part (i) `w_derived=1.0` → `p1_recreated: false`. Part (ii) the
  `w_derived=100.0` positive control → `p1_recreated: true`, confirming the instrument has
  power (a negative from an instrument that cannot produce a positive would not be evidence —
  confirmed it CAN).
- AC-353: all three parts green — Dream suites pass (21 passed), the `dream/` path exists at
  `b7f1a47` (3 files), and `git diff b7f1a47..HEAD -- .../dream/` is empty (run on the HOST).

## AC-349 — green
`git diff b7f1a47..HEAD -- mcp-server/src/crystalium/storage/relational.py` on the HOST: empty.
`bm25_search`'s signature/SQL is frozen, as required.

## AC-381 — green (replaced form)
Used the REPLACED, line-wrap-normalising form from `spec.criteria.amend-04.md` (the amend-03
form's anchor can never match, per that amendment's own finding). Ran it verbatim in-container:
prints `ok`.

## AC-382 — node-collection sweep: **BLOCKER found, run exactly as documented**
`wave-manifest-pending.txt` is **not empty** (1 stale entry:
`test_storage_graph.py::test_exclude_seeds_default_is_byte_identical`, a W-42/AC-350 node that
has already landed and collects/passes on this tree — it should have been pruned per the
manifest's own rule "a node must be REMOVED from this list when its wave lands").

More significantly: running the AC-382 VERIFY block **exactly as specified** in
`spec.criteria.amend-04.md` (host `git`/`docker compose run --rm crystalium pytest
mcp-server/tests/ --collect-only -q`, then the documented `comm -23` set-difference against
`nodes_eff.txt`) produces **2 spurious BLOCKERs**:
```
mcp-server/tests/test_retrieve_layer_merge.py::test_subset_censoring_signal_is_the_global_fetch
mcp-server/tests/test_sparse_status_topup.py::test_at_most_one_extra_query
```
Both functions **exist and pass** — confirmed directly
(`test_subset_censoring_signal_is_the_global_fetch[censored]`/`[uncensored]` and
`test_at_most_one_extra_query[default]`/`[single-layer]`/`[subset]` all collect and pass). The
sweep's own node-extraction regex pulls BARE `file.py::function` references out of the spec
docs, but both these Wave-2 functions became **parametrized** (`@pytest.mark.parametrize`) when
they landed, so `--collect-only` only ever emits the bracketed forms
(`...::test_at_most_one_extra_query[default]`, etc.) — an exact-line `comm -23` can never match
a bare doc reference against a bracketed collection ID, so every parametrized Wave-2 node is
reported missing regardless of whether it exists. **The stale `wave-manifest-pending.txt` entry
noted above is accidentally masking a THIRD instance of the exact same defect** — that node is
ALSO parametrized (4 topologies) and would produce a 3rd spurious BLOCKER the moment someone
"correctly" prunes the manifest per its own rule, which may be why it was never pruned. This is a
real, reproducible defect in AC-382's own comparison logic (a false-BLOCKER species — the
opposite direction from RC-1/RC-2/RC-3, which amend-04 already documents as self-red-checks of
this same gate) — a 4th recurrence not yet caught. **AC-382, run per its own documented VERIFY
block, currently exits non-zero (blockers.txt non-empty) on this RC tree.**

## The #42 default — green
`Config.recall_seed_derived_credit: bool = False` (`config.py:360`) AND the env override
`_env_bool("CRYSTALIUM_RECALL_SEED_DERIVED_CREDIT", False)` (`config.py:475-476`) — both `False`,
per FORGE's ruling in `issue-42-default-ruling.md`.

## Container discipline
Container-only (`/app/.venv/bin/python`), never `bash -lc`, never `2>/dev/null` on a
success-check, `git` used only on the HOST for the two mandated host-git checks (AC-349, AC-353),
loops redirected `< /dev/null`. Worktree confirmed clean (`git status --porcelain` empty) before
and after every perturbation and at report time.

## VERDICT: REJECT

Two named, blocking defects, both reproduced independently and both real (not fixture-relative,
not FORGE-precedent-covered):

1. **AC-382 (a MUST gate in the release checklist) currently exits non-zero on this exact RC
   tree when run per its own documented VERIFY block** — 2 spurious BLOCKERs from a
   parametrize/bracket mismatch, with a 3rd instance currently masked only by a manifest entry
   that was never pruned. "PASS = exit 0 with `blockers.txt` empty" is not met.
2. **AC-361/VP-M8's wire-identity pass bar is not met** — 11 real, unmasked differences
   including a safety-relevant `isError` flip on the UNKNOWN_TOOL path that the golden fixture's
   own comment says a FORGE ruling (R4) depends on, and a universal tool-name change. This is
   very likely inherited drift pre-dating this campaign (confirmed via `git diff` that W-45/44/42
   never touch `server.py`'s naming/dispatch logic) rather than something #45/#44/#42
   introduced — but it is nonetheless a currently-true, previously-uncaught FAIL against a named
   MUST criterion in this checker's own mandate, on the tree about to be tagged.

Neither defect is in the mechanism the maker's own W-45/W-44/W-42 work changed (recall order and
membership) — all THREE required axis-independent red-checks against that mechanism (#45, #44,
#42) behaved correctly: each perturbation reddened a real, named criterion and restored clean.
AC-360/AC-350/AC-352/AC-353/AC-349/AC-381 and the #42 default are all genuinely green. But
AC-382 and AC-361 are both explicitly named in this checker's mandate as MUST-verify items, and
both fail as measured, on this exact tree, right now. Per D9's own disposition ladder, an
unfailable-or-wrongly-failing gate is itself a blocking finding, not something to route around
silently. **Recommend: fix the AC-382 sweep's parametrize-handling (or switch its effective-node
extraction to bracket-tolerant matching) and file/triage the AC-361 wire drift (isError +
tool-name prefix) before tagging** — the second item may turn out to be an accepted,
already-shipped (in v2.0.2) prior decision once traced, but that determination has not been made
and documented anywhere in this change folder, so it cannot be waved through silently at this
checker hop.

---

## RE-VERIFICATION ADDENDUM (independent, fresh evidence — neither of the coordinator's numbers was trusted)

Both resolutions were re-run from scratch with my own commands/scripts, not by re-reading the
coordinator's artifacts. Worktree confirmed clean (`git status --porcelain` empty) before,
during (via a separate `git worktree add --detach 973ab73`, removed after), and after.

### AC-382 — CONFIRMED FIXED, independently reproduced
Regenerated `nodes_eff.txt` fresh from the current `spec.criteria*.md`/`verification-plan*.md`
(20 nodes, byte-identical to my original pre-fix run — the effective criteria set itself did not
change). Regenerated `all_nodes.txt` via a fresh `--collect-only` run (1102 nodes, matches).
Applied the RC-4 fix (`sed -E 's/\[[^]]*\]$//' ... > all_nodes_norm.txt`, 989 lines, matches) and
the two-stage `comm -23` against the now-empty `wave-manifest-pending.txt` (confirmed 0 bytes).
**Result: `missing.txt` empty even before the manifest filter, `blockers.txt` empty, exit 0 —
independently reproduced.** Then red-checked the fix myself (not the coordinator's red-check):
appended a fabricated node id to `nodes_eff.txt` and re-ran the same pipeline — **1 BLOCKER,
exit 1**, proving the gate is live, not vacuously green. **AC-382: REJECT WITHDRAWN.**

### AC-361 — CONFIRMED FIXED, independently reproduced with fresh evidence (not the coordinator's files)
Set up a second, fully separate git worktree at `973ab73` (v2.0.2) via `git worktree add`,
confirmed the archived `golden_wire.py` I copied is byte-identical to the canonical archive copy
(diff empty). Ran the capture on BOTH trees myself, each in its own isolated compose project
(`wt-checker21` / `wt-v202-verify`, separate named volumes) with a never-before-used
`CRYSTALIUM_DATA_DIR` on each side (`checker-fresh-v210` / `checker-fresh-v202`) specifically to
rule out the dedup-contamination artifact the coordinator described — confirmed clean: both
`call_commit` results show `"status": "committed"` (never `"merged"`) on first read.
Wrote my own comparator (not the coordinator's) with a shape-guard-first discipline (asserts
`serverInfo.{name,version}` and `call_commit.id` non-null/non-empty/typed on BOTH captures before
any masking), extending the volatile-key exclusion list to include `content_ref` — measured
directly that this hash differs run-to-run even between two captures on the SAME tree (not just
across trees, contradicting my original report's implication that it was suspicious; it is
ordinary volatility, same species as `id`).
**Result:** shape guard OK on both; tool names identical (9, single-segment); `inputSchema`
identical for all 9; `isError` map identical across all 4 call paths
(`{commit:false, recall:false, schema_violation:true, unknown_tool:true}`) — exact match to the
coordinator's reported values; full normalised diff: **0 differences, exit 0**. Red-checked my
own comparator by poisoning a copy's tool name — correctly caught, exit 1.
Sanity-checked the coordinator's root-cause claim against `CHANGELOG.md` directly: the `[2.0.0]`
entry documents, as a **BREAKING** change, exactly the two behaviours originally flagged —
`#35, #33` renaming all 9 tools from dotted to single-segment, and unknown-tool calls now
returning `isError: true` (previously `false`) — confirming these are real, shipped, documented
v2.0.0 changes (crystalium's own CHANGELOG, not a claim I had to take on faith).
**AC-361: REJECT WITHDRAWN.** The v1.11.0 golden baseline was genuinely stale; v2.1.0 introduces
zero wire drift relative to its actual predecessor v2.0.2.

## REVISED VERDICT: APPROVE

Both blocking items from the original REJECT are independently confirmed resolved:
AC-382's sweep is fixed and red-checked sound; AC-361 passes against the correct (v2.0.2)
baseline with zero wire drift, and the original 11-difference finding is explained, sourced to
the CHANGELOG, and shown not to implicate this release. Combined with the original findings that
already held (AC-360 both modes green, three axis-independent red-checks all correctly reddened
and restored on the #45/#44/#42 mechanism itself, AC-350/352/353/349/381 green, the #42 default
correctly `False`), there is no remaining blocking finding against tagging `v2.1.0`.

Follow-ups noted in `ac361-wire-resolution.md` (re-baseline the archived golden capture to
v2.0.2; land the shape guard into `compare_wire.py` itself) are correctly non-blocking and should
be tracked as separate housekeeping, not conditions of this tag.
