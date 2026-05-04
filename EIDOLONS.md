<!-- eidolon:cortex start -->
# EIDOLONS.md — Routing Cortex

> Always-loaded routing cortex for the Eidolons nexus.
> A host LLM reading this file once at session start can route any
> free-form prompt to the correct Eidolon(s), at the correct tier,
> in the correct chain. No vendor model names appear here — capability
> classes only (speed-class, reasoning-class). See §DEEP for extended
> tables loaded on demand.

---

## Roster Index (always-loaded)

| Name | Capability class | Trigger verbs | Refuses | Hands off to |
|------|-----------------|---------------|---------|--------------|
| **ATLAS** | scout | map, trace, find where, who calls, build call graph, list entrypoints, audit (read-only) | implement, fix, edit, write, commit | SPECTRA, APIVR-Δ, IDG |
| **SPECTRA** | planner | spec, plan, decompose, clarify requirements, GIVEN/WHEN/THEN, decision-ready | implement code, modify files | APIVR-Δ, IDG |
| **APIVR-Δ** | coder | implement, build, fix, extend, wire up, make tests pass | design from scratch, novel architecture | IDG |
| **IDG** | scriber | document, ADR, runbook, chronicle, synthesize, record decisions | explore repo, find calls, retrieve | (terminal) |
| **FORGE** | reasoner | trade-off, which approach, ambiguous, counterfactual, deliberate | implement, retrieve, synthesize prose | (lateral consultant) |
| **VIGIL** | debugger | root cause, flaky, heisenbug, regression after X, post-mortem, why does this fail | build new feature, plan from scratch | (lateral specialist) |

---

## Dispatch Protocol (always-loaded)

**Step 1 — Classify.** Extract verbs from the prompt. Match against trigger columns above. Score each Eidolon 0–1.

**Step 2 — Gate.**
- Score ≥ 0.8 for one Eidolon and ≤ 1 verb class: dispatch that Eidolon, standard tier.
- Score ≥ 0.6 for ≥ 2 Eidolons OR prompt spans ≥ 2 capability classes: build a chain (see Chain Templates below).
- No Eidolon scores ≥ 0.6: emit `clarification_request` with 1–3 targeted questions. Do not dispatch.

**Step 3 — Refusal check.** If the top-scored Eidolon would refuse the prompt's intent (see Refuses column), set `refusal_rerouting: true`, select the capable peer, emit `[DECISION]` explaining the override.

**Step 4 — Tier.** Default is `standard`. Escalate to `elite` only when **both** hold: (a) complexity flags fire AND (b) user supplies explicit `ELITE` token or upstream Eidolon flags high-stakes. See ELITE Activation Gates below.

**Step 5 — Emit routing artifact.**
```
selected: [<eidolon>, ...]
tier: standard | elite
chain: [{eidolon, role, hand_off_artifact_path, edge_origin}, ...]
model_tier_per_step: [speed-class | reasoning-class, ...]
confidence: 0..1
assumptions: [...]       # [GAP]/[DISPUTED] when routing is ambiguous
clarification_request: <string?>
refusal_rerouting: <bool>
```

---

## Chain Templates (always-loaded)

| Template | Steps | When |
|----------|-------|------|
| **plan-before-build** | ATLAS → SPECTRA → APIVR-Δ → IDG | Unfamiliar code + multi-component change |
| **audit-without-touching** | ATLAS → IDG | "Audit", "explain", "review" with no write intent |
| **ship-fast** | SPECTRA → APIVR-Δ | Known terrain, scoped feature |
| **direct-implementation-bypass** | ATLAS → APIVR-Δ (skip SPECTRA) | Complexity < 7/12 AND small surface AND unambiguous reqs; emit `[DECISION]` |
| **decide-then-implement** | FORGE → SPECTRA → APIVR-Δ | "Should we use X or Y, then build it" |
| **forensic-then-fix** | VIGIL → APIVR-Δ | Bug with reproduction + verified patch suggestion |
| **failed-attempt-recovery** | (prior APIVR-Δ failure) → VIGIL → APIVR-Δ | Conversation shows prior APIVR-Δ Reflect-exhaustion |
| **decision-only** | FORGE | No code touching; deliberation emitting verdict + assumptions |

---

## ELITE Activation Gates (always-loaded)

ELITE grants: parallel fan-out (max 5 branches), worktree isolation per branch, verifier-cascade wrapping, evaluator-optimizer loop (cap 3 iterations), model-tier upgrade (lead = reasoning-class, workers = speed-class).

ELITE is **never** the default. Auto-trigger requires **both** a complexity flag AND a stakes flag. Cost warning emitted at ≥ 5× standard-tier budget.

| Gate | Eidolon | Condition |
|------|---------|-----------|
| G1 — Discovery scatter | ATLAS | Surface > 25 files OR > 5 modules → scatter sub-agents per module, aggregate via Abstract phase |
| G2 — Hard-decision consistency | FORGE | ≥ 3 plausible alternatives AND (high-stakes flag OR explicit ELITE token) → N=3 reasoning traces, majority-vote |
| G3 — Spec evaluator-optimizer | SPECTRA | Complexity ≥ 7/12 AND (high-stakes OR ambiguous reqs) → generator + evaluator, max 3 iterations |
| G4 — Parallel implementation | APIVR-Δ | SPECTRA emitted > 1 independent story AND budget bounded → one APIVR-Δ per track, worktree isolation |
| G5 — Doc parallel synthesis | IDG | Large source artifact set AND topological order allows parallelism → per-section parallel, CHT per section, one-revision cap preserved |
| G6 — Forensic counterfactuals | VIGIL | ≥ 2 plausible root-cause hypotheses AND bisect surface allows independent testing → parallel hypothesis tests on isolated bisects |

**ELITE refusals (immutable):** A refused capability does not become available at ELITE. ATLAS still does not write. SPECTRA still does not implement. IDG still does not retrieve. FORGE still does not tool-call. VIGIL still does not auto-apply patches. Per-Eidolon retry budgets remain enforced inside ELITE.

---

## Confidence Signals (always-loaded)

| Signal | Effect | Target |
|--------|--------|--------|
| Stack trace, panic, "still failing after retry" | +0.3 | VIGIL |
| Surface > 25 files or 5 modules | +0.2 | ATLAS-ELITE |
| "Greenfield", "from scratch", "novel" | −0.3 | APIVR-Δ (it refuses greenfield) |
| "I don't have a spec yet" | +0.2 | SPECTRA |
| Prior failed APIVR-Δ attempt in conversation | +0.4 | VIGIL |
| Eidolon named explicitly in prompt | +0.5 | that Eidolon (still check refusal table) |
| Multiple SDLC phases ("scout and spec and build") | chain trigger | (see Chain Templates) |

---

## Invariants

- **I-C1** — Marker-bounded sections when embedding into shared host files (`<!-- eidolon:cortex start/end -->`).
- **I-C2** — No `eval` of routing rules; descriptor table is data, dispatch is interpretive.
- **I-C3** — Capability classes only: `speed-class`, `reasoning-class`. Never vendor names.
- **I-C4** — Always-loaded section ≤ 900 tokens; deep tables in `methodology/cortex/`.
- **I-C5** — Refusals are immutable; cortex must never request a refused capability of a target Eidolon.
- **I-C6** — Same prompt + same context + same roster ⇒ same routing decision.
- **I-C7** — `roster/index.yaml` is the source of truth; new Eidolons auto-appear, removed Eidolons disappear.
- **I-C8** — `[GAP]` and `[DISPUTED]` over silent merge when routing is genuinely ambiguous.
- **I-C9** — Bash 3.2 compatibility for any CLI helper consuming a cortex artifact.
- **I-C10** — Stderr discipline for all tooling logs; stdout reserved for captured values.

---

*Deep tables (ELITE matrix, hand-off graph, disambiguation table, validation gates, open questions) load on demand from `methodology/cortex/`. See `methodology/cortex/README.md`.*

<!-- eidolon:cortex end -->
