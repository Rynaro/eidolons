# spec.criteria — `crystalium-residual-eight-plan`

Companion to `spec.md`. Every criterion is falsifiable by a checker who did not write the code:
each VERIFY line is a command a checker can paste, plus the **exact** condition that makes it pass.

## Conventions

| shorthand | absolute path |
|---|---|
| CHANGE | `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan` |
| MAIN | `/home/rynaro/workspace/oss/agents/crystalium` |

- **Container-only.** Every command runs as `docker compose run --rm crystalium …` from MAIN.
  Inside a container use `/app/.venv/bin/python`; **never `bash -lc`** (NC-4).
- **Never `2>/dev/null`.** A command whose success is being checked keeps its stderr.
- **Exit-code convention:** "PASS" means exit `0` unless stated. `jq -e` exits `1` on a
  false/null result, so `jq -e '<predicate>'` is itself the assertion.
- **Test node names are normative.** Where a criterion names a test function, the
  implementation must use that exact name so the checker's `-k` selector is deterministic.
- **Seed protocol (C-2).** "7 seeds" always means `PYTHONHASHSEED` in `0 1 2 3 4 5` plus one
  run with the variable unset.
- **No absolute thresholds.** Numbers that do not yet exist are never asserted; every
  measurement criterion is a differential or a distribution-disjointness claim.

---

## Wave 0

### AC-301 (event-driven)
GIVEN the tree clean at `b7f1a47`
WHEN the entrypoint smoke test runs under the CI mode
THEN the system shall complete the MCP stdio handshake and report a non-empty tool list
VERIFY: `docker compose run --rm crystalium env CRYSTALIUM_SKIP_SLOW=1 pytest mcp-server/tests/test_server_entrypoint.py::test_serve_stdio_handshake -v` — PASS = exit 0.

### AC-302 (unwanted-behavior)
IF `run_stdio` raises at import or startup
THEN the system shall fail `test_serve_stdio_handshake` with the subprocess stderr included in the assertion message
VERIFY: inject `raise NameError("red-check")` at the top of `run_stdio`, run AC-301's command, confirm exit non-zero and that the captured stderr text appears in the pytest output; revert and re-run AC-301 green.

### AC-303 (unwanted-behavior)
IF the asserted tool name is absent from the `tools/list` response
THEN the system shall fail rather than pass on process liveness alone
VERIFY: temporarily assert a nonexistent tool name in the test, confirm RED, revert.

### AC-304 (ubiquitous)
GIVEN the entrypoint smoke test module
WHEN  the test file is inspected
THEN  the system shall carry no `slow` marker on the entrypoint smoke test
VERIFY: `docker compose run --rm crystalium grep -c "pytest.mark.slow" mcp-server/tests/test_server_entrypoint.py` — PASS = output `0`.

### AC-305 (event-driven)
GIVEN a gate fixture with one pinned axis deliberately set to a binding value
WHEN the shared rig's liveness self-check runs
THEN the rig shall return verdict `"confounded"` and emit no numeric axes
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_corpus_rig.py::test_confounded_axis_returns_no_numbers -v` — PASS = exit 0.

### AC-306 (ubiquitous)
GIVEN the `bm25_search` status-predicate fence
WHEN  the fence-amend record is inspected
THEN  the system shall record a verdict of exactly ALLOW or DENY
VERIFY: `jq -e '.verdict=="ALLOW" or .verdict=="DENY"' CHANGE/fence-amend.json` — PASS = exit 0. DENY triggers STOP S-10.

---

## Wave 1 — the four gates

### AC-310 (event-driven)
GIVEN the cross-layer fixture with `corpus_per_layer < candidate_k` and an edgeless graph
WHEN `Aetheryte.recall` is called with `layers=None`
THEN the gate shall report the semantic target at a fused rank other than 0 on `b7f1a47`
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals cross-layer-gate | jq -e '.target_rank != 0'` — PASS = exit 0. A `target_rank` of 0 here triggers STOP S-3.

### AC-311 (event-driven)
GIVEN the same fixture restricted to `layers=["semantic"]`
WHEN `Aetheryte.recall` is called on `b7f1a47`
THEN the gate's single-layer control shall report the semantic target at fused rank 0
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_cross_layer_gate.py::test_single_layer_control_is_rank_zero -v` — PASS = exit 0. RED triggers STOP S-4.

### AC-312 (ubiquitous)
GIVEN the cross-layer gate
WHEN  it emits its result object
THEN  the system shall assert its pinned axes are non-binding before emitting any numeric axis
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals cross-layer-gate | jq -e '.liveness.edge_count==0 and .liveness.corpus_per_layer < .liveness.candidate_k and .liveness.dense_arm_size==0'` — PASS = exit 0.

### AC-313 (event-driven)
GIVEN the `cross_layer` axis rename in `evals/fusion_gate.py`
WHEN the diff is inspected
THEN `_build_fixture` and `run_arm`'s recall path shall be byte-identical to `b7f1a47`
VERIFY: `cd MAIN && git diff b7f1a47 -- evals/fusion_gate.py | grep -E '^[+-]' | grep -vE '^[+-]{3}' | grep -viE 'cross_layer|sparse_arm_per_layer_probe|^[+-]\s*#|"""'` — PASS = **no output**.

### AC-314 (event-driven)
GIVEN a single-layer corpus of `M` crystals with `M > candidate_k`
WHEN the corpus-scaling gate runs on `b7f1a47`
THEN the planted ground-truth record shall be absent from the recalled ids
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals corpus-scaling-gate | jq -e '.planted_recovered == false'` — PASS = exit 0.

### AC-315 (event-driven)
GIVEN the corpus-scaling fixture shrunk below `candidate_k`
WHEN the gate runs on the same build
THEN the planted record shall be recovered
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_corpus_scaling_gate.py::test_small_corpus_control_recovers_planted -v` — PASS = exit 0. RED triggers STOP S-7.

### AC-316 (ubiquitous)
GIVEN the corpus-scaling gate
WHEN  the module is imported
THEN  the system shall leave `FETCH_WIDTH_FLOOR` at 10
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -c "from crystalium.aetheryte.retrieve import FETCH_WIDTH_FLOOR; assert FETCH_WIDTH_FLOOR==10; print('ok')"` — PASS = prints `ok`.

### AC-317 (event-driven)
GIVEN the weight-discriminating fixture
WHEN it is evaluated at `fusion_weight_derived` values 0.90, 0.95 and 1.00
THEN the gate shall produce at least two distinct outcomes across those three values
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals weight-discrimination | jq -e '[.cells[].outcome] | unique | length >= 2'` — PASS = exit 0. A single distinct outcome means the fixture is degenerate exactly as #55 reports.

### AC-318 (ubiquitous)
GIVEN the weight-discrimination module
WHEN  its docstring's first paragraph is read
THEN  the system shall state the module's purpose is the DP-1(b) re-check rather than sub-1.0 band characterisation
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; d=(m.__doc__ or '').split(chr(10)+chr(10))[0]; assert 'DP-1' in d and 'not' in d.lower(); print('ok')"` — PASS = prints `ok`.

### AC-319 (event-driven)
GIVEN the current tree
WHEN the §D2 bitwise identity harness runs its 20 in-process comparisons
THEN the maximum absolute fused-score difference shall be exactly 0.0
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals d2-identity | jq -e '.comparisons==20 and .max_abs_diff==0'` — PASS = exit 0. A non-zero diff is DP-2's recorded reversal condition: STOP.

### AC-320 (unwanted-behavior)
IF one arm weight is perturbed by one ULP
THEN the §D2 identity harness shall report a non-zero difference
VERIFY: run the harness with the perturbation injected, confirm `max_abs_diff > 0`; revert and re-run AC-319 green.

### AC-321 (event-driven)
GIVEN the post-#41 tree
WHEN the floor-sensitivity prediction check runs on the **existing** fusion fixture
THEN the measurement shall record whether floor 10 and floor 1000 still produce differing derived-arm membership
VERIFY: `jq -e 'has("floor10_derived") and has("floor1000_derived") and has("channel_live")' CHANGE/vp-m1-floor-channel.json` — PASS = exit 0. `channel_live == false` confirms spec.md §4's prediction and routes to the new fixture; it is a finding, not a failure.

### AC-322 (event-driven)
GIVEN the new tie-break-neutral floor-sensitivity fixture with the edge-bearing competitor at a dense rank between the two floors
WHEN the target rank is measured at floor 10 and floor 1000 across 7 seeds
THEN the two floors' target-rank distributions shall be disjoint
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals floor-sensitivity-gate --seeds 7 | jq -e '([.floor10[]]|unique) as $a | ([.floor1000[]]|unique) as $b | ([$a[]] - [$b[]] | length) == ($a|length)'` — PASS = exit 0. Non-disjoint triggers STOP S-5.

### AC-323 (unwanted-behavior)
IF the edge-bearing competitor is moved to a dense rank inside both floors
THEN AC-322's disjointness assertion shall fail
VERIFY: apply the move, re-run AC-322's command, confirm exit non-zero; revert.

### AC-324 (event-driven)
GIVEN the floor-sensitivity ACs have moved to their own fixture
WHEN `test_fusion_gate.py` is inspected
THEN the strict-xfail block shall be absent and `evals/fusion_gate.py` shall be unmodified by this unit
VERIFY: `cd MAIN && grep -c "xfail" mcp-server/tests/test_fusion_gate.py` — PASS = output `0`; and `git diff b7f1a47 -- evals/fusion_gate.py` — PASS = **no output** for the W-G-FLOOR branch.

### AC-325 (ubiquitous)
GIVEN the four new gate modules
WHEN  the suite runs in CI mode
THEN  the system shall execute all four without any carrying the `slow` marker
VERIFY: `docker compose run --rm crystalium env CRYSTALIUM_SKIP_SLOW=1 pytest mcp-server/tests/test_cross_layer_gate.py mcp-server/tests/test_corpus_scaling_gate.py mcp-server/tests/test_weight_discrimination.py mcp-server/tests/test_floor_sensitivity_gate.py -v` — PASS = exit 0.

---

## Wave 1 exit — release v2.0.2

### AC-330 (event-driven)
GIVEN every Wave-1 unit merged to the release branch
WHEN both suite modes run
THEN both shall be green
VERIFY: `cd MAIN && make test-ci` — PASS = exit 0; then `cd MAIN && make test` — PASS = exit 0. Disagreement triggers STOP S-9.

### AC-331 (ubiquitous)
GIVEN the v2.0.2 batch
WHEN  its diff against v2.0.1 is inspected
THEN  the system shall show no production-behaviour change under `mcp-server/src/`
VERIFY: `cd MAIN && git diff v2.0.1..HEAD --name-only -- mcp-server/src/` — PASS = output is empty **or** contains only comment-only diffs, each demonstrated by `git diff -w -U0` showing no non-comment line.

### AC-332 (event-driven)
GIVEN the v2.0.2 release candidate
WHEN the checker independently re-breaks each new gate
THEN each gate shall go red under the checker's own perturbation
VERIFY: `jq -e '[.gates[] | select(.independently_reproduced==true)] | length == 4' CHANGE/checker-redcheck.json` — PASS = exit 0. Replaying the maker's `red-evidence.txt` does not satisfy this.

### AC-333 (ubiquitous)
GIVEN the v2.0.2 release
WHEN  the plan state is inspected
THEN  the system shall record a critic whose identity differs from the author
VERIFY: `./.eidolons/ramza/bin/ramza-gate status --state .spectra/plans/crystalium-residual-eight-plan.state.json` — PASS = a critic record is present with `author != checker`.

---

## Wave 2 — behaviour

### AC-340 (event-driven)
GIVEN W-45 merged
WHEN the cross-layer gate runs
THEN the semantic target shall be at fused rank 0
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals cross-layer-gate | jq -e '.target_rank == 0'` — PASS = exit 0.

### AC-341 (ubiquitous)
GIVEN the ordering fix commit
WHEN  its file list is inspected
THEN  the system shall show the xfail-marker removal in the same commit as the `retrieve.py` change
VERIFY: `cd MAIN && git show --stat HEAD` — PASS = the commit touches both `retrieve.py` and `mcp-server/tests/test_cross_layer_gate.py`.

### AC-342 (unwanted-behavior)
IF the layer-merge change is reverted while the tests remain
THEN the cross-layer gate shall go red again
VERIFY: revert only the `retrieve.py` hunk, run AC-340's command, confirm exit non-zero; restore.

### AC-343 (event-driven)
GIVEN the semantic target relocated into the `episodic` layer
WHEN the cross-layer gate runs on the fixed build
THEN the gate shall not treat the record's identity as the signal
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_cross_layer_gate.py::test_relocated_target_control -v` — PASS = exit 0.

### AC-344 (event-driven)
GIVEN the AC-125 fusion A/B run across 7 seeds after each Wave-2 link
WHEN the results are collected
THEN all 7 runs shall report `gate_pass` true
VERIFY: for `s` in `0 1 2 3 4 5` and unset — `docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -m evals fusion-gate | jq -e '.gate_pass==true'` — PASS = exit 0 on all 7. Any red triggers STOP S-6.

### AC-345 (event-driven)
GIVEN a corpus whose top `candidate_k` BM25 hits are all deprecated
WHEN recall runs on the pre-#44 build
THEN the active hits shall be absent and the selectivity boost shall read 0.0
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_prefix_baseline_starves_active_hits -v` — PASS = exit 0 on the pre-fix tree.

### AC-346 (event-driven)
GIVEN the same corpus on the post-#44 build
WHEN recall runs
THEN the active hits shall be present in `result.records`
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_topup_recovers_active_hits -v` — PASS = exit 0.

### AC-347 (unwanted-behavior)
IF the top-up call is deleted while its `explain.fusion.sparse_topup` counter is left in place
THEN AC-346 shall go red
VERIFY: delete the call, keep the counter, re-run AC-346's command, confirm exit non-zero; restore. A counter that stays truthful after its code is removed is the #36 F-V3 defect.

### AC-348 (ubiquitous)
GIVEN the status-aware top-up
WHEN  a recall runs on the dirty-and-censored path
THEN  the system shall issue at most one additional `bm25_search` per recall
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_at_most_one_extra_query -v` — PASS = exit 0 (asserted by call count on a spy, not by reading the source).

### AC-349 (ubiquitous)
GIVEN this campaign's full diff
WHEN  `relational.py` is inspected
THEN  the system shall show the `bm25_search` signature and SQL unchanged
VERIFY: `cd MAIN && git diff b7f1a47..HEAD -- mcp-server/src/crystalium/storage/relational.py` — PASS = **no output**. Non-empty without an ALLOW in `fence-amend.json` is NC-5 tamper evidence.

### AC-350 (event-driven)
GIVEN `exclude_seeds=True` (the default)
WHEN `neighbor_expand` and `decaying_walk` run on a fixture where one seed is reachable from another
THEN the returned sets shall be byte-identical to `b7f1a47`
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py::test_exclude_seeds_default_is_byte_identical -v` — PASS = exit 0.

### AC-351 (unwanted-behavior)
IF the `exclude_seeds` default is flipped to False
THEN AC-350 shall go red
VERIFY: flip the default, re-run AC-350's command, confirm exit non-zero; restore.

### AC-352 (event-driven)
GIVEN seed exclusion relaxed on the retrieval path
WHEN the DP-1(b) re-check runs on the weight-discriminating fixture
THEN no derived-only record shall outrank a record backed by two base arms
VERIFY: `docker compose run --rm crystalium /app/.venv/bin/python -m evals weight-discrimination --dp1-recheck | jq -e '.p1_recreated == false'` — PASS = exit 0. `true` triggers STOP S-1.

### AC-353 (state-driven)
GIVEN seed exclusion is relaxed on the retrieval path
WHEN  the Dream suites run
THEN  the system shall leave the Dream consolidation path unaffected
VERIFY: `docker compose run --rm crystalium pytest mcp-server/tests/test_dream_worker.py mcp-server/tests/test_dream_gate.py mcp-server/tests/test_dream_scheduler.py -v` — PASS = exit 0, and `cd MAIN && git diff b7f1a47..HEAD -- mcp-server/src/crystalium/dream/` — PASS = no output.

---

## Wave 2 exit — release v2.1.0

### AC-360 (event-driven)
GIVEN all three Wave-2 links merged
WHEN both suite modes run
THEN both shall be green
VERIFY: `cd MAIN && make test-ci` then `cd MAIN && make test` — PASS = exit 0 on both. Disagreement triggers STOP S-9.

### AC-361 (ubiquitous)
GIVEN the v2.1.0 release
WHEN  the wire capture is diffed before and after
THEN  the system shall show no breaking client-visible change
VERIFY: capture the wire with the `golden_wire.py` harness before and after; `diff` the two captures — PASS = differences confined to `result.content` payload ordering, with **no** change to tool names, `inputSchema`, or `isError` on any exchange.

### AC-362 (ubiquitous)
GIVEN the v2.1.0 release
WHEN  the plan state is inspected
THEN  the system shall record a second critic whose identity differs from the author
VERIFY: `./.eidolons/ramza/bin/ramza-gate status --state .spectra/plans/crystalium-residual-eight-plan.state.json` — PASS = a second critic record with `author != checker`.

### AC-363 (event-driven)
GIVEN each crystalium tag
WHEN the roster is bumped
THEN both roster files shall move together
VERIFY: `git show --stat HEAD -- roster/mcps.yaml roster/index.yaml` — PASS = both files appear in the same commit; a one-file bump fails the skew guard.

### AC-364 (event-driven)
GIVEN the published image digest
WHEN the lock is verified
THEN `eidolons mcp verify` shall report a definite pass
VERIFY: `cd /home/rynaro/workspace/oss/agents/eidolons && ./cli/eidolons mcp verify` — PASS = exit 0. **Exit 3 is INDETERMINATE, not a pass.**

---

## Wave 3 — disposition

### AC-370 (ubiquitous)
GIVEN the sub-1.0 `fusion_weight_derived` band
WHEN  `config.py` is read
THEN  the system shall record the band as formally unsupported rather than characterised
VERIFY: `cd MAIN && grep -n "unsupported" mcp-server/src/crystalium/config.py` — PASS = a line stating values below 1.0 remain uncharacterised until a fixture with non-stipulated ground truth exists; and no line presents any sub-1.0 value as a supported dial (C-9).

### AC-371 (ubiquitous)
GIVEN a future weight sweep
WHEN  the eval notes are read
THEN  the system shall name the retrieval gate as the informative fixture for weight sweeps
VERIFY: `cd MAIN && grep -rn "retrieval gate" docs/ evals/` — PASS = at least one line naming the fusion gate as uninformative for weight sensitivity (target/Z at k=2).

### AC-372 (unwanted-behavior)
IF `candidate_k` is changed without a recorded response curve
THEN the change shall carry an explicit unsupported-claim fence in its config comment
VERIFY: `cd MAIN && git diff b7f1a47..HEAD -- mcp-server/src/crystalium/aetheryte/retrieve.py | grep -A3 candidate_k` — PASS = either no change, or a change accompanied by a comment stating no shipped measurement validates the law. STOP S-11 otherwise.

### AC-373 (ubiquitous)
GIVEN the eight target issues
WHEN  the open-issue list is queried
THEN  the system shall show each closed with a recorded disposition
VERIFY: `cd MAIN && gh issue list --state open --limit 30 --json number | jq -e 'length == 0'` — PASS = exit 0; and each of #42 #44 #45 #47 #48 #52 #55 #57 carries a closing comment naming either the shipped fix or the WONTFIX rationale.
