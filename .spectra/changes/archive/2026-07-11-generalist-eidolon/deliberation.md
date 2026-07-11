---
title: FORGE deliberation — covering the "general-purpose agent" seat in the Eidolons roster
producer: FORGE (Reasoner), standard single-trace (self-consistency NOT used, per maintainer instruction)
methodology: FORGE 1.10.0
decision_type: TRADE-OFF (constraint-gated)
campaign: generalist-eidolon
date: 2026-07-10
requires_checker: true
---

# [VERDICT] Adopt **H-E** — a new, measurement-gated `generalist` Eidolon that is dispatched *only* as a strict specialist-preferring fallthrough worker, and packaged as the exportable methodology for host general-purpose slots.

Confidence: **77%** (moderate-high — act with monitoring; two named [GAP]s and a hard cortex-budget precondition).

---

## F — Frame

### The decision (Specificity Test applied)

> Given the Eidolons nexus machinery — a **closed** 8-value `capability_class` enum, an always-loaded cortex already **at/over** its ≤900-token ceiling, specialists that are **narrow by explicit design** at multiple enforcement layers, a Dispatch Protocol whose Step-2 no-match branch bounces every unrouted prompt to `clarification_request` (there is **no** catch-all route today), and **no** mechanism for wiring an Eidolon into a host's built-in general-purpose slot — how should the roster cover the "general-purpose agent" seat (mixed read+act, multi-step, cross-class-or-unroutable missions), such that (a) it actually covers that seat, (b) the specialist-first routing philosophy survives, (c) it is measurement-gateable per the Kupo/RAMZA precedent, and (d) it satisfies every nexus P0 hard constraint?

**Decision type:** `TRADE-OFF` (5+ viable options) gated by `CONSTRAINT-SATISFACTION` (11 hard constraints). Multi-criteria weighted scoring is the reasoning pattern.

**Two senses of "the seat" (do not conflate — per E1):**
- **S-internal** — the roster's own routing has no target for a *clear, actionable, multi-step, mixed read+act* prompt that fits no specialist trigger or spans classes with no clean chain. Today it bounces to `clarification_request` even when actionable (a routing false-negative).
- **S-host** — the methodology exported into a host's native catch-all agent (Claude Code `general-purpose`, Codex/OpenCode/Cursor catch-all slots). Covering this is what the maintainer's target names explicitly.

A third, structural framing from the research (E1, reference design): a general-purpose *system* needs **coordinator + read-only explorer + write-capable general worker + independent verifier**. Eidolons has the coordinator (orchestrator/cortex), the read-only explorer (ATLAS), and the verifier (VIGIL / Kupo's external-verifier) — but **no write-capable general worker**. That is a structural hole in the reference architecture, independent of prompt frequency.

### Deliberation depth (Framing Step 4)

Ambiguity 3 (≥5 viable paths, unclear winner) + Reversibility 3 (new external repo + CI row + cortex trim + ECL contracts; reversible only by expensive deprecation) + Blast radius 3 (touches the every-session cortex + routing philosophy + external repos) = **9 → Deep**. Per maintainer instruction, run **standard single-trace FORGE (2 passes + leader red-team), NOT self-consistency (G2)**. Depth-9 without G2 is honored by an explicit Pass-2 red-team on the leader.

### Constraint map (hard = fail if violated)

| ID | Constraint | Hard/Soft | Source |
|----|-----------|-----------|--------|
| HC1 | No per-Eidolon methodology content in the nexus repo — it lives in the member's own repo | Hard | CLAUDE.md "Notes on scope" |
| HC2 | ECL 10-performative set closed (no new performatives) | Hard | CLAUDE.md ECL P0 |
| HC3 | ESL anti-scope — name fields / reference schemas by version, never re-declare a deferred schema | Hard | CLAUDE.md ESL P0 |
| HC4 | EIIS install contract | Hard | CLAUDE.md |
| HC5 | Marker-bounded host-file sections | Hard | CLAUDE.md invariants |
| HC6 | Idempotent sync | Hard | CLAUDE.md invariants |
| HC7 | bash 3.2 compatibility | Hard | CLAUDE.md |
| HC8 | Kupo "worker, never router" + subagents-cannot-spawn-subagents is a host-level architectural fact | Hard | task; EIDOLONS.md:29 |
| HC9 | Cortex always-loaded ≤900 tokens; a new row must be paid for by trimming (already at/over — FINDING-019) | Hard (precondition) | I-C4; FINDING-019 |
| HC10 | Must be measurement-gateable before `status: shipped` (Kupo/RAMZA/Vivi precedent) | Hard | FINDING-013/014, A14 |
| HC11 | MAST — an added agent must reduce uncertainty or expand authority-scoped capability *measurably*; head-count growth alone fails | Hard | E1 finding 6; task |

### Success criteria
- [x] Picks among H-A..H-E (+ any added) with rejection reasons
- [x] Every hard constraint given pass/fail
- [x] Reversal conditions stated
- [x] If new-Eidolon: draft roster-row scope boundary + Dispatch Step-2 change + measurement gate
- [x] `requires_checker` evaluation
- [x] Confidence with 4-factor calibration

---

## O — Observe (Evidence Inventory)

| ID | Source | Type | Relevance | Reliability |
|----|--------|------|-----------|-------------|
| E1 | `gp-agent-research-digest.md` | Research digest | Direct | **H** for convergent findings (generality=harness property; small action substrate; externalized verification; delegation-on-boundaries; MAST/swarms-are-liabilities; capability permission tables). **M** for the reference-design *prescriptions* (TaskState schema, worker archetype) — the digest itself flags "no controlled ablation; engineering synthesis only." |
| E2 | `scout-report.md` (ATLAS) | Scout report | Direct | **H** for in-repo FINDING-001..019 (several re-verified below). **L** for GAP-001 (composition.md auto-gen enforcement not verified in-checkout). **M** for GAP-002/003. |
| E3 | My primary Reads: `EIDOLONS.md:15-58,42`, `routing.yaml:44-48`, `roster-entry.schema.json:11` | Source verification | Direct | **H** — confirmed: Step-2 fallthrough → `clarification_request` (no catch-all); `classes.default` exists for "unknown/future capability classes"; enum is closed at 8 values. |
| E4 | CRYSTALIUM recall (2 hits) | Prior memory | Neutral | Both hits are ECM-campaign episodics — **not relevant** to this decision. No prior verdict on this seat. |

**Critical [GAP]s carried into reasoning:**
- **[GAP-freq]** No trace data on how often `clarification_request` fires on *actionable-but-unroutable* prompts. The S-internal frequency justification is unmeasured. (This is precisely what the measurement gate resolves.)
- **[GAP-hostslot]** (GAP-002) No machinery wires an Eidolon into a host's built-in general-purpose type. In Claude Code the built-in `general-purpose` subagent type is **not** user-overridable via agent files [ASSUMPTION, M — inferred from FINDING-017/018 + host behavior]. So the S-host sense is achievable as *a named fallthrough agent + exported methodology/documentation*, **not** as a literal override of the host's built-in type. Every hypothesis inherits this ceiling equally.
- **[GAP-comp]** (GAP-001) composition.md auto-gen-from-eidolons-ecl enforcement unverified in this checkout; affects blast-radius estimates for A/B/C/E equally.

---

## R — Reason

### Hypotheses (6 — genuinely distinct actions)

Two positions were added beyond the supplied A–E: **H-F** (measure-first / defer the member) as the strongest MAST-disciplined objection to adding anything. H-E is retained as the supplied hybrid; the "simplest viable" mandatory hypothesis is H-D.

#### H-A — New Eidolon + new `generalist` class (as supplied)
**Position:** Mint a new member packaging the research findings; Step-2 fallthrough routes to it "instead of (or before) `clarification_request`"; optionally the host-GP methodology.
**Requires:** the closed enum extends (A1, documented backward-compatible path — FINDING-004); the fallthrough semantics don't cause over-capture.
**Weakness:** "instead of (or before)" is **ambiguous** on specialist-preference. If the generalist competes in Step-1 scoring it steals prompts from specialists → MAST inter-agent-misalignment + breaks routing determinism (I-C6).

#### H-B — Promote Kupo
**Position:** Widen Kupo's triggers/refusals/tools/model into the general seat.
**Falsification / stress:** Reverses **four independent** narrow-by-design layers (routing refuse_verbs, tool allowlist, skill-level refusal gate, handoff role — FINDING-005..009). Destroys Kupo's "structurally non-negative cheap bounce" safety property. The K→U→P→O cycle is architected for ≤2-file micro-tasks; a general mode is "a new methodology under an old name" (B7). **Name collision** is fatal to I-C6: Kupo would score on *both* micro-task and open-ended verbs, so the same prompt no longer routes deterministically. Confounds the Kupo eval (the KEEP-cohort 36/36 measured micro-task behavior). **Worst of both worlds:** the full build cost of a new methodology *plus* the destruction of a working safety property.

#### H-C — Widen a non-Kupo member (Vivi or ATLAS)
**Position:** Vivi becomes coder+generalist, or ATLAS grows act-capability.
**Stress:** Collapses a *deliberate* class boundary. A generalist must **not** refuse open-ended work — but Vivi's design/novel-architecture refusal is a core boundary that feeds the design→planner handoff; removing it dissolves the "loop-native coder" identity. ATLAS-grows-act violates the **read-only explorer** invariant (scout refuses implement/fix/edit/write/commit) — the exact safety property the reference design relies on. Same category error as H-B on a different, larger member.

#### H-D — No new persona (orchestrator machinery only) [simplest viable]
**Position:** Cover the seat with a fallback chain template / routing rule composed from existing specialists.
**Stress:** Covers *routable* cross-class prompts — but the 8 existing chain templates already do most of this. It does **not** cover the actual gap: fits-no-specialist / open-ended-bounded-write missions, because the specialists **refuse** the open parts (Vivi refuses design; Kupo refuses >2-file). And there is **no persona to export** for S-host. Risks conflating **coordinator with worker** (MAST role-confusion) if the "fallback chain" tries to act rather than route. Covers the easy half, misses the gap. **Best on cost/reversibility, worst on fit.**

#### H-E — Hybrid A+D: new `generalist`, strict specialist-preferring fallthrough, gated [supplied]
**Position:** A new generalist Eidolon that is (1) the roster's fallthrough target for *actionable-but-unroutable / cross-class multi-step* missions **and** (2) the exported methodology for host GP slots — while Dispatch continues to **prefer specialists whenever one scores ≥ τ**. The generalist carries **no positive trigger verbs** (it never enters Step-1 scoring); it is dispatched **only** via a new Step-2 branch, and **only** when the prompt is actionable. Underspecified prompts still → `clarification_request`.
**Why it dominates A:** it resolves A's ambiguity by making specialist-first *load-bearing and mechanical*. The generalist is strictly last-resort, so it cannot compete with specialists → I-C6 preserved.
**HC8 fit:** the generalist is itself a subagent → it **cannot spawn**. It delegates by **returning a typed handoff request upward** to the orchestrator (mirroring Kupo's "flag, orchestrator dispatches"). It is a *worker, never a router* — fully consistent with HC8, and consistent with E1's "delegation = typed contract" prescription.
**HC1 fit:** the methodology (TaskState schema, capability/authority permission table, explicit stopping policy, typed delegation contracts, externalized-verification loop, "deliberately boring worker" posture) lives in the **new member's own repo** — the nexus gets only a roster row + routing block + cortex row + CI line + external ECL edge contracts. Correct four-layer split.

#### H-F — Defer the member; ship routing-only now, gate the member on measured trace frequency [added — MAST-disciplined]
**Position:** Ship H-D's routing rule now (cheap, reversible), **instrument** `clarification_request` to measure how often actionable-but-unroutable prompts fire, and only mint the member (→ H-E) if the trace shows a persistent boundary — literally E1's prescription: "add specialists only when task traces show a persistent modality or context boundary."
**Strength:** the single strongest objection to adding anything now — the S-internal frequency justification is a [GAP], and MAST says head-count is a liability by default.
**Resolution (why it folds, not wins):** the Eidolons process **already** stages exactly this. A new member enters at `status: in_construction` and flips to `shipped` **only** after clearing a measurement gate (Kupo: in_construction v0.1.0 → KEEP-cohort eval → shipped v1.0.0 — FINDING-013). H-F's instrumentation is precisely what that gate's holdout consumes. So H-F ≡ "H-E executed through the standard in_construction→gate→shipped discipline." It is absorbed into H-E's rollout, not a different destination. Its distinct claim — "don't even mint at in_construction until traces justify it" — trades a small, reversible in_construction build for an open, unowned seat and leaves S-host uncovered indefinitely; and the **authority gap is structural, not frequency-based** (the write-capable-worker archetype is missing regardless of how often it fires), which is a principled, non-frequency justification to mint the worker now.

### Adversarial stress-tests (Inversion / Boundary / Pre-Mortem / Dependency) on the leader (H-E)

- **Inversion** — *If a generalist were NOT needed, what would I see?* I'd see specialists whose refuse-sets fully tile the mission space (no actionable prompt falls through) OR a coordinator that can itself act on open-ended missions. I see neither: the specialists refuse the open parts by design, and the coordinator cannot be the worker (subagents can't spawn; coordinator≠worker in E1). The inversion evidence is **absent** → the gap is real. But I also *do* see the frequency inversion (no trace proving the fall-through fires often) → this is why the gate, not the verdict, certifies `shipped`.
- **Boundary** — Breaks if the "actionable vs underspecified" split (the Step-2 branch predicate) cannot be made **mechanical** (I-C2/I-C6 require data, not LLM discretion). If the split is fuzzy, the generalist either over-captures (steals from `clarification_request` — annoying) or under-fires (no coverage). Mitigation lives in the spec: the predicate must be observable signals (explicit objective present + action verb present + no single-specialist ≥ τ + no clean chain), not vibes.
- **Pre-Mortem** — *We shipped it and it failed. Most likely cause?* **Over-capture** — the generalist scored/fired on prompts a specialist should own, eroding specialization and routing determinism → the roster's core value proposition. → `[RISK-over-capture]`, and the reason the no-regression arm of the gate is mandatory.
- **Dependency** — Holds only while: (a) the cortex budget can be reclaimed under 900 tokens (HC9); (b) the host permits a named fallthrough agent + methodology export (S-host ceiling, [GAP-hostslot]); (c) the eval infra (KEEP-cohort/RAMZA-style holdout) remains available. Each is a `[REVERSAL-CONDITION]`.

### Scoring rubric (custom — aligned to the task's six soft criteria)

Weights (justified): **Fit-to-target 25%** + **Roster-coherence 22%** dominate (47%) — a wrong routing philosophy is paid every session forever, and a solution that misses the seat fails the mission; both outrank one-time build cost. **Methodology-substance 15%** + **Measurement-gateability 13%** (28%) are the "is it real and provable" axes (substance also gives the member a home per HC1 and satisfies MAST/HC11). **Blast/reversibility 13%** + **Maintenance 12%** (25%) are the cost axes — real, but one-time / bounded.

Each cell scored 1–5 independently before comparison.

| Dimension (weight) | H-A | H-B | H-C | H-D | **H-E** | H-F |
|---|---|---|---|---|---|---|
| Fit-to-target (25%) | 4 | 3 | 3 | 2 | **5** | 3 |
| Roster-coherence (22%) | 3 | 1 | 1 | 4 | **5** | 5 |
| Methodology-substance (15%) | 5 | 2 | 2 | 2 | **5** | 2 |
| Measurement-gateability (13%) | 4 | 2 | 2 | 3 | **5** | 5 |
| Blast radius / reversibility (13%) | 2 | 1 | 2 | 5 | **2** | 4 |
| Maintenance cost (12%) | 2 | 2 | 3 | 5 | **2** | 4 |
| **Weighted composite** | **3.43** | **1.90** | **2.15** | **3.32** | **4.25** | **3.80** |

Composite arithmetic (Σ score×weight):
- H-A = 4(.25)+3(.22)+5(.15)+4(.13)+2(.13)+2(.12) = **3.43**
- H-B = 3(.25)+1(.22)+2(.15)+2(.13)+1(.13)+2(.12) = **1.90**
- H-C = 3(.25)+1(.22)+2(.15)+2(.13)+2(.13)+3(.12) = **2.15**
- H-D = 2(.25)+4(.22)+2(.15)+3(.13)+5(.13)+5(.12) = **3.32**
- **H-E = 5(.25)+5(.22)+5(.15)+5(.13)+2(.13)+2(.12) = 4.25**
- H-F = 3(.25)+5(.22)+2(.15)+5(.13)+4(.13)+4(.12) = **3.80**

**Ranking:** H-E (4.25) > H-F (3.80) > H-A (3.43) > H-D (3.32) > H-C (2.15) > H-B (1.90).

**Tie check (rule 3):** top gap = 4.25 − 3.80 = **0.45 > 0.3** → not a forced tie; H-E is a clear winner.
**Sensitivity check (rule 4):** the largest single-dimension ±1 swing on H-E (fit or coherence 5→4) yields 4.00–4.03, still > H-F's 3.80; raising H-F's fit 3→4 yields 4.05 < 4.25. **Winner is robust to ±1 on any single dimension** — a ~2-point combined swing would be needed to flip. Sensitivity is favorable.

**Convergence:** H-E led both passes (Pass-1 scoring, Pass-2 red-team). Winner unchanged across passes → +confidence.

---

## G — Gate

| Dimension | Result |
|-----------|--------|
| **Logical soundness** | No false dichotomy (6 hypotheses, incl. do-nothing H-D and defer H-F). No appeal-to-authority (E1's prescriptions graded M, not adopted on reputation). The H-F tension is *resolved* (absorbed into the in_construction gate), not suppressed. `[ASSUMPTION]`s marked: cortex-budget reclaimable via de-labeling deep tables; host-slot override not user-configurable in Claude Code. |
| **Evidence coverage** | Every load-bearing routing claim re-verified at source (E3). Two critical [GAP]s named and each mapped to a gate arm / reversal condition rather than reasoned past. |
| **Decision completeness** | Verdict answers the framed question; all 11 hard constraints below given pass/fail; 6 alternatives with reasons; reversal conditions + roster row + gate spec present. |

### Hard-constraint disposition for the winner (H-E)

| Constraint | Verdict | Note |
|---|---|---|
| HC1 (no methodology in nexus) | **PASS** | Methodology lives in the member's own repo; nexus gets row + routing + cortex + CI + external ECL contracts only. |
| HC2 (ECL 10 closed) | **PASS** | Uses existing performatives (PROPOSE verified result, INFORM, REQUEST-style delegation). New *edge contracts* are additive, not new performatives. |
| HC3 (ESL anti-scope) | **PASS** | Member repo names fields / references schemas by version; re-declares nothing deferred. |
| HC4 (EIIS) | **PASS** | New member is a standard EIIS-conformant repo (A10). |
| HC5 (marker-bounded) | **PASS** | Installer writes its host-file section inside `<!-- eidolon:<name> -->` markers like every member. |
| HC6 (idempotent sync) | **PASS** | Additive roster/routing/cortex entries; sync stays idempotent. |
| HC7 (bash 3.2) | **PASS** | No CLI logic change beyond an added roster name; conformance unaffected. |
| HC8 (worker-never-router) | **PASS (design-critical)** | Generalist is a subagent → cannot spawn; delegates by returning a typed handoff request upward. Must be enforced in the member's methodology + routing (`downstream: []`, delegation-as-emitted-artifact). |
| HC9 (cortex ≤900) | **PASS *only as a precondition*** | The always-loaded section is already at/over budget (FINDING-019). The row **cannot ship** until the section is re-fit < 900 tokens — reclaimable by moving mislabeled "always-loaded" deep tables (Chain-Template detail, TRANCE prose) to on-demand `methodology/cortex/`. `[CONSTRAINT]` for RAMZA. |
| HC10 (gateable) | **PASS** | Two-sided measurement gate defined below (capability-expansion + no-over-capture). |
| HC11 (MAST) | **PASS** | Justified on **authority-scope expansion** (the missing write-capable-worker archetype), not head-count. The frequency question is a [GAP] the gate resolves before `shipped`. |

### Confidence calibration (4 factors, 25% each)

| Factor | Score | Basis |
|--------|-------|-------|
| Evidence Quality | **72** | Load-bearing routing facts H (re-verified at source). Convergent research findings H. Two critical [GAP]s (frequency, host-slot ceiling) — but each is *managed* (mapped to a gate arm / reversal), not unmanaged. |
| Logical Coherence | **78** | Winner follows from fit+coherence dominance; H-F absorbed, not hand-waved. Two well-justified [ASSUMPTION]s in the non-critical path. |
| Constraint Coverage | **80** | All 11 hard constraints given explicit pass/fail; HC9/HC10 flagged as preconditions. |
| Sensitivity Analysis | **78** | Winner robust to ±1 single-dimension perturbation; A/E converge on the same action (the A-vs-E delta is design-precision, not destination). |

**Composite = (72+78+80+78)/4 = 77%.** → 70–84 band: *act with monitoring; flag assumptions.* Not ≥85 because the S-internal frequency is unmeasured and the S-host literal-override ceiling ([GAP-hostslot]) is unresolved.

**Gate result:** **PASS** (no REFORGE needed).

---

## E — Emit

### [VERDICT] Recommended action

Adopt **H-E**. Concretely, the recommended course of action is:

1. **Mint a new `generalist` capability class + a new Eidolon at `status: in_construction`** (persona/display **name is a MAINTAINER decision — do NOT auto-name**; the capability-class enum value is proposed as `generalist`).
2. **Wire it as a strict specialist-preferring fallthrough** (Dispatch Step-2 change below) — the H-D routing mechanism is *how the generalist is dispatched*, so H-D is a **component** of H-E's rollout, not a rejected rival.
3. **Gate it to `shipped`** only after the two-sided measurement gate passes — this is where H-F's discipline is honored.
4. **Hand off to RAMZA** to spec the change (right-size, criteria-freeze, plan-vs-diff drift, maker≠checker), and to the maintainer/**human** for the strategic go/no-go + naming.

### Rejected alternatives (reasons)
- **H-A** — same destination as H-E but without the strict-fallthrough / no-positive-triggers discipline; its ambiguous "instead of/before `clarification_request`" invites over-capture and I-C6 non-determinism. Rejected as *the riskier variant of the winning move*.
- **H-B (promote Kupo)** — reverses 4 narrow-by-design layers, destroys the cheap-bounce safety property, name-collides Kupo's identity (fatal to I-C6), and confounds Kupo's eval. Lowest score (1.90).
- **H-C (widen Vivi/ATLAS)** — collapses a deliberate class boundary (Vivi's design-refusal / ATLAS's read-only invariant). 2.15.
- **H-D (routing only)** — best on cost, but covers only the routable half and leaves the authority gap + S-host uncovered; no methodology, no exportable persona. Its mechanism survives *inside* H-E.
- **H-F (defer)** — MAST-correct but absorbed: the in_construction→gate→shipped process already stages the measurement it demands; deferring leaves an unowned seat + S-host uncovered and ignores the structural (non-frequency) authority justification.

### [REVERSAL-CONDITION]s (verdict-invalidating)
1. **Gate-fail (over-capture):** if the no-regression arm shows the generalist captures prompts a specialist should own (specialist routing precision regresses beyond the RAMZA-style non-inferiority margin) → do **not** flip to `shipped`; fall back to H-F stage-1 (routing rule only) / H-D.
2. **Gate-fail (no expansion):** if the capability-expansion arm shows the generalist does not meaningfully outperform the `clarification_request` baseline on actionable-but-unroutable missions → the seat isn't worth a member; revert to H-D.
3. **Frequency-null:** if instrumenting `clarification_request` shows actionable-but-unroutable prompts are vanishingly rare (e.g. < ~2% of dispatches) **and** no host demands the exported methodology → the authority justification weakens toward head-count; defer (H-F).
4. **Host-slot impossible:** if no host-GP-slot wiring is achievable within EIIS/marker constraints ([GAP-hostslot]) → S-host collapses to "documentation-only methodology"; the member still stands on S-internal + worker-archetype grounds, but re-check that fit still clears the bar (confidence would drop).
5. **Budget-locked:** if the cortex always-loaded section cannot be re-fit < 900 tokens even after de-labeling deep tables → the roster row cannot ship (HC9); blocks A/E until re-fit, else forces H-D (needs no row).

### [RISK]s (residual, post-mitigation)
- **[RISK-over-capture]** (highest) — the generalist eroding specialization. *Mitigation:* it carries **no positive trigger verbs** and never enters Step-1 scoring; it fires only in the Step-2 fallthrough branch, only when no specialist scores ≥ τ. This is the single most important design invariant.
- **[RISK-identity-drift]** — without a crisp refuse-set it becomes a dumping ground. *Mitigation:* explicit refuse-set (below) + the "deliberately boring worker" posture enforced in the member's methodology.
- **[RISK-coordinator-conflation]** — mis-specifying it as a mini-orchestrator (spawning) reproduces the MAST swarm liability + violates HC8. *Mitigation:* delegation-by-returning-typed-request-upward; `downstream: []`.
- **[RISK-cortex-regression]** — adding the row silently pushes the always-loaded section further over 900 (GAP-003: no CI gate enforces it). *Mitigation:* RAMZA's spec must include the trim **and** ideally add a token-budget CI check (closes GAP-003 as a bonus).

---

## Deliverable 3 — Draft roster-row SCOPE BOUNDARY (H-E winner)

> **Naming is a maintainer decision.** The persona/display name (à la "Kupo", "Vivi", "RAMZA") is explicitly **not** picked here. The mechanical **capability-class enum value** is proposed as `generalist` (the A1 enum extension, backward-compatible per FINDING-004).

| Field | Draft value |
|-------|-------------|
| **Capability class** | `generalist` (new enum value → `schemas/roster-entry.schema.json:11`) |
| **Status (initial)** | `in_construction` (v0.x) — flips to `shipped` only on gate pass |
| **Trigger verbs (Eidolons cortex)** | **NONE.** The generalist deliberately has *no positive triggers* and never enters Step-1 scoring. It is dispatched *only* via the new Step-2 fallthrough branch (below). (On the S-host surface, the *host's own* router invokes it — the Eidolons cortex is not in that loop.) |
| **Fallthrough condition (the real "trigger")** | Prompt is **actionable** (explicit objective + an action verb + a discernible acceptance/stop signal) **AND** is mixed read+act / multi-step **AND** no specialist scores ≥ τ (0.6) **AND** no clean chain template co-triggers. |
| **Refuse verbs** | Any intent that cleanly maps to a specialist trigger (map/trace → ATLAS; spec/plan/decompose → RAMZA; implement-known-terrain → Vivi; root-cause/flaky → VIGIL; document/ADR → IDG; ≤2-file micro-task → Kupo; trade-off/deliberate → FORGE). Also refuses: deploy / irreversible side-effects without a checker; **routing or spawning subagents** (worker-never-router, HC8); and **underspecified** missions (those still → `clarification_request`). |
| **Handoffs — upstream** | `[orchestrator]` — dispatched by the orchestrator on the Step-2 fallthrough branch; receives a typed mission contract `{objective, scope(paths,mode), deliverables, evidence_required, stop_conditions, authority(read/write/network/deploy)}` (E1 finding 5). |
| **Handoffs — downstream** | `[]` (worker, never router). Delegation is expressed as an **emitted typed handoff-request artifact** the orchestrator routes onward (to ATLAS for read-expansion, Kupo for a verifier-backed micro-patch, VIGIL for debug, IDG for docs, FORGE for a sub-decision). Mirrors Kupo's "flag; orchestrator dispatches." |
| **Lateral** | `[forge]` (may consult FORGE on in-mission trade-offs). |
| **security.writes_repo** | `false` at the boundary — acts within a **capability/authority permission table** (read/write/exec/network/secrets/deploy with default + escalation, E1 finding 7); write is sandbox-scoped + externalized-verification-gated, PROPOSE-only for anything crossing the authority line (same posture as Kupo/Vivi PROPOSE). |
| **Methodology home (HC1)** | New member's **own repo** (`Rynaro/<Name>`): TaskState schema, capability/authority table, explicit stopping policy (continue/recover/escalate/terminate), typed delegation contracts, externalized-verification loop, "deliberately boring general worker" posture. **None of this lives in the nexus.** |

### Dispatch Protocol Step-2 change (EIDOLONS.md:42 → new)

**Current:**
> No Eidolon scores ≥ 0.6: emit `clarification_request` with 1–3 targeted questions. Do not dispatch.

**Proposed:**
> No Eidolon scores ≥ 0.6:
> - **(a) actionable →** if the prompt is *actionable* (mechanical predicate: explicit objective present **AND** action verb present **AND** a discernible acceptance/stop signal **AND** no clean chain co-triggers), dispatch the **`generalist`** as a bounded-authority fallthrough worker, standard tier.
> - **(b) underspecified →** otherwise, emit `clarification_request` with 1–3 targeted questions (unchanged).
>
> Invariant: the generalist **never** participates in Step-1 scoring and **never** outranks a specialist that scores ≥ τ — it exists solely in branch (a). The (a)/(b) split MUST be mechanical (I-C2/I-C6), not LLM-discretionary.

### Measurement gate (per A14 precedent — Kupo pass³ / RAMZA non-inferior+holdout)

Two arms; **both must pass** before `status: shipped`:

1. **Capability-expansion arm.** Holdout of *actionable-but-unroutable* missions (mixed read+act, cross-class, no clean specialist/chain match — the exact prompts that today bounce to `clarification_request`). **Metric:** generalist completes-with-externally-verified-result vs the `clarification_request` baseline (which completes 0 — it bounces). **Pass:** generalist meaningfully covers missions the baseline cannot, with verification-passing results.
2. **No-over-capture arm (the MAST guard — mandatory).** Replay the *existing* routing corpus (specialist-matched prompts) with the generalist present. **Metric:** specialist routing precision/recall must be **non-inferior** — the Step-2(a) branch must *never* fire when a specialist scores ≥ τ. **Pass:** zero over-capture on the specialist corpus (or within a defined non-inferiority margin, matching RAMZA's "non-inferior + holdout-consistent, 0 MUST-fails" bar).

This gate is what converts the [GAP-freq] unknown into a certified `shipped` decision, and is why the verdict is safe to make at 77% now.

---

## Checker-handoff evaluation (`requires_checker`)

Scanned the recommended course of action against the five mechanical irreversibility triggers:

| # | Category | Match? |
|---|----------|--------|
| 1 | Deploy / release | **YES** — the course culminates in *releasing a new roster member + cutting a nexus version to publish it* (the eventual `shipped` flip). |
| 2 | Destructive migration / data deletion | No |
| 3 | Security-boundary change | No |
| 4 | External spend / commitment | No |
| 5 | Public communication / public contract change | **YES** — a new public roster member changes the published roster contract (README/MANIFESTO/roster/index). |

**`requires_checker: true`** — categories **1** and **5** fire.

`[CHECKER-REQUIRED]` — the immediate action (spec + in_construction build) is reversible, but the course it authorizes (ship a public roster member) is a release/public-contract change. It MUST NOT flow straight to `shipped`:
- **Checker-class hint → human** for the strategic go/no-go + naming (roster-shape judgment no evidence pass resolves; the maintainer explicitly owns this).
- **Checker-class hint → the measurement gate (maker≠checker, A14 precedent)** for the technical non-inferiority/expansion check before the `shipped` flip. FORGE's own Gate is self-review and is *not* sufficient authority to greenlight this release.

---

## Provenance
- **Decision type:** TRADE-OFF (constraint-gated)
- **Deliberation depth:** Deep score (9) run as standard single-trace — 2 passes + leader red-team; **self-consistency (G2) NOT used** per maintainer instruction
- **Evidence sources:** 4 (E1 mixed H/M, E2 H/M/L, E3 H primary-verified, E4 neutral)
- **Hypotheses evaluated:** 6 (A, B, C, D, E, F)
- **Confidence:** 77% (Evidence 72, Logic 78, Constraints 80, Sensitivity 78)
- **Gate result:** PASS (no REFORGE)
- **Markers:** 2 ASSUMPTION, 3 GAP, 4 RISK, 5 REVERSAL-CONDITION
- **Handoffs:** → RAMZA (spec the H-E change), → human/maintainer (go/no-go + naming), → ATLAS (follow-up: scout `Rynaro/eidolons-ecl`/`eidolons-eiis` to close GAP-001; probe host-slot wiring feasibility to close GAP-002)
- **`requires_checker`:** true (categories 1, 5)

*Reasoner — FORGE*
