# verification-plan.amend-01 — `crystalium-residual-eight-plan`

**Amendment `amend-01`.** `verification-plan.md` is NOT edited. Where a section appears below,
this file governs; sections not listed stand as originally written.

Companions: `spec.amend-01.md` (spec sections + findings ledger),
`spec.criteria.amend-01.md` (criteria + the five global command rules).

MAIN = `/home/rynaro/workspace/oss/agents/crystalium`
CHANGE = `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan`
NEXUS = `/home/rynaro/workspace/oss/agents/eidolons`
ART = `MAIN/evals/results` (host) ⇔ `/app/evals/results` (container) — already gitignored at
`b7f1a47`.

---

## 0. Execution rules — AMENDED (adds rules 8-10)

Rules 1-7 of `verification-plan.md` §0 stand unchanged (container-only; never `2>/dev/null`;
three suite modes; never assert on `crystalium.__version__` from a bind-mounted dev container;
one worktree per unit; the C-2 seed protocol; never diff across a fixture change).

**8. NEVER pipe a gate's raw stdout into `jq` (K-B15).** The shipped evals write structlog to
**stdout** ahead of their JSON — measured, `kb15-stdout-contamination.md`. Use the artifact
form (`emit(result, '/app/evals/results/<name>.json')`, then `jq` the file), or — only for the
frozen `evals/fusion_gate.py` — `awk '/^\{/{f=1} f'` into a file first. **Every jq predicate
carries a parse/type guard, and exit 2/5 means "the artifact did not parse", NOT "the gate is
red".** Recording a 2/5 as a red is itself a finding. *This defect first surfaced as a 7-seed
VP-B3 capture that returned `rc=0` on all seven runs with an EMPTY `gate_pass` — exit 0, no
signal.*

**9. NEVER assert the negation of a failure value (VP-B4).** `gate_pass: null` is a **live
value in this repo** (`retrieval-gate` under `CRYSTALIUM_SKIP_SLOW=1`), and
`jq -e '.gate_pass != false'` **exits 0 on it**. Assert the positive: `== true`, an exact
number, a type guard.

**10. A 7-seed protocol spawns 7 PROCESSES (K-B3 / K-N17).** `PYTHONHASHSEED` is read by
CPython before `main()`. Six runs with `-e PYTHONHASHSEED=$s` for `s ∈ {0..5}`, and a
**seventh that omits `-e` entirely** (`-e PYTHONHASHSEED=` sets it *empty*, not *unset*).
`--seeds 7` in one process is **never** the protocol.

---

## 1. Baseline capture — **DISCHARGED** (K-N13)

`verification-plan.md` §1's baseline is **captured**; see `CHANGE/baseline-verdict.md`.

| id | result | verdict |
|---|---|---|
| VP-B5 | `b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc` | matches required `b7f1a47` |
| VP-B1 `make test` | `998 passed, 2 skipped, 1 xfailed` (848.76s) | GREEN |
| VP-B2 `make test-ci` | `994 passed, 6 skipped, 1 xfailed` (299.41s) | GREEN |
| VP-B3 fusion-gate × 7 seeds | 7/7 `gate_pass: true`, `weighted.target_rank == 0` on all 7 | GREEN — **S-6 does not fire** |
| VP-B4 retrieval-gate | `SKIP_SLOW=1` ⇒ `verdict: "inconclusive"`, `gate_pass: null`; default ⇒ `gate_pass: true` | as predicted — the N-5 honesty branch works |

**S-9 does not fire.** The two suites differ in **counts** (998/2 vs 994/6) but not in
**outcome**: both green, zero failures, zero errors. The 4-test delta is SKIP_SLOW converting
slow tests to skips. Recorded so it is not later rediscovered and misread as drift.

**VP-B4 settles spec.md §0.3 by measurement.** A gate built on the retrieval-gate template
contributes **nothing** under `make test-ci` — the mode CI actually runs. NC-3 stands, and
every new gate in this campaign uses the fusion-gate template.

**Two capture defects were found and are now execution rules 8 and 9** (see §0). Both share
one shape: *a command that exited 0 while telling us nothing.*

---

## 2. VP-M1 — REWRITTEN (K-B7; FORGE D5)

*(Supersedes `verification-plan.md:50-72` in full.)*

### 2.1 Why the original could not run

VP-M1 drove `run_floor_probe(floor=…, weighted=False)`. That symbol **exists** with exactly
that keyword-only signature (`fusion_gate.py:290-292`) — but it returns `run_arm`'s dict,
`{"target_rank", "retrieved", "cross_layer"}` (`fusion_gate.py:266`), with **no derived-arm
field**, and `run_arm` never passes `explain=True` (`:250-253`). `floor10_derived` /
`floor1000_derived` were structurally unobtainable, and AC-321's `has(...)` was a **shape**
check on a file the maker writes — it could not fail on the measurement being wrong, while
gating the entire W-G-FLOOR unit.

### 2.2 The probe (normative)

**Location: `evals/floor_sensitivity_gate.py` — W-G-FLOOR's own new file — as
`vp_m1_probe(*, floor: int) -> dict`.** `evals/fusion_gate.py` stays **byte-untouched**; no
fence exception exists or is needed.

1. `from evals.fusion_gate import _build_fixture, run_floor_probe` — **imports are reads, not
   edits**. §3.1's freeze governs the file's bytes and the AC-125 measurement; an import
   disturbs neither.
2. Build the stores and `Aetheryte` with **exactly** `run_arm`'s construction flags
   (`completion=True, completion_max_hops=1, completion_decay=0.5, recall_active_only=False,
   recall_relevance_primary=True`, weights from `Config` — `fusion_gate.py:232-249`).
3. **Wrap the real `GraphStore` in a thin recording proxy** that delegates every method and
   records the return values of `decaying_walk` and `neighbor_expand`. Pass the proxy to
   `Aetheryte`. `floorN_derived` := the **sorted union of ids the walk actually returned**.
   This is the membership the prediction is about, captured where it is produced — no
   re-implementation of `retrieve.py` internals, and no reliance on `explain`, which carries
   only `arm_sizes` (`retrieve.py:1098-1104`): **sizes, not membership**.
4. Apply the `FETCH_WIDTH_FLOOR` monkeypatch in `try/finally` (`fusion_gate.py:227-229, 264`).
5. **Self-check.** The probe also calls `run_floor_probe(floor=floor, weighted=False)` on a
   **fresh data dir** and asserts its own `{target_rank, retrieved}` equals it, recording
   `self_check_ok`. If `fusion_gate`'s recall path drifts, the probe **invalidates itself
   loudly** rather than measuring a divergent construction.

### 2.3 Protocol — 7 spawned processes

```
( cd /home/rynaro/workspace/oss/agents/crystalium && for s in 0 1 2 3 4 5; do docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_seed(seed_label='$s'), '/app/evals/results/m1-seed-$s.json')" || exit 1; done )
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_seed(seed_label='unset'), '/app/evals/results/m1-seed-unset.json')"
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && jq -s '{seeds: ., channel_live: (any(.[]; .floor10_derived != .floor1000_derived))}' evals/results/m1-seed-0.json evals/results/m1-seed-1.json evals/results/m1-seed-2.json evals/results/m1-seed-3.json evals/results/m1-seed-4.json evals/results/m1-seed-5.json evals/results/m1-seed-unset.json > /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```

The seventh run **omits `-e` entirely** (K-N17).

### 2.4 Aggregate JSON schema

```json
{
  "seeds": [
    { "seed": "0",
      "floor10_derived":     ["..."],   "floor1000_derived":     ["..."],
      "floor10_retrieved":   ["..."],   "floor1000_retrieved":   ["..."],
      "floor10_target_rank": 0,          "floor1000_target_rank": 0,
      "self_check_ok": true }
  ],
  "channel_live": false
}
```

`channel_live := any(seed.floor10_derived != seed.floor1000_derived)` — **derived membership**,
not the fused list.

### 2.5 AC-321's corrected consistency predicate

```
jq -e '(type == "object") and (.seeds | type == "array") and ((.seeds | length) == 7) and (all(.seeds[]; (.floor10_derived | type == "array") and (.floor1000_derived | type == "array") and (.self_check_ok == true))) and (.channel_live | type == "boolean") and (.channel_live == ([.seeds[] | .floor10_derived != .floor1000_derived] | any))' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```
**PASS = exit 0.** The verdict must be **derivable from the recorded per-seed evidence in the
same file** — a fabricated `channel_live` that disagrees with its own rows FAILS. *Verified
during the amendment pass: flipping `channel_live` to `true` against identical rows returns
exit 1; the original `has(...)` form returned exit 0 on the same file.*

### 2.6 THE PRELIMINARY CAPTURE IS A ONE-SIDED PROXY AND CONFIRMS NOTHING

`CHANGE/vp-m1-floor-channel.json` currently holds a **`retrieved`-only** 7-seed capture already
executed by the maker. Every seed, both arms, reports
`f10_retrieved == f1000_retrieved` and `differ: false`.

**Stated explicitly, as FORGE D5 requires:**

- Differing fused lists would **REFUTE** channel-dead. They did not differ ⇒ **nothing is
  refuted.**
- **Identical fused lists do NOT CONFIRM channel-dead.** The derived memberships can differ
  while the fused surface is masked by weights or by the id-ascending tie-break — which is
  exactly what `test_fusion_gate.py:60-73` and `fusion_gate.py:152-157` claim is happening on
  this fixture. The tree carries the **opposite**, channel-is-live claim in prose.
- Therefore the preliminary capture is **uninformative about `channel_live` as D5 defines it**.
  It is evidence of *fused-surface invariance only*, and **must not be cited as confirmation of
  `spec.md` §4 #48's prediction.**
- **Action:** preserve it as `CHANGE/vp-m1-floor-channel.preliminary.json`; the D5 probe's
  output takes the canonical name. Carrying "channel dead" forward on a proxy that cannot see
  the channel is the campaign's own named defect class.

### 2.7 Routing — unchanged either way

`channel_live == false` ⇒ `spec.md` §4 #48's prediction **confirmed**; carry it.
`channel_live == true` ⇒ **refuted**; carry the tie-break explanation instead, and do **not**
carry the refuted claim forward. **Either way the new between-floors fixture is built** — the
design is right in both branches; only the prose differs.

**Reversal (D5):** if the recording proxy perturbs the measurement (e.g. `Aetheryte` type-checks
its `graph_store`, or the proxy shifts hash iteration order), the seam capture is invalid and
the fallback is the `retrieved`-only redefinition **with its one-sidedness stated in the
artifact**. If a future `explain` schema adds arm **membership**, the proxy is retired in
favour of `explain=True`.

---

## 2A. VP-M2 — NEW: the artifact that gates W-45 (FORGE D1)

*(Supersedes `verification-plan.md:74-81`. This is the change that turns "RED by construction"
from an adjective into an obligation.)*

VP-M2 runs the rebuilt G-XL gate (§B.2 of `spec.amend-01.md`) on `b7f1a47` and **writes
`CHANGE/vp-m2-gxl-red.json`**. **W-45 may not start until that artifact exists and passes.**

**Commands:**
```
cd /home/rynaro/workspace/oss/agents/crystalium && git rev-parse HEAD
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.cross_layer_gate as m; m.emit(m.run(), '/app/evals/results/cross-layer-gate.json')"
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_cross_layer_gate.py -v
```
```
cp /home/rynaro/workspace/oss/agents/crystalium/evals/results/cross-layer-gate.json /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m2-gxl-red.json
```

**Artifact schema (`CHANGE/vp-m2-gxl-red.json`):**
```json
{
  "tree_sha": "b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc",
  "verdict": "measured",
  "target_rank": 3,
  "expected_blocked_rank": 3,
  "sparse_ranking": ["ep1", "ep2", "ep3", "sem-target"],
  "liveness": {
    "corpus_per_layer": 3, "candidate_k": 15, "k": 5,
    "sparse_arm_size": 4, "dense_arm_size": 0,
    "edge_count": 0, "node_count": 4,
    "global_bm25_rank0": "sem-target"
  }
}
```

**Entry gate (all three must hold):** `tree_sha == b7f1a47…`; AC-310's predicate exit 0;
AC-312's predicate exit 0. Any liveness conjunct red is a **fixture bug**, not an S-3 event
(S-13 step 1).

**A corpus-level pre-measurement is already recorded** (`spec.amend-01.md` §B.2.1): in the
pinned SQLite 3.46.1 build, the TF/document-length corpus produces a **strict total order**
with `sem-target` at global rank 0. That discharges D1's REVERSAL CONDITION at the corpus
level. **It does not discharge VP-M2**, which measures the *fused* rank through
`Aetheryte.recall`.

---

## 2B. VP-M3 through VP-M8 — deltas

| id | delta |
|---|---|
| **VP-M3** (corpus scaling) | Unchanged in intent. Now emits an artifact and asserts `sparse_arm_size == candidate_k` **exactly** — if it is anything else the fetch was **not** censored and the gate is measuring something else. Small-corpus control stays a mandated GREEN on the pre-fix tree (which is why **S-8** had to be rewritten — K-N20). |
| **VP-M4** (weight discrimination) | *"3 weights × 7 seeds = 21 cells"* now means **7 spawned processes × 3 cells each** (K-B3). The injection point is `Aetheryte.__init__` and the value **must be read back off the instance** (`weight_readback`), never off the kwarg dict — that is a tautology and cannot fail. No verdict is asserted on the sub-1.0 cells (C-9). |
| **VP-M5** (§D2 identity refresh) | **STRUCK** (K-B6; FORGE D4). The harness does not exist and is not built. Replaced by the binding forward obligation: any future change to combiner arithmetic (`weighted_rrf_merge_scored`, the RRF constant, `fusion_weight_*` semantics) MUST build and run it as a precondition of that change. |
| **VP-M6** (floor sensitivity) | 7 spawned processes; the disjointness predicate gains **non-empty and `>= 0` guards** (K-B3's vacuous pass: `|[] − []| == |[]|` is `0 == 0`). |
| **VP-M7** (Wave-2 differentials) | Unchanged, **plus**: record `explain.fusion.{n_sparse_cap, selectivity, w_sparse, arm_sizes}` pre/post **per Option-A path** (all-layers global, single-layer filtered, strict-subset global+backstop). D3's reversal condition reads this: if the global cap pins `selectivity` to 0.0 on realistic fixtures, the **cap semantics** reopen — bounded to censoring-signal definitions, **never** to reverting the score-space merge. |
| **VP-M8** (wire non-regression) | Use `compare_wire.py`, which **already exists** in the same archive directory and was never mentioned (K-N16). It is mechanical (exit 0 = identical modulo documented exclusions; exit 1 = regression) and compares tool names, descriptions, `inputSchema`, capabilities, `protocolVersion`, **`isError` on every path**, error payload text and record shapes **verbatim** — excluding only `serverInfo.version` (NC-6: `__version__` derives from installed METADATA) and volatile record keys whose **presence is still asserted**. The human-judged `diff` is replaced. Commands: AC-361. |

---

## 3. STOP conditions — amended table

Identical ids to `spec.md` §6 / `spec.amend-01.md` §C.

| id | trigger (mechanical) | action |
|---|---|---|
| **S-1** | AC-352 part (i) returns `p1_recreated: true`, **or** its part (ii) positive control cannot produce `true` at `w_derived = 100.0`, **or** a post-#41 multi-seed run shows relaxation regressing multi-hop F1 | keep seed exclusion; close #42 policy-affirmed **with the measurement**; do not ship. *(The control clause is new — K-N15: without it a degenerate fixture reports `false` and S-1 can never be cleared honestly.)* |
| **S-2** | any gate red at `fusion_weight_derived = 1.00`, **or** AC-370's guard shows the default moved off 1.0 | STOP before any `config.py` edit (AC-136 contingency) |
| **S-3** | `CHANGE/vp-m2-gxl-red.json` reports `target_rank != expected_blocked_rank` **with all AC-312 liveness conjuncts green** | **S-13.** Liveness red is a fixture bug, not S-3 (S-13 step 1). Terminal branch = class (a): #45 premise-refuted, W-45 cancelled, v2.1.0 re-scopes to W-44 (per-layer AC-348) + W-42 |
| **S-4** | AC-311 red on `b7f1a47` | fixture's BM25 assumption wrong; gate red for the wrong reason |
| **S-5** | AC-322 cannot be made disjoint at any fixture shape | **S-13 class (c)**: retire AC-138/AC-139 with a mechanism note; issue comment says *retired*, not *discharged*; **no permanent strict-xfail** |
| **S-6** | AC-344 not 7/7 after any unit | contingency six |
| **S-7** | AC-315 red (small corpus still loses the planted record) | gate not measuring truncation ⇒ **S-13 class (b)**: WONTFIX #47 with a named production reopen signal |
| **S-8** | **REWRITTEN (K-N20).** A gate's **defect-asserting node** — the single node named in that gate's AC as RED-on-`b7f1a47` (G-XL: AC-310; G-CORPUS: AC-314) — passes on the pre-fix tree | it is not a gate ⇒ **S-13**. **Does NOT apply** to a gate's controls, to negative controls, or to characterisation instruments that precede no fix (G-WD, G-FLOOR) — as originally worded S-8 fired on the plan's own mandated GREEN controls (G-CORPUS's small-corpus check). For those, the falsifiability bar is D8's checker perturbation flipping them RED |
| **S-9** | `make test`, `make test-ci` and the baked-image CI form disagree in **outcome** (not in counts) | the third mode is a release gate. *Recorded baseline delta: 998/2 vs 994/6, same outcome — that is SKIP_SLOW, not S-9* |
| **S-10** | `fence-amend.json`'s `.verdict == "DENY"` | #44 not closable as specified; re-file against the fence itself; do not ship a half-fix |
| **S-11** | a proposal to close #47 or #55 by presenting a construct as a measurement | `spec.md` §5.1 / §5.2 ⇒ **S-13 class (b)** |
| **S-12** | **MECHANISM REPLACED (K-B11).** A unit's branch diff contains a file outside that unit's literal §2/§B.1 ownership row | DRIFT: `ramza-freeze --amend --reason` or revert. **`ramza-drift` cannot detect this** — it checks one plan-level `declared_scope` and the union of all units' files *is* that scope, so every cross-unit overlap reports clean. See §5 for the replacement command. |
| **S-13** | **NEW** — a gate is green with fully green liveness and cannot be made to fail on its defect | the **Unfailable-Gate Disposition ladder**; `spec.amend-01.md` §C.1, in full. Common terminal action for S-3, S-5, S-7, S-8 |

---

## 4. Red-check protocol (NC-1) — §4's TABLE REPLACED WHOLESALE (K-B9; FORGE D8)

For **every** artifact, the maker records to `CHANGE/red-evidence.json` — **now the same
structured schema as the checker's file**, so the anti-replay diff step has structured input on
both sides:
`(gate, unit, axis, perturbation_patch, command, tree_sha, exit_code, output_tail, restore)`.

**The checker does NOT replay that file.** The checker applies **their own perturbation on a
different AXIS** and confirms red, recording `CHANGE/checker-redcheck.json` (v2.0.2) and
`CHANGE/checker-redcheck-v2.1.0.json`.

### 4.1 v2.0.2 batch — 5 rows (was 4; the count silently excluded the entrypoint gate)

| gate | maker's axis | checker's perturbation (replacement) | checker's axis | asserted RED |
|---|---|---|---|---|
| **entrypoint (#57)** | process startup (`NameError` crash in `run_stdio`) | Neutralize tool registration in `server.py` (empty tool table); the handshake completes and the process stays alive, `tools/list` returns `[]` | handshake **content** vs process liveness | `test_serve_stdio_handshake` RED on the non-empty-tool-list assertion, **with the process demonstrably alive** (no traceback in the captured stderr). *The old row (rename the `serve` subcommand) was strictly weaker than the maker's: it kills the subprocess, which a liveness-only test would also catch, so it could not validate that the handshake is genuinely parsed — the property AC-303 exists to protect.* |
| **cross-layer G-XL (#52)** | layer placement / append order | Remove ONE query term from ONE episodic filler's summary (make it a strict-subset matcher under FTS5 implicit-AND) | term coverage / **arm liveness** — the K-B1 axis | C-XL-2's `sparse_arm_size == corpus_per_layer + 1` fails ⇒ pytest node RED and the eval verdict flips to `"confounded"` ⇒ **AC-312's jq exits non-zero**. *This is the direct proof that the guard added in response to K-B1 can fire: a gate hardened because of a finding must be shown hardened, not assumed. The old row (move `sem-target` into `procedural`) was designed to keep the gate RED — and `_ALL_LAYERS` order (`retrieve.py:44`) puts `procedural` LATER, so the outcome was unchanged by construction.* |
| **corpus-scaling G-CORPUS (#47)** | corpus size `M` vs `candidate_k` | Boost the planted record's BM25 (append the query terms twice more to its summary) so it enters the top-`candidate_k` | the plant's **score-rank vs the truncation boundary** (data), not the boundary itself | **AC-314's `.planted_recovered == false` exits non-zero** (the record is now recovered) — proving the gate measures *"plant beyond the fetch window"*, not *"plant is unfindable"*. *The old row (raise `k` so `candidate_k > M`) moved the same single inequality from the other side: the maker's test with the algebra transposed.* |
| **weight-discrimination G-WD (#55)** | **none existed** — the old row was cross-labelled (the maker cell belonged to item 2's D2 harness, the checker cell to AC-352's `p1_recreated`) | Sever record `A`'s graph edge (A loses its only support) | **derived-arm membership topology** | **AC-317's ">= 2 distinct outcomes across `w ∈ {0.90, 0.95, 1.00}`" fails** — every weight produces the identical outcome: the exact degeneracy #55 reports |
| **floor-sensitivity G-FLOOR (#48)** | the edge-bearing competitor's dense rank; the floor constants | Delete the edge from the edge-bearing competitor to its phantom | **graph topology** vs rank placement | **AC-322's disjointness fails** — no derived vote exists at either floor and both distributions collapse onto the same ranks. *The old row ("run both probes at floor 1000") was the maker's own second red-check with a different constant — a direct violation of the table's own "must differ" rule.* |

### 4.2 v2.1.0 batch — 3 rows (NEW; the old table conflated the two batches)

| gate | maker's axis | checker's perturbation | checker's axis | asserted RED |
|---|---|---|---|---|
| **layer merge W-45 (#45)** | code revert of the `retrieve.py` fetch-shape hunk (AC-342) | Inflate ONE episodic filler's TF above `sem-target`, making it the legitimate global BM25 best | **data / score order** vs code presence | **AC-340** (`target_rank == 0`) RED — proves the gate tracks score order **through the global merge**, not target identity or layer label |
| **status top-up W-44 (#44)** | code presence (delete the call, keep the counter) and code constant (`HARD_TOPUP_CEILING = cap`) | Deepen the deprecated stratum: add deprecated rows until even the widened `k_wide` fetch is fully deprecated-censored | **data / recovery-impossible** vs code | **AC-346** RED (active hits unrecoverable **through the data**), **and** cross-check that `explain.fusion.sparse_topup` reports `fired: true` with recovery **absent** — the counter must describe the **fetch**, not the intention (the #36 F-V3 lesson, applied from the data side). *The old row ("mark every fixture crystal active") is deleted: under D6's `recall_active_only=True` pin it merely disarms the fixture, so AC-346 goes GREEN — a negative control mislabelled as a red-check.* |
| **seed exclusion W-42 (#42)** | default flip (AC-351) | Sever ONE threading site only: make `graph.py:272`'s subtraction unconditional again (ignore the flag at that site) | **per-site wiring** vs default value | **AC-354** (False-branch expected sets) RED on T1 **and** T2, while **AC-350** (True-branch byte-identity) stays GREEN. *Only possible because D2 threads all five sites; it converts K-B2 from a defect into the checker's sharpest instrument. The old row ("remove the `visited = set()` half only") was self-inverting and, per K-B2, could not flip anything at depth 1.* |

### 4.3 Per-gate evidence schema (both files)

**A boolean is no longer acceptable.** Per gate:

```json
{
  "gate": "cross-layer",
  "unit": "W-G-XL",
  "axis": "term coverage / arm liveness",
  "asserted_ac": "AC-312",
  "perturbation_patch": "<unified diff, verbatim>",
  "command": "<the exact command run>",
  "tree_sha": "<RC sha the perturbation was applied on>",
  "exit_code": 1,
  "output_tail": "<last 20 lines, captured>",
  "restore": { "command": "git checkout -- <path>", "exit_code": 0 }
}
```

### 4.4 Anti-replay step (mandatory, on both checklists)

Diff each `perturbation_patch` against **every** patch in the maker's `red-evidence.json`.
**Any identical patch fails AC-332 / AC-365.** Command: AC-332 part 3 / AC-365 part 2.

**Honest limit, stated:** a checker who fabricates outputs outright cannot be prevented by any
file format. The schema makes **replay detectable** (identical patch) and **fabrication
falsifiable on audit** (every recorded command re-runs against the recorded SHA). That is the
maximum a self-describing artifact can carry — and it is a real improvement over a boolean a
replayer writes identically.

**Rule (unchanged, and now enforceable):** a red-check the checker could not reproduce with an
**axis-independent** perturbation is a claim, not evidence, and the gate does not count as
verified.

**Reversal (D8):** if a listed perturbation fails to flip its gate RED on the RC tree, **that is
itself a blocking finding against the gate** (it cannot fail on that axis) and routes to
**S-13** — the row is **not** quietly swapped for an easier one. If maker and checker
independently converge on the same minimal patch, the checker documents the collision and
substitutes a second axis-distinct perturbation; the requirement is **axis independence**, not
patch-text novelty for its own sake.

---

## 5. Release checklists — REPLACED

### 5.1 v2.0.2 (gates only)

- [ ] AC-301..AC-325 green, **AC-319/AC-320 struck** (D4), **AC-325b** (W-CLI `--out`) green
- [ ] AC-330 — **all three** suite modes: `make test-ci`, `make test`, and the **baked-image CI
      form** (`docker compose build crystalium && docker run --rm -e CRYSTALIUM_SKIP_SLOW=1
      crystalium:dev pytest tests/ -v --tb=short -p no:cacheprovider`). K-N11: `make test-ci`
      is a bind-mount **proxy** for CI, not CI
- [ ] AC-331 — mechanical no-production-behaviour check (3 parts, incl. the `v2.0.1` ref guard)
- [ ] AC-332 — **5** independently re-broken artifacts, full evidence schema, non-zero exits
- [ ] **Anti-replay:** every `checker-redcheck.json` `perturbation_patch` differs from every
      patch in `red-evidence.json` (AC-332 part 3)
- [ ] AC-333 — `ramza-gate critic --author <maker> --checker <checker>` run, **and**
      `CHANGE/critic-v2.0.2.json` written with `.at > .batch_started_at` (K-B12: `ramza-gate
      status` never prints the critic, and the plan-time record already satisfied the old form)
- [ ] **S-12, per unit — REPLACES the `ramza-drift` invocation.** For **each** unit:
      ```
      cd /home/rynaro/workspace/oss/agents/crystalium && git diff --name-only v2.0.1..<unit-branch> > /tmp/unit-files.txt && comm -23 <(sort -u /tmp/unit-files.txt) <(sort -u CHANGE/ownership/<unit>.txt)
      ```
      **PASS = no output**, where `CHANGE/ownership/<unit>.txt` is that unit's **literal** file
      list from §2 / `spec.amend-01.md` §B.1. *`ramza-drift` cannot do this: it checks one
      plan-level `declared_scope`, and the union of all units' files IS that scope, so every
      cross-unit overlap reports clean.*
- [ ] Plan-level scope check, **with the `--repo` flag** (K-B11: the tool defaults `REPO="."`,
      the state file lives in the **nexus**, and `v2.0.1` is a **crystalium** tag — without
      `--repo` this command diffs the nexus and returns a convincing, silent zero):
      ```
      cd /home/rynaro/workspace/oss/agents/eidolons && ./.eidolons/ramza/bin/ramza-drift --state .spectra/plans/crystalium-residual-eight-plan.state.json --repo /home/rynaro/workspace/oss/agents/crystalium --range v2.0.1..HEAD
      ```
- [ ] `ramza-freeze --amend --reason "amend-01: FORGE D1-D9 + Kupo K-B1..K-B16, K-N1..K-N21"`
      recorded against the frozen criteria hash
      `eb0492ff1ac778499f89c8f4c70b1c919fbd9e3a83c83da630f022890da8908e`
- [ ] **ESL record conformance (K-N14):** `change.json` `status` advanced, `acceptance_checks`
      populated (or both criteria files referenced by path + hash), `spec.yaml` added for C3 at
      `full` tier, `has_code: true` with the **cross-repo** note (code lands in crystalium; if
      the code-state gates cannot run cross-repo, the skip is **recorded explicitly**, never
      silently disabled by `has_code: false`)
- [ ] tag `v2.0.2`; ghcr image built + pushed (**tags are un-prefixed**)
- [ ] index digest pulled **from the ghcr registry**, not from a local build
- [ ] roster PR bumps **both** `roster/mcps.yaml` and `roster/index.yaml` in one commit
      (AC-363, run from the **nexus** — K-N18)
- [ ] nexus integrity PR: `archive_sha256` = raw tar **with prefix**, verified by hand
      (**this PR gets no CI**)
- [ ] `eidolons mcp verify` **exit 0** (AC-364). **Exit 3 = INDETERMINATE, not a pass.**
- [ ] local `.mcp.json` re-pinned (routinely forgotten)

### 5.2 v2.1.0 (behaviour)

- [ ] AC-340..AC-356 green. **Convention: AC-345 green = `XFAIL` on the tagged tree; `XPASS`
      is RED** (D7's strict-xfail sentinel)
- [ ] `CHANGE/ac345-prefix-evidence.json` records the commit-1 SHA, and the checker
      **re-ran** the node at that SHA (AC-345 part i) — a plain `git checkout`, not a
      maker-attested text file
- [ ] AC-355 (`test_subset_layer_recall_no_regression`) green — the K-N12 gate
- [ ] AC-356 (`test_topup_inert_when_active_only_off`) green — the D6 negative control
- [ ] AC-360 — all three suite modes
- [ ] AC-361 — **`compare_wire.py` exit 0** (K-N16; replaces the human-judged diff)
- [ ] AC-362 — `CHANGE/critic-v2.1.0.json` written, **and** the two per-batch records slurp to
      `length == 2` with distinct batches and ordered timestamps
- [ ] AC-365 — **3** independently re-broken v2.1.0 artifacts, each pinned to the AC it flips
- [ ] **Anti-replay** for the v2.1.0 table (AC-365 part 2)
- [ ] S-12 per-unit ownership check for W-45, W-44, W-42; plan-level `ramza-drift` **with
      `--repo`**, range `v2.0.2..HEAD`
- [ ] VP-M7 cap-semantics delta recorded **per Option-A path**; if `selectivity` is pinned to
      0.0 on realistic fixtures, D3's censoring clause reopens (bounded to signal definitions)
- [ ] CHANGELOG states plainly that recall **result order and membership change**, **and** that
      #44 was a **production defect at default deployment** (`config.py:333` → `server.py:600`)
- [ ] the same roster/nexus checklist as v2.0.2

### 5.3 Wave 3 — disposition

- [ ] Every closing comment carries a literal `DISPOSITION: <class>` line, class ∈
      `{shipped, premise-refuted, unobservable-WONTFIX, retired}` (AC-373, D9's vocabulary)
- [ ] #47 and #55 closures name their **reopen condition** (class (b) requirement)
- [ ] #48's comment says **retired**, not discharged, if S-5 fired (they are different closures)

---

## 6. What this plan does NOT license — AMENDED (additions only)

`verification-plan.md` §6's five items stand. Added:

- Any claim that `channel_live` is settled by the **preliminary** `retrieved`-only VP-M1
  capture. It is a one-sided proxy: it can refute channel-dead, it cannot confirm it (§2.6).
- Any claim that a criterion is RED when its `jq` exited **2 or 5** — that is a capture
  failure, not a gate result (execution rule 8).
- Any claim that `make test-ci` **is** CI. It is a bind-mount proxy for CI's baked-image
  invocation (§0, K-N11).
- Any claim that `ramza-drift` verified per-unit file ownership. It cannot; §5's `comm` check
  is the S-12 mechanism (K-B11).
- Any claim that AC-332/AC-365 prove the checker did not fabricate. They prove **replay is
  detectable** and **fabrication is falsifiable on audit**; nothing more (§4.4).
- Any claim that the d2-identity property was **re-measured** in this campaign. It was not; it
  stands on the recorded structural argument, and the harness is a **forward obligation** on
  the next combiner-arithmetic change (D4).
