---
eidolon: ramza
kind: spec-amendment
amendment_id: amend-02
version: 1.0.0
created_at: 2026-08-05
change_id: crystalium-residual-eight-plan
maker: ramza
checker: kupo
supersedes: spec.amend-01.md §B.7 (#48 / VP-M1), §A (adds global rule (f)), §B.1 (W-G-XL grant), §C.2 (S-5 probability), §F (items 3-4)
amends_criteria_sha256: 7e680dc63f87439dbfc2dec0220b8df51aa2b33fe776550a18b20f54cfeb05c9
criteria_sha256_after_amend: f385f39bbabb6ee7371afd8815ef2de0e18905a0048d2f4000813edf219b0d9f
target_repo: /home/rynaro/workspace/oss/agents/crystalium
target_head: b7f1a47
---

# spec.amend-02 — `crystalium-residual-eight-plan`

**Supersedes named parts of `spec.amend-01.md`. `amend-01` is NOT rewritten.** Chain:
`spec.md` (frozen) → `spec.amend-01.md` → **`spec.amend-02.md`** (governs on conflict).

**Gates run for this amendment** (P0-2): `ramza-freeze --amend` chained
`7e680dc6… -> f385f39b…` (entry 3 in `state.amendments[]`); `ramza-ears-lint` on
`spec.criteria.amend-02.md` → **ok: 6 criteria pass**. Every jq predicate and the AST body-diff
below was **executed against positive and negative fixtures** during this pass — including the
7-seed C-2 artifact (AC-321 now returns exit 1 on it), a 14-seed artifact with seed 8 swapped
out (exit 1), a missing positive control (exit 1), and a control reporting `false` (exit 1).

Trigger: a defect in **VP-M1** found by the coordinator after `amend-01` was dispatched, and
**independently re-derived from source and from git history during this pass**. `amend-01`
demoted the preliminary VP-M1 result on FORGE D5's one-sidedness grounds. That was correct and
insufficient. The real defect is worse and is a different defect.

---

## 1. K-B17 — VP-M1 AS SPECIFIED CANNOT FAIL. It was guaranteed to return `channel_live == false`.

**Blocking. Maker/coordinator-found by source reading + git dating, not by review.**
This is the campaign's own named defect class — *a gate that cannot fail on the defect it
names* — sitting in the measurement that **gates the entire W-G-FLOOR unit**.

Three independent blindnesses. **They are orthogonal: no one fix removes another.**

### 1.1 Blindness A — the mandated seed set provably excludes the only divergent point

`evals/fusion_gate.py:85-92`, verbatim at `b7f1a47`:

> *"measured over 14 sample points (PYTHONHASHSEED 0-12 and unset) on the id-renamed variant
> (3, above): **exactly ONE point diverges (seed 8**: floor=10 gives one rank, floor=1000
> another — proving the channel is live end-to-end), while **all 13 other sampled points
> (0-7, 9-12, unset) agree** across both floors"*

The C-2 protocol is `{0, 1, 2, 3, 4, 5, unset}`. That is a **strict subset of the recorded
AGREEING set** `{0-7, 9-12, unset}`. **Seed 8 — the sole divergent point, and the entire basis
for the tree's "channel is LIVE and MEASURED" claim — is not sampled by the protocol VP-M1
mandates.**

⇒ A 7-seed C-2 VP-M1 returns `channel_live == false` **whether the channel is live or dead.**
The measurement has no failure mode. `amend-01`'s §B.7.3 said the preliminary capture
"refutes nothing and confirms nothing" — true, but it understated the cause: the *protocol*,
not the *proxy*, is what made `false` inevitable.

**C-2 is the correct protocol for AC-125 unanimity and the WRONG protocol for floor-channel
detection, and the tree says why** (`fusion_gate.py:65-70` ties C-2's unanimity to the
tie-break, and `:85-92` reports the channel evidence on a 14-point set). Using one protocol for
both questions is the error.

### 1.2 Blindness B — the shipped fixture pins the fused rank AGAINST derived-arm variation

`evals/fusion_gate.py:65-70`, verbatim:

> *"`target` is absent from the dense arm, and `N1` (dense rank 1, uppercase id) is **ALWAYS
> tied** with `target` at `1/61` on the reverted build; the id-ascending tiebreak
> ("N1" < "target") means **`target` never reaches rank 0 there regardless of anything the
> derived arms do** — this is what keeps AC-125 (`gate_pass`) unanimous across every sampled
> seed (0-5, unset — C-2)"*

The fused rank is **deliberately engineered to be invariant to the derived arm**, because that
invariance is what makes AC-125 reliable. Any VP-M1 that reads `retrieved` / `target_rank` is
reading the one quantity the fixture pins against the signal.

**FORGE D5's `graph_store` spy fixes exactly this and only this.** It does not touch Blindness A.

### 1.3 Blindness C — the channel evidence and the probe target are DIFFERENT FIXTURES

`fusion_gate.py:35-43`: variant **(3)** — *"RENAMED so every competitor sorts AFTER `target`
(tried and measured, **then reverted**)"*, which *"regressed AC-125's own reliability (dropped
from 7/7 to ~2/7 unanimous)"*. `fusion_gate.py:45-46`: *"**FINAL shape ships (2)** — uppercase
ids, 12 fillers"*.

The 14-seed / seed-8 evidence was measured on **variant (3)**. `_build_fixture` at `b7f1a47`
builds **variant (2)**. VP-M1's probe therefore **cannot inherit the variant-3 evidence at
all**.

**Consequence that must be stated and not softened:** including seed 8 removes a *provable*
blindness; it does **not** make the measurement complete. On the shipped fixture, seed 8 is
*"the only point where divergence was ever observed on any fixture"* — a **heuristic prior,
not a guarantee**. There is no seed known to diverge on variant (2), because variant (2) has
never been measured for this at all.

### 1.4 Collateral finding — `fusion_gate.py:80-81` is a PRE-#41 claim in shipped source, GIT-DATED

`fusion_gate.py:78-81` grounds the liveness claim in a mechanism that no longer exists:

> *"at floor=1000/seed=0 it is given a 15-element seed set and returns `{}` (the pick lands on
> a edge-less filler first, and **anomaly A's single-seed cap aborts the walk there**). **The
> floor's channel is LIVE and MEASURED**"*

**#41 removed that cap.** Post-#41, `decaying_walk` calls `neighbor_expand(sorted(frontier),
depth=1)` (`graph.py:305`) and `_neighbor_expand_one_hop` loops **every** seed
(`graph.py:215-230`) — "the pick lands on an edge-less filler first" no longer aborts anything.

**Git dating (decisive, not argued):**

| file | last commit at `b7f1a47` | date |
|---|---|---|
| `evals/fusion_gate.py` | `56c8510` *"weighted RRF fusion … (#38) (#49)"* | **2026-08-03** |
| `mcp-server/src/crystalium/storage/graph.py` | `cab9b73` *"open-issues sweep — graph cursor repair … (#41 #43 #46 #47 #50 #51 #53 #54) (#56)"* | **2026-08-04** |

The docstring was written **the day before #41 landed** and **has not been touched since**.
The claim is provably pre-#41 and **nothing on the post-#41 tree has tested it.**

The repo already has the pattern for this: `config.py:304-308` explicitly dates the
retrieval-gate weight cliff as *"HISTORICAL (pre-#41 tree, 56c8510)"* — the **same commit**.
`fusion_gate.py:72-92` simply never got that treatment.

**It is a claim in shipped source that shipped source does not support**, and correcting or
dating it is a deliverable of this campaign (§4).

---

## 2. NEW GLOBAL RULE (f) — positive-capability before a routing negative

**Standing equal to global rules (a)-(e) in `spec.criteria.amend-01.md` §0.1.**

> **(f) Any measurement whose NEGATIVE result would route a disposition MUST first be shown
> capable of producing a POSITIVE.** A probe never demonstrated to emit `true` is not evidence
> when it emits `false`. The demonstration is a named, shipped control, recorded in the same
> artifact as the measurement it licenses.

This is the general form of K-N15 (which caught the instance at AC-352). Rule (f) audit across
every routing negative in the campaign:

| measurement | its negative routes | positive-capability control | status |
|---|---|---|---|
| **VP-M1 `channel_live == false`** | #48's carried claim + fixture design | **NONE existed** | **GAP ⇒ new AC-357** |
| **AC-322 disjointness fails** | S-5 ⇒ D9 class (c), retire AC-138/AC-139 | none — AC-323 shows only that it can go RED | **PARTIAL GAP ⇒ new AC-358** |
| AC-352 `p1_recreated == false` | S-1, keep seed exclusion | `w_derived = 100.0` in-fixture control | satisfied (`amend-01`, K-N15) |
| AC-310 `target_rank == 0` w/ green liveness | S-3 ⇒ D9 class (a), cancel W-45 | C-XL-1 (single-layer control reports rank 0 today) + D8's checker perturbation firing C-XL-2 | satisfied |
| AC-314 `planted_recovered == true` | S-8 ⇒ S-13 | AC-315 (small-corpus control recovers the plant) | satisfied |
| AC-317 `< 2 distinct outcomes` | #55 degeneracy finding | D8's checker perturbation (sever A's edge) collapses it | satisfied |

Two gaps, both closed below. Note the asymmetry that makes AC-322 only *partially* closable:
its fixture-level positive **is the gate passing**, so an in-fixture control would be circular.
§3.2 states the honest split.

---

## 3. REPLACEMENT — §B.7 (#48 / VP-M1)

`spec.amend-01.md` §B.7.2's probe construction (D5's spy, the self-check, the `try/finally`
monkeypatch, the byte-untouched `fusion_gate.py`) **stands unchanged**. What changes is the
**protocol**, the **controls**, and what the result is allowed to license.

### 3.1 VP-M1's seed set — 14 points, seed 8 mandatory

**Normative:** VP-M1 runs over **`PYTHONHASHSEED ∈ {0,1,2,3,4,5,6,7,8,9,10,11,12}` plus one
run with the variable unset — 14 spawned processes.** This is the tree's own evidence set
(`fusion_gate.py:85-86`), chosen because it is the only set **provably containing the divergent
point**.

- Global rule (d) still governs the mechanics: 13 runs with `-e PYTHONHASHSEED=$s`, and a
  **14th that omits `-e` entirely**.
- **C-2 (`0-5` + unset) remains correct and unchanged everywhere else** — AC-125 unanimity
  (AC-344), AC-317, AC-322. Only the *floor-channel* question changes protocol. The two
  questions have different failure modes and the tree records why.
- **Any floor measurement run on fewer than 14 points MUST record, in-artifact,
  `seed_set_covers_divergent_point: false` and `divergent_point_known: "8"`.** A 7-point run is
  not forbidden as a smoke test; it is forbidden as *evidence*.
- **A smaller set is permissible only if it provably contains seed 8** and the artifact records
  the justification. `{0-5, 8, unset}` (8 points) is the minimum defensible reduction.

### 3.2 VP-M1's positive control (new **AC-357**) — the probe must be shown able to say `true`

The probe emits `channel_live` from `any(seed.floor10_derived != seed.floor1000_derived)`.
Before any `false` from it is trusted, the **same probe, same code path, same comparison** must
be shown to emit `true` under a condition **known** to produce a derived-membership difference.

**Normative control — a floor that provably changes the seed slice.** `_build_fixture` puts
`N1/N2/N3` (the only edge-bearing nodes) at dense ranks 1-3 and `F1..F12` at 4-15
(`fusion_gate.py:55-61`). Run the probe at **`floor = 2` vs `floor = 1000`**: `dense_ranking[:2]`
contains `N1, N2` and **excludes `N3`**, while `[:1000]` admits all 15 — so the walk's seed set
differs in membership *by construction*, and any seed reachable only via `N3` changes the
derived union. The control asserts `channel_live == true` for that pair.

- If **`floor=2` vs `floor=1000` also reports `false`**, the probe is **not instrumented** —
  it is not measuring derived membership at all. That is a **probe defect**, not a finding
  about the floor: fix the probe (S-13 step 1) and re-run. **No `channel_live == false` from
  an uncontrolled probe may be recorded, carried, or cited.**
- The control runs at **one** seed (it is a property of the slice, not of hash order) and its
  result is written into the **same artifact** as the measurement.

### 3.3 AC-321 must not be dischargeable by a seed set excluding 8

The seed set is **encoded in the artifact and asserted** (criteria delta §5). AC-321 now
requires: 14 seed rows, the literal label `"8"` present, `self_check_ok` on every row, the
positive control present and `true`, and `channel_live` derivable from the rows.

### 3.4 What VP-M1 may and may not license

| result | licensed conclusion |
|---|---|
| `channel_live == true` (14 pts, control green) | the channel is live at the derived level **on the shipped fixture (variant 2)** post-#41. `spec.md` §4 #48's prediction is **refuted**; carry the tie-break explanation instead. |
| `channel_live == false` (14 pts, control green) | **on the shipped fixture, at 14 sampled points, no derived-membership difference is observable.** NOT "the channel is dead" — variant (2) has never had a divergent seed identified, so an unsampled point cannot be excluded. Record as *"no observable channel at 14/14 sampled points on variant (2), post-#41"*, with the sampled set attached. |
| `channel_live == false`, control **red or absent** | **NOTHING.** Probe defect. Not recordable. |
| any result on `< 14` points | smoke test only; the artifact must carry `seed_set_covers_divergent_point: false`. |

**The routing rule is unchanged: the new between-floors fixture gets built either way.** Only
the carried prose differs.

### 3.5 This RAISES the probability of S-5 / D9 class (c)

Stated plainly, because it makes #48 less closable and that must not be discovered later:

The tree's only evidence that `FETCH_WIDTH_FLOOR` has a live channel is (i) **pre-#41**
(git-dated, §1.4), (ii) measured on a **reverted fixture variant**, and (iii) grounded in a
mechanism (**anomaly A's single-seed cap**) that **#41 deleted**. Post-#41, `neighbor_expand`
expands **all** seeds (`graph.py:215-230`) and `decaying_walk` sorts the frontier
(`graph.py:305`), so the hash-order lottery the divergence rode on **no longer exists**.

⇒ **The most likely outcome of a correctly-instrumented VP-M1 is `channel_live == false` for a
real reason**, and the most likely outcome of AC-322 is non-disjointness ⇒ **STOP S-5 ⇒ S-13
class (c): retire AC-138/AC-139 with a mechanism note, and close #48 as *retired*, not
*discharged*.**

That is a **legitimate closure** (`spec.md` §5, `amend-01` §C.1 step 3(c)) and it is the
outcome this plan should expect. It is **not** a licence to (a) weaken AC-322, (b) hunt for a
fixture until one goes green (S-13 step 2's one-cycle bound), or (c) leave a permanent
strict-xfail (S-13 step 4). **W-G-FLOOR's gate artifact still merges only if its controls are
falsifiable** (S-13 step 5); if the fixture cannot be built, the gate is **deleted, not
merged**, and #48 closes class (c).

### 3.6 AC-322's positive-capability gap (new **AC-358**) — and its honest limit

AC-322's negative routes S-5. Rule (f) demands a positive-capability demonstration, and the
fixture-level positive **is the gate passing** — so an in-fixture control would be circular.
The honest, non-circular split:

1. **Instrument control (shippable, mandatory).** The disjointness verdict is computed by a
   **pure classifier** — no I/O, both branches reachable from in-memory inputs (the
   `retrieval_gate.py:91-114` precedent this plan already cites). It ships with a unit test
   exercising **both** branches on synthetic rank lists: `([0,0], [2,2]) ⇒ disjoint`;
   `([0,1], [1,2]) ⇒ not disjoint`; `([], []) ⇒ not disjoint` (the K-B3 vacuity case).
   This proves the **instrument** can say "disjoint".
2. **Fixture-level positive — explicitly NOT claimed.** Whether *any* fixture makes the floor
   change the fused rank deterministically post-#41 is the open empirical question. There is
   no control for it, and inventing one would be S-11. Its absence is **exactly S-5's
   trigger**, and it routes to D9 class (c).

Recorded as a limit, not papered over: rule (f) is satisfiable for the classifier and **not
satisfiable for the fixture**, and the correct response to the second is a classified closure.

---

## 4. REPLACEMENT — §B.1 ownership delta: who corrects `fusion_gate.py:72-92`

**Constraint collision, resolved.** The pre-#41 prose (§1.4) must be corrected or dated, but
FORGE D5 requires `evals/fusion_gate.py` to be **byte-untouched by W-G-FLOOR**, and §3.1
freezes the file.

**Resolution — no ruling is bent:**

- **W-G-FLOOR touches `evals/fusion_gate.py` not at all.** D5's letter holds; the probe still
  only *imports*.
- The correction lands inside **W-G-XL's existing module-docstring grant**, which `amend-01`
  §B.1 already opened for the `:104-106` hyphen sentence on exactly this reasoning: **§3.1's
  freeze protects `_build_fixture` and `run_arm`'s recall path — the AC-125 measurement —
  not the module docstring.** The grant is extended from `:104-106` to
  **`:72-92` and `:104-106`**.
- **The CONTENT is #48's finding and is authored as such** (the correction cites #41,
  `graph.py:215-230`, `graph.py:305`, and the git dating). W-G-XL owns the *bytes*;
  W-G-FLOOR owns the *claim*. Both are recorded in the #48 closing comment.

**Required text properties** (new **AC-359**), any one of which discharges it, all three
preferred:
1. the liveness claim at `:80-81` is **dated** as pre-#41 — the `config.py:304-308`
   *"HISTORICAL (pre-#41 tree, 56c8510)"* pattern, verbatim in form;
2. it states the mechanism it rested on (**anomaly A's single-seed cap**) was **removed by
   #41** (`graph.py:215-230`, `:305`);
3. it states that **nothing on the post-#41 tree has re-tested it**, and names VP-M1 as the
   measurement that would.

It must **not** be silently deleted: the failure history in that docstring is load-bearing
(*"the failures are kept in this docstring on purpose"*, `fusion_gate.py:14-16`) and deleting
a superseded claim destroys the same record §3.1 exists to protect.

**AC-313's freeze check is restructured** to permit a docstring edit while *strengthening* the
code freeze (criteria delta §5). The `_build_fixture` hash pin is retained and joined by two
more, all computed from the tree at `b7f1a47` during this pass:

| symbol | sha256 of `inspect.getsource` | may it change? |
|---|---|---|
| `_crystal` | `6fa658f431c97b759824408cb5af0f3a98f851dd46c089607c649a39f1930ded` | **no** |
| `_build_fixture` | `66d3e9a7ea3bb8b1830c5d5ea3de7c8f70afef7a098b4a38069677ef6d6b62d4` | **no** |
| `run_floor_probe` | `eeea6f2b86c0f7bd2a647386ecd13f9077fec4fc94e5336f16b1721e3ad1f0d6` | **no** |
| `_FILLER_COUNT` | `12` | **no** (vigil F-V4's cardinality fix) |
| `_QUERY` | `'plarnix threxil vandomere signature'` | **no** |
| `run_arm`, `run` | — | only the `cross_layer` key rename |
| module docstring | — | **yes** — the #48 correction |

This is strictly stronger than `amend-01`'s single pin plus a text filter: three functions and
two constants are now byte-frozen, and the rename surface is bounded to two functions.

---

## 5. STOP-table and §F deltas

| id | delta |
|---|---|
| **S-5** | Trigger unchanged. **Added:** *"A `channel_live == false` from a VP-M1 whose positive control (AC-357) is red or absent does NOT contribute to S-5's evidence — it is a probe defect (S-13 step 1)."* And: **S-5 is now the EXPECTED outcome**, not the exception (§3.5). |
| **S-13** | Unchanged. §3.5 records that #48's most likely terminal state is class (c). |
| **NEW S-14** | **Trigger:** a measurement whose negative would route a disposition is run, or its result recorded, **without** the positive-capability control required by global rule (f). **Action:** the result is **not evidence** and may not be carried, cited, or entered into any closing comment. Build the control, re-run. This is not an S-13 event — the gate is not unfailable, it is **unvalidated**. |

`amend-01` §F (What this amendment does NOT resolve) items 3 and 4 are superseded:

- **item 3** (*"whether AC-322's disjointness is achievable at all post-#41"*) — still open,
  now with a **stated prior**: unlikely, for the three source-grounded reasons in §3.5.
- **item 4** (*"`channel_live` itself"*) — the preliminary capture was not merely one-sided;
  its **protocol could not fail** (§1.1). Superseded by §3.4's licensing table.
- **NEW item 8:** whether the shipped fixture (variant 2) has *any* divergent seed is unknown
  and unmeasured; seed 8 is a prior imported from a **reverted** variant (§1.3).

---

## 6. Findings ledger delta

| id | disposition | where discharged |
|---|---|---|
| **K-B17** — VP-M1 as specified cannot fail; three orthogonal blindnesses (mandated seed set excludes the sole divergent point; the shipped fixture pins the fused rank against derived-arm variation; the channel evidence was measured on a reverted variant) *(coordinator-found post-dispatch; re-derived from `fusion_gate.py:35-43, :65-70, :85-92` and git-dated this pass)* | **ACCEPTED-AS-FILED** | §3.1 (14-point protocol), §3.2 / **AC-357** (positive control), §3.3 / **AC-321** (seed-set assertion), §3.4 (licensing table) |
| **K-B18** — `fusion_gate.py:80-81`'s *"The floor's channel is LIVE and MEASURED"* is a **pre-#41** claim (git-dated: fixture `56c8510` 2026-08-03, #41 `cab9b73` 2026-08-04) resting on a mechanism #41 deleted, untested since, in shipped source | **ACCEPTED-AS-FILED** | §4 / **AC-359**; W-G-XL grant extended to `:72-92` |
| **K-N22** — the campaign had no general rule requiring positive-capability before a routing negative; K-N15 caught one instance | **ACCEPTED-AS-FILED** | §2 global rule **(f)**; audit table; **AC-357**, **AC-358**; **S-14** |

Running totals after `amend-02`: **40 distinct findings** (18 blocking `K-B1..K-B18`, 22
non-blocking `K-N1..K-N22`) — **31 ACCEPTED-AS-FILED, 11 RULED-BY-FORGE-Dn, 0 SUPERSEDED,
0 REJECTED-WITH-REASON.**

---

## 7. Criteria and verification-plan deltas produced by this amendment

Full text in `spec.criteria.amend-02.md` and `verification-plan.amend-02.md`:

- **AC-321** — REPLACED again (14 rows, literal seed `"8"` asserted, control present and true).
- **AC-313** — REPLACED again (three source hashes + two constants; docstring free).
- **AC-322** — amended (in-artifact statement that C-2 cannot see seed 8; the seed set is
  recorded).
- **AC-357** — ADDED (VP-M1 positive control, `floor=2` vs `floor=1000`).
- **AC-358** — ADDED (disjointness-classifier control, both branches + the empty case).
- **AC-359** — ADDED (the `fusion_gate.py:72-92` correction/dating).
- **VP-M1** — protocol replaced (14 spawns), control step added, licensing table added.
- **§3 STOP table** — S-5 amended, **S-14** added.
- **§5 checklists** — v2.0.2 gains the AC-357/358/359 lines and the rule-(f) audit line.
