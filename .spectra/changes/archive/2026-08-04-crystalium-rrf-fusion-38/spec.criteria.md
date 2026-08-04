# Acceptance criteria — crystalium-rrf-fusion-38 (frozen, amended four times)

Frozen sibling of `spec.md` revision 1.4.0. **Amended four times, legally**, via
`ramza-freeze --amend --reason`. A further change requires another
`ramza-freeze --amend --reason "<why>"` — a silent edit is tamper evidence.

change_id:  crystalium-rrf-fusion-38
target:     Rynaro/crystalium @ ef42967 (v1.9.0) -> 1.10.0
maker:      vivi   checker: vigil
criteria:   42   (#36's AC-001..AC-032 remain in force, re-asserted by AC-121)
supersedes: sha256 b17f209a89442a35f4f508af6becf53563f7158234ce476ae0f0e1e15e353a75

**Change manifest — CORRECTED (vigil round-2 B-1).** Revision 1.1.0's manifest declared seven
amended blocks; seventeen had in fact changed, plus a Terminology deletion. Every one of those
edits was an improvement implementing F5 or an advisory, so this was a manifest defect rather than
tampering — but the manifest is the surface `ramza-freeze` exists to make trustworthy, and a reader
diffing the two frozen versions would have read AC-109's changed GIVEN as an undeclared edit. The
full, accurate history:

| revision | hash | amended | added | removed |
|---|---|---|---|---|
| 1.0.0 | `132b25df…f9d119` | — (31 blocks, initial freeze) | AC-101..AC-131 | — |
| 1.1.0 | `7e4c0807…d64802` | **AC-101, 104, 108, 109, 111, 112, 117, 119, 120, 121, 122, 124, 125, 127, 129, 130, 131 + Terminology** (17 + Terminology; rev 1.1.0's own manifest named only 7 — B-1) | AC-132..AC-139 | none |
| 1.2.0 | `59244291…fe0137` | **Terminology, AC-104, 109, 112, 117, 133, 134, 135, 136, 138, 139** (11 + Terminology) | AC-140, AC-141, AC-142 | none |
| 1.3.0 | `b17f209a…353a75` | **AC-136, AC-141, AC-142** (3) | none | none |
| 1.4.0 | this file (Assemble) | **AC-142 VERIFY guidance only** — N-2 label correction; every normative GIVEN/WHEN/WHILE/WHERE/THEN clause in all 42 blocks is byte-identical to 1.3.0 | none | none |

Round-1 findings F1..F6 and advisories A-1..A-11 are closed (verified by vigil's round-2
re-measurement). Round-2 blocking findings G-1 (guard-vs-cure had no criterion) and G-2 (the
selectivity denominator's status axis) are closed by AC-140/AC-141 and AC-142 respectively. Round-3
blocking finding H-1 — AC-142's oracle was non-discriminating because §D3's mandatory clamp
swallowed the mixed-population signature — is closed by amending AC-142's THEN to the
population-agreement invariant. Round-3 advisories C-1 (AC-141's escape-hatch convention) and C-2
(AC-140's AC-136 exclusion becomes FORGE's DP-4(ii) ruling) are folded in. **No criterion was added
or removed in revision 1.3.0.**

**Terminology.** **Sketch fixture** = the issue's acceptance sketch: a target crystal whose
summary carries three distinctive low-frequency tokens and which is BM25 rank 1; a dense ranking
placing three unrelated competitors at ranks 1-3 and the target at rank 4; graph and completion
arms that are NON-EMPTY at the fetch width actually used and that return those same three
competitors.

**Fixture-shape hazard (vigil F2), binding on every criterion below that names the sketch
fixture.** The Terminology clause above effectively mandates a graph mock whose return value is
independent of its `seed_ids` argument. `FETCH_WIDTH_FLOOR` reaches the world through exactly one
channel — it sizes `seed_ids` — so on such a mock, widening the floor is a **no-op by
construction**. Any criterion whose purpose is to show a result is *not* floor-borne is therefore
worthless at Layer 2 and MUST run at Layer 3 (real `GraphStore`) or on the AC-125 eval gate. See
AC-138/AC-139, which replace revision 1.0.0's tautological attack-E clause.

**Floor-direction hazard (vigil G-1), binding on AC-138..AC-141.** `fetch_width = max(k, FLOOR)`,
so the floor's causal channel is live in only one direction per `k`:

| `k` | floor 1 | floor 10 (shipped) | floor 1000 | does *lowering* the floor matter? |
|---|---|---|---|---|
| 1 | 1 | 10 | 1000 | **yes** |
| 3 | 3 | 10 | 1000 | **yes** |
| 5 | 5 | 10 | 1000 | **yes** |
| 10 | 10 | 10 | 1000 | no — inert |
| 25 | 25 | 25 | 1000 | no — inert |

AC-138/AC-139 raise the floor at a gate that runs `k=10`, so they can only probe floor *inflation*.
The change's thesis — "a cure, not the v1.9.0 guard", and the issue's literal bar "without relying
on the fetch-width floor" — is a claim about floor **removal at `k < 10`**, which is exactly the
regime DP-R1 built the floor for (#36 F-V1's k=1 and k=3 cells). AC-140 tests that direction and
AC-141 is its falsifiability precondition.

### AC-101 (event-driven)
GIVEN the sketch fixture with `recall_relevance_primary` enabled together with the weighted
fusion path active, and a query composed of the target's three distinctive tokens
WHEN  `Aetheryte.recall()` is called with `k=10`
THEN  the system shall return the target crystal's id as `result.records[0].id`
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestIssue38Sketch::test_target_is_fusion_rank_1` — must be demonstrated RED at `ef42967`. Asserts fusion rank 1, not membership; membership is what the v1.9.0 fetch-width floor already provides. Non-floor-borne-ness is AC-138/AC-139's job, not this node's.

### AC-102 (event-driven)
GIVEN the sketch fixture in the default configuration
WHEN  `Aetheryte.recall()` is called once per value of `k` drawn from 1, 3, 5, 10, 25
THEN  the system shall return the target crystal's id as `result.records[0].id` at every one of those values
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestIssue38Sketch::test_rank_1_is_k_independent` parameterised over `k in (1,3,5,10,25)` — the issue's "should win fusion at ANY k".

### AC-103 (unwanted-behavior)
GIVEN the sketch fixture with the weighted fusion path disabled
WHEN  `Aetheryte.recall()` is called with `k=10`
THEN  the system shall return an id other than the target's as `result.records[0].id`
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestIssue38Sketch::test_unweighted_path_ranks_target_below_first` — the gate's own gate. If this node cannot go red, AC-101 is passing for some reason other than the fix.

### AC-104 (ubiquitous)
GIVEN any ranking set in which every arm weight is 1.0
WHEN  `weighted_rrf_merge_scored` is called on it
THEN  the system shall produce the same `(id, score)` multiset that `rrf_merge_scored` produces for the same input
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestWeightedRrf::test_unit_weights_match_legacy_scores` over the existing `test_rrf.py` fixture corpus, **plus the discordant fixture `[["b"], ["a"]]`, plus an intra-list-duplicate fixture such as `[["a", "b", "a"]]`**. The duplicate fixture is required by vigil B-4: `rrf_merge_scored` accumulates one term *per occurrence* (`retrieve.py:82-86`, and its docstring blesses the case — "Duplicates within a single list are allowed but unusual"), so `weighted_rrf_merge_scored` must do the same or this criterion is green only because the shipped corpus happens to contain no intra-list duplicate. §D1's docstring must state the per-occurrence rule explicitly. **AMENDED (vigil F4/A-11):** revision 1.0.0 asserted "the same id sequence", which contradicts AC-105's deliberate id-ascending tie-break. Measured counterexample: `[["b"],["a"]]` -> legacy `['b','a']` (insertion order), weighted-at-1.0 `['a','b']` (id ascending) — while the score multiset is identical. Revision 1.0.0 was green only because every tie in the shipped corpus happens to be insertion-order-concordant. The unverifiable "at most one derived arm present" clause is also dropped: the function takes `list[tuple[list[str], float]]` and has no notion of a derived arm.

### AC-105 (ubiquitous)
GIVEN two candidates whose weighted fusion scores are exactly equal
WHEN  `weighted_rrf_merge_scored` orders them
THEN  the system shall place the lexicographically smaller id first
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestWeightedRrf::test_exact_tie_breaks_by_id_ascending` with the arms supplied in both possible orders — an insertion-order tie-break is not stable under P3.

### AC-106 (state-driven)
WHILE `mcp-server/tests/test_rrf.py`'s pre-existing test classes remain byte-identical to their state at `ef42967`
WHEN  the test file is executed against the fixed build
THEN  the system shall report zero failures among those pre-existing tests
VERIFY: `pytest mcp-server/tests/test_rrf.py -k "TestRrfMerge"` plus `git diff ef42967 -- mcp-server/tests/test_rrf.py` showing additions only — pins that `rrf_merge`/`rrf_merge_scored` were not modified.

### AC-107 (event-driven)
GIVEN a candidate that appears in both the graph ranking and the completion ranking
WHEN  the derived-family merge produces `derived_ranking`
THEN  the system shall include that candidate exactly once in `derived_ranking`
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestDerivedFamily::test_candidate_in_both_arms_appears_once` asserting the emitted position equals the candidate's minimum rank across the two arms.

### AC-108 (optional-feature)
WHERE the completion ranking supplied to the merge is empty, leaving exactly one derived arm
WHEN  `weighted_rrf_merge_scored` runs with every weight at 1.0
THEN  the system shall produce scores equal to the unweighted three-arm fusion to within 1e-15
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestDerivedFamily::test_single_derived_arm_is_identity` — the identity property recorded in `spec.md` §D2. **AMENDED (vigil A-9):** revision 1.0.0's WHERE named `Config.recall_completion`, which is inoperative at a pure-function boundary — the function has no Config access. The Config-level counterpart is now AC-135.

### AC-109 (event-driven)
GIVEN a store in which the query's BM25 conjunction matches a number of crystals far below both the fetch cap and the count of crystals in the searched layers, counted over the same status population as the numerator (AC-142)
WHEN  the sparse arm weight is resolved for that recall
THEN  the system shall report a sparse arm weight strictly greater than 1.0
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestSparseWeight::test_selective_query_boosts_sparse_arm` on the pure weight helper, plus `result.explain["fusion"]["w_sparse"]` on the real stack.

### AC-110 (event-driven)
GIVEN a query whose sparse ranking length reaches the fetch cap
WHEN  the sparse arm weight is resolved for that recall
THEN  the system shall report a sparse arm weight of exactly 1.0
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestSparseWeight::test_censored_sparse_arm_is_neutral` — a censored count cannot evidence selectivity.

### AC-111 (unwanted-behavior)
GIVEN a query for which the sparse arm returns no candidates
WHEN  the sparse arm weight is resolved for that recall
THEN  the system shall complete the resolution without raising
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestSparseWeight::test_empty_sparse_arm_does_not_raise` parameterised over searched-layer sizes 0 and 1 — guards the zero-division and negative-selectivity edges.

### AC-112 (ubiquitous)
GIVEN any combination of sparse-arm length, fetch cap, searched-layer crystal count (over the AC-142 population) and configured alpha
WHEN  the sparse arm weight is resolved
THEN  the system shall report a value within the closed interval from 1.0 to 1.0 plus the configured alpha
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestSparseWeight::test_weight_is_bounded` over a parameterised grid including degenerate inputs. Note this criterion is a bound, not a correctness oracle — vigil F5 demonstrated an inverted weight sitting comfortably inside it; AC-134 is the oracle that catches that.

### AC-113 (event-driven)
GIVEN a record present in the sparse ranking but positioned outside the dense ranking's first `fetch_width` entries
WHEN  the graph expansion seed set is assembled
THEN  the system shall include that record's id in the seed set
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestSeeding::test_sparse_only_record_becomes_a_seed` asserting against the ids passed to the mocked `neighbor_expand` — issue item 2.

### AC-114 (unwanted-behavior)
GIVEN a recall in which the graph ranking is non-empty
WHEN  the preliminary fused order used for seeding is computed
THEN  the system shall exclude every ranking other than the sparse ranking together with the dense ranking
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestSeeding::test_prelim_reads_base_arms_only` — invariant I-1; a derived arm feeding its own seeds is a feedback loop.

### AC-115 (ubiquitous)
GIVEN any recall in the default configuration
WHEN  the graph expansion seed set is assembled
THEN  the system shall pass no more than `fetch_width` seed ids to the expansion
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestSeeding::test_seed_count_bounded_by_fetch_width` parameterised over `k in (1,3,10,50)` — pins that D4 changed seed *composition*, never seed *count*.

### AC-116 (ubiquitous)
GIVEN any non-empty recall result on the weighted path
WHEN  the caller reads a returned `CrystalSummary`
THEN  the system shall expose a `score` equal to that record's weighted fused value
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestScoreSemantics::test_score_is_the_weighted_fusion_value` comparing against the pure function recomputed on the same arms — keeps `rrf_score_by_id` the single source of truth (#36 seam 1).

### AC-117 (event-driven)
GIVEN a caller passing `explain=true` on the weighted path
WHEN  `Aetheryte.recall()` returns
THEN  the system shall include a `fusion` object in `result.explain` carrying the three arm weights together with the selectivity inputs that produced them
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestExplain::test_explain_carries_fusion_object` asserting key presence plus consistency with the surfaced scores. The object must name the searched-layer crystal count actually used as the selectivity denominator **together with the status population that count was drawn from** (AC-134's and AC-142's diagnostic surface) — vigil G-2: revision 1.1.0 surfaced the denominator's value but nothing asserted its population, which is how the status-axis defect stayed invisible.

### AC-118 (event-driven)
GIVEN a default-configuration fixture routed to one slot whose cap forces at least one eviction
WHEN  `Aetheryte.recall()` returns the surviving records on the weighted path
THEN  the system shall emit them in non-increasing `score` order
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestOrdering::test_weighted_scores_emit_descending` — re-asserts #36 AC-007's contract under weighted scores; the eviction-forcing fixture is mandatory (#36 F-V2).

### AC-119 (optional-feature)
WHERE `Config.recall_weighted_fusion` is set to `False`
WHEN  `Aetheryte.recall()` runs against the sketch fixture whose mocked arms are id-ascending with pairwise-distinct completion scores
THEN  the system shall reproduce the fused id order that `ef42967` produces for the same arms
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestFlagOff::test_weighted_off_reproduces_v190_fusion` against an order captured from `ef42967` under those same fixture conditions. **AMENDED (vigil A-2):** revision 1.0.0's reference was "an order captured from `ef42967`", which for any set-derived graph arm is exactly the hash-seed-dependent artifact P3 exists to disprove — an oracle that cannot exist. The id-ascending/distinct-scores precondition makes the captured order well-defined under both `ef42967`'s unsorted iteration and D5's `sorted()`, which is required because §Rollback deliberately places D5 OUTSIDE the flag.

### AC-120 (optional-feature)
WHERE `Config.recall_relevance_primary` is set to `False` while `Config.recall_weighted_fusion` is left `True`
WHEN  `Aetheryte.recall()` runs against the sketch fixture
THEN  the system shall produce the unweighted fused order
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestFlagOff::test_relevance_primary_off_subsumes_weighting` — pins D7's subsumption so the half-gated mode #36 DP-R4(iii) closed cannot reappear as an emergent property. Note (vigil A-10) that this path also narrows `fetch_width` to bare `k`, since the shipped line is `max(k, FETCH_WIDTH_FLOOR) if self.recall_relevance_primary else k`; the fixture must therefore hold both differences fixed, not one.

### AC-121 (state-driven)
WHILE the 32 frozen criteria of change `crystalium-recall-starvation-36` are evaluated against the fixed build
WHEN  their VERIFY batch completes
THEN  the system shall report zero failures across all 32
VERIFY: `pytest mcp-server/tests/test_recall_starvation.py -v` exiting 0 with the test count asserted at 32, **plus `pytest mcp-server/tests/test_composer.py::TestTotalCap` (required by #36 AC-019) and `pytest mcp-server/tests/test_diagnosability.py::TestSummaryQualityGate` (required by #36 AC-023)**. **AMENDED (vigil A-7):** revision 1.0.0 named one file for a 32-criteria claim, so its own VERIFY could not discharge its own THEN.

### AC-122 (state-driven)
WHILE the F-V1 four-cell probe runs on the real embedding stack with a fresh store per cell
WHEN  the flag-on column completes for every `k` drawn from 1, 3, 5, 10
THEN  the system shall return the freshly committed crystal in every one of those four cells
VERIFY: the probe script recorded in `verification.md`, re-run per #36 DP-R4(ii); interleaving cells in one store is invalid (#36 verification, F-V1 note). This criterion scopes the probe to the flag-on column (four cells); `spec.md` revision 1.1.0 §Acceptance Criteria was corrected to match (vigil A-5).

### AC-123 (state-driven)
WHILE the full pytest suite runs against the fixed build
WHEN  the suite completes
THEN  the system shall report zero failures
VERIFY: `make test` (`docker compose run --rm crystalium pytest mcp-server/tests/ -v`) exits 0.

### AC-124 (event-driven)
GIVEN `eval-before.json` captured from `python -m evals retrieval-gate` before any code change
WHEN  the same gate is re-run against the fixed build
THEN  the system shall report a `multihop_f1.completion` value no lower than the recorded baseline
VERIFY: `python -m evals retrieval-gate` diffed against `eval-before.json`; `completion_pass` must also remain `true`. The threshold is the measured baseline, never any modelled number in `spec.md` (evidence gap G-1). **AMENDED (vigil A-1):** this criterion is now explicitly scoped to the multi-hop axis only; the gate's second axis is guarded separately by AC-133, because `gate_pass = (completion_ok and graph_ok) or context_ok` cannot surface a context-axis degradation on its own.

### AC-125 (event-driven)
GIVEN the new fusion eval gate running a weighted arm together with an unweighted arm over identical corpora
WHEN  `python -m evals fusion-gate` completes
THEN  the system shall report the target at fused rank 0 in the weighted arm while reporting it at a rank greater than 0 in the unweighted arm
VERIFY: `python -m evals fusion-gate` with `gate_pass` true, plus `pytest mcp-server/tests/test_fusion_gate.py` — an A/B whose only variable is the flag, per the honest-ablation discipline in `evals/retrieval_gate.py`. The gate uses a real `GraphStore`, which is what makes it a legal host for AC-138/AC-139.

### AC-126 (event-driven)
GIVEN an eval fixture committing query-matching crystals to more than one layer
WHEN  the fusion gate runs against it
THEN  the system shall report the target crystal's rank within the sparse arm for each layer
VERIFY: `python -m evals fusion-gate` emitting a `cross_layer` axis — the evidence DP-5 defers its decision to; the shipped `retrieval_gate.py` commits every crystal to `episodic`, so no existing gate can observe this axis.

### AC-127 (ubiquitous)
GIVEN each of the four new fusion configuration fields
WHEN  a value for it is supplied through its documented source
THEN  the system shall resolve that value onto the `Config` instance
VERIFY: `pytest mcp-server/tests/test_config.py::TestFusionConfig` parameterised over the four fields crossed with both `crystalium.yaml` and the `CRYSTALIUM_*` environment variable — the YAML half is the one that silently fails when `_from_dict`'s `bool_field`/`float_field` allowlists are not extended.

### AC-128 (ubiquitous)
GIVEN the `crystalium.recall` tool manifest
WHEN  a client reads the `score` field's description
THEN  the system shall state that the value is a weighted fusion score
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestDX::test_manifest_describes_weighted_score` asserting the description no longer reads `raw hybrid-retrieval RRF value` unqualified, plus a matching CHANGELOG entry for 1.10.0.

### AC-129 (ubiquitous)
GIVEN a live `RecallResult` produced with `explain=true` on the weighted path
WHEN  its `model_dump` is validated against `schemas/recall-result.v1.json`
THEN  the system shall produce a document that satisfies the published schema
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestSchemaRoundTrip::test_explain_with_fusion_validates` importing `jsonschema` unconditionally — the top level declares `additionalProperties: false` (the trap #36 hit) while `explain` is deliberately loose, so this must pass with no schema edit.

### AC-130 (state-driven)
WHILE the checker executes attacks A, B, C, D, F and G of `spec.md` §Test Plan Layer 5
WHEN  each attack is applied to the fixed build in turn
THEN  the system shall turn every one of those six attacks' named criteria red
VERIFY: `verification.md` recording per-attack observed status against the expected column; a green attack on any of the six is a finding, per "a gate that cannot fail on the defect it names is not a gate". **AMENDED (vigil F2):** revision 1.0.0 folded attack E into this criterion with the expected outcome "nothing changes", which is unfalsifiable on the Layer-2 mock the Terminology block mandates. Attack E is now AC-138 with its own falsifiability precondition, AC-139.

### AC-131 (state-driven)
WHILE the same recall is executed in separate processes started with different `PYTHONHASHSEED` values, over a derived-arm fixture holding at least four distinct ids of the crystal UUID shape
WHEN  every process completes against identical store contents
THEN  the system shall produce byte-identical fused id orders across all of them
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestDeterminism::test_fused_order_is_hash_seed_independent` spawning subprocesses over `PYTHONHASHSEED` values 0 through 4. **AMENDED (vigil F3):** revision 1.0.0 pinned seeds 0 and 1 over a three-id arm and left the id shape unstated, so its mandatory RED-first demonstration was decided by fixture strings rather than by the defect. Measured (CPython set-iteration order, ten seeds): at n=2 the plain-`n1,n2` style gives seed0 == seed1; at n=3 vigil measured UUID-shaped ids identical under seeds 0 and 1, and my own re-measurement with different UUID strings found them differing — the disagreement is itself the evidence that small-n discrimination is string-specific. At n>=4 all three id styles differ under seeds 0 and 1 and yield 8-10 distinct orders over ten seeds. The implementer MUST record, in `verification.md`, the fixture's literal ids together with the observed disagreeing seed pair from 0..4 that establishes RED at `ef42967`.

### AC-132 (ubiquitous)
GIVEN any ranking set with every arm weight at 1.0 in which no two candidates hold exactly equal fused scores
WHEN  `weighted_rrf_merge_scored` is called on it
THEN  the system shall produce the same id sequence that `rrf_merge_scored` produces for the same input
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestWeightedRrf::test_unit_weights_match_legacy_order_when_tie_free` with a tie-freeness assertion in the fixture builder — **NEW (vigil F4)**; carries the order half of revision 1.0.0's AC-104, correctly restricted to the domain where the two tie-break rules cannot diverge.

### AC-133 (event-driven)
GIVEN `eval-before.json` captured from `python -m evals retrieval-gate` before any code change
WHEN  the same gate is re-run against the fixed build
THEN  the system shall report a `context_rank.context` value no worse than the recorded baseline
VERIFY: `python -m evals retrieval-gate` diffed against `eval-before.json` on the context axis — **NEW (vigil A-1)**. **Proxy note (vigil B-2):** `recall_context_match` defaults **False** (`config.py:202`, "stays OFF — no rank lift in the discriminating gate"), so the shipped arm is `comp`, and `retrieval_gate.run()` exports `context_rank` for the `flat`/`context`/`both` arms only — the shipped arm's `ctx_rank` is not an exported metric at all. This criterion therefore guards a **proxy** arm, which is legitimate because the fusion weight is arm-independent (the same `w_sparse` is resolved whatever `recall_context_match` is set to), but it must not be read as a guard on shipped behaviour. The exposure is concrete: `w_sparse` near 1.97 roughly doubles the hub's sparse term while `ctx_match` ("acme login session token guide") does not satisfy the conjunctive query at all and gains nothing, so the context axis can degrade while `gate_pass` stays true. A `None` baseline (the crystal absent from the result) is treated as the worst value.

### AC-134 (unwanted-behavior)
GIVEN a layer-filtered recall whose BM25 conjunction matches every crystal in the searched layer
WHEN  the sparse arm weight is resolved for that recall
THEN  the system shall report a sparse arm weight of exactly 1.0
VERIFY: `pytest mcp-server/tests/test_rrf.py::TestSparseWeight::test_layer_saturating_query_gets_no_boost` plus a real-stack `layers=['procedural']` case asserting `result.explain["fusion"]["w_sparse"] == 1.0` — **NEW (vigil F5)**. Must be demonstrated RED against a global-`N` denominator: with 5 procedural crystals all matched inside a 10 005-crystal store, the global reading resolves `w_sparse = 1.9995` — a near-maximal boost for a maximally non-selective query — and every criterion of revision 1.0.0 survived it, AC-112 included. This is the criterion that forces the denominator to be counted over `target_layers`, consistent with how `cap` already multiplies through `len(target_layers)`. It closes the **layer** axis only; the **status** axis is AC-142, and the two together are the full statement of "numerator and denominator must be drawn from the same population".

### AC-135 (optional-feature)
WHERE `Config.recall_completion` is set to `False` with `fusion_sparse_boost_alpha` set to 0.0 and every arm weight left at 1.0
WHEN  `Aetheryte.recall()` runs against the sketch fixture
THEN  the system shall reproduce the fused id order that `ef42967` produces for the same arms
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestIdentity::test_path_level_identity_with_completion_off` — **NEW (vigil A-9)**. **Reseeding precondition (vigil B-3), which the fixture MUST assert rather than assume:** neutralising `alpha` and the arm weights does not neutralise **D4**, which lives inside the same flag — with every weight at 1.0, `prelim = fuse(sparse, dense)` is still not `dense_ranking`, so `seed_ids` genuinely differs from `ef42967`'s. The identity holds only because the sketch fixture's `prelim[:fetch_width]` is **set-equal** to `dense_ranking[:fetch_width]` (the order differs, the membership does not, so expansion returns the same neighbours). The fixture must assert that set-equality explicitly; without it this criterion inherits exactly the fixture-dependence F2 and F3 were repaired for, and it is scoped to fixtures where that precondition holds. §D2's identity property and R-2's mitigation ("bounds it to `recall_completion=True`") are claims about the shipped *path*, which also carries D3's boost, D4's reseeding and D5's re-ordering; AC-108 pins only the pure function. Neutralising alpha isolates the derived-family merge, which is what R-2 actually asserts. The AC-119 fixture preconditions (id-ascending arms, distinct completion scores) apply here too.

### AC-136 (state-driven)
WHILE any of AC-121, AC-122, AC-123, AC-124, AC-125 or AC-133 is red on the implementation branch
WHEN  the shipped default of `Config.recall_weighted_fusion` is decided
THEN  the system shall ship that flag defaulting to `False`
VERIFY: the release checklist in `verification.md` records the verdict of all six named criteria beside the shipped default; a `True` default alongside any red verdict blocks the tag and returns the change to FORGE — **NEW (vigil F6)**. Revision 1.0.0's contingency bound only AC-124/125, leaving a red non-regression gate (a strictly more serious signal) with no mechanical rule, which is how a gate declared "mechanical, never discretionary" becomes discretionary. Revision 1.2.0 adds **AC-133** (vigil B-2): it was introduced for precisely the silent-degradation reason that motivates the contingency, so leaving it outside the list reproduced the F6 defect one criterion over. AC-140 is **not** in the list **pending FORGE's explicit ruling on DP-4(ii)** (vigil C-2). Revision 1.2.0 excluded it on the spec's own reasoning; "the issue's literal acceptance bar is red and the flag still ships ON" is a call the deliberating authority must make on the record, not one a spec may assume. Until DP-4(ii) is ruled, this criterion's list is the five of revision 1.1.0 plus AC-133.

### AC-137 (event-driven)
GIVEN `evals/BENCH-NOTES.md`'s recorded `context_rank` figure that #36's F-V6 found non-reproducible
WHEN  this change lands
THEN  the system shall carry that figure either corrected or annotated as run-varying
VERIFY: `git diff` on `evals/BENCH-NOTES.md` showing the F-V6 figure changed or annotated, with the annotation naming P3 as the mechanism — **NEW (vigil A-8)**. P3 supplies the explanation F-V6 lacked, so this change is the one that can retire the artifact rather than leave a known-wrong committed number standing.

### AC-138 (unwanted-behavior)
GIVEN the Layer-3 real-`GraphStore` fixture of AC-125 with the fusion fix present
WHEN  `FETCH_WIDTH_FLOOR` is raised to 1000
THEN  the system shall leave the target crystal at fused rank 0
VERIFY: `python -m evals fusion-gate` with the fetch-width floor overridden to 1000, target rank unchanged at 0 — **NEW (vigil F2)**, replacing revision 1.0.0's attack-E clause inside AC-130. This node is only meaningful once AC-139 has established that the floor has a live channel in this fixture; recording a PASS here without AC-139 green is recording an unfalsifiable result. **Scope (vigil G-1):** this pair probes floor *inflation* only. Because the host gate runs `k=10` and `fetch_width = max(k, FLOOR)`, *lowering* the floor is inert here; the guard-vs-cure question is AC-140/AC-141's.

### AC-139 (event-driven)
GIVEN the same Layer-3 real-`GraphStore` fixture with the fusion fix reverted to `ef42967` behaviour
WHEN  `FETCH_WIDTH_FLOOR` is raised to 1000
THEN  the system shall change the target crystal's fused rank relative to the same fixture at the shipped floor of 10
VERIFY: `python -m evals fusion-gate` run twice on the reverted build, floor 10 versus floor 1000, with the two target ranks recorded and asserted different — **NEW (vigil F2)**. Probes floor inflation only; see AC-138's scope note and AC-140/AC-141 for the removal direction (vigil G-1). This is the falsifiability precondition for AC-138: it proves the floor actually reaches the result in this fixture, so AC-138's "nothing changes" carries information instead of being a no-op by construction. If AC-139 cannot go green, the fixture is seed-insensitive and AC-138 must be moved, not weakened.

### AC-140 (event-driven)
GIVEN the Layer-3 real-`GraphStore` fixture of AC-141 with the fusion fix present and `FETCH_WIDTH_FLOOR` set to 1
WHEN  `Aetheryte.recall()` is called once per value of `k` drawn from 1, 3, 5
THEN  the system shall return the target crystal's id as `result.records[0].id` at every one of those values
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestGuardVsCure::test_target_survives_floor_removal_at_small_k` parameterised over `k in (1,3,5)` with the floor monkeypatched to 1 — **NEW (vigil G-1)**. This is the change's thesis test and the issue's literal acceptance bar ("without relying on the fetch-width floor"). It MUST run at Layer 3 or on the AC-125 eval gate with a real `GraphStore`: on the Layer-2 seed-independent mock the Terminology block mandates, lowering the floor is a no-op by construction and this criterion would repeat the F2 tautology in the opposite direction. Its expected mechanism is **D4, not the weighting**: at `fetch_width = 1`, base-arm fused seeding makes `seed_ids = [target]` (the target holds two base arms against each competitor's one, so it leads `prelim` at every `w_sparse` from 1.0 to 2.0 — modelled), whereas `ef42967`'s `dense_ranking[:1]` seeds the top dense *competitor* and walks its neighbourhood instead. **A red AC-140 is not a defect to be patched away** — it is the finding that this change is layered on the v1.9.0 guard rather than replacing it, and it goes to FORGE as DP-1 input. Whether it *also* flips the shipped default is **DP-4(ii)**, open for FORGE (vigil C-2); this criterion does not presume the answer.

### AC-141 (event-driven)
GIVEN the same Layer-3 real-`GraphStore` fixture with the fusion fix reverted to `ef42967` behaviour and `FETCH_WIDTH_FLOOR` set to 1
WHEN  `Aetheryte.recall()` is called with `k` set to 1
THEN  the system shall return an id other than the target's as `result.records[0].id`
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestGuardVsCure::test_reverted_build_needs_the_floor_at_k1` — **NEW (vigil G-1)**; the falsifiability precondition for AC-140, standing to it exactly as AC-139 stands to AC-138. It proves the floor's channel is live in this fixture at small `k`, so that AC-140's green carries information rather than being a no-op. This is #36's F-V1 k=1 cell reproduced: at `323229f`, before seam 3b, the fresh crystal was not returned at `k` of 1 or 3. If AC-141 cannot go **green**, the fixture is not floor-sensitive and AC-140 must be **moved, not weakened** — note the convention, harmonised with AC-139 in revision 1.3.0 (vigil C-1): AC-141's own THEN asserts that the *reverted* build puts some other id first, so the precondition is satisfied when **AC-141 itself is green**, exactly as for AC-139.

### AC-142 (event-driven)
GIVEN a searched layer holding some active crystals together with some deprecated ones, where the query's BM25 conjunction matches every crystal in that layer regardless of status
WHEN  the sparse arm weight is resolved for that recall
THEN  the system shall report a sparse-arm count no greater than the searched-layer count that produced it
VERIFY: `pytest mcp-server/tests/test_fusion_weighting.py::TestSparseWeight::test_mixed_status_population_agrees` on a store seeded with N active plus M deprecated matching crystals, asserting **both** `explain["fusion"]["n_sparse"] <= explain["fusion"]["n_scoped"]` **and** `w_sparse == 1.0`, in that test. The two assertions are **complementary, not oracle-plus-redundancy** — each catches a mismatch direction the other cannot (see the complementarity table below). **AMENDED in revision 1.3.0 (vigil H-1)** — see the discriminating-power table below. Must be demonstrated RED against a mixed-population implementation. The defect it catches: `bm25_search` applies **no status predicate** (`relational.py:493-541`) over an FTS index whose triggers carry every row including deprecated ones (`relational.py:75-88`), so `n_sparse` counts inactive crystals; `recall_active_only` (default `True`, `config.py:225`) removes them only at `retrieve.py:482-505`, long after the weight is resolved; while the natural denominator is active-only (the existing helper is literally `count_active_by_scope_key`). Numerator and denominator then come from different populations, the ratio inflates, and `w_sparse` decays monotonically toward 1.0 as deprecated rows accumulate — which under P0-5 ("write-new, never hard-delete") they do **by design**. The headline feature would die silently in exactly the long-lived stores it exists for, with no error, no log line and no explain anomaly, and every fixture among AC-101..AC-139 is a fresh store. **Why the THEN asserts the invariant rather than the weight (vigil H-1, R-7's third occurrence).**
Revision 1.2.0 asserted `w_sparse == 1.0` and closed with "only the mixed implementation gives a
non-zero boost". That sentence was **false**, and the criterion could not fail on the defect it
names. The fixture is deliberately *saturating* so that both pure populations yield zero boost and
the criterion stays DP-9-neutral — but under the mixed implementation the numerator exceeds the
denominator, `1 - n/N` goes **negative**, and §D3's clamp (mandatory, because AC-112 requires the
`[1, 1+alpha]` bound) floors it to 0, returning the identical `w_sparse = 1.0`. Reproduced across
every fixture shape the GIVEN admits:

| N active | M deprecated | all-statuses | active-only | mixed | weight discriminates? |
|---|---|---|---|---|---|
| 100 | 50 | 1.0 | 1.0 | 1.0 | **no** |
| 10 | 5 | 1.0 | 1.0 | 1.0 | **no** |
| 5 | 5 | 1.0 | 1.0 | 1.0 | **no** |
| 50 | 200 | 1.0 | 1.0 | 1.0 | **no** |

The population-agreement **invariant** does discriminate, on the same fixtures, while staying
DP-9-neutral:

| implementation | `n_sparse` (at N=100, M=50) | `N_scoped` | `n_sparse <= N_scoped` |
|---|---|---|---|
| all-statuses | 150 | 150 | holds |
| active-only | 100 | 100 | holds |
| **mixed** | **150** | **100** | **VIOLATED** |

Both pure populations satisfy it by construction at a saturating fixture; the mixed one cannot.
Observability already exists — AC-117 requires `explain.fusion` to surface the denominator's value
**together with the status population it was drawn from**, so the same test that reads `w_sparse`
can read both counts.

**Complementarity of the two assertions — CORRECTED at Assemble (vigil N-2).** Revision 1.3.0
labelled the weight check "a companion non-discriminating regression check". That label was wrong
and understated the criterion. Enumerating every population pairing at the saturating fixture
(N = 100 active, M = 50 deprecated):

| implementation | `n_sparse` | `n_scoped` | invariant `n <= N` | `w_sparse` | caught by |
|---|---|---|---|---|---|
| all-statuses (num all, den all) | 150 | 150 | holds | 1.0000 | neither — correct |
| active-only (num active, den active) | 100 | 100 | holds | 1.0000 | neither — correct |
| **mixed** (num all, den active) | 150 | 100 | **VIOLATED** | 1.0000 | **invariant only** |
| **reverse** (num active, den all) | 100 | 150 | holds | **1.3333** | **weight only** |

The reverse mismatch — an active-only numerator against an all-statuses denominator, the exact
error an implementer makes by filtering one end of DP-9's ruling and forgetting the other —
**satisfies the invariant** and is caught *only* by the weight assertion. Neither assertion alone
covers both directions; together they cover all four pairings. Both are therefore load-bearing and
must be transcribed as such into `verification.md`.

*Wording note.* vigil's literal prescription was a single compound assertion ("…weight of exactly
1.0 **and** …count no greater than…"). One criterion is one assertion, so the invariant became the
normative clause and the weight assertion is carried in VERIFY — a grammar split, **not** a
demotion in importance.

Non-saturating fixtures cannot be used here: at 1 active + M deprecated matched in a 100-active
layer the three implementations give 1.66 / 1.99 / 1.49 (M=50), so the two *pure* populations
disagree with each other and no value assertion could stay DP-9-neutral. That is the trap revision
1.2.0 walked into, and it is a real one.
