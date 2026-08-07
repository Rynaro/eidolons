---
eidolon: ramza
kind: spec
version: 1.0.0
created_at: 2026-08-05
change_id: crystalium-residual-eight-plan
tier: full
maker: ramza
checker: kupo
target_repo: /home/rynaro/workspace/oss/agents/crystalium
target_head: b7f1a47
---

# spec — `crystalium-residual-eight-plan`

| field | value |
|---|---|
| change_id | `crystalium-residual-eight-plan` |
| ESL tier | **full** (`ramza-rightsize` score 5: novel + public-api + high stakes) |
| complexity | **12 / human_loop** (`ramza-score --rubric complexity`: scope 3, ambiguity 3, dependencies 3, risk 3) |
| maker | `ramza` (planner, read-only — this document contains no code) |
| checker | `kupo` |
| target repo | `/home/rynaro/workspace/oss/agents/crystalium` |
| target HEAD | `b7f1a47` — *"fix(telemetry): stop double-writing recall calls … v2.0.1 (#60)"* |
| nexus | `v2.16.1` |
| closes | crystalium #42 #44 #45 #47 #48 #52 #55 #57 (all eight open) |
| releases | **v2.0.2** (patch, gates only) → **v2.1.0** (minor, recall order changes) → **#47 disposition** |

Anchor convention: `path:line` always means **at `b7f1a47`**. `retrieve.py` =
`mcp-server/src/crystalium/aetheryte/retrieve.py`; `graph.py` =
`mcp-server/src/crystalium/storage/graph.py`; `relational.py` =
`mcp-server/src/crystalium/storage/relational.py`. Every anchor below was re-derived from
the working tree at `b7f1a47`, not copied from issue text (issue line numbers are stale).

---

## 0. Scope — the structural claim this plan is built on

Four of the eight issues (**#52, #55, #48, #57**) are not behaviour changes at all — they are
*"build a gate that can actually fail"* problems. Two more (**#45, #47**) are blocked behind a
missing gate. Only **#42** and **#44** are primarily code-behaviour changes, and both are
one-seam edits.

A naive issue-by-issue plan builds four overlapping fixtures. This plan builds **one
parameterised corpus rig** and **four deliberately disjoint fixture instances** on top of it,
and states below exactly where sharing is safe and where a shared instance would confound the
measurement — because this codebase has already shipped a confounded gate (#43) and a gate
that could not fail on the defect it named (#52 is that report).

### 0.1 Where sharing is SAFE (share the rig)

The following are *mechanism*, not *measurement*, and are identical across all four axes:

| shared component | why sharing cannot confound |
|---|---|
| deterministic crystal minting (`_crystal(id, layer, summary, …)`, strictly-increasing `created_at`) | fixture construction, no arm participates |
| `RelationalStore` insert loop + `GraphStore` node/edge seeding | ditto |
| the **stub dense arm** (`MagicMock.dense_search` returning a caller-supplied id list) | pins the dense arm to a *stated* ranking; removes the CI-invisibility of a real embedder (§0.3) |
| the `Aetheryte` construction harness (all flags explicit, never defaulted) | flag-explicitness is what made `fusion_gate.py` auditable |
| the **arm-liveness self-checks** (`edge_count == expected`, `len(dense_ranking) == expected`, `len(sparse_ranking) == expected`) | this is `retrieval_gate.py::resolve_verdict`'s `confounded` branch generalised — it is the anti-confound machinery itself |
| the pure **verdict classifier** pattern (no I/O, every branch reachable from in-memory inputs) | `retrieval_gate.py:91-114` precedent; makes the honesty branch falsifiable |

### 0.2 Where sharing is UNSAFE (disjoint instances, mandatory)

`retrieve.py:521-548` is a **single loop** that simultaneously (a) iterates layers in
`_ALL_LAYERS` order and (b) truncates each per-layer fetch at `candidate_k`. Layer-major
append (#45) and `candidate_k` truncation (#47) therefore produce the *same observable symptom*
— a ground-truth-relevant record missing from the fused head — through *two different causes*.
One fixture that exercises both cannot attribute. That is precisely the #43 defect class.

The deconfounding rule is mechanical and must be **asserted inside each gate**, not assumed:

| gate | the axis it measures | the other axes pinned NON-BINDING, asserted |
|---|---|---|
| **G-XL** (#52 → #45) | layer-major append order | `corpus_per_layer < candidate_k` — asserted, so truncation *cannot* be the cause. Graph store edgeless (`all_edges() == 0`), completion off. |
| **G-CORPUS** (#47) | `candidate_k` per-layer fetch width | `layers=["episodic"]` **single layer** — asserted, so layer-major ordering *cannot* be the cause. Edgeless, completion off. |
| **G-WD** (#55 → #42) | `fusion_weight_derived` / derived-arm arithmetic | single layer, `corpus < candidate_k` — asserted. Only the derived arm varies. |
| **G-FLOOR** (#48) | `FETCH_WIDTH_FLOOR` seed-width channel | single layer, `corpus < candidate_k`, tie-break-neutral ids — asserted. |

**Rule R-CONF:** any gate whose own liveness self-check reports a pinned axis at a binding
value returns verdict `"confounded"` and **never numbers** (`retrieval_gate.py:301-310`
precedent). A gate that emits numbers with a live confound is the defect, not the evidence.

### 0.3 The CI-invisibility trap (why the rig uses a stub dense arm)

`retrieval_gate.py` uses a **real** `VectorStore`, so under `CRYSTALIUM_SKIP_SLOW=1` it
returns `verdict: "inconclusive"` and no numbers (`retrieval_gate.py:117-137, 261-278`) — and
its pytest wrappers are `@pytest.mark.slow`. CI runs `SKIP_SLOW=1` **with slow tests still
selected** (`Makefile:34`, `.github/workflows/ci.yml`). Consequence: **a gate built on the
retrieval-gate template protects CI not at all.**

Every gate in this plan therefore uses the **fusion-gate template** (real `RelationalStore` +
real `GraphStore` + deterministic stub vector arm, `fusion_gate.py:223-225`). None of them is
`@pytest.mark.slow`. All four run under `make test-ci`. This is a hard requirement, not a
preference — see NC-3.

---

## 1. Dependency graph

```
                     SHIPPED at b7f1a47: #41 (neighbor_expand all-seeds + sorted frontier),
                                          #43 (retrieval-gate deconfound), #46, #47-cosmetic
                                                    │
   ┌──────────────────┬────────────────────────────┴───────────────┬──────────────────────┐
   │                  │                                             │                      │
 W-ENTRY (#57)     W-RIG  evals/_corpus_rig.py                  W-HOP (#44 fence)     [no deps]
 no deps           no deps                                      no code
   │                  │                                             │
   │      ┌───────────┼───────────────┬──────────────┐              │
   │      │           │               │              │              │
   │   W-G-XL      W-G-CORPUS      W-G-WD         W-G-FLOOR         │
   │   (#52)        (#47 gate)      (#55 fixture)  (#48)            │
   │      │           │               │              │              │
   │      │           │               └──► DP-1(b) re-check ORACLE  │
   │      │           │                        │                    │
   │      └───────────┴──── W-CLI (evals/__main__.py registration) ─┘
   │                                    │
   └────────────────────────────────────┤
                                        │
        ═══════════ retrieve.py SERIAL CHAIN (single-file contention) ═══════════
                    W-45 ──► W-44 ──► W-42 ──► [W-47-code | WONTFIX]
```

**Critical path (longest chain, 5 links):**
`W-RIG → W-G-XL → W-45 → W-44 → W-42` — the rig must exist before the cross-layer gate can be
written, the gate must be **demonstrably RED** before #45's fix is allowed to touch
`retrieve.py`, and #44 and #42 land on the *post-#45* fetch structure, not the current one.

**The real serialisation constraint is `retrieve.py`, not the issue graph.** Four of the eight
issues (#42's opt-in call site, #44, #45, #47) all edit `retrieve.py`. Under one-worktree-per-
unit they **cannot** be parallel. The parallelism in this campaign lives entirely in Wave 1
(gates and tests, file-disjoint from `retrieve.py`); Wave 2 is a rebase chain.

**A second hidden contention point:** `evals/__main__.py`. Four gate units would each want to
register a subparser. They do not: each gate module is self-contained and is driven from its
pytest wrapper by direct import (the `test_fusion_gate.py:18` precedent). CLI registration is
one trailing unit, **W-CLI**, which owns `evals/__main__.py` exclusively.

**Parallelisable:** `{W-ENTRY, W-RIG, W-HOP}` in Wave 0; `{W-G-XL, W-G-CORPUS, W-G-WD,
W-G-FLOOR}` in Wave 1 (all four depend only on W-RIG and are file-disjoint from each other).

**Coupling that is easy to miss:** #42 changes the *membership* of the derived arm; #55's
weight-discriminating fixture measures the *weight* on that arm. If #42 lands after a #55
characterisation, the characterisation is stale. The cycle is broken by re-purposing:
**W-G-WD's fixture is built in Wave 1 as the DP-1(b) re-check oracle for #42** — not as a band
characterisation (see §5 and NC-5). The band question is answered by disposition, not by that
fixture.

---

## 2. Work-unit ownership (file-disjoint, one worktree per unit)

| unit | branch | EXCLUSIVELY owns | may READ but not write |
|---|---|---|---|
| W-ENTRY | `fix/server-entrypoint-smoke-57` | `mcp-server/tests/test_server_entrypoint.py` (NEW) | `server.py`, `__main__.py` |
| W-RIG | `chore/eval-corpus-rig` | `evals/_corpus_rig.py` (NEW), `mcp-server/tests/test_corpus_rig.py` (NEW) | `fusion_gate.py` (template only) |
| W-HOP | *(no branch — ESL doc)* | `.spectra/changes/crystalium-residual-eight-plan/fence-amend.md` | — |
| W-G-XL | `feat/cross-layer-gate-52` | `evals/cross_layer_gate.py` (NEW), `mcp-server/tests/test_cross_layer_gate.py` (NEW), **and only** the `cross_layer` key rename inside `evals/fusion_gate.py:257-266` + `mcp-server/tests/test_fusion_gate.py:31-39` | everything else |
| W-G-CORPUS | `feat/corpus-scaling-gate-47` | `evals/corpus_scaling_gate.py` (NEW), `mcp-server/tests/test_corpus_scaling_gate.py` (NEW) | — |
| W-G-WD | `feat/weight-discriminating-fixture-55` | `evals/weight_discrimination.py` (NEW), `mcp-server/tests/test_weight_discrimination.py` (NEW) | — |
| W-G-FLOOR | `feat/floor-sensitivity-gate-48` | `evals/floor_sensitivity_gate.py` (NEW), `mcp-server/tests/test_floor_sensitivity_gate.py` (NEW), **and only** the xfail-marker block `test_fusion_gate.py:85-113` | `evals/fusion_gate.py` — **UNTOUCHABLE** (§3.1) |
| W-CLI | `chore/eval-cli-registration` | `evals/__main__.py` | — |
| W-45 | `fix/cross-layer-rank-blocking-45` | `retrieve.py`, `mcp-server/tests/test_retrieve_layer_merge.py` (NEW); removes W-G-XL's xfail marker | — |
| W-44 | `fix/sparse-status-blind-44` | `retrieve.py` (rebased on W-45), `mcp-server/tests/test_sparse_status_topup.py` (NEW) | `relational.py` — **fenced** (§3.2) |
| W-42 | `fix/seed-exclusion-relax-42` | `graph.py`, `mcp-server/tests/test_storage_graph.py`, `retrieve.py` (rebased on W-44, call site only) | — |
| W-REL-A / W-REL-B | `release/v2.0.2`, `release/v2.1.0` | `CHANGELOG.md`, `mcp-server/pyproject.toml:8`, `mcp-server/src/crystalium/__init__.py:8` | — |

**No unit but a release unit may touch `CHANGELOG.md` or a version string.** Both version
strings must move together; `__version__` derives from installed package **METADATA**, not the
bind-mounted source, so a dev capture reports the *image's* version — no oracle in this plan
may assert on `crystalium.__version__` from inside a bind-mounted dev container (NC-6).

---

## 3. Fences that may not be crossed silently

### 3.1 The AC-125 fixture is untouchable

`evals/fusion_gate.py::_build_fixture` and `run_arm`'s recall path are frozen. A tie-break-
neutral variant was measured to regress AC-125 from 7/7 to ~2/7 unanimous
(`test_fusion_gate.py:61-64`), and AC-125 is in AC-136's contingency six. W-G-FLOOR builds a
**new file**; it does not "fix" the old fixture. The only permitted edits to
`evals/fusion_gate.py` in this whole campaign are W-G-XL's rename of the `cross_layer` dict key
(§4, #52 item 2) — a pure key/docstring rename with byte-identical fixture construction.

### 3.2 The `bm25_search` fence (recorded FORGE ruling)

`retrieve.py:605-615` records verbatim:

> "never a status predicate on the shared `bm25_search` … no new public storage method, per
> FORGE's ruling"

echoed at `retrieve.py:241-242`. **#44 reverses this**, so it requires a spec hop (**W-HOP**)
before any code. Two shapes are pre-authorised by the ruling's own text ("a *parameterised*
future shape"); the plan's recommended shape (§4, #44) needs **neither**, because it lives
entirely caller-side in `retrieve.py`. If the hop is denied, #44 is not closable as specified
(§5). The second production consumer, `layers/episodic.py:319`, is untouched either way.

### 3.3 C-9 — no sub-1.0 "precision dial"

No test, doc, CHANGELOG line, or gate output produced by this campaign may present a sub-1.0
`fusion_weight_derived` as a supported precision dial. W-G-WD's fixture *is* a response curve
over combiner arithmetic; presenting it as characterisation violates C-9 (NC-5).

### 3.4 DP-1(b)'s recorded reversal condition

`deliberation.md §8`: DP-1(b)'s reversal fires on *"evidence that anomaly B's seed exclusion is
removed (F-B), which would restore the issue's original premise."* **#42 IS F-B.** Landing it
therefore obliges a derived-family-merge re-check, and the re-check needs an instrument that
can see derived-arm arithmetic — which no shipped gate has (that is #55's finding). Hence the
W-G-WD → W-42 ordering.

---

## 4. Approach — per issue: fix, oracle, red-check

Full EARS criteria in `spec.criteria.md`; commands with pass conditions in
`verification-plan.md`.

### #57 — no entrypoint test  ·  unit W-ENTRY  ·  no dependencies  ·  v2.0.2

**Approach.** Port the ready-made template
`/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/archive/2026-08-05-crystalium-mcp-sdk-2x-39/golden_wire.py`
into `mcp-server/tests/test_server_entrypoint.py` as a pytest node: launch
`[sys.executable, "-m", "crystalium", "serve"]` as a **subprocess**, complete
`initialize → notifications/initialized → tools/list` over stdio, assert a non-empty tool list,
close stdin, assert clean exit within a timeout. `stderr=subprocess.PIPE` (never `DEVNULL`,
never `/dev/null` — NC-4) and the captured stderr is included in every assertion message, so a
startup traceback is *visible in the failure*, not swallowed. **Not** `@pytest.mark.slow` — the
stdio handshake needs no model, so it runs under `make test-ci` where it protects CI.

HTTP: `run_http` binds a port. Recommended disposition is to **state explicitly** in the test
module docstring that `test_server.py:159-178` (`build_http_app` ASGI) covers app construction
and that the uncovered surface is `uvicorn` startup + port binding, then add an ephemeral-port
`run_http` smoke **only if** it can be made deterministic in-container within the unit's
timebox. A recorded "what this does not cover" is a closure; a flaky port test is not.

**Oracle.** `pytest mcp-server/tests/test_server_entrypoint.py -v` green, under **both**
`make test` and `make test-ci`.

**Red-check.** Insert a deliberate `NameError` at the top of `run_stdio` (the exact #39 failure
mode), observe the node RED with the traceback in the assertion message, revert. Second
red-check: replace `tools/list`'s assertion target with a tool name that does not exist and
confirm RED — proving the handshake is genuinely parsed, not just "process didn't crash".

---

### #52 — `cross_layer` axis cannot fail  ·  unit W-G-XL  ·  needs W-RIG  ·  v2.0.2

**Approach (two parts, both required).**

1. **New gate `evals/cross_layer_gate.py`, THROUGH `Aetheryte.recall`.** Fixture:
   - `episodic`: N weakly-matching crystals (one query term each), N chosen so
     `N < candidate_k` (assert it).
   - `semantic`: one `sem-target` matching **every** query term — strictly better BM25 than
     any episodic hit, and the ground-truth best record overall.
   - Dense arm: stub returning `[]` (or a neutral fixed list containing neither target nor a
     competitor). Graph: **edgeless**, `all_edges() == 0` asserted. Completion **off**.
     → the sparse arm is the **only** voter, by construction and by assertion.
   - Call `aetheryte.recall(scope, query, k, layers=None, …)`; assert
     `records[0].id == "sem-target"`.
   - Today: `sparse_ranking == [ep1…epN, sem-target]` (per-layer append,
     `retrieve.py:521-530`), so `sem-target` fuses at rank N. **RED by construction.**
   - Ship it RED as `@pytest.mark.xfail(strict=True)` citing #45 — the repo's own precedent
     (`test_fusion_gate.py:85-103`). Strict xfail is **self-enforcing**: W-45's fix turns it
     XPASS, which fails the suite until W-45 also removes the marker.
2. **Relabel the old axis.** Rename `fusion_gate.py`'s `cross_layer` key to
   `sparse_arm_per_layer_probe` and rewrite `test_fusion_gate.py`'s AC-126 docstring to say
   what it actually measures (a per-layer `bm25_search` sanity probe that never reaches
   `Aetheryte.recall`). Retiring it entirely is also acceptable; relabelling is preferred so
   the historical record survives. **Nothing else in `fusion_gate.py` may change** (§3.1).

**Oracle.** The gate is RED on `b7f1a47` and GREEN after W-45 — that *transition* is the
oracle, not either endpoint.

**Red-check (this is the inverted one — a gate that must start RED needs proof it can go
GREEN).** Two mandatory controls, both shipped as permanent test nodes:
- **C-XL-1 (single-layer control):** the same fixture with `layers=["semantic"]` must put
  `sem-target` at rank 0 **today**. If it does not, the fixture's BM25 assumption is wrong and
  the gate is red for the wrong reason → STOP (§6, S-4).
- **C-XL-2 (arm-liveness):** assert `len(sparse_ranking) == N+1`, `all_edges() == 0`,
  `dense arm empty`. Any deviation → verdict `"confounded"`, never numbers (R-CONF).

---

### #45 — cross-layer rank blocking  ·  unit W-45  ·  needs W-G-XL RED  ·  v2.1.0

**Approach — two options; the plan does not pre-decide, it names the invariant each threatens
and the gate that decides.**

- **Option A — single-fetch score merge (recommended).** Replace the per-layer loop with **one**
  `bm25_search(query, layer_filter=None, k=candidate_k * len(_ALL_LAYERS))` and post-filter
  rows whose `layer ∉ target_layers`. `bm25_search` already orders globally by
  `bm25(crystals_fts)` (`relational.py:531-541`), so this is a genuine score-space merge with
  **zero** change to the shared read path, **no** new column, **no** new public method, **no**
  status predicate. `dense_search(layer_filter=None)` is likewise supported
  (`vector.py:174-199`), so the dense arm gets the same treatment and the fix is not
  sparse-only. **Invariant it threatens:** `cap = candidate_k * len(target_layers)`
  (`retrieve.py:597`) and the censoring test `raw_n_sparse >= cap`
  (`retrieve.py:256`) change meaning when `layers` is a strict subset — #38's D3 selectivity
  boost is downstream of both. Mandatory oracle: AC-125 (`test_fusion_gate.py`) stays 7/7
  unanimous, and `explain.fusion.{n_sparse_cap, selectivity, w_sparse}` are compared
  pre/post on the *same* fixture.
- **Option B — round-robin interleave.** Keep the per-layer loop, interleave
  `layer_hits[i][j]` by `j` then `i`. **Invariant it preserves:** `cap` semantics unchanged.
  **What it does not fix:** it is still rank-space, not score-space — a semantic hit with a
  far better BM25 score still only reaches position ≤ n_layers. G-XL as specified (one
  semantic target vs N episodic) goes green under B, so **G-XL alone cannot distinguish A from
  B.** If Option B is chosen, G-XL must be extended with a second assertion (a *second*
  semantic record that must beat episodic rank 1) or the choice is unfalsifiable.

**Oracle.** G-XL flips RED→GREEN; the xfail marker is removed in the same commit;
`make test` and `make test-ci` both green; AC-125 7/7 unanimous over `PYTHONHASHSEED` 0-5 +
unset (C-2 protocol).

**Red-check.** Revert the append-order change only (keep the tests), observe G-XL RED again,
restore. Plus: assert G-XL fails when the fix is present but the fixture's semantic target is
moved into `episodic` — proving the gate is measuring *layer* and not *record identity*.

---

### #44 — bm25 status-blind  ·  unit W-44  ·  needs W-HOP + W-45  ·  v2.1.0

**Approach — bounded status-aware top-up, caller-side, fence-preserving.** In `retrieve.py`
only, after the sparse fetch: count candidates failing `_is_active` (the predicate already
defined at `retrieve.py:572-584`). If any are inactive **and** the fetch was censored
(`raw_n_sparse >= cap`), issue **at most one** additional `bm25_search` at a widened `k`
(`k_wide = min(cap + n_inactive_observed, HARD_TOPUP_CEILING)`), merge preserving BM25 order,
and dedupe. Then recompute the censoring signal against the **final** width — this is the
subtle part: `resolve_sparse_weight`'s censoring test is "was this fetch truncated?"
(`retrieve.py:229-237`), a property of the fetch actually performed, so after a top-up both
`raw_n_sparse` and `cap` must refer to the widened fetch or the boost is decided against a
fetch that no longer exists.

This adds **no** parameter to `bm25_search`, **no** public storage method, and **no** status
predicate in SQL — the fence's letter and spirit both hold. W-HOP records that the fence was
*consulted and satisfied*, not broken; if the executor instead prefers a `status_filter=`
parameter on `bm25_search`, that **does** break the fence and W-HOP must record an explicit
amend before any code.

Bound the cost: at most one extra query per recall, only on the censored-and-dirty path. Emit
`explain.fusion.sparse_topup: {fired: bool, k_initial, k_final, n_inactive_observed}` so the
behaviour is diagnosable in production rather than silent (the exact failure mode the issue
names: *"no error, no log line and no explain anomaly"*).

**Oracle.** New `test_sparse_status_topup.py`: a fixture with `cap` deprecated near-duplicates
ranking above `cap - 1` active hits. Pre-fix: the active hits are absent from
`result.records` and `explain.fusion.selectivity == 0.0` (boost silently disabled). Post-fix:
active hits present and `selectivity > 0.0`.

**Red-check.** Delete the top-up call but keep the `explain.fusion.sparse_topup` counter →
the oracle must go RED. (This is exactly the #36 F-V3 attack: a counter computed independently
of the code it describes reported five drops that never happened. Derive every reported field
from the fetch actually performed.) Second red-check: set `HARD_TOPUP_CEILING = cap` (no
widening possible) → RED.

---

### #42 — seed exclusion  ·  unit W-42  ·  needs W-G-WD + W-44  ·  v2.1.0

**Approach (FORGE's recorded ruling: relax, opt-in).** Add `exclude_seeds: bool = True` to
`GraphStore.neighbor_expand` and `decaying_walk`. Default `True` = today's behaviour
byte-identically, so **Dream and every other consumer are untouched by construction**. When
`False`: `_neighbor_expand_one_hop` drops the `if neighbor_id not in seed_ids` filter
(`graph.py:225`) and `decaying_walk` seeds `visited = set()` instead of `set(seed_ids)`
(`graph.py:302`) — a seed reachable from another seed then earns derived credit at its true
hop distance. Retrieval opts in from `retrieve.py`'s two call sites, behind a
`Config.recall_seed_derived_credit` flag (default decided by the DP-1 re-check, §6 S-1).

**Oracle.** Three layers:
1. `test_storage_graph.py`: with `exclude_seeds=True` the return set is **byte-identical** to
   `b7f1a47` on a fixture where a seed is reachable from another seed; with `False` the seed
   appears with the correct hop weight.
2. **DP-1(b) re-check on G-WD** (§3.4): the derived-family-merge's base-arm rank-1 protection
   must still hold with seeds includable — i.e. a derived-only record must **not** outrank a
   record backed by two base arms.
3. AC-125 7/7 unanimous, retrieval gate non-regressed.

**Red-check.** Flip the default to `exclude_seeds=False` → the byte-identity test in (1) must
go RED. If it stays green, the parameter is not wired to the behaviour it names.

**STOP (recorded reversal, §6 S-1).** If a post-#41 multi-seed measurement shows relaxation
regresses multi-hop F1, or if (2) shows P1 re-creation, **keep exclusion** and close #42 as
*policy affirmed, relaxation rejected with measurement* — a legitimate closure.

---

### #48 — AC-138/AC-139  ·  unit W-G-FLOOR  ·  needs W-RIG  ·  v2.0.2

**A prediction this plan makes, and requires to be measured first.** Pre-#41,
`neighbor_expand` expanded effectively one seed, so *which* seed came first mattered, and the
floor (10 vs 1000 seeds) changed that — that is the channel that produced divergence at seed 8
on the renamed variant. **Post-#41 the walk expands ALL seeds** (`graph.py:215-230` loops every
seed; `graph.py:305` sorts the frontier). On the current fusion fixture the edge-bearing nodes
`N1/N2/N3` sit at dense ranks 1-3 and are therefore inside **both** `[:10]` and `[:1000]`, so
the derived arm's *union* is identical at both floors. **#41 plausibly removed the floor's only
channel on that topology**, which would make AC-139 as literally worded *less* obtainable, not
more.

This is a derivation, not a measurement. **W-G-FLOOR's first task is to confirm or refute it**
(verification-plan VP-M1). Then:

**Approach.** New `evals/floor_sensitivity_gate.py` — a fixture designed so the floor has a
channel that survives all-seed expansion:
- ids renamed so every competitor sorts **after** `target` (tie-break-neutral; safe because
  this is a new file and AC-125's fixture is untouched — §3.1);
- the **edge-bearing** competitor placed at dense rank ~12, i.e. **inside `[:15]` but outside
  `[:10]`** — so `floor=10` never seeds it and its phantom neighbour is never discovered,
  while `floor=1000` does;
- the phantom, once discovered, earns a derived vote sufficient to demote `target`.
- → `floor=10` gives `target_rank == 0`; `floor=1000` gives `target_rank != 0`,
  **deterministically at every `PYTHONHASHSEED`** (post-#41 there is no lottery left).
- Move AC-138/AC-139 here (per AC-139's own "moved, not weakened" escape hatch) and delete the
  strict-xfail block at `test_fusion_gate.py:85-113`.

**Oracle.** `floor=10` vs `floor=1000` produce **disjoint** target-rank distributions over
`PYTHONHASHSEED` 0-5 + unset (7 points, C-2 protocol) — the exact C-2 bar AC-139 failed on the
old fixture.

**Red-check.** Move the edge-bearing competitor to dense rank 3 (inside both floors) → the
divergence assertion must go RED. Second: run both probes at `floor=10` → RED.

**STOP (§6, S-5).** If no fixture can be built where the floor changes the fused rank
deterministically post-#41, AC-139 as worded is **unobtainable**, and #48 closes as
*retired with mechanism note* — not as a permanent xfail. Do not invent a fixture that only
appears to work.

---

### #55 — DP-2 band  ·  unit W-G-WD (fixture) + disposition  ·  v2.0.2 (docs)

**The issue offers two options: "characterize the sub-1.0 band, or leave it formally
unsupported." This plan recommends the second, and says why in §5.**

**What is built (W-G-WD).** A weight-discriminating fixture, on the shared rig:
- single layer, `corpus < candidate_k`, real `GraphStore`, stub dense arm;
- `A` = a record whose **only** support is the derived arm (graph-only phantom);
- `B` = a record with exactly one base-arm vote at a **known** rank r;
- the ordering of `A` vs `B` is then decided by `w_derived/(60+r_A)` vs `1/(60+r_B)` — pure,
  stated, checkable arithmetic (the same mechanism `dp2-control-note.md` reconstructed for the
  retrieval gate);
- assert the fixture **DIFFERS** across the values it claims to distinguish: at
  `w_derived ∈ {0.90, 0.95, 1.00}` the gate must produce **at least two distinct outcomes**.
  A gate that returns the same answer at every weight is not a weight gate (the exact
  degeneracy #55 reports).

**Its declared purpose is the #42 DP-1(b) re-check oracle (§3.4), NOT band characterisation.**
The module docstring must say so in the first paragraph, because the failure mode #52
documents — *an axis that "presents as" evidence for something it does not measure* — is
exactly what happens if a future reader finds a weight-sweep fixture and cites it as the band
characterisation.

**Also landed under #55 (both obtainable):**
- **item 2:** re-run the §D2 bitwise identity harness (20 in-process comparisons) on the
  current tree, refreshing evidence that `w_derived = 1.0` carries the identity property. The
  recorded FORGE position accepted this *without* re-measurement on structural grounds
  ("W1-W4 changed candidate generation, not combiner arithmetic"); that argument survives #42
  as well (#42 changes derived-arm *contents*, not the combiner), so this is a **cheap
  refresh, not a blocker**. Reversal condition on record: a non-zero diff.
- **item 3:** an eval-notes line stating that the **retrieval** gate is the informative fixture
  for weight sweeps and the **fusion** gate is not (target/Z at k=2 cannot express it) — so the
  next sweep does not vacuously "pass" on the wrong fixture.

**Red-check for item 2.** Perturb one arm weight by 1 ULP → the harness must report a non-zero
diff. A bitwise-identity harness that cannot report a difference is not a harness.

---

### #47 — corpus scaling  ·  unit W-G-CORPUS (gate) + disposition  ·  v2.0.2 (gate) / TBD (fix)

**Approach (gate first, fix maybe never — §5).** `evals/corpus_scaling_gate.py`:
- **single layer** (`layers=["episodic"]`) — asserted, so layer-major ordering cannot be the
  cause (§0.2);
- corpus of M crystals with `M > candidate_k = max(k*3, FETCH_WIDTH_FLOOR)`; at `k=10`,
  `candidate_k = 30`, so `M ≈ 60` already reaches the regime — the "31 crystals cannot reach
  it" reading is about the *scaling-law* question, not the *truncation* question (#38's own
  datum: `dense_ranking` held exactly 30 ids against 31 crystals and `candidate_k` cut
  `spoke2` out);
- one planted ground-truth record whose BM25 rank is `> candidate_k`, therefore invisible to
  every arm;
- assert it is recalled. **RED today.** `FETCH_WIDTH_FLOOR` is **not** touched — the issue's
  own constraint (a corpus-dependent floor makes the ranking universe drift with unrelated
  commits) — so the gate reads and asserts `FETCH_WIDTH_FLOOR == 10` unchanged.

**Oracle for the gate itself:** it is RED at `b7f1a47` and its liveness self-check confirms
`len(sparse_ranking) == candidate_k` exactly (i.e. the fetch really was censored).

**Red-check.** Shrink the corpus to `M < candidate_k` → the gate must go GREEN (no truncation,
nothing to recover). If it stays RED at small corpus, the gate is measuring something other
than truncation → STOP (§6, S-7).

**The fix is deliberately NOT specified here.** See §5.

---

## 5. Ruthless honesty — what may NOT be closable as specified

| issue | closable as specified? | honest disposition if not |
|---|---|---|
| **#57** | **Yes.** Template exists, no dependencies, red-check is trivial. | HTTP half may reduce to a recorded "what this does not cover" — that is a closure, not a dodge. |
| **#52** | **Yes.** The gate is red by construction on today's code; the C-XL-1 control proves it can go green. | — |
| **#45** | **Yes**, once #52 exists. | If Option A breaks the D3 selectivity invariant irrecoverably, fall back to Option B **and extend G-XL**, or the choice is unfalsifiable. |
| **#42** | **Yes, either way.** "Relax" and "policy affirmed, relaxation rejected" are both closures — the reversal condition is on record. | Close as WONTFIX-relax **with the measurement attached**. |
| **#44** | **Conditional on W-HOP.** | If the fence amend is denied, #44 is not closable; re-file against the fence itself rather than shipping a half-fix. |
| **#48** | **Probably**, but possibly not as literally worded — §4 predicts #41 removed the floor's only channel on the *old* topology, and the *new* topology must be shown to have one. | If no deterministic floor-sensitive fixture exists post-#41: **retire AC-138/AC-139 with a mechanism note** (they measured a lottery that no longer exists) and close #48. Do **not** leave a permanent strict-xfail. |
| **#47** | **NO — not as specified.** | See below. |
| **#55** | **NO — item 1 is not obtainable as a quality measurement.** | See below. |

### 5.1 #47 — the measurement that is not obtainable

What **is** obtainable: a deterministic gate showing that `candidate_k` truncation drops a
planted ground-truth record once `corpus_per_layer > candidate_k`. That is real and it goes
red today.

What is **not** obtainable from any synthetic fixture: evidence that a *particular scaling
law* is correct. A synthetic gate proves only that *some* larger fetch recovers *the record
the fixture author planted*. Its ground truth is stipulated, so it cannot adjudicate between
`candidate_k = k*3`, `k*5`, `c·log(n_scoped)`, or `n_scoped/2` — every one of them "passes" if
you make it wide enough, and each buys recall with latency the fixture does not price.

**Recommended disposition — close #47 as WONTFIX-with-rationale, plus the gate.** Ship the
gate (it is genuine evidence that a ceiling exists), ship the `explain.fusion.candidate_k`
telemetry path that is *already there*, and record: *"`candidate_k` stays a constant multiple
of `k` by design. The response curve that would justify a scaling law requires production
telemetry, not a synthetic corpus. Reopen when `explain.fusion` data from a real store shows
the ceiling binding in practice."*

**Second-best:** land a bounded, **explicitly heuristic** scaling with a C-9-style fence in
the config comment ("no shipped measurement validates this law; it is a headroom hedge").

**Explicitly rejected:** shipping a scaling constant and declaring #47 closed. That is what
v1.11.0 did (a cosmetic `max(k*3, FETCH_WIDTH_FLOOR)` link that is a no-op at defaults) and it
is why the issue is open a second time. If the executor finds themselves writing a number into
`candidate_k` without a response curve, the correct action is to stop and close WONTFIX.

### 5.2 #55 — characterisation is not measurement

A weight-discriminating fixture is **buildable** — the arithmetic is explicit and §4 gives the
construction. But what it produces is a **response curve of the combiner's rank arithmetic**,
which is *already fully documented* at `config.py:296-312`. It cannot say whether demoting the
derived-only record is *good*, because the fixture author decided which record is relevant.

Presenting that curve as "the sub-1.0 band is now characterised" would be the same species of
error as the `cross_layer` axis (#52): an artefact that *presents* as evidence for a claim it
structurally cannot support.

**Recommended disposition — take the issue's own second option: leave the sub-1.0 band
formally unsupported, and close #55** on the strength of items 2 (identity refresh) and 3
(which-gate-is-informative note) plus an explicit config-comment line: *"values below 1.0 are
legal, unsupported, and will remain uncharacterised until a fixture with non-stipulated ground
truth exists."* The fixture is still built — because it is the DP-1(b) re-check instrument #42
needs — but it is **labelled as that**, in its first docstring paragraph, and never cited as
band characterisation.

**STOP condition:** if someone proposes closing #55 by shipping the response curve as
characterisation, that is the v1.11.0/#47 failure repeated one axis over.

---

## 6. Risks and STOP conditions (mechanical; each returns to FORGE, not to the implementer)

| id | trigger | action |
|---|---|---|
| **S-1** | #42's recorded reversal: a post-#41 multi-seed measurement shows relaxing seed exclusion regresses multi-hop F1, **or** the DP-1(b) re-check shows a derived-only record outranking a two-base-arm record | **Keep exclusion.** Close #42 as policy-affirmed with the measurement. Do not ship the relaxation. |
| **S-2** | `fusion_weight_derived = 1.00` red on **any** gate at **any** point | STOP before any config edit. AC-136 contingency class — inherited, still binding. |
| **S-3** | G-XL is **green** on `b7f1a47` | The gate does not measure the defect. STOP, redesign — do not proceed to W-45. |
| **S-4** | G-XL's single-layer control (C-XL-1) is **red** on `b7f1a47` | The fixture's BM25 assumption is wrong; the gate is red for the wrong reason. STOP. |
| **S-5** | No fixture makes `FETCH_WIDTH_FLOOR` change the fused rank deterministically post-#41 | AC-139 is unobtainable. **Retire** it with a mechanism note; do not ship a permanent strict-xfail and do not fabricate a pass. |
| **S-6** | AC-125 (`test_fusion_gate.py::test_weighted_vs_unweighted_ab`) not 7/7 unanimous over `PYTHONHASHSEED` 0-5 + unset after **any** unit | STOP. Contingency six. |
| **S-7** | G-CORPUS stays RED when the corpus is shrunk below `candidate_k` | The gate is not measuring truncation. STOP, WONTFIX #47. |
| **S-8** | **Any** new gate passes on the pre-fix tree | It is not a gate. STOP (the campaign's recurring defect class). |
| **S-9** | `make test-ci` and `make test` disagree on any batch | The third mode is a release gate, not an optimisation. STOP until both are green. |
| **S-10** | W-HOP (the `bm25_search` fence amend) is denied | #44 is not closable as specified. Do not ship a partial fix; re-file. |
| **S-11** | A proposal to close #47 or #55 by shipping a construct as a measurement | STOP. §5.1 / §5.2. |
| **S-12** | Any unit's diff touches a file another unit exclusively owns (§2) | DRIFT. `ramza-freeze --amend --reason` or revert; a silent overlap is what makes attribution impossible. |

---

## 7. Release strategy

| release | semver | contents | client-visible? | breaking? |
|---|---|---|---|---|
| **v2.0.2** | **patch** | W-ENTRY (#57), W-RIG, W-G-XL (#52, gate RED-as-xfail + axis relabel), W-G-CORPUS (#47 gate), W-G-WD (#55 fixture), W-G-FLOOR (#48), W-CLI, #55 items 2+3 + config-comment disposition | **No.** Tests, evals, and comments only. Zero production-code behaviour change. | No |
| **v2.1.0** | **minor** | W-45 (#45), W-44 (#44), W-42 (#42) | **Yes** — recall result *order* and *membership* change by design (the 1.9.0 / 1.10.0 / 1.11.0 precedent: every recall-ordering change was a minor). New additive `explain.fusion.sparse_topup` object; new additive `exclude_seeds=` kwarg (default preserves behaviour); possible new `Config.recall_seed_derived_credit`. | **No.** No tool rename, no schema change, no `isError` semantics change, no removed field. |
| **#47 fix** | **minor** if it ships at all | per-layer fetch scaling | Yes (recall membership) | No |

**`is_error`-class surfaces:** none of the three batches changes error surfacing. v2.0.0's
single-segment tool names + `isError` are untouched. #57's entrypoint test *observes* the wire
but asserts only on `tools/list`, so it does not freeze `isError` shape.

**Maker ≠ checker — required on BOTH batches.** #35/#39 shipped without an independent checker
and the post-hoc check rejected and found a real defect (telemetry double-write) already in
production. For v2.0.2 the checker hop matters **more**, not less: the entire batch is gates,
and *nothing checks the checker*. The v2.0.2 checker's specific mandate is: **independently
re-break every new gate** (their own perturbation, not a replay of the maker's
`red-evidence.txt`) and confirm each goes red. A red-evidence file the checker did not
reproduce is a claim, not evidence.

**Hop placement:** checker hop after the last unit of a batch merges to a release branch and
**before** the tag. `ramza-gate critic --author <maker> --checker <checker>` records the
identities; `ramza-drift --range <base>..<head>` fences the diff against §2's ownership table.

**Roster / nexus bumps (per release, both of them):**
1. tag crystalium `vX.Y.Z`, build + push the ghcr image (tags are **un-prefixed**);
2. pull the **index digest from the ghcr registry** — not from a local build;
3. roster PR bumping **both** `roster/mcps.yaml` **and** `roster/index.yaml` — crystalium is
   dual-rostered and skew-guarded; a one-file bump fails the guard;
4. nexus release + integrity PR. **The integrity PR gets no CI** — verify `archive_sha256`
   equals the raw tar *with prefix* by hand;
5. `eidolons mcp verify` against the pinned digest. **Exit 3 = INDETERMINATE, not a pass.**
   The lock entry is a receipt, not an order.
6. Local project wiring is a separate step and is routinely forgotten — this repo's `.mcp.json`
   currently pins 1.9.0 while the roster is at 1.10.0.

---

## 8. Stories — loop batches

### Wave 0 — foundations (fully parallel, 3 units)

**Entry:** `b7f1a47` clean; `make test` and `make test-ci` both green at baseline (captured).
**Exit gate:**
`docker compose run --rm crystalium pytest mcp-server/tests/test_server_entrypoint.py mcp-server/tests/test_corpus_rig.py -v`
→ exit 0, **and** `fence-amend.md` exists with an explicit ALLOW/DENY.

| unit | entry precondition | exit gate (command + pass condition) |
|---|---|---|
| W-ENTRY | none | `pytest …/test_server_entrypoint.py -v` exit 0 under **both** `make test` and `make test-ci`; `red-evidence` shows the `NameError` injection RED |
| W-RIG | none | `pytest …/test_corpus_rig.py -v` exit 0; rig's own liveness self-check demonstrated to return `"confounded"` on a deliberately mis-pinned axis |
| W-HOP | none | `fence-amend.md` records ALLOW or DENY for the `bm25_search` fence, with the ruling text quoted. DENY ⇒ S-10 |

### Wave 1 — gates (4 parallel units + 1 trailing)

**Entry:** W-RIG merged. **Exit gate:** all four gates present, each with a checker-reproduced
red-check, and `make test-ci` green (G-XL is a strict xfail, so "green" includes it).

| unit | entry precondition | exit gate |
|---|---|---|
| W-G-XL | W-RIG | G-XL RED on `b7f1a47` (as strict xfail); C-XL-1 single-layer control GREEN; `fusion_gate.py` diff = key rename only, `_build_fixture` byte-identical (`git diff` scoped check) |
| W-G-CORPUS | W-RIG | G-CORPUS RED at `M > candidate_k`; GREEN at `M < candidate_k` (the red-check); `FETCH_WIDTH_FLOOR` unchanged, asserted |
| W-G-WD | W-RIG | ≥2 distinct outcomes across `w_derived ∈ {0.90, 0.95, 1.00}`; docstring paragraph 1 states its purpose is the DP-1(b) re-check, **not** band characterisation |
| W-G-FLOOR | W-RIG | **VP-M1 first** (confirm/refute the "#41 killed the channel" prediction); then disjoint rank distributions at floor 10 vs 1000 over 7 seeds; `test_fusion_gate.py:85-113` xfail block deleted; `evals/fusion_gate.py` untouched |
| W-CLI | all four above | `python -m evals <each-new-gate>` runs and prints JSON; `evals/__main__.py` is the only file touched |

**Wave 1 exit → release v2.0.2** (checker hop, then tag, then roster/nexus).

### Wave 2 — behaviour (strictly serial rebase chain on `retrieve.py`)

**Entry:** v2.0.2 tagged; G-XL RED and G-WD discriminating, both on the released tree.

| link | entry precondition | exit gate |
|---|---|---|
| W-45 | G-XL RED, verified by the checker | G-XL GREEN + xfail marker removed in the same commit; AC-125 7/7 unanimous; `explain.fusion.{n_sparse_cap,selectivity,w_sparse}` pre/post diff recorded; `make test` **and** `make test-ci` green |
| W-44 | W-45 merged; W-HOP = ALLOW | `test_sparse_status_topup.py` green; red-check (delete the top-up, keep the counter) RED; ≤1 extra query per recall, asserted by call-count; both suites green |
| W-42 | W-44 merged; G-WD available as the DP-1(b) oracle | `exclude_seeds=True` byte-identical to `b7f1a47`; DP-1(b) re-check passes (no P1 re-creation); AC-125 7/7; both suites green. **S-1 applies.** |

**Wave 2 exit → release v2.1.0** (checker hop, then tag, then roster/nexus).

### Wave 3 — disposition (no code, or one small unit)

| item | exit gate |
|---|---|
| #55 close | config comment + eval note landed in v2.0.2; §D2 identity refresh recorded; issue closed citing "formally unsupported" |
| #47 close | WONTFIX-with-rationale posted, **or** a scaling change with a C-9-style unsupported fence. **S-11 applies.** |
| #48 close | AC-138/139 moved to `floor_sensitivity_gate.py`, **or** retired with a mechanism note (S-5) |
| #42 close | relaxation shipped, **or** policy affirmed with the measurement (S-1) |

---

## 9. Non-negotiable constraints, encoded

| id | constraint | where it binds |
|---|---|---|
| **NC-1** | Every new gate is **red-checked**: broken deliberately, observed to fail, restored. Two prior ACs exited 0 comparing `null` to `null`. | Every Wave-0/1 exit gate; the checker must **re-break independently**, not replay `red-evidence.txt` |
| **NC-2** | **maker ≠ checker** before any release. | §7; `ramza-gate critic` on both v2.0.2 and v2.1.0 |
| **NC-3** | **CI mode is a third mode**: `CRYSTALIUM_SKIP_SLOW=1` **with** slow tests selected (`make test-ci`). A `slow` mark does **not** protect CI; a test inheriting SKIP_SLOW can pass `test-fast` and fail `make test`. | §0.3 (no new gate is `slow`); every exit gate names both `make test` and `make test-ci`; S-9 |
| **NC-4** | Container-only (`docker compose run --rm crystalium …`); inside containers use `/app/.venv/bin/python`; **never `bash -lc`** (the login profile resets PATH to a dependency-free interpreter). Never send stderr to `/dev/null` when checking success. | Every command in `verification-plan.md`; #57's test captures stderr via PIPE and surfaces it in assertions |
| **NC-5** | Do not silently reverse recorded rulings: `retrieve.py:605-615` (bm25_search), C-9 (no sub-1.0 precision dial), the AC-125 fixture. | §3.1, §3.2, §3.3; W-HOP; S-10 |
| **NC-6** | `__version__` derives from installed package **METADATA**, not the bind-mounted source — a dev capture reports the image's version. No oracle may trip on it. | #57's entrypoint test asserts on `tools/list`, **not** on `serverInfo.version` |

---

## 10. Rejected Alternatives (scored, `ramza-score --rubric explore`)

| hypothesis | score | why rejected |
|---|---|---|
| **H-B gate-first, two-phase, shared rig** | **84 solid — SELECTED** | Exploits the four-gates insight; the only shape where `retrieve.py` contention is confronted rather than discovered mid-campaign |
| H-E narrow-and-close (gates for #57/#52, fix #45, WONTFIX the rest) | 74 solid | Cheapest and most honest, but abandons #42/#44/#48 which **are** closable. Its honesty component is **adopted** for #47 and #55 |
| H-A issue-by-issue serial | 55.5 weak | Builds four overlapping fixtures; `retrieve.py` serialises it anyway; loses the shared rig |
| H-C single mega-PR | 44 weak | Destroys attributability — and attribution is what caught #43's confound and #52's tautology |
| H-D fix-first, gate-later | 38.5 weak | A gate written after the fix is written to pass. This is the campaign's own recurring defect class, deliberately re-committed |


---

## 11. Acceptance Criteria

The 49 mechanically-checkable criteria live in
`/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/spec.criteria.md`
(EARS form, `ramza-ears-lint` green). They are frozen at Assemble; any later edit without
`ramza-freeze --amend --reason` is tamper evidence.

| range | covers |
|---|---|
| AC-301..AC-306 | Wave 0 — entrypoint smoke (#57), shared rig, fence hop (#44 precondition) |
| AC-310..AC-325 | Wave 1 — the four gates (#52, #47-gate, #55-fixture, #48) |
| AC-330..AC-333 | v2.0.2 release gate, including the independent checker re-break |
| AC-340..AC-353 | Wave 2 — #45, #44, #42 behaviour changes |
| AC-360..AC-364 | v2.1.0 release gate, wire non-regression, roster/nexus |
| AC-370..AC-373 | Wave 3 — dispositions for #55, #47, #48, #42 |

The runnable commands, measurement order, red-check protocol and release checklists are in
`verification-plan.md`.

---

## 12. Confidence

`ramza-score --rubric confidence` → **84.75 / VALIDATE** (pattern_match 88, requirement_clarity
78, decomposition_stability 85, constraint_compliance 88). VALIDATE, not AUTO_PROCEED, is the
honest verdict and it agrees with the complexity routing (12 → `human_loop`): two of the eight
dispositions (#47, #55) are **recommendations that need a human decision**, and one load-bearing
technical claim (§4 #48 — that #41 removed `FETCH_WIDTH_FLOOR`'s channel on the old fixture) is
a derivation this plan requires to be **measured first** (VP-M1) rather than assumed.

What is high-confidence: the dependency graph, the `retrieve.py` contention finding, the
safe/unsafe sharing split (§0.1/§0.2), and every fence and STOP condition — all re-derived from
the tree at `b7f1a47`, not from issue text.

What is not: the #45 Option A/B choice (deliberately left to a measured decision), the exact
shape of #48's replacement fixture (gated on VP-M1), and whether #44's fence hop is granted.
