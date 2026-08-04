# crystalium#38 — binding pre-deliberation measurement (DP-1 / DP-2)

> Produced by the real-stack measurement agent ordered by spec rev 1.1.0's DP-1 binding
> pre-deliberation clause. Real stack, real gate: 26 gate runs + 2 targeted probes.
> Scratch clone at `ef42967`; the real checkout was never touched (verified clean
> post-run). Prototype scaffolding is throwaway, env-gated, and lives only in the
> scratch clone (`.meas/`); with the env vars unset the instrumented file reproduced
> the shipped baseline exactly. Recorded 2026-08-03 for the FORGE deliberation.

## 0. Headline

| # | question | measured answer |
|---|---|---|
| G-7 | spokes' actual dense ranks | **spoke1 = 17; spoke2 = ABSENT from `dense_ranking` entirely** |
| DP-1 | does H-A (0.35/0.25) hold F1? | **NO — collapses 0.4615 → 0.3077, gate_pass=false, at all 6 hash seeds** |
| DP-2 | `w_derived` 1.00 vs 0.95 | **1.00 passes 7/7 runs; 0.95 passes 6/7 and FAILS at PYTHONHASHSEED=5** |
| D2 | identity property | **HOLDS bitwise** — 20/20 in-process comparisons, max score diff exactly `0.0` |

**The spec's revision 1.1.0 reversal is measured-wrong.** Revision 1.0.0's conclusion
("static down-weighting collapses multi-hop F1") reproduces on the real stack. vigil's
F1 refutation — and the withdrawal, the H-A re-score 61.5→72.5, and the reopening of
DP-1 — rest on a dense-arm model that does not match reality.

## 1. Baseline reproduction — exact

```
docker compose run --rm crystalium python -m evals retrieval-gate
```

`multihop_f1` flat `0.30769230769230765`, completion `0.4615384615384615`, both
`0.4615384615384615`; `context_rank.flat/context` `2/2`; `graph_ok true`,
`completion_pass true`, `context_pass false`, `gate_pass true`. Matches the prior
campaign on every named axis. `context_rank.both` is **not** stable (see §6).

## 2. G-7 CLOSED — measured arm memberships

Multi-hop query `"acme login session token rotation"`, `k=10`, `layers=None`,
`candidate_k=30`, `fetch_width=10`, corpus 31 crystals. Identical in every run:

| role | sparse rank | dense rank | graph | completion |
|---|---|---|---|---|
| hub | **1** (only sparse hit, `n_sparse=1`) | **1** | — | — |
| ctx_match | — | 2 | — | — |
| ctx_off | — | 3 | — | — |
| **spoke1** | — | **17** | rank 1 (sole member) | rank 1–3 |
| **spoke2** | — | **ABSENT** | — | rank 1–4 |
| noise2 / noise1 | — | 29 / 30 | — | rank 1–4 |

`dense_ranking` holds exactly 30 ids (`candidate_k`) against a 31-crystal corpus —
spoke2 is the one record cut.

**Neither modelled column in the spec is correct.** Rev 1.0.0 modelled both spokes
absent; the critique's F1 correction modelled them at 25/26, 27/28 or 29/30. The truth
is **mixed**: one at 17, one absent. `w_dense` never touches spoke2 because spoke2 has
no dense term — which is exactly why down-weighting the derived arms destroys it.

## 3–5. Variant × axis (PYTHONHASHSEED=0 unless noted)

| variant | f1.flat | f1.completion | f1.both | ctx_rank flat/context/both | graph_ok | completion_pass | context_pass | **gate_pass** |
|---|---|---|---|---|---|---|---|---|
| **baseline** (ef42967) | 0.30769230769230765 | **0.4615384615384615** | 0.4615384615384615 | 2/2/5 | true | true | false | **true** |
| **H-A** w_g=0.35 w_c=0.25 | 0.30769230769230765 | **0.30769230769230765** | 0.30769230769230765 | 2/2/2 | true | **false** | false | **false** |
| **H-B** w_d=1.00 α=1 | 0.30769230769230765 | **0.4615384615384615** | 0.4615384615384615 | 2/2/5 | true | true | false | **true** |
| **H-B** w_d=0.95 α=1 | 0.30769230769230765 | **0.4615384615384615** | 0.4615384615384615 | 2/2/2 | true | true | false | **true** |
| H-B w_d=0.90 α=1 | 0.30769230769230765 | **0.30769230769230765** | 0.30769230769230765 | 2/2/4 | true | false | false | **false** |
| H-B w_d=0.85 α=1 | 0.30769230769230765 | 0.30769230769230765 | 0.30769230769230765 | 2/2/4 | true | false | false | **false** |
| H-B w_d=0.50 α=1 | 0.30769230769230765 | 0.30769230769230765 | 0.30769230769230765 | 2/2/4 | true | false | false | **false** |
| H-B w_d=1.00 α=0 (neutral) | 0.30769230769230765 | 0.4615384615384615 | 0.4615384615384615 | 2/2/4 | true | true | false | **true** |

`f1` denominators: relevant = {hub, spoke1, spoke2}; retrieved = 10. F1 `0.4615…` =
2·(2/10·2/3)/(2/10+2/3) → 2 of 3 relevant in top-10. F1 `0.3077…` → 1 of 3.

### Raw fused orders — multi-hop query, completion arm (seed 0)

`w_sparse` resolved by D3: `n_sparse=1`, `cap=120`, `N_scoped=31` →
`selectivity=0.967741935483871`, `w_sparse=1.967741935483871`.

```
baseline          graph=[spoke1]  completion=[noise2,noise1,spoke2,spoke1]
  0 spoke1     0.04500545560996381      <-- P1 INVERSION: zero lexical match outranks the exact match
  1 hub        0.03278688524590164
  2 noise2     0.027629397679130595
  3 noise1     0.02724014336917563
  4 ctx_match  0.016129032258064516
  5 ctx_off    0.015873015873015872
  6 spoke2     0.015873015873015872     <-- inside k=10
  7 D3a2a      0.015625
  ...                                    f1 = 0.4615384615384615

H-A 0.35/0.25     graph=[spoke1]  completion=[spoke1,spoke2]
  0 hub        0.03278688524590164      <-- P1 fixed
  1 spoke1     0.022823078560783482
  2 ctx_match  0.016129032258064516
  3 ctx_off    0.015873015873015872
  4 Dd3e3      0.015625
  ... spoke2 = 0.25/62 = 0.004032258…    <-- EVICTED, f1 = 0.30769230769230765

H-B w_d=1.00     graph=[spoke1]  completion=[spoke2,noise2,spoke1,noise1]
  0 hub        0.048651507139079855     <-- P1 fixed AND spokes retained
  1 spoke1     0.02938045560996381
  2 noise2     0.027108970929195647
  3 noise1     0.026736111111111113
  4 spoke2     0.016129032258064516
  5 ctx_match  0.016129032258064516
  ...                                    f1 = 0.4615384615384615

H-B w_d=0.95     completion=[noise2,spoke1,spoke2,noise1]
  ... 9 spoke2 0.01507937  (= 0.95/63)   <-- last k=10 slot; next is 0.01492537 (=1/67). Margin 1.0%
                                          f1 = 0.4615384615384615
```

**H-A's failure mechanism, measured:** spoke2's *only* vote is the completion arm.
Baseline gives it `1/62…1/64 ≈ 0.0159`, which clears the distractor band `[1/71, 1/62]`.
H-A gives it `0.25/62 = 0.004032`, an order of magnitude below. H-A cannot help the
case the issue names either — the issue's 3-arm competitors sit at dense ranks 1–3,
and §7-anomaly-B shows such records structurally *cannot* hold derived votes.

**H-B fixes P1 without paying for it.** In baseline, spoke1 (no lexical match at all)
outranks hub (BM25 rank 1 + dense rank 1) — the issue's exact defect, live in the
shipped fixture. H-B's sparse boost restores hub to rank 0 while leaving both spokes
in the top-10. H-A restores hub too, but by evicting spoke2.

## 4b. Identity property — VERDICT: HOLDS, bitwise

Measured in-process (same arms, same interpreter — cross-process comparison is invalid
because ids are `uuid4`-fresh per run):

| condition | instances | same id set | max abs score diff | bitwise equal | order identical |
|---|---|---|---|---|---|
| completion arm **empty** | **20 / 20** | true | **0.0** (exact) | **true** | **true** |
| completion arm non-empty | 20 / 20 | true | 1.56e-02 … 1.64e-02 | false | false |

With `w_derived=1.0`, the sparse boost neutralised (`alpha=0`), and the completion arm
inactive, family-merge is **exactly** `rrf_merge_scored` — same ids, bit-identical
floats, identical order. AC-108/AC-135 are supportable as written. **Caveat:** the
*order* half of the identity is untested for ties in this fixture — with completion off
all fused scores are distinct, so the F4 divergence (insertion-order vs `(-score, id)`)
never fires here. That needs a purpose-built tie case, not this gate.

## 6. Hash-seed sensitivity

| variant | seed 0 | 1 | 2 | 3 | 4 | 5 | unset |
|---|---|---|---|---|---|---|---|
| baseline `f1.completion` | .4615 | .4615 | .4615 | .4615 | .4615 | .4615 | .4615 |
| baseline `context_rank.both` | **5** | **4** | **5** | **2** | **4** | **5** | 4, then 2 |
| H-A `f1.completion` | .3077 | .3077 | .3077 | .3077 | .3077 | .3077 | .3077 |
| H-B 1.00 `f1.completion` | .4615 | .4615 | .4615 | .4615 | .4615 | .4615 | .4615 |
| **H-B 0.95** `f1.completion` | .4615 | .4615 | .4615 | .4615 | .4615 | **.3077 FAIL** | .4615 |
| H-B 0.95 spoke2 completion rank | 3 | 1 | 1 | 2 | 3 | **4** | 2 |

**P3 confirmed on the real gate.** `context_rank.both` takes values {2, 4, 5} across
seeds — and it also varied 4→2 across two runs at the *same* (unset) seed, because ids
are regenerated per run. #36's `BENCH-NOTES.md` figure (4) and the checker's re-run (5)
are both in the observed set; F-V6's "non-reproducible number" is explained and
reproduced. The graph/completion arm's *membership and cardinality* vary too
(completion arm observed at length 2 and 4 with 4 different orderings).

**DP-2 decisive finding.** `w_derived=0.95` is not merely lower-margin — it is
**flaky**. spoke2's sole vote is `w_d/(60+r)` where `r` is the hash-nondeterministic
completion rank. At `r≤3`, `0.95/63 = 0.0150794 > 1/67 = 0.0149254` → passes. At
`r=4`, `0.95/64 = 0.0148438 < 0.0149254` → **evicted, gate fails**. Seed 5 lands
`r=4` and the gate goes red. `w_derived=1.00` clears every observed `r`
(`1/64 = 0.015625`). The measured cliff sits between 0.90 (fail) and 0.95 (conditional).

## 7. Issue-sketch scenario — attempted, and it exposed something better

The synthetic probe (`.meas/sketch_probe.py`, all five variants evaluated in **one
process against one corpus**, arms asserted byte-identical) was **degenerate**: BGE-m3
put the distinctive-token target at dense rank **1**, not 4, so T was fusion-rank-0
under every variant. A real embedder could not be cheaply steered to dense rank ≈4.

But it surfaced the structural reason the issue's sketch is unbuildable — and the
shipped fixture contains a better instance anyway (baseline: spoke1 outranks hub, §3).

## Anomalies — three, all material to the docket

**A. `neighbor_expand` returns only the FIRST seed's neighbours.** `graph.py:205-256`
wraps the *entire* `for seed_id in seed_ids` loop in one `try`, and Kuzu **raises** on
`get_next()` at exhaustion instead of returning `None`. So the first seed's row loop
always throws and aborts the whole expansion. Probe (`.meas/probe_neighbor.py`, 6
nodes, edges `id1→id4` and `id2→id5`):

```
A neighbor_expand([id1, id2])      -> [id4]        expected {id4, id5}
B neighbor_expand([id0, id1, id2]) -> []           expected {id4, id5}
C neighbor_expand([id2, id1])      -> [id5]        expected {id4, id5}
```

`neighbor_expand(seeds) ≡ neighbor_expand([seeds[0]])` at ef42967, and `decaying_walk`
passes `list(frontier)` from a **set** — so the walk explores one hash-randomly-chosen
seed. This is P3, but far more severe than the spec models: it changes arm
*membership*, not just order. DP-8's two-line `sorted()` fix does **not** address it.

**B. Any record at dense rank ≤ `fetch_width` is structurally barred from both derived
arms.** `neighbor_expand` filters `if neighbor_id not in seed_ids`, and `decaying_walk`
seeds `visited = set(seed_ids)`. With `seed_ids = dense_ranking[:10]`, the issue's
premise — competitors at dense ranks 1–3 *also* carrying graph and completion votes —
**cannot occur**. The derived arms only ever promote records from *below* dense rank
10, or absent from dense entirely. This reframes DP-1: down-weighting the derived
family can only demote deep/absent records (the multi-hop targets), and can never
demote the top-of-dense competitors the issue wants demoted. It is an argument against
H-A independent of the F1 number.

**C. The retrieval gate's fixture is arm-dependent — its own docstring's isolation
claim is false.** Measured edge counts: flat **2**, context **2**, completion **142**,
both **142**. Cause: `server.py:522,535` sets `link_cooccurrence=config.recall_completion`,
so flipping the completion flag also changes the graph at *commit* time. Worse,
`recent_crystal_ids` does `ORDER BY created_at DESC LIMIT 5` while the fixture stamps
every crystal with the identical `_T0` — so "5 most recent" resolves to the 5
**first-committed** crystals, and the measured edge-target histogram is exactly
`{spoke1: 30, hub: 30, spoke2: 29, noise1: 27, noise2: 26}`. **Both ground-truth spokes
are direct co-occurrence neighbours of nearly every crystal.** The completion arm's F1
lift is therefore substantially an artifact of `created_at` ties, not of the seeded
2-hop chain. The docstring claims "Edges are seeded in EVERY arm, so the only variable
is whether the recall walk / re-rank runs — isolating the faculty, not the fixture."
That is contradicted by 2 vs 142.

Consequence: **AC-124's non-inferiority threshold is anchored on a confounded gate.**
The measurement above is the best available and the ranking it produces stands, but
FORGE should know the F1 axis it is ruling on is not measuring only what its docstring
says.

## Prototype diffs

Two files, +195 lines, entirely additive and env-gated; with
`CRYSTALIUM_MEAS_VARIANT`/`CRYSTALIUM_MEAS_DUMP` unset the file is behaviourally
identical to `ef42967` (verified: instrumented baseline reproduced the shipped numbers
exactly).

`mcp-server/src/crystalium/aetheryte/retrieve.py` — three pure helpers plus a variant
switch and dump at the fusion site:

```python
def meas_weighted_rrf_merge_scored(weighted_rankings, k_rrf=60):
    scores = {}
    for ranking, w in weighted_rankings:
        for rank_0, record_id in enumerate(ranking):
            scores[record_id] = scores.get(record_id, 0.0) + w / (k_rrf + rank_0 + 1)
    return sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))

def meas_minrank_merge(arms):                      # spec D2, exact
    minrank = {}
    for arm in arms:
        for i, cid in enumerate(arm):
            minrank[cid] = min(minrank.get(cid, 1 << 30), i + 1)
    return [cid for cid, _ in sorted(minrank.items(), key=lambda kv: (kv[1], kv[0]))]

def meas_w_sparse(n_sparse, cap, n_scoped, alpha):  # spec D3 rev 1.1.0, scoped denominator
    if n_sparse == 0 or n_sparse >= cap: sel = 0.0
    else: sel = max(0.0, min(1.0, 1.0 - (n_sparse / max(1, n_scoped))))
    return 1.0 + alpha * sel, sel
```

H-A replaces `fused_scored` with `[(sparse,1.0),(dense,1.0),(graph,w_g),(completion,w_c)]`.
H-B builds `derived = meas_minrank_merge([graph_ranking, completion_ranking])`, resolves
`cap = candidate_k * len(target_layers)` and
`N_scoped = self.relational.count_for_export(scope.project, layers=target_layers)`, then
fuses `[(sparse,w_sparse),(dense,1.0),(derived,w_derived)]`. **Seeding was deliberately
left unchanged** (`seed_ids = dense_ranking[:fetch_width]`) to isolate the fusion
variable; D4 would be a no-op here anyway since hub is rank 1 in both base arms, so
`prelim[0] == dense_ranking[0]`.

`evals/retrieval_gate.py` — fixture id→role map, edge dump, `walk_from_hub`, retrieved
list. Full diffs: `git -C <scratch> diff`.

## Exact commands

```bash
git clone /home/rynaro/workspace/oss/agents/crystalium <scratch>/crystalium-meas
git -C <scratch>/crystalium-meas checkout ef42967

# baseline
docker compose run --rm crystalium python -m evals retrieval-gate

# any variant (runner: scratchpad/run_variant.sh)
docker compose run --rm \
  -e CRYSTALIUM_MEAS_DUMP=/app/.meas/<label>.jsonl \
  -e CRYSTALIUM_MEAS_VARIANT={baseline|ha|hb} \
  -e CRYSTALIUM_MEAS_WGRAPH=0.35 -e CRYSTALIUM_MEAS_WCOMP=0.25 \
  -e CRYSTALIUM_MEAS_WDERIVED=1.0 -e CRYSTALIUM_MEAS_ALPHA=1.0 \
  -e PYTHONHASHSEED=N \
  crystalium python -m evals retrieval-gate

docker compose run --rm crystalium python /app/.meas/probe_neighbor.py
docker compose run --rm crystalium python /app/.meas/sketch_probe.py
```

## Artifacts (left in place for audit)

`<scratch>/crystalium-meas/.meas/` — 26 `*.jsonl` arm dumps (full ordered arms +
per-id RRF scores + identity block per recall), 26 `*.result.json`,
`probe_neighbor.py`, `sketch_probe.py`. Analyzer: `<scratch>/analyze.py`. Runner:
`<scratch>/run_variant.sh`. (`<scratch>` = the session scratchpad's `crystalium-meas`.)

## Cleanup verification

`git -C /home/rynaro/workspace/oss/agents/crystalium status --porcelain` → empty;
`log -1` → `ef42967dc7930bf174d0b14436241927da773444`. Nothing committed, nothing
pushed, no PRs.

## What this licenses

- **DP-1: measurement selects (b) family-merge.** H-A fails the shipped gate at 6/6
  seeds. The spec's revision-1.1.0 reversal (F1) and the H-A re-score to 72.5 should
  themselves be withdrawn — on the *measured* dense-arm column, revision 1.0.0's
  directional conclusion was right and only its magnitude was wrong.
- **DP-2: measurement selects (a) `w_derived = 1.0`.** 0.95 is not a margin trade, it
  is a flake: red at seed 5, green at 0–4. The identity property at 1.0 is now
  measured, not modelled.
- **Not licensed:** any claim resting on the gate's F1 axis being a clean faculty
  ablation (anomaly C), and DP-8's adequacy — the two-line `sorted()` fix does not
  repair anomaly A, which is the dominant nondeterminism source. Recommendation:
  anomalies A and B enter the docket as inputs to DP-8 and to the scope of S-1.
