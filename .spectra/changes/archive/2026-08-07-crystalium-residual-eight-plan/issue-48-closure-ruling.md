# FORGE ruling — crystalium #48 closure classification

ruled_by: forge (autonomous, per the D9 mandate in `forge-rulings.md`)
ruled_at: 2026-08-06
decision_type: CONFLICT-RESOLUTION (classification of a closure)
inputs: `forge-rulings.md` (D9), `issue-48-mechanism-note.md`, `vp-m1-interpretation.md`,
`vp-m1-floor-channel.json` (tree `1767127`), `spec.md` §4 #48 / §6 S-5 / §8 exit table,
`spec.amend-02.md` §1–§3, `spec.amend-03.md` §5, `spec.criteria.amend-03.md`
(AC-321/AC-322/AC-357/AC-358/AC-359/AC-374), `red-evidence-wgfloor.json` (3 executed
red-checks), verification-plan.md §6, and the gate source on
`feat/floor-sensitivity-gate-48` (`89f02e4`): `evals/floor_sensitivity_gate.py`,
`mcp-server/tests/test_floor_sensitivity_gate.py`. The orchestrator's measured facts are
taken as settled (not re-derived), per the dispatch.

---

## [VERDICT] — option (iii): SPLIT, each half named

**#48 closes as a SPLIT closure with two named components:**

1. **RETIRED — D9 class (c), obsoleted-by-prior-fix:** AC-138/AC-139 **as worded against
   the shipped `evals/fusion_gate.py` fixture**, together with the tree's *"the floor's
   channel is LIVE and MEASURED"* prose claim. The mechanism they measured — the pre-#41
   abort channel (anomaly A's single-successful-seed cap turning hash order into a
   lottery) — was deleted by #41 (`graph.py:215-230` loops every seed; `:305` sorts the
   frontier). On that fixture the demanded disjointness is unobtainable **structurally**:
   all three edge-bearing competitors share one phantom (`fusion_gate.py:175-177`,
   AC-374 `distinct_phantom_count == 1`) and `fetch_width = max(k, FETCH_WIDTH_FLOOR)`
   (`retrieve.py:562`) always admits `N1`, so the derived union is `{Z}` at every floor.
   Measured: `channel_live == false` at **14/14** seed points including seed 8
   (`seed_set_covers_divergent_point = true`), positive control green.

2. **DISCHARGED — as the MOVED oracle, now AC-322:** AC-139's oracle bar — disjoint
   floor-10 vs floor-1000 target-rank distributions over the C-2 protocol,
   deterministic — is **met un-weakened** on the purpose-built
   `evals/floor_sensitivity_gate.py` fixture, via AC-139's own *"moved, not weakened"*
   escape hatch (spec.md §4 #48 named this path explicitly). Measured: `floor=10 →
   target_rank == 0`, `floor=1000 → target_rank == 1`, deterministically disjoint at all
   7 sampled seeds; `classify_disjoint` and the independent jq recomputation agree; two
   axis-distinct red-checks flip it RED with distinct failure signatures and revert
   cleanly. What is discharged is the criterion's **falsifiability function** — a
   regression guard on `FETCH_WIDTH_FLOOR`'s semantics — never the retired evidential
   claim.

Confidence: **88%** (evidence quality high — every load-bearing fact is a recorded,
executed artifact; the residual sensitivity is the scope reading of the escape hatch,
carried as reversal condition R1 below).

---

## REASONING

Three genuinely distinct positions were live; each was stress-tested.

**H1 — pure DISCHARGED (rejected).** The mechanism-note draft's own terminal sentence
("If yes, #48 closes discharged") supports it, and S-5's literal trigger — *"no fixture
makes `FETCH_WIDTH_FLOOR` change the fused rank deterministically post-#41"* — did NOT
fire: such a fixture exists and is measured. But pure discharge fails Inversion: it
asserts AC-138/AC-139 were *satisfied*, when the thing they were **evidence for** — a
live floor channel on the shipped eval surface — is gone, deleted by #41 before this
campaign started. A plain "discharged/fixed" would let a future reader believe the
floor's behavioural relevance was demonstrated where it was originally claimed. It also
contradicts the shipped module docstring itself, which states the shipped-fixture
wording is "retired with this mechanism note, not discharged"
(`floor_sensitivity_gate.py:29-31`) — the gate the discharge would ride on *disagrees
with the pure-discharge reading of itself*. This is the exact "unclassified honesty"
failure D9 exists to prevent.

**H2 — pure RETIRED (rejected).** Supported by amend-03 §5.3's middle routing row
("close #48 retired, not discharged"), which DID fire on the observed facts (AC-357
green + AC-374 green + AC-321 `channel_live == false`). But that row was written under
amend-02 §3.5's prior that AC-322 would come out non-disjoint — the row has no branch
for "shipped fixture dead AND the moved oracle passes," and AC-322's own triage text
routes retirement only off `classifier == recomputed == false`, which is not what was
measured (`disjoint == true`, cross-checked). Pure retirement fails Boundary: it would
misstate the measurement (implying the floor is unobservable post-#41, which AC-357 and
AC-322 refute), discard the escape hatch AC-139 itself carries, and leave a merged gate
guarding a criterion the closure just declared dead. S-5's trigger not firing is
decisive against H2 as the *sole* closure.

**H3 — SPLIT (selected).** The two halves have different objects, and both obtain:

- The **criterion-instance** that #48 was filed about — the strict-xfail block at
  `test_fusion_gate.py:85-113`, measuring the floor on the shipped fixture — probed a
  mechanism #41 deleted. That is D9 class (c) **verbatim** ("the mechanism the gate was
  built to measure was removed by an earlier change — retire with a mechanism note").
  Class (c) does not need S-5's trigger; it needs the mechanism note plus AC-374, both
  in hand. The xfail block is deleted (D9 prohibition: never leave a permanent
  strict-xfail), `evals/fusion_gate.py` byte-identical to `b7f1a47`, and both stale
  docstring claims are dated per AC-359 (dated, never erased).
- The **oracle bar** is fixture-indexed only through the escape hatch, and the hatch
  was exercised exactly as spec.md §4 #48 contemplated ("Move AC-138/AC-139 here").
  The bar is met and arguably **strengthened**: deterministic at every sampled point,
  where the old fixture's divergence was one point in fourteen riding a hash lottery —
  and the old "emergent" evidence was in fact a side-effect of a defect-class mechanism
  (the single-seed cap) that #41 fixed. The new instrument demonstrates the floor
  through the *intended* post-#41 mechanics. "Moved, not weakened" is satisfied at the
  level of the bar; the fixture-indexed liveness *claim* cannot be moved, and retires.

The spec's own exit gate (§8: "#48 close | AC-138/139 moved to
`floor_sensitivity_gate.py`, **or** retired with a mechanism note (S-5)") presents an
OR whose disjuncts **both partially obtain**. The routing-row conflict resolves the
same way: amend-03 §5.3's middle row governs what **VP-M1 licenses** (the
shipped-fixture retirement — upheld), not the whole issue; its terminal clause
presupposed an AC-322 outcome that did not occur. Naming both halves is the only
closure that neither overstates nor understates a measurement.

---

## What the new gate LICENSES — and what it does NOT

**Licensed:**

- `FETCH_WIDTH_FLOOR` is a **live, causally-connected parameter**: the dense-slice
  truncation at `retrieve.py:562` propagates through seed membership → derived-arm
  membership → fused rank, observably and deterministically, post-#41. This is an
  **existence proof over topologies**: at least one topology makes the floor decisive.
- A **regression guard** on that causal chain. If a future change makes the floor cease
  to bind (fetch-width logic removed or bypassed, the walk stops deriving from dense
  seeds, derived votes stop reaching fused ranks, or the unweighted two-arm vote
  arithmetic the demotion rides on — `2/61` vs `1/61` — changes), AC-322 /
  `test_run_seed_disjoint_ranks` goes red. AC-374 additionally guards the **evidentiary
  basis of this closure**: it reddens the moment the shipped fixture gains distinct
  phantoms, forcing #48's framing to be redone rather than inherited.

**NOT licensed — state it plainly:**

- **Not evidence that the floor matters in practice.** "Observable on a topology built
  to make it observable" and "matters in practice" are different claims, and the gate
  supports only the first. The strongest practice-adjacent fact this campaign produced
  points the **other way**: on the only fixture not built for this purpose — the
  shipped one — the floor has no observable effect at all, structurally, at every seed.
  **Yes: the new gate is a regression guard, not evidence the floor matters.** The
  closing comment says so in those words.
- No claim about real corpora, production workloads, retrieval quality, or the floor's
  default value (verification-plan §6's general rule: every gate here is a
  falsifiability instrument on a stipulated fixture).
- No resurrection of the shipped fixture's "channel live" claim.

---

## Species analysis — is this the #47/#55 construct wearing our colours?

The #47/#55 species (D9 class (b), S-11) is: a fixture whose **ground truth is
stipulated by its author**, presented as a **measurement of a graded property** (quality,
band characterisation, practical relevance) that the stipulation structurally cannot
reach. The vice is a category error in the *claim*, not the synthetic-ness of the
fixture — every fixture in this campaign is synthetic, including the one AC-139
originally lived on.

The floor gate is a **different species, conditionally**:

- Its claim is confined to a **mechanical** property: "parameter X causally propagates
  to output Y under topology T." For that claim, an author-constructed topology is not
  a confound — it is the **experimental treatment**. An existence proof requires one
  constructed instance; the construction *is* the demonstration, and it is honest for
  as long as it is labelled an existence proof and regression guard, and never
  generalised.
- It is falsifiable on the axes it names, demonstrated by execution
  (`red-evidence-wgfloor.json`): RC2 (competitor moved inside both floors — placement
  axis, collapses at rank 1, `assert 1 != 1`) and RC3 (edge severed — topology axis,
  collapses at rank 0, `assert 0 != 0`) are axis-distinct with **distinct failure
  values**; RC1 proves AC-357's control itself reddens on exactly the shipped-fixture
  confound (shared phantom). The #47/#55 constructs were ruled unobtainable because no
  perturbation could make them wrong *about the thing they claimed*; this gate has two.
- Its verdict is not author-stipulated at emit time: the disjointness is computed twice
  (shipped classifier + independent jq recomputation, required to agree), the vacuous
  empty case is rejected (`classify_disjoint([], []) == False`), the control's phantom
  targets are read **off the graph at runtime** (never hard-coded), and AC-374's
  non-empty-union conjunct prevents a dead walk from masquerading as invariance.

**The concession, without generosity:** the species boundary lives in the *claim*, not
the artifact. The moment anyone cites this gate as evidence that
`FETCH_WIDTH_FLOOR` *matters* — in production, on real corpora, or even on the shipped
eval surface — it becomes exactly the condemned species: a stipulated ground truth
laundered as a measurement. Likewise if AC-322's green were presented as discharging
the original shipped-fixture claim. The split classification and the fenced closing
comment below are the mechanism that keeps it on the right side of that line; they are
load-bearing, not decoration.

---

## VERBATIM closing comment for #48

> **Closed — SPLIT closure. AC-138/AC-139 as worded: RETIRED (obsoleted-by-prior-fix, S-13/D9 class (c)). The floor-sensitivity oracle, moved per AC-139's own "moved, not weakened" escape hatch: DISCHARGED as AC-322 on a purpose-built fixture.**
>
> Retired and discharged are different closures (verification-plan §6); this issue requires both, so each half is named with its evidence.
>
> **RETIRED — AC-138/AC-139 against the shipped `evals/fusion_gate.py` fixture, and the "channel is LIVE and MEASURED" claim (class (c): the mechanism they measured was removed by an earlier fix).**
> - **Mechanism.** The pre-#41 divergence (seed 8) rode an ABORT channel, not a membership channel: anomaly A's single-successful-seed cap made `decaying_walk` expand exactly one seed, so hash order decided between `{Z: 0.5}` (pick lands on an edge-bearing competitor) and `{}` (pick lands on an edgeless filler; walk aborts). #41 deleted that mechanism (`graph.py:215-230` loops every seed; `graph.py:305` sorts the frontier). No lottery remains, and no membership channel existed to replace it: `fusion_gate.py:175-177` points all three edge-bearing competitors (N1/N2/N3) at the SAME phantom `Z`, and `fetch_width = max(k, FETCH_WIDTH_FLOOR)` (`retrieve.py:562`) always admits `N1` (dense rank 0) — so the derived union is `{Z}` at EVERY floor, by topology, independent of seed. Mechanised as AC-374 (`distinct_phantom_count == 1`; identical non-empty derived union at floors 2/10/1000).
> - **Measurement.** `channel_live == false` at **14/14** `PYTHONHASHSEED` points (0-12 + unset) — a seed set provably containing seed 8, the single historically divergent point and the entire basis of the old liveness claim (`seed_set_covers_divergent_point: true`) — with derived-arm MEMBERSHIP captured at the `graph_store` seam (never `explain`), self-check green on every row, and the probe's positive control (AC-357, distinct-phantom fixture) demonstrating the instrument can emit `true`. Artifact: `vp-m1-floor-channel.json`.
> - **Timeline.** The liveness prose was written at `56c8510` (2026-08-03), one day BEFORE #41 landed (`cab9b73`, 2026-08-04), and was never re-tested. Both docstring sites in `evals/fusion_gate.py` are now dated pre-#41 per AC-359 (the `config.py:304-308` "HISTORICAL" pattern) — dated, not erased.
> - The permanent strict-xfail block (`test_fusion_gate.py:85-113`) is **deleted**, not left standing; `evals/fusion_gate.py` is byte-identical to `b7f1a47`.
>
> **DISCHARGED — the oracle bar, as AC-322 on `evals/floor_sensitivity_gate.py`.**
> - The new fixture gives the floor a channel that survives #41's all-seed expansion **by construction**: one edge-bearing competitor at dense rank 11 (outside `[:10]`, inside `[:15]`), ONE distinct phantom, tie-break-neutral ids, single layer.
> - **Measurement.** `floor=10 → target_rank == 0` and `floor=1000 → target_rank == 1` at ALL 7 C-2 seeds — deterministically DISJOINT; `classify_disjoint` and an independent jq recomputation agree. This is the exact bar AC-139 demanded and failed on the old fixture, met un-weakened — and stronger: deterministic at every sampled point, where the old fixture's divergence was one point in fourteen riding a hash lottery.
> - **Falsifiability.** Two axis-distinct red-checks flip the gate RED with distinct failure signatures (competitor moved inside both floors ⇒ both floors collapse on rank 1; edge severed ⇒ both collapse on rank 0) and revert cleanly; the positive control reads its phantom targets off the graph at runtime, so it cannot be pointed at a same-phantom fixture and silently mean nothing.
>
> **What this closure does NOT claim.**
> - It does NOT claim `FETCH_WIDTH_FLOOR` matters in practice. The new gate is an existence proof and a **regression guard**: it demonstrates the floor is a live, causally-connected parameter (dense-slice truncation → derived membership → fused rank) on a topology BUILT to make it observable. On the only fixture not built for that purpose — the shipped one — the floor is measured to have NO observable effect at all. No claim about real corpora, production workloads, retrieval quality, or the floor's default value is made or licensed (verification-plan §6).
> - It does NOT resurrect the shipped fixture's "channel live" claim; that claim is retired above.
> - It ships NO production-code behaviour change: `retrieve.py`, `graph.py`, and `evals/fusion_gate.py` are untouched.
>
> **Reopen condition.** AC-374 going red (the shipped fixture gaining distinct phantoms), or any measurement showing a floor-sensitive derived-membership channel on a fixture not purpose-built for it — either reopens #48's framing rather than inheriting this closure.

---

## MERGE DECISION

**MERGE — the gate passes D9 step 5.** It is not a permanently-green ornament:

- **It can fail on the defect it names**, demonstrated by execution, on both causal
  links (placement RC2, topology RC3), with distinct failure values and restore proofs
  (`red-evidence-wgfloor.json`, tree `1767127`, non-zero exits recorded).
- **Its controls are falsifiable**: RC1 reddens AC-357's control on exactly the
  confound it exists to catch (shared phantom, `assert 1 >= 3` fails on `['zzz1']`);
  `classify_disjoint` rejects the vacuous empty case; AC-374's non-empty-union conjunct
  blocks the dead-walk false pass; the aggregate's verdict must agree with an
  independent recomputation.
- **It guards something real**: the post-#41 semantic contract of `FETCH_WIDTH_FLOOR`
  end-to-end, plus (via AC-374) the evidentiary premise of this closure itself.
  Concrete regressions that would redden it: fetch-width truncation removed or
  bypassed; walk semantics decoupled from dense seed membership; derived votes no
  longer reaching fused rank; a change to the unweighted two-arm vote arithmetic the
  rank-1 demotion depends on.

**Conditions attached to the merge/closure (neither changes the classification):**

1. **AC-358's VERIFY command cannot collect its nodes as written.** It names
   `test_floor_sensitivity_gate.py::test_disjointness_classifier_both_branches` and
   `::test_aggregate_uses_classifier` at module level, but both are **class methods**
   (`TestDisjointnessClassifier::…`, `TestAggregateSeeds::…`) — pytest will fail
   collection (exit 4) on the literal command. This is the K-B8 species (a criterion
   naming a thing no step produces), its **fifth** recurrence. Fix before the release
   checklist runs AC-358: amend the command to class-qualified node ids, or hoist the
   two nodes to module level. Route per amend-03 §16.3's standing rule.
2. The closing comment ships as written above — the split naming and the not-claimed
   block are load-bearing (verification-plan §6; D9 prohibition against presenting the
   construct as a measurement).
3. The rule-(g) chains (AC-321/AC-322/AC-357/AC-374) re-run at the RC sha per the
   existing release checklist — the recorded artifacts carry tree `1767127` while the
   branch tip is `89f02e4`; the standing per-release re-emit handles the skew, no new
   process needed.

---

## Reversal conditions

- **[REVERSAL-CONDITION] R1 — escape-hatch scope.** If AC-139's original criterion text
  (the #38-campaign source) shows "moved, not weakened" scoped narrower than "any
  fixture, same bar" (e.g. movable only against the same fixture), the DISCHARGED half
  reclassifies to "AC-139 wholly RETIRED; AC-322 discharged as a NEW criterion." The
  comment structure survives; one clause changes; the split remains a split.
- **[REVERSAL-CONDITION] R2 — AC-374 red.** The shipped fixture gaining distinct
  phantoms refutes the retirement's structural premise; reopen #48's framing, treat the
  prior green as a finding about the gate (D9's own reversal clause).
- **[REVERSAL-CONDITION] R3 — a non-purpose-built floor channel.** Any future
  measurement showing floor-sensitive derived membership on a fixture not built for it
  upgrades the floor from "can matter" to "does matter" and the licensing section of
  this ruling must be rewritten before it is cited again.
- **[ASSUMPTION]** AC-138/AC-139's original wording is as the dispatch stipulates
  (disjoint floor-10/1000 target-rank distributions over C-2, on the fusion-gate
  fixture, with the moved-not-weakened hatch). All four governing documents in this
  folder quote it consistently; the #38-campaign source was not independently re-read.

*FORGE. One question, one ruling: SPLIT — retire the claim, discharge the moved oracle,
merge the gate as a guard and never call it evidence.*
