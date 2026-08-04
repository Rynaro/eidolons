# Critique — crystalium-rrf-fusion-38 (spec revision 1.0.0)

critic:   vigil (independent; plan maker: vivi — recorded via `ramza-gate critic`)
date:     2026-08-03
inputs:   spec.md (rev 1.0.0, proposed) · spec.criteria.md (frozen,
          sha256 132b25df1392456ccce6a261bad62003c1177859ea650417f6fed1a034f9d119 —
          **re-hashed independently, matches exactly**) ·
          .spectra/plans/crystalium-rrf-fusion-38.state.json
target:   /home/rynaro/workspace/oss/agents/crystalium @ ef42967 (v1.9.0, clean — verified)

**Verdict:** ramza-lint clean (exit 0, full tier) · ramza-ears-lint clean (31/31, exit 0) ·
refine rubric: **fail** (cycle 1, total 3.4, min 2 — dims clarity 4 / completeness 3 /
actionability 4 / efficiency 4 / **testability 2**; computed by `ramza-score --rubric refine`,
appended to state.gates[] and ramza-calibration.jsonl at 2026-08-03T18:15:11Z, exit 1)

**Overall: REVISE.** Six BLOCKING findings (F1–F6), eleven ADVISORY (A-1..A-11).

The document is unusually strong on anchor discipline — every `file:line` I re-read at
`ef42967` was accurate, and both self-declared evidence closures (G-4, G-5) verify. The
failure is concentrated in one place, and it is the place this project's doctrine says to
look: **four of the thirty-one criteria, including the change's own thesis test, cannot
fail on the defect they name.** Separately, the single measurement that rejects H-A and
grounds the two headline recommendations (DP-1(b), DP-2(a)) **inverts** under the very
correction §Evidence Gaps G-1 declares it robust to.

Nothing here says the recommended design is wrong. It says the evidence offered for it does
not currently support it, and the gates written to protect it cannot currently detect its
absence.

## What was independently checked, not trusted

Re-read at `ef42967`, confirmed exact: `rrf_merge_scored` retrieve.py:61-88 (unweighted
`Σ 1/(60+rank)`, `sorted(..., key=kv[1], reverse=True)` — insertion-order tie-break);
`rrf_merge` :91-113 delegating to it; `FETCH_WIDTH_FLOOR = 10` :53; `fetch_width` :374;
`seed_ids = dense_ranking[:fetch_width]` :377; `completion_seeds = seed_ids or
sparse_ranking[:fetch_width]` :397; `sorted(walked.items(), key=lambda kv: -kv[1])` :405
(score-only, no id tiebreak — D5's premise holds); fusion :415-426 with `graph_ranking`
always appended and `completion_ranking` only when non-empty.

Claims verified **correct**:
- **G-4 closure** — `_from_dict`'s `float_field` allowlist is real (config.py:376; `bool_field`
  :342, carrying `recall_relevance_primary`). The silent-YAML-failure hazard and AC-127's
  both-sources parameterisation are justified.
- **G-5 closure** — `schemas/recall-result.v1.json` is `additionalProperties: false` at top
  level, and its `explain` property is `additionalProperties: true` with the quoted
  "intentionally loose" description. S-6's "no schema edit required" is right.
- **D3's FTS5 premise** — `_fts5_query` (relational.py:189-201) quotes each token and its own
  docstring says "implicit-AND across terms". Conjunctive semantics confirmed; `n_sparse` is
  a true match count, not an OR-flood.
- **DP-5's premise** — `evals/retrieval_gate.py` commits every crystal to `episodic` (:88-102);
  `_QUERY` is the 5-token "acme login session token rotation" (:28); corpus = hub + 2 spokes +
  2 noise + 24 `_DISTRACTORS` + 2 ctx = **31**. No shipped gate can observe a cross-layer axis.
- **DP-7/AC-128's premise** — server.py:186-197 does read "raw hybrid-retrieval RRF value".
- **#36 AC-031's fixture** — verbatim confirmed: `_neighbor_expand`/`_decaying_walk` return `[]`
  / `{}` once `len(seed_ids) > 3`, so at `fetch_width = 10` the fusion under test really is
  two-arm and the criterion really is membership-only (`assert "fresh" in ids`,
  test_recall_starvation.py:965-1021). The spec's central indictment of the shipped gate is fair.
- **`Config.__new__` helper count = 5**, at exactly the five cited files/lines
  (test_aetheryte.py:42, test_composer.py:82, test_dream_worker.py:34,
  test_dream_scheduler.py:41, test_recall_starvation.py:82). #36's C-8 count of four was
  indeed stale. The spec's correction is right.
- **`_FALLBACK_VERSION = "1.8.0"`** (crystalium/__init__.py:8) — stale as claimed.
- **AC-121's count is satisfiable** — test_recall_starvation.py contains exactly **32** test
  functions. I initially suspected an 11-criteria hole (only 21 distinct `AC-0NN` strings appear
  in the file) and **retracted it**: all eleven unannotated criteria (AC-011..014, 018, 019,
  023, 024, 026, 027, 030) name tests that are PRESENT in the file. No hole. See A-7 for the
  residue.
- **Scope hygiene** — `storage/graph.py` is correctly OUT of the declared globs (D5 is
  consumer-side only, as claimed); `evals/retrieval_gate.py` correctly OUT (AC-124 re-runs it,
  never edits it).

## Findings (severity-tagged)

### F1 — BLOCKING: the F1-collapse measurement that rejects H-A inverts under the spec's own G-1 correction

Anchors: §D2 table ("static `w_graph = 0.35, w_comp = 0.25` → 0, **25, 26** → F1 **0.1538**");
§DP-1 Recommendation ("(a) is measurably wrong (§D2 table: eval-gate F1 0.4615 -> 0.1538)");
§Rejected Alternatives H-A ("Rejected on measurement, not taste"); §Evidence Gaps G-1
("Directional conclusions (static down-weighting collapses multi-hop; family-merge at
`w_derived=1.0` does not) **are robust to that correction**").

G-1 states the dense-arm inference is weak and that the spokes are "**probably** present near
the bottom" of `dense_ranking`, because `dense_search` is called with `k = candidate_k = 30`
against a 31-crystal corpus. I modelled the shipped `retrieval_gate.py` topology (verified
from source: `sparse=[hub]`, `graph=[spoke1]`, `completion=[spoke1, spoke2]`, relevant =
hub+spoke1+spoke2, retrieved = top-10) under both readings:

| scheme | spokes ABSENT from dense (spec's model) | spokes at dense rank 25/26 | 27/28 | 29/30 |
|---|---|---|---|---|
| unweighted (today) | ranks 0,1,3 · **F1 0.4615** | 1,0,2 · 0.4615 | 1,0,2 · 0.4615 | 1,0,2 · 0.4615 |
| static 0.5 / 0.5 | 0,1,30 · **F1 0.3077** | 0,1,2 · **0.4615** | 0,1,2 · **0.4615** | 0,1,2 · **0.4615** |
| static 0.35 / 0.25 | 0,29,30 · **F1 0.1538** | 0,1,4 · **0.4615** | 0,1,5 · **0.4615** | 0,1,7 · **0.4615** |
| family-merge w=1.0 | 0,1,3 · 0.4615 | 0,1,2 · 0.4615 | 0,1,2 · 0.4615 | 0,1,2 · 0.4615 |

The mechanism is arithmetic: a spoke with a dense term at rank 29 carries `1/89 = 0.011236`
that static down-weighting does **not** touch (`w_dense = 1.0`), while every distractor it
competes with sits in the narrow band `1/62 … 1/90` = `[0.0111, 0.0161]`. Down-weighting the
derived arms therefore cannot push a spoke out of the top 10 — it only has to beat a
dense-rank-7 distractor at `0.014925`, and `0.35/61 + 0.25/61 + 1/89 = 0.021072` does that
comfortably.

**Consequence.** The "67 % modelled collapse" is an artifact of the one inference the author
flagged as weak, and G-1's explicit robustness claim is false for the first of its two
directional conclusions. H-A's `correctness 3` explore score, DP-1's rejection of (a), and
DP-2(a)'s "zero modelled multi-hop cost" framing all rest on it. FORGE would rule DP-1 and
DP-2 on an inverted number, and **no criterion in AC-101..AC-131 would ever discover this** —
AC-124 measures only the shipped design's non-inferiority, never the H-A arm.

(The sketch-closure conclusions are unaffected: the issue's sketch fixes T at dense rank 4 and
the competitors at 1–3 by construction, so G-1 does not reach them. Family-merge still closes
the sketch under both readings. The defect is in the *rejection* evidence, not the *selection*
evidence.)

### F2 — BLOCKING: attack E is a tautology at the layer it would naturally run (AC-130)

Anchors: §Test Plan Layer 5 row E ("set `FETCH_WIDTH_FLOOR = 1000` with the fix present |
must redden: **nothing** — proves AC-101 is not floor-borne"); "Attack **E** is the
load-bearing one for this change's thesis"; AC-130 ("shall turn every attack's named criterion
red **except attack E, whose named outcome is that nothing changes**"); §Test Plan Layer 2
(AC-101 runs on `MagicMock` vector and graph stores); spec.criteria.md Terminology ("graph and
completion arms that are NON-EMPTY at the fetch width actually used and that return **those
same three competitors**").

`FETCH_WIDTH_FLOOR` reaches the world through exactly one channel: it sizes
`seed_ids = prelim[:fetch_width]`. A mocked graph store that returns the same three
competitors regardless of its `seed_ids` argument — which is what the Terminology block's
non-emptiness clause effectively mandates — makes widening the floor to 1000 a **no-op by
construction**. Attack E is then green whether the fusion fix works, is absent, or is entirely
floor-borne. It carries zero bits.

The alternative shape is worse: a seed-count-sensitive mock (the `len(seed_ids) <= 3` idiom
#36's AC-031 used, verified verbatim) empties the arms at floor 1000 and thereby violates the
same Terminology clause AC-101 depends on.

This is the exact species this repo's doctrine names — a gate that cannot fail on the defect
it names — sitting on the criterion the spec itself calls the thesis test. AC-130 currently
requires the checker to record a PASS that is unfalsifiable.

### F3 — BLOCKING: AC-131's ability to go RED at ef42967 is a function of unspecified fixture id strings, not of the defect

Anchors: AC-131 ("two separate processes started with different `PYTHONHASHSEED` values …
spawning subprocesses with `PYTHONHASHSEED` **0 and 1** — **must be demonstrated RED at
`ef42967`**"); §P3's own evidence (five UUID-shaped ids, four seeds); spec.criteria.md
Terminology ("graph and completion arms … return **those same three competitors**").

Measured directly (set iteration order, CPython, ten seeds each):

| id style | n=2 | n=3 | n=4 | n=5 |
|---|---|---|---|---|
| `n1,n2,…` | seed0 **==** seed1 | differ | differ | differ |
| `target,n1,n2,…` | differ | differ | differ | differ |
| UUID-shaped | seed0 **==** seed1 | seed0 **==** seed1 | differ | differ |

The sketch fixture's derived arms hold **exactly three** ids by the criteria's own Terminology
clause. With UUID-shaped ids at n=3 — crystalium's actual id shape — `PYTHONHASHSEED=0` and
`PYTHONHASHSEED=1` produce the **identical** order and the test is **GREEN at `ef42967`**. The
criterion's mandatory RED-first demonstration then fails for a reason unrelated to the defect,
and the likeliest repair under time pressure is to weaken the criterion.

§P3's supporting evidence used five ids and four seeds precisely because two ids and two seeds
do not discriminate; AC-131 pins the two-seed variant and leaves the arm cardinality and id
shape unstated.

### F4 — BLOCKING: AC-104 and AC-105 are contradictory as written; AC-104 passes only by luck of the shipped corpus

Anchors: AC-104 ("**GIVEN any ranking set** in which every arm weight is 1.0 … THEN … produce
the **same id sequence** that `rrf_merge_scored` produces"); AC-105 (weighted merge breaks exact
ties **by id ascending**); §D1 ("`rrf_merge` and `rrf_merge_scored` are **not modified**. They
keep their documented **insertion-order tie-break**").

D1 deliberately gives the two functions different tie-break rules, so AC-104's universally
quantified THEN is refutable in two lines:

```
rankings = [["b"], ["a"]]        # both score 1/61 — exact tie
rrf_merge_scored           -> ['b', 'a']      (insertion order)
weighted, all weights 1.0  -> ['a', 'b']      (id ascending, AC-105)
```

I ran AC-104's actual VERIFY scope — the five fixtures of
`test_rrf.py::test_rrf_merge_scored_matches_rrf_merge`, over `k_rrf` 1 and 60 — and it
**passes, 0/10 disagreements**. It passes because every tie in that corpus happens to be
insertion-order-concordant with id-ascending order (`a,b,c`; `shared,exclusive_a,exclusive_b`).
`test_three_rankings_fused`'s own docstring flags one of them: "a == b == c … order
deterministic by dict insertion."

So AC-104 is green today, contradicts AC-105 in principle, and goes red the moment S-2's
mandate to "extend `test_rrf.py` with a new class" adds one discordant fixture. Two frozen
criteria that contradict each other require an amend, not an implementer's judgement call. The
reduction property the spec actually wants — that weighting is a strict generalisation — is
true of **scores**, not of **order under ties**.

### F5 — BLOCKING: a defect that passes all 31 criteria — D3's selectivity mixes a search-space-local numerator with a corpus-global denominator

Anchors: §D3 ("`N` = total crystals in the store"; `cap = candidate_k * len(target_layers)`);
retrieve.py:314 (`target_layers = layers if layers else _ALL_LAYERS`); the `layers` parameter
is first-class and caller-facing in the `crystalium.recall` manifest.

`cap` is correctly made search-space-local by multiplying through `len(target_layers)` — the
author saw the layer-multiplicity issue. `N` is not. `n_sparse` counts matches **within the
layers actually searched**; `N` counts **the whole store**. They agree only when `layers=None`.

| case | n_sparse | N (global) | resolved w_sparse | true in-search-space selectivity |
|---|---|---|---|---|
| `layers=None`, distinctive query | 1 | 10005 | 1.9999 | 0.9999 ✓ |
| `layers=['procedural']`, matches **all 5** procedural crystals | 5 | 10005 | **1.9995** | **0.0000** ✗ |
| `layers=['semantic']`, matches **all 20** semantic crystals | 20 | 10020 | **1.9980** | **0.0000** ✗ |

A query that matched **100 % of the layer it searched** — maximally non-selective — receives a
near-maximal sparse boost, because ten thousand crystals it never looked at inflate the
denominator. The censoring branch does not save it (`n_sparse = 5 < cap = 30`).

Every criterion in the set survives this. AC-109 asks only for `> 1.0`; AC-110 for the censored
case; AC-111 for non-raising; AC-112 only bounds the interval `[1, 1+alpha]` — an inverted
weight is inside it. AC-126's multi-layer fixture reports per-layer sparse rank; it never
exercises a **layer-filtered** recall's weight. This is precisely the "is there a defect that
passes all 31 ACs" case, and the answer is yes.

Note this is also the mirror image of the objection the spec raises against DP-3(b) ("the
denominator is a fetch artifact, not a corpus property"). (b)'s denominator was scrutinised;
(a)'s was not.

### F6 — BLOCKING: DP-4's mechanical contingency omits the non-regression gates

Anchors: §DP-4 ("**Recommendation (a), with a mechanical contingency:** default ON **iff**
AC-124 … and AC-125 … are green. If either is red the default flips to OFF automatically and
the change returns to FORGE"); §Risks R-6; AC-121/AC-122/AC-123.

The contingency is named as mechanical and binds only the two forward-looking gates. A red
AC-121 (all 32 frozen #36 criteria), AC-122 (the F-V1 four-cell probe) or AC-123 (`make test`)
is a strictly more serious signal than a red AC-124, and the rule is silent on it. As written
an implementer can observe AC-121 red with AC-124/125 green and have no mechanical instruction
— which is how a "mechanical, never LLM-discretionary" gate quietly becomes discretionary.

The exposure is real rather than theoretical: DP-4(a) ships weighted fusion **default ON**, and
D7 subsumes it under `recall_relevance_primary`, which #36's flag-on tests set to `True`. Every
#36 flag-on criterion therefore runs against a changed fusion, and the spec nowhere analyses
whether any of their fused orders move. (I checked the two that would hurt most — #36 AC-008
and AC-009 assert set membership and record count, not fused order, and one passes
`graph_store=None` — so they are safe. That is a spot check, not the analysis.)

## Advisory findings

- **A-1 — AC-124 guards one of the eval gate's two axes.** It pins `multihop_f1.completion` and
  `completion_pass`; `context_rank` and `context_pass` are unguarded. `w_sparse ≈ 1.97` roughly
  doubles the hub's sparse term while `ctx_match` ("acme login session token guide") does not
  match the conjunctive query at all and so gains nothing — `context_rank` can degrade silently.
  `gate_pass = (completion_ok and graph_ok) or context_ok` will not surface it. Practical risk
  is low only because `context_pass` is already `false` at baseline.
- **A-2 — AC-119's reference value is the artifact P3 proves does not exist.** "an order captured
  from `ef42967`" is, for any run whose graph arm derives from a `set`, hash-seed-dependent —
  the spec's own thesis. Compounding it, D5's determinism fixes are deliberately **outside** the
  flag (§Rollback), so the flag-off path's graph arm is `sorted()` after the change and the
  captured order is not. Survivable only if the fixture's mocked arms are already id-ascending
  with distinct completion scores; the criterion does not say so.
- **A-3 — the Release Plan invites an edit outside the declared scope.** "`_FALLBACK_VERSION` is
  *already* stale at `"1.8.0"` … a one-line correction is welcome on this touch." I checked all
  12 globs: `mcp-server/src/crystalium/__init__.py` matches **none** of them. Accepting the
  invitation trips `ramza-drift`. Either add the glob or withdraw the invitation.
- **A-4 — "`Aetheryte(` sites = exactly 2" is unqualified.** There are **10**: 2 production
  (`server.py:548`, `__main__.py:340`) and 8 in tests (test_context_match.py:47,
  test_diagnosability.py:429/462, test_aetheryte.py:146/358, test_recall_starvation.py:175/213/1004).
  The intent — production sites needing the sentinel wiring — is right; the Gate-record line as
  written will mislead a grep-checking implementer.
- **A-5 — AC-122 says four cells, spec.md says eight.** AC-122 scopes the probe to the flag-on
  column at `k ∈ {1,3,5,10}` (four cells, internally consistent); spec.md §Acceptance Criteria
  describes it as "`k` over `{1,3,5,10}` x flag on/off" (eight). The frozen file governs; the
  summary should be corrected to match rather than the reverse.
- **A-6 — DP-3's cost note undercounts and overlooks two existing helpers.** `diagnostics_summary`
  issues **five** aggregates (relational.py:996, 998, 1001, 1005, 1008), not four. More usefully,
  `count_for_export` (:926-977) already performs a single bounded `SELECT count(*) FROM crystals
  WHERE …` and `count_active_by_scope_key` (:1019) exists — which materially weakens the
  "(a) adds a public method to `RelationalStore`" objection the DP asks FORGE to weigh.
- **A-7 — AC-121's VERIFY names one file for a 32-criteria claim.** #36's AC-019 additionally
  requires `test_composer.py::TestTotalCap` and AC-023 additionally requires
  `test_diagnosability.py::TestSummaryQualityGate`. AC-123 (`make test`) backstops both, so
  there is no coverage hole — but AC-121's own VERIFY cannot discharge AC-121's own THEN.
- **A-8 — no criterion requires correcting the F-V6 record.** `evals/BENCH-NOTES.md` is in the
  declared scope and §P3 cites F-V6's `context_rank.both = 4` vs `5` as the witnessed symptom
  that P3 explains. Nothing in AC-101..AC-131 requires the committed non-reproducible number to
  be corrected or annotated, so the change that explains the defect leaves its artifact standing.
- **A-9 — AC-108's WHERE clause is inoperative and the integration identity is unpinned.** The
  WHERE names `Config.recall_completion`, but the WHEN and VERIFY target
  `weighted_rrf_merge_scored`, a pure function with no Config access. Separately, §D2's identity
  claim and R-2's mitigation ("bounds it to `recall_completion=True`") are about the *shipped
  path*, which also carries D3's boost, D4's reseeding and D5's re-ordering — no criterion pins
  the path-level identity those two passages lean on.
- **A-10 — the `fetch_width` quotation drops its gate.** §"What v1.9.0 shipped" quotes
  `fetch_width = max(k, FETCH_WIDTH_FLOOR)` (retrieve.py:53,374); the shipped line is
  `max(k, FETCH_WIDTH_FLOOR) if self.recall_relevance_primary else k`. This matters for AC-120's
  reasoning: with `recall_relevance_primary=False` the seed set also narrows to `[:k]`, so that
  path differs from the weighted path in two ways, not one.
- **A-11 — AC-104's GIVEN is unverifiable at the function boundary.** "with at most one derived
  arm present" is a property of the caller's arm construction; `weighted_rrf_merge_scored` takes
  `list[tuple[list[str], float]]` and has no notion of a derived arm.

## Per-dimension findings (refine rubric, cycle 1 — tool verdict: fail, min 2)

- **clarity (4/5)** — Anchor discipline is excellent; every `file:line` I re-read was accurate,
  and D0's numbered pipeline plus invariant I-1 make the construction order unambiguous. Docked
  for A-4 (unqualified "exactly 2"), A-5 (four cells vs eight), A-6 (five aggregates, not four)
  and A-10 (a quoted line missing its gate).
- **completeness (3/5)** — Scope, non-scope, deferred items, rejected alternatives, risks and
  rollback are all present and genuinely reasoned. Docked to the bar by F1 (the rejection
  evidence for H-A does not survive the author's own stated correction), F5 (a live defect no
  criterion can observe), F6 (the contingency omits the non-regression gates) and A-1.
- **actionability (4/5)** — S-1..S-7 carry timeboxes, executor tiers, output contracts and
  criteria maps; "land S-1 first and alone" is exactly right, and the `Config.__new__` audit
  (5, not 4) is the kind of correction that saves an implementer a day. Docked for A-3 (a
  sanctioned edit that trips the drift gate) and for F2/F3 leaving the implementer to discover
  at execution time that two mandatory RED demonstrations may not be obtainable.
- **efficiency (4/5)** — No ceremony. Templates reused rather than reinvented, DP-6 deferred
  with a real argument rather than punted, 12 scope globs proportionate to 7 stories, and the
  decision to leave `rrf_merge`/`rrf_merge_scored` untouched buys the non-regression signal
  cheaply.
- **testability (2/5)** — **The failing axis.** Four criteria cannot fail on the defect they
  name: AC-130/attack E is a tautology under the fixture shape its own Terminology block
  mandates (F2); AC-131's RED-first demonstration is decided by unspecified fixture id strings
  and is green at `ef42967` for the most likely fixture (F3); AC-104 contradicts AC-105 and
  passes only by corpus luck (F4); AC-119's oracle is the non-deterministic artifact P3 exists
  to prove non-deterministic (A-2). AC-103, AC-127 and AC-129 are, by contrast, model gates —
  the problem is local, not systemic.

## Prescriptions (for the author's next Refine, in order)

1. **§Evidence Gaps G-1 + §D2 + §DP-1 + §Rejected Alternatives H-A** — strike the claim that the
   directional conclusions are robust to the dense-arm correction; it is false for the
   down-weighting arm. Either (i) re-derive the §D2 table with the spokes modelled at their
   probable dense ranks and re-score H-A's `correctness` accordingly, or (ii) — preferred, and
   cheap — **measure it**: the H-A arm is a two-constant change to a config the existing
   `retrieval-gate` already runs, so land an actual `w_graph=0.35/w_comp=0.25` measurement
   before FORGE rules DP-1/DP-2 rather than a model of one.
2. **AC-130 / §Test Plan Layer 5 row E** — amend so attack E names the layer it runs at, and
   make that a layer where `FETCH_WIDTH_FLOOR` is load-bearing: the Layer-3 real-stack probe or
   the AC-125 fusion eval gate with a real `GraphStore`. Add the falsifiability check
   explicitly — "with the fusion fix reverted, attack E must change AC-101's verdict" — so the
   attack is demonstrated to carry information rather than assumed to.
3. **AC-131** — amend to (a) mandate a derived-arm cardinality ≥ 4 distinct ids **and** state
   the id shape, and (b) require the RED demonstration to name the observed disagreeing seed
   pair from a set (e.g. 0..4) rather than pinning seeds 0 and 1. Measured evidence for the
   necessity is in F3's table.
4. **AC-104** — amend the THEN from "the same id sequence" to "the same `(id, score)` multiset,
   and the same id sequence **on inputs with no exact score tie**", or assert score equality only.
   As written it contradicts AC-105 and D1's deliberate divergence. Drop or restate the
   unverifiable "at most one derived arm present" clause (A-11).
5. **§D3 + a new criterion** — make the selectivity denominator search-space-local
   (`N` counted over `target_layers`, matching how `cap` already multiplies through
   `len(target_layers)`), or state and defend the global-`N` choice explicitly. Add a criterion
   that a query matching every crystal in the searched layer resolves `w_sparse` to 1.0 — the
   current set cannot distinguish that case from maximal selectivity (F5).
6. **§DP-4** — extend the mechanical contingency to "AC-121, AC-122, AC-123, AC-124 and AC-125
   green", so a non-regression red has a rule. Add the missing analysis of whether weighted
   fusion default-ON moves any #36 flag-on fused order.
7. **AC-119** — state the reference-capture conditions (arms id-ascending, completion scores
   distinct) or re-scope the THEN to "the fused id order `ef42967` produces **for id-sorted
   arms**". Cross-reference §Rollback's decision to keep D5 outside the flag, which is what
   creates the tension (A-2).
8. **AC-124** — add `context_rank` / `context_pass` to the guarded axes, or record explicitly
   that they are deliberately unguarded and why (A-1).
9. **§Release Plan** — either add `mcp-server/src/crystalium/__init__.py` to the declared scope
   and re-run `ramza-drift --declare`, or withdraw the `_FALLBACK_VERSION` invitation (A-3).
10. **Gate record + S-5** — restate as "production `Aetheryte(` construction sites = 2 (of 10
    total; 8 are test sites)" (A-4). Correct "four aggregates" to five and note
    `count_for_export` / `count_active_by_scope_key` already exist, since that changes the
    cost balance FORGE is being asked to weigh in DP-3 (A-6).
11. **spec.md §Acceptance Criteria** — reconcile the "four-cell probe" description with AC-122's
    frozen text (A-5); fix the `fetch_width` quotation to include its
    `if self.recall_relevance_primary else k` gate (A-10); add the AC-108 WHERE-clause
    correction and a path-level identity criterion if R-2's mitigation is to hold (A-9).
12. **AC-121** — either extend the VERIFY to name `test_composer.py::TestTotalCap` and
    `test_diagnosability.py::TestSummaryQualityGate`, or add "plus AC-123" to it (A-7). Consider
    a criterion requiring the F-V6 figure in `evals/BENCH-NOTES.md` to be corrected or annotated
    now that P3 supplies the mechanism (A-8).

Any change to AC-101..AC-131 arising from 2–5, 7, 8, 11 or 12 requires
`ramza-freeze --amend --reason "<why>"` — the frozen hash
`132b25df1392456ccce6a261bad62003c1177859ea650417f6fed1a034f9d119` is recorded in the plan
state and a silent edit is tamper evidence.

## Gate record (this critique)

| gate | result |
|---|---|
| frozen-criteria hash re-verified | `sha256:132b25df…f9d119` — **matches** state + brief |
| `ramza-lint --plan spec.md --state …` | **clean**, exit 0 (tier full) — re-run, not trusted |
| `ramza-ears-lint spec.criteria.md` | **clean**, 31 criteria, exit 0 — re-run, not trusted |
| `ramza-score --rubric refine --cycle 1` | **fail** — total 3.4, min 2 (clarity 4, completeness 3, actionability 4, efficiency 4, testability 2), exit 1 |
| `ramza-gate critic --author vivi --checker vigil` | **OK** — recorded (maker ≠ checker satisfied) |
| verdict | **REVISE** — 6 blocking, 11 advisory |

Read-only throughout: no crystalium file was modified, and no `.spectra/` artifact other than
this critique, `crystalium-rrf-fusion-38.state.json` (gates[] + critic block, via the tools)
and `ramza-calibration.jsonl` was written.

---

*vigil — independent critique, RAMZA critic skill (maker≠checker)*

---

# Critique — ROUND 2 (delta re-critique of spec revision 1.1.0)

critic:   vigil (independent; plan maker: vivi — re-recorded via `ramza-gate critic`)
date:     2026-08-03
inputs:   spec.md (rev 1.1.0, + `## Refine record`) · spec.criteria.md (frozen, **amended once**,
          39 criteria, sha256 7e4c0807d7684ad821d00f39c98d562d1acd453f9147f4dc9e19918f76d64802 —
          **re-hashed independently, matches**) · plan state (refine_cycles 1)
target:   crystalium @ ef42967 — re-verified clean; no code touched by either round

**Verdict:** ramza-lint clean (exit 0, full tier) · ramza-ears-lint clean (**39/39**, exit 0) ·
refine rubric: **fail** (cycle 2, total 3.8, min 3 — clarity 4 / completeness 4 / actionability 4 /
efficiency 4 / **testability 3**; bar at cycle ≥ 2 is every dimension ≥ 4)

**Overall: REVISE (round 2) — but for a materially different reason than round 1.**
**All six blocking findings F1–F6 are genuinely CLOSED**, verified by re-measurement rather than
accepted on the author's word, and all eleven advisories are taken. The revision is a model of
how to answer a critique: F1 was reproduced cell-for-cell *before* being accepted, and F3 records
a reproduction *disagreement* with me rather than papering over it.

REVISE is driven entirely by **new attack surface**: two blocking defects that the round-1 criteria
could not have contained because they live in the round-2 additions and in the part of F5 the fix
did not reach. Neither is a regression; both are cheap to close.

**Amend trail: LEGAL.** One `ramza-freeze --amend` with a substantive `--reason` (854 chars, maps
each edit to the finding that caused it); hash chain `132b25df… -> 7e4c0807…` recorded in
`state.amendments[0]`; all 31 original IDs verified still present; 39 blocks total; **none
removed**. See B-1 for the one integrity defect in its *self-description*.

## Per-finding closure verdicts (verified, not accepted)

| # | verdict | what I checked |
|---|---|---|
| **F1** | **CLOSED** | §D2 now reads "That claim is **withdrawn**" (spec.md:236-238) and carries all four of my columns with my exact arithmetic (`1/89 = 0.011236`, `1/67 = 0.014925`, `0.021072`, band `[1/90, 1/62]`). G-1's robustness sentence is struck and replaced with "They were not." H-A re-scored 61.5 → 72.5 (recorded in `state.gates[]`). DP-1 re-opened with a binding real-stack measurement order. **No residual text leans on 0.1538 as a live claim** — it survives only as the explicitly-labelled "rev 1.0.0's model" column. |
| **F2** | **CLOSED as stated** | AC-130 no longer carries attack E; AC-138 hosts it at the AC-125 real-`GraphStore` layer, and AC-139 is a real falsifiability precondition. The clause "If AC-139 cannot go green, the fixture is seed-insensitive and AC-138 must be moved, **not weakened**" is the correct doctrine and closes the exact hole I named. **But the thesis question attack E existed to answer is now unanswered — see G-1.** |
| **F3** | **CLOSED** | AC-131 now mandates ≥ 4 distinct UUID-shaped derived-arm ids, seeds 0..4, and a recorded disagreeing seed pair. I measured the prescription's discriminating power over 40 randomly-drawn UUID id-sets per size: **0/40 at n=4, 0/40 at n=5, 0/40 at n=6** produced all-five-seeds agreement. The RED-first demonstration is now decided by the defect, not by fixture strings. The recorded n=3 disagreement between our two measurements is handled honestly and is itself the right evidence for the ≥ 4 floor. |
| **F4** | **CLOSED** | I attacked the split and could not break it. AC-104's `(id, score)` multiset equality is *exact* under unit weights (`w * x` with `w == 1.0` is identity in IEEE-754, and the fixed arm order preserves summation order), and `[["b"],["a"]]` is now a mandated fixture. AC-132's tie-free restriction is the precise domain where the two tie-break rules provably cannot diverge, with tie-freeness mechanically asserted in the fixture builder. One unpinned edge remains — B-4. |
| **F5** | **CLOSED on the layer axis** | §D3's denominator is now counted over `target_layers`, matching how `cap` already multiplies through `len(target_layers)`. AC-134 carries my exact inverted-case figure (`w_sparse = 1.9995` for 5 matched procedural crystals in a 10 005-crystal store) and is a genuine RED-on-inversion oracle: under the corrected denominator a layer-saturating query gives `1 - 5/5 = 0 ⇒ w_sparse = 1.0` exactly. **The same numerator/denominator-population defect survives on the status axis — see G-2.** |
| **F6** | **CLOSED** | AC-136 binds the flag default to all five of AC-121/122/123/124/125 mechanically ("a `True` default alongside any red verdict blocks the tag"), which is exactly the prescription. Residual: the criterion added for A-1 is not itself in the list — B-2. |

Advisories A-1..A-11: all taken. Spot-verified against source: A-3 (`__init__.py` now in scope —
13 globs, and I re-ran full coverage: **0 of the 16 files the 39 ACs require is uncovered**);
A-4 ("2 production of 10 total", correct); A-6 (five aggregates, and `count_for_export` :926-977
and `count_active_by_scope_key` :1019 now named — the correction that weakens DP-3's own
objection); A-10 (`fetch_width` quotation now carries `if self.recall_relevance_primary else k`).

## NEW blocking findings

### G-1 — BLOCKING: the guard-vs-cure question now has no criterion at all

Anchors: AC-138/AC-139 (both raise `FETCH_WIDTH_FLOOR` 10 → 1000); AC-125 (the host gate, which
calls recall at k=10); retrieve.py:374 (`fetch_width = max(k, FETCH_WIDTH_FLOOR) if
self.recall_relevance_primary else k`); §"What v1.9.0 shipped, and why it is not a fix".

The floor's entire causal channel is `fetch_width = max(k, FLOOR)`. Computed across the k values
this change cares about:

| k | floor = 1 | floor = 10 (shipped) | floor = 1000 | lowering the floor matters? |
|---|---|---|---|---|
| 1 | 1 | 10 | 1000 | **yes** |
| 3 | 3 | 10 | 1000 | **yes** |
| 5 | 5 | 10 | 1000 | **yes** |
| 10 | 10 | 10 | 1000 | **no — inert** |
| 25 | 25 | 25 | 1000 | **no — inert** |

The v1.9.0 floor is load-bearing **only at k < 10** — precisely the regime DP-R1 built it for
(#36 F-V1's k=1 and k=3 cells, where the fresh crystal was *not returned at all*). "Is AC-101
floor-borne?" is therefore a question about floor **removal at small k**. AC-138 and AC-139 both
raise the floor, at a gate that runs k=10, where lowering it is inert. The pair is now
falsifiable (F2 closed) but it interrogates the one direction that cannot answer the change's
central claim.

Concretely: if the fix still needs the v1.9.0 floor at k=1/k=3, this change is an improvement
*layered on* the guard rather than the replacement it declares itself to be — and **no criterion
among the 39 can discover that.** The spec's own §"What v1.9.0 shipped" section stakes the whole
change on the opposite.

*Prescription:* add AC-140 — with `FETCH_WIDTH_FLOOR` set to 1, AC-102's `k ∈ {1, 3, 5}` cells
must still return the target at `result.records[0].id`. That is a two-line parameterisation of a
fixture AC-102 already builds, and it is the direct test of "cure, not guard." A red AC-140 is not
a defect in the change — it is the single most decision-relevant fact FORGE could receive on DP-1.

### G-2 — BLOCKING: a defect that passes all 39 — the selectivity denominator's *status* axis

Anchors: relational.py:493-541 (`bm25_search` — **no status predicate** in either branch);
relational.py:75-88 (FTS triggers index every row, with no status guard); config.py:225
(`recall_active_only: bool = True` — "W6 gate PASS + correctness"); retrieve.py:478-492 (the
`_is_active` filter), which sits **after** the fusion at :415-426.

F5 corrected the denominator's *layer* population. Its *status* population is still unspecified,
and the two ends are drawn from different ones:

- **Numerator.** `n_sparse = len(sparse_ranking)` is built from `bm25_search`, which applies no
  status filter, over an FTS index that carries deprecated and superseded rows. So `n_sparse`
  counts inactive crystals. The `recall_active_only` defence removes them only at :478, long
  after the weight would be resolved.
- **Denominator.** "the count of crystals in the searched layers" (AC-109/112/134) does not say
  which statuses. The natural implementation counts **active** crystals — the existing helper is
  literally named `count_active_by_scope_key`, and `recall_active_only` defaults `True`.

The result is a silent, monotone decay of the feature:

```
selectivity = 1 - n_sparse / N_L      numerator: all statuses
                                      denominator: active only  ⇒ ratio inflated
                                                                ⇒ selectivity depressed
                                                                ⇒ w_sparse → 1.0
```

and in the degenerate case `n_sparse > N_L` the clamp pins `w_sparse = 1.0` outright — the boost
disappears with no error, no log line and no explain anomaly. Under CRYSTALIUM's P0-5
("write-new, never hard-delete") deprecated rows accumulate **by design**, so the headline feature
degrades as a store ages, and looks identical to healthy throughout.

Every criterion survives it: AC-109's "far below" holds on a fresh store; AC-134's
layer-saturating case is all-active so it still resolves 1.0; AC-112 is a bound and the depressed
value is inside it; AC-117 surfaces the denominator but nothing asserts its population. **Every
fixture in the 39 is a fresh store.** This is the same species as F5 — numerator and denominator
drawn from different populations — along the axis the F5 repair did not reach.

*Prescription:* state the status population explicitly in §D3 (numerator and denominator must
agree; the cheaper and more honest choice is *all statuses*, matching what `bm25_search` actually
returns), and add a criterion: given a searched layer holding N active plus M deprecated crystals
where the query matches every one of them, `w_sparse` shall resolve to exactly 1.0. That fixture
goes red on the mixed-population implementation and is the only thing in the set that can.

## NEW advisory findings

- **B-1 — the criteria file's change manifest understates its own diff.** The header (line 11-12)
  declares "AC-104/108/119/121/124/130/131 amended, AC-132..AC-139 added, none removed". I verified
  *none removed* and *39 total* mechanically, and both are true. But at least ten further blocks
  changed: **AC-101** (VERIFY gained the AC-138/139 delegation), **AC-109** ("corpus size" →
  "count of crystals in the searched layers"), **AC-111** ("corpus sizes" → "searched-layer
  sizes"), **AC-112** (GIVEN population + a new VERIFY note), **AC-117**, **AC-120**, **AC-122**,
  **AC-125**, **AC-127**, **AC-129** — and the **Terminology block** lost its round-1 sentence
  recording that #36's AC-031 fixture empties both graph helpers at `fetch_width = 10`. Every one
  of those edits is an *improvement* and most implement F5 or an advisory, so this is a manifest
  defect, not tampering. It still matters: the manifest is the surface `ramza-freeze` exists to
  make trustworthy, and a reader diffing the two frozen versions would read AC-109's changed GIVEN
  as an undeclared edit. Restate as "amended: AC-101, 104, 108, 109, 111, 112, 117, 119, 120, 121,
  122, 124, 125, 127, 129, 130, 131 + Terminology".
- **B-2 — AC-133 guards a configuration the product does not ship, and sits outside AC-136.**
  `recall_context_match` defaults **False** (config.py:202, "stays OFF (T2: no rank lift)"), so
  the shipped arm is `comp` (completion on, context off). AC-133 guards `context_rank.context` —
  the `ctx` arm. Worse, `retrieval_gate.run()` exports `context_rank` for `flat`/`context`/`both`
  only, so **the shipped arm's ctx_rank is not an exported metric at all**. The guard is a
  reasonable proxy (the fusion weight is arm-independent) but should say so. Separately, AC-133 is
  not among AC-136's five contingency gates, though it was added for exactly the silent-degradation
  reason that motivates the contingency.
- **B-3 — AC-135's path-level identity is fixture-dependent.** It neutralises `alpha` and the arm
  weights, but not **D4's reseeding**, which is inside the same flag: with all weights at 1.0,
  `prelim = fuse(sparse, dense)` is still not `dense_ranking`, so `seed_ids` differs from
  `ef42967`'s. It passes only because the sketch fixture's `prelim[:fetch_width]` is *set-equal* to
  `dense_ranking[:fetch_width]` (order differs, membership does not, so a real `neighbor_expand`
  returns the same neighbours). State that precondition, or the criterion inherits the
  fixture-dependence F2/F3 were just repaired for.
- **B-4 — AC-104's "any ranking set" still admits intra-list duplicates.** `rrf_merge_scored`
  adds a term *per occurrence* (`scores[record_id] = scores.get(...) + …` inside
  `enumerate(ranking)`), and its own docstring blesses the case ("Duplicates within a single list
  are allowed but unusual"). D1's docstring is silent on it. The shipped corpus has no intra-list
  duplicate, so the criterion is again green-by-corpus-luck on that edge. One fixture closes it.
- **B-5 — cycle labelling.** The author's self-gate ran `--cycle 1` (bar: all ≥ 3) on a
  post-refine artifact; `state.refine_cycles` is 1, so the doctrinal bar for the next assessment is
  cycle ≥ 2 (all ≥ 4). Their 4/4/4/4/4 clears either bar, so nothing material turns on it — but
  this delta is scored at cycle 2 and the labels should agree. The self-gate is correctly and
  explicitly marked "NOT a critique", which is the right practice.
- **B-6 — wording.** spec.md:982 reads "One directional conclusion survived … and one did not
  (static down-weighting collapses multi-hop)". The parenthetical restates the *withdrawn* claim in
  the present tense; read in isolation it inverts the paragraph's meaning. Reword to "…and one did
  not: the claim that static down-weighting collapses multi-hop recall."

## Per-dimension findings (refine rubric, cycle 2 — tool verdict: fail, min 3)

- **clarity (4/5)** — The `## Refine record` table with per-finding disposition *and* independent
  reproduction evidence is the best artifact in either revision; AMENDED annotations name the
  finding that caused each edit. Held at 4 by B-1 (the manifest understates its own diff) and B-6.
- **completeness (4/5)** — All six blocking findings and all eleven advisories closed; scope
  re-declared and now covers every file the 39 ACs require (0 uncovered, re-checked). Not 5 because
  G-2 shows the F5 repair addressed one axis of a two-axis defect.
- **actionability (4/5)** — AC-139's "move the fixture, do not weaken it" escape hatch and AC-136's
  tag-blocking rule are both directly executable. DP-1's binding pre-deliberation measurement order
  is the right instrument. Held at 4 by G-1 leaving the implementer no way to answer the change's
  own central claim.
- **efficiency (4/5)** — 31 → 39 with none removed, one amend operation, no ceremony inflation;
  the eight new criteria are all load-bearing rather than defensive padding.
- **testability (3/5)** — **The failing axis, but up from 2.** The four round-1 defects are
  measurably repaired: AC-131 now has verified discriminating power (0/40 all-agree at n ≥ 4),
  AC-134 is a real RED-on-inversion oracle carrying the exact figure it must catch, the
  AC-104/AC-132 split resisted attack, and AC-138/AC-139 restore falsifiability. Below the cycle-2
  bar because the change's central thesis still has no criterion that can fail on it (G-1) and one
  defect silently disables the headline feature while passing all 39 (G-2).

## Prescriptions (round 2 — ordered)

1. **Add AC-140 (guard-vs-cure).** With `FETCH_WIDTH_FLOOR = 1`, AC-102's `k ∈ {1,3,5}` cells must
   still place the target at `result.records[0].id`. This is the floor-*removal* direction; AC-138
   and AC-139 test only floor inflation, which at k=10 cannot answer the question (G-1). Feed the
   result to FORGE before it rules DP-1 — a red AC-140 reframes the change.
2. **Pin the selectivity denominator's status population (G-2).** State in §D3 that numerator and
   denominator must count the same statuses, and prefer *all statuses* (that is what `bm25_search`
   returns — verified: no status predicate, and the FTS triggers carry deprecated rows). Add the
   mixed-population criterion: a searched layer of N active + M deprecated crystals, all matched,
   must resolve `w_sparse` to exactly 1.0.
3. **Correct the criteria header's amend manifest (B-1)** to name all seventeen changed blocks plus
   the Terminology edit. This needs no new `--amend` if folded into the next one; it must not land
   as a silent edit.
4. **AC-135** — add the reseeding precondition (`prelim[:fetch_width]` set-equal to
   `dense_ranking[:fetch_width]` in the fixture), or state that D4 is deliberately not neutralised
   and the identity is therefore fixture-scoped (B-3).
5. **AC-136** — add AC-133 to the contingency list, for the same reason AC-121..123 were added (B-2).
6. **AC-133** — record that `recall_context_match` defaults False, so this guards a proxy arm, and
   that the shipped arm's `ctx_rank` is not exported by `retrieval_gate.run()` at all (B-2).
7. **AC-104** — add one intra-list-duplicate fixture, or exclude duplicates in the GIVEN (B-4).
8. **spec.md:982** — reword the parenthetical so it does not restate the withdrawn claim in the
   present tense (B-6). Label the next self-gate `--cycle 2` (B-5).

Prescriptions 1, 2, 4, 5, 6 and 7 touch the frozen set and require a second
`ramza-freeze --amend --reason`. Current frozen hash:
`7e4c0807d7684ad821d00f39c98d562d1acd453f9147f4dc9e19918f76d64802`. `state.refine_cycles` is 1;
a round-2 refine takes it to 2 of the hard cap 3 — the remaining prescriptions are small and
should land in **one** pass, not two.

## Gate record (round 2)

| gate | result |
|---|---|
| frozen-criteria hash re-verified | `sha256:7e4c0807…d64802` — **matches** state + brief |
| amend trail | **LEGAL** — 1 amendment, substantive `--reason`, chain `132b25df… -> 7e4c0807…`, all 31 original IDs present, 39 total, none removed (manifest self-description incomplete: B-1) |
| `ramza-lint` | **clean**, exit 0 (tier full) — re-run |
| `ramza-ears-lint` | **clean, 39 criteria**, exit 0 — re-run |
| `ramza-score --rubric refine --cycle 2` | **fail** — total 3.8, min 3 (clarity 4, completeness 4, actionability 4, efficiency 4, testability 3), exit 1 |
| `ramza-gate critic --author vivi --checker vigil` | **OK** — re-recorded for round 2 |
| crystalium tree | clean at `ef42967` — re-verified; read-only honoured across both rounds |
| verdict | **REVISE (round 2)** — F1–F6 all closed; 2 new blocking (G-1, G-2), 6 new advisory |

---

*vigil — delta re-critique round 2, RAMZA critic skill (maker≠checker)*

---

# Critique — ROUND 3 (final delta re-critique of spec revision 1.2.0)

critic:   vigil (independent; plan maker: vivi — re-recorded via `ramza-gate critic`)
date:     2026-08-03
inputs:   spec.md (rev 1.2.0) · spec.criteria.md (frozen, **amended twice**, 42 criteria,
          sha256 59244291378b79d668781befa42200a58315ba29b0cd7885cab01a0e07fe0137 —
          **re-hashed independently, matches**) · plan state (refine_cycles 2 of cap 3)
target:   crystalium @ ef42967 — re-verified clean; no code touched in any round

**Verdict:** ramza-lint clean (exit 0, full tier) · ramza-ears-lint clean (**42/42**, exit 0) ·
refine rubric: **fail** (cycle 2, total 3.8, min 3 — clarity 4 / completeness 4 / actionability 4 /
efficiency 4 / **testability 3**; bar all ≥ 4)

**Overall: REVISE (round 3) — one clause, mechanical, and it should be the last pass.**

Both deviations are **UPHELD**: the author was right and I was wrong on deviation 1, and deviation 2
is handled exactly as a maker/checker disagreement should be. G-1 is **CLOSED** with a better
instrument than I prescribed. G-2's *design* fix is closed. But **AC-142 — the sole oracle for G-2 —
cannot fail on the defect it names**, because the clamp §D3 mandates swallows the mixed-population
signature. That is R-7 firing a third time, and it is the only thing standing between this spec and
Assemble.

**Amend trail: LEGAL across all three revisions.** Chain `132b25df… -> 7e4c0807… -> 59244291…`
verified, both amendments carry substantive `--reason` text (1376 and 2236 chars), all 42 IDs
AC-101..AC-142 present, **none removed**. The B-1 manifest defect is fully repaired: the criteria
file now carries a three-revision table that independently reconstructs and confirms my
seventeen-block round-1 count.

## Ruling on the two deliberate deviations

### Deviation 1 — AC-140 pinned to Layer 3 rather than my AC-102 parameterisation: **UPHELD. My prescription was defective.**

I checked the premise rather than my own prescription. spec.md:898-902: "**Layer 2 — real stack,
mocked arms** … Covers AC-101, **AC-102**, AC-103, AC-113..AC-120, AC-129." AC-102 is Layer 2, and
the Terminology block mandates a graph mock whose return value is independent of `seed_ids`. On
that mock, *lowering* `FETCH_WIDTH_FLOOR` changes `seed_ids` but not the arms, so the target's rank
is unchanged **by construction** — my "two-line parameterisation of a fixture AC-102 already
builds" would have planted the F2 tautology in the mirror direction, on the change's own thesis
test. The author caught a real defect in a critic prescription; the Layer-3 pinning is correct
doctrine and I withdraw the round-2 wording.

**AC-141 is observable, and its mechanism model checks out.** I re-derived the seeding claim:

| `w_sparse` | target | N1 | N2 | N3 | `prelim[0]` |
|---|---|---|---|---|---|
| 1.00 | 0.032018 | 0.016393 | 0.016129 | 0.015873 | **target** |
| 1.50 | 0.040215 | 0.016393 | 0.016129 | 0.015873 | **target** |
| 2.00 | 0.048412 | 0.016393 | 0.016129 | 0.015873 | **target** |

The target leads `prelim` across the entire `w_sparse` range, so at `fetch_width = 1`
`seed_ids = [target]`, while `ef42967` seeds `dense_ranking[:1] = [N1]` — the top dense
*competitor*. The author's conclusion that **D4 reseeding, not the weighting, is the
floor-removal enabler** is sound, and pre-registering it is good practice: it makes AC-140 a
prediction that can be wrong rather than a result to be narrated afterwards. Excluding AC-140 from
AC-136's flag contingency and routing a red result to FORGE as DP-1 input is also right — a red
AC-140 means "layered on the guard", which is a *finding about the change's nature*, not a
correctness failure of the shipped default. (One Assemble note: FORGE should still be asked to
rule explicitly whether a red AC-140 changes the default, rather than leaving it implicit.)

### Deviation 2 — DP-9 recommends active-only against my all-statuses: **UPHELD as a fair escalation. The framing is fair to my position; the mechanism is not yet complete.**

The worked example reproduces exactly on my own arithmetic: 1 fresh + 50 superseded in a
100-active layer gives `w_sparse = 1.66` all-statuses versus `1.99` active-only, while the caller
sees one record either way. The argument — that under bi-temporal supersession the deprecated rows
are lexical near-duplicates of the target itself, so counting them lets records the caller never
sees dilute the very signal they are duplicates of — is **stronger on quality grounds than my
own**, which was a cheapness/faithfulness argument ("all-statuses is what `bm25_search` actually
returns"). Recording it as DP-9 with both positions rather than silently overruling the checker is
the correct handling, and writing AC-142 to be population-neutral so FORGE can rule either way
without a further amend was the right instinct.

Two things DP-9 should carry to FORGE that it does not yet say:

1. **Active-only is not a denominator choice alone — it requires an active-only numerator too**,
   and `bm25_search` has no status predicate. The cheap route is to count active hits *within*
   `sparse_ranking` for weight purposes only (status is available — `bm25_search` returns full
   crystal dicts via `_row_to_dict`), leaving the sparse arm itself untouched. Say so, or an
   implementer may reach for a status predicate on the shared storage method.
2. **All-statuses carries a second failure mode DP-9 does not mention**, which strengthens the
   author's own recommendation: `bm25_search` applies `LIMIT candidate_k` with no status filter, so
   deprecated near-duplicates consume fetch slots and can push `n_sparse` to `cap`, tripping the
   censoring branch to `w_sparse = 1.0` — and can crowd active hits out of the candidate set
   entirely. That is pre-existing and out of scope to fix, but it is decision-relevant to DP-9.

## NEW blocking finding

### H-1 — BLOCKING: AC-142, the sole oracle for G-2, cannot fail on the defect it names (R-7, third occurrence)

Anchors: AC-142 ("**only the mixed implementation gives a non-zero boost** for a query that matched
everything it searched"); §D3's frozen formula
`selectivity = clamp(1.0 - n_sparse / max(1, N), 0, 1)`; AC-112 (which *requires* the resulting
bound `[1, 1+alpha]`, so the clamp is mandatory, not incidental); R-9 ("AC-142 is the oracle").

AC-142's fixture is **saturating** — the query matches every crystal in the layer regardless of
status — precisely so that both pure populations yield zero boost and the criterion stays
DP-9-neutral. That neutrality is what destroys it. Computed across the three implementations:

| N active | M deprecated | all-statuses | active-only | **mixed (num all, den active)** |
|---|---|---|---|---|
| 100 | 50 | 1.0 | 1.0 | **1.0** |
| 10 | 5 | 1.0 | 1.0 | **1.0** |
| 5 | 5 | 1.0 | 1.0 | **1.0** |
| 50 | 200 | 1.0 | 1.0 | **1.0** |

Under the mixed implementation the numerator exceeds the denominator, so `1 - n/N` is **negative**
— and the clamp floors it at 0, returning `w_sparse = 1.0`, the identical answer. AC-142 is green
under all three implementations for every fixture shape it admits. Its closing sentence is a
statement of fact and it is **false**.

The consequence is exactly what G-2 warned about, now one level up: verification will record
AC-142 PASS, R-9's stated mitigation will read as discharged, and the status-axis defect — a
headline feature that decays silently toward `w_sparse = 1.0` as deprecated rows accumulate, by
design under P0-5, with no error, no log line and no explain anomaly — ships unguarded.

The three implementations do diverge on a **non**-saturating fixture (matched = 1 active + M
deprecated: 1.66 / 1.99 / 1.49), but there the two pure populations disagree with each other, so
no value-assertion can stay DP-9-neutral. That is the trap the author walked into, and it is a
genuine one.

**The fix is one clause, and it keeps DP-9 neutrality intact.** Assert the *population-agreement
invariant* rather than the resulting weight:

| implementation | `n_sparse` | `N_L` | `n_sparse <= N_L` |
|---|---|---|---|
| all-statuses | 150 | 150 | holds |
| active-only | 100 | 100 | holds |
| **mixed** | **150** | **100** | **VIOLATED** |

Both pure populations satisfy `n_sparse <= N_L` by construction at the saturating fixture; the
mixed one cannot. And it is already observable: revision 1.2.0's AC-117 requires `explain.fusion`
to surface the denominator's value **together with the status population it was drawn from**, so
the assertion is available to the same test that already reads `w_sparse`.

*Prescription (single, mechanical, no re-deliberation):* amend AC-142's THEN to
"…shall report a sparse arm weight of exactly 1.0 **and shall report a sparse-arm count no greater
than the searched-layer count that produced it**", and replace the false closing sentence with the
table above. This is the only change round 3 requires.

## Advisory (round 3)

- **C-1 — AC-141's escape-hatch clause inverts AC-139's convention.** AC-139 reads "If AC-139
  cannot go **green**, the fixture is seed-insensitive"; AC-141, in the structurally identical
  role, reads "If AC-141 cannot go **red**…". AC-141's own THEN is an assertion that the reverted
  build puts something *else* first, so the precondition is satisfied when AC-141 is **green**.
  The informal reading ("the reverted build must go red") is recoverable, but two sibling
  preconditions should not use opposite conventions for the same instruction. Normative
  GIVEN/WHEN/THEN is unambiguous; this is the guidance clause only.
- **C-2 — AC-140's exclusion from AC-136 should be FORGE's explicit ruling, not the spec's
  assumption.** The reasoning is sound, but "the issue's literal acceptance bar is red and the flag
  still ships ON" is a call the deliberating authority should make on the record.

## Per-dimension findings (refine rubric, cycle 2 — tool verdict: fail, min 3)

- **clarity (4/5)** — The three-revision change manifest independently reconstructing my own
  seventeen-block count is the strongest integrity artifact in the campaign, and AC-138/139's new
  scope notes ("this pair probes floor *inflation* only") are exactly the honest self-limitation
  that was missing. Held at 4 by AC-142's false closing sentence and C-1.
- **completeness (4/5)** — G-1 closed with a better instrument than prescribed; G-2's §D3 binding,
  AC-109/112/117 population clauses and the DP-9 escalation all landed; all six round-2 advisories
  verified closed (B-1 manifest, B-2 AC-133 now in AC-136's list, B-3 set-equality precondition,
  B-4 `[["a","b","a"]]` fixture, B-5, B-6). Not 5 because G-2's oracle does not work.
- **actionability (4/5)** — AC-140/141 carry a pre-registered mechanism prediction; "a red AC-140
  is not a defect to be patched away" is the right instruction to leave an implementer; DP-9 gives
  FORGE a clean either-way ruling. Docked for the two DP-9 mechanism gaps above.
- **efficiency (4/5)** — 39 → 42 with one amend and no bloat. The population-neutral design of
  AC-142 was a genuinely clever attempt to avoid a post-DP-9 amend; it simply does not work.
- **testability (3/5)** — AC-140/AC-141 are well-built and the Layer-3 pinning is better doctrine
  than my own prescription; AC-104's duplicate edge is closed. Below the bar solely because the
  single criterion guarding a blocking finding is provably non-discriminating (H-1) — the failure
  mode this project treats as disqualifying, on its third occurrence.

## On R-7's third occurrence, and the cycle cap

The author's stated position — "if the pattern breaks a third time, escalate rather than add a
fourth criterion" — is sound discipline, and I want to record why I am **not** invoking it here.

The first two occurrences were the same defect: an attack that could not fail (F2's tautology,
then G-1's inert direction). The response — a mandatory falsifiability precondition per attack
(AC-139 for AC-138, AC-141 for AC-140) — is a *structural* fix, and it holds: I attacked both
pairs this round and could not break either.

H-1 is a different species. It is not an attack that cannot fail; it is an oracle whose
**DP-9-neutrality requirement and the mandated clamp interact** to erase its discriminating power.
That interaction is subtle, the author's attempt at neutrality was correct in intent, and the
repair is one clause that does not touch the design, the DPs, or any other criterion. Escalation
is the right instrument for a pattern that resists structural repair; this is a defect that a
single mechanical edit closes.

So: **REVISE, with the explicit expectation that refine cycle 3 is the last** — one clause in
AC-142, plus C-1's wording and C-2's note. If anything of substance emerges after that pass, I
agree escalation is correct and I will say so rather than open a fourth round.

## Gate record (round 3)

| gate | result |
|---|---|
| frozen-criteria hash re-verified | `sha256:59244291…fe0137` — **matches** state + brief |
| amend trail (3 revisions) | **LEGAL** — chain `132b25df… -> 7e4c0807… -> 59244291…`, 2 amendments with substantive `--reason`, 42 IDs AC-101..AC-142 all present, none removed; B-1 manifest defect repaired |
| `ramza-lint` | **clean**, exit 0 (tier full) — re-run |
| `ramza-ears-lint` | **clean, 42 criteria**, exit 0 — re-run |
| `ramza-score --rubric refine --cycle 2` | **fail** — total 3.8, min 3 (4/4/4/4/**3**), exit 1 |
| `ramza-gate critic --author vivi --checker vigil` | **OK** — re-recorded for round 3 |
| deviation 1 (AC-140 at Layer 3) | **UPHELD** — author correct; my round-2 prescription withdrawn |
| deviation 2 (DP-9 active-only) | **UPHELD** — fair escalation; two mechanism gaps to carry to FORGE |
| crystalium tree | clean at `ef42967` — re-verified; read-only honoured across all three rounds |
| verdict | **REVISE (round 3)** — 1 blocking (H-1, one clause), 2 advisory |

---

*vigil — delta re-critique round 3, RAMZA critic skill (maker≠checker)*

---

# Critique — ROUND 4 (TERMINAL ruling on spec revision 1.3.0)

critic:   vigil (independent; plan maker: vivi — re-recorded via `ramza-gate critic`)
date:     2026-08-03
inputs:   spec.md (rev 1.3.0) · spec.criteria.md (frozen, **amended three times**, 42 criteria,
          sha256 b17f209a89442a35f4f508af6becf53563f7158234ce476ae0f0e1e15e353a75 —
          **re-hashed independently, matches**) · plan state (refine_cycles 3 of cap 3, exhausted)
target:   crystalium @ ef42967 — re-verified clean; no code touched in any round

**Verdict: APPROVE-FOR-ASSEMBLE.**

ramza-lint clean (exit 0, full tier) · ramza-ears-lint clean (**42/42**, exit 0) ·
refine rubric **pass** (cycle 3, total 4.4, **min 4** — clarity 4 / completeness 5 /
actionability 4 / efficiency 5 / testability 4; bar all ≥ 4).

**H-1 is CLOSED — and the fix is stronger than the one I prescribed.** No blocking finding
remains. Two Assemble notes go to FORGE and the implementer; neither is gap-report weight, and I
say so deliberately with the cap exhausted: a gap report is for a defect that would let something
through, and neither of these can.

**Amend trail: LEGAL across all four revisions.** Chain
`132b25df… -> 7e4c0807… -> 59244291… -> b17f209a…` verified contiguous (each amendment's `prev`
equals its predecessor's `new`); head matches `state.criteria_sha256`; three amendments carrying
1376 / 2236 / 2223 chars of `--reason`; all 42 IDs AC-101..AC-142 present; **none added or removed
in this revision**, as claimed. `ramza-gate refine` confirmed DENY at the cap — this ruling is
terminal, as it should be.

## H-1 closure — verified by re-attack, and the author under-sold the result

AC-142's THEN is now the invariant clause and the VERIFY asserts
`explain["fusion"]["n_sparse"] <= explain["fusion"]["n_scoped"]`, keeping `w_sparse == 1.0` as a
companion. I did not check only the direction I had named; I enumerated **every** population
pairing at the saturating fixture (N = 100 active, M = 50 deprecated, all matched):

| numerator | denominator | `n_sparse` | `n_scoped` | invariant | `w_sparse` | caught by |
|---|---|---|---|---|---|---|
| all-statuses | all-statuses | 150 | 150 | holds | 1.0 | — correct impl, both pass |
| active-only | active-only | 100 | 100 | holds | 1.0 | — correct impl, both pass |
| **all-statuses** | **active-only** | 150 | 100 | **VIOLATED** | 1.0 | **invariant (normative THEN)** |
| **active-only** | **all-statuses** | 100 | 150 | holds | **1.3333** | **weight check (VERIFY companion)** |

Two things follow.

1. **The oracle is complete.** Every population *mismatch* is caught, and both correct
   implementations pass — so AC-142 now discriminates exactly the class it names, under either
   resolution of DP-9. That is H-1's closure, verified rather than accepted.
2. **The criterion mislabels its own companion.** The weight check is described as "a companion
   **non-discriminating** regression check". It is not non-discriminating: it is the *only*
   assertion that catches the **reverse** mismatch (active-only numerator, all-statuses
   denominator) — a genuinely plausible implementer combination, since DP-9's brief recommends an
   active-only numerator while the naive denominator is a bare
   `SELECT count(*) … WHERE layer IN (…)`. The two assertions are **complementary**, not
   oracle-plus-redundancy. This is the author under-selling their own fix, so it is an Assemble
   note rather than a defect — but the label should be corrected before the criterion is quoted
   into `verification.md`, or a future reader may drop the "redundant" half and reopen the hole.

The author's confirmation that no non-saturating fixture could have worked also checks out on my
own arithmetic: at 1 active + 50 deprecated in a 100-active layer the three implementations give
**1.66 / 1.99 / 1.49**, so the two *pure* populations disagree and DP-9 neutrality is unattainable
off-saturation. The saturating fixture was forced; the invariant was the only way out of it.

## Ruling on the compound-THEN split: **UPHELD — my prescription was the defective one**

My literal round-3 fix was "…shall report a sparse arm weight of exactly 1.0 **and** shall report a
sparse-arm count no greater than…". That is a compound THEN — a violation of the very grammar I am
here to enforce, and the RAMZA critic skill's own worked example of a prescription is literally
"AC-004's THEN is compound; split into AC-004a/AC-004b". I prescribed the defect I police.

The split is correct and preserves intent completely:

- the **discriminating** half is normative (THEN), which is where a gate's falsifiability must live;
- the weight check sits in VERIFY, where it is still **executed** — VERIFY names the pytest
  assertions and `ramza-ears-lint` governs THEN grammar, not VERIFY content, so nothing is
  weakened, only relocated;
- one criterion, one assertion; `ramza-ears-lint` passes 42/42 and my independent sweep for
  compound THENs across all 42 blocks returns **0**.

Same content, same oracle, EARS-atomic. This is the second time this round-trip the author has
correctly refined a defective prescription of mine (the first being AC-140's Layer-3 pinning),
and both corrections were argued from evidence rather than deferred to. That is the maker≠checker
loop working in the direction it is least often observed working.

## C-1 and C-2 — both closed

- **C-1** — AC-141 now reads "If AC-141 cannot go **green**…", matching AC-139, and adds an
  explicit note reconciling the convention ("AC-141's own THEN asserts that the *reverted* build
  puts some other id first, so the precondition is satisfied when AC-141 itself is green"). The
  two sibling preconditions now speak one language.
- **C-2** — AC-140's exclusion from AC-136 is now **DP-4(ii)**, open for FORGE with both options
  stated, and AC-136 records its list as pending that ruling ("Until DP-4(ii) is ruled, this
  criterion's list is the five of revision 1.1.0 plus AC-133"). The spec no longer assumes a call
  that belongs to the deliberating authority. AC-136's VERIFY correctly reads "all six named
  criteria".

## Assemble notes (for FORGE and the implementer — not gap-report weight)

- **N-1 — `explain.fusion`'s denominator key is named inconsistently.** AC-142's VERIFY asserts
  `explain["fusion"]["n_scoped"]`, but §D8's illustrative object (spec.md:466-472) still names the
  denominator **`corpus_n`** — a leftover from the pre-F5 corpus-global design, stale in both name
  and semantics now that the count is layer-scoped and population-bound. `n_scoped` appears
  nowhere in spec.md. AC-117 mandates the key exists but does not fix its spelling, so the criteria
  are internally consistent and the spec body's example is the stale artifact. **Why this is a note
  and not a blocker:** the failure mode is a `KeyError` on the first run of
  `test_mixed_status_population_agrees` — loud, immediate, and impossible to mistake for a pass. It
  cannot produce a false green, which is the bar a gap report exists to defend. Align §D8 on
  `n_scoped` (and drop `corpus_n`) in the implementation pass.
- **N-2 — correct AC-142's "non-discriminating companion" label** per the table above, before the
  criterion is transcribed into `verification.md`.

## Per-dimension findings (refine rubric, cycle 3 — tool verdict: pass, min 4)

- **clarity (4/5)** — AC-142 now carries both measurement tables, an explicit statement that
  revision 1.2.0's closing sentence "was **false**", and a wording note explaining the split;
  AC-141's convention note is exemplary. Held at 4 solely by N-1.
- **completeness (5/5)** — Every finding across four rounds (F1–F6, A-1..A-11, G-1, G-2, B-1..B-6,
  H-1, C-1, C-2) is dispositioned and verified closed. DP-9 carries both mechanism gaps I raised
  *plus* two the author added. R-7 is generalised into a standing rule. I cannot name a missing
  element.
- **actionability (4/5)** — Pre-registered mechanisms, "moved, not weakened" instructions on both
  falsifiability pairs, DP-4(ii) framed for ruling rather than assumed. Held at 4 by N-1's
  KeyError friction.
- **efficiency (5/5)** — 42 → 42. Three blocks amended, one amend operation, and — the discipline
  that matters — **no new criterion was added to repair a criterion defect**. The trajectory
  31 → 39 → 42 → 42 is convergent, not accretive.
- **testability (4/5)** — The oracle discriminates all four population pairings (verified above);
  both attack pairs carry falsifiability preconditions that survived attack; AC-131 has measured
  power (0/40 all-agree at n ≥ 4); AC-104/AC-132 resisted counterexample; my sweep found no
  remaining criterion that cannot fail on its named defect. Not 5 because **every RED-first claim
  in this spec is still a prediction** — G-2 in §Evidence Gaps is honest that crystalium was never
  executed, and predictions are not measurements.

## On R-7's generalisation

The author's standing rule — *an oracle must be shown to DIFFER across the implementations it
claims to distinguish, not merely hold on the correct one* — is the correct abstraction of all
three R-7 occurrences, and it is strictly stronger than the doctrine I opened round 1 with ("a gate
that cannot fail on the defect it names is not a gate"). Mine tests a gate against one wrong
implementation; the author's requires a *difference table* across the space of candidate
implementations, which is precisely the instrument that would have caught H-1 prospectively and did
catch the reverse-mismatch case here. It belongs in the repo's methodology notes, not just in this
spec.

For the record, the score ledger across the campaign — mine 3.4 fail / 3.8 fail / 3.8 fail / **4.4
pass**, the author's 4 pass at each cycle — is the expected signature of a working maker≠checker
split, not of a disagreement: the author scored the artifact they intended, and I scored the
artifact as an adversary reading it cold. The convergence at cycle 3 is on the merits.

## Handoff note for the FORGE deliberation

**What the deliberator should weigh most: DP-1 is now an open question resting on a measurement
that did not exist when this spec was written, and the spec is honest that it cannot answer it.**
Revision 1.0.0 rejected static per-arm weighting on a modelled 67 % multi-hop F1 collapse; that
number inverted under the spec's own declared-weak dense-arm inference (F1), the rejection was
withdrawn, H-A was re-scored 61.5 → 72.5, and a binding real-stack measurement was ordered. FORGE
should not rule DP-1 or DP-2 before that measurement lands, and should treat any number in
§D2 as modelled. Second, **DP-9 is a recorded maker/checker disagreement, deliberately left open**:
the checker argued all-statuses (cheap, faithful to what `bm25_search` returns), the maker argued
active-only (better signal under bi-temporal supersession), AC-142 is population-neutral so either
ruling lands with no further amend, and the two costed mechanism gaps are in the brief — note
especially that active-only requires an active-only *numerator*, which must be computed within
`sparse_ranking` for weight purposes only, because a status predicate on the shared `bm25_search`
would change every caller's candidate set. Third, **DP-4(ii)** asks whether a red AC-140 — the
change proving to be layered on the v1.9.0 guard rather than replacing it — flips the shipped
default; that is a genuine product call the spec correctly declines to make. Finally, weigh
**R-8 and R-9 as the live risks**: both are unmeasured, both now have purpose-built oracles
(AC-140/141 and AC-142), and both were invisible until this critique cycle — which is the strongest
available evidence that the criteria set is worth the four revisions it took to get here.

## Gate record (round 4, terminal)

| gate | result |
|---|---|
| frozen-criteria hash re-verified | `sha256:b17f209a…353a75` — **matches** state + brief |
| amend trail (4 revisions) | **LEGAL** — chain contiguous `132b25df… -> 7e4c0807… -> 59244291… -> b17f209a…`, head == state, 3 substantive `--reason` records, 42 IDs present, none added/removed this revision |
| `ramza-lint` | **clean**, exit 0 (tier full) — re-run |
| `ramza-ears-lint` | **clean, 42 criteria**, exit 0 — re-run |
| compound-THEN sweep (all 42) | **0** — EARS-atomic throughout |
| `ramza-score --rubric refine --cycle 3` | **pass** — total 4.4, **min 4** (4/5/4/5/4), exit 0 |
| `ramza-gate critic --author vivi --checker vigil` | **OK** — re-recorded, terminal |
| `ramza-gate refine` | **DENY** at cap 3 — confirmed; no further refine is legal |
| H-1 | **CLOSED** — oracle discriminates all four population pairings (re-attacked, not accepted) |
| compound-THEN split | **UPHELD** — my prescription was the defective one |
| crystalium tree | clean at `ef42967` — read-only honoured across all four rounds |
| **verdict** | **APPROVE-FOR-ASSEMBLE** — 0 blocking, 2 Assemble notes (N-1, N-2) |

---

*vigil — terminal delta re-critique round 4, RAMZA critic skill (maker≠checker)*
