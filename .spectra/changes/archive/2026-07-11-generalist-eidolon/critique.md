# Independent Critique — ESL change `generalist-eidolon`

> **Critic:** `ramza-critic-fresh` (independent RAMZA instance; NOT the maker `ramza`).
> **Read-only on the spec.** This file is the only artifact authored by the critic.
> Maker≠checker recorded mechanically: `ramza-gate critic --author ramza --checker
> ramza-critic-fresh` → `OK` (exit 0). Refine-rubric anchor (cycle 1):
> `ramza-score --rubric refine` → **verdict: fail** (total 3.2, **min 2**, testability=2,
> exit 1) — appended to `plan-state.json` gates[] + `ramza-calibration.jsonl`.

---

## 0. Mechanical anchor results (critic re-run vs maker's recorded values)

| Anchor | Critic result | Maker's recorded | Concordance |
|---|---|---|---|
| `ramza-lint --plan spec.md --state plan-state.json` | `ok: plan passes structural lint (tier: full)` exit 0 | `structural: "pass (tier=full)"` | **MATCH** |
| `ramza-ears-lint acceptance-criteria.md` | `ok: 45 criteria pass EARS lint` exit 0 | `ears: "45 criteria pass"` | **MATCH** |
| `sha256sum acceptance-criteria.md` | `43280da4f651e03c2f5f0de2dc7e72cdb9b19355670463df08bc8389f9be18a8` | expected `43280da4…18a8` | **MATCH (no tamper)** |
| requirements count (spec.md ∩ spec.yaml) | 47 ∩ 47 | `requirements_count: 47` | **MATCH** |
| acceptance-check count (criteria ∩ spec.yaml) | 45 ∩ 45 | `acceptance_checks_count: 45` | **MATCH** |

No mechanical discrepancy vs the maker's recorded results, and **no SHA mismatch → no BLOCKING
from the tamper anchor.** The findings below are content-quality and gate-design defects the
grep-level linters cannot see — which is exactly where the critic's judgment is reserved, and
(per the project maxim) exactly where defects hide.

## Trace-check (≥10 sampled, across all 8 tracks)

Verified each bracketed trace points at a real clause that says what the requirement claims,
by reading the cited FINDING/GAP/HC/verdict/digest source:

| Req | Trace sampled | Verdict |
|---|---|---|
| R-001 | FINDING-001 (enum closed@8) + FINDING-004 (add-eidolon backward-compat path) | SOUND |
| R-002 | FINDING-002 (routing.schema open string; classes.default) | SOUND |
| R-005 | FINDING-006 (Kupo refuse_verbs) + delib. Deliverable-3 refuse row + HC8 | SOUND |
| R-007 | FINDING-007 (Kupo orchestrator-dispatched, never router) + HC8 | SOUND |
| R-016 | FINDING-010 (Step-2 → clarification_request, no catch-all) + verdict Step-2 change | SOUND |
| R-021 | FINDING-019 (at/over budget) + GAP-003 (no CI gate) + HC9 + REVERSAL-5 | SOUND |
| R-026 | digest§3 (structured TaskState) | SOUND (digest self-graded "synthesis only") |
| R-034 | FINDING-020 (54 edge YAMLs) + FINDING-021 (composition auto-gen) | SOUND |
| R-039 | verdict measurement-gate Arm-1 + HC10 + A14 | SOUND |
| R-045 | checker-handoff cats 1&5 + verdict §Checker-handoff | SOUND |
| R-010 | FINDING-005 (working_set_tokens) + task§2 | **STRETCH** — see CRIT-011 |
| R-017 | "I-C2/I-C6" | **MISCITE** — I-C2 says dispatch IS interpretive; see CRIT-006 |

No fabricated traces. Two stretched/miscited traces are filed as MINOR findings below.

---

## Findings

### CRIT-001 — MAJOR — The Step-2(a) predicate is NOT mechanical; its signal *definitions* leak discretion and systematically bias toward false fallthrough
**Anchor:** spec.md §Approach 3 (signal table S1..S8) + R-017/AC-C05 claim "all Boolean,
lexical/structural — no model discretion (I-C2/I-C6)"; FORGE Boundary stress-test
(deliberation.md:114); OQ-7 ("primary risk").

The spec asserts the eight signals are "lexical/structural — no model discretion," but the
*definitions* are semantic prose, not lexical rules. Critically, four signals use **modal /
potential** phrasing rather than **presence** phrasing:

- S1 `objective_named` — "an explicit goal/outcome clause is present" (what regex detects a
  "goal clause"?)
- S3 `repo_surface_identifiable` — "a path/file/module/component **is referenceable**"
- S5 `acceptance_or_stop_signal` — "a done/acceptance/stop criterion **is statable**"
- S6 `authority_statable` — "read/write/exec/network/deploy scope **is boundable**"

"Referenceable / statable / boundable / identifiable" ask *"could one, in principle, state/bound
this?"* — to which the answer is **almost always yes**. This is (a) a discretion leak (two
evaluators resolve them differently) and (b) a **systematic bias toward PASS = dispatch the
generalist**. There is no closed act-verb lexicon for S4, no regex for S1, no parser spec, no
tie-break rule. The mechanicalness is *asserted*, not *delivered*. This is the make-or-break
invariant FORGE named (I-C6 determinism), and the spec ships the claim without the artifact.

**Adversarial walkthroughs (verbatim; predicate evaluated inside the no-match branch, S7∧S8 hold):**

- **P1 (false fallthrough — a vacuous prompt PASSES):** "Make the project better."
  S1=1 (lenient: "better" = outcome), S4=1 ("make"), S5=1 ("statable": "project is better"),
  S3=1 ("the project" ≈ repo-wide). `1∧1∧1∧(1∨*)` = **actionable → dispatch generalist.** A
  maximally underspecified prompt is dispatched, not clarified — the exact failure branch (b)
  exists to prevent.
- **P2 (false fallthrough via "statable"):** "Improve performance somewhere in the codebase."
  S1=1, S4=1, S5=1 (statable), S3=1 ("codebase" ≈ repo-wide) → **actionable.** Unbounded,
  unmeasurable mission dispatched.
- **P5 (false fallthrough of a large mission):** "Set up CI for the project."
  S1=1, S4=1, S5=1, S3=1 → **actionable.** The predicate cannot distinguish "set up CI"
  (multi-file, deploy-adjacent) from "fix a typo" — both pass identically (no blast-radius signal).
- **P3 (specialist-owned falls through — over-capture):** "Rename `getUserData` to
  `fetchUserProfile` everywhere it appears and update all call sites and the docs."
  Kupo refuses (>2 files) → Kupo<τ; if Vivi's triggers miss the phrasing, Vivi scores 0.59 <τ →
  S7=1. Then S1=1, S4=1 ("rename/update"), S5=1, S3=1 → **generalist captures a
  should-route-to-coder mission.** AC-G03 cannot flag it (Vivi scored <τ) — see CRIT-003.
- **P4 (discretion leak on S4):** "Look into the flaky checkout test and figure out what's
  going on." Evaluator A: "figure out" *produces an artifact* (a diagnosis) → S4=1 → generalist.
  Evaluator B: no state mutation → S4=0 → clarification_request. **Same prompt, two outcomes** —
  I-C6 violated. The definition "produces an artifact" makes nearly every investigate verb
  qualify, again biasing toward fallthrough.
- **P6 (chain-owned engineered to fall through, discretion on S8):** "Weigh whether we should
  use REST or gRPC for the new service and set it up." The `decide-then-implement` chain
  (FORGE+coder) should own this. S8 = "no chain co-triggers **cleanly**" — "cleanly" is
  discretionary: an evaluator who judges the single-sentence intent as "not clean" sets S8=1 →
  fallthrough → **generalist captures a chain-owned decision+implement mission.**

**Disposition (REVISE):** Replace each modal definition with a *presence* rule + closed
lexicon/regex: S1/S5/S6 must be "explicitly **present in the prompt**," never "statable/boundable";
publish the closed act-verb list for S4 (and disqualify pure investigate verbs, or route them to
ATLAS not the generalist); define "cleanly" in S8 mechanically; add a tie-break default that
**biases to clarification_request, not dispatch** when a signal is indeterminate. Until then the
predicate does **not** satisfy R-017/I-C6.

### CRIT-002 — MAJOR — AC-C05 tests the Boolean combinator, not signal extraction — the gate misses where the discretion lives
**Anchor:** AC-C05 VERIFY ("predicate truth-table test passes with a deterministic (no-LLM)
evaluator"); truth table spec.md §Approach 3.

The truth table (`actionable = S1∧S4∧S5∧(S3∨S6)`) is a **correct** Boolean decomposition — I
verified all five canonical rows; the *combinator* is sound. But AC-C05 feeds the evaluator
**pre-assigned S1..S8 Boolean inputs**; a truth-table test over fixed Booleans is trivially
deterministic and will always pass. The discretion (CRIT-001) is entirely in **prompt → S1..S8
extraction**, which AC-C05 never exercises. This is a gate that certifies the easy half and is
blind to the hard half — false assurance on the spec's own primary risk.

**Disposition (REVISE):** Add an acceptance criterion that the **signal extractor** (natural
language → S1..S8) is deterministic — e.g. a fixed corpus of prompts with frozen expected signal
vectors, evaluated by the no-LLM extractor, with a required exact match. Without a mechanical
extractor to test (CRIT-001), AC-C05 as written cannot discharge R-017.

### CRIT-003 — MAJOR — The Arm-2 over-capture gate is near-tautological: its corpus excludes the only region where over-capture can occur
**Anchor:** AC-G03 / AC-C03 ("over-capture count == 0 on the specialist replay corpus");
spec.md §Approach 7 Arm 2; Step-2 precondition S7 `no_specialist_ge_tau`.

Over-capture is measured on the "existing **specialist-matched** routing corpus" — prompts where
a specialist scores **≥ τ**. But Step-2(a) is gated on S7 = *no specialist ≥ τ*. So on that
corpus the generalist **structurally cannot fire** — "over-capture count == 0" is true **by
construction**, independent of predicate quality. The gate measures a physically-impossible event.

The *real* over-capture (pre-mortem #1 risk) is the **near-threshold** case: a prompt a specialist
*should* own whose trigger-verb coverage dips it to 0.59 (<τ), so it falls through and the
generalist captures it (see P3). Those prompts are **excluded** from a "specialist-matched (≥τ)"
corpus. **Forged-input scenario:** assemble the replay corpus from clean, strongly-matched
specialist prompts (all ≥τ) → 0 over-capture and ~0 precision delta trivially → Arm 2 declared
PASS → ship, while near-threshold over-capture is never measured. The margin (OQ-1) is defined on
the wrong denominator.

**Disposition (REVISE):** Redefine the Arm-2 corpus to include **near-threshold / should-route-
to-specialist** prompts (0.5 ≤ specialist_score < τ, and paraphrase-perturbed specialist prompts).
Define over-capture as "generalist fired on a prompt whose *ground-truth owner* is a specialist,"
adjudicated against a labeled key — not "fired when a specialist scored ≥ τ." Otherwise AC-G03's
"hard MUST = 0" is unfalsifiable.

### CRIT-004 — MAJOR — Arm-1 pass bar is ">baseline zero" — a single verified completion passes; "meaningfully covers" is not operationalized
**Anchor:** AC-G01 VERIFY ("generalist verified-completions **strictly greater than the baseline's
zero**"); spec.md §Approach 7 ("**meaningfully** covers them").

The baseline (`clarification_request`) completes **0** by definition (it bounces). AC-G01 passes
on **>0** — i.e. **one** verified completion in a cohort of any size. There is no cohort-size floor,
no difficulty stratification, no minimum coverage rate, no representativeness constraint. The prose
requirement ("meaningfully covers") and the mechanical VERIFY (">0") **diverge**. **Forged-input
scenario:** a holdout of 50 actionable-but-unroutable missions; the generalist verifiably completes
the 1 easiest and fails 49; AC-G01 → PASS. A weak generalist ships on a cherry-picked cohort.

**Disposition (REVISE):** Specify Arm-1 as a **rate** with a floor (e.g. "≥ X% verified-completion
over an N≥K stratified holdout, spanning the mission-difficulty distribution"), maker≠checker on
cohort construction. Peg X to the RAMZA-succession/Kupo-KEEP precedent rather than ">0."

### CRIT-005 — MAJOR — The token-budget CI (the P0 cortex precondition) is under-specified: no tokenizer, no region delimiters — pass/fail is undefined
**Anchor:** AC-D01/AC-D02 ("count ≤ 900 for the always-loaded region"); FINDING-019
("≈ **800–1,100 tokens**"); I-C4 (EIDOLONS.md:147, "Always-loaded section ≤ 900 tokens" — no
tokenizer, no delimiter named); Story 2 risk-tag **P0**; HC9 is a hard *precondition*.

The whole row ships only if this gate is green (HC9/R-021/R-044), yet AC-D02 names **no tokenizer**
(BPE? cl100k? word-count×k? chars/4?) and **no region boundaries** (FINDING-019 notes "nearly every
section is labeled (always-loaded)"). FINDING-019's own estimate — 800–1,100 tokens — **straddles
the 900 ceiling by ±150**; the pass/fail flips on the unspecified measurement method. A bash-3.2
script (HC7) realistically uses a char/word heuristic, i.e. exactly the imprecise band. A frozen
acceptance criterion that gates a P0 precondition must pin its own measurement.

**Disposition (REVISE):** AC-D02 must name (a) the exact counting method (tokenizer name+version,
or the specific char/word heuristic **and** a conservative margin, e.g. count ≤ 850 to absorb
heuristic error) and (b) the **machine-readable delimiters** bounding "the always-loaded region"
(the §DEEP / (always-loaded) markers AC-D04 relies on, made precise). Add a fixture proving the
script's count agrees with the chosen ground-truth tokenizer within tolerance.

### CRIT-006 — MINOR — R-017/AC-C05 mis-cite I-C2: I-C2 says dispatch IS interpretive, not "non-LLM-discretionary"
**Anchor:** EIDOLONS.md:145 — "**I-C2** — No `eval` of routing rules; descriptor table is data,
**dispatch is interpretive**." The spec repeatedly grounds the "mechanical, never LLM-discretionary"
predicate in "I-C2/I-C6." I-C2 forbids *code eval* and affirms *interpretive* dispatch — it does
not demand non-discretion. The support for a mechanical predicate is **I-C6 alone** (determinism).
The mis-citation does not change the conclusion but the spec's justification rests on a
mischaracterized invariant — and (per CRIT-001) I-C6 is not yet satisfied.
**Disposition:** Drop I-C2 from R-017/AC-C05's rationale; ground on I-C6; add the extractor artifact.

### CRIT-007 — MINOR (borderline MAJOR) — REVERSAL-3 (frequency-null) is simultaneously a pre-flip stop gate and "deferred/uninstrumented" — AC-H04 cannot mechanically check it
**Anchor:** Scope §Deferred ("Frequency instrumentation of `clarification_request` (REVERSAL-3) …
not a blocker") vs R-047/AC-H04 (the five reversal-conditions, incl. "frequency-null", are
"recorded **pre-flip stop gates**"). If frequency is never instrumented, AC-H04's frequency-null
item is unverifiable — a checklist gate with no signal behind it.
**Disposition:** Either undefer minimal frequency instrumentation, or explicitly *redefine*
REVERSAL-3's evaluation as "Arm-1 holdout coverage-rate < threshold" with a stated number, so the
pre-flip checklist item is mechanically evaluable.

### CRIT-008 — MINOR — The predicate admits unbounded-surface missions a `writes_repo:false` worker cannot complete (dispatch/authority-envelope mismatch)
**Anchor:** predicate `S3∨S6` (authority S6 is optional if S3 holds); truth-table row-2 only guards
when **both** S3 and S6 are false; R-009/AC-B07 (`writes_repo:false`, PROPOSE-only). A prompt with
S3="repo-wide" but no statable authority (S6=0) still dispatches (see P2/P5). A repo-wide refactor
handed to the "deliberately boring worker" whose boundary is `writes_repo:false` can only be
PROPOSEd, not done — the dispatch predicate green-lights missions outside the worker's authority
envelope. **Disposition:** make a *bounded* authority/surface a hard AND (require S6, or require
S3∧S6 for act-heavy missions), or add a blast-radius signal that routes repo-wide/unbounded acts to
clarification, not the generalist.

### CRIT-009 — MINOR — `downstream: []` vs five outbound `TBD_NAME→{atlas,kupo,vigil,idg,forge}` ECL edge contracts — reconcile the model (OQ-4)
**Anchor:** R-007/AC-B05 (`handoffs.downstream == []`) vs §Approach 6 / R-034 (PROPOSE-upward
edges TBD_NAME→atlas/kupo/vigil/idg/forge). The spec's resolution — "emitted handoff-request the
orchestrator routes, not dispatch" — is coherent, but composition.md regen + `composition-drift.yml`
operate on the edge contracts; the spec must state explicitly how a `TBD_NAME→X` contract's
`edge_origin` encodes "emitted-request, not dispatch" so AC-B05 (`downstream:[]`) and AC-F03
(one YAML per edge) do not contradict. **Disposition:** add a requirement pinning the edge_origin/
performative for the five outbound edges as PROPOSE-upward (not dispatch), and confirm the set
with the maintainer.

### CRIT-010 — MINOR — AC-A02 has a compound THEN ("retain all eight … *with* exactly one added") that escapes the EARS linter
**Anchor:** acceptance-criteria.md:42; `ramza-ears-lint` only flags uppercase `" AND "`. AC-A02
asserts two things ("retains all 8 prior" ∧ "exactly one added"). The linter passes it because the
conjunction is via "with," not " AND " — a gate blind spot. **Disposition:** split into AC-A02a
(superset: all 8 present) and AC-A02b (length == 9), or reword to a single assertion.

### CRIT-011 — MINOR — R-010 trace stretch (model-tier=standard) + OQ-5 unresolved for the residual-hardest missions
**Anchor:** R-010 traces [FINDING-005, task§2]; FINDING-005 documents Kupo's `working_set_tokens`
but says nothing about model tier — the "standard tier" claim originates in the deliberation's
Step-2 change. Separately: the generalist handles the *residual hardest* category (cross-class,
multi-step, no specialist matched); assigning **standard** to it is defensible on cost and is
gate-caught (Arm-1), but the spec leaves OQ-5 open. **Disposition:** correct R-010's trace to cite
the deliberation Step-2 change; document the standard-tier rationale (cost + Arm-1-caught) rather
than leaving it open, or escalate to human with the trade-off.

### CRIT-012 — MINOR (observational) — checker-identity plumbing: change.json `checker: kupo` vs the RAMZA critic
**Anchor:** change.json:7 (`"checker": "kupo"`) vs this RAMZA maker≠checker critic
(`ramza-critic-fresh`) + plan-state note. These are **distinct gates** — the ESL change-checker
(kupo, `kupo-esl-hop`/`verify-incoming`) and the RAMZA maker≠checker critic gate — and the maker
noted the distinction. Not a defect, but the two-checker topology should be stated explicitly in
Track H so the human sees both gates are required before the flip. **Disposition:** one sentence in
§Approach 8 / R-045 naming both the RAMZA critic and the ESL checker as required pre-flip.

---

## Open-Question dispositions (OQ-1..OQ-7)

| OQ | Classification | Critic disposition |
|---|---|---|
| OQ-1 (Arm-2 margin) | needs-human | Properly flagged — **but** the margin is downstream of a corpus/denominator defect (CRIT-003); fix the corpus before pinning a number. |
| OQ-2 (persona name) | needs-human | Properly flagged (`requires_checker`). No critic action. |
| OQ-3 (host-slot feasibility) | needs-human/ATLAS | Properly flagged; Scope correctly carves S-host to documentation-only pending GAP-002. Sound. |
| OQ-4 (downstream edge set) | resolvable-by-critic | See CRIT-009 — reconcile `downstream:[]` with the five outbound edge contracts; edge set itself is plausibly complete; confirm with maintainer. |
| OQ-5 (standard vs deep tier) | resolvable-by-critic | See CRIT-011 — standard is defensible + Arm-1-gated; document the rationale rather than leave open. |
| OQ-6 (mint in_construction w/o frequency) | resolvable-by-critic | **Concur with FORGE** — the authority justification is structural (missing write-capable-worker archetype, HC11), not head-count; in_construction is reversible and gated. NOT a defect. Caveat: see CRIT-007 (REVERSAL-3 must stay evaluable). |
| OQ-7 (S1..S8 crisp enough?) | **spec-defect** | **NO** — see CRIT-001/CRIT-002. This is the primary risk and it is unresolved as specified. |

## Maker's 3 self-declared riskiest decisions (assessed)

The maker's final-summary text was not in the critic's artifact set; I assess the three
P0-tagged / OQ-7-flagged design decisions that the spec structurally presents as riskiest:

1. **The strict-fallthrough *mechanical* predicate (RISK-over-capture / predicate-fuzziness, P0/P1).**
   → **spec-defect** as delivered (CRIT-001/002). The design *intent* (no positive triggers, never
   in Step-1, branch-(a)-only) is correct and preserves I-C6 at the *ranking* layer; the defect is
   the *extraction* layer, which is not mechanical. Fixable in Refine, not a re-litigation of H-E.
2. **The two-arm gate as the sole technical ship-authority (P0).**
   → **spec-defect** as delivered (CRIT-003/004). Both arms are forgeable as specified (tautological
   over-capture corpus; ">0" expansion bar). The *concept* (coverage + no-over-capture, maker≠checker)
   is right; the *operationalization* must be hardened before it can gate `shipped`.
3. **Minting `in_construction` before frequency is measured (structural-authority justification).**
   → **sound / not a defect** (concur, OQ-6). The reversible-and-gated staging absorbs the frequency
   GAP; only caveat is CRIT-007 (keep REVERSAL-3 mechanically evaluable).

---

## VERDICT: REVISE

**No BLOCKING** (SHA matches; lint/ears clean; traces sound; counts concordant). **5 MAJOR + 7
MINOR.** The plan's architecture (H-E strict fallthrough, staged rollout, maker≠checker, cortex
precondition) is sound and traces faithfully to the FORGE H-E verdict without drift. But the two
load-bearing gates — the Step-2(a) predicate and the two-arm measurement gate — are, as specified,
**not mechanical / not falsifiable**, and the P0 token-budget gate is unmeasurable. The maker must
change, before the plan can advance to Assemble:

1. **CRIT-001** — replace modal signal definitions (statable/identifiable/boundable) with
   presence-rules + closed lexicons/regex; add an indeterminate→clarification tie-break.
2. **CRIT-002** — add an acceptance criterion testing the **signal extractor's** determinism, not
   only the Boolean combinator.
3. **CRIT-003** — redefine the Arm-2 over-capture corpus to include near-threshold/should-route-to-
   specialist prompts; define over-capture against a labeled ground-truth owner, not "specialist ≥ τ."
4. **CRIT-004** — replace Arm-1's ">0" bar with a stratified coverage-rate floor pegged to precedent.
5. **CRIT-005** — pin AC-D02's tokenizer/heuristic + margin and the machine-readable region delimiters.
6. **CRIT-006..CRIT-012** — the seven MINORs (I-C2 mis-cite, REVERSAL-3 evaluability, unbounded-
   surface authority mismatch, downstream/edge reconciliation, AC-A02 compound-THEN split, R-010
   trace + OQ-5 rationale, two-checker topology).

Mechanical anchor: `ramza-score --rubric refine` (cycle 1) = **fail** (min 2 < 3). Route to
Refine (R); do not enter Assemble (A) until CRIT-001..005 are resolved and re-scored ≥3 (cycle 1).

*Critic: `ramza-critic-fresh` — maker≠checker recorded via `ramza-gate critic`. Read-only; the
spec artifacts were not modified.*

---

# Cycle 2 — re-check of rev 2 (critic: `ramza-critic-fresh`)

**Scope:** independent re-verification of the maker's rev-2 dispositions (CRIT-001..012), a
FRESH adversarial pass against the *actual* frozen lexicons/regex (NOT reusing P1..P6 — those are
now normative fixtures the maker tuned for; Goodhart), and a second attack on the revised gates.

## C2.0 — Mechanical anchors (rev 2) + state honesty

| Anchor | Critic result | Claim | Concordance |
|---|---|---|---|
| `ramza-lint --plan spec.md` | `ok … (tier: full)` exit 0 | pass | MATCH |
| `ramza-ears-lint acceptance-criteria.md` | `ok: 52 criteria pass` exit 0 | 52/52 | MATCH |
| `sha256sum acceptance-criteria.md` | `51368260e8fd1ee81adab44207adc98ed52f96e09c59af779090936c5485b258` | claimed `51368260…5258` | **EXACT MATCH** |
| requirements (spec.md ∩ spec.yaml) | 51 ∩ 51 | 51 | MATCH |
| acceptance-checks (criteria ∩ spec.yaml, full a/b suffix) | 52 ∩ 52, symmetric-diff empty | 52 | MATCH |

**State honesty (duty 1) — all three present and honest:** (a) cycle-1 REVISE is recorded
(`gates[]` refine cycle-1 `fail`, min 2); (b) the revision is recorded (`revision:2`,
`revision_note`, `crit_dispositions{}`, rev1 SHA logged as superseded); (c) the self-reverted
advance-probe is recorded in `corrections[]` — the maker ran `ramza-gate advance --to A` as a
DENY-probe, it *succeeded* (verdict-blind gate), and the maker **restored to T and did not
self-approve**, flagging the tooling defect. I confirmed the disclosure is accurate (ramza-gate
lines 143-146 check `.critic.checker` presence only, never the verdict). This is a high-integrity
disclosure; credited.

**Disposition reality (duty 2):** all twelve CRIT-001..012 dispositions are **real in the text**,
not merely summarized — verified inline (lexicons + fixtures §Closed lexicons; R-048/R-049/R-050;
AC-C05..C08, AC-D02/D06, AC-F05, AC-G01..G05, AC-A02a/b; I-C2 explicitly dropped from R-017;
REVERSAL-3 redefined in Scope §Deferred + AC-H04). My original P1..P6 all now correctly resolve to
`clarification_request`/chain. The predicate moved from *asserted-mechanical + systematically
biased* to *genuinely mechanical with residual lexicon/regex holes*. Substantial, good-faith fix.

## C2.1 — Poisoned normative fixtures (the flagship determinism gate is self-contradictory)

### CRIT-013 — MAJOR — The frozen fixture table contradicts the signal rules; a faithful extractor cannot pass AC-C06
**Anchor:** criteria §Normative fixtures (rows P3, P6, P5) vs §The eight signals (S5, S2, S3 rules);
AC-C06 ("extractor output equals the frozen fixture table row-for-row, exact match, exit 0").

Walking the frozen prompts through the frozen rules:
- **P3** "Rename `getUserData` … everywhere … update all call sites and the docs." — GENERIC_SCOPE
  (`everywhere`,`all`) **co-occurs** with a PATH_OR_ID (`getUserData`, backtick-fenced ⇒ symbol).
  The S5 rule = "no GENERIC_SCOPE, **OR** a GENERIC_SCOPE co-occurs with a PATH_OR_ID/authority
  bound" → second disjunct TRUE → **S5=1**. The frozen fixture says **S5=0.** Contradiction.
- **P6** "Weigh whether … REST or gRPC … set it up." Frozen `S2=1, S3=0`. S2 can only be 1 via a
  DELIVERABLE_NOUN (none present — "service" is not in the list) or a PATH_OR_ID; if a PATH_OR_ID
  is present, S3 (same trigger) must also be 1. `(S2=1,S3=0)` is **unreachable** by the rules.
- **P5** "Set up CI for the project." Frozen `S2=1`, but "CI" is not a DELIVERABLE_NOUN and whether
  "CI" is a "CamelCase symbol" is undefined for all-caps acronyms → S2 is **indeterminate**, and
  the tie-break says indeterminate→0, so a faithful extractor yields S2=0 ≠ frozen 1.

The routes are unaffected (other 0-cells dominate), so this is not a misroute — it is worse: the
**extractor-determinism gate itself (AC-C06), the linchpin of the CRIT-001/002 fix, is
unsatisfiable as frozen.** An implementer either fails CI permanently or hand-codes the three
fixtures as special cases — **re-admitting exactly the discretion CRIT-001 removed, behind a green
gate.** Provable by pure inspection; independent of S6/S7.
**Disposition (REVISE):** recompute every frozen S-vector from the published rules (or fix the
rules), so P3.S5, P6.(S2,S3), P5.S2 agree with a mechanical extractor; add a self-check that the
fixture table is internally consistent with the lexicons before freeze.

## C2.2 — Fresh adversarial pass against the lexicons (six NEW prompts, verbatim)

Each evaluated inside the no-match branch (S6∧S7 assumed to hold unless noted). ACT_VERBS,
INVESTIGATE_VERBS, DELIVERABLE_NOUNS, GENERIC_SCOPE, ACCEPTANCE_MARKERS, PATH_OR_ID as frozen.

### CRIT-014 — MAJOR — S1 is part-of-speech-blind: ACT_VERBS that are common nouns false-hit → over-fire onto read-only intents
**N3 (lexicon false-hit / over-fire):** *"In `services/auth/Login.ts`, explain what the recent
patch does and why the update matters, until it's clear to me."*
- S1: `patch` and `update` are ACT_VERBS — **matched as nouns** (word-boundary presence, no POS) →
  **S1=1**, though the only imperative verb is `explain` (INVESTIGATE) and the intent is read-only.
- S2: `services/auth/Login.ts` (slash + `.ts`) → 1. S3: PATH_OR_ID → 1. S4: `until` ⇒ ACCEPTANCE
  → 1. S5: no GENERIC_SCOPE → 1. → **predicate TRUE → dispatch the write-capable generalist onto a
  purely investigative "explain this code" mission.** Two evaluators diverge on S1 (intent-reader:0
  vs strict-presence:1). Many ACT_VERBS are everyday nouns (`patch, update, build, fix, wire,
  install, upgrade, bump, set up, scaffold, remove, apply`) → systematic over-fire vector.
**Disposition:** add a POS/noun-sense guard (e.g. require the ACT token in imperative/verb
position, or exclude ACT tokens that are immediately preceded by an article/possessive: "the patch",
"the update"), or subtract an INVESTIGATE-dominant override when the head verb is INVESTIGATE.

### CRIT-015 — MAJOR — PATH_OR_ID extension-regex over-matches versions/decimals/units/abbreviations → phantom S2/S3 "named target"
**N4 (regex abuse / over-fire):** *"Configure the timeout to 30.5s until the healthcheck returns
healthy."*
- S1: `configure` → 1. S2/S3: `30.5s` matches `[\w./-]+\.[A-Za-z0-9]{1,6}` (**verified**:
  `30.5s`,`2.5.0`,`3.14`,`e.g.` all EXT-MATCH) → treated as PATH_OR_ID → **S2=1, S3=1** although
  `30.5s` names **no repo surface**. S4: `until`,`returns` → 1. S5: no GENERIC_SCOPE → 1. →
  **dispatch onto a mission with no identified target** — precisely what S3 "named_target" exists to
  prevent. Any prompt carrying a version/decimal/measurement/`e.g.` trips it.
**Disposition:** tighten PATH_OR_ID to exclude pure-numeric/version/unit tokens (require ≥1 alpha in
the stem and a known-ish extension, or disallow a digits-only pre-dot segment); define the
"CamelCase/snake_case symbol" clause precisely (all-caps acronyms? hyphenated? Title-case single
words — see P5 "CI").

### CRIT-016 — MAJOR — S5 co-occurrence rule is too weak: any co-occurring path neutralizes GENERIC_SCOPE → repo-wide mutations dispatch (CRIT-008 re-opened)
**N5 (generic scope + one concrete path):** *"Refactor `src/legacy/` across the entire codebase to
remove deprecated calls, until the test suite is green."*
- S1: `refactor`,`remove` → 1. S2/S3: `src/legacy/` (slash) → 1. S4: `until`,`green` → 1. S5:
  GENERIC_SCOPE (`across`,`the entire codebase`) present, but **co-occurs** with PATH_OR_ID
  `src/legacy/` → S5 rule's second disjunct → **S5=1.** → **dispatch a repo-wide ("entire
  codebase") mutation onto the `writes_repo:false` worker** — the exact blast-radius the CRIT-008
  guard was added to stop. The guard is defeated because the rule treats *any* co-occurring path as
  "bounded," even when the generic scope explicitly widens beyond it. (Same mechanism produces the
  P3 fixture contradiction, CRIT-013.)
**Disposition:** S5 should be 1 only when GENERIC_SCOPE is *absent*, or when every GENERIC_SCOPE
token is **scoped by** the path (e.g. "everywhere in `src/legacy/`"), not merely co-present; treat
"across/entire/whole + <path>" as still-unbounded → clarify.

### CRIT-017 — MAJOR — Arm-2 "labeled ground-truth owner" labeling is unguarded → the hard MUST=0 over-capture bar is gameable
**Anchor:** AC-G03/G04, R-041/R-042 ("each prompt labeled by ground-truth owner"; over-capture =
generalist fired on a specialist-owned prompt). The spec pins `maker≠checker` on the gate *verdict*
(AC-G05) and `maker≠checker on construction` for the **Arm-1** holdout — but says **nothing about
who assigns the Arm-2 labels, nor that labels are frozen/blind before the generalist runs.** If the
maker (or a non-independent party) labels a captured borderline prompt as "generalist-owned," the
over-capture count is defined down to 0 — a green MUST=0 bar over a router that over-captures. The
CRIT-003 forgeability moved from the *corpus* to the *labeling*.
**Disposition:** require the Arm-2 owner-labels to be (i) assigned by an independent party
(labeler ≠ maker), (ii) **SHA-frozen before** the generalist is run (blind to outcome), (iii) per a
written labeling rubric — mirror the Arm-1 "maker≠checker on construction" clause onto labeling.

### CRIT-018 — MINOR — Closed-lexicon coverage gap (under-fire; safe direction, but caps Arm-1 coverage)
**N1 (lexicon miss):** *"Append a `retry` field to `config/http.yaml` so requests retry 3 times."*
`append` is genuinely actionable but **absent from ACT_VERBS** → S1=0 → clarification. Also missing:
`insert, enable, disable, revert, rollback, seed, provision, compile, lint, format, export, import,
publish, init, bootstrap, stub, deprecate`. Under-fire is the safe direction, but it silently
shrinks the seat's coverage (Arm-1 denominator) and creates evaluator divergence on out-of-lexicon
verbs. **Disposition:** publish a lexicon *versioning + maintenance* policy and an explicit rule
that out-of-lexicon verbs → S1=0 → clarify (so divergence is defined away), and broaden ACT_VERBS.

### CRIT-019 — MINOR — Predicate input language/format is unscoped
**N6 (non-English):** *"Crea el archivo `src/app.py` y añade la función `login` para que el test
pase."* Fully actionable in Spanish, but English-only lexicons → S1=0 → clarification. Emoji /
code-fenced prompts are likewise unspecified. AC-C06's "two independent evaluators produce identical
vectors" only holds if both ignore meaning and apply the English lexicon literally. **Disposition:**
scope the predicate to English input explicitly (and state that non-English/emoji-only prompts route
to clarification by design), so the behavior is intentional rather than incidental.

## C2.3 — Duty-4 classifications (gate gaming) and the Arm-1 floor

- **Arm-1 rate floor X% pinned or placeholder?** — **Legitimately human-owned (OQ-1), NOT a
  defect.** CRIT-004 was about the forgeable *structure* (">0" bar); rev 2 pins the structure (rate
  + strata + SHA-frozen non-cherry-pickable holdout + pass³ + maker≠checker on construction). Only
  the numeric X remains, which properly needs precedent/human calibration (as RAMZA-succession's
  non-inferiority number did). Same for the Arm-2 near-threshold numeric bound. Correctly deferred.
- **Arm-2 labeling gameable?** — **Yes → CRIT-017 (MAJOR).** The labeler-independence/blinding is
  the one guard the revision did not extend from Arm-1 construction to Arm-2 labeling.

## C2.4 — Tooling / audit observations (out of spec scope; recorded for the owner)

### CRIT-020 — MINOR — `ramza-gate advance --to A` is verdict-blind (RAMZA tooling, not this plan)
Confirmed: the tier=full guard checks only that `.critic.checker` is non-empty, never the critic's
verdict — so a REVISE critic record satisfies it exactly as an approval would. This is the hole the
maker's probe hit. Not a defect in *this spec* (the maker held at T), but the RAMZA tooling owner
should gate on a recorded *approval*, not a record's mere presence. (Project maxim: nothing checks
the checker — here, the gate does not check the check's verdict.)

### CRIT-021 — MINOR — Audit hygiene of the manual T→A→T revert
Because `ramza-gate` has no revert verb, the erroneous advance was undone by a manual state edit
(the transient `A` is scrubbed from `phases_done`; the round-trip survives only as `corrections[]`
prose). Honest and correct outcome; noted only so the phase history's provenance (tool vs hand-edit)
is explicit in the record.

## Cycle 2 — independent gate result

`ramza-score --rubric refine --cycle 2` (critic, independent of the maker's self-score 4.4):
clarity 5 · completeness 4 · **actionability 4** · efficiency 4 · **testability 3** → **min 3 < 4 →
verdict: fail.** The testability shortfall is the demonstrated gap between the predicate's
*mechanical-determinism claim* (R-017/AC-C05/C06) and its behavior: a self-contradictory fixture
table (CRIT-013) plus three systematic over-fire vectors (CRIT-014/015/016) plus a gameable Arm-2
label (CRIT-017).

## VERDICT (cycle 2): REVISE

**No BLOCKING. 5 MAJOR (CRIT-013..017) + 4 MINOR (CRIT-018..021).** Rev 2 is a large, honest
improvement — every rev-1 disposition is real, my original attacks are defeated, the state trail is
truthful, and the Arm-1/Arm-2 numeric deferrals to OQ-1 are legitimate. But the fresh pass shows the
lexicon predicate does **not yet** survive: the flagship extractor-determinism gate is
self-contradictory (CRIT-013), the predicate over-fires the write-capable worker via noun false-hits
(CRIT-014), phantom numeric targets (CRIT-015), and a defeated blast-radius guard (CRIT-016), and
the MUST=0 over-capture bar rests on unguarded labeling (CRIT-017). All five are **narrow and
mechanically fixable** (recompute the frozen vectors; add a noun/POS guard; tighten PATH_OR_ID;
strengthen the S5 co-occurrence rule to require path-*scoping*; pin labeler-independence+blinding).
Route to Refine; do not enter Assemble until CRIT-013..017 are resolved and the fixture table is
re-derived to agree with the rules.

*Critic: `ramza-critic-fresh` — cycle 2. maker≠checker recorded via `ramza-gate critic`. Read-only;
spec artifacts unmodified.*

---

# Cycle 3 — re-check of rev 3 (critic: `ramza-critic-fresh`)

**Stakes noted:** `refine_cycles = 2` of 3 — last headroom before the cap forces escalation.
Verdict calibrated to evidence: REVISE only for a defect that materially compromises a
ship-authority gate (Arm-1/Arm-2/token-CI) or the determinism invariant; otherwise APPROVE with
residual MINORs recorded.

## C3.0 — Mechanical anchors (rev 3) + state honesty

| Anchor | Critic result | Claim | Concordance |
|---|---|---|---|
| `ramza-lint` | `ok … (tier: full)` exit 0 | pass | MATCH |
| `ramza-ears-lint` | `ok: 57 criteria pass` exit 0 | 57/57 | MATCH |
| `sha256sum acceptance-criteria.md` | `d088c0cc58b72330bea3f61fc376c1f7c5e1086496c1d3297793d1cf3f9ff8d8` | claimed `d088c0cc…ff8d8` | **EXACT MATCH** |
| requirements (spec.md ∩ spec.yaml) | 54 ∩ 54 | 54 | MATCH |
| acceptance-checks (criteria ∩ spec.yaml) | 57 ∩ 57, symmetric-diff empty | 57 | MATCH |

**State honesty:** my cycle-2 REVISE record is present (`gates[]`
`critic-cycle2-ramza-critic-fresh` refine fail, min 3); rev 3 is recorded (`revision:3`,
`revision_note`, updated SHA with rev2 superseded); phase held at **T**, `critic_status` pending,
**not self-approved.** Honest.

## C3.1 — CRIT-013 determinism fix: INDEPENDENTLY RE-DERIVED (the core duty)

I hand-executed the published reference extractor (phrase-normalize → tokenize → S1..S5 rules,
tightened PATH_OR_ID, imperative-position S1, LIMITER-rescue S5) against **all 17 fixtures** — well
beyond the required 8, spanning every P and C row. **Result: 17/17 vectors match the frozen table
exactly; 0 mismatches.** Spot-highlights:

- **P7** "…explain what the recent patch does and why the update matters, until it's clear…" →
  S1=**0**. `patch`/`update` are ACT lexemes but sit in noun position (prev = `recent`/`the`; `the`
  ∈ DET_BLOCKLIST, neither in imperative position) → S1 correctly suppressed. **CRIT-014 fixed.**
- **P8** "Configure the timeout to 30.5s until…" → S3=**0**. `30.5s` fails tightened PATH_OR_ID
  (stem `30` has no letter; ext `5s` ∉ FILE_EXT). **CRIT-015 fixed** (mechanically reproduced:
  `30.5s`,`2.5.0`,`3.14`,`e.g.` all excluded; real paths/fences all included).
- **P9** "Refactor `src/legacy/` across the entire codebase…" → S5=**0**. Generic scope present, no
  LIMITER → not neutralized by the co-occurring path. **CRIT-016 fixed for the fixture set.**
  **C6** "…across `src/auth/` **only**, until…" → S5=**1** (LIMITER-rescue). Both directions verified.
- **P3.S5=0, P6.(S2=0,S3=0), P5.S2=1** — the three rev-2 self-contradictions (CRIT-013) are **all
  resolved** and now reproduce from the rules. **P10** (Spanish) → S1=0 (English-only, CRIT-019).
  **C5** "Append…" → S1=1 (lexicon broadened, CRIT-018).

The machine-derivation claim holds under independent execution. **The determinism invariant is
intact.**

**Disposition reality:** all nine cycle-2 dispositions are real in the text — CRIT-013 (published
extractor + AC-C06/C11 self-check), CRIT-014 (imperative-position + DET_BLOCKLIST, AC-C09),
CRIT-015 (tightened PATH_OR_ID + FILE_EXT, AC-C10), CRIT-016 (LIMITER-rescue S5, AC-C08),
**CRIT-017** (AC-G07: labeler ≠ maker ≠ generalist-builder, labels SHA-frozen pre-replay, second
blind adjudicator — the Arm-2 labeling hole is closed), CRIT-018/019, CRIT-020/021 recorded.

## C3.2 — Proportionate fresh probe of the NEW rev-3 surface (3 prompts)

### CRIT-022 — MINOR (recorded) — PATH_OR_ID rule 2 (bare filename + extension) has ZERO fixture coverage
Every path-token in the 17 fixtures uses rule 1 (contains `/`) or rule 3 (backtick-fence); **no
fixture exercises rule 2** (a bare filename like `README.md`/`index.js`, no slash, unfenced). So
AC-C06/AC-C11 give no coverage of rule 2 — a bug there (I hit an ambiguity reproducing it) would
ship untested. Not a determinism failure (the invariant is verified on the covered rules), but a
test-suite gap. **Disposition:** add one fixture with a bare filename+ext, e.g. *"Update README.md
so the badges render."* → expected S2=S3=1 via rule 2.

### CRIT-023 — MINOR (recorded) — S5 LIMITER-rescue checks co-PRESENCE, not binding (residual blast-radius edge)
**N8:** *"Refactor the entire codebase, only if practical, until `README.md` matches the new API."*
`Refactor` (first → imperative) S1=1; `README.md`/path→ S2=S3=1; `until`/`matches`→ S4=1;
GENERIC_SCOPE (`entire codebase`) present, **LIMITER `only` + a PATH_OR_ID co-present anywhere** →
S5=**1** → **dispatch a repo-wide refactor** — though `only` binds "if practical" (not the scope)
and `README.md` is the acceptance artifact (not a scope bound). The rev-3 rule tightened rev-2's
"any path neutralizes generic" to "any LIMITER **and** any path," but still does not require the
LIMITER to *bind* the generic scope. **Why MINOR, not REVISE:** it does not compromise a
ship-authority gate — Arm-2's near-threshold + paraphrase + labeled-owner corpus is precisely what
measures residual over-capture before ship — nor the determinism invariant (N8's vector is
reproducible; the rule is merely semantically loose); and the target is `writes_repo:false` +
PROPOSE-only + sandbox-first, so a mis-dispatch cannot mutate the repo, only surface an oversized
proposal. **Disposition:** require the LIMITER (or a narrowing PATH) to occur in the **same clause**
as the GENERIC_SCOPE token; add N8 as an Arm-2 fixture.

### CRIT-024 — MINOR (recorded) — no interrogative guard; verb-first questions read as imperatives
**N7:** *"Rewrite `api/users.js` until when?"* — `Rewrite` (first) S1=1; path S2=S3=1; `until`
S4=1; no generic S5=1 → **dispatch on an interrogative** (the user is *asking*, not commanding). The
imperative-position rule has no `?`/wh-word detector. Narrow (most questions lack a bounded
acceptance marker) and safe-defaulting elsewhere, but recordable. **Disposition:** route a prompt
whose sentence is interrogative (leading act-verb + trailing `?` / wh-word) to
`clarification_request`.

### CRIT-025 — MINOR (by-design; recorded) — backtick-fence manufactures PATH_OR_ID from gibberish
**N9:** *"Add `foo` to `bar` until `baz` matches."* — fenced `foo`/`bar` satisfy S3 though they name
nothing. Arguably intended (the user's backtick asserts "this is an identifier"), and backstopped by
the worker's externalized verification (it finds nothing → PROPOSE/clarify). Recorded as acceptable
design with a note, not a defect.

## C3.3 — Ship-authority gates + determinism: status

- **Determinism invariant** — VERIFIED (17/17 independent re-derivation).
- **Arm-1** — hardened (rate-floor + strata + SHA-frozen non-cherry-pickable holdout + pass³ +
  maker≠checker on construction); numeric X% legitimately human-owned (OQ-1).
- **Arm-2** — hardened (labeled-owner + near-threshold `[τ−0.15,τ)` + paraphrase + P1..P11;
  **AC-G07** independent blind labeler ≠ maker ≠ builder, SHA-frozen pre-replay, second-blind
  adjudication). CRIT-017 closed.
- **Token-budget CI** — tokenizer-pinned (`ceil(chars/4)` of the marker-bounded region, fail > 850,
  ±15% BPE fixture). CRIT-005 closed.

None of CRIT-022..025 compromises any of the above. They are predicate-edge refinements, each
defense-in-depth-backstopped.

## Cycle 3 — independent gate result

`ramza-score --rubric refine --cycle 3` (critic, independent of the maker's self-score 4.8):
clarity 5 · completeness 4 · actionability 5 · efficiency 4 · testability 4 → **min 4 ≥ 4 →
verdict: pass.** (The two 4s reflect CRIT-022's coverage gap and the CRIT-023 residual — real but
minor.)

## VERDICT (cycle 3): APPROVE

**No BLOCKING. No MAJOR.** Rev 3 closes all five cycle-2 MAJORs with mechanically-verifiable fixes:
I **independently re-derived 17/17 fixtures** (CRIT-013 determinism holds), mechanically confirmed
the tightened PATH_OR_ID (CRIT-015), and verified the noun-trap (CRIT-014), blast-radius fixture
behavior (CRIT-016), Arm-2 labeling guard (CRIT-017), and English-scoping (CRIT-019) in the frozen
text. All three ship-authority gates are hardened and the determinism invariant is intact.

**Residual findings — recorded-not-blocking (all MINOR):**
1. **CRIT-022** — add a rule-2 (bare filename+ext) fixture; rule 2 is currently uncovered.
2. **CRIT-023** — tighten S5 LIMITER-rescue to require same-clause binding; add N8 to the Arm-2 corpus.
3. **CRIT-024** — add an interrogative guard (verb-first question → clarify).
4. **CRIT-025** — backtick-fence trust: acceptable by design; note only.
5. Carried tooling notes: **CRIT-020** (`ramza-gate advance --to A` is verdict-blind — RAMZA
   tooling, out of this plan's scope) and **CRIT-021** (manual-revert audit hygiene).

The plan is critic-APPROVED and eligible to advance T→A (Assemble/freeze) — the maker's step; I do
not advance it (read-only critic). The ESL change-checker (kupo) and the human go/no-go + naming
remain required pre-flip per R-045 (two-checker topology) and `requires_checker=true`.

*Critic: `ramza-critic-fresh` — cycle 3. maker≠checker recorded via `ramza-gate critic`; refine
cycle-3 PASS is the mechanical approval signal. Read-only; spec artifacts unmodified.*
