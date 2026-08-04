---
eidolon: ramza
kind: spec
version: "1.4.0"
created_at: "2026-08-03T17:42:00Z"
status: ASSEMBLED (vigil APPROVE-FOR-ASSEMBLE, 3 critique rounds, 0 blocking; next hop = FORGE deliberation on DP-1..DP-9 + DP-4(ii))
change_id: crystalium-rrf-fusion-38
esl_tier: full
maker: vivi
checker: vigil
target_repo: Rynaro/crystalium
target_commit: ef42967
target_version: "1.9.0"
next_version: "1.10.0"
upstream_issue: "Rynaro/crystalium#38"
predecessor: "crystalium-recall-starvation-36 (archived 2026-08-03)"
---

# Spec — RRF fusion is unweighted and arm-seeding is rank-blind (crystalium#38)

> **Anchors.** Every `file:line` below is against `/home/rynaro/workspace/oss/agents/crystalium`
> at `ef42967` (`main`, clean tree, matches `origin/main`), package version `1.9.0`.
> Every anchor was re-read from source for this spec.
>
> **Numbers.** Every fusion figure in this document was recomputed for this spec from a
> standalone reimplementation of the fusion formula, not copied from the issue or from the
> #36 campaign. Figures the issue itself asserts are re-derived and marked against my own
> computation. **All fusion figures are closed-form model output, not measurements of a
> running crystalium** — see §Evidence Gaps for exactly what that does and does not license.

---

## Problem Statement

`Aetheryte.recall()` fuses up to four ranked lists with Reciprocal Rank Fusion
(`retrieve.py:415-426`). Three defects compound.

### P1 — fusion sums arms as if they were independent

`rrf_merge_scored` (`retrieve.py:61-88`) computes `score(id) = Σ_arms 1/(60 + rank)` with no
per-arm weight. A record's fused score therefore grows with the *number* of arms that mention
it, regardless of how well any single arm fits the query. Re-derived:

| claim from the issue | my computation | verdict |
|---|---|---|
| two single-arm rank-1 entries tie at exactly `1/61` | `0.016393` | confirmed |
| exact lexical match seen by 2 arms: `2 × 1/61` | `0.032787` | confirmed |
| 3-arm graph neighbour: `3 × 1/62` | `0.048387` | confirmed |

Modelling the issue's own acceptance sketch — target `T` at **BM25 rank 1** and **dense
rank 4**; competitors `N1..N3` holding dense ranks 1-3 plus graph and completion votes:

```
today (unweighted):   N1 0.049180   N2 0.048387   N3 0.047619   T 0.032018   -> rank(T) = 3
```

`T` is the only record the *lexical* arm — the arm that actually fits a distinctive-token
query — ranks first, and it loses to three records it never lexically matched.

### P2 — the extra arms are not independent evidence; they are the dense arm's opinion, counted three times

This is the mechanism behind P1 and the reason a naive weight fix fails (§D2).
`seed_ids = dense_ranking[:fetch_width]` (`retrieve.py:377`) seeds graph expansion, and
`completion_seeds = seed_ids or sparse_ranking[:fetch_width]` (`retrieve.py:397`) seeds the
completion walk from the same set. Both derived arms are *functions of the dense ranking*.
RRF's rank summation assumes quasi-independent voters; here the dense arm votes once directly
and twice more through its own neighbourhood. The sparse arm never seeds anything.

### P3 — the graph and completion arms have no deterministic rank order at all

`GraphStore.neighbor_expand` returns `set[str]` (`graph.py:205,221,256`) and `retrieve.py:383`
builds `graph_ranking` by iterating that set. `decaying_walk` scores a set comprehension
(`graph.py:279-284`), and `retrieve.py:405` sorts by score only — a stable sort, so every node
at the same hop retains set-iteration order. Python randomises `str` hashing per process and
`PYTHONHASHSEED` is set nowhere in the repository.

Demonstrated (same five UUID-shaped ids, four processes):

```
PYTHONHASHSEED=0   graph rank order [3, 1, 4, 2, 0]   completion [3, 1, 4, 2, 0]
PYTHONHASHSEED=1   graph rank order [0, 4, 3, 1, 2]   completion [0, 4, 3, 1, 2]
PYTHONHASHSEED=2   graph rank order [3, 2, 4, 1, 0]   completion [3, 2, 4, 1, 0]
PYTHONHASHSEED=3   graph rank order [3, 1, 0, 2, 4]   completion [3, 1, 0, 2, 4]
```

Every graph/completion rank — and therefore every fused score for any candidate those arms
touch, and therefore `CrystalSummary.score` — varies between processes. **This already
produced a witnessed symptom:** #36's `verification.md` F-V6 records `context_rank.both = 4`
in `evals/BENCH-NOTES.md` against `5` on vigil's re-run, filed as "a non-reproducible number
in a committed document" with no mechanism identified. P3 is that mechanism.

P3 is a *prerequisite*, not a nice-to-have: an acceptance criterion asserting a fused rank
position while graph/completion candidates are in play is not a criterion — it is a coin flip
that happens to be biased.

### What v1.9.0 shipped, and why it is not a fix

`FETCH_WIDTH_FLOOR = 10` makes the *seed set* k-independent — but only on the gated path. The
shipped line (`retrieve.py:374`, quoted with its gate, vigil A-10) is
`fetch_width = max(k, FETCH_WIDTH_FLOOR) if self.recall_relevance_primary else k`, so with
`recall_relevance_primary=False` the seed set narrows to bare `[:k]`. That two-way difference is
load-bearing for AC-120's fixture. FORGE's own ruling says so: DP-R1 ordered the floor and in
the same sentence ordered "a follow-up issue for the untouched pre-existing root (unweighted
RRF lets a 3-arm graph neighbour outvote a 2-arm exact lexical match) — NOT in this release."
That follow-up is #38. The floor stabilised *which* records vote; it changed nothing about
*how much* each vote counts.

The floor's guard nature is visible in the shipped gate. #36's AC-031
(`test_fresh_crystal_returned_at_k3`, `test_recall_starvation.py:965-1021`) asserts only
`assert "fresh" in ids` — membership. Its fixture returns `[]` from both mocked graph helpers
once `len(seed_ids) > 3`, so at `fetch_width = 10` **the graph and completion arms are empty
and the fusion under test is a two-arm fusion**. The criterion cannot observe P1.

---

## Scope / Non-Scope

### In scope

1. A weighted fusion mechanism with a config surface, replacing unweighted summation on the
   gated path (DP-1, DP-2).
2. A query-conditional weight for the sparse arm (DP-3).
3. Collapsing the correlated derived arms (graph, completion) into one voter (DP-1).
4. Seeding graph + completion expansion from a **base-arm** (sparse + dense) preliminary fused
   order instead of `dense_ranking` alone (issue item 2).
5. Deterministic rank order for the graph and completion arms (P3, DP-8).
6. Deterministic tie-breaking in the new fusion function.
7. Diagnosability: the weights and the query signal that produced them, surfaced in
   `result.explain`.
8. A new deterministic eval gate for fusion quality, plus a multi-layer fixture.
9. `FETCH_WIDTH_FLOOR` corpus-scaling: **decided** (DP-6 — defer the change, land the evidence).

### Out of scope

- **Nexus roster bump.** Separate flow (mission constraint).
- **Reranker.** The BGE stub (`retrieve.py:449-454`) stays commented out.
- **Any change to `k` semantics.** `k` remains a pure response cap (#36 AC-002/003/009).
- **Score-space fusion.** Rejected (§Rejected Alternatives H-C).
- **New runtime dependencies.** None proposed; DP-3 option (c) would still add none.
- **Cross-layer rank blocking — the FIX.** Deferred with rationale (DP-5); the *evidence* to
  decide it later is in scope.
- **`neighbor_expand`'s return type.** DP-8 fixes ordering at the consumer, not the store API.

### Deferred (follow-up issues this change should open)

- **D-1 — cross-layer rank blocking** (DP-5). `sparse_ranking` and `dense_ranking` are built by
  a `for layer in target_layers` loop that *appends* each layer's hits (`retrieve.py:326-360`),
  so rank position is **layer-order-primary, relevance-secondary**.
  `_ALL_LAYERS = ["episodic", "semantic", "procedural", "execution"]` (`retrieve.py:45`), so
  with `layers=None` an episodic hit always precedes every semantic hit regardless of BM25
  score. Recomputed severity — a semantic exact match landing at index `j` behind `j` episodic
  hits:

  | episodic hits ahead (`j`) | episodic rank-1 | semantic rank-1 at index `j` | inverted |
  |---|---|---|---|
  | 1 | 0.016393 | 0.016129 | yes |
  | 2 | 0.016393 | 0.015873 | yes |
  | 5 | 0.016393 | 0.015152 | yes |
  | 10 | 0.016393 | 0.014085 | yes |
  | 30 | 0.016393 | 0.010989 | yes |

  The inversion fires at `j >= 1` — any store with one episodic match. It is **arm-internal**,
  so the sparse boost cannot correct it (at `w_sparse = 2.0`: `2/61 = 0.032787` vs
  `2/91 = 0.021978` — same ordering).
- **D-2 — redundant embedding.** `self.vector_store.embed(query)` is called once *per layer*
  inside the loop (`retrieve.py:340`) — four identical embeddings per default recall.
- **D-3 — `neighbor_expand` discovery order.** DP-8 sorts by id, which is deterministic but
  arbitrary; returning BFS order from the store would be deterministic *and* meaningful.

---

## Approach — Design

### D0 — pipeline order (load-bearing; no feedback loop)

The order below is a hard constraint, not a suggestion: the sparse weight depends on the sparse
arm's size, the seeds depend on the weights, and the derived arms depend on the seeds.

```
1. sparse_ranking, dense_ranking      <- per-layer retrieval (unchanged)
2. n_sparse = len(sparse_ranking)     <- the query-conditional signal (D3)
3. w_sparse, w_dense, w_derived       <- weights resolved once per recall
4. prelim = weighted_fuse(sparse, dense)           <- BASE ARMS ONLY (D4)
5. seed_ids = prelim[:fetch_width]
6. graph_ranking      <- neighbor_expand(seed_ids), deterministically ordered (D5)
7. completion_ranking <- decaying_walk(seed_ids),   deterministically ordered (D5)
8. derived_ranking    <- min-rank merge of (6, 7)   (D2)
9. fused = weighted_fuse(sparse, dense, derived)    <- the final fusion (D1)
```

**Invariant I-1:** step 4 never reads `graph_ranking` or `completion_ranking`. Violating it
creates a feedback loop in which the derived arms influence their own seeds.

### D1 — weighted RRF (new pure function, legacy function untouched)

```python
def weighted_rrf_merge_scored(
    weighted_rankings: list[tuple[list[str], float]],
    k_rrf: int = 60,
) -> list[tuple[str, float]]:
    """score(id) = sum over arms of  w_arm / (k_rrf + rank_arm(id)),  rank 1-based.
    Arms in which `id` does not appear contribute nothing.
    Output sorted by (-score, id) — id-ascending tiebreak, insertion-order independent."""
```

Three deliberate properties:

- **`rrf_merge` and `rrf_merge_scored` are not modified.** They keep their documented
  insertion-order tie-break and remain the flag-off path. `test_rrf.py` must pass
  **unmodified** — its continued green is the non-regression signal (AC-106).
- **Deterministic tie-break `(-score, id)`.** With float weights exact ties are rarer but more
  dangerous; the modelled residual in §D3 produces one. Insertion-order tie-breaks depend on
  the order arms are appended, which P3 shows is not stable.
- **Fixed arm iteration order** (`sparse, dense, derived`) so float summation is
  bit-reproducible.

`rrf_score_by_id` (`retrieve.py:426`) stays the single source of truth for
`_ComposerRecord.relevance_score` -> `CrystalSummary.score` (#36 seam 1). On the gated path it
now holds the **weighted** value. See DP-7.

### D2 — the derived family is ONE voter

Graph and completion are collapsed into a single `derived_ranking` before fusion, by
**min-rank**:

```python
minrank: dict[str, int] = {}
for arm in (graph_ranking, completion_ranking):
    for i, cid in enumerate(arm):
        minrank[cid] = min(minrank.get(cid, 1 << 30), i + 1)
derived_ranking = [cid for cid, _ in sorted(minrank.items(), key=lambda kv: (kv[1], kv[0]))]
```

This is the correction P2 asks for: correlated voters are merged, not summed.

**Why this and not per-arm down-weighting — CORRECTED, revision 1.1.0.** Revision 1.0.0 claimed
static down-weighting was "measurably wrong", citing a 67 % eval-gate F1 collapse. **That claim is
withdrawn.** vigil (F1) showed it inverts under the very correction §Evidence Gaps G-1 flagged and
then wrongly declared itself robust to, and I reproduced vigil's table cell-for-cell before
accepting it. Modelled against the *shipped* `evals/retrieval_gate.py` topology (multi-hop F1 at
k=10, relevant = hub + 2 graph-only spokes), across both readings of where the spokes sit in
`dense_ranking` — ranks shown as (hub, spoke1, spoke2):

| scheme | sketch `rank(T)` | spokes ABSENT from dense (rev 1.0.0's model) | spokes at 25/26 | 27/28 | 29/30 |
|---|---|---|---|---|---|
| today — unweighted sum | 3 | 0,1,3 · F1 0.4615 | 1,0,2 · 0.4615 | 1,0,2 · 0.4615 | 1,0,2 · 0.4615 |
| static `0.5 / 0.5` | 2 (unfixed) | 0,1,30 · 0.3077 | 0,1,2 · **0.4615** | 0,1,2 · **0.4615** | 0,1,2 · **0.4615** |
| static `0.35 / 0.25` | 0 (fixed) | 0,29,30 · 0.1538 | 0,1,4 · **0.4615** | 0,1,5 · **0.4615** | 0,1,7 · **0.4615** |
| family-merge `w_d = 1.0` | 2 | 0,1,3 · 0.4615 | 0,1,2 · 0.4615 | 0,1,2 · 0.4615 | 0,1,2 · 0.4615 |
| family-merge `w_d = 1.0` + boost | **0** | 0,1,3 · 0.4615 | 0,1,2 · 0.4615 | 0,1,2 · 0.4615 | 0,1,2 · 0.4615 |

The mechanism, re-derived: a spoke carrying a dense term at rank 29 contributes
`1/89 = 0.011236`, which down-weighting the *derived* arms does not touch (`w_dense` stays 1.0),
while the distractors it competes with sit in the band `1/62 … 1/90 = [0.011111, 0.016129]`. To
stay in the top 10 the spoke need only beat a dense-rank-7 distractor at `1/67 = 0.014925`, and
`0.35/61 + 0.25/61 + 1/89 = 0.021072` does so comfortably. The spokes-absent column was the one
inference G-1 itself called weak, and `dense_search` is called with `k = candidate_k = 30` against
a 31-crystal corpus — so the spokes are *probably present*, and the corrected columns are the more
probable reading.

**What survives.** Family-merge still closes the issue's sketch under every column (the sketch
fixes T at dense rank 4 and the competitors at 1-3 by construction, so G-1 does not reach it), and
it still leaves the eval-gate ranks undisturbed. What does **not** survive is the empirical
*rejection* of static weights: on the corrected reading their F1 is identical, and only the spoke
*rank* margin degrades (1/2 -> 1/7 at the 29/30 column) — a fragility signal, not a capability
loss. DP-1 and DP-2 are re-opened accordingly.

**Identity property (verified to 1e-15):** with `w_derived = 1.0` and the completion arm inactive,
family-merge is **exactly** today's fusion — same ids, same scores. A single derived arm re-ranked
by its own min-rank is that arm. AC-108 pins this at the function boundary and AC-135 at the path
level (the latter added because §D2 and R-2 both lean on a *path*-level claim, vigil A-9).

**Identity property (verified to 1e-15):** with `w_derived = 1.0` and the completion arm
inactive, family-merge is **exactly** today's fusion — same ids, same scores. A single derived
arm re-ranked by its own min-rank is that arm. So the correction only bites when
`recall_completion` is on (AC-108).

### D3 — the query-conditional sparse weight

```
cap         = candidate_k * len(target_layers)             # candidate_k = max(k*3, 10)
n_sparse    = len(sparse_ranking)
N_scoped    = crystal count WITHIN target_layers           # NOT the whole store — see below
selectivity = 0.0                                          if n_sparse == 0 or n_sparse >= cap
              clamp(1.0 - n_sparse / max(1, N_scoped), 0, 1)  otherwise
w_sparse    = 1.0 + FUSION_SPARSE_BOOST_ALPHA * selectivity   # in [1.0, 1.0 + alpha]
```

**The denominator is search-space-local, not global — corrected in revision 1.1.0 (vigil F5).**
Revision 1.0.0 used the whole-store count, which mixes a numerator counted *within the searched
layers* with a denominator counted *across all of them*. They agree only when `layers=None`.
Reproduced:

| case | `n_sparse` | global `N` | global `w_sparse` | scoped `w_sparse` | true in-search-space selectivity |
|---|---|---|---|---|---|
| `layers=None`, distinctive | 1 | 10005 | 1.9999 | 1.9999 | 0.9999 |
| `layers=['procedural']`, matches **all 5** | 5 | 10005 | **1.9995** | **1.0000** | 0.0000 |
| `layers=['semantic']`, matches **all 20** | 20 | 10020 | **1.9980** | **1.0000** | 0.0000 |

A query matching 100 % of the layer it searched — maximally *non*-selective — drew a near-maximal
boost, because ten thousand crystals it never looked at inflated the denominator. The censoring
branch does not save it (`n_sparse = 5 < cap = 30`), and **every criterion of revision 1.0.0
survived it**, AC-112's bound included. AC-134 is the oracle that now goes RED on it. `cap` was
already made search-space-local by multiplying through `len(target_layers)`; `N` now matches.

**The numerator and the denominator MUST be drawn from the same population — binding, and the
part revision 1.1.0 got only half right (vigil G-2).** F5 corrected the *layer* population; the
*status* population was left unspecified, and the two ends default to different ones:

- **Numerator.** `n_sparse = len(sparse_ranking)` comes from `bm25_search`, which applies **no
  status predicate** (`relational.py:493-541`, verified — no `status` token in either branch) over
  an FTS index whose triggers carry every row including deprecated ones (`relational.py:75-88`, no
  status guard). So `n_sparse` counts inactive crystals. `recall_active_only` (default `True`,
  `config.py:225`) removes them only at `retrieve.py:482-505` — **after** the fusion at `:424`.
- **Denominator.** "crystals in the searched layers" did not say which statuses, and the natural
  implementation counts active ones; the existing helper is literally `count_active_by_scope_key`.

Mixed, the ratio inflates, selectivity is depressed, and `w_sparse` decays monotonically toward
1.0; in the degenerate case `n_sparse > N_scoped` the clamp pins it at 1.0 outright. Under P0-5
("write-new, never hard-delete") deprecated rows accumulate **by design**, so the headline feature
would die silently in exactly the long-lived stores it exists for — no error, no log line, no
`explain` anomaly — and every fixture among AC-101..AC-139 is a fresh store. This is the same
species as F5 along the axis the F5 repair did not reach. **AC-142** is the population-agreement
oracle; it goes RED only on the mixed implementation and is satisfied by either resolution of the
new **DP-9**. `explain.fusion` must name the population, not just the count (AC-117).

`N_scoped` is obtained per DP-3 and its status population per DP-9. Rationale for each branch:

- `n_sparse >= cap` — the result set was **censored** by the fetch cap; the true match count is
  unknown and >= cap. Treat as non-selective: `w_sparse = 1.0`.
- `n_sparse == 0` — no sparse votes exist; the weight is unobservable, so pin it neutral.
- otherwise `n_sparse` is the *true* match count within the searched layers, and selectivity is
  relative to those same layers.

FTS5 applies implicit AND across query terms (`relational.py:189-201` quotes each token; the
default `crystals_fts` config is conjunctive), so this measures **how far the lexical arm
narrowed the corpus for this query** — a direct measure of the arm's fit, which is the property
the issue is actually after. Worked values:

| `N` | `n_sparse` | selectivity | `w_sparse` (alpha = 1.0) |
|---|---|---|---|
| 31 | 1 | 0.9677 | 1.9677 |
| 31 | 20 | 0.3548 | 1.3548 |
| 10000 | 1 | 0.9999 | 1.9999 |
| 10000 | 20 | 0.9980 | 1.9980 |
| 10000 | 120 (= cap) | 0.0000 | 1.0000 |
| 25 | 20 | 0.2000 | 1.2000 |

The boost is safe *because* it is conditional: it only fires when few records match, so there
are few records to promote. A generic query gets `w_sparse = 1.0` and today's behaviour.

**Recommended defaults resolve the issue's acceptance sketch across the whole selectivity range
except the neutral end:**

| selectivity | `w_sparse` | `rank(T)` | `T` score | top competitor |
|---|---|---|---|---|
| 1.00 | 2.00 | **0** | 0.048414 | N1 0.032787 |
| 0.75 | 1.75 | **0** | 0.044313 | N1 0.032787 |
| 0.50 | 1.50 | **0** | 0.040215 | N1 0.032787 |
| 0.25 | 1.25 | **0** | 0.036117 | N1 0.032787 |
| 0.00 | 1.00 | 2 | 0.032018 | N1 0.032787 |

The `selectivity = 0` row is the honest limit: for a query with no lexical distinctiveness there
is no signal to act on, and `w_derived = 1.0` alone leaves `T` 2.4 % short. Closing that row
costs multi-hop depth — that trade is **DP-2**.

**Known residual (not closed by this design).** When the target is visible to the sparse arm
*only* (dense misses it entirely):

| `w_sparse` | `rank(T)` | `T` | `N1` |
|---|---|---|---|
| 1.0 | 3 | 0.016393 | 0.032787 |
| 1.5 | 3 | 0.024590 | 0.032787 |
| 1.8 | 3 | 0.029508 | 0.032787 |
| 2.0 | 1 | 0.032787 | 0.032787 (**exact tie**, broken by id) |

A one-arm candidate cannot reliably outrank a two-arm candidate under any bounded weight. This
is outside the issue's stated acceptance sketch (which specifies dense rank 4, i.e. two arms)
and is recorded here rather than silently satisfied. **No acceptance criterion is written on
this scenario** — a criterion whose margin is an exact float tie is a flake generator.

### D4 — seeding from the base-arm preliminary fusion

```python
prelim = weighted_rrf_merge([(sparse_ranking, w_sparse), (dense_ranking, w_dense)])
seed_ids = prelim[:fetch_width]                      # replaces dense_ranking[:fetch_width]
completion_seeds = seed_ids or sparse_ranking[:fetch_width]
```

- `fetch_width = max(k, FETCH_WIDTH_FLOOR)` is **unchanged** (`retrieve.py:374`); #36 AC-031's
  seam-3b guarantee is untouched, and the seed *count* is unchanged.
- A record the sparse arm surfaces but the dense arm ranks below `fetch_width` now becomes a
  seed. That is issue item (2), and it is what makes the graph walk topic-appropriate rather
  than embedding-appropriate.
- Invariant I-1 holds by construction: `prelim` reads only base arms.
- `completion_seeds`' `or sparse_ranking[:fetch_width]` fallback becomes near-dead (prelim is
  non-empty whenever either base arm is). Keep it — free and defensive — but say so in the
  comment so it is not mistaken for a live path.
- **No modelled eval-gate impact:** in the shipped fixture `sparse_ranking = [hub]` and
  `dense_ranking = [hub, D1..D24]`, so prelim's top-10 is byte-identical to `dense_ranking[:10]`.

### D5 — determinism (prerequisite, P3)

Two one-line consumer-side fixes in `retrieve.py`, no storage API change:

```python
for nid in sorted(neighbour_ids):                            # was: for nid in neighbour_ids
for cid, _score in sorted(walked.items(), key=lambda kv: (-kv[1], kv[0])):  # id tiebreak added
```

Both replace hash-order with a total order. `sorted()` on a set of ids is deterministic across
processes; the completion sort keeps score-primary and makes the within-hop order stable.

This is deliberately *ordering* determinism, not *relevance* ordering — `neighbor_expand` has no
relevance signal to offer (it returns a set). Discovery-order preservation is D-3.

### D6 — config surface

| field | default | env | note |
|---|---|---|---|
| `recall_weighted_fusion` | `True` (DP-4) | `CRYSTALIUM_RECALL_WEIGHTED_FUSION` | master gate |
| `fusion_weight_dense` | `1.0` | `CRYSTALIUM_FUSION_WEIGHT_DENSE` | |
| `fusion_weight_derived` | `1.0` (DP-2) | `CRYSTALIUM_FUSION_WEIGHT_DERIVED` | graph + completion family |
| `fusion_sparse_boost_alpha` | `1.0` (DP-3) | `CRYSTALIUM_FUSION_SPARSE_BOOST_ALPHA` | `w_sparse` in `[1, 1+alpha]` |

There is deliberately **no** `fusion_weight_sparse`. RRF ordering is invariant to a global
positive scale factor (`score` values scale, the sort does not), so pinning the sparse base at
1.0 removes a redundant degree of freedom. Document that in the field comment — otherwise its
absence reads as an oversight.

Follow the existing pattern exactly: dataclass field with a comment naming the decision,
`_env_bool`/`_env_float` line in `from_env`, and an entry in the matching `_from_dict` tuple —
`bool_field` (`config.py:345-349`) for `recall_weighted_fusion`, and `float_field`
(`config.py:375-390`) for the three floats.

**`_from_dict` is the silent-failure surface.** It is a hand-maintained allowlist: a field
present in the dataclass and in `from_env` but absent from the relevant tuple is accepted from
the environment and **silently ignored from `crystalium.yaml`**. AC-127 exists specifically
because a test that only sets `CRYSTALIUM_*` cannot observe that, and it must therefore be
parameterised over both sources.

### D7 — gating and subsumption

`recall_weighted_fusion` is **subsumed by** `recall_relevance_primary`: the weighted path is
taken only when both are on.

```python
self._weighted = bool(recall_weighted_fusion and recall_relevance_primary)
```

Why subsumption rather than independence: `recall_relevance_primary=False` is contractually
"byte-identical to pre-1.9.0" (#36 AC-008/AC-009, frozen). An independent weighting flag would
alter the fused order on that path and put those frozen criteria at risk.

The known hazard of subsumption is the half-gated mode FORGE closed in #36 DP-R4(iii)
(`Composer(...)` silently ignoring `Config.recall_relevance_primary`). Close it the same way,
one step further: the subsumption is **pinned by an acceptance criterion** (AC-120), so
"weighted flag on, relevance-primary off => unweighted fusion" is tested behaviour rather than
an emergent property. Use the same `None`-sentinel constructor idiom DP-R4(iii) introduced.

### D8 — diagnosability

`result.explain` gains a `fusion` object (explain-gated; no cost on the hot path):

```json
"fusion": {
  "weighted": true,
  "w_sparse": 1.9677, "w_dense": 1.0, "w_derived": 1.0,
  "selectivity": 0.9677,
  "n_sparse": 1, "n_sparse_cap": 120,
  "n_scoped": 31, "n_scoped_layers": ["episodic","semantic","procedural","execution"],
  "n_scoped_status": "active_only",
  "fetch_width": 10,
  "arm_sizes": {"sparse": 1, "dense": 25, "graph": 1, "completion": 2, "derived": 2}
}
```

**Field-name note (vigil N-1).** Revision 1.2.0 called the denominator `corpus_n`, which was
stale in both name and semantics after F5 made it search-space-local — and AC-142's VERIFY asserts
`explain["fusion"]["n_scoped"]`, a key that appeared nowhere in this document. Renamed to
`n_scoped` here, with `n_scoped_layers` and `n_scoped_status` added so the object satisfies AC-117
(the denominator's value **together with the status population it was drawn from**) and so AC-142's
population-agreement assertion has both operands. `n_scoped_status` takes the value DP-9 rules;
`all_statuses` and `active_only` are the two admissible values.

`fetch_width` is included specifically to give DP-6's deferred corpus-scaling question an
evidence trail. `explain` and the surfaced `score` must never disagree — the same rule #36 DP-3c
applied to `budget`.

---

## Decision-Points — OPEN (for FORGE)

Each carries my recommendation. None is pre-bound.

### DP-1 — the weighting mechanism

- **(a)** Static per-arm weights only.
- **(b) [RECOMMENDED]** Correlated-family merge (D2) + query-conditional sparse boost (D3), with
  per-arm weights present as a config surface defaulting to 1.0 for dense and derived.
- **(c)** Score-space fusion — expose BM25/dense scores, normalise, combine convexly.
- **(d)** Keep unweighted RRF; add an invariant that a candidate present in no base arm may not
  outrank the rank-1 entry of any base arm.
- **(e)** Fix seeding only; leave fusion unweighted.

**STATUS — GENUINELY OPEN between (a) and (b); revision 1.0.0 over-claimed.** The empirical
rejection of (a) is **withdrawn** (§D2, vigil F1): on the more probable dense-arm reading, static
`0.35/0.25` and family-merge deliver the *same* eval-gate F1 (0.4615), and both close the issue's
sketch. Re-scored on the corrected evidence, H-A rises from `61.5 weak` to `72.5 solid` against
H-B's `81.5 solid` — a 9-point gap, not the 20-point gap revision 1.0.0 presented. Both scores are
in the plan state.

**Recommendation: still (b), but now on principled rather than empirical grounds, and at
materially lower confidence.** Three arguments survive F1:

1. **(b) needs no arbitrary constant.** Its derived weight is 1.0 — literally "change nothing about
   how much the derived family counts" — so it carries the §D2 identity property and cannot
   regress a multi-hop path it does not touch. (a) requires choosing `0.35/0.25` or `0.5/0.5` with
   no evidence that now distinguishes them.
2. **(a)'s surviving cost is margin, not capability.** At the 29/30 column the spokes land at ranks
   1 and 7 of 10 under (a) versus 1 and 2 under (b). Same F1 today; three fewer positions of
   headroom before a distractor evicts a spoke.
3. **(a) does not fix the generic-query case either** — at `0.5/0.5` the sketch stays unfixed
   (`rank(T) = 2`), so (a) still needs a selectivity signal or a lower constant to be complete.

**Binding pre-deliberation input (vigil prescription 1, adopted).** The H-A arm is a two-constant
change to a config the existing `retrieval-gate` already runs. **FORGE should not rule DP-1 or
DP-2 on either model.** Before deliberation, run `python -m evals retrieval-gate` under
`w_graph=0.35, w_comp=0.25` and under family-merge, on the real stack, and put both measurements in
the docket. I could not run it (evidence gap G-2, read-only). Everything above is a model, and the
last model that decided this DP was wrong.

Note that (b) delivers the *mechanism* the issue asks for (per-arm weights, config-surfaced) while
its shipped defaults decline to down-weight anything.

### DP-2 — `fusion_weight_derived` default: the precision / multi-hop dial

Modelled, generic query (`selectivity = 0`, `w_sparse = 1.0`):

| `w_derived` | issue sketch `rank(T)` | eval-gate ranks (hub, spoke1, spoke2) |
|---|---|---|
| 1.00 | 2 | 0, 1, 3 |
| 0.98 | 1 | 0, 2, 4 |
| 0.96 | 1 | 0, 3, 5 |
| **0.95** | **0** | 0, 4, 6 |
| 0.90 | 0 | 0, 7, 9 |
| 0.85 | 0 | 0, 11, 13 |
| 0.80 | 0 | 0, 16, 18 |

- **(a) [RECOMMENDED] `1.0`** — the identity property of §D2 holds exactly; satisfies the issue's
  stated acceptance sketch (which specifies a *distinctive-token* query, so `selectivity > 0`).
- **(b) `0.95`** — additionally closes the generic-query row; spokes move from ranks 1/3 to 4/6 on
  the spokes-absent model, reducing the margin before they fall out of `k = 10`.

**Recommendation (a), with the same caveat as DP-1.** The table above is computed on the
spokes-absent model, which vigil F1 showed is the *less* probable reading; the "zero modelled
multi-hop cost" framing revision 1.0.0 used for (a) inherits that weakness. What is model-independent
is the identity property: at `w_derived = 1.0` the derived family's contribution is unchanged by
construction, so (a) cannot regress multi-hop retrieval whatever the dense arm actually contains,
whereas any value below 1.0 can. That is the argument for (a) that F1 does not touch. The
generic-query trade remains real, and the measurement ordered in DP-1 should be run at both values
so FORGE rules on data.

### DP-3 — the query-conditional signal

- **(a) [RECOMMENDED]** Search-space-relative selectivity `1 - n_sparse/N_scoped`, with
  `N_scoped` counted over `target_layers` (§D3, corrected per vigil F5). Needs one cheap bounded
  `count()`.
- **(b)** Fetch-relative `1 - (n_sparse-1)/(cap-1)`. Zero new I/O and zero storage surface, but
  the denominator is a fetch artifact, not a corpus property: 20 matches reads the same in a
  25-crystal store and a 10 000-crystal store.
- **(c)** True per-token IDF via `SELECT count(*) ... MATCH '"tok"'` per token. Most faithful to
  the issue's literal wording ("distinctive-token"), still no new dependency and no schema
  change, but N extra queries per recall.
- **(d)** No query-conditional weighting. Rejected by §D3's table — `w_derived = 1.0` alone
  leaves `rank(T) = 2`.

**Recommendation (a).** It measures the arm's *actual* discriminative power on this query rather
than a proxy for it. Concretely (a) and (c) disagree on the shipped eval-gate query "acme login
session token rotation": five common tokens whose conjunction matches exactly one document of
~31. (c) sees common tokens and declines to boost; (a) sees a corpus narrowed to one and boosts.
(a) is right there, and the case is not contrived — it is the fixture the repo already ships.

**Cost note for FORGE — corrected (vigil A-6).** Revision 1.0.0 said (a) "adds a public method to
`RelationalStore`" and described `diagnostics_summary` as issuing four aggregates. It issues
**five** (`relational.py:996, 998, 1001, 1005, 1008`), and more usefully the store **already**
carries `count_for_export` (`:926-977`, a single bounded `SELECT count(*) FROM crystals WHERE …`)
and `count_active_by_scope_key` (`:1019`). A layer-scoped count is a small extension of an existing
idiom rather than a new surface, which materially weakens the objection this DP was asking FORGE to
weigh. If the surface is still unwelcome, (b) is a genuine fallback whose only defect is
scale-blindness.

### DP-4 — flag surface and default state

- **(a) [RECOMMENDED]** New `recall_weighted_fusion`, default **ON**, subsumed by
  `recall_relevance_primary` (D7), subsumption pinned by AC-120.
- **(b)** New flag, default OFF, promoted after a gate win — the repo's standard
  "ablation-or-revert" posture (`config.py:196-197`).
- **(c)** No new flag; ride `recall_relevance_primary`.

**Recommendation (a), with a mechanical contingency — WIDENED in revision 1.1.0 (vigil F6):**
default ON **iff all five** of AC-121 (the 32 frozen #36 criteria), AC-122 (the F-V1 four-cell
probe), AC-123 (`make test`), AC-124 (retrieval-gate non-inferiority) and AC-125 (the new fusion
gate) are green on the implementation branch. If any is red the default flips to OFF automatically
and the change returns to FORGE. Revision 1.0.0 bound only AC-124/125, so a red *non-regression*
gate — a strictly more serious signal — had no rule, which is exactly how a gate declared
"mechanical, never discretionary" becomes discretionary. AC-136 now pins this. (c) is unsafe: it
makes `recall_relevance_primary=false` a two-change revert and forfeits the ablation arm the repo's
own doctrine requires.

**DP-4(ii) — does a red AC-140 flip the shipped default? (NEW, vigil C-2.)** AC-140 is the issue's
literal acceptance bar ("without relying on the fetch-width floor"). Revision 1.2.0 excluded it from
the AC-136 contingency on the reasoning that a red AC-140 is a finding about the change's *nature*
(layered on the guard rather than replacing it) rather than a correctness failure of the shipped
default — so it should route to DP-1 as deliberation input, not trigger an automatic flag flip.
vigil upheld the reasoning but ruled that **"the issue's literal acceptance bar is red and the flag
still ships ON" is a call the deliberating authority must make on the record**, not one a spec may
assume. So: options are **(a)** red AC-140 leaves the default ON and routes to DP-1 (revision
1.2.0's assumption, now offered rather than assumed), or **(b)** red AC-140 joins AC-136's
contingency and flips the default to OFF. **Recommendation (a)**, for the reason above — but this
is explicitly FORGE's to rule, and AC-136 records the list as pending that ruling.

**Blast-radius analysis onto #36's flag-on criteria (vigil F6, owed and now stated).** D7 subsumes
weighted fusion under `recall_relevance_primary`, which #36's flag-on tests set to `True` — so
every #36 flag-on criterion runs against a *changed fusion*. Reviewed by criterion class:

- **Membership/count criteria** (#36 AC-001, 002, 003, 008, 009, 031) assert set membership or
  `len(records)`, not fused order. Weighting reorders; it removes no candidate from the ranking
  universe, and the `[:k]` gate is applied to a set that is a permutation of the same members. Safe
  by argument; AC-121 is the mechanical check.
- **Ordering criteria** (#36 AC-007) assert non-increasing `score`. Seam 5 sorts by whatever
  `rrf_score_by_id` holds, so the contract is weight-agnostic. Re-asserted under weighting by
  AC-118.
- **Field-semantics criteria** (#36 AC-005, 006, 015-018, 032) assert presence, derivation and
  bounds of `score`/`budget`, none of which depend on the fused *values*.
- **Ranked-position criteria** — **none exist in #36.** That is the reason this analysis comes out
  clean, and it is also precisely the gap #38 exists to close.

This is an argument, not a measurement; AC-121 is what makes it falsifiable, and AC-136 is what
makes a red result binding.

The default-ON argument is #36's, restated: this is a correctness fix, not an optional faculty.
The contingency exists because, unlike #36's correctness claim, this one has a measurable way to
be wrong.

### DP-5 — cross-layer rank blocking (D-1)

- **(a)** Fix now by round-robin interleaving the per-layer rankings.
- **(b)** Fix now by true score merge (requires exposing `bm25()` from
  `RelationalStore.bm25_search`).
- **(c) [RECOMMENDED]** Defer the fix; land the evidence — a multi-layer eval fixture (AC-126)
  plus per-arm rank surfacing in `explain` (D8) — and open follow-up issue D-1.

**Recommendation (c).** The defect is real and confirmed by reading (`retrieve.py:326-360` plus
`_ALL_LAYERS` order), and it fires at `j >= 1`. But: it is arm-internal and orthogonal to fusion
weighting; the acceptance sketch is single-layer and passes either way; and — decisively —
**there is currently no gate that could observe a cross-layer regression.** Every crystal in
`evals/retrieval_gate.py` is committed to `episodic` (`retrieval_gate.py:88-102`), so the shipped
gate is single-layer in practice despite calling recall with `layers=None`. Landing an
unmeasurable reordering of every multi-layer recall inside a change whose thesis is "the previous
fix was a guard, not a cure" would repeat the error. Fix it next, with a gate that can fail.

If FORGE prefers (a), it must land with AC-126's fixture *first*, not alongside.

### DP-6 — `FETCH_WIDTH_FLOOR` corpus scaling

- **(a)** Scale with corpus size, e.g. `max(10, ceil(sqrt(N)))`.
- **(b) [RECOMMENDED]** Explicitly defer; surface `fetch_width` in `explain` (D8) so the question
  can be decided on data.

**Recommendation (b), as a decision, not a punt.** The floor is a *stability* device — DP-R1
introduced it to keep the ranking universe k-independent, and its own rationale ("converging
small-k rankings onto the well-tested default-k=10 ranking is strictly variance-reducing") argues
against making it a function of anything that drifts. Scaling it with `N` makes the ranking
universe a function of corpus size, so the same query against the same crystals returns a
different ranking after unrelated commits — which breaks reproducibility for exactly the
deterministic eval gates this change depends on, and for AC-105. Meanwhile the recall ceiling a
growing corpus actually threatens is `candidate_k = max(k*3, 10)` (`retrieve.py:324`) — the
*per-layer fetch*, not the *seed width*. If corpus scaling is warranted anywhere it is there, and
that needs measurement this spec cannot supply.

### DP-7 — surfaced `score` semantics

`rrf_score_by_id` is the frozen source of truth for `CrystalSummary.score` (#36 seam 1, DP-5).
Under weighting its values change: same ordering semantics, different magnitudes, and a larger
attainable maximum (`w_sparse` reaches `1 + alpha`).

- **(a) [RECOMMENDED]** Surface the weighted fused value; document the change in CHANGELOG and
  the MCP manifest; make it interpretable via `explain.fusion`.
- **(b)** Normalise to [0, 1] before surfacing.
- **(c)** Surface both (raw + normalised).

**Recommendation (a).** `score` is already documented as "raw hybrid-retrieval RRF value"
(`server.py:191-193`) and is not comparable across queries today either — normalising by the top
score would make it *look* comparable while remaining query-relative, which is worse. (c) doubles
the schema surface for a field no consumer has been shown to need.

**Binding regardless of choice:** `server.py:186-197` and `CHANGELOG.md` must state that `score`
is now weighted (AC-128). A surfaced number whose meaning changed silently is the "lockfile can
lie" species.

### DP-8 — graph/completion arm determinism (P3)

- **(a) [RECOMMENDED]** Sort at the consumer in `retrieve.py` (D5). Two lines, no API change.
- **(b)** Change `GraphStore.neighbor_expand` to return an ordered `list[str]`.
- **(c)** Pin `PYTHONHASHSEED` in the container/test harness.

**Recommendation (a).** (c) is not a fix — it hides the defect from CI while leaving every
operator process non-reproducible, and it is precisely the "fail-open hides dead kernels"
pattern. (b) is better engineering but changes a store method used elsewhere; it belongs in D-3
with a proper call-site audit.

**FORGE should note this DP is not optional in the way the others are.** AC-101/102 assert fused
rank positions with graph and completion candidates in play. Without DP-8 those criteria are not
deterministic, and a green result would not mean what it says.

### DP-9 — the selectivity denominator's *status* population (NEW, vigil G-2)

Population *agreement* is binding either way (§D3, AC-142). Which population is open:

- **(a)** **All statuses** — denominator counts every crystal in `target_layers` regardless of
  status. This is exactly the population `bm25_search` searched, so agreement holds by
  construction with no filtering of the numerator. Cheapest, and the ratio is age-stable in the
  sense that both ends grow together.
- **(b) [RECOMMENDED]** **Active-only on both ends**, tracking `recall_active_only`: filter the
  numerator with the same `_is_active` predicate the response applies, and count the denominator
  with the active-scoped helper. When `recall_active_only` is `False` the response returns
  everything, so the consistent population is then all-statuses — i.e. the rule is *"the
  denominator's status scope matches the status scope the response applies"*, not a fixed choice.

**Recommendation (b), and the difference is not cosmetic.** Under (a) the boost still decays,
honestly rather than spuriously: CRYSTALIUM's dominant write pattern is bi-temporal supersession,
so the deprecated rows are *lexical near-duplicates of the very crystal the distinctive query is
looking for*. Worked: 1 fresh crystal plus 50 superseded revisions of it, in a layer of 100 active
+ 50 deprecated. (a) resolves `1 - 51/150 = 0.66 -> w_sparse 1.66`; (b) resolves
`1 - 1/100 = 0.99 -> w_sparse 1.99`. The caller sees exactly one record either way, because the
response filters the other 50. (a) therefore lets records the caller will never see dilute the
signal that decides the caller's ranking.

The cost of (b) is one `_is_active` pass over `sparse_ranking` — the crystal dicts are already in
hand (`bm25_search` returns full rows via `_row_to_dict`), so it is a pure-Python filter with no
extra I/O — plus the `recall_active_only` gating, which is the part that must be tested rather than
assumed.

**Two mechanism facts FORGE must have (raised by vigil in round 3; both bear on the ruling).**

1. **(b) is not a denominator choice alone — it needs an active-only NUMERATOR too.** `bm25_search`
   has no status predicate, so choosing (b) without filtering the numerator produces exactly the
   mixed population AC-142 exists to forbid. The cheap and correct route is to count active hits
   *within* `sparse_ranking`, **for weight purposes only**, leaving the sparse arm itself and the
   fused ranking untouched. Stating this explicitly matters: an implementer who reads "active-only"
   as a storage concern may reach for a status predicate on `bm25_search`, which is a **shared**
   method — that would silently change the candidate set for every caller and is out of scope.
2. **(a) carries a second failure mode this DP did not previously mention, and it strengthens the
   case for (b).** `bm25_search` applies `LIMIT candidate_k` with no status filter, so deprecated
   near-duplicates consume fetch slots: they can push `n_sparse` up to `cap` and trip the censoring
   branch to `w_sparse = 1.0`, and they can crowd active hits out of the candidate set entirely.
   That second effect is a **pre-existing** defect of the sparse arm, out of scope to fix here, but
   it is decision-relevant — under (a) the aging store degrades along two paths rather than one.

vigil prescribed (a) as "cheaper and more honest". I am recommending against it on the aging
argument above and recording the disagreement rather than silently taking the prescription; AC-142
was deliberately written to be neutral so FORGE can rule either way without a further amend.

---

## Rejected Alternatives

Scored via `ramza-score --rubric explore`; all five recorded in the plan state.

### H-A — static per-arm weights only — **72.5 (solid)**, re-scored in revision 1.1.0 — NOT REJECTED

The issue's most literal reading. **Revision 1.0.0 rejected this "on measurement, not taste". The
measurement was wrong and the rejection is withdrawn** (§D2, vigil F1): on the more probable
dense-arm reading, `w_graph = 0.35, w_comp = 0.25` leaves eval-gate multi-hop F1 at 0.4615 —
identical to today and to H-B — and closes the issue's sketch. The original `correctness 3` score
was assigned on the inverted number; re-scored at 7 (it does close the sketch, and the refutation
is gone) with `risk` at 5 (the spoke rank margin still degrades to 1/7 at the 29/30 column), the
hypothesis totals **72.5 solid** rather than 61.5 weak.

It is listed here rather than in §Decision-Points only for continuity of numbering — **DP-1 now
treats it as a live option**, and the measurement ordered there is what should settle it. The one
surviving objection is that its two constants are unjustified by any evidence that currently
distinguishes `0.35/0.25` from `0.5/0.5`, and that at `0.5/0.5` it does not close the sketch at
all.

### H-C — score-space fusion (normalised BM25 + cosine, convex combination) — **59 (weak)**

Highest ceiling of the five: real scores carry margin information that ranks discard. Rejected
for this change: BM25 scores are not exposed (`bm25_search` returns `self._row_to_dict(r)` with
no `bm25()` column, `relational.py:493-541`), so it needs a storage API change; raw BM25 is
corpus- and query-length-relative, so any normalisation is a new, unvalidated design with its own
failure modes; and it discards every rank-based invariant the frozen #36 criteria and
`test_rrf.py` are written against. Worth revisiting once a fusion eval gate exists (AC-125) —
which is one reason to build that gate here.

### H-D — base-arm rank-1 protection invariant — **65.5 (weak)**

"A candidate present in no base arm may not outrank the rank-1 entry of any base arm." Minimal
blast radius, and it encodes the acceptance sketch exactly. Rejected because it fixes the
*instance* the issue used as an illustration rather than the *class* the issue describes — it
does nothing at base rank 2 — and because a bolt-on guard defending a single rank position is the
same shape as the fetch-width floor this issue exists to supersede. Shipping it would mean
answering "the guard is not a cure" with a second guard.

### H-E — fused-order seeding only — **60.5 (weak)**

Cheapest, and a genuine improvement (it is issue item 2, adopted into the recommendation as D4).
Rejected **as a standalone fix** because it provably cannot satisfy the acceptance sketch: seeding
determines *which* neighbourhoods are explored, fusion determines *how much* their votes count,
and the sketch's failure is entirely in the second. In #36's F-V1 scenario the walk started from
the fresh crystal's own neighbourhood — correct seeding, wrong fusion.

---

## Stories

Executor-tier hints assume the #36 implementer (vivi). Timeboxes are days.

### S-1 — deterministic arm ordering (P3 / DP-8) · 0.5 d · P0

**As** the fusion gate, **I need** graph and completion ranks to be identical across processes,
**so that** any criterion asserting a fused rank position is a criterion.
Land **first and alone** — every later story's tests depend on it.
*Plan:* D5's two edits; add a `PYTHONHASHSEED`-varying subprocess test.
*Executor hint:* mid tier. *Output contract:* diff <= 2 statements in `retrieve.py` + 1 test.
*Criteria:* AC-105, AC-131.

### S-2 — `weighted_rrf_merge_scored` pure function · 1 d · P0

**As** the fusion layer, **I need** a weighted, deterministically-tie-broken RRF, **so that** arm
influence is expressible. Includes the min-rank derived-family merge (D2) as a separate pure
helper.
*Plan:* new functions in `retrieve.py`; `rrf_merge*` untouched; extend `test_rrf.py` with a new
class, leaving existing tests byte-identical.
*Executor hint:* any tier — fully specified. *Output contract:* two pure functions + unit tests.
*Criteria:* AC-104, AC-105, AC-106, AC-107, AC-108.

### S-3 — query-conditional weight resolution · 1 d · P1

**As** recall, **I need** `w_sparse` derived from the query's lexical selectivity.
*Plan:* D3's formula in a pure helper taking `(n_sparse, cap, N, alpha)`; the store `count` per
DP-3(a); resolve once per recall.
*Executor hint:* mid tier — the branch conditions are the subtle part; DP-3 may change the signal
source, so keep the helper's signature narrow.
*Criteria:* AC-109, AC-110, AC-111, AC-112.

### S-4 — wire fusion + seeding into `Aetheryte.recall` · 1.5 d · P0

**As** recall, **I need** D0's pipeline order, base-arm seeding (D4), and the weighted fusion
feeding `rrf_score_by_id`.
*Plan:* restructure `retrieve.py:362-426` per D0; `fetch_width` untouched; comment I-1 explicitly
at the `prelim` site.
*Executor hint:* top tier — this is the hot path with the repo's worst fragility history (#36
R-7, the v1.8.1 crash).
*Criteria:* AC-101, AC-102, AC-103, AC-113, AC-114, AC-115, AC-116, AC-118.

### S-5 — config surface + gating · 0.5 d · P1

**As** an operator, **I need** the four fields of D6 and the subsumption of D7.
*Plan:* `config.py` dataclass + `from_env` + `_from_dict` (**both** the `bool_field` tuple and
the `float_field` tuple — see D6); `None`-sentinel constructor idiom at both **production** `Aetheryte(`
construction sites — `server.py:548` and `__main__.py:340`. Audited: there are **10** `Aetheryte(`
sites in total, the other 8 being tests (`test_context_match.py:47`, `test_aetheryte.py:146/358`,
`test_diagnosability.py:429/462`, `test_recall_starvation.py:175/213/1004`), so a grep for the
symbol will not match the count (vigil A-4); update the
manual `Config.__new__` test helpers **in the same commit**. Audited at `ef42967` — there are
**five**, not the four #36's C-8 enumerated: `test_aetheryte.py:42`, `test_composer.py:82`
(moved from `:73`), `test_dream_worker.py:34`, `test_dream_scheduler.py:41`, and
`test_recall_starvation.py:82`, which #36 itself added and its own condition therefore predates.
*Criteria:* AC-119, AC-120, AC-127.

### S-6 — diagnosability · 0.5 d · P2

**As** an operator, **I need** `explain.fusion` (D8) and a schema that admits it.
*Plan:* build the object explain-gated. **No schema edit is required** — verified at
`ef42967`: `schemas/recall-result.v1.json` is `additionalProperties: false` at the top level (the
trap #36 hit), but its `explain` property is deliberately loose, its own description reading
"additionalProperties is intentionally loose so evolving keys ... never re-drift this schema".
`explain.fusion` therefore validates as-is. AC-129 still asserts it, because "no edit required"
is a claim a schema change could quietly invalidate.
*Criteria:* AC-117, AC-129.

### S-7 — eval gates + non-regression · 2 d · P0

**As** the release, **I need** a gate that can fail on the defect this change names.
*Plan:* new `evals/fusion_gate.py` + `fusion-gate` subcommand in `evals/__main__.py` +
`mcp-server/tests/test_fusion_gate.py` (template: `retrieval_gate.py` / `test_retrieval_gate.py`);
multi-layer fixture; capture `eval-before.json` **before any code change**.
*Executor hint:* top tier — the gate must be attacked, not merely written.
*Criteria:* AC-121, AC-122, AC-123, AC-124, AC-125, AC-126, AC-130.

---

## Acceptance Criteria

The 42 blocks are held verbatim in the frozen sibling `spec.criteria.md` (amended twice; the
current hash is in the plan state and in §Gate record). IDs run **AC-101..AC-142** to stay unambiguous against #36's AC-001..AC-032,
which remain in force unchanged and are re-asserted here by AC-121.

Load-bearing properties of the set:

- **AC-101/102 assert fusion rank 1, not membership.** `result.records[0].id == target`, with
  AC-102 parameterising `k` over `{1, 3, 5, 10, 25}` so a rank that depends on `k` fails. Contrast
  #36's AC-031, which asserts `"fresh" in ids` against a fixture whose graph arms are empty.
  Note these run at Layer 2, where the fetch-width floor is inert — **showing the result is not
  floor-borne is AC-138/AC-139's job, at Layer 3.**
- **AC-103 is the gate's own gate.** The same fixture with weighting disabled must place the target
  *below* rank 1. If AC-103 cannot go red, AC-101 is passing for a reason other than the fix.
- **AC-139 is AC-138's gate, and AC-141 is AC-140's.** An attack only carries information once the
  fixture is shown to be sensitive on the axis being attacked; revision 1.0.0's attack E was a
  no-op by construction (vigil F2), and revision 1.1.0's replacement probed the inert floor
  direction (vigil G-1).
- **AC-140 is the change's thesis test** — floor *removal* at `k < 10`, the issue's literal bar.
  Nothing in revisions 1.0.0 or 1.1.0 could fail on it.
- **AC-142 catches the second population defect**, on the status axis F5's repair did not reach —
  a silent decay of the headline feature as a store accumulates deprecated rows (vigil G-2).
- **AC-134 catches a defect all 31 earlier criteria missed** — a layer-saturating query drawing a
  near-maximal sparse boost from a global denominator (vigil F5).
- **AC-121/122 pin the v1.9.0 protections**: all 32 frozen #36 criteria, plus the F-V1 probe. Per
  vigil A-5, AC-122's frozen text scopes that probe to the **flag-on column at `k` over
  `{1,3,5,10}` — four cells**; revision 1.0.0's summary here said eight, and the frozen file
  governs.
- **AC-124's threshold is the *measured* pre-change baseline**, captured before any code change —
  never a modelled figure from this document (§Evidence Gaps G-1, G-7). AC-133 guards the eval
  gate's second axis, which AC-124 alone left open (vigil A-1).

---

## Test Plan

### Layer 1 — pure unit (no storage, no mocks)

`mcp-server/tests/test_rrf.py`, new classes only; every existing test byte-identical. Covers
AC-104..AC-108, AC-112. Fully deterministic, sub-second. The weight-resolution helper
(AC-109..AC-111) is unit-testable in the same file if kept pure per S-3.

### Layer 2 — real stack, mocked arms

`mcp-server/tests/test_fusion_weighting.py` (new), template `test_recall_starvation.py`: real
`RelationalStore` (so BM25/FTS5 is genuine) + `MagicMock` vector and graph stores (so arm
memberships are exact). Covers AC-101, AC-102, AC-103, AC-113..AC-120, AC-129.

**Fixture requirement, from #36's F-V2:** AC-101's fixture must make the graph and completion arms
**non-empty at the fetch width actually used**. #36's AC-031 fixture returns `[]` once
`len(seed_ids) > 3`, which silently reduces the fusion under test to two arms. An AC-101 fixture
with that shape would be green and meaningless.

### Layer 3 — full stack

The F-V1 four-cell probe (AC-122) on real embedding + graph arms, fresh store per cell — #36's
verification notes an interleaved-store first attempt was invalid. Plus `make test` (AC-123).

### Layer 4 — evals

- `python -m evals retrieval-gate` before and after -> `eval-before.json` / `eval-after.json`
  (AC-124). **Capture before first.**
- `python -m evals fusion-gate` (new, AC-125): a weighted-vs-unweighted A/B on a fixture whose
  target is BM25-rank-1 and dense-rank-4, reporting the target's fused rank in each arm. Both arms
  run against identical corpora — the only variable is the flag (the "honest ablation" discipline
  `retrieval_gate.py:11-14` already states).
- Multi-layer fixture (AC-126): the same query resolvable in `semantic` and `episodic`, so the
  cross-layer axis is *measured* even though DP-5 defers the fix.

### Layer 5 — adversarial (the checker's gate attacks)

Each must turn a named node **red**; a green attack is a finding, per "gates are where defects
hide."

| # | attack | layer | must redden |
|---|---|---|---|
| A | revert D2 (sum graph + completion again) | 2 | AC-101, AC-107 |
| B | force `w_sparse = 1.0` (delete the boost) | 2 | AC-101, AC-109 |
| C | revert D4 (`seed_ids = dense_ranking[:fetch_width]`) | 2 | AC-113 |
| D | revert D5 (unsorted set iteration) | 2 | AC-131 |
| F | make `prelim` include `graph_ranking` (break I-1) | 2 | AC-114 |
| G | ship `recall_weighted_fusion=True, recall_relevance_primary=False` | 2 | AC-120 |
| H | use a global-store denominator for selectivity | 1 | AC-134 |

Those seven rows are AC-130's scope. **Attack E was removed from this table in revision 1.1.0
(vigil F2) because it was a tautology.** `FETCH_WIDTH_FLOOR` reaches the world through exactly one
channel — it sizes `seed_ids` — and the Layer-2 fixture the criteria's Terminology block mandates
uses a graph mock whose return value ignores its `seed_ids` argument. Widening the floor on that
fixture is a no-op *by construction*, so the attack was green whether the fix worked, was absent,
or was entirely floor-borne. It carried zero bits while sitting on the criterion the spec called
its thesis test.

Attack E is now **two pairs** of Layer-3/eval-gate criteria against a real `GraphStore`, where the
floor has a live channel. Revision 1.1.0 shipped only the inflation pair; vigil G-1 showed that
`fetch_width = max(k, FLOOR)` makes floor *lowering* inert at `k >= 10`, and the host gate runs
`k=10` — so the inflation pair alone interrogates the one direction that cannot answer the change's
central claim.

**Inflation pair (revision 1.1.0):**

- **AC-139 (the falsifiability precondition, run first)** — on the build with the fusion fix
  *reverted*, widening the floor to 1000 must **change** the target's fused rank. This is what
  proves the fixture is seed-sensitive at all.
- **AC-138 (the attack)** — on the fixed build, widening the floor to 1000 must leave the target at
  rank 0.

**Removal pair (revision 1.2.0, vigil G-1) — this is the actual thesis test:**

- **AC-141 (the falsifiability precondition, run first)** — on the *reverted* build with
  `FETCH_WIDTH_FLOOR = 1` at `k=1`, the target must **not** be rank 0. This is #36's F-V1 k=1 cell
  reproduced, and it proves the floor's channel is live at small `k` in this fixture.
- **AC-140 (the thesis test)** — on the fixed build with `FETCH_WIDTH_FLOOR = 1`, the target must
  hold rank 0 at `k` in `{1, 3, 5}`. This is the issue's literal bar: "without relying on the
  fetch-width floor."

Either pair without its precondition green is an unfalsifiable PASS, and the criteria say so
explicitly. If a precondition cannot go green, the fixture is insensitive on that axis and the
attack must be **moved, not weakened**.

**Predicted mechanism, and why it is D4 rather than the weighting.** At `fetch_width = 1`, base-arm
fused seeding makes `seed_ids = [target]`: the target carries two base arms (sparse rank 1, dense
rank 4) against each competitor's one, so it leads `prelim` at every `w_sparse` from 1.0 to 2.0
(modelled). `ef42967` instead takes `dense_ranking[:1]` — the top dense *competitor* — and walks
that neighbourhood, which is precisely the #36 F-V1 mechanism. So the component that would let the
floor be removed is **D4, the reseeding**, not the fusion weights. If AC-140 comes back red, that
inference is wrong and the change is layered on the guard; §DP-1 says explicitly that this is
FORGE input, not a defect to patch away.

---

## Release Plan

- **Version: `1.10.0`** (minor). Semver from `mcp-server/pyproject.toml:8` (currently `1.9.0`);
  behaviour changes are additive and flag-gated, no public schema removed. If DP-4 lands (b)
  (default OFF), the version is unchanged — a dormant flag is still a minor feature.
- **Version edit** to `mcp-server/pyproject.toml`. Note `crystalium/__init__.py:_FALLBACK_VERSION`
  is *already* stale at `"1.8.0"` (#36 verification D4, accepted as out-of-scope then); a one-line
  correction is welcome on this touch but is **not** a criterion. Per vigil A-3, revision 1.0.0
  issued that invitation while `mcp-server/src/crystalium/__init__.py` matched **none** of the 12
  declared scope globs — accepting it would have tripped `ramza-drift`. The glob is added in
  revision 1.1.0 (13 globs, re-declared through the tool), so the invitation is now legal.
- **Nexus roster bump is out of scope** (mission constraint) — including the GHCR digest.
- **CHANGELOG `[1.10.0]`** must carry, at minimum: the weighted-fusion mechanism and its defaults;
  the derived-family merge; `score` is now a *weighted* fused value (DP-7); the two determinism
  fixes with the note that graph/completion ordering was previously hash-seed-dependent; the four
  new config fields; and the revert path.
- **Migration notes:** no storage migration, no schema break. Operator-visible: absolute `score`
  values shift on the default path (ordering semantics unchanged); `explain` gains `fusion`;
  `recall_weighted_fusion: false` restores v1.9.0 fusion exactly.
- **Release-gate memory (repo, not this issue):** `mcp` is pinned `>=1.2.0,<2` at `2b5fe7d`;
  assert the resolved version from the build log and probe the published image before any digest is
  recorded downstream.

---

## Risks + Rollback

| # | risk | severity | mitigation |
|---|---|---|---|
| R-1 | The modelled arm memberships are wrong, so the recommended defaults do not behave as tabulated on the real stack | **high — REALISED ONCE ALREADY** | This risk fired during critique: the dense-arm inference inverted §D2's rejection of H-A (vigil F1). Mitigations now: DP-1 orders a real `retrieval-gate` measurement as a **binding pre-deliberation input**; AC-124 + AC-133 guard both eval axes; `eval-before.json` captured pre-change; DP-2 is a constant, retunable without redesign |
| R-2 | Down-weighting nothing still shifts multi-hop rank (the derived-family merge removes one vote) | med | Identity property (§D2) bounds it to `recall_completion=True` — pinned at the function boundary by AC-108 and, per vigil A-9, at the **path** level by AC-135; AC-124 + AC-133 are the tripwires |
| R-3 | DP-3(a)'s per-recall `count()` adds hot-path I/O | low | one indexed aggregate; if it measures badly, DP-3(b) needs no I/O at all |
| R-4 | `score` magnitude change breaks an unknown consumer | low-med | ordering semantics preserved; documented (AC-128); revertible by flag |
| R-5 | Cross-layer blocking (D-1) dominates real-world behaviour, so users see little improvement | med | AC-126 measures it; DP-5 is FORGE's to overrule |
| R-6 | A frozen #36 criterion breaks in a way the suite does not surface | med | AC-121 runs all 32 explicitly; subsumption (D7) keeps AC-008/009's path untouched |
| R-7 | The new gate cannot fail on the defect it names | **high — REALISED THREE TIMES** | Round 1: attack E was a tautology (F2). Round 2: the surviving pair probed the inert floor direction (G-1). Round 3: AC-142's oracle was swallowed by §D3's mandatory clamp (H-1). The first two were the same species and got a *structural* fix — a mandatory falsifiability precondition per attack (AC-139 for AC-138, AC-141 for AC-140), which vigil attacked in round 3 and could not break. H-1 was a different species: a DP-neutrality requirement interacting with a mandated clamp to erase discriminating power. Standing rule for this spec: **an oracle must be shown to differ across the implementations it claims to distinguish, not merely to hold on the correct one** |
| R-8 | The change is layered on the v1.9.0 guard rather than replacing it | **high, currently UNMEASURED** | AC-140/AC-141 are the test; the predicted mechanism (D4 reseeding) is modelled, not measured (G-2 in §Evidence Gaps). A red AC-140 reframes the change and goes to FORGE as DP-1 input |
| R-9 | The sparse boost decays silently as a store ages | med-high | Population agreement is binding (§D3); AC-142 is the oracle; DP-9 decides which population. Invisible without the criterion — no error, no log, no explain anomaly |

**Rollback.** Single lever: `recall_weighted_fusion: false` (or
`CRYSTALIUM_RECALL_WEIGHTED_FUSION=0`) restores v1.9.0 fusion, seeding, and `score` magnitudes.
The determinism fixes (D5) are deliberately **outside** the flag — they are strictly
order-stabilising, and gating a determinism fix behind a flag means the flag-off path stays
irreproducible. Reverting them requires a code revert; that is the correct cost.

---

## Confidence

`ramza-score --rubric confidence` -> recorded in the plan state; verdict honoured, not narrated.
The dimensions carry these justifications:

- **pattern_match** — high. Every mechanism has a template in-repo: flag-gated faculty
  (`config.py:196-225`), pure fusion function + independent unit file (`test_rrf.py`), ablation
  gate + `python -m evals <name>-gate` + `test_<name>_gate.py`, frozen-AC discipline from #36.
- **requirement_clarity** — high. The issue states its own acceptance sketch, and §D2/D3's tables
  convert it into a threshold.
- **decomposition_stability** — good. Three self-consistency decompositions (by pipeline stage, by
  file, by risk class) agree on S-1/S-2/S-4/S-7 as the load-bearing units.
- **constraint_compliance** — moderate, and this is the honest weak axis. Two live tensions: DP-7
  changes a surfaced value whose *provenance* #36 froze (mitigated: `rrf_score_by_id` remains the
  single source of truth), and eight DPs remain open, so the shipped shape is not yet fixed.

---

## Evidence Gaps

Recorded rather than papered over. G-1 is the one that matters.

- **G-1 — every fusion number here is model output, not measurement, and revision 1.0.0's
  robustness claim about it was FALSE.** The figures come from a standalone reimplementation of
  `score = sum(w/(60+rank))` plus *inferred* arm memberships. The sparse-arm inference is strong
  (FTS5 implicit-AND over `retrieval_gate.py`'s literal fixture strings implies only the hub matches
  the 5-token query — vigil verified this independently). The dense-arm inference was **weak and
  wrong**: revision 1.0.0 modelled the two spokes as absent from `dense_ranking`, then asserted the
  directional conclusions were "robust to that correction". They were not. `dense_search` is called
  with `k = candidate_k = 30` against a 31-crystal corpus, so the spokes are probably present near
  the bottom, and once modelled there the entire rejection of static down-weighting inverts (§D2,
  vigil F1; reproduced cell-for-cell before acceptance). One directional conclusion survived
  (family-merge at `w_derived = 1.0` costs nothing) and one did not: the claim that static
  down-weighting collapses multi-hop recall. **Consequences:** AC-124's threshold is the measured baseline, never a number from
  this document; and DP-1/DP-2 carry a binding order to measure the H-A arm on the real stack before
  FORGE rules.
- **G-2 — I did not execute crystalium.** No pytest run, no eval run, no container. Mission
  constraint (read-only). Every RED-first claim is a prediction the implementer must demonstrate.
- **G-3 — reporter usage unknown.** #36 recorded `k` in `{3..15}`; nothing here re-establishes the
  distribution of real queries by selectivity, which is what decides how often the boost fires.
- **G-4 — CLOSED during Test.** `_from_dict` carries an explicit `float_field` allowlist
  (`config.py:375-390`) alongside the `bool_field` one. The three new floats must be added to it
  or YAML configuration is silently ignored; folded into D6 and AC-127.
- **G-5 — CLOSED during Test.** Read directly: top level is `additionalProperties: false`, but the
  `explain` property is intentionally loose. `explain.fusion` needs no schema change; S-6 shrank
  accordingly.
- **G-6 — CLOSED.** vigil delivered the independent critique (`critique.md`, 2026-08-03): verdict
  REVISE, six blocking findings, eleven advisory, refine rubric fail (3.4, testability 2). Revision
  1.1.0 is the response. Disposition per finding is in §Refine record.
- **G-7 — NEW, opened by the refine.** The corrected §D2 table is still a model; it merely moves the
  uncertainty from "which conclusion" to "which dense-rank column". The spokes' actual dense ranks
  are unknown to this spec and are what decide DP-1. Only the measurement ordered in DP-1 closes
  this.

---

## Gate record

| gate | result |
|---|---|
| `ramza-rightsize --files-est 8 --public-api --novel --stakes high` | score 5 -> **full** |
| `ramza-score --rubric complexity` | 10 -> **human_loop** |
| `ramza-score --rubric explore` x5 (rev 1.0.0) | H-B 81.5 solid; H-D 65.5, H-A 61.5, H-E 60.5, H-C 59 |
| `ramza-score --rubric explore` (rev 1.1.0 re-score) | **H-A 61.5 -> 72.5 solid**; gap to H-B 20 -> 9 points |
| phase walk | RS S P E C T R T R T via `ramza-gate`, no skips |
| self-consistency (3 decompositions) | min pairwise Jaccard **0.714** |
| call-site + dependency audit | production `Aetheryte(` = 2 of 10; `Config.__new__` helpers = 5; `float_field` allowlist (G-4); loose `explain` schema (G-5) |
| `ramza-lint --plan spec.md` | **clean** (tier full) |
| `ramza-ears-lint spec.criteria.md` | **clean**, 42 criteria |
| `ramza-drift --declare` | 13 globs (vigil round-2: 0 of 16 required files uncovered) |
| `ramza-freeze` | `132b25df…` -> `7e4c0807…` -> **rev 1.2.0** (see plan state; manifest corrected per B-1) |
| `ramza-verify-emit --spec spec.md` | **pass** (`ECL_VERSION` unset) |
| `ramza-gate critic --author vivi --checker vigil` | recorded round 1 + round 2 |
| `ramza-score --rubric refine` (vigil) | cycle 1 **fail** 3.4 (testability 2) -> cycle 2 **fail** 3.8 (testability 3) |
| `ramza-gate refine` | cycle **2 of hard cap 3** |

---

## FORGE handoff — how to deliberate this docket

Carried from vigil's terminal critique, and binding on the order of business.

1. **Weigh DP-1 first, and do NOT rule it before the real-stack measurement lands.** Every number
   in §D2 is **modelled** until then. The model in revision 1.0.0 was wrong once already and
   inverted the entire rejection of H-A; the corrected model is still a model (§Evidence Gaps G-1,
   G-7). The measurement is running in a scratch clone and FORGE consumes it directly — no
   criterion in the 42 depends on its outcome.
2. **DP-9 is a recorded maker/checker disagreement, deliberately left open.** vigil prescribed
   all-statuses; I recommend active-only; vigil then ruled my argument the stronger one and
   escalated rather than overruling. **Either ruling lands with no further amend** — AC-142 was
   built population-neutral on purpose. If active-only is ruled, the numerator must be made
   active-only too, computed **within `sparse_ranking` for weight purposes only** — never by adding
   a status predicate to the shared `bm25_search`.
3. **DP-4(ii) is a genuine product call, not a technical one.** "The issue's literal acceptance bar
   (AC-140) is red and the flag still ships ON" is a decision the deliberating authority must make
   on the record. I recommend (a) — route a red AC-140 to DP-1 as a finding about the change's
   nature rather than flipping the default — but the spec does not presume it.
4. **R-8 and R-9 are the live risks, and each now has a purpose-built oracle.** R-8 (this change is
   layered on the v1.9.0 guard rather than replacing it) is measured by AC-140 with AC-141 as its
   falsifiability precondition. R-9 (the sparse boost decays silently as a store ages) is measured
   by AC-142, whose two assertions cover all four population pairings between them.

**Standing rule earned by this campaign, for any criterion added downstream:** an oracle must be
shown to *differ* across the implementations it claims to distinguish — not merely to hold on the
correct one. R-7 fired three times here (a tautological attack, an attack probing an inert
direction, and an oracle swallowed by a mandated clamp), and each time the criterion looked fine
until someone computed its value under the defect.

---

## Refine record — cycle 1 (response to `critique.md` round 1)

Every blocking finding was **independently reproduced before acceptance**. Where my reproduction
disagreed with the critic, that is recorded too.

| # | disposition | evidence |
|---|---|---|
| **F1** | **ACCEPTED — reversal.** §D2's rejection of static weights withdrawn; DP-1 re-opened; H-A re-scored 61.5 -> 72.5; G-1's robustness claim struck; DP-1/DP-2 carry a binding real-stack measurement order | Reproduced vigil's four-column table **cell-for-cell** (`1/89 = 0.011236`, `1/67 = 0.014925`, `0.6/61 + 1/89 = 0.021072`, band `[1/90, 1/62]`). 0.1538 holds only on the spokes-absent column |
| **F2** | **ACCEPTED.** Attack E removed from AC-130; replaced by AC-138 + AC-139 | Verified by construction: the floor's only channel is `seed_ids` |
| **F3** | **ACCEPTED, with a recorded reproduction disagreement.** >= 4 UUID-shaped ids, seeds 0..4, observed pair recorded | 3 styles x 4 cardinalities x 10 seeds. vigil measured UUID n=3 identical under seeds 0/1; my strings differed. The disagreement *is* the argument for the >= 4 floor |
| **F4** | **ACCEPTED.** AC-104 -> `(id, score)` multiset; order half split into AC-132 | `[["b"],["a"]]` -> legacy `['b','a']`, weighted `['a','b']`, multiset identical |
| **F5** | **ACCEPTED.** Denominator counted over `target_layers`; AC-134 added | `layers=['procedural']` matching 5 of 5: `w_sparse` 1.9995 global vs 1.0000 scoped |
| **F6** | **ACCEPTED.** Contingency widened to five gates; AC-136 pins it; #36 blast-radius analysis written | Key observation: #36 contains **no** ranked-position criterion |
| A-1..A-11 | all accepted | A-3 verified by `fnmatch` (no match); A-4 10 sites, 8 in tests; A-6 five aggregates + two existing count helpers; A-10 `retrieve.py:374` verbatim |

## Refine record — cycle 2 (response to `critique.md` round 2)

vigil closed F1..F6 by re-measurement and raised two new blocking findings on round-2 surface.
Both were verified at source before acceptance.

| # | disposition | evidence |
|---|---|---|
| **G-1** | **ACCEPTED, and strengthened beyond the prescription.** Added **AC-140** (thesis test: floor = 1, target at rank 0 for `k` in `{1,3,5}`) **and AC-141**, its falsifiability precondition, which the prescription did not call for | Reproduced the floor table: lowering is live at `k` in `{1,3,5}` and **inert at `k` >= 10**; `retrieval_gate.py:117-120` calls recall at `k=10`, so both existing criteria probed the dead direction. **Deviation from the prescription, deliberate:** vigil proposed AC-140 as "a two-line parameterisation of a fixture AC-102 already builds" — but AC-102 is Layer 2, where the seed-independent mock makes floor changes a no-op **by construction**. Landing it there would have repeated the exact F2 tautology in the opposite direction. AC-140 is therefore pinned to Layer 3 / the AC-125 gate, and AC-141 supplies the sensitivity proof |
| **G-2** | **ACCEPTED.** Population agreement is now a **binding invariant** in §D3 (not a preference); **AC-142** added as the population-agreement oracle; AC-109/112/117/134 amended to carry the status axis; new **DP-9** for which population | Verified all four anchors: `bm25_search` has no `status` token in either branch (`relational.py:493-541`); FTS triggers carry every row with no status guard (`:75-88`); `count_active_by_scope_key` is active-only (`:1019`); `_is_active` runs at `:482/:505`, after fusion at `:424`. **Partial deviation:** vigil prescribed all-statuses as "cheaper and more honest"; I recommend **active-only** in DP-9 and recorded the disagreement rather than taking the prescription silently. Reason: under bi-temporal supersession the deprecated rows are lexical near-duplicates of the target itself, so all-statuses lets records the caller never sees dilute the ranking signal (1 fresh + 50 superseded in a 100-active layer: `w_sparse` 1.66 vs 1.99). AC-142 is written to be neutral, so FORGE can rule either way with no further amend |
| B-1 | accepted — the criteria header now carries a three-revision manifest naming all 17 round-1 changed blocks + Terminology, and all 11 round-2 ones | Reconstructed and confirmed vigil's count |
| B-2 | accepted — AC-133 records that `recall_context_match` defaults False, that it guards a **proxy** arm, and that the shipped arm's `ctx_rank` is not exported by `retrieval_gate.run()` at all; AC-136's contingency extended to include it | |
| B-3 | accepted — AC-135 now requires the fixture to **assert** the `prelim[:fetch_width]` / `dense_ranking[:fetch_width]` set-equality rather than depend on it silently; D4 is explicitly not neutralised | |
| B-4 | accepted — AC-104 gains an intra-list-duplicate fixture (`[["a","b","a"]]`); §D1's docstring must state the per-occurrence rule | Confirmed `retrieve.py:82-86` accumulates per occurrence and the docstring blesses it |
| B-5 | accepted — this round's self-gate is labelled `--cycle 2` and scored at the cycle-2 bar (every dimension >= 4) | |
| B-6 | accepted — the parenthetical no longer restates the withdrawn claim in the present tense | |

**Criteria delta:** 39 -> 42. Amended: Terminology, AC-104, 109, 112, 117, 133, 134, 135, 136,
138, 139. Added: AC-140, AC-141, AC-142. Removed: none.

## Refine record — cycle 3 of 3 (response to `critique.md` round 3)

vigil **upheld both round-2 deviations** — withdrawing their own AC-140 prescription after checking
its premise, and ruling the DP-9 active-only argument stronger than their own position — and raised
one blocking finding on my round-2 work.

| # | disposition | evidence |
|---|---|---|
| **H-1** | **ACCEPTED — my own oracle was blind, and it is R-7's third occurrence.** AC-142's THEN is now the population-agreement **invariant** (`n_sparse <= N_scoped`) instead of the weight | Reproduced across every fixture shape the GIVEN admits — N/M = 100/50, 10/5, 5/5, 50/200 — all three implementations return `w_sparse = 1.0`, because under the mixed population `1 - n/N` goes negative and §D3's clamp (mandatory, since AC-112 requires the `[1, 1+alpha]` bound) floors it to 0. My closing sentence "only the mixed implementation gives a non-zero boost" was **false**. The invariant discriminates on the identical fixtures: 150<=150 holds, 100<=100 holds, **150<=100 violated**. Also confirmed vigil's point that no non-saturating fixture could work: at 1 active + 50 deprecated the three give 1.66 / 1.99 / 1.49, so the two *pure* populations disagree and DP-9 neutrality is unattainable there |
| C-1 | accepted — AC-141's escape hatch now reads "cannot go **green**", matching AC-139's convention for the structurally identical role | AC-141's THEN asserts the reverted build puts some *other* id first, so the precondition is satisfied when AC-141 is green |
| C-2 | accepted — AC-140's exclusion from AC-136 is now **DP-4(ii)**, open for FORGE, with (a) recommended; AC-136 records its list as pending that ruling | The spec no longer assumes a call that belongs to the deliberating authority |
| DP-9 brief | both mechanism gaps folded in | (i) active-only needs an active-only *numerator*; cheap route is counting active hits within `sparse_ranking` for weight purposes only — with an explicit warning against a status predicate on the **shared** `bm25_search`. (ii) all-statuses degrades along a second path: `LIMIT candidate_k` has no status filter, so deprecated rows consume fetch slots, can trip the censoring branch, and can crowd active hits out of the candidate set entirely (pre-existing, out of scope, decision-relevant) |

**Wording refinement to the prescription, recorded.** vigil's literal fix was a compound THEN
("…weight of exactly 1.0 **and** …count no greater than…"). One criterion is one assertion, so the
**discriminating** half became the THEN and the non-discriminating weight check is retained in
VERIFY as a companion regression assertion. Same content, same oracle, EARS-atomic.

**Criteria delta:** 42 -> 42. Amended: AC-136, AC-141, AC-142. Added: none. Removed: none.

**Closed.** vigil's terminal delta returned **APPROVE-FOR-ASSEMBLE**, zero blocking findings, with
their independent refine score passing at 4.4 (their ledger: 3.4 -> 3.8 -> 3.8 -> 4.4). Assemble
notes N-1 (the stale `corpus_n` field name) and N-2 (the mislabelled weight assertion) were both
discharged **in** Assemble rather than deferred — see §D8's field-name note and AC-142's
complementarity table. Refine cycles now stand at **3 of the hard cap 3 — the cap is reached.** A further round of
substance cannot be absorbed by another refine pass: `ramza-gate refine` will DENY, and the correct
instrument is escalation with a gap report. vigil recorded the same expectation. DP-1..DP-9 go to FORGE afterwards. Per the
coordinator, the real-stack DP-1 measurement is running in a scratch clone and lands before
deliberation; **no criterion here depends on its outcome** — FORGE consumes it directly.
