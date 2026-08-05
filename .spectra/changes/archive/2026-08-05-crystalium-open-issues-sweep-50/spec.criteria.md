# spec.criteria — `crystalium-open-issues-sweep-50`

Companion to `spec.md`. Every criterion is falsifiable by a checker who did not write the code:
each VERIFY line is a command a checker can paste, plus the **exact** condition that makes it pass.

## Conventions

Absolute paths (the harness resets cwd between commands, so every VERIFY line is self-contained):

| shorthand used in prose | absolute path |
|---|---|
| CHANGE | `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50` |
| MAIN | `/home/rynaro/workspace/oss/agents/crystalium` |
| W1 | `/home/rynaro/workspace/oss/agents/crystalium-w1-graph` |
| W2 | `/home/rynaro/workspace/oss/agents/crystalium-w2-retrieve` |
| W3 | `/home/rynaro/workspace/oss/agents/crystalium-w3-gate` |
| W4 | `/home/rynaro/workspace/oss/agents/crystalium-w4-relational` |

- **Exit-code convention:** unless stated otherwise, "PASS" means the command exits `0`.
  `jq -e` exits `1` on a false/null result, so `jq -e '<predicate>'` is itself the assertion.
- **Baseline record shape** (`eval-before.json`, `eval-after.json`): a JSON array of
  `{"seed": <"0".."5"|"unset">, "git_sha": <string>, "gate": <string>, "cmd": <string>,
  "output": <the gate's stdout JSON>}`. The `gate` tag vocabulary is fixed:
  `fusion-gate-run`, `fusion-floor-weighted-10`, `fusion-floor-weighted-1000`,
  `fusion-floor-reverted-10`, `fusion-floor-reverted-1000`, `retrieval-gate`.
- **Test node names are normative.** Where a criterion names a test function, the implementation
  must use that exact name, so the checker's `-k`/node-id selector is deterministic.
- **No absolute thresholds.** Every criterion that depends on the baseline is phrased as a
  differential against `eval-before.json`. W0's numbers do not exist yet; no number in this file is
  a measurement.

---

## W0 / W0b / W0c — baseline capture

### AC-201 (event-driven)
GIVEN the target tree clean at `56c8510` before any code change
WHEN  the 7-seed fusion-gate baseline capture completes
THEN  the system shall record seven `fusion-gate-run` records whose `gate_pass` is true
VERIFY: `jq -e '[.[]|select(.gate=="fusion-gate-run")] | length==7 and (map(.output.gate_pass)|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-before.json` — PASS = exit 0. Any red seed on the **shipped** build is a shipped-build flake, not a baseline: STOP (VP-S1) and return to FORGE.

### AC-202 (event-driven)
GIVEN the target tree clean at `56c8510` with the sentence-transformers model available in-container
WHEN  the 7-seed retrieval-gate baseline capture completes
THEN  the system shall record seven `retrieval-gate` records that each carry a non-null `axes.multihop_f1.completion` with `graph_ok` true
VERIFY: `jq -e '[.[]|select(.gate=="retrieval-gate")] | length==7 and (map(.output.graph_ok)|all) and (map(.output.axes.multihop_f1.completion != null)|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-before.json` — PASS = exit 0. A `graph_ok` false means the null-stub branch (`evals/retrieval_gate.py:168-170`) fired and the capture is void.

### AC-203 (event-driven)
GIVEN AC-138's frozen VERIFY line requiring the **weighted** arm at floor 1000 (#38 `spec.criteria.md:295`)
WHEN  the W0b supplementary capture completes
THEN  the system shall record seven records for each of the two weighted floor-probe families
VERIFY: `jq -e '([.[]|select(.gate=="fusion-floor-weighted-10")]|length==7) and ([.[]|select(.gate=="fusion-floor-weighted-1000")]|length==7)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-before.json` — PASS = exit 0. The commands captured are `python -m evals fusion-gate --floor 10` and `python -m evals fusion-gate --floor 1000` (no `--reverted`; `evals/__main__.py:98-99` passes `weighted=not args.reverted`).

### AC-204 (unwanted-behavior)
GIVEN the DP-2 sweep harness run against the **pre-fix** SHA `56c8510`, where `config.py:238-243` records that `fusion_weight_derived = 0.90` "fails the gate deterministically"
WHEN  the harness sweeps 0.90 over the seven seeds
THEN  the system shall report `gate_pass` false on every one of the seven seeds
VERIFY: `jq -e '[.[]|select(.weight==0.90)] | length==7 and (map(.output.gate_pass==false)|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/dp2-control-prefix.json` — PASS = exit 0. This is the harness's **positive control**: `Config` is a plain `@dataclass` (`config.py:82`) and the gate harnesses bypass `Config.from_env`, so a naive monkeypatch silently no-ops. A green 0.90 here means the sweep is not reaching the code: the sweep is void, STOP (VP-S5).

**AMENDMENT A-1 (measured correction).** The control MUST run against `python -m evals retrieval-gate`, **not** `fusion-gate`. Measured at `56c8510`: on the fusion fixture the only competitor for rank 0 is the graph-only phantom `Z`, so *lowering* `fusion_weight_derived` only demotes `Z` and `target` holds rank 0 at every sub-1.0 value — the fusion gate is green at 0.0/0.5/0.9/1.0 and only goes red ABOVE 1.0 (5.0/100.0 → `Z` outranks `target`, the documented P1 inversion). The cliff lives on the retrieval gate: `deliberation.md:169-172` gives the mechanism as spoke2's vote `w_derived/(60+r)` against a distractor at `0.0149254` at the last k=10 slot, and `0.90/63 = 0.0142857` is below it at every rank. Re-run on the retrieval gate reproduces the record (0.90 RED, 0.95 flake, 1.00 GREEN). Two further hardening rules: the injection point is `Aetheryte.__init__` and the value MUST be read back off the **instance** — reading it back off the kwarg dict you just wrote is a tautology and cannot fail; and a sweep on the fusion gate would "pass" vacuously, so the gate under sweep is itself part of the criterion. See `dp2-control-note.md`.

### AC-205 (ubiquitous)
GIVEN any baseline artefact produced by this campaign
WHEN  a checker inspects a record
THEN  the system shall carry `seed`, `git_sha`, `gate`, `cmd` on every record
VERIFY: `jq -e 'all(.[]; has("seed") and has("git_sha") and has("gate") and has("cmd"))' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-before.json` — PASS = exit 0; additionally `jq -r '[.[].git_sha]|unique|.[]' <same file>` prints exactly `56c8510`.

### AC-206 (unwanted-behavior)
GIVEN W0 is specified as measurement-only
WHEN  the capture finishes
THEN  the system shall leave the target working tree byte-identical to `56c8510`
VERIFY: `test -z "$(git -C /home/rynaro/workspace/oss/agents/crystalium status --porcelain)" && git -C /home/rynaro/workspace/oss/agents/crystalium rev-parse --short HEAD` — PASS = exit 0 with stdout `56c8510`.

---

## W1 — GraphStore cursor + pattern repair (#41, N-1, N-4)

### AC-210 (unwanted-behavior)
GIVEN the new multi-seed tests applied on top of the **pre-fix** `graph.py` (fix stashed)
WHEN  those tests run against the real `GraphStore`
THEN  the system shall fail at least three of them
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && git stash push -- mcp-server/src/crystalium/storage/graph.py && docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py::TestNeighborExpandMultiSeed mcp-server/tests/test_storage_graph.py::TestAllEdgesCursor -q 2>&1 | tee /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/red-evidence.txt; git -C /home/rynaro/workspace/oss/agents/crystalium-w1-graph stash pop` — PASS = `grep -Eq '\b([3-9]|[0-9]{2,}) failed' /home/…/red-evidence.txt` exits 0. **If the new tests pass on pre-fix code they are not gates: STOP (VP-S2).** The current suite is green on the bug — the scout measured `pytest test_storage_graph.py test_completion.py -q` → 27 passed at `56c8510`.

### AC-211 (event-driven)
GIVEN a fixture with at least two seeds, each carrying out-edges, and no seed-to-seed edge
WHEN  `neighbor_expand(seed_ids)` is called on the real `GraphStore`
THEN  the system shall return the union of the per-seed expansions minus the seed set
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_graph.py::TestNeighborExpandMultiSeed::test_multi_seed_expansion_is_union_minus_seeds" -q` — PASS = exit 0, `1 passed`. The identity asserted is `expand(S) == (⋃ expand([s]) for s in S) - set(S)`; the naked union form is false while `graph.py:251`'s seed exclusion stands (#42 is REPORT).

### AC-212 (unwanted-behavior)
GIVEN a seed list whose **first** seed has no out-edges while later seeds do
WHEN  `neighbor_expand` is called with that list
THEN  the system shall return a non-empty set
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_graph.py::TestNeighborExpandMultiSeed::test_edgeless_first_seed_does_not_abort_later_seeds" -q` — PASS = exit 0, `1 passed`. This is the scout-measured escalation the issue text does **not** state (`expand([e0,s1,s2]) = []` at `56c8510`).

### AC-213 (event-driven)
GIVEN a discriminating fixture where seeds after the first have neighbours the first does not
WHEN  `neighbor_expand(seeds)` is compared with `neighbor_expand([seeds[0]])`
THEN  the system shall return different sets for the two calls
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_graph.py::TestNeighborExpandMultiSeed::test_multi_seed_differs_from_first_seed_alone" -q` — PASS = exit 0, `1 passed`. Directly negates `CHANGELOG.md:99-100`'s recorded symptom `neighbor_expand(seeds) == neighbor_expand([seeds[0]])`.

### AC-214 (event-driven)
GIVEN a plain chain `a → b → c` with no self-loops
WHEN  `neighbor_expand(["a"], depth=2)` is called
THEN  the system shall return exactly `{"b", "c"}`
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_graph.py::TestNeighborExpandMultiSeed::test_depth_2_chain_returns_both_hops" -q` — PASS = exit 0, `1 passed`. N-4: at `56c8510`, `graph.py:229-230, 235` binds every hop to the same variable `b`, so this returns `set()` unless `b` has a self-loop; the "up to *depth* hops" contract at `graph.py:206` is restored, with the original seeds excluded at every hop per `graph.py:215`.

### AC-215 (event-driven)
GIVEN a graph carrying edges of at least two distinct relationship types
WHEN  `all_edges()` is called with no `rel_filter`
THEN  the system shall return every edge of every queried relationship type
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_graph.py::TestAllEdgesCursor::test_all_edges_complete_across_rel_types" -q` — PASS = exit 0, `1 passed`.

### AC-216 (unwanted-behavior)
GIVEN a healthy graph where every `all_edges` sub-query succeeds
WHEN  `all_edges()` runs
THEN  the system shall emit no `all_edges_rel_error` log event
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_graph.py::TestAllEdgesCursor::test_all_edges_emits_no_rel_error_on_healthy_path" -q` — PASS = exit 0, `1 passed`. N-1: at `56c8510`, `graph.py:333-339` logs one warning per rel type on **every** call because exhaustion raises into the per-rel `except`.

### AC-217 (event-driven)
GIVEN `decaying_walk` invoked with a multi-node frontier
WHEN  the same call is repeated under different `PYTHONHASHSEED` values
THEN  the system shall produce an identical score dict
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && for s in 0 5; do docker compose run --rm -e PYTHONHASHSEED=$s crystalium pytest "mcp-server/tests/test_storage_graph.py::TestNeighborExpandMultiSeed::test_decaying_walk_is_hashseed_invariant" -q; done` — PASS = both invocations exit 0. At `56c8510` `graph.py:278` passes `list(frontier)` from the `set` at `:276`, so the surviving seed is hash-random (scout-measured: input `['s1','s2','s3']` logged as `['s2','s1','s3']`).

### AC-218 (event-driven)
GIVEN the W1 branch with the fix applied
WHEN  the storage plus dream-worker suites run in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py mcp-server/tests/test_dream_worker.py -q` — PASS = exit 0.

### AC-219 (event-driven)
GIVEN the W1 branch with the fix applied
WHEN  the fast suite runs in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w1-graph && make test-fast` — PASS = exit 0. Contingency: if `test_fusion_gate.py::TestFetchWidthFloorInflation::test_reverted_build_rank_changes_with_floor` XPASSes under `make test`, `strict=True` (`test_fusion_gate.py:102`) turns the suite red — that is a **measured AC-139 GREEN** (pre-ruled), W1 removes the marker, records the measurement in `verification.md`, and #48's ruling is noted as moot. No other edit to that file is permitted.

---

## W1b — re-baseline and the mandated re-runs

All W1b criteria are **differentials against `eval-before.json`**. The retrieval half of that
baseline is knowingly **confounded** (#43); the differential is still valid for isolating #41
because both sides run the identical fixture and identical arm wiring, with `graph.py` as the only
variable (see `spec.md` §2.3).

### AC-220 (event-driven)
GIVEN W1 merged to `main`
WHEN  the W0/W0b protocol is repeated at the post-W1 SHA
THEN  the system shall produce `eval-after.json` whose gate/seed coverage matches `eval-before.json` exactly
VERIFY: `jq -e -n --slurpfile b /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-before.json --slurpfile a /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-after.json '($b[0]|map({gate,seed})|sort) == ($a[0]|map({gate,seed})|sort)'` — PASS = exit 0. Additionally `jq -r '[.[].git_sha]|unique|length' eval-after.json` prints `1` with a value that is **not** `56c8510`.

### AC-221 (event-driven)
GIVEN the frozen AC-125 VERIFY line (#38 `spec.criteria.md:217`, frozen sha `e644052e868db47b49c7daedba904e9f53b67d401c81bde0b5e2887ffcb2fded`)
WHEN  the fusion gate is re-run at the post-W1 SHA over the seven seeds
THEN  the system shall report `gate_pass` true on all seven seeds
VERIFY: `jq -e '[.[]|select(.gate=="fusion-gate-run")] | length==7 and (map(.output.gate_pass)|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-after.json` — PASS = exit 0. Not 7/7 unanimous ⇒ AC-136 contingency class: STOP (VP-S3), return to FORGE.

### AC-222 (event-driven)
GIVEN the frozen AC-125 VERIFY line's second half
WHEN  the fusion-gate pytest wrapper runs at the post-W1 SHA
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_fusion_gate.py -q` — PASS = exit 0 (an `xfail` counts as pass; an `XPASS` does not, per §AC-219's contingency).

### AC-223 (event-driven)
GIVEN the frozen AC-124 VERIFY line (#38 `spec.criteria.md:211`), scoped by vigil A-1 to the multi-hop axis
WHEN  the retrieval gate is re-run at the post-W1 SHA over the seven seeds
THEN  the system shall report `completion_pass` true on all seven seeds
VERIFY: `jq -e '[.[]|select(.gate=="retrieval-gate")] | length==7 and (map(.output.completion_pass)|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-after.json` — PASS = exit 0.

### AC-224 (event-driven)
GIVEN the AC-124 threshold defined as "the measured baseline, never any modelled number"
WHEN  the post-W1 `multihop_f1.completion` distribution is compared with the baseline distribution
THEN  the system shall report a post-fix median no lower than the baseline median
VERIFY: `jq -n -e --slurpfile b /home/…/eval-before.json --slurpfile a /home/…/eval-after.json 'def med: sort | if length==0 then null elif length%2==1 then .[length/2|floor] else (.[length/2-1]+.[length/2])/2 end; ([$a[0][]|select(.gate=="retrieval-gate")|.output.axes.multihop_f1.completion]|med) >= ([$b[0][]|select(.gate=="retrieval-gate")|.output.axes.multihop_f1.completion]|med)'` — PASS = exit 0 (expand `/home/…/` to the CHANGE path from the conventions table).

### AC-225 (event-driven)
GIVEN the frozen AC-133 VERIFY line (#38 `spec.criteria.md:265`), where `context_rank` is lower-is-better with `null` treated as the worst value
WHEN  the post-W1 `context_rank.context` distribution is compared with the baseline distribution
THEN  the system shall report a post-fix median no worse than the baseline median
VERIFY: `jq -n -e --slurpfile b /home/…/eval-before.json --slurpfile a /home/…/eval-after.json 'def med: sort | if length==0 then null elif length%2==1 then .[length/2|floor] else (.[length/2-1]+.[length/2])/2 end; def rk: [.[]|select(.gate=="retrieval-gate")|(.output.axes.context_rank.context // 1e9)]; ($a[0]|rk|med) <= ($b[0]|rk|med)'` — PASS = exit 0. The `// 1e9` substitution is the frozen "null = worst" rule made mechanical.

### AC-226 (event-driven)
GIVEN the DP-2 sweep harness validated by AC-204
WHEN  the sweep runs at the post-W1 SHA over `fusion_weight_derived ∈ {0.90, 0.95, 1.00}` × seven seeds
THEN  the system shall report `gate_pass` true on all seven seeds at 1.00
VERIFY: `jq -e '[.[]|select(.weight==1.00)] | length==7 and (map(.output.gate_pass)|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/dp2-sweep-postfix.json` — PASS = exit 0. **Any red at 1.00 ⇒ STOP (VP-S4)** before any `config.py` edit; the shipped default's justification (`config.py:243-245`, the bitwise identity property) is at stake and `config.py` belongs to W3, not to W1b.

### AC-227 (ubiquitous)
GIVEN the sweep's 0.90 and 0.95 cells may legitimately move once membership is deterministic
WHEN  the post-fix sweep completes
THEN  the system shall record all twenty-one weight-by-seed outcomes without asserting a verdict on the sub-1.0 cells
VERIFY: `jq -e 'length==21 and ([.[].weight]|unique|sort)==[0.90,0.95,1.00]' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/dp2-sweep-postfix.json` — PASS = exit 0. A 0.90/0.95 outcome that differs from `config.py:238-243`'s recorded cliff is a **finding for the CHANGELOG and for FORGE**, never a licence to present a sub-1.0 value as supported (`config.py:246-252`).

### AC-228 (event-driven)
GIVEN membership in the derived arms is deterministic once #41 is fixed
WHEN  the post-W1 fusion gate is compared across the seven seeds
THEN  the system shall report an identical `weighted.target_rank` on every seed
VERIFY: `jq -e '[.[]|select(.gate=="fusion-gate-run")|.output.weighted.target_rank]|unique|length==1' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-after.json` — PASS = exit 0. A failure here is **not an automatic STOP**: residual cross-seed variance on the fusion gate is a NEW finding that is reported to FORGE with the seed-level data (FORGE W1b, final bullet).

### AC-229 (unwanted-behavior)
GIVEN W1b is specified as measurement-only
WHEN  the re-baseline finishes
THEN  the system shall leave the target working tree clean
VERIFY: `test -z "$(git -C /home/rynaro/workspace/oss/agents/crystalium status --porcelain)"` — PASS = exit 0.

---

## W2 — `retrieve.py` micro-repairs (#46, #47)

### AC-230 (event-driven)
GIVEN a recall over more than one layer with a mocked vector store
WHEN  `Aetheryte.recall` completes
THEN  the system shall have called `vector_store.embed` exactly once
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieve_hoist_floor.py::TestEmbedHoist::test_embed_called_once_per_multi_layer_recall" -q` — PASS = exit 0, `1 passed`. At `56c8510` the call sits at `retrieve.py:524` inside the `for layer in target_layers:` loop opened at `:510`, so `layers=None` (→ `_ALL_LAYERS`, `retrieve.py:45`) yields four calls. No existing test asserts on `embed.call_count` — this is a new gate, not a re-assertion.

### AC-231 (event-driven)
GIVEN a vector store whose `embed` raises (the `CRYSTALIUM_SKIP_SLOW` shape, `vector.py:88-92`)
WHEN  a multi-layer recall runs
THEN  the system shall emit exactly one `embed_skipped` warning carrying a `layers` field
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieve_hoist_floor.py::TestEmbedHoist::test_embed_skipped_logged_once_with_layers" -q` — PASS = exit 0, `1 passed`. The per-layer `layer=layer` field at `retrieve.py:526` has no hoisted equivalent and is replaced by `layers=list(target_layers)`.

### AC-232 (event-driven)
GIVEN `explain=True` on a recall whose embed succeeds
WHEN  the explain object is read
THEN  the system shall report the same `dense_got_vector` value as the pre-hoist build
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieve_hoist_floor.py::TestEmbedHoist::test_dense_got_vector_survives_hoist" -q` — PASS = exit 0, `1 passed`. `retrieve.py:504-506` documents the flag as *"did ANY layer's embed() call return a usable vector?"*; with one hoisted call the quantifier degenerates but the `explain` contract must not.

### AC-233 (event-driven)
GIVEN `FETCH_WIDTH_FLOOR` monkeypatched to 50 with `k=1`
WHEN  a recall runs with `explain=True`
THEN  the system shall report `explain.fusion.candidate_k` equal to 50
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieve_hoist_floor.py::TestFloorLink::test_candidate_k_follows_fetch_width_floor" -q` — PASS = exit 0, `1 passed`. This test **must** be demonstrated RED against `56c8510`'s `candidate_k = max(k * 3, 10)` (`retrieve.py:508`) and the red output appended to `red-evidence.txt`. The monkeypatch must use `monkeypatch.setattr` (auto-restore): `FETCH_WIDTH_FLOOR` is a module global that `evals/fusion_gate.py:227-229` mutates with an explicit `finally` restore at `:264`; a leaked mutation poisons every later test in the process.

### AC-234 (event-driven)
GIVEN the shipped `FETCH_WIDTH_FLOOR = 10` (`retrieve.py:53`)
WHEN  a recall runs at `k` in `{1, 3, 10, 50}`
THEN  the system shall report `explain.fusion.candidate_k` equal to `max(k*3, 10)` in every case
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieve_hoist_floor.py::TestFloorLink::test_candidate_k_unchanged_at_shipped_default" -q` — PASS = exit 0, `4 passed` (parameterised).

### AC-235 (event-driven)
GIVEN the W2 branch rebased onto the merged post-W1 `main`, so the only delta against `eval-after.json`'s tree is W2's own diff
WHEN  `PYTHONHASHSEED=0 python -m evals fusion-gate` runs in the W2 worktree
THEN  the system shall produce output byte-identical to `eval-after.json`'s seed-0 `fusion-gate-run` record
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && docker compose run --rm -e PYTHONHASHSEED=0 crystalium python -m evals fusion-gate > /tmp/w2-fg-seed0.json && jq -S . /tmp/w2-fg-seed0.json > /tmp/w2.n && jq -S '[.[]|select(.gate=="fusion-gate-run" and .seed=="0")][0].output' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-after.json > /tmp/ref.n && diff -q /tmp/w2.n /tmp/ref.n` — PASS = `diff` exits 0. **Precondition on the comparison, not on the code:** `git -C /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve merge-base --is-ancestor <post-W1-main-sha> HEAD` must exit 0 first; otherwise the diff spans two changes and proves nothing (`spec.md` §2.4.4, correction S-5).

### AC-236 (event-driven)
GIVEN the W2 branch
WHEN  the fast suite runs in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w2-retrieve && make test-fast` — PASS = exit 0. In particular `mcp-server/tests/test_fusion_weighting.py` (not W2-owned; mirrors the `max(k*3, 10)` formula at `:273` and asserts the `explain.fusion` key set at `:499`) must remain untouched and green.

---

## W3 — retrieval-gate deconfound (#43, N-5)

**Design constraint D-1 (planner-imposed, so the gate's own failure modes are cheaply falsifiable).**
`evals/retrieval_gate.py` exposes a **pure** verdict resolver — signature
`resolve_verdict(*, edge_counts: dict[str, int], expected_edges: int, embeddings_ok: bool) -> str` —
that `run()` calls. Precedence is fixed: `embeddings_ok` false ⇒ `"inconclusive"`; else any arm
whose edge count differs from `expected_edges` ⇒ `"confounded"`; else the honest verdict. Tests on
the pure function are **unmarked** and therefore run under `make test-fast`
(`Makefile:31`, `-m "not slow"`), which is what makes AC-241/AC-242/AC-243 real gates rather than
tests the fast suite silently skips.

### AC-240 (event-driven)
GIVEN `Config.link_cooccurrence` defaulting to `None`, meaning "follow `recall_completion`"
WHEN  `_build_components` wires the episodic and semantic layers
THEN  the system shall pass the same value it passed at `56c8510` for every configuration that leaves the new field unset
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieval_gate.py::TestLinkCooccurrenceWiring::test_none_follows_recall_completion" -q` — PASS = exit 0, `2 passed` (parameterised over `recall_completion` true/false). Anchors: `server.py:533` and `server.py:546` (the issue text says 522/535 — the scout's numbers win, and both were re-derived at HEAD).

### AC-241 (event-driven)
GIVEN edge counts equal to `expected_edges` in all four arms with embeddings available
WHEN  `resolve_verdict` is called
THEN  the system shall return the honest verdict string
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieval_gate.py::TestResolveVerdict::test_resolve_verdict_honest_when_isolated" -q` — PASS = exit 0, `1 passed`.

### AC-242 (unwanted-behavior)
GIVEN any arm whose post-commit edge count differs from `expected_edges`
WHEN  `resolve_verdict` is called with embeddings available
THEN  the system shall return `"confounded"`
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieval_gate.py::TestResolveVerdict::test_resolve_verdict_confounded_when_edges_exceed_expected" -q` — PASS = exit 0, `1 passed`. This is the isolation self-check's own falsifiability proof: a gate that cannot emit `"confounded"` cannot detect the confound it was written to remove.

### AC-243 (unwanted-behavior)
GIVEN embeddings unavailable (`CRYSTALIUM_SKIP_SLOW` set, `vector.py:88-92` raising)
WHEN  the retrieval gate runs
THEN  the system shall return the verdict `"inconclusive"` with no numeric axes
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && make test-fast 2>&1 | grep -E "test_(resolve_verdict_inconclusive_when_embeddings_unavailable|run_emits_no_numbers_when_inconclusive)"` — PASS = both node names appear with `PASSED`, i.e. `make test-fast` collected them. The two tests **must be unmarked** (no `@pytest.mark.slow`) and **must set `CRYSTALIUM_SKIP_SLOW` themselves** via `monkeypatch.setenv`; both existing tests in that file carry `@pytest.mark.slow` (`test_retrieval_gate.py:18, 28`), so a marked test is filtered out by `-m "not slow"` and the oracle would be vacuous (`spec.md` §2.5.4(b), correction S-6).

### AC-244 (event-driven)
GIVEN the deconfounded fixture pinning `link_cooccurrence=False` in every arm
WHEN  each of the four arms finishes committing its 31 crystals
THEN  the system shall count exactly two edges in every arm
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieval_gate.py::TestIsolation::test_gate_reports_two_edges_in_every_arm" -q` — PASS = exit 0, `1 passed`. Two = the explicit `hub→spoke1→spoke2` chain at `retrieval_gate.py:107-110`. At `56c8510` the `comp`/`both` arms additionally carry up to ~150 co-occurrence edges (31 commits × `cooccurrence_limit=5`, `episodic.py:58/101-104`).

### AC-245 (event-driven)
GIVEN the fixture stamping a distinct `created_at` per commit
WHEN  the corpus is inspected in the relational store
THEN  the system shall hold 31 distinct `created_at` values
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && docker compose run --rm crystalium pytest "mcp-server/tests/test_retrieval_gate.py::TestIsolation::test_created_at_strictly_increases_across_commits" -q` — PASS = exit 0, `1 passed`. At `56c8510`, `retrieval_gate.py:26/61` stamps one `_T0` on all 31 rows, `relational.py:356` writes it to the column, and `relational.py:648-652`'s `ORDER BY created_at DESC` is a total tie with no `id ASC` term (contrast `relational.py:919`) and no index (`relational.py:90-93`).

### AC-246 (unwanted-behavior)
GIVEN the corrected module docstring
WHEN  the file is inspected
THEN  the system shall no longer contain the false isolation claim
VERIFY: `grep -c "Edges are seeded in EVERY arm" /home/rynaro/workspace/oss/agents/crystalium-w3-gate/evals/retrieval_gate.py` — PASS = prints `0`. The sentence at `evals/retrieval_gate.py:12-13` is the claim #43 disproves.

### AC-247 (event-driven)
GIVEN W1 merged, so multi-seed expansion is real
WHEN  the deconfounded gate runs over the seven seeds
THEN  the system shall report a verdict other than `"confounded"` on every seed
VERIFY: `jq -e '[.[]|select(.gate=="retrieval-gate-deconfounded")] | length==14 and (map(.output.verdict != "confounded")|all)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/eval-baseline-deconfounded.json` — PASS = exit 0.

**AMENDMENT A-2 (protocol strengthened: 7 → 14 records).** The frozen protocol varied only `PYTHONHASHSEED`. Measurement showed that is the WRONG axis: at a fixed seed the gate returned `context_rank.both` = 4 on one run and 5 on the next (commit `7918094`), and after W4 a fixed seed produced `completion_pass` false then true on consecutive runs (`d3566f9`). The dominant variance source is uuid4-fresh crystal ids under a tied `created_at`, which the hash seed does not touch — so a 7-record single-run-per-seed capture cannot detect the instability it exists to rule out. The protocol is therefore **two runs per seed** (14 records, seeds labelled `<seed>-a` / `<seed>-b`), which is what makes the post-W3 determinism claim falsifiable. This strengthens the criterion; it does not relax it.

### AC-248 (event-driven)
GIVEN the deconfounded measurement complete
WHEN  the `recall_completion` earned-ON justification is re-examined
THEN  the system shall carry a `config.py:199` comment consistent with the measured outcome
VERIFY: `grep -n "EARNED ON" /home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/config.py` — PASS = **either** the line quotes the *new* figures recorded in `eval-baseline-deconfounded.json` (lift survived) **or** the phrase is absent and the change folder holds the filed default-flip issue reference (lift did not survive).

**AMENDMENT A-3 (evaluate on the merged tree, not the W3 worktree).** The frozen path pointed at `crystalium-w3-gate`, but W3's branch does **not** contain W1's `neighbor_expand` fix, and the two interact: measured on W3 alone the completion lift disappears (`completion == flat == 0.3077`) and W3 accordingly RETRACTED the earned-ON claim; measured on the merged tree the lift is real and stable (`flat 0.3077 → completion 0.4615`, single distinct value across all 14 runs). Evaluating this criterion at the W3 worktree therefore certifies a superseded measurement. The binding path is the merged tree, where the retraction is withdrawn and the honest branch is "lift survived → quote the new figures". The withdrawn retraction is recorded in-comment so a future reader does not re-derive it. Both branches were pre-ruled by FORGE; the default stays `True` this campaign either way. The same branch governs `test_retrieval_gate.py:19-25`'s assertion (`spec.md` §2.5.4(a), correction S-7) — a fabricated pass there is tamper evidence, not a fix.

### AC-249 (event-driven)
GIVEN the W3 branch
WHEN  the fast suite runs in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w3-gate && make test-fast` — PASS = exit 0.

---

## W4 — relational recency determinism (N-2)

### AC-250 (event-driven)
GIVEN several active crystals in one project sharing an identical `created_at`
WHEN  `recent_crystal_ids` is called repeatedly across separate connections
THEN  the system shall return the same id list every time
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w4-relational && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_relational.py::TestRecentCrystalIds::test_recent_crystal_ids_ties_break_by_id_ascending" -q` — PASS = exit 0, `1 passed`. Must be demonstrated RED against `56c8510`'s `ORDER BY created_at DESC LIMIT ?` (`relational.py:651`) where the tie order is a SQLite scan artefact; the red output is appended to `red-evidence.txt`.

### AC-251 (event-driven)
GIVEN crystals with strictly distinct `created_at` values
WHEN  `recent_crystal_ids` is called
THEN  the system shall return the same order it returned at `56c8510`
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w4-relational && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_relational.py::TestRecentCrystalIds::test_recent_crystal_ids_preserves_order_for_distinct_timestamps" -q` — PASS = exit 0, `1 passed`.

### AC-252 (event-driven)
GIVEN an existing database opened twice
WHEN  the schema DDL executes on each open
THEN  the system shall hold exactly one `idx_crystals_created_at` index without raising
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w4-relational && docker compose run --rm crystalium pytest "mcp-server/tests/test_storage_relational.py::TestRecentCrystalIds::test_created_at_index_exists_and_is_idempotent" -q` — PASS = exit 0, `1 passed`. The index must be `CREATE INDEX IF NOT EXISTS`, sitting beside `relational.py:90-93`, so an existing store migrates in place with no migration script.

### AC-253 (event-driven)
GIVEN the W4 branch
WHEN  the storage suite runs in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w4-relational && make test-storage` — PASS = exit 0.

### AC-254 (event-driven)
GIVEN the W4 branch
WHEN  the fast suite runs in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium-w4-relational && make test-fast` — PASS = exit 0.

---

## W5 — release

### AC-260 (event-driven)
GIVEN the mandate at `CHANGELOG.md:105-108` requiring the re-baseline to be named
WHEN  the v1.11.0 entry is written
THEN  the system shall reference both baseline artefacts together with the three re-run criteria
VERIFY: `awk '/^## \[?1\.11\.0/,/^## \[?1\.10\.0/' /home/rynaro/workspace/oss/agents/crystalium/CHANGELOG.md > /tmp/e.md && grep -q eval-before.json /tmp/e.md && grep -q eval-after.json /tmp/e.md && grep -q AC-124 /tmp/e.md && grep -q AC-125 /tmp/e.md && grep -q AC-133 /tmp/e.md && grep -q "DP-2" /tmp/e.md` — PASS = exit 0.

### AC-261 (event-driven)
GIVEN the release version 1.11.0
WHEN  the version strings are inspected
THEN  the system shall report 1.11.0 from both declaration sites
VERIFY: `grep -c '^version = "1.11.0"' /home/rynaro/workspace/oss/agents/crystalium/mcp-server/pyproject.toml && grep -c '_FALLBACK_VERSION = "1.11.0"' /home/rynaro/workspace/oss/agents/crystalium/mcp-server/src/crystalium/__init__.py` — PASS = both print `1`. These are the only two sites (`mcp-server/pyproject.toml:8`, `mcp-server/src/crystalium/__init__.py:8`); neither lies in a W1–W4 owned file.

### AC-262 (event-driven)
GIVEN all units merged to `main`
WHEN  the full suite runs in-container
THEN  the system shall exit 0
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium && make test` — PASS = exit 0. This is the run that surfaces the `strict=True` xfail contingency (`test_fusion_gate.py:102`); `make test-fast` cannot, because the slow-marked gates are filtered out.

### AC-263 (unwanted-behavior)
GIVEN ESL P0-9 requiring maker≠checker on a public release
WHEN  the change record is inspected before the tag
THEN  the system shall name a checker different from the maker
VERIFY: `jq -e '.maker=="vivi" and .checker=="kupo" and .maker != .checker' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/change.json` — PASS = exit 0.

---

## Campaign-wide

### AC-270 (unwanted-behavior)
GIVEN five branches specified to own disjoint file sets
WHEN  the changed-file sets of every pair are intersected
THEN  the system shall report an empty intersection for every pair
VERIFY: `B=56c8510; for a in w1-graph w2-retrieve w3-gate w4-relational; do for b in w1-graph w2-retrieve w3-gate w4-relational; do [ "$a" \< "$b" ] || continue; comm -12 <(git -C /home/rynaro/workspace/oss/agents/crystalium-$a diff --name-only $B..HEAD|sort) <(git -C /home/rynaro/workspace/oss/agents/crystalium-$b diff --name-only $B..HEAD|sort); done; done | tee /tmp/isect; test ! -s /tmp/isect` — PASS = exit 0 (empty output). Any shared path is an isolation breach: STOP (VP-S6).

### AC-271 (unwanted-behavior)
GIVEN each unit's declared ownership table (`spec.md` §1)
WHEN  a unit's changed-file set is compared with its declared set
THEN  the system shall report no file outside the declared set
VERIFY: per unit, `git -C <worktree> diff --name-only 56c8510..HEAD` — PASS = every printed path appears in that unit's `spec.md` §1 row. W1's row includes `mcp-server/tests/test_fusion_gate.py` **only** under the §2.2.6 XPASS contingency; its appearance without a recorded XPASS measurement is drift.

### AC-272 (unwanted-behavior)
GIVEN W5 as the sole owner of `CHANGELOG.md` and the version strings
WHEN  the four code branches are inspected
THEN  the system shall show none of them touching those files
VERIFY: `for w in w1-graph w2-retrieve w3-gate w4-relational; do git -C /home/rynaro/workspace/oss/agents/crystalium-$w diff --name-only 56c8510..HEAD | grep -E '^(CHANGELOG\.md|mcp-server/pyproject\.toml|mcp-server/src/crystalium/__init__\.py)$'; done | tee /tmp/own; test ! -s /tmp/own` — PASS = exit 0 (empty output).

### AC-273 (unwanted-behavior)
GIVEN the REPORT set is out of scope (`spec.md` §4)
WHEN  the union of all four branch diffs is inspected
THEN  the system shall show no change to the REPORT surfaces
VERIFY: `for w in w1-graph w2-retrieve w3-gate w4-relational; do git -C /home/rynaro/workspace/oss/agents/crystalium-$w diff 56c8510..HEAD -- mcp-server/src/crystalium/storage/relational.py | grep -E '^\+.*bm25_search|^\+.*status\s*=\s*.active' ; git -C /home/rynaro/workspace/oss/agents/crystalium-$w diff --name-only 56c8510..HEAD | grep -E '^evals/fusion_gate\.py$'; done | tee /tmp/rep; test ! -s /tmp/rep` — PASS = exit 0 (empty output). Covers #44 (no status predicate on the shared `bm25_search`, `retrieve.py:605-611`) and #45/#48 (`evals/fusion_gate.py` untouched). #42's fence is checked separately: `git -C /home/rynaro/workspace/oss/agents/crystalium-w1-graph diff 56c8510..HEAD -- mcp-server/src/crystalium/storage/graph.py | grep -E 'exclude_seeds|include_seeds'` must print nothing.
