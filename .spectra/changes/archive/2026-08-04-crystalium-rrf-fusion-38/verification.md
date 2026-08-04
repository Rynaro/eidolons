# Verification — crystalium-rrf-fusion-38

## Fresh-context attestation

| Field | Value |
|---|---|
| checker | `vigil` (fresh context; authored none of spec/critique/deliberation/impl/red-evidence) |
| maker | `vivi` |
| date | 2026-08-03 |
| target | `/tmp/claude-1000/.../scratchpad/crystalium-impl` (worktree under verification) |
| branch | `fix/rrf-fusion-38` |
| HEAD verified | `414d45c35cab867b28ba17a99bcc91ce0377d3da` |
| baseline | `ef42967dc7930bf174d0b14436241927da773444` (v1.9.0) |
| criteria integrity | `sha256sum spec.criteria.md` = `e644052e868db47b49c7daedba904e9f53b67d401c81bde0b5e2887ffcb2fded` — **matches the frozen hash** (C-15); no criterion text edited |
| **verdict** | **FAIL — one frozen criterion (AC-130) is RED** |

The FAIL is narrow and is **not** a defect in the shipped implementation. Every
behavioural criterion is discharged, AC-136's contingency six are all green, and the
shipped default is legal. What is red is AC-130's own subject matter: one of the six
mandated gate attacks **cannot redden the criterion it names**, so the change ships a gate
that cannot fail on the defect it guards. Remedy is a test-only change inside an already
declared glob (`mcp-server/tests/*`); no `src/` edit is implied. See F-V1 and §Verdict.

### What I re-ran myself (nothing below is taken from the maker's transcript)

- Freeze-hash, HEAD, clean-tree preflight; full `ef42967..HEAD` hunk audit against the 13
  declared globs and the C-1 scope fence.
- The full pytest suite on the final HEAD, start to finish, in the worktree.
- The eight gate mutations of §Test Plan Layer 5 (A, B, C, D, F, G + H and the AC-142
  mixed-population defect), each in an **isolated throwaway clone**, observing the named
  node's status and restoring the clone after each.
- **AC-122's four-cell probe** on the real embedding stack, fresh store per cell, both flag
  states, ×2 runs — the #36 non-regression the maker argued rather than measured.
- `python -m evals retrieval-gate` ×3 on the clean baseline and ×3 on the branch (C-5).
- `python -m evals fusion-gate` ×5 (C-2), the floor probe at 10 vs 1000 on both builds ×3
  seeds, and `TestGuardVsCure` ×5 seeds.
- Two purpose-built forensic probes that are **not** in the maker's evidence: an
  arm-order/fused-order diagnostic across `PYTHONHASHSEED` 0..19, and a `seed_ids`
  interception on the fusion gate that establishes the *actual* root cause of the
  AC-138/AC-139 indeterminacy.
- Independent `crystalium.yaml` and env round-trips for all four config fields.

---

## Step 1 — Preflight and scope audit

Freeze hash matches. `HEAD = 414d45c…3da`, branch `fix/rrf-fusion-38`, two commits on
`ef42967`, `git status --porcelain` empty at entry. Baseline checkout clean at `ef42967`
at entry **and at exit**.

19 files changed, +2273/−43. Every path maps into the 13 declared globs:

| declared glob | touched | note |
|---|---|---|
| `retrieve.py`, `config.py`, `server.py`, `__main__.py`, `__init__.py` | yes | core |
| `storage/relational.py` | **no** | declared, untouched — correct |
| `schemas/recall-result.v1.json` | **no** | declared, untouched — required by AC-129 |
| `mcp-server/tests/*` | 9 files | 8 additive, 1 import-line expansion |
| `evals/fusion_gate.py`, `evals/__main__.py`, `evals/BENCH-NOTES.md` | yes | |
| `CHANGELOG.md`, `mcp-server/pyproject.toml` | yes | |

**C-1 scope fence — all clean, verified by empty diffs / greps:**

| forbidden | observed |
|---|---|
| `storage/graph.py` (anomaly A → F-A) | diff empty |
| `evals/retrieval_gate.py` (destroys AC-124 comparability) | **diff empty** |
| `rrf_merge` / `rrf_merge_scored` bodies | untouched; only additive surface below them |
| pre-existing `test_rrf.py` classes | `TestRrfMerge` byte-identical; the file's **only** deletion is the import line |
| per-layer append loop `retrieve.py:326-360` | untouched |
| `FETCH_WIDTH_FLOOR` constant nature | still `FETCH_WIDTH_FLOOR: int = 10` |
| `bm25_search` predicate | untouched (relational.py diff empty) |
| **consumer-side per-seed union for anomaly A** (explicitly rejected, DP-8) | **not present** — one `neighbor_expand` call site, `seed_ids=seed_ids`; no `union(`, no per-seed loop |
| stale `corpus_n` explain key (N-1) | absent |
| new runtime dependencies | none |

`_is_active` is **moved, not modified** — the deleted block and the re-inserted block are
byte-identical, and the move is upward within the same method, so every later caller
resolves the same closure. This is what makes DP-9(b)'s population parity structural
rather than a second, divergent definition.

---

## Step 2 — Full suite, my own run (AC-123)

`docker compose run --rm crystalium pytest mcp-server/tests/ -v`, on `414d45c`, to
completion, with no other crystalium run on the host (I waited for the maker's in-flight
container to exit first — `docker wait` → 0 — because both share the compose project's
data volume):

```
====== 950 passed, 4 skipped, 1 xfailed, 32 warnings in 762.61s (0:12:42) ======
```

Exit 0. **AC-123 GREEN.** The maker's 948/4/0 predates `test_fusion_gate.py`; the delta is
exactly that file (+2 passed, +1 xfailed). The single `xfailed` is the AC-139 node
(strict), adjudicated in Step 7.

---

## Step 3 — Frozen-criteria conformance (42)

Executed against the criteria's own VERIFY oracles, not the maker's paraphrases.

| AC | verdict | evidence |
|---|---|---|
| 101 | GREEN | `test_target_is_fusion_rank_1` PASSED; independently reddened by attacks A and B |
| 102 | GREEN | `test_rank_1_is_k_independent[1,3,5,10,25]` 5/5 PASSED |
| 103 | GREEN | `test_unweighted_path_ranks_target_below_first` PASSED — the flag-off RED-first, re-run by me |
| 104 | GREEN | PASSED with **both** mandated fixtures present: discordant `[["b"],["a"]]` and intra-list duplicate `[["a","b","a"]]`; docstring states the per-occurrence rule |
| 105 | GREEN | `test_exact_tie_breaks_by_id_ascending` PASSED |
| 106 | GREEN | `TestRrfMerge` 9/9 PASSED; `git diff` on `test_rrf.py` = +219/−1, the −1 being the import line |
| 107 | GREEN | PASSED; **reddened by attack A** |
| 108 | GREEN | `test_single_derived_arm_is_identity` PASSED |
| 109 | GREEN | PASSED; **reddened by attack B** |
| 110 | GREEN | PASSED; C-7 honoured in code — censoring reads `raw_n_sparse` before any status filter |
| 111 | GREEN | PASSED (layer sizes 0 and 1) |
| 112 | GREEN | PASSED over the parameterised grid |
| 113 | GREEN | PASSED; **reddened by attack C** |
| 114 | GREEN | PASSED; **reddened by attack F** |
| 115 | GREEN | PASSED over `k in (1,3,10,50)` |
| 116 | GREEN | PASSED — `rrf_score_by_id = dict(fused_scored)` keeps seam 1 the single source of truth |
| 117 | GREEN | PASSED; all C-6 keys present incl. `n_scoped_status`, `candidate_k`, `arm_sizes` |
| 118 | GREEN | PASSED with the eviction-forcing fixture (`evicted_count > 0` asserted) |
| 119 | GREEN | PASSED |
| 120 | GREEN | PASSED; **reddened by attack G** |
| 121 | GREEN | 32 distinct test functions across 13 classes, **all PASSED**; companions `TestTotalCap` (3) and `TestSummaryQualityGate` (9) all PASSED. #36's criteria run on the **weighted** path (fixtures set the flag True, and `Aetheryte(...)` defaults True) |
| 122 | **GREEN** | **my own four-cell probe** — see Step 5 |
| 123 | GREEN | 950/4/1xfail/0 fail — Step 2 |
| 124 | GREEN | C-5 satisfied — see Step 6 |
| 125 | GREEN | C-2: 5/5 unanimous — see Step 6 |
| 126 | GREEN | `cross_layer` axis emitted for `episodic` and `semantic`, both 0 |
| 127 | GREEN | independently re-verified with a **real `crystalium.yaml` file** and env vars — all four fields, both sources |
| 128 | GREEN | manifest no longer carries `raw hybrid-retrieval RRF value`; carries `weighted hybrid-retrieval`; CHANGELOG `[1.10.0]` states it |
| 129 | GREEN | `schemas/` diff **empty**; live `explain=true` instance validates against `recall-result.v1.json` |
| **130** | **RED** | **attack D is GREEN — see Step 4 / F-V1** |
| 131 | GREEN (THEN) | fused order byte-identical across `PYTHONHASHSEED` 0–4 (and 0–19 in my sweep). **But its mandatory RED-first is unobtainable at the prescribed seeds — F-V1** |
| 132 | GREEN | `test_unit_weights_match_legacy_order_when_tie_free` PASSED |
| 133 | GREEN | `context_rank.context` = 2 on all 3 before and all 3 after runs |
| 134 | GREEN (THEN) | `w_sparse == 1.0` on the pure function and the real stack. **Its real-stack RED-first is non-discriminating — F-V2** |
| 135 | GREEN | PASSED, with the set-equality precondition asserted |
| 136 | GREEN | all six of AC-121/122/123/124/125/133 green → shipping `True` is legal — Step 10 |
| 137 | GREEN | BENCH-NOTES annotation present, names P3 as the mechanism. **C-11's anomaly-C half is missing — F-V3** |
| **138** | **INDETERMINATE** | unfalsifiable — AC-139 not green. Criteria-legal, but the recorded root cause is wrong — F-V4 |
| **139** | **INDETERMINATE** | floor-10 and floor-1000 rank distributions **identical**, not disjoint → C-2 makes this INDETERMINATE, which is not green |
| 140 | GREEN | C-2: 5/5 unanimous at `k ∈ {1,3,5}`, floor patched to 1 — Step 8 |
| 141 | GREEN | C-2: 5/5 unanimous — the precondition is satisfied, so AC-140's green **carries information** |
| 142 | GREEN | PASSED; **reddened by the mixed-population mutation** |

**Counts: 39 green · 1 red (AC-130) · 2 indeterminate (AC-138, AC-139).**

### AC-142 — both assertions are load-bearing (transcribed as the criterion requires)

| implementation | `n_sparse` | `n_scoped` | invariant `n ≤ N` | `w_sparse` | caught by |
|---|---|---|---|---|---|
| all-statuses (num all, den all) | 150 | 150 | holds | 1.0000 | neither — correct |
| active-only (num active, den active) | 100 | 100 | holds | 1.0000 | neither — correct |
| **mixed** (num all, den active) | 150 | 100 | **VIOLATED** | 1.0000 | **invariant only** |
| **reverse** (num active, den all) | 100 | 150 | holds | **1.3333** | **weight only** |

Neither assertion alone covers both directions; together they cover all four pairings.
I confirmed the mixed direction empirically: forcing `n_sparse_resolved = raw_n_sparse`
while the denominator stayed active-only turned `test_mixed_status_population_agrees` red.
The shipped implementation reads `n_sparse=5`, `n_scoped=5`, `arm_sizes.sparse=8` on a
5-active/3-deprecated store — numerator and denominator from one population, raw length
kept separate (C-6).

---

## Step 4 — Attack matrix (AC-130)

Each mutation applied in an isolated throwaway clone of `414d45c`, the named node run,
then `git checkout --` restore. Final clone state verified empty.

| # | attack | must redden | observed | verdict |
|---|---|---|---|---|
| A | revert D2 (sum graph + completion again) | AC-101, AC-107 | **2 failed** | reddens ✓ |
| B | force `w_sparse = 1.0` | AC-101, AC-109 | **2 failed** | reddens ✓ |
| C | revert D4 (`seed_ids = dense_ranking[:fw]`) | AC-113 | **1 failed** | reddens ✓ |
| **D** | **revert D5 (unsorted set iteration)** | **AC-131** | **1 PASSED** | **GREEN ATTACK — F-V1** |
| F | `prelim` includes the graph arm (break I-1) | AC-114 | **1 failed** | reddens ✓ |
| G | `recall_weighted_fusion=True` with `relevance_primary=False` | AC-120 | **1 failed** | reddens ✓ |
| H (7th row, not in AC-130's six) | global-store denominator | AC-134 | **2 PASSED** | **GREEN ATTACK — F-V2** |
| — | mixed status population (AC-142's named defect) | AC-142 | **1 failed** | reddens ✓ |

Five of the six mandated attacks redden their nodes. **Attack D does not.** AC-130's THEN
— "the system shall turn every one of those six attacks' named criteria red" — is
therefore not satisfied.

---

## Step 5 — AC-122, the four-cell probe (my own; the maker did not measure this)

Protocol per #36 `verification.md` R5 and #36 DP-R4(ii): real `commit → recall` stack via
`server._build_components`, real sentence-transformers (BAAI/bge-m3) dense arm, real Kuzu
graph arm, **one fresh data dir per cell**, 6 topically-unrelated crystals + 1 fresh
crystal carrying three distinctive low-frequency tokens (`zephyrion quaggle
brindlewisp`), query = exactly those tokens. Two runs per cell. `F` = the fresh crystal.

**Flag ON (AC-122's scope — the four cells):**

| `k` | run 1 | run 2 |
|---|---|---|
| 1 | **fresh pos 0** `[F]` | **fresh pos 0** `[F]` |
| 3 | **fresh pos 0** `[F,1,5]` | **fresh pos 0** `[F,1,5]` |
| 5 | **fresh pos 0** `[F,1,5,3,0]` | **fresh pos 0** `[F,1,5,3,0]` |
| 10 | **fresh pos 0** `[F,1,5,3,0,2,4]` | **fresh pos 0** `[F,1,5,3,0,2,4]` |

**Flag OFF (context, not a criterion):** byte-identical to the ON column in every cell.

**AC-122 GREEN — 8/8 flag-on cells, fresh crystal returned at position 0 in every one.**
Two further properties worth recording: each small-`k` result is an exact **prefix** of
the k=10 ranking, and every cell is byte-stable across its two runs. #36's F-V1
starvation does not reappear under weighted fusion, and the weighted path costs nothing
against the unweighted path on this fixture. The maker's blast-radius argument was
correct, but it was an argument; this is the measurement.

---

## Step 6 — Eval honesty (AC-124, AC-133, AC-125/126)

### AC-124 / AC-133 — C-5 protocol, 3 runs per side

`eval-before` captured from the **clean, unmodified** `/home/rynaro/workspace/oss/agents/crystalium`
checkout at `ef42967` (verified `git status --porcelain` empty before and after);
`eval-after` from this branch. `evals/retrieval_gate.py` is byte-identical on both sides
(diff empty), so the fixture — confound and all — is held invariant, which is the one
property that makes AC-124 readable at all.

| run | `multihop_f1.completion` | `context_rank.context` | `completion_pass` | `gate_pass` |
|---|---|---|---|---|
| before seed 0 | 0.4615384615384615 | 2 | true | true |
| before seed 1 | 0.4615384615384615 | 2 | true | true |
| before seed 2 | 0.4615384615384615 | 2 | true | true |
| after seed 0 | 0.4615384615384615 | 2 | true | true |
| after seed 1 | 0.4615384615384615 | 2 | true | true |
| after seed 2 | 0.4615384615384615 | 2 | true | true |

`max(before) = 0.4615384615384615`; `min(after) = 0.4615384615384615`;
**`min(after) ≥ max(before)` holds** → **AC-124 GREEN** (not indeterminate: the after-set
does not straddle the before-set, it coincides with it). `completion_pass` stayed true in
all six. **AC-133 GREEN** — `context_rank.context` is 2 on every run, both sides.

For the record, the run-varying axis reproduced under my hand too:
`context_rank.both` ∈ {4, 5} before and {4, 4, 5} after — overlapping sets, no signal,
exactly as `BENCH-NOTES.md` now says.

**The three limits a green AC-124 CANNOT license (transcribed verbatim from §3-C):**

> (i) Any claim that multi-hop retrieval quality *improved*, or was preserved *in general*
> — the axis is a single fixture with a known artifact. (ii) Any claim about the completion
> faculty's isolated contribution: the completion flag changes the corpus's edge set
> (2 → 142), so the "ablation" compares two different graphs. (iii) Any inference that a
> green AC-124 shows the derived-family merge preserves multi-hop *chains* — the F1 lift is
> substantially carried by `created_at`-tie co-occurrence edges, not by the seeded 2-hop
> chain.

The CHANGELOG does not paraphrase AC-124 as a retrieval-quality claim. Confirmed.

### AC-125 / AC-126 — C-2 multi-run, 5 independent runs

`python -m evals fusion-gate`, fresh process and fresh store per run,
`PYTHONHASHSEED ∈ {0,1,2,3,unset}`:

| seed | weighted `target_rank` | unweighted `target_rank` | `gate_pass` |
|---|---|---|---|
| 0 | 0 | 1 | true |
| 1 | 0 | 1 | true |
| 2 | 0 | 1 | true |
| 3 | 0 | 1 | true |
| unset | 0 | 1 | true |

**Unanimous 5/5. AC-125 GREEN with C-2 confidence.** AC-126's `cross_layer` axis reports
`episodic: 0` and `semantic: 0` — **AC-126 GREEN**.

---

## Step 7 — AC-138 / AC-139 adjudication, and a corrected root cause

### The measurement

Floor probe, fresh store per run, `PYTHONHASHSEED ∈ {0,1,2}` (I re-ran 3 of the maker's 7
configurations per side):

| build | floor 10 | floor 1000 | distributions |
|---|---|---|---|
| reverted | 1, 1, 1 | 1, 1, 1 | `{1}` vs `{1}` — **identical, not disjoint** |
| fixed | 0, 0, 0 | 0, 0, 0 | `{0}` vs `{0}` |

AC-139 requires the reverted build's target rank to **change** between floor 10 and 1000.
It does not. Per C-2, an overlap makes **AC-139 INDETERMINATE, which is not green**, which
triggers its own escape hatch: **AC-138 must be moved, not weakened**. AC-138's own 7/7
rank-0 result is therefore *unfalsifiable* and is **not claimed as discharged**. The
maker's disposition — record it, do not force it — is the criteria-legal outcome, and the
encoding is faithful: `TestFetchWidthFloorInflation::test_reverted_build_rank_changes_with_floor`
carries the literal AC-139 assertion under `@pytest.mark.xfail(..., strict=True)`, so it
cannot silently pass, and it is named rather than deleted. I verified `strict=True` and
observed it as `XFAIL` (not `XPASS`) in my own full-suite run.

Neither AC-138 nor AC-139 is in AC-136's contingency six, so this does not touch the
shipped default.

### The root cause is NOT what the change records — F-V4

The maker, `red-evidence.txt`, `evals/fusion_gate.py`'s docstring and the xfail reason
string all attribute the indeterminacy to **anomaly A**: "`neighbor_expand` caps at
`seeds[0]`, and `seeds[0]` is invariant to `FETCH_WIDTH_FLOOR` (the floor only changes the
seed-set **TAIL**, never its head)."

That explanation presupposes the floor at least changes the seed *list*. I intercepted the
actual `seed_ids` argument handed to `neighbor_expand` at both floors:

```
build=reverted floor=10    seed_ids calls: [["N1","N2","N3"], ["N2","N1","N3"]]
build=reverted floor=1000  seed_ids calls: [["N1","N2","N3"], ["N2","N1","N3"]]   <- IDENTICAL
build=fixed    floor=10    seed_ids calls: [["target","target-sem","N1","N2","N3"], [...]]
build=fixed    floor=1000  seed_ids calls: [["target","target-sem","N1","N2","N3"], [...]]  <- IDENTICAL
```

**There is no tail.** The fixture's base arms hold 3 ids (reverted) and 5 ids (fixed) —
both far below the floor of 10 — because `dense_ranking` de-duplicates and the mock
supplies only `["N1","N2","N3"]`. So `dense_ranking[:10] == dense_ranking[:1000]` and
`prelim[:10] == prelim[:1000]` as *byte-identical lists*. The floor's causal channel is
dead by **fixture cardinality**, before anomaly A ever gets a chance to act.

Two consequences the change currently records wrongly:

1. **F-A would not unblock this.** `test_fusion_gate.py` says "a future F-A fix should
   flip this to strict=False and then to a real pass." It would not — with 3 dense hits the
   floor still changes nothing, so the node would still xfail. A reader who lands F-A and
   sees this node stay red will file a false bug.
2. **The blocker is in scope, not out of it.** `evals/fusion_gate.py` is a declared glob.
   A fixture carrying more than `FETCH_WIDTH_FLOOR` dense competitors would give the floor a
   live channel on the seed list — at which point anomaly A becomes the *next* obstacle and
   the "blocked on F-A" story becomes true. Today it is an out-of-scope excuse standing in
   front of an in-scope fixture choice.

I am **not** asking for the fixture to be rebuilt inside this change — C-14 reserves that
call for FORGE, and AC-139's escape hatch says "moved, not weakened", never "moved by the
checker". What must change before the tag is the **attribution**, in three places.

---

## Step 8 — AC-140 / AC-141, the thesis pair (C-2), and C-12

`TestGuardVsCure` re-run in 5 independent processes, `PYTHONHASHSEED ∈ {0,1,2,3,unset}`:

| seed | result |
|---|---|
| 0 | 4 passed |
| 1 | 4 passed |
| 2 | 4 passed |
| 3 | 4 passed |
| unset | 4 passed |

**Unanimous 5/5. AC-141 GREEN → AC-140 GREEN, and AC-140's green carries information.**

Per-`k` table (fixed build, `FETCH_WIDTH_FLOOR` monkeypatched to 1):

| `k` | `records[0].id` | verdict |
|---|---|---|
| 1 | `target` | green |
| 3 | `target` | green |
| 5 | `target` | green |
| (AC-141, reverted, k=1) | `N2` — **not** the target | precondition satisfied |

Realised per-arm ranks in the AC-140/141 fixture (recorded per C-4 before the pair was
read): target = sparse rank 1 (sole hit), dense rank 4; N1/N2/N3 = dense ranks 1–3, no
lexical match; one real Kuzu edge `N1 → N2`. Vector arm is a pinned deterministic stub,
graph store is real — exactly what C-4 permits and AC-140 requires.

I re-derived the mechanism independently and it is the pre-registered one, **D4, not the
weighting**: at `fetch_width = 1` the reverted build seeds `dense_ranking[:1] = ["N1"]`,
whose real out-edge lifts `N2` to a second arm (`1/62 + 1/61 = 0.032522`) above the
target's two (`1/61 + 1/64 = 0.032018`); the fixed build's base-arm `prelim` puts the
target first (`w_sparse/61 + 1/64`, `w_sparse = 1.75` here), so `seed_ids = [target]`, and
the target has no out-edges.

**C-12 is not triggered** — AC-140 is green, so no honesty conditions are owed and DP-4(ii)
is moot. But see F-V5: the CHANGELOG describes the *red* outcome anyway.

---

## Step 9 — Release surface

| item | observed | verdict |
|---|---|---|
| `mcp-server/pyproject.toml` | `version = "1.10.0"` | ✓ |
| `crystalium/__init__.py::_FALLBACK_VERSION` | `"1.10.0"` | ✓ (also retires #36's F-V8/D4 skew, which sat at `1.8.0` against a 1.9.0 pyproject) |
| CHANGELOG `[1.10.0]` — score semantics | states `score` is now a **weighted** RRF fusion value, magnitudes shifted, ordering semantics unchanged | ✓ (C-10) |
| CHANGELOG — residual nondeterminism named | "Known limitations" names the store-side membership nondeterminism, scopes the determinism fix to consumer-side ordering | ✓ (C-10) — but the F-A **link** is a placeholder, see F-V6 |
| CHANGELOG — no general determinism claim | explicitly disclaims it | ✓ |
| CHANGELOG — four config fields + revert lever | present | ✓ |
| illustrative figures from the implementation's own run, not `measurement.md` | no prototype figure transcribed | ✓ (C-10) |
| manifest `score` description (AC-128) | unqualified `raw hybrid-retrieval RRF value` **gone**; `WEIGHTED hybrid-retrieval RRF fusion value` present | ✓ |
| `fusion_weight_derived` comment (C-9) | records the 0.90/0.95/1.00 cliff, the `PYTHONHASHSEED=5` flake, the 1.0 % margin, identity forfeiture below 1.0, P1 re-creation above 1.0 | ✓ |
| `fusion_weight_sparse` absence explained (C-9) | "RRF ordering is invariant to a global positive scale" comment present | ✓ |
| AC-127 both sources | real `crystalium.yaml` **file** → `from_yaml` → `_from_dict`: all four applied; env vars: all four applied | ✓ |
| `schemas/recall-result.v1.json` | unmodified; live instance validates | ✓ |
| BENCH-NOTES (AC-137 / C-11) | both mechanisms named, `{2,4,5}` recorded, 4→2 at fixed seed recorded, "remains run-varying after 1.10.0" stated | ✓ **except** anomaly C — F-V3 |

**NOTE (pre-existing, carried forward from #36's Guard 3b).** Inside the dev container
`crystalium.__version__` resolves to `1.4.0` from stale baked-venv dist metadata, on
**both** this branch and `ef42967` — so it is an image artifact, not a change defect.
`_FALLBACK_VERSION` is only consulted when metadata is absent. The published release image
must be rebuilt and probed so `__version__` reports `1.10.0` before its digest enters the
nexus roster.

---

## Step 10 — AC-136 release checklist (the mechanical contingency)

| criterion | verdict |
|---|---|
| AC-121 (#36's 32 re-asserted) | **GREEN** |
| AC-122 (four-cell real-embedding probe) | **GREEN** |
| AC-123 (full suite) | **GREEN** |
| AC-124 (multi-hop non-inferiority, C-5) | **GREEN** |
| AC-125 (fusion gate, C-2) | **GREEN** |
| AC-133 (context axis) | **GREEN** |

All six green. **`Config.recall_weighted_fusion` may ship defaulting to `True`.** AC-130's
red does not enter this list, and AC-138/AC-139's indeterminacy does not either — neither
is in AC-136's frozen six, and I am not widening it (that would be exactly the F6 defect
the criterion exists to prevent, run in reverse).

---

## Evidence notes required by the deliberation

**Anomaly A (DP-8 / C-3) — AC-131's claim scope.** AC-131 green licenses **only** *"the
fused order is hash-seed-independent given fixed arm contents"*. It does **not** license
"the graph and completion arms are deterministic on the real stack" — that claim is false,
and my own fusion-gate interception shows it live: `decaying_walk`'s internal expansion
received `["N2","N1","N3"]` where the direct graph call received `["N1","N2","N3"]`, i.e.
the frontier set's hash order, in the same process. The mocks in AC-131's fixture do return
`set[str]` and `dict[str, float]` as C-3 requires; I confirmed the set's iteration order
genuinely varies across seeds (measured: `3241, 3142, 2413, 3412, 3412, 2134, 4132, 2413`
for seeds 0–7), so the fixture is correctly typed. The problem is downstream — see F-V1.

**Anomaly B (DP-8) — evidence-note, cite when #38 is closed.** `neighbor_expand` filters
`if neighbor_id not in seed_ids` and `decaying_walk` seeds `visited = set(seed_ids)`, so a
record at or above seed rank is structurally barred from both derived arms. The issue's
acceptance sketch — competitors at dense ranks 1–3 that *also* carry graph and completion
votes — therefore describes a configuration the code cannot produce. #38's *class* of
defect is fixed and measured; its *illustration* was unbuildable. I saw the same structure
from the other side: the AC-140 fixture is green at `k ∈ {3,5}` partly because `N2`, the
only edge destination, is itself among the seeds and self-excludes.

**Anomaly C (DP-5 / C-5) — evidence-note.** The retrieval gate's fixture is confounded:
`server.py:522,535` ties `link_cooccurrence` to `config.recall_completion`, so the flag
under test changes the commit-time graph (edge counts 2 / 2 / 142 / 142), and
`recent_crystal_ids` resolves "the 5 most recent" to the 5 *first-committed* crystals
because the fixture stamps an identical `_T0`. The gate's own isolation docstring is false.
I did not re-measure the edge histogram (that would require touching `retrieval_gate.py`,
which C-1 forbids); I take it as recorded and confine AC-124 to the tripwire reading above.

---

## Findings

### F-V1 — **BLOCKING**: attack D cannot redden AC-131 at the seeds AC-131 mandates (AC-130 RED)

*Severity: blocking (the only one). Evidence: my seed sweep, below.*

AC-131's VERIFY mandates subprocesses over `PYTHONHASHSEED` **0 through 4**, and F3
amended the criterion specifically so that its "mandatory RED-first demonstration" would be
decided by the defect rather than by fixture strings. I reverted D5 (both `sorted()` calls)
and ran the node: **it passed.**

Diagnostic — the same fixture, fused order per process, on the **D5-reverted** build:

| seed | 0 | 1 | 2 | 3 | 4 | 5 | **6** | 7 | 8 | **9** | 10 | 11 | 12 | 13 | 14 | **15** | 16 | **17** | **18** | 19 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fused order | 1234 | 1234 | 1234 | 1234 | 1234 | 1234 | **1243** | 1234 | 1234 | **1243** | 1234 | 1234 | 1234 | 1234 | 1234 | **1243** | 1234 | **1243** | **1243** | 1234 |

The defect **is** observable — at seeds 6, 9, 15, 17 and 18 — and the shipped build is
`1234` at every one of them, so D5 is a real, working fix. But **no seed in 0..4 discriminates**,
and 0..4 is precisely the window the criterion prescribes. Mechanism: `completion_ranking`
is a fixed dict literal `[id1,id2,id3,id4]`, and D2's min-rank merge collapses most graph
permutations back onto it; the derived order only moves when `id4` reaches graph rank 1,
which happens for roughly one seed in four. The maker's chosen fixture drew a 5-seed window
that missed it — a ≈ 24 % outcome, not misconduct.

`red-evidence.txt` states: *"PYTHONHASHSEED=0: graph_ranking iteration order differs from
PYTHONHASHSEED=1 … → different derived_ranking → different fused scores."* The first clause
is true (`3241` vs `3142`); the conclusion is **not reproducible** — the fused order is
identical at seeds 0 and 1 on the reverted build. AC-131's own text requires
`verification.md` to record "the observed disagreeing seed pair from 0..4". **There is no
such pair for these fixture ids.** The literal ids, as the criterion also requires:

```
11111111-1111-4111-8111-111111111111
22222222-2222-4222-8222-222222222222
33333333-3333-4333-8333-333333333333
44444444-4444-4444-8444-444444444444
```

Consequence: AC-130's THEN is unmet → **AC-130 RED**. This is the fourth
"gate that cannot fail on the defect it names" this campaign has surfaced, and the first to
survive into an implementation.

**Remedy (test-only, inside `mcp-server/tests/*`, no `src/` change):** widen the node's
seed set to include a discriminating value (0..7 suffices; 6 is the first), or choose
fixture ids that diverge inside 0..4, and record the disagreeing pair. Re-run attack D to
confirm it then reddens.

### F-V2 — MAJOR: AC-134's real-stack oracle cannot fail on the defect it names

*Severity: major (does not fail a frozen criterion's THEN).*

AC-134 exists "to force the denominator to be counted over `target_layers`". Its real-stack
node inserts **only** 5 procedural crystals, so the layer-scoped count and the global count
are both 5 and the two implementations are indistinguishable. I replaced
`count_for_export(project, layers=target_layers)` with `count_for_export(project)` on both
population branches; the node **passed**.

Counterfactual on a genuinely multi-layer store (5 matched procedural + 95 unrelated
episodic), `layers=['procedural']`:

| build | `n_sparse` | `n_scoped` | `selectivity` | `w_sparse` | AC-134 |
|---|---|---|---|---|---|
| shipped (layer-scoped) | 5 | 5 | 0.0 | **1.0** | holds |
| global denominator | 5 | 100 | 0.95 | **1.95** | **violated** |

So **the implementation is correct** — this is a fixture gap, not a code defect, and it
reproduces the criterion's own predicted shape (its 10 005-crystal example gives 1.9995;
my 100-crystal one gives 1.95). The maker's RED-first for AC-134 was demonstrated only at
the pure-function level (`resolve_sparse_weight(5, 5, 30, 10_005, 1.0) → 1.9995`), which
proves the arithmetic, not that the *implementation* draws the denominator from the right
population. Remedy: add other-layer crystals to that fixture (one line).

Sub-note: in the mutated build `explain.fusion.n_scoped_layers` still reported
`["procedural"]` while `n_scoped` was 100 — the explain surface would have lied, and
nothing asserts consistency between those two keys. Worth an assertion.

### F-V3 — MAJOR: C-11's anomaly-C half is missing from BENCH-NOTES

C-11 is explicit: "**The same entry** records anomaly C's confound and links F-C." §3-C
additionally names `evals/BENCH-NOTES.md` as "the in-scope landing spot for this evidence".
The new entry covers P3 and anomaly A well, but grepping the whole file finds no
`link_cooccurrence`, no `created_at`-tie artifact, no 2-vs-142 edge counts, no edge-target
histogram, no note that the gate's isolation docstring is false, and no F-C reference. A
binding condition is unmet, and the one document that would warn the next reader that this
gate "currently cannot mean what it says" does not warn them. Remedy: append a paragraph.

### F-V4 — MAJOR: the AC-138/AC-139 indeterminacy is attributed to the wrong cause

Full evidence in Step 7. `seed_ids` is byte-identical at floor 10 and floor 1000 on both
builds because the fixture's arms (3 and 5 ids) are shorter than the floor — the floor
changes nothing at all, so anomaly A is not the operative mechanism. Three artifacts state
otherwise and should be corrected before the tag:

1. `evals/fusion_gate.py` module docstring — "the floor changes the TAIL of the seed slice,
   never its head" (there is no tail).
2. `test_fusion_gate.py::TestFetchWidthFloorInflation` docstring **and** the `xfail` reason
   string — same claim, plus "a future F-A fix should flip this to strict=False and then to
   a real pass", which is false on this fixture.
3. `red-evidence.txt`'s AC-138/139 section — same attribution.

The *verdict* (INDETERMINATE, not green, AC-138 not claimed) is correct and criteria-legal;
only the causal story is wrong. This matters because it changes F-A's advertised payoff and
because it presents an in-scope fixture choice as an out-of-scope blocker.

### F-V5 — MINOR: the CHANGELOG describes a red AC-140 that measured green

CHANGELOG `[1.10.0]` → "Known limitations":

> **No claim is made that this change replaces the v1.9.0 `FETCH_WIDTH_FLOOR` guard.** At
> very small `k` … with the floor artificially lowered, the fix's own thesis test **is
> layered on top of, rather than a replacement for, that guard**…

AC-140 is **green**, unanimously across 5 seeds, with AC-141 green as its precondition — so
the thesis test *passed*: at `FETCH_WIDTH_FLOOR = 1` the target holds rank 0 at
`k ∈ {1,3,5}`. The prose asserts the opposite measured outcome. It errs in the safe
direction (declining a claim is always permitted; §8 would in fact now license it), but it
is a statement about evidence that the evidence contradicts, in the release notes of a
change whose whole discipline is bounded claims. Remedy: either restate it factually
("with the floor lowered to 1, the target still holds rank 0 at `k ∈ {1,3,5}`; the guard
nonetheless remains shipped at 10 and is not removed by this change"), or delete the second
sentence and keep the first.

### F-V6 — MINOR: C-10's "linked to F-A" is a placeholder

The CHANGELOG says "a follow-up issue tracks the store-side fix and the re-baseline it
requires" without an issue number, and BENCH-NOTES likewise says "tracked as a follow-up
issue". C-13 requires F-A opened **before the tag**, so the number will exist; C-10 requires
the residual "named and linked to F-A". Substitute the real issue numbers into both
documents once C-13's issues are filed. Same applies to F-C in BENCH-NOTES (see F-V3) and
to the D-1/D-4 references.

### F-V7 — NOTE: `n_sparse` and `arm_sizes.sparse` diverge silently by design

C-6 mandates the split and the code comments it, and AC-142's test pins `n_sparse=5` against
`arm_sizes.sparse=8`. This is correct. Recording it because a consumer reading
`explain.fusion` will see two "sparse counts" that disagree on any aged store, and only the
code comment explains why. A one-line note in the CHANGELOG's `explain.fusion` bullet would
save a support round-trip.

### F-V8 — NOTE: a pre-existing stash entry survives in the worktree

`git stash list` in the worktree shows `stash@{0}: On fix/recall-tiktoken-special-token-32:
vivi: pre-merge stash of unrelated nexus sync drift` — predates this change (it is the same
entry #36's F-V9 recorded). I left it untouched.

---

## Verdict

**FAIL — AC-130.**

39 of 42 criteria green; 2 (AC-138, AC-139) INDETERMINATE in the criteria-legal way, with
the finding recorded and routed to FORGE; **1 (AC-130) RED**.

Stated plainly, because the shape of this failure matters more than the label: **the
implementation is sound.** I attacked it eight ways and it defended itself six of those
ways on its own terms; the derived-family merge, the query-conditional sparse boost, the
base-arm reseeding, the D5 determinism fix, the DP-9(b) population parity and the C-7
censoring split are all real, all measured, and all correctly gated. AC-136's contingency
six are green, so `recall_weighted_fusion: true` is a legal default. AC-122 — the one
non-regression the maker argued instead of measuring — **holds**, 8/8, on the real
embedding stack. AC-140/AC-141, the thesis pair, are green with C-2 confidence, which is
the strongest result this change could have obtained.

What fails is a **gate**, not the code it guards: reverting D5 does not turn AC-131 red at
the five hash seeds AC-131 itself prescribes, so AC-130's THEN — "the system shall turn
every one of those six attacks' named criteria red" — is unmet. This campaign amended its
criteria three times to eliminate exactly this species (the F2 tautology, the F3
string-dependence, the H-1 non-discriminating oracle) and promoted the doctrine into a
frozen criterion so that it would be mechanical rather than discretionary. Discharging
AC-130 by argument now would be the F6 defect one criterion over.

The remedy is small and entirely inside an already declared glob: widen AC-131's seed set
past 4 (6 is the first discriminating value I measured) or pick ids that diverge inside
0..4, then re-run attack D and record the disagreeing pair. No `src/` change is implied by
any finding in this report.

**A reading I considered and rejected.** AC-130's VERIFY says "a green attack on any of the
six **is a finding**", which can be read as making the recording — not the reddening — the
deliverable, in which case AC-130 would be discharged-with-findings and this verdict would
be PASS-WITH-FINDINGS. I rejected it because the block's normative THEN is unambiguous and
a criterion's VERIFY names how to evidence a THEN, not how to excuse one. The maintainer
may legitimately route that disposition to FORGE under C-14 rather than accept my reading;
if FORGE takes the softer reading, everything else in this report supports proceeding, and
F-V1 becomes a MAJOR finding on a change that is otherwise release-ready.

**Owed before the tag regardless of how AC-130 is dispositioned:** F-V3 (C-11's anomaly-C
half — a binding condition, currently unmet), F-V4 (three artifacts assert a root cause the
measurement contradicts), F-V5 (release notes contradict a green AC-140), F-V6 (issue
numbers), and C-13's five MUST follow-ups.

### Tree-left-as-found attestation

| tree | entry state | exit state |
|---|---|---|
| worktree `crystalium-impl` | `414d45c…3da`, `status --porcelain` empty | **`414d45c…3da`, `status --porcelain` empty** |
| baseline `/home/rynaro/workspace/oss/agents/crystalium` | `ef42967…444`, clean | **`ef42967…444`, clean** |

No commit, no stash, no branch, no tag, no push, nothing untracked left in either tree. All
eight mutations were applied in a throwaway clone under my own scratch directory
(`…/scratchpad/vigil/attack`), restored after each attack (final `status --porcelain`
empty), and that clone plus my probe scripts and logs live entirely in the session
scratchpad. The pre-existing `stash@{0}` in the worktree (F-V8) was not mine and was not
touched. `evals/retrieval_gate.py` was never edited on either side of the AC-124 capture.

---

## Follow-up issues this change owes

C-13 makes **F-A, F-B, F-C, F-D and D-1 MUST-open before the tag**, and D-2/D-4 SHOULD.
Two more are owed by this verification (F-V-A, F-V-B). Draft bodies follow.

### F-A — `neighbor_expand` returns only the first seed's neighbours (high)

> `GraphStore.neighbor_expand` (`storage/graph.py:205-256`) wraps its entire
> `for seed_id in seed_ids` loop in a single `try`, and the Kuzu driver **raises** at cursor
> exhaustion instead of returning `None` — so the first seed's row loop aborts the whole
> expansion and `neighbor_expand(seeds) ≡ neighbor_expand([seeds[0]])`. Probed at `ef42967`:
> `[id1,id2] -> [id4]`, `[id0,id1,id2] -> []`, `[id2,id1] -> [id5]`. `decaying_walk` passes
> `list(frontier)` from a **set**, so *which* seed survives is per-process hash-random: this
> is **membership** nondeterminism, not merely ordering, and crystalium#38's two consumer-side
> `sorted()` calls do not reach it. Observed consequences: completion-arm cardinality 2 and 4
> with four distinct orderings; `context_rank.both ∈ {2,4,5}` including a 4→2 variation at a
> fixed `PYTHONHASHSEED` (ids are `uuid4`-fresh per run). The fix must land with a per-seed
> store unit test, a `neighbor_expand` call-site audit, D-3's discovery/BFS-order question
> folded in, a **re-baselined `eval-before.json`**, and a re-run of #38's AC-124/AC-125/AC-133
> plus a re-check of the DP-2 `fusion_weight_derived` default — because repairing membership
> changes arm composition and therefore the completion rank the 0.95 cliff was measured
> against. Note for whoever picks this up: **every measurement in the #38 campaign was taken
> on a one-seed expansion.** Note also that fixing this alone will **not** make #38's
> AC-138/AC-139 falsifiable — see F-V-A.

### F-B — seeds are structurally excluded from both derived arms (medium)

> `neighbor_expand` filters `if neighbor_id not in seed_ids` and `decaying_walk` seeds
> `visited = set(seed_ids)`. Consequence: a record at or above seed rank can never receive
> graph or completion credit, so a strong graph neighbour that is *also* a top-dense hit is
> systematically under-credited. This is not obviously a defect — excluding your own seeds is
> defensible for arms whose job is to find *new* records — but it is load-bearing enough to
> deserve an explicit decision: it is why crystalium#38's acceptance sketch (competitors at
> dense ranks 1–3 that *also* carry derived votes) describes a configuration the code cannot
> produce, and why #38's derived-family merge yields the "base-arm rank-1 protection"
> invariant as a theorem rather than a bolted-on guard. Decide whether seed exclusion should
> be relaxed — e.g. credit a seed's own derived support without re-expanding it — and record
> the decision either way so the next reader does not re-derive it.

### F-C — the retrieval gate's fixture is confounded; its isolation docstring is false (med-high)

> `evals/retrieval_gate.py` claims "Edges are seeded in EVERY arm, so the only variable is
> whether the recall walk / re-rank runs — isolating the faculty, not the fixture." Measured
> edge counts contradict it: flat **2**, context **2**, completion **142**, both **142**. Two
> causes. (1) `server.py:522,535` sets `link_cooccurrence = config.recall_completion`, so the
> flag under test changes the commit-time graph — the "ablation" compares two different
> graphs. (2) `recent_crystal_ids` does `ORDER BY created_at DESC LIMIT 5` while the fixture
> stamps every crystal with an identical `_T0`, so "the 5 most recent" resolves to the 5
> **first-committed** crystals; the resulting edge-target histogram is
> `{spoke1: 30, hub: 30, spoke2: 29, noise1: 27, noise2: 26}`, i.e. both ground-truth spokes
> are direct co-occurrence neighbours of nearly every crystal, and the completion arm's F1
> lift is substantially an artifact of `created_at` ties rather than of the seeded 2-hop
> chain. Fix: distinct `created_at` stamps, edge seeding decoupled from the arm under test,
> and the docstring corrected either way. Severity is driven by blast radius — this is the
> gate that guards every retrieval change in the repo, and it currently cannot mean what it
> says. Until it is fixed, it remains valid **only** as a non-inferiority tripwire on an
> identical fixture (crystalium#38 deliberation C-5).

### F-D — the sparse candidate set is status-blind (medium)

> `bm25_search` applies `LIMIT candidate_k` with no status predicate, so under CRYSTALIUM's
> P0-5 (write-new, never hard-delete) deprecated near-duplicates consume fetch slots: they can
> push the raw `n_sparse` to `cap` — tripping crystalium#38's censoring branch to
> `w_sparse = 1.0` and silently disabling the selectivity boost — and can crowd active hits
> out of the candidate set entirely. Pre-existing and independent of #38, but #38's DP-9(b)
> makes it the **dominant remaining aging path** for the sparse boost: the feature degrades
> monotonically in exactly the long-lived stores it exists for, with no error, no log line
> and no explain anomaly. Note the constraint that shaped #38: no status predicate may be
> added to `bm25_search` itself, which is a shared read path — the fix belongs at the fetch
> sizing or in a status-aware candidate top-up.

### D-1 — cross-layer rank blocking (med-high)

> `retrieve.py:326-360` appends candidates per layer over `_ALL_LAYERS`, so with
> `layers=None` an episodic hit always precedes every semantic hit regardless of BM25 score;
> the inversion fires at `j >= 1`. It is arm-internal, so crystalium#38's sparse boost cannot
> correct it. #38 deliberately deferred the fix and landed the *evidence* instead:
> `evals/fusion_gate.py` now reports a `cross_layer` axis (measured this verification:
> `episodic: 0`, `semantic: 0` on a fixture where the query resolves in both layers). Land a
> discriminating multi-layer gate **before** the fix, per the spec's own sequencing
> condition, then choose between round-robin interleave and a score-space merge.

### D-2 — `embed(query)` called once per layer (low)

> `retrieve.py:340` sits inside the per-layer loop, so a default four-layer recall computes
> four identical query embeddings. Pure waste on the hot path; hoist the embedding above the
> loop. No behavioural change expected — worth a micro-benchmark on the way in so the saving
> is recorded rather than assumed.

### D-4 — `candidate_k` corpus scaling, not `FETCH_WIDTH_FLOOR` (low-med)

> The recall ceiling a growing corpus actually threatens is `candidate_k = max(k*3, 10)`
> (`retrieve.py:324`), not the seed-width floor. First measured datum, from crystalium#38:
> `dense_ranking` held exactly 30 ids (`candidate_k`) against a 31-crystal corpus, and
> `candidate_k` — not the floor — is what cut `spoke2` out of the dense arm entirely.
> `FETCH_WIDTH_FLOOR` must stay a constant for eval reproducibility (a corpus-dependent floor
> makes the ranking universe drift with unrelated commits), so the per-layer fetch is where
> scaling belongs. Needs measurement on a large corpus, which #38 did not supply.
> `explain.fusion` now surfaces both `fetch_width` and `candidate_k`, so the datum is
> collectable in production.

### F-V-A (new, from this verification) — the fusion gate's floor probe has no live channel (medium)

> `evals/fusion_gate.py`'s fixture supplies three dense competitors, so `dense_ranking`
> (which de-duplicates) holds 3 ids on the reverted path and `prelim` holds 5 on the fixed
> path — both far below `FETCH_WIDTH_FLOOR = 10`. Measured by intercepting the `seed_ids`
> argument handed to `neighbor_expand`: the lists are **byte-identical** at floor 10 and floor
> 1000 on both builds (`[["N1","N2","N3"], ["N2","N1","N3"]]` reverted;
> `[["target","target-sem","N1","N2","N3"], …]` fixed). The floor therefore changes nothing —
> not merely "the tail, never the head" as the current docstrings and the `xfail` reason say.
> Consequences: (1) crystalium#38's AC-138/AC-139 are blocked by **fixture cardinality**, not
> by anomaly A, so landing F-A will **not** flip
> `TestFetchWidthFloorInflation::test_reverted_build_rank_changes_with_floor` to green and the
> current "a future F-A fix should flip this to strict=False" comment will mislead; (2) the
> blocker is in scope — a fixture carrying more than `FETCH_WIDTH_FLOOR` dense competitors
> would give the floor a live channel on the seed list, at which point anomaly A becomes the
> next (and genuine) obstacle. Fix the fixture, re-run the pair, and correct the attribution
> in `evals/fusion_gate.py`, `test_fusion_gate.py` and the change's `red-evidence.txt`.

### F-V-B (new, from this verification) — two #38 gates cannot fail on the defects they name (high)

> Found by the crystalium#38 checker's attack matrix; both are **test-side**, neither implies
> a `src/` change. (1) **AC-131 / attack D.** Reverting the D5 `sorted()` calls does **not**
> change the fused id order at `PYTHONHASHSEED` 0–4 — the exact window AC-131's VERIFY
> prescribes. Divergence first appears at seed 6 and recurs at 9, 15, 17, 18 (measured over
> 0–19), because `completion_ranking` is a fixed dict literal and D2's min-rank merge collapses
> most graph permutations back onto it; the derived order only moves when the fourth id reaches
> graph rank 1. Widen the node's seed set past 4, or choose ids that diverge inside 0–4, and
> record the disagreeing pair. (2) **AC-134's real-stack node.** Its store holds only the 5
> procedural crystals it matches, so a layer-scoped and a global denominator are both 5;
> replacing `count_for_export(project, layers=target_layers)` with `count_for_export(project)`
> leaves the node green. On a store with 95 additional episodic crystals the same mutation
> moves `w_sparse` from 1.0 to 1.95, so the fixture needs other-layer population. Also add an
> assertion that `explain.fusion.n_scoped` is consistent with `n_scoped_layers` — in the
> mutated build the explain surface reported `["procedural"]` beside a global count of 100.

---

*VIGIL — reproduction before blame; counterfactual before conclusion. Verify · Isolate ·
Graph · Intervene · Learn.*

---
---

# Delta round — remediation re-verification (2026-08-03, vigil, same fresh context)

| Field | Value |
|---|---|
| round | 2 (delta) — round 1 above stands unaltered |
| **HEAD verified** | **`54c1e51cf028654218077c8c86aec63107cd9bfe`** |
| previous HEAD | `414d45c35cab867b28ba17a99bcc91ce0377d3da` |
| branch | `fix/rrf-fusion-38` (unchanged) |
| criteria integrity | `e644052e868db47b49c7daedba904e9f53b67d401c81bde0b5e2887ffcb2fded` — **still matches the frozen hash** (C-15) |
| **updated verdict (whole change)** | **PASS-WITH-FINDINGS** |

## Delta scope audit

One commit, `54c1e51`, 5 files, +317/−102. **`git diff 414d45c HEAD -- 'mcp-server/src/'` is
empty** — no production code changed, so every round-1 behavioural result stands without
re-derivation. Touched: `CHANGELOG.md`, `evals/BENCH-NOTES.md`, `evals/fusion_gate.py`,
`mcp-server/tests/test_fusion_gate.py`, `mcp-server/tests/test_fusion_weighting.py` — all
inside the 13 declared globs, C-1 fence still intact. `red-evidence.txt` (change folder)
rewritten in place with a retraction notice at the top.

I re-cloned the throwaway attack clone at `54c1e51` and confirmed
`retrieve.py` is byte-identical to the worktree before running any mutation.

## Full suite

I waited on the maker's in-flight remediation container (`docker wait` → **0**) rather than
launching a duplicate under contention:

```
950 passed, 4 skipped, 1 xfailed, 32 warnings in 762.86s (0:12:42)
```

Identical to my own round-1 number (`950 / 4 / 1 xfail` in 762.61s). The remediation added
no new test nodes — it replaced fixture ids, enlarged two fixtures and rewrote docstrings —
so an unchanged node count is the correct expectation, not a coincidence. **AC-123 stays
GREEN.** The single `xfailed` remains the AC-139 node, still `strict=True`, still XFAIL (not
XPASS).

## Per-finding closure

### F-V1 (BLOCKING) — **CLOSED**

`_DETERMINISM_IDS` now holds four measured ids. I re-ran both directions myself.

**Shipped build (D5 present), seeds 0–4 — 5/5 byte-identical:**

```
all seeds: [fb6f38da, ef087731, 82445783, d8fb6b35]
```

**D5-reverted (attack D), same ids, seeds 0–4:**

| seed | fused order |
|---|---|
| 0 | `fb6f38da, ef087731, d8fb6b35, 82445783` |
| **1** | `fb6f38da, d8fb6b35, ef087731, 82445783` ← **diverges from seed 0** |
| 2 | `fb6f38da, ef087731, d8fb6b35, 82445783` (= seed 0) |
| 3 | `fb6f38da, d8fb6b35, ef087731, 82445783` (= seed 1) |
| 4 | `fb6f38da, ef087731, 82445783, d8fb6b35` ← third distinct order |

This reproduces the maker's recorded table **seed for seed**. The
**observed disagreeing seed pair from 0..4 that AC-131's frozen text requires is (0, 1)**,
with the literal ids:

```
fb6f38da-ed29-429d-8db1-b7c4772f4dd2
ef087731-8b91-4b7e-a603-f8e82aadd84c
d8fb6b35-c1ac-472c-b518-9777e389a9b4
82445783-adf6-4972-b00c-f667bd06e315
```

Attack D against the real node now **reddens**:

```
E   At index 1 diff: 'd8fb6b35-c1ac-472c-b518-9777e389a9b4' != 'ef087731-8b91-4b7e-a603-f8e82aadd84c'
FAILED mcp-server/tests/test_fusion_weighting.py::TestDeterminism::test_fused_order_is_hash_seed_independent
```

The gate can now fail on the defect it names. Note the remediation is a genuine
**re-selection**, not a re-ordering: the ids were chosen by measuring candidates against the
real implementation, and the docstring records the mechanism (a fixed-dict completion arm
merged by D2's min-rank against a hash-varying graph arm) rather than asserting the outcome.

### AC-130 attack matrix, re-run in full at `54c1e51` — **GREEN**

| # | attack | must redden | observed | verdict |
|---|---|---|---|---|
| A | revert D2 | AC-101, AC-107 | 2 failed | reddens ✓ |
| B | force `w_sparse = 1.0` | AC-101, AC-109 | 2 failed | reddens ✓ |
| C | revert D4 | AC-113 | 1 failed | reddens ✓ |
| **D** | **revert D5** | **AC-131** | **1 failed** | **reddens ✓ (was green)** |
| F | break I-1 | AC-114 | 1 failed | reddens ✓ |
| G | break D7 subsumption | AC-120 | 1 failed | reddens ✓ |
| — | mixed status population | AC-142 | 1 failed | reddens ✓ |

**All six of AC-130's named rows redden. AC-130 is GREEN.** The round-1 FAIL is discharged.

### F-V2 (MAJOR) — **CLOSED**

The AC-134 real-stack fixture now carries 95 unrelated episodic fillers, so the layer-scoped
denominator (5) and the global one (100) diverge. I re-ran **my exact round-1 mutation**
(strip `layers=target_layers` from `count_for_export` on **both** population branches):

```
>       assert fusion["w_sparse"] == 1.0
E       assert 1.95 == 1.0
FAILED mcp-server/tests/test_fusion_weighting.py::TestExplain::test_layer_saturating_query_real_stack
```

`1.95` is exactly the value I computed independently in round 1 (`1 + 1.0*(1 − 5/100)`). The
node now fails on the defect AC-134 names. My sub-note was also addressed: the test now
asserts `n_scoped == 5` **and** `n_scoped_layers == ["procedural"]`, so the self-contradictory
explain surface (a global count of 100 beside `["procedural"]`) is caught too.

### F-V3 (MAJOR) — **CLOSED**

The new BENCH-NOTES paragraph satisfies every element of C-11's binding condition: it names
`link_cooccurrence` and the `server.py:522,535` coupling, records the measured edge counts
**flat 2 / context 2 / completion 142 / both 142**, explains the `created_at`-tie mechanism
and gives the edge-target histogram `{spoke1: 30, hub: 30, spoke2: 29, noise1: 27,
noise2: 26}`, states plainly that the gate's own isolation docstring is false, scopes what
survives (the non-inferiority tripwire) against what does not (faculty isolation,
general quality, multi-hop chains), and **links F-C**. C-11 is now met.

### F-V4 (MAJOR) — **CLOSED**, and the correction is itself correct

The fixture now carries 12 fillers so `dense_ranking` holds 15 ids. I re-ran my own
interception, this time spying **both** `neighbor_expand` and `decaying_walk`:

| seed | build | floor | seeds passed | `decaying_walk` → | `retrieved` | `target_rank` |
|---|---|---|---|---|---|---|
| 0 | reverted | 10 | 10 | `{Z}` | `['Z', 'target']` | 1 |
| 0 | reverted | **1000** | **15** | **`{}`** | **`['N1', 'target']`** | 1 |
| 0 | fixed | 10 | 10 | `{Z}` | `['target','target-sem']` | 0 |
| 0 | fixed | **1000** | **17** | **`{}`** | `['target','target-sem']` | 0 |

**The floor's channel is live and measured** — the seed sets genuinely differ (10 vs 15/17),
the walk's return value differs (`{Z}` vs `{}`), and the **retrieved list itself changes**
(`['Z','target']` → `['N1','target']`). This independently reproduces the maker's exact
recorded datum. Round 1's "the floor changes nothing, not even the tail" was true only of the
undersized original fixture, and both the maker's correction and my own re-measurement now
say so. The retraction is propagated to all three artifacts I named plus `red-evidence.txt`,
which opens with an explicit retraction notice.

What remains unmoved is `target_rank`, because `N1` ties `target` at `1/61` and the
id-ascending tiebreak (`"N1" < "target"`) keeps the target at rank 1 whether the phantom earns
one vote or two.

**Ruling 1 — is the INDETERMINATE now criteria-legal with correct attribution? YES.**
C-2 requires the floor-10 and floor-1000 rank *distributions* to be **disjoint**; I measured
`{1,1,1}` versus `{1,1,1}` (reverted) and `{0,0,0}` versus `{0,0,0}` (fixed) across seeds
0–2. They overlap, so AC-139 is INDETERMINATE — which is not green — and AC-138 is
unfalsifiable and is **not claimed as discharged**. That is precisely the outcome DP-8's
`[RISK]` and C-2 pre-registered, and the escape hatch's disposition ("recorded and returned to
FORGE — never resolved by an implementer") is what the change does: the literal assertion
survives as a strict, named xfail; the measurement is recorded; nothing is fabricated. The
attribution is now a *measured mechanism* (live channel masked by a deliberate tiebreak)
rather than a borrowed excuse (anomaly A). Neither criterion is in AC-136's six, so the
shipped default is untouched.

**Ruling 2 — was declining the AC-125 trade the right call? YES, and it is not a close call.**
The tie-break-neutral diagnostic fixture would have bought disjointness on AC-138/AC-139 at
the cost of AC-125's unanimity (measured 7/7 → ~2/7). Under C-2 a split verdict is "**RED and
a finding, never a retry**"; AC-125 is one of AC-136's frozen six, so a red AC-125 flips
`recall_weighted_fusion` to `False` **mechanically** and returns the change to FORGE — i.e.
it would ship unweighted fusion, with the measured P1 inversion live, in exchange for
converting two criteria that are *explicitly permitted* to be indeterminate into green ones.
AC-136 exists exactly so this is not a judgement call, and the ruling it forces is the one the
maker took.

I verified the mechanism rather than accepting the claim. At seed 1 on the shipped fixture the
reverted build's `decaying_walk` returned `{}`, so the phantom earned only **one** vote
(`1/61`) — tied with `target` and with `N1` — and `target_rank` was still 1 **solely** because
`"N1" < "target"`. Remove that tiebreak and `target` takes rank 0, failing AC-125's
`unweighted target_rank != 0` assertion at exactly the seeds where the completion lottery
loses. The regression the maker reports is real and reproduces from my own measurement.

Two things I record in the maker's favour: the diagnostic variant was **measured across 14
seeds and preserved** (the seed-8 divergence is the proof the channel reaches final ranks) —
knowledge kept, fixture not shipped — and the trade-off is disclosed in the shipped docstrings
rather than buried.

### F-V5 (MINOR) — **CLOSED**

The CHANGELOG bullet now states the measured result and bounds it correctly:

> Measured (not modelled): with the floor artificially lowered to `1` … the target still holds
> fused rank 0 at `k` in `{1, 3, 5}`, unanimous across 5 independent `PYTHONHASHSEED` values.
> The mechanism is D4's base-arm reseeding, not the floor … it is not itself a claim that the
> floor is redundant at every `k`, fixture, or corpus this change did not test.

It neither under-claims (the old text asserted a red outcome that measured green) nor
over-claims (§8 would now license "replaces the floor"; the text declines it and names the
untested dimensions). The leading sentence still says the floor remains a shipped constant,
which is true and is what DP-6 wants readers to take away.

### F-V6 (MINOR) — **CLOSED with a standing pre-tag obligation**

Canonical labels `F-A` and `D-1` are now cited with `deliberation.md §7` references in both
CHANGELOG and BENCH-NOTES, and `F-C` in BENCH-NOTES. No GitHub issue numbers were fabricated —
the correct call, since none exist yet. **C-13's requirement that F-A, F-B, F-C, F-D and D-1
be opened before the tag is unchanged and still outstanding**; substituting real numbers into
these three documents remains a pre-tag task the maintainer owns, not a maker gap.

### F-V7 (NOTE) — **CLOSED.** The `explain.fusion` bullet now states that `n_sparse` and
`arm_sizes.sparse` are deliberately different fields that diverge on stores carrying
deprecated rows.

### F-V8 (NOTE) — unchanged; the pre-existing stash was left untouched, per my own disposition.

### F-V9 (NEW, NOTE) — AC-125's unweighted arm now fails partly by tiebreak

Recording what the enlarged fixture changed, since nothing else will. Before remediation the
unweighted arm's `target_rank != 0` was earned by the phantom collecting two derived votes;
now, at seeds where the completion lottery loses (seed 1 in my sweep), it is delivered by
`"N1" < "target"` at an exact `1/61` score tie. AC-125's THEN is still satisfied and the A/B
still isolates the flag — the *weighted* arm's rank-0 remains genuinely boost-driven, which is
the half that carries the fusion claim — but the gate's negative half is now partly an
alphabetical artifact. This is a deliberate, disclosed trade (see Ruling 2) and it blocks
nothing; it belongs in the follow-up that eventually revisits this fixture.

## Updated criteria tally (all 42)

**40 GREEN · 0 RED · 2 INDETERMINATE (AC-138, AC-139).**

Changes from round 1: **AC-130 RED → GREEN**. Everything else holds, and the four criteria
whose fixtures changed were re-verified rather than assumed:

| criterion | delta re-verification |
|---|---|
| AC-131 | shipped build 5/5 identical, seeds 0–4, on the new ids |
| AC-134 | `w_sparse == 1.0`, `n_scoped == 5`, `n_scoped_layers == ["procedural"]`; mutation reddens at 1.95 |
| AC-125 / AC-126 | C-2, 5 runs: weighted rank 0, unweighted rank 1, `gate_pass` true — **5/5 unanimous** on the enlarged fixture |
| AC-140 / AC-141 | C-2, 5 runs: `4 passed` at every seed — unchanged (their fixture was not touched) |
| AC-138 / AC-139 | INDETERMINATE, distributions `{1}` vs `{1}` and `{0}` vs `{0}` |

## AC-136 release checklist (re-affirmed at `54c1e51`)

AC-121 · AC-122 · AC-123 · AC-124 · AC-125 · AC-133 — **all six GREEN**. AC-122 and AC-124/133
carry forward from round 1 unchanged (no `src/` or `evals/retrieval_gate.py` change could
affect them; both were verified empty). AC-125 was re-measured because its fixture changed.
**`Config.recall_weighted_fusion` ships defaulting to `True`.**

---

## Verdict — **PASS-WITH-FINDINGS**

All 42 frozen criteria are either discharged (40) or **criteria-legally INDETERMINATE with the
finding recorded and routed to FORGE** (AC-138, AC-139) — which is the disposition C-2 and
AC-139's own escape hatch prescribe, now resting on a measured mechanism instead of a
misattribution. AC-130's attack matrix is green across all six rows: every gate in this change
can now fail on the defect it names, which is the doctrine this campaign was built to enforce
and the reason round 1 failed. AC-136's contingency six are green, so the default-ON flag is
legal. The C-conditions I can evaluate as checker are met: C-1 (scope fence), C-2 (multi-run,
unanimity, disjointness rule applied), C-3 (AC-131 typing and claim scope), C-5 (eval capture
discipline and the indeterminacy rule), C-6/C-7 (explain contract, raw censoring), C-9
(config documentation), C-10 (release-note honesty), **C-11 (now met)**, C-12 (not triggered —
AC-140 is green), C-15 (freeze integrity).

The remediation is the right shape in a way worth recording: it fixed **only** what was
broken — no `src/` file changed, so no behavioural result needed re-deriving — it corrected a
false claim by **retraction rather than quiet edit**, and where a fix would have traded a
contingency-six criterion for two non-contingency ones, it **declined the trade and documented
why**. It also did not manufacture a green AC-139 when one was available at that price.

### Nothing blocks `verified`

The remaining items are maintainer-owned and land **before the tag**, not before `verified`:

1. **C-13 — file the five MUST follow-ups** (F-A, F-B, F-C, F-D, D-1; F-V-A additionally) and
   substitute their real issue numbers into CHANGELOG, BENCH-NOTES and the test docstrings that
   currently carry canonical labels only.
2. **Release-image version probe** (carried from round 1, pre-existing): the dev container
   resolves `crystalium.__version__` to `1.4.0` from stale baked-venv metadata on this branch
   *and* on `ef42967`. Rebuild the release image and assert `__version__ == "1.10.0"` before its
   digest enters the nexus roster — #36's Guard 3b, repeated.
3. **F-V9** — the note above, for whoever next touches the fusion-gate fixture.

### Exact HEAD verified and tree attestation

**`54c1e51cf028654218077c8c86aec63107cd9bfe`**, branch `fix/rrf-fusion-38`.

| tree | entry (delta round) | exit |
|---|---|---|
| worktree `crystalium-impl` | `54c1e51…bfe`, `status --porcelain` empty | **`54c1e51…bfe`, `status --porcelain` empty** |
| baseline `/home/rynaro/workspace/oss/agents/crystalium` | `ef42967…444`, clean | **`ef42967…444`, clean** |

No commit, stash, branch, tag or push in either tree. The frozen `spec.criteria.md` still
hashes to `e644052e…fded`. All delta mutations ran in a fresh throwaway clone under my own
scratchpad, which was restored to a clean tracked state after every attack and then deleted
(its container-created root-owned caches were removed via a throwaway container, since they
are not removable as the host user — worth knowing for anyone repeating this protocol). ESL
status left at `in_progress`; the orchestrator owns the transition.

---

## Follow-up issue drafts — refreshed

**F-A, F-B, F-C, F-D, D-1, D-2, D-4** stand exactly as drafted in round 1, with **one
correction to F-A**: strike the round-1 sentence *"Note also that fixing this alone will not
make #38's AC-138/AC-139 falsifiable — see F-V-A"* and replace it with: *"Note that landing
this alone will not make #38's AC-138/AC-139 falsifiable on their shipped fixture — that
blocker is a deliberate tie-break trade-off protecting AC-125, not anomaly A. See F-V-A."*
The rest of F-A is unaffected: its mandate to re-baseline `eval-before.json` and re-run
AC-124/AC-125/AC-133 plus the DP-2 default check stands.

### F-V-A — **REPLACED** (its round-1 premise was corrected by this remediation)

Round 1 said the fusion gate's floor probe had "no live channel". That was true of the
3/5-id fixture and is **no longer true**: the fixture now holds 15 dense ids and the channel is
measured live end-to-end. The residual follow-up is different and narrower:

> **AC-138/AC-139 remain unfalsifiable on the shipped fusion-gate fixture — by a deliberate,
> disclosed trade-off (medium).** `evals/fusion_gate.py` now gives `FETCH_WIDTH_FLOOR` a
> genuinely live channel (15 dense ids; `[:10]` vs `[:1000]` pass different seed sets, and
> `decaying_walk` returns `{Z}` vs `{}` at seed 0 on the reverted build, changing the retrieved
> list from `['Z','target']` to `['N1','target']`). The target's *final rank* nonetheless does
> not move, because `N1` ties `target` at `1/61` and the id-ascending tiebreak keeps `target` at
> rank 1 regardless of vote count — so the floor-10 and floor-1000 rank distributions overlap
> and C-2 makes AC-139 INDETERMINATE. A tie-break-neutral variant (competitor ids renamed to
> sort after `target`) **does** show divergence (seed 8 of a 14-seed sweep) but regresses AC-125
> from 7/7 to ~2/7 unanimous, and AC-125 is in AC-136's contingency six while AC-138/AC-139 are
> not — so it was correctly not shipped. Revisit when a fixture can be built that is
> simultaneously tie-break-neutral **and** AC-125-reliable; that most likely requires F-A
> (so the phantom node reliably earns its second vote instead of depending on a hash lottery),
> which means **F-A is a precondition for this, not a solution to it**. Until then AC-138/AC-139
> stay recorded-not-discharged, per AC-139's own "moved, not weakened" escape hatch, and the
> disposition sits with FORGE rather than with an implementer (C-14).

### F-V-B — **WITHDRAWN (closed in-change)**

Round 1 raised "two #38 gates cannot fail on the defects they name" (AC-131's seed window and
AC-134's single-layer store). Both were fixed at `54c1e51` and both fixes were verified by
re-running the original mutations, which now redden. No follow-up issue is owed. Recording the
withdrawal rather than deleting the item, so the campaign's audit trail shows the finding was
closed by repair and not by reclassification.

---

*VIGIL — reproduction before blame; counterfactual before conclusion. Verify · Isolate ·
Graph · Intervene · Learn.*
