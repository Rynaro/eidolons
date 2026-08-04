---
eidolon: forge
kind: deliberation
seat: HUMAN-DECISION (delegated; rulings BINDING)
change_id: crystalium-rrf-fusion-38
esl_tier: full
spec: spec.md (ramza 1.4.0, ASSEMBLED)
criteria: spec.criteria.md frozen @ sha256 e644052e868db47b49c7daedba904e9f53b67d401c81bde0b5e2887ffcb2fded (42, immutable)
target: Rynaro/crystalium @ ef42967 (v1.9.0) -> 1.10.0
decided_at: "2026-08-03"
methodology: FORGE 1.10.0 (F -> O -> R -> G -> E per DP)
primary_evidence: measurement.md (26 real-stack gate runs + 2 probes) — supersedes every modelled number in spec.md §D2
requires_checker: true
checker_class_hint: VIGIL
---

# Binding deliberation — crystalium#38 weighted RRF fusion

## 0. Evidence primacy and what was checked before ruling

**Primacy rule applied throughout:** where `measurement.md` and any modelled figure in
`spec.md` §D2/§D3 disagree, the measurement wins. Where the measurement is itself
confounded (anomaly C), the ruling states what the number can and cannot license rather
than discounting it wholesale.

Checked before ruling, from the artifacts named in the docket:

- **Measured arm memberships** (`measurement.md` §2): hub sparse-1/dense-1; ctx_match
  dense-2; ctx_off dense-3; **spoke1 dense-17**, graph rank 1 (sole member); **spoke2
  absent from `dense_ranking` entirely**, completion-only. `dense_ranking` holds exactly
  30 ids (`candidate_k`) against a 31-crystal corpus. **Neither modelled column in
  spec.md or critique.md is correct** — rev 1.0.0 modelled both spokes absent, vigil's F1
  correction modelled them at 25/26–29/30; the truth is one at 17, one absent.
- **H-A on the real gate**: `f1.completion` 0.4615384615384615 -> 0.30769230769230765,
  `completion_pass false`, **`gate_pass false`, at all 6 hash seeds**.
- **H-B (`w_derived=1.0`, `alpha=1`)**: `f1.completion` 0.4615…, `gate_pass true`, and the
  measured P1 inversion corrected — baseline puts spoke1 (zero lexical match) at fused
  rank 0 (0.04500545560996381) above hub (0.03278688524590164); H-B puts hub at rank 0
  (0.048651507139079855) with spoke1 at 1 (0.02938045560996381) and spoke2 retained at 4.
- **`w_derived=0.95`**: 6/7, red at `PYTHONHASHSEED=5`; mechanism arithmetic given
  (`0.95/63 = 0.0150794 > 1/67 = 0.0149254` at completion rank <= 3;
  `0.95/64 = 0.0148438 < 0.0149254` at rank 4). Measured margin at the last k=10 slot: 1.0 %.
- **Identity property at 1.0**: 20/20 in-process comparisons, max abs score diff **exactly
  `0.0`**, bitwise equal, order identical, with the completion arm empty.
- **D3 live on the real stack**: `n_sparse=1`, `cap=120`, `N_scoped=31` ->
  `selectivity=0.967741935483871`, `w_sparse=1.967741935483871`, denominator obtained from
  the existing bounded `count_for_export(scope.project, layers=target_layers)`.
- **P3 on the real gate**: `context_rank.both` takes {2, 4, 5} across seeds and varied
  4 -> 2 across two runs at the *same* (unset) seed; completion-arm cardinality observed at
  2 and 4 with four distinct orderings.
- **Frozen-criteria consistency**: every ruling below was checked against the 42 frozen
  blocks for amend-freeness. Three rulings are **foreclosed by the freeze** — see §4.

**Bookkeeping correction, on the record.** Revision 1.1.0's withdrawal of the H-A
rejection (spec §D2, critique F1) is itself **measured wrong**, and the H-A explore
re-score `61.5 -> 72.5` recorded in the plan state is **stale**. This is not a criticism of
the critique: vigil's F1 was a correct critique of a *model* (the spokes-absent column was
unjustified), and vigil's own prescription 1(ii) — "measure it" — is what produced the
evidence that settles it. What the campaign should record is narrower and sharper: **three
successive models of the dense arm were offered and all three were wrong.** The rejection
of H-A is reinstated on measurement and on structure (anomaly B), never on rev 1.0.0's
0.1538 figure — the measured collapse is 0.4615 -> 0.3077 (33 %), not the modelled 67 %.

---

## 1. RULINGS

| DP | Ruling | Operative instruction to the implementer (vivi) |
|----|--------|--------------------------------------------------|
| **DP-1** | **(b) — correlated-family merge (D2) + query-conditional sparse boost (D3)**; per-arm weights present as config, defaulting to 1.0 | Implement D1/D2/D3/D4 as specified. H-A (static per-arm down-weighting) is **rejected on measurement**: it fails the shipped gate at 6/6 seeds and, per anomaly B, structurally cannot demote the record class the issue names. Do not ship any default below 1.0 for `fusion_weight_dense` or `fusion_weight_derived`. |
| **DP-2** | **(a) — `fusion_weight_derived = 1.0`**; values `< 1.0` remain *legal* config but are **removed from the documented band** | Default `1.0`. No validator, no clamp (keeps AC-127 trivially satisfiable). The field comment MUST record the measured cliff (0.90 deterministic fail / 0.95 red at `PYTHONHASHSEED=5` / 1.00 pass 7/7), that any value `< 1.0` forfeits the §D2 identity property, and that any value `> 1.0` re-creates P1. No test, doc, or CHANGELOG line may present 0.95 as a "precision dial". |
| **DP-3** | **(a) — search-space-relative selectivity, `N_scoped` counted over `target_layers`** | Use the existing bounded aggregate (the measurement used `count_for_export(scope.project, layers=target_layers)`); do **not** add a new public `RelationalStore` method. `alpha` default `1.0`. Status population per DP-9. Options (b), (c), (d) are **illegal** — each requires amending the frozen set (§4). |
| **DP-4** | **(a) — new `recall_weighted_fusion`, default `True`, subsumed by `recall_relevance_primary`** | `self._weighted = bool(recall_weighted_fusion and recall_relevance_primary)`; `None`-sentinel constructor idiom at both production sites (`server.py:548`, `__main__.py:340`); AC-120 pins the subsumption. AC-136's contingency stands at its frozen six (AC-121, 122, 123, 124, 125, 133): any red -> ship `False` and return to FORGE. |
| **DP-4(ii)** | **(a) — a red AC-140 does NOT flip the shipped default and does NOT block the tag**, subject to the four honesty conditions of C-12 | A red AC-140 is recorded as a finding about the change's *nature*, routed to FORGE as DP-1 input post-hoc. If any of C-12's four conditions cannot be satisfied, the tag **blocks** and the change returns to FORGE. `verification.md` MUST record which shape the red took (AC-141 green = measured failure; AC-141 not green = indeterminate) — they mean different things downstream. |
| **DP-5** | **(c) — defer the cross-layer fix; land the evidence** | No change to the per-layer append loop (`retrieve.py:326-360`). AC-126's `cross_layer` axis is the evidence. Open follow-up **D-1** with the recomputed severity table and attach AC-126's measured output when it lands. |
| **DP-6** | **(b) — defer floor scaling; surface `fetch_width`** | `FETCH_WIDTH_FLOOR` stays a constant `10`. `explain.fusion` carries `fetch_width` **and `candidate_k`** (C-6). Open follow-up **D-4** naming `candidate_k`, not the floor, as the real corpus-scaling question — the measurement supplies its first datum: `dense_ranking` held 30 of 31 crystals and **`candidate_k` is what cut spoke2 out of the dense arm**. |
| **DP-7** | **(a) — surface the weighted fused value** | `rrf_score_by_id` remains the single source of truth (#36 seam 1) and holds the weighted value on the gated path. `server.py:186-197` + `CHANGELOG.md` state that `score` is a **weighted** fusion value (AC-128). `explain` and `score` may never disagree (#36 DP-3c). (b) and (c) are **illegal** — both contradict AC-116 (§4). |
| **DP-8** | **(a) — D5's two consumer-side sorts, unchanged, IN SCOPE. Anomaly A is a follow-up (F-A), NOT in this change. PLUS the mandatory multi-run protocol of C-2 and the claim-scoping of C-3/C-10.** | Ship D5 exactly as specified (`sorted(neighbour_ids)`; `sorted(walked.items(), key=lambda kv: (-kv[1], kv[0]))`), outside the flag. Do **not** touch `storage/graph.py`. Do **not** implement a consumer-side per-seed union workaround in `retrieve.py` (explicitly rejected — §2 DP-8). AC-131 is discharged at its own (mocked) fixture under C-3; every real-`GraphStore` rank criterion is evaluated under C-2. |
| **DP-9** | **(b) — active-only on both ends, tracking `recall_active_only`** (population parity with the response) | Numerator = count of **active** hits computed **within `sparse_ranking`**, for weight purposes only; the sparse arm, the candidate set and the fused ranking are untouched. **No status predicate may be added to `bm25_search`** (shared method). When `recall_active_only=False`, both ends are all-statuses. `explain.fusion.n_scoped_status` reports the resolved population, applied to **both** ends. Pre-flight, fallback and dual-config test per C-8. |

**Anomaly dispositions** (detail in §3): **A -> follow-up issue F-A (high), plus in-change
claim-bounding**; **B -> evidence-note in `verification.md` + follow-up issue F-B**;
**C -> evidence-note + a binding interpretation rule for AC-124 (C-5) + follow-up issue F-C**.

---

## 2. Per-DP reasoning

### DP-1 — (b), and H-A is rejected twice over

**Ruling: (b).** Three independent lines converge, and they do not share a failure mode.

**Line 1 — measurement.** H-A (`w_graph=0.35, w_comp=0.25`) collapses `f1.completion`
from 0.4615384615384615 to 0.30769230769230765 and turns `gate_pass` **false at 6/6 hash
seeds**. That is not a margin degradation; it is a gate failure, deterministic across the
one axis that could have made it noise. The mechanism is measured, not inferred: spoke2's
*only* vote is the completion arm, worth `1/62…1/64 ~ 0.0159` in baseline against a
distractor band of `[1/71, 1/62]`; H-A pays it `0.25/62 = 0.004032`, an order of magnitude
below, and spoke2 is evicted. Rev 1.0.0's *direction* was right; its magnitude (67 %) was
wrong; the corrected model (F1) was wrong in direction. The measured collapse is 33 %.

**Line 2 — structure, independent of any F1 number (anomaly B).** `neighbor_expand`
filters `if neighbor_id not in seed_ids` and `decaying_walk` seeds `visited = set(seed_ids)`.
With `seed_ids = prelim[:fetch_width]`, **any record at or above fused-seed rank
`fetch_width` is structurally barred from both derived arms.** Therefore down-weighting
the derived family can *only* demote records that are deep in, or absent from, the base
arms — the multi-hop targets — and can *never* demote the top-of-dense competitors the
issue asks to demote. H-A is not a weak instrument for the issue's goal; it is an
instrument pointed at the wrong population. This argument holds on any fixture and
survives every confound in §7.

**Line 3 — the freeze already foreclosed (a), (c), (d), (e).** AC-107, AC-108 and AC-135
are written against a named `derived_ranking` produced by a derived-family merge, and
AC-104/AC-105/AC-132 against a named `weighted_rrf_merge_scored`. Under (a), (d) or (e)
those VERIFY targets do not exist and the criteria cannot be discharged; under (c) the
rank-based equivalences are meaningless. Ruling anything but (b) requires an amend and is
**illegal** under this deliberation's constraints (§4).

**What (b) buys, derived from the measured arms.** With the family merge and every weight
at 1.0 (`alpha = 0`), hub scores `2/61 = 0.032787` against spoke1's
`1/61 + 1/77 = 0.029380` — **the family merge alone corrects the measured inversion**, at
a margin of 11.6 %. The sparse boost raises hub to 0.048652, a margin of 65.6 %.
`[DERIVED]` from the measured arm memberships plus the D1/D2 formulas; the intermediate
value is not separately measured, though H-B's measured 0.02938045560996381 for spoke1
confirms the spoke1 term exactly. Read as: **D2 is the cure, D3 is the margin.** That is a
reason to keep `alpha = 1.0` and a reason not to chase further margin by raising it.

**A structural consequence worth recording.** After the family merge, a record with no
base-arm presence scores at most `w_derived/61 = 0.016393`, which cannot exceed a record
holding rank 1 in both base arms (`>= 0.032787`) and cannot exceed a single base-arm rank-1
record on any selective query (`w_sparse/61 > 1/61`). **H-D's proposed invariant is
therefore delivered by D2 as a theorem rather than bolted on as a guard** — which is the
disposition H-D deserved and the reason it is subsumed, not merely out-scored.

- **Rejected (a) static weights** — measured gate failure 6/6; structurally aimed at a
  population it cannot reach (anomaly B); and its two constants remain undistinguished by
  any evidence. Also illegal under the freeze.
- **Rejected (d) base-arm rank-1 protection** — newly refuted *on measured data*: the one
  live instance of the defect is spoke1 (dense rank **17**, i.e. present in a base arm)
  outranking hub. H-D's invariant does not fire on it. A guard that misses the only
  observed instance of the class it guards is not a candidate.
- **Rejected (e) seeding-only** — the measurement isolated this: seeding was deliberately
  left at `dense_ranking[:fetch_width]` in the H-B prototype and the P1 correction still
  landed, while D4 was a no-op in that fixture (hub is rank 1 in both base arms, so
  `prelim[0] == dense_ranking[0]`). Reseeding is necessary for the small-`k` thesis test
  (AC-140) and worthless as a standalone fix — exactly as §H-E argued, now measured.
- **Rejected (c) score-space** — unchanged: needs a storage API change, discards every
  rank-based invariant the frozen set is written against, illegal under the freeze.
- **Rejected (f) — "sequence anomaly A first, then re-deliberate fusion"** (a position the
  docket did not name; generated here and taken seriously). It fails on symmetry: fixing A
  invalidates the eval baseline exactly as much as fixing fusion would, so the
  re-measurement cost is identical either way; A is pre-existing and shipping since before
  1.9.0, so this change creates no urgency; and the DP-1 *direction* is stable under A's
  repair — a correct `neighbor_expand` enlarges the derived family, which under unweighted
  RRF makes P1 **worse** and makes a single min-rank derived voter **more** valuable, while
  making static down-weighting more destructive, not less. What (f) does earn is a binding
  requirement on the follow-up: F-A must re-run AC-124/AC-125/AC-133 against a re-baselined
  `eval-before.json` and re-check the DP-2 default (C-13).

`[RISK]` Every measured number in this campaign was taken on a graph arm that expanded
**one** seed (anomaly A). The ruling's *direction* is robust to A's repair (argued above);
its *magnitudes* are not. Recorded, not papered over.

### DP-2 — (a) `1.0`; `0.95` stays legal, leaves the documented band

**Ruling: `1.0`.** The measurement converts what the spec framed as a precision/multi-hop
trade into something else entirely: **0.95 is not a lower-margin setting, it is a flake.**
Red at `PYTHONHASHSEED=5`, green at 0–4 and unset, with the mechanism given to five
significant figures — spoke2's sole vote is `w_derived/(60 + r)` where `r` is the
hash-nondeterministic completion rank, and the pass/fail boundary sits between `r=3`
(`0.0150794`) and `r=4` (`0.0148438`) against a distractor at `0.0149254`. The surviving
margin at the last k=10 slot is **1.0 %**.

Two further facts make 0.95 indefensible as a default even after D5 lands:

1. **D5 does not make 0.95 safe; it makes the coin already flipped.** D5 stabilises the
   *order* of a given `walked` dict, but `walked`'s membership is produced by a walk whose
   frontier is a set and whose expansion (anomaly A) explores one hash-chosen seed. After
   D5, `r` becomes a fixed-but-unpredictable value drawn from the observed range
   `{1, 2, 3, 4}` — one of which is red. A default whose gate verdict is decided by a 1.0 %
   margin against a rank we cannot predict is not a default.
2. **`r` is a function of a known bug that a follow-up will fix.** F-A changes completion
   membership and therefore `r`. Tuning a shipped default against it is tuning against a
   value we have already scheduled to change.

`1.0` additionally carries the only model-independent property in the design: the identity
is now **measured bitwise** (20/20, max abs diff exactly `0.0`, order identical, completion
arm empty) rather than modelled to 1e-15. AC-108 and AC-135 are supportable as written.

**On legality of `0.95` as a config value.** The field stays a free float. Constraining it
would add unspecified behaviour on the one field AC-127 parameterises, and dropping the
knob would remove the mechanism the issue asked for and the R-1 retunability mitigation.
What changes is the *documentation*: the field comment carries the measured cliff, the
identity forfeiture below 1.0, and the P1 re-creation above 1.0 (C-9). Retuning below 1.0
later requires the reversal condition in §8, not an implementer's judgement.

- **Rejected (b) 0.95** — measured flaky on the shipped gate; forfeits the measured
  identity property; tuned against a rank determined by an open bug.

### DP-3 — (a), and the freeze had already decided it

**Ruling: (a).** Two grounds, either sufficient.

**Ground 1 — the frozen set admits nothing else.** AC-134 demands `w_sparse` **exactly
1.0** when the conjunction matches every crystal in the searched layer. Option (b)
(fetch-relative, `1 - (n_sparse-1)/(cap-1)`) resolves that case to
`1 - 4/29 = 0.862 -> w_sparse 1.862`, red. Option (c) (per-token IDF) has no mechanism that
lands on exactly 1.0 when a *conjunction* saturates while its tokens individually do not.
Option (d) makes AC-109 ("strictly greater than 1.0") unsatisfiable. AC-117 and AC-142
further name `n_scoped` — a searched-layer count — as the denominator by construction.
(b), (c) and (d) each require an amend and are therefore **illegal**.

**Ground 2 — (a) is the only option that has been run.** The measurement resolved it live
on the real stack: `n_sparse=1`, `cap=120`, `N_scoped=31`, `selectivity=0.967741935483871`,
`w_sparse=1.967741935483871`, with no gate regression, using the *existing* bounded
`count_for_export(scope.project, layers=target_layers)`. The A-6 cost objection is
extinguished: no new public storage surface is required, and the hot-path cost is one
indexed aggregate that has already been observed in a passing gate run.

**Scope note carried into the ruling:** the sparse boost is **margin, not cure**, in the
one measured instance (§DP-1, `[DERIVED]`). Keep `alpha = 1.0`; do not raise it chasing
headroom, because every increment moves `score` magnitudes (DP-7) for a benefit the
measured fixture does not need.

### DP-4 — (a), default ON, contingency at its frozen six

**Ruling: (a).** The default-ON argument is #36's, now with evidence #36's could not have:
the shipped configuration (`w_derived=1.0`, `alpha=1`) was **run on the real gate and
passed** while correcting a live inversion in that same fixture. Default-OFF (b) would
ship a product in which spoke1 — a record with zero lexical match — outranks hub, which is
the issue's exact defect, measured live at `ef42967`.

The subsumption under `recall_relevance_primary` (D7) stands for the reason the spec gives:
`recall_relevance_primary=False` is contractually byte-identical to pre-1.9.0 and #36's
AC-008/AC-009 are frozen against it. AC-120 pins it so the half-gated mode #36 DP-R4(iii)
closed cannot re-emerge as an emergent property.

The contingency stays exactly at AC-136's frozen six (AC-121, 122, 123, 124, 125, 133).
Note the ordering consequence of my DP-8 and anomaly-C rulings: **an INDETERMINATE AC-124
is not green**, so C-5's indeterminacy rule feeds AC-136 and can flip the default to
`False`. That is intended.

- **Rejected (b) default OFF** — withholds a measured improvement; makes the fix an
  opt-in faculty when it is a correctness correction; #36's precedent is directly on point.
- **Rejected (c) no new flag** — makes `recall_relevance_primary=false` a two-change
  revert and forfeits the ablation arm the repo's doctrine requires. Also illegal:
  AC-119/AC-120/AC-127 name the field.

### DP-4(ii) — (a), with the honesty conditions made mechanical

**Ruling: (a) — a red AC-140 leaves the default ON, does not block the tag, and routes to
FORGE as a finding, PROVIDED C-12's four conditions are satisfied.**

The decisive observation is about *what configuration a red AC-140 describes*. AC-140
monkeypatches `FETCH_WIDTH_FLOOR` to **1**. The shipped floor is **10**. No operator runs
the configuration AC-140 tests. Meanwhile AC-102 — frozen, and green-required regardless —
asserts the target at fused rank 0 at `k` in `{1, 3, 5, 10, 25}` under the shipped floor.
So a red AC-140 says: *"our correction has a guard-shaped component"*, which is a claim
about the change's taxonomy, not a defect in any behaviour a user can reach.

Flipping the default OFF on that basis would ship unweighted fusion — with the measured
inversion live — to punish a taxonomic disappointment, and it would **not un-layer
anything**: the guard stays either way. Default-OFF is strictly worse on every axis that
has been measured, and better on none.

The legitimate concern behind (b) is honesty, not correctness — "the issue's literal bar is
red and we ship anyway". That concern is fully addressable, and C-12 converts it from a
posture into four observable artifacts: no "cure, not guard" claim anywhere; #38 not closed
as fixed; a follow-up issue naming the residual; the per-`k` table in `verification.md` and
a FORGE hop. If any of the four cannot be produced, the tag blocks.

**A third position, generated and dispositioned.** (c): flip the default OFF only when
AC-140 is red *and* AC-141 is green (i.e. the fixture was proven floor-sensitive, so the
red is a measurement rather than an artifact). This is a genuine improvement on (b) and I
tested my ruling against its strongest form: even with AC-141 green, the analysis above is
unchanged — the failing configuration is still one nobody runs, and AC-102 still holds at
the shipped floor. So (c) does not move the ruling. What it does earn is a **recording**
requirement, folded into C-12: `verification.md` must state which shape the red took,
because "measured failure" and "unfalsifiable" have different consequences for F-A and for
the follow-up's scope.

`[RISK]` The measurement gives advance warning that AC-141 may be unobtainable on a
naively-built fixture: BGE-m3 placed the distinctive-token target at dense rank **1**, not
4 (measurement §7), and at dense rank 1 the reverted build also seeds `[target]` at
`fetch_width=1`, so AC-141 cannot go green. C-4 closes this before it costs a cycle.

### DP-5 — (c), defer the fix, land the evidence

**Ruling: (c).** The defect is real, source-confirmed, and fires at `j >= 1`. It is also
arm-internal, orthogonal to fusion weighting, and — decisively — **unmeasurable today**:
every crystal in `evals/retrieval_gate.py` is committed to `episodic`
(`retrieval_gate.py:88-102`), so the only gate in the repo is single-layer in practice.
Anomaly C compounds this: the gate is not merely single-layer, it is confounded on the axis
it does measure (§3-C). Landing an unmeasurable reordering of every multi-layer recall,
inside the change whose thesis is "the previous fix was a guard, not a cure", would repeat
precisely the error being corrected, and would do so with **no frozen criterion able to
observe it** — the campaign's own standing rule forbids exactly that.

AC-126 already mandates the evidence (`cross_layer` axis on the new fusion gate), so
deferral costs nothing that this change was going to deliver.

- **Rejected (a) round-robin interleave / (b) score merge now** — both legal under the
  freeze (no criterion forbids them) and both would ship a reordering of every multi-layer
  recall with no oracle. If a future FORGE prefers (a), the spec's own condition holds:
  AC-126's fixture lands **first**, not alongside.

### DP-6 — (b), defer; and the measurement names the real target

**Ruling: (b).** The floor is a *stability* device; making it a function of corpus size
makes the ranking universe a function of unrelated commits, which breaks the run-to-run
comparability that AC-124's before/after diff and every deterministic eval gate in this
change depend on. That argument was reasoned in the spec; the measurement now supplies the
missing datum for the deferred question: **`dense_ranking` held exactly 30 ids
(`candidate_k`) against a 31-crystal corpus, and `candidate_k` is what cut spoke2 out of
the dense arm entirely.** The recall ceiling a growing corpus actually threatens is
`candidate_k = max(k*3, 10)` (`retrieve.py:324`), not `FETCH_WIDTH_FLOOR` — exactly as the
spec predicted, now with an instance.

Operative additions: `explain.fusion` carries `fetch_width` **and `candidate_k`** (C-6) —
`cap` alone is a product (`candidate_k * len(target_layers)`) and hides the term the
deferred decision is about. Follow-up **D-4** owns the scaling question, scoped to
`candidate_k`.

### DP-7 — (a), and the freeze had already decided it

**Ruling: (a).** AC-116 requires `score` to equal *the record's weighted fused value*; (b)
normalisation and (c) dual-surface both contradict it, and (c) additionally needs a
`CrystalSummary` field against `extra="forbid"` plus a schema edit AC-129 is written to
avoid. Both are **illegal** (§4). On the merits (a) is also right: `score` is already
documented as a raw hybrid-retrieval RRF value (`server.py:186-197`) and is not comparable
across queries today either; normalising would make it *look* comparable while staying
query-relative — a worse contract than the honest one.

The magnitude shift is real and now measured: hub moves 0.032787 -> 0.048652 on the shipped
eval fixture, and the attainable maximum rises with `1 + alpha` on the sparse term.
**Binding regardless of choice (AC-128):** the manifest and CHANGELOG say `score` is
weighted. Any illustrative figure in the CHANGELOG must come from the implementation's own
run, never from `measurement.md`'s prototype (C-10).

### DP-8 — (a) ships, anomaly A routes out, and the real-stack claim gets bounded

This is the ruling the measurement most changed, so it is stated as a three-part split.

**(i) What this change ships: D5, exactly as specified, outside the flag.** Two
consumer-side sorts in `retrieve.py`, no storage API change. They are correct, they are
cheap, and they fix a real channel: the fused order is currently a function of set
iteration order over ids whose hashing is per-process randomised.

**(ii) What this change does NOT ship: anomaly A.** Four reasons, each independently
sufficient:

1. **Scope.** `storage/graph.py` is outside the 13 declared globs — vigil verified the
   exclusion as correct scope hygiene in round 1. Fixing A requires a scope re-declaration
   and a `ramza-drift --declare` re-run, mid-change, on a store method with no call-site
   audit.
2. **Evidentiary basis.** Fixing A changes arm *membership*. AC-124's threshold is
   `eval-before.json` "captured before any code change"; a membership change inside the
   same commit range makes the before/after diff attribute two changes at once and renders
   the non-inferiority verdict uninterpretable.
3. **No oracle.** The frozen 42 contain no criterion for A. Shipping it would violate this
   campaign's own standing rule — an oracle must be shown to differ across the
   implementations it distinguishes — in the change that generalised the rule.
4. **Blast radius.** `neighbor_expand` is a shared store method; DP-8 itself deferred the
   return-type change to D-3 "with a proper call-site audit", and no audit exists.

**Explicitly rejected: the clever in-scope workaround.** A per-seed union in `retrieve.py`
(`set().union(*(neighbor_expand([s]) for s in seed_ids))`) would repair membership without
touching `graph.py` and therefore without tripping the drift gate. It is rejected: it
carries every evidentiary consequence of (2) and (3), adds `fetch_width` Kuzu round-trips
to the hot path, and papers a store defect at the consumer — guaranteeing a double-fix when
F-A lands. Naming it here is deliberate, because an implementer will otherwise invent it.

**(iii) What replaces the deferred fix: bounded claims and a multi-run protocol, not a
caveat.** The doctrine "a guard must not stand in for a cure" is honoured by refusing to
*claim* the cure, and by making the residual visible where it can corrupt this change's own
gates:

- **AC-131 compliance** is discharged at AC-131's own fixture, whose derived arms are mocked
  (its VERIFY names `test_fusion_weighting.py`, the Layer-2 file with `MagicMock` vector and
  graph stores). D5 satisfies it. **C-3** makes that honest in both directions: the mocks
  MUST return `set[str]` / `dict[str, float]`, mirroring `graph.py`'s real return types —
  otherwise `ef42967` iterates a list deterministically and the mandatory RED-first
  demonstration is unobtainable for a reason unrelated to the defect (the F3 species) — and
  `verification.md` MUST record that **AC-131 green licenses only "the fused order is
  hash-seed-independent given fixed arm contents", never "the graph and completion arms are
  deterministic on the real stack"**, which the measurement shows is false.
- **Every real-`GraphStore` rank criterion** (AC-125, AC-138, AC-139, AC-140, AC-141) is
  evaluated under **C-2's multi-run protocol**. This is the instrument that keeps those
  criteria from becoming coin flips while A is open, and it is strictly a *strengthening* —
  the normative THEN is unchanged, it is simply required to hold under more samples, which
  needs no amend. Note that seed pinning (DP-8(c)) could not do this job even if doctrine
  allowed it: the measurement observed `context_rank.both` varying 4 -> 2 across two runs at
  the *same* seed, because crystal ids are `uuid4`-fresh per run.
- **The release notes** scope the determinism claim to consumer-side ordering and name the
  residual with a link to F-A (C-10); **AC-137's BENCH-NOTES annotation** names *both*
  mechanisms and records the observed value set {2, 4, 5} (C-11). Without C-11 the
  annotation would attribute the whole variance to the half that got fixed, and the next
  reader would file a bug when the figure still moves after 1.10.0 — a new false document
  produced by the criterion meant to retire one.

`[RISK]` **AC-139 may be unfalsifiable in the opposite direction.** Its THEN requires the
target's rank to *change* when the floor goes 10 -> 1000 on the reverted build. Under
anomaly A, widening `seed_ids` does not change `seeds[0]`, so the direct graph arm is
unaffected — but the walk's hash-random choice is drawn from a larger pool, so the rank may
change *for reasons of noise*, satisfying the literal text while carrying no information.
C-2 closes this by requiring the two arms' rank **distributions to be disjoint** across
runs; an overlap makes AC-139 **INDETERMINATE**, which is not green, which triggers its own
escape hatch: AC-138 must be **moved, not weakened**. If the move is blocked on F-A, that is
recorded and returned to FORGE — never resolved by an implementer.

- **Rejected (b) ordered `neighbor_expand`** — better engineering, out of declared scope,
  no call-site audit; folds into F-A.
- **Rejected (c) pin `PYTHONHASHSEED`** — not a fix; hides the defect from CI while every
  operator process stays irreproducible; and measured to be *insufficient* anyway (fresh
  uuid4 ids move set order at a fixed seed). Also cannot satisfy AC-131, which varies the
  seed by construction.

### DP-9 — (b) active-only, tracking `recall_active_only`

**Ruling: (b).** This is the recorded maker/checker disagreement, and it is worth stating
that it is not a live conflict: vigil prescribed all-statuses on cheapness/faithfulness
grounds, then in round 3 **ruled vivi's argument the stronger one** and escalated rather
than overruling. I am ratifying the escalated position, not overriding a standing checker
objection. **The measurement does not discriminate DP-9** — its fixture is a fresh
31-crystal store where every crystal is active, so (a) and (b) coincide. This ruling is on
mechanism and doctrine, and is scored accordingly (§8).

**Why (b).** The weight's job is to express how far the lexical arm narrowed the corpus
*for the ranking the caller receives*. That ranking is active-only by default
(`recall_active_only=True`, `config.py:225`; `_is_active` at `retrieve.py:482-505`). Under
(a), the weight is computed over a population that includes records the caller will never
see — and under CRYSTALIUM's P0-5 (write-new, never hard-delete) those records are
*lexical near-duplicates of the very crystal the distinctive query is looking for*. The
worked case reproduces on both parties' arithmetic: 1 fresh crystal plus 50 superseded
revisions in a layer of 100 active + 50 deprecated gives `w_sparse` 1.66 under (a) and 1.99
under (b), while the caller sees exactly one record either way. (a) therefore lets
invisible history dilute the signal that decides the visible ranking, monotonically, as the
store ages — which is R-9, the risk the campaign built AC-142 for.

A second, sharper framing: under (a), `w_sparse` — a value surfaced in `explain` and,
through the fusion, in `score` — becomes a function of history the caller cannot observe or
control. Under (b) it is a function of (query, active corpus): reproducible from what the
caller can see. A surfaced number whose value drifts with invisible state is the species
this repo's memory names "the lockfile can lie", in a mild form.

**(a)'s best argument, and why it does not carry.** (a) has genuinely lower implementation
risk: one count, no numerator filter, no conditional branch, and it cannot produce the
reverse mismatch (active numerator against an all-statuses denominator, `w_sparse=1.3333`)
that a half-implemented (b) produces. That advantage is **neutralised by a frozen
criterion**: vigil's round-4 enumeration verified AC-142 catches all four population
pairings — the invariant clause catches the mixed direction, the VERIFY weight assertion
catches the reverse. (b)'s distinctive failure mode is the one the oracle was built for.

**Two further positions, generated and dispositioned.** (c) *make the population a config
field*: rejected on the repo's own doctrine — an unmeasured knob must be earned by an eval
(the reasoning that killed #36 DP-1's option O2), and this one would ship two untested
branches instead of one. (d) *the mixed implementation* (active denominator, raw numerator):
named only because it is what a careless implementer produces; it is the defect AC-142
exists to forbid.

**Three mechanical constraints ride with the ruling** (C-7, C-8, C-6), and two are traps a
straightforward (b) implementation falls into:

1. **The censoring test uses the RAW `len(sparse_ranking)`, never the filtered count.**
   Censoring asks "was the fetch truncated by the cap?" — a property of the fetch, not of
   the active subset. A store returning 120 raw hits (= `cap`) of which 3 are active would,
   under a filtered censoring test, resolve a near-maximal boost on a fetch whose true match
   count is unknown and `>= cap`. AC-110 ("GIVEN a query whose sparse ranking length reaches
   the fetch cap ... THEN exactly 1.0") already requires the raw reading; C-7 makes it
   explicit before it is got wrong.
2. **`explain.fusion.n_sparse` is the population-resolved numerator; `arm_sizes.sparse` is
   the raw ranking length. Under (b) on a mixed store they differ** (100 vs 150 at AC-142's
   fixture). Setting both from one variable either makes `arm_sizes` lie or drives AC-142
   red on a *correct* implementation. C-6 pins the contract.
3. **No status predicate on `bm25_search`.** It is shared; a predicate there silently
   changes every caller's candidate set and is out of scope. The active count is taken from
   the rows already in hand (`_row_to_dict`), for weight purposes only.

**Residual, recorded rather than fixed.** (b) does not repair the pre-existing status
blindness of the *candidate set*: `bm25_search` applies `LIMIT candidate_k` with no status
filter, so deprecated near-duplicates consume fetch slots, can push raw `n_sparse` to `cap`
and trip the censoring branch to `w_sparse = 1.0`, and can crowd active hits out entirely.
Under (b) this becomes the **dominant remaining aging path** for the feature. Out of scope;
follow-up **F-D** (C-13).

`[REVERSAL-CONDITION]` (b) assumes the status field is present on `bm25_search`'s returned
rows. Both maker and checker assert this; neither cited the field name. C-8 makes it a
pre-flight check with a stated fallback: if status is not available without extra I/O, take
(a), record the reason in `verification.md`, and do **not** add I/O or a shared-method
predicate to rescue (b).

---

## 3. Anomaly dispositions

### A — `neighbor_expand` returns only the first seed's neighbours: **FOLLOW-UP ISSUE (F-A), high severity; NOT in scope for #38**

Full disposition is DP-8 above. Summary: `graph.py:205-256` wraps the entire
`for seed_id in seed_ids` loop in one `try`, and Kuzu raises at cursor exhaustion, so the
first seed's row loop aborts the whole expansion — `neighbor_expand(seeds) ≡
neighbor_expand([seeds[0]])`, reproduced by probe (A -> `[id4]`, B -> `[]`, C -> `[id5]`).
`decaying_walk` passes `list(frontier)` from a **set**, so *which* seed survives is
hash-random: this is membership nondeterminism, not merely order, and D5 does not touch it.

In-change obligations that A generates: C-2 (multi-run protocol), C-3 (AC-131 scoping),
C-10 (release-note scoping), C-11 (BENCH-NOTES annotation naming both mechanisms), C-13
(open F-A before the tag). Out-of-change: everything else.

### B — records at or above seed rank are structurally barred from the derived arms: **EVIDENCE-NOTE + FOLLOW-UP ISSUE (F-B)**

`neighbor_expand` filters `if neighbor_id not in seed_ids`; `decaying_walk` seeds
`visited = set(seed_ids)`. B is **not primarily a defect** — excluding your own seeds is
defensible behaviour for arms whose purpose is to find *new* records. Its force is
epistemic, and it is large:

1. **It refutes the issue's premise.** #38's acceptance sketch requires competitors at
   dense ranks 1–3 that *also* carry graph and completion votes. That configuration cannot
   occur. The measurement independently confirmed the sketch is unbuildable (§7); the
   shipped fixture contains a better and *real* instance of the same class (spoke1 over
   hub).
2. **It refutes H-A independent of any F1 number** (DP-1, line 2).
3. **It is why D2 yields H-D's invariant as a theorem** (DP-1).

Therefore: record it in `verification.md` as an evidence-note, and cite it when #38 is
closed — the issue's *class* is fixed and measured; its *illustration* was based on a
configuration the code cannot produce. The open design question it raises (should a strong
graph neighbour that is *also* a top-dense hit get no derived credit at all?) is genuinely
interesting and genuinely out of scope: follow-up **F-B**.

### C — the retrieval gate's fixture is confounded: **EVIDENCE-NOTE + a binding interpretation rule for AC-124 + FOLLOW-UP ISSUE (F-C)**

Measured: edge counts flat **2**, context **2**, completion **142**, both **142**. Cause:
`server.py:522,535` sets `link_cooccurrence = config.recall_completion`, so flipping the
completion flag also changes the graph at **commit** time; and `recent_crystal_ids` does
`ORDER BY created_at DESC LIMIT 5` while the fixture stamps every crystal with an identical
`_T0`, so "the 5 most recent" resolves to the 5 **first-committed** crystals. The measured
edge-target histogram is `{spoke1: 30, hub: 30, spoke2: 29, noise1: 27, noise2: 26}` —
both ground-truth spokes are direct co-occurrence neighbours of nearly every crystal. The
gate's own docstring ("Edges are seeded in EVERY arm, so the only variable is whether the
recall walk / re-rank runs — isolating the faculty, not the fixture") is contradicted by
2 versus 142.

**Ruling on how AC-124 may be read at verification time** (so the checker does not have to
improvise it):

**What AC-124 CAN license.** A **non-inferiority tripwire on the incumbent gate**: "the
fusion change did not lower `multihop_f1.completion`, and `completion_pass` stayed true, on
the identical fixture". This reading is legitimate *despite* the confound, and for a
precise reason: **the confound is a property of the fixture, and the fixture is identical
on both sides of the comparison.** A confounded metric remains a valid change detector when
the confound is held invariant. That invariance is not free — C-5 makes it a checkable
precondition.

**What AC-124 CANNOT license.** (i) Any claim that multi-hop retrieval quality *improved*,
or was preserved *in general* — the axis is a single fixture with a known artifact.
(ii) Any claim about the completion faculty's isolated contribution: the completion flag
changes the corpus's edge set (2 -> 142), so the "ablation" compares two different graphs.
(iii) Any inference that a green AC-124 shows the derived-family merge preserves multi-hop
*chains* — the F1 lift is substantially carried by `created_at`-tie co-occurrence edges,
not by the seeded 2-hop chain. `verification.md` must transcribe these three limits
verbatim beside the AC-124 verdict; the CHANGELOG must not paraphrase a green AC-124 as a
retrieval-quality claim.

**What must not happen in this change:** `evals/retrieval_gate.py` stays **unedited** (it
is correctly outside the declared globs). Editing the fixture between `eval-before` and
`eval-after` destroys the one property that makes AC-124 readable at all. The in-scope
landing spot for this evidence is `evals/BENCH-NOTES.md`, which AC-137 already requires
touching (C-11).

Follow-up **F-C** owns the repair: distinct `created_at` stamps, edge seeding decoupled
from the arm under test (so the docstring's isolation claim becomes true), and the
docstring corrected either way. Severity medium-high — this is the gate that guards every
retrieval change in the repo, and it currently cannot mean what it says.

---

## 4. Rulings foreclosed by the freeze (recorded as a process finding)

The 42 criteria are immutable for this deliberation, and checking each ruling against them
produced a result worth stating plainly: **several DPs presented as open were already
decided by the frozen set.**

| DP | Options that cannot be discharged against the frozen 42 | Blocking criteria |
|---|---|---|
| DP-1 | (a), (c), (d), (e) | AC-104/105/132 name `weighted_rrf_merge_scored`; AC-107/108/135 name the derived-family merge and its `derived_ranking` |
| DP-3 | (b), (c), (d) | AC-134 (exactly 1.0 on a layer-saturating query); AC-109 (strictly > 1.0); AC-117/142 name `n_scoped` |
| DP-4 | (c) no new flag | AC-119, AC-120, AC-127 name `Config.recall_weighted_fusion` |
| DP-7 | (b), (c) | AC-116 (`score` equal to the weighted fused value); AC-129 + `extra="forbid"` for (c) |
| DP-8 | (c) seed pinning | AC-131 varies `PYTHONHASHSEED` by construction |

Legal-but-rejected options (DP-2's 0.95, DP-4's default OFF, DP-4(ii)(b), DP-5's (a)/(b),
DP-6's (a), DP-8's (b), DP-9's (a)) were ruled on merit, not on legality.

**The finding, stated without blame.** Freezing criteria against a recommended design is
normal and correct; it is what makes the criteria falsifiable. But when a DP is declared
"genuinely open" while its alternatives cannot be discharged against the frozen set,
FORGE's real choice is **ratify or escalate for an amend** — and that should be visible at
the top of the docket rather than discovered during deliberation. In this instance the
question is moot in the best possible way: the measurement independently selects the same
option the freeze admits. Had the measurement gone the other way — had H-B regressed the
gate — the correct outcome would have been escalation and a fifth amend, **not** shipping
(b) because it was the only legal option. That the two roads converged is the reason this
deliberation ratifies rather than escalates. Recommended for the campaign's methodology
notes: a right-sizing/assemble check that flags DPs whose alternatives are freeze-blocked.

---

## 5. Cross-DP consistency chain (verified)

1. **DP-1(b) -> DP-2(1.0) -> AC-108/AC-135 discharge.** The identity property is a property
   of the family merge *at weight 1.0*; ruling any other default would put both criteria at
   risk and forfeit the only measured-bitwise property in the design.
2. **DP-3(a) + DP-9(b) -> AC-142 discharges under either reading, and AC-110 stays green
   only under C-7.** The population-parity ruling supplies AC-142's operands; the raw
   censoring test supplies AC-110's. Getting either backwards drives a correct
   implementation red.
3. **DP-9(b) -> C-6's explain contract -> AC-117 + AC-142.** `n_scoped_status` names the
   population applied to **both** ends; `n_sparse` is the resolved numerator and
   `arm_sizes.sparse` the raw length. Without the split, a correct implementation fails its
   own oracle.
4. **DP-8(a) + anomaly A open -> C-2 -> AC-136.** Real-`GraphStore` rank criteria become
   multi-run; an INDETERMINATE AC-125 is not green; AC-125 is in AC-136's contingency;
   therefore unresolved store-side nondeterminism can flip the shipped default to `False`
   mechanically rather than by argument. That is the intended coupling.
5. **Anomaly C -> C-5 -> AC-124 -> AC-136.** An indeterminate AC-124 is not green and
   therefore flips the default. The confound is thus handled by the change's own contingency
   machinery instead of by a caveat.
6. **DP-4(ii)(a) + C-12 -> #38's closure text.** The issue may not be closed as "fixed" on a
   red AC-140; the honesty conditions are what make default-ON defensible without the
   literal bar.
7. **DP-6(b) + DP-5(c) -> D-1 and D-4 carry the deferred questions with measured evidence
   attached**, not as punts: AC-126 supplies D-1's axis, the 30-of-31 `candidate_k`
   truncation supplies D-4's first datum.

---

## 6. CONDITIONS (binding; the rulings hold only if these hold)

- **C-1 — Scope fence.** Do not modify: `mcp-server/src/crystalium/storage/graph.py`
  (anomaly A -> F-A); `evals/retrieval_gate.py` (destroys AC-124's comparability);
  `rrf_merge` / `rrf_merge_scored` (AC-106); any pre-existing test in `test_rrf.py`
  (AC-106, byte-identical); the per-layer append loop at `retrieve.py:326-360` (DP-5);
  `FETCH_WIDTH_FLOOR`'s constant nature (DP-6); `k` semantics; `bm25_search`'s predicate
  (DP-9). No new runtime dependencies. No nexus roster bump. **No consumer-side per-seed
  union workaround for anomaly A** in `retrieve.py`.
- **C-2 — Multi-run determinism protocol.** Every criterion asserting a rank position
  against a real `GraphStore` (AC-125, AC-138, AC-139, AC-140, AC-141) is evaluated over
  **>= 5 independent runs** (fresh process, fresh store; vary `PYTHONHASHSEED` across at
  least 0, 1, 2 and unset). PASS requires **unanimity**; a split verdict is **RED and a
  finding**, never a retry. For AC-139 (a "must differ" node) PASS additionally requires the
  floor-10 and floor-1000 rank **distributions to be disjoint**; an overlap makes AC-139
  INDETERMINATE, which is not green, which triggers its own escape hatch (AC-138 moved, not
  weakened). Every observed value set is transcribed into `verification.md`. This is a
  strengthening of VERIFY practice, not a criteria change.
- **C-3 — AC-131 fixture typing and claim scope.** If AC-131's derived arms are mocked (the
  natural reading of its VERIFY file and the Layer-2 template), the mocks MUST return
  `set[str]` for `neighbor_expand` and `dict[str, float]` for `decaying_walk`, mirroring
  `graph.py`'s real return types — otherwise `ef42967` iterates deterministically and the
  mandatory RED-first demonstration is unobtainable for a reason unrelated to the defect.
  If a real `GraphStore` is used instead, AC-131 falls under C-2 and may be blocked on F-A —
  record it, never weaken it. `verification.md` MUST state that AC-131 green licenses only
  *"the fused order is hash-seed-independent given fixed arm contents"*.
- **C-4 — AC-140/AC-141 fixture construction.** The tests live in `test_fusion_weighting.py`
  (per VERIFY) but MUST construct a **real `GraphStore`** (per the same criterion's binding
  guidance). The **vector arm may be a deterministic stub** with pinned embeddings: the
  criteria require only the graph store to be real, and the Terminology block's mandated
  dense-rank-4 shape is not reliably obtainable from a real embedder — measurement §7 put
  the distinctive-token target at dense rank **1**, which would make AC-141 unobtainable and
  the whole thesis pair a no-op. Record the realised per-arm ranks in `verification.md`
  before running the pair.
- **C-5 — Eval capture discipline and the AC-124 indeterminacy rule.** `eval-before.json` is
  captured **before any code change**, from an unmodified `evals/retrieval_gate.py`, with
  identical config for `recall_completion` and every flag feeding `link_cooccurrence`
  (`server.py:522,535`), and identical corpus construction. Capture **>= 3 runs per side**.
  AC-124 is **green iff `min(after) >= max(before)`**; if the after-set straddles the
  before-set the criterion is **INDETERMINATE**, which is not green — record the
  distributions and route to FORGE; the checker may not self-rescue by re-running. The three
  "cannot license" limits of §3-C are transcribed verbatim beside the verdict.
- **C-6 — `explain.fusion` contract.** Keys: `weighted`, `w_sparse`, `w_dense`, `w_derived`,
  `selectivity`, `n_sparse` (**the population-resolved selectivity numerator**),
  `n_sparse_cap`, `n_scoped`, `n_scoped_layers`, `n_scoped_status` (`active_only` |
  `all_statuses`, naming the population applied to **both** ends), `fetch_width`,
  **`candidate_k`**, `arm_sizes` (where `arm_sizes.sparse` is the **raw** ranking length and
  may differ from `n_sparse` under DP-9(b)). §D8's stale `corpus_n` is dropped (N-1). A code
  comment states the `n_sparse` / `arm_sizes.sparse` distinction. `explain` and the surfaced
  `score` may never disagree.
- **C-7 — Censoring uses the raw count.** The `n_sparse >= cap` censoring branch tests
  `len(sparse_ranking)` **before** any status filtering; the selectivity ratio uses the
  population-resolved numerator. AC-110 depends on this.
- **C-8 — DP-9(b) implementation fence.** (i) Pre-flight: confirm the status field is
  present on `bm25_search`'s returned rows (`_row_to_dict`); if it is not available without
  extra I/O, **fall back to DP-9(a)** and record the reason — do not add I/O and do not add
  a predicate to the shared method. (ii) The active count is computed within
  `sparse_ranking`, for weight purposes only; the sparse arm, candidate set and fused
  ranking are untouched. (iii) The population is resolved once per recall and tracks
  `recall_active_only`. (iv) Tested at **both** `recall_active_only=True` and `False`
  (mirroring #36's C-3 dual-config discipline) — an untested branch rots.
- **C-9 — Config field documentation.** `fusion_weight_derived`'s comment records: the
  measured cliff (0.90 deterministic fail / 0.95 red at `PYTHONHASHSEED=5`, 1.0 % margin /
  1.00 pass 7/7); that any value `< 1.0` forfeits the measured identity property; that any
  value `> 1.0` re-creates P1 (a derived-only record at `w/61` can then outrank a
  two-base-arm record at `2/61`). The absent `fusion_weight_sparse` keeps its
  "RRF ordering is invariant to a global positive scale" comment so its absence does not
  read as an oversight.
- **C-10 — Release-note honesty.** CHANGELOG `[1.10.0]` states: `score` is now a **weighted**
  fused value with shifted magnitudes and unchanged ordering semantics (any illustrative
  figure comes from the implementation's own run, never from `measurement.md`'s prototype);
  the determinism fix is scoped to **consumer-side ordering**, with the residual store-side
  membership nondeterminism named and linked to F-A; the four config fields; the revert
  lever. No sentence may claim graph/completion arm determinism generally, and — if AC-140
  is red — none may claim the fetch-width floor has been replaced (C-12).
- **C-11 — AC-137's annotation content.** The `evals/BENCH-NOTES.md` entry retiring the F-V6
  figure names **both** mechanisms (P3 consumer-side ordering, now fixed; anomaly A
  store-side membership/cardinality, still open and linked to F-A), records the measured
  value set `context_rank.both ∈ {2, 4, 5}` including the 4 -> 2 variation at a fixed seed,
  and states that the figure **remains run-varying after 1.10.0**. The same entry records
  anomaly C's confound and links F-C.
- **C-12 — Red-AC-140 honesty conditions (DP-4(ii)).** If AC-140 is red the flag still ships
  `True` and the tag is not blocked, **iff all four hold**: (1) no "cure, not guard" /
  "replaces the fetch-width floor" claim appears in the CHANGELOG, the manifest, the PR body
  or the issue comment; (2) #38 is **not** closed as fixed — it stays open or is closed with
  an explicit "partial: the floor remains load-bearing at k < 10" note; (3) a follow-up issue
  is opened naming the residual, with the per-`k` table; (4) `verification.md` carries the
  per-`k` table, states which shape the red took (AC-141 green = measured failure; AC-141 not
  green = indeterminate), and the result is routed to FORGE as DP-1 input. If any of the four
  cannot be produced, **the tag blocks and the change returns to FORGE**.
- **C-13 — Follow-up issues opened before the tag.** **MUST**: F-A, F-B, F-C, F-D, D-1
  (§7). **SHOULD**: D-2, D-4. F-A's text MUST require, as part of *its* eventual fix, a
  re-baselined `eval-before.json` and a re-run of #38's AC-124/AC-125/AC-133 plus a re-check
  of the DP-2 default, because its repair changes arm membership.
- **C-14 — Deviation protocol.** Any deviation from these rulings, or any implementation
  choice that would require amending `spec.criteria.md`, returns to FORGE before the tag —
  no implementer judgement call (mirrors #36 C-10).
- **C-15 — Freeze integrity.** `spec.criteria.md` stays at
  `sha256 e644052e868db47b49c7daedba904e9f53b67d401c81bde0b5e2887ffcb2fded`. No ruling here
  requires an amend. Any criteria change goes through `ramza-freeze --amend --reason` with a
  regenerated `change.json`; a silent edit is tamper evidence.

---

## 7. Follow-up issue splits (concrete)

| id | title | severity | opened by | content |
|---|---|---|---|---|
| **F-A** | `neighbor_expand` returns only the first seed's neighbours | **high** | MUST, this change | `graph.py:205-256` wraps the whole `for seed_id in seed_ids` loop in one `try` and Kuzu raises at cursor exhaustion, so the first seed aborts the expansion: `neighbor_expand(seeds) ≡ neighbor_expand([seeds[0]])`. Probe: `[id1,id2] -> [id4]`, `[id0,id1,id2] -> []`, `[id2,id1] -> [id5]`. `decaying_walk` passes `list(frontier)` from a set, so which seed survives is hash-random — membership, not just order. Observed: completion arm cardinality 2 and 4, four orderings; `context_rank.both ∈ {2,4,5}`. Fix must land with a per-seed store unit test, a `neighbor_expand` call-site audit, D-3's discovery/BFS-order question folded in, a re-baselined `eval-before.json`, and a re-run of #38's AC-124/AC-125/AC-133 plus a DP-2 default re-check. Note that #38's measurements were all taken on a one-seed expansion. |
| **F-B** | Seeds are structurally excluded from both derived arms | med | MUST, this change | `neighbor_expand` filters `if neighbor_id not in seed_ids`; `decaying_walk` seeds `visited = set(seed_ids)`. Consequence: a record at or above seed rank can never receive graph or completion credit, so a strong graph neighbour that is also a top-dense hit is systematically under-credited — and #38's acceptance sketch (competitors at dense 1–3 *with* derived votes) describes a configuration the code cannot produce. Decide whether seed exclusion should be relaxed (e.g. credit a seed's own derived support without re-expanding it). |
| **F-C** | The retrieval gate's fixture is confounded; its isolation docstring is false | med-high | MUST, this change | Measured edge counts: flat 2, context 2, completion 142, both 142. `server.py:522,535` sets `link_cooccurrence = config.recall_completion`, so the flag under test changes the commit-time graph; `recent_crystal_ids` (`ORDER BY created_at DESC LIMIT 5`) resolves to the 5 first-committed crystals because the fixture stamps an identical `_T0`; edge-target histogram `{spoke1:30, hub:30, spoke2:29, noise1:27, noise2:26}`. Fix: distinct `created_at` stamps, edge seeding decoupled from the arm under test, docstring corrected. Gate-guards-everything severity. |
| **F-D** | Sparse candidate set is status-blind (`LIMIT candidate_k`, no predicate) | med | MUST, this change | `bm25_search` applies `LIMIT candidate_k` with no status filter, so under P0-5 accumulation deprecated near-duplicates consume fetch slots: they can push raw `n_sparse` to `cap` (tripping the censoring branch to `w_sparse = 1.0`) and can crowd active hits out of the candidate set entirely. Pre-existing and independent of #38; becomes the dominant aging path for the sparse boost once DP-9(b) ships. |
| **D-1** | Cross-layer rank blocking (layer-order-primary, relevance-secondary) | med-high | MUST, this change (DP-5) | `retrieve.py:326-360` appends per layer over `_ALL_LAYERS`, so with `layers=None` an episodic hit always precedes every semantic hit regardless of BM25 score; the inversion fires at `j >= 1` (severity table in spec §Deferred). Arm-internal, so the sparse boost cannot correct it. Attach AC-126's `cross_layer` measurements when they land; land the gate before the fix. |
| **D-2** | `embed(query)` called once per layer | low | SHOULD | `retrieve.py:340` inside the per-layer loop — four identical embeddings per default recall. |
| **D-4** | `candidate_k` corpus scaling (not `FETCH_WIDTH_FLOOR`) | low-med | SHOULD (DP-6) | Measured first datum: `dense_ranking` held exactly 30 ids (`candidate_k`) against a 31-crystal corpus, and `candidate_k` — not the seed-width floor — is what cut spoke2 out of the dense arm. The floor must stay constant for eval reproducibility; the per-layer fetch is where scaling belongs, and it needs measurement this change does not supply. |

---

## 8. Confidence, reversal conditions, and what is NOT licensed

| DP | Confidence | `[REVERSAL-CONDITION]` |
|---|---|---|
| DP-1 (b) | 96 | A real-stack measurement on a **deconfounded** gate (post-F-C) showing family-merge inferior to a static scheme on multi-hop F1; or evidence that anomaly B's seed exclusion is removed (F-B), which would restore the issue's original premise. |
| DP-2 (1.0) | 94 | After F-A lands, a re-measurement across >= 6 seeds showing a value below 1.0 both deterministic and strictly better on both gate axes — with the identity-property loss accepted explicitly. |
| DP-3 (a) | 93 | A measured hot-path cost regression from the per-recall bounded count (R-3), which would move the question to DP-3(b) **and require an amend** of AC-134/AC-117 — i.e. escalation, not an implementer switch. |
| DP-4 (a) | 85 | Any of AC-136's six red -> default `False` mechanically. |
| DP-4(ii) (a) | 78 | A red AC-140 accompanied by evidence that the shipped floor of 10 is *also* insufficient at some `k` a caller uses (i.e. AC-102 red), which would convert a taxonomy finding into a correctness failure. |
| DP-5 (c) | 90 | AC-126 showing cross-layer blocking dominates the fused order on multi-layer recalls, which would make D-1 a release blocker rather than a follow-up. |
| DP-6 (b) | 92 | Measured evidence that seed width, not `candidate_k`, is the binding recall ceiling on a large corpus. |
| DP-7 (a) | 95 | A named consumer demonstrated to depend on `score`'s absolute magnitude — which would still not license normalisation, only a wider migration note. |
| DP-8 (a + C-2) | 82 | AC-139 or AC-141 proving INDETERMINATE under C-2, which blocks the attack pairs on F-A and returns the sequencing question to FORGE. |
| DP-9 (b) | 76 | Status unavailable on `bm25_search`'s rows without extra I/O (C-8 pre-flight) -> revert to (a); or a measured hot-path cost for the active-scoped denominator. |

**Overall verdict confidence: 88.** Evidence quality is high where it matters most (DP-1/DP-2
are measured on the real stack, 26 runs); it is lowest on DP-9, which the measurement does
not discriminate at all, and on DP-4(ii), which is a product call by construction.

**Not licensed by anything in this document:** any claim that multi-hop retrieval quality
improved (§3-C); any claim that the graph or completion arms are deterministic on the real
stack (§3-A, C-3); any claim that #38's acceptance sketch was reproduced (§3-B — it is
unbuildable, and the shipped fixture's spoke1-over-hub inversion is the instance that was
actually fixed); any claim that this change replaces the v1.9.0 fetch-width floor, unless
and until AC-140 is green with AC-141 green as its precondition (C-12).

---

## 9. Escalations and DPs not ruled

**None.** All ten docket items (DP-1..DP-9 including DP-4(ii)) and all three anomaly
dispositions landed on a ruling within the verified evidence, and **no ruling requires
amending the frozen 42** — verified block by block (§4, §5). Two items are recorded as
*process* findings rather than escalations: the freeze-foreclosure of several "open" DPs
(§4), and the staleness of the plan state's H-A explore re-score `72.5` and of spec §D2's
corrected-model table, both superseded by `measurement.md` (§0). Neither is a blocker;
neither is mine to edit.

The three conditions that could *become* escalations during implementation are named with
their triggers: C-5 (indeterminate AC-124), C-8 (DP-9 pre-flight failure), C-12 (a red
AC-140 whose honesty conditions cannot be met). Each returns to FORGE rather than being
resolved by the implementer.

---

## 10. Checker handoff

`[CHECKER-REQUIRED]` — **`requires_checker: true`**, fired on trigger category **5, public
API contract change**. Checker-class hint: **VIGIL** (the claims are evidence-based and
reproducible by a second verification pass, not organizational judgement).

Category-by-category, checked mechanically against the recommended action:

| # | Category | Fired | Why |
|---|---|---|---|
| 1 | Deploy / release | **no** | This verdict authorizes **implementation on a branch**, not a tag. The release is separately gated by AC-136's contingency and by C-12/C-14, each of which returns to FORGE. The rulings are revertible at ordinary cost (`recall_weighted_fusion: false` restores v1.9.0 fusion, seeding and `score` magnitudes; D5 is a code revert). |
| 2 | Destructive migration / data deletion | no | No storage migration, no schema break, no deletion; DP-9 explicitly forbids a status predicate on the shared read path. |
| 3 | Security-boundary change | no | None in scope. |
| 4 | External spend / commitment | no | None. |
| 5 | **Public communication / public API contract change** | **YES** | DP-7 changes the documented semantics of `CrystalSummary.score` — a field in the published `schemas/recall-result.v1.json` and in the `crystalium.recall` tool manifest — in a **shipped, digest-pinned MCP server consumed by every Eidolon**; AC-128 exists precisely because a surfaced number whose meaning changes silently is contract-grade. DP-4's default-ON compounds it: every consumer's next upgrade changes ranking behaviour with no opt-in. |

The flag is a payload marker, not a refusal: implementation may proceed on these rulings.
What it withholds is self-certification past the contract line — vigil (already this
change's ESL checker) adjudicates AC-128's manifest/CHANGELOG wording, C-10's claim
scoping, and the three conditions only a checker can evaluate (C-2's multi-run protocol,
C-5's indeterminacy rule, C-12's honesty conditions) before the tag.

---

## 11. Rulings digest

*Suitable for verbatim transcription into the maker's brief.*

| DP | Ruling | One-line rationale |
|----|--------|--------------------|
| **DP-1** | **(b) family-merge + query-conditional sparse boost; per-arm weights default 1.0** | H-A fails the shipped gate at 6/6 seeds *and* (anomaly B) can only demote the records the issue wants kept; (a)/(c)/(d)/(e) additionally cannot be discharged against the frozen 42. |
| **DP-2** | **`fusion_weight_derived = 1.0`; `< 1.0` legal but out of the documented band** | 0.95 is a flake, not a margin trade — red at `PYTHONHASHSEED=5` on a 1.0 % margin against a completion rank that anomaly A's fix will move; 1.0 carries the bitwise-measured identity. |
| **DP-3** | **(a) search-space-relative selectivity over `target_layers`, alpha 1.0** | The only option that resolves AC-134 to exactly 1.0 — (b)/(c)/(d) each require an amend — and the only one measured live (`w_sparse = 1.9677`, no regression) using an existing bounded count. |
| **DP-4** | **(a) new `recall_weighted_fusion`, default ON, subsumed; contingency = AC-136's frozen six** | The shipped configuration was run on the real gate and passed while correcting a live inversion; default-OFF withholds a measured improvement and forfeits nothing in exchange. |
| **DP-4(ii)** | **(a) a red AC-140 keeps the default ON and does not block the tag — subject to C-12's four honesty conditions** | AC-140 tests `FETCH_WIDTH_FLOOR = 1`, a configuration nobody ships; AC-102 holds at the shipped floor; flipping OFF would ship the measured defect to punish a taxonomy claim, and would un-layer nothing. |
| **DP-5** | **(c) defer the cross-layer fix; land AC-126's evidence; open D-1** | Real, arm-internal, and unmeasurable today — the only gate in the repo is single-layer *and* confounded; shipping an unguarded reordering would repeat the guard-not-cure error being corrected. |
| **DP-6** | **(b) defer floor scaling; surface `fetch_width` + `candidate_k`; open D-4** | A corpus-dependent floor makes the ranking universe drift with unrelated commits; the measurement shows `candidate_k` (30 of 31 crystals) is the real ceiling that cut spoke2. |
| **DP-7** | **(a) surface the weighted fused value; manifest + CHANGELOG say so** | AC-116 forecloses (b) and (c); `score` is already documented as a raw fusion value, and normalising would make a query-relative number *look* comparable. |
| **DP-8** | **(a) D5's two sorts ship; anomaly A -> F-A; plus C-2's multi-run protocol, C-3's AC-131 scoping, C-10/C-11's claim bounding; consumer-side union workaround explicitly rejected** | D5 fixes the consumer-side channel and discharges AC-131 at its mocked fixture; fixing A in-change would breach scope, invalidate AC-124's baseline, ship unguarded, and force a double-fix — so the residual is bounded and made visible instead of claimed away. |
| **DP-9** | **(b) active-only on both ends, tracking `recall_active_only`; numerator computed within `sparse_ranking`, never a predicate on `bm25_search`; censoring uses the raw count** | Population parity with the *response* is the semantically load-bearing parity — under P0-5 the deprecated rows are lexical near-duplicates of the target, so (a) lets invisible history dilute the visible ranking; (a)'s lower implementation risk is already neutralised by AC-142's four-pairing oracle. |
| **Anomaly A** | **Follow-up issue F-A (high); NOT in scope; in-change obligations C-2/C-3/C-10/C-11** | Membership-level defect in an out-of-scope store method with no oracle in the frozen 42; fixing it inside the change would invalidate the measurement that decides DP-1/DP-2. |
| **Anomaly B** | **Evidence-note in `verification.md` + follow-up issue F-B** | It reframes the issue (the sketch is unbuildable), refutes H-A structurally, and explains why D2 delivers H-D's invariant as a theorem — all reasoning, none of it code. |
| **Anomaly C** | **Evidence-note + binding AC-124 interpretation (C-5) + follow-up issue F-C** | AC-124 stays a valid **non-inferiority tripwire** because the confound is invariant across the compared arms; it licenses no retrieval-quality claim, no faculty-isolation claim, and no multi-hop-chain claim. |
| **Gate** | **`requires_checker: true` — category 5 (public API contract change); hint VIGIL** | `score`'s documented semantics change in a shipped, digest-pinned MCP server, default-ON; implementation may proceed, self-certification past the contract line may not. |

---

*FORGE — binding deliberation, delegated HUMAN-DECISION seat. Measurement over model;
freeze over convenience; a bounded claim over a comfortable one.*
