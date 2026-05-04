# EIDOLONS.md Cortex — Specification

> SPECTRA-cycle output for the central cortex document. **This is the spec
> for `EIDOLONS.md`, not `EIDOLONS.md` itself.** A downstream implementer
> (recommended: APIVR-Δ) drafts the artifact against the rubrics, gates,
> and stories below.
>
> Inputs consumed:
> - `/Users/henrique/workspace/oss/agents/eidolons/.spectra/research/eidolons-cortex-research-dossier.md` (D)
> - `/Users/henrique/workspace/oss/agents/eidolons/.spectra/research/eidolons-cortex-foundation.md` (F)
> - `CLAUDE.md`, `MANIFESTO.md`, `methodology/prime-directives.md` (repo)
>
> Citations use the keys `[D §x.y]` for dossier and `[F §x]` for foundation.

---

## 1. Mission Statement

`EIDOLONS.md` is the **always-loaded routing cortex** for the Eidolons
nexus. It closes the routing gap identified in `[F §5]`: today
`cli/eidolons` is a string dispatcher that assumes the user already knows
which Eidolon to call (`cli/eidolons:84-133`), so any free-form
natural-language prompt arriving through Claude Code, Cursor, OpenCode, or
the API has no semantic dispatch path. `EIDOLONS.md` adds that path —
without replacing the deterministic name-match — by publishing the
fixed-roster descriptor table and an explicit decision protocol that maps
an arbitrary prompt to one or more Eidolons, a tier (standard or TRANCE),
and a hand-off chain. **Success** means: (a) a host LLM reading
`EIDOLONS.md` once at session start can route a free-form prompt to the
correct Eidolon(s) at the correct tier with the correct chain, (b) TRANCE
escalation is gated, audited, and refusable rather than always-on, and
(c) the cortex itself fits the working-set budget the manifesto refuses
to bloat (`MANIFESTO.md:39`, D1 `≤3500` tokens for specialists).

---

## 2. Scope & Non-Scope

### In scope
- A descriptor table for all six roster members (ATLAS, SPECTRA,
  APIVR-Δ, IDG, FORGE, VIGIL) suitable for soft-matching by a host LLM.
- A scoring rubric mapping prompt features → eidolon(s) and confidence.
- A definition of the TRANCE tier — what it grants, when it activates,
  when it must refuse to activate, and how cost is bounded.
- The canonical hand-off graph the cortex assumes when composing chains,
  including resolution of the disagreement flagged in `[F §4]`.
- GIVEN/WHEN/THEN validation gates the eventual `EIDOLONS.md` must pass.
- Cortex-level invariants that extend `[F §9]`.

### Out of scope (explicit)
- **Replacing `cli/eidolons` deterministic dispatch.** When a user types
  `eidolons atlas scout`, the existing string-match path in
  `cli/src/dispatch_eidolon.sh` runs unchanged. The cortex augments only
  the free-form prompt arriving through a host conversation.
- **Per-Eidolon methodology content.** Each Eidolon's full methodology
  stays in its own repo (`CLAUDE.md` "Notes on scope"); the cortex
  references descriptors only.
- **Trained ML routers.** `[D §3.2]` recommends a calibrated classifier
  in production; this spec uses LLM-self-routing against descriptors as
  the v1 mechanism, with a placeholder for a learned router later (see
  §10 OQ-1).
- **Persisting routing memory across sessions in v1.** `[D §6]` open
  question on memory-across-routers; v1 is stateless, audited via
  structured artifact only.
- **Modifying `roster/index.yaml` schema.** The cortex consumes roster
  data; schema changes are a separate work item (see §10 OQ-3).

---

## 3. Design Principles

| # | Principle | Why (cited) | Trade-off accepted |
|---|---|---|---|
| P1 | Routing is a calibrated classifier with a tunable threshold, not LLM-as-judge. | RouteLLM ICLR 2025 `[D §2 #1]`; Hybrid-LLM ICLR 2024 `[D §2 #2]`; RouterArena `[D bib]`. 30-85% cost cut at matched quality. | v1 has no trained classifier — we approximate with descriptor-soft-matching plus an explicit confidence threshold τ. Migrate later (OQ-1). |
| P2 | Heterogeneity is preserved by exposing every Eidolon distinctly. | X-MAS `[D §2 #6]`; Stop-Overvaluing-MAD NeurIPS 2025 `[D §2 #6]`. 8-47% lift comes from distinct methodologies, not from debate. | Six descriptors, six refusal lists. The cortex never collapses two Eidolons into one role. Cost: ~600 always-loaded tokens vs a generic mega-prompt's ~5000. |
| P3 | Descriptors follow progressive disclosure. | Anthropic Agent Skills (Oct 2025) `[D §3.1]`; Skill survey `[D §2 #22]`. ≤100-tok metadata in system prompt, body loaded on trigger. | Cortex stays under D1's 3500-token specialist budget (`prime-directives.md:27`); deep methodology is not duplicated here. |
| P4 | TRANCE = parallel fan-out + isolation + verifier wrapping, not "longer thinking." | Anthropic multi-agent research-system blog (90.2% lift, ~15× tokens) `[D §3.4]`; Revisiting o1 ACL 2025 (longer CoT often degrades) `[D §2 #18]`; o1 / s1 (parallel > sequential) `[D §2 #17]`. | TRANCE costs ~15× tokens; we cap blast-radius via budget gates (§6). Pure self-revision rejected as the TRANCE primitive. |
| P5 | Confidence-gated escalation, not always-on TRANCE. | Self-Consistency `[D §2 #8]`; Self-Refine `[D §2 #9]`; Reflexion `[D §2 #10]`; Ask-or-Assume `[D §2 #19]` (61.2 → 69.4% resolve rate via clarification). | TRANCE auto-trigger lives behind a complexity-score gate; the user can also opt-in. Mis-routed cheap dispatch is preferred to over-spending on a simple prompt. |
| P6 | Refusals are routing signals, not stops. | `[F §9 invariant 5]`; D2 (`prime-directives.md:34`). ATLAS-won't-write, SPECTRA-won't-implement, etc. | If a target Eidolon would refuse, the cortex must re-route to a peer that can act. One extra reasoning step on the cortex's side; never bypasses the refusal. |
| P7 | Hand-off contracts are structured artifacts on disk, not chat threads. | `[F §9 invariant 4]`; `methodology/composition.md:54-58`; Plan-and-Act ICML 2025 `[D §2 #13]`. | Cortex chains are emitted as a structured plan (markers + paths), not as conversational hand-waving. |
| P8 | Heterogeneous models per role at TRANCE. | X-MAS `[D §2 #6]`; Anthropic research blog (Opus lead + Sonnet workers) `[D §3.4]`; APIVR memory feedback (sonnet pinned) `[F §1]`. | Cortex emits **capability-class tiers**, never vendor names (D9, `prime-directives.md:152-162`). Translation to specific models is a host-config concern. |
| P9 | Reflexion-style memory is opt-in and bounded. | Reflexion NeurIPS 2023 `[D §2 #10]`; APIVR `apivr-memory-management/SKILL.md:16-23,141`. | v1 emits routing-decision artifacts but does not consume past decisions. Stateless cortex is reproducible; learned cortex is OQ-9. |
| P10 | The cortex itself respects D1, D2, D9, D10 — it is not a new monolith. | `prime-directives.md:9-46,152-188`; `MANIFESTO.md:39`. | Always-loaded section ≤900 tokens; deep tables in collapsible/anchored sections; no vendor names; reads-only summary of refusals it cannot override. |

---

## 4. Cortex Architecture

### 4.1 Inputs

1. **Prompt text** (the user's free-form natural-language utterance).
2. **Conversation context** (prior turns; whether an Eidolon has already
   acted; whether prior attempts failed — relevant for VIGIL gating).
3. **Host environment signals** — presence of `CLAUDE.md`, `AGENTS.md`,
   `.cursor/rules/`, `.opencode/agents/` (`cli/src/lib.sh` `detect_hosts`).
4. **Roster availability** — `eidolons.lock` and `./.eidolons/<name>/`
   presence determine which members are installed (`[F §6]`;
   `methodology/composition.md:86-107`).
5. **User-supplied tier hint** (optional) — explicit `TRANCE` token in the
   prompt or a project-level config flag (see §6.4).

### 4.2 Output

A **routing decision artifact** (structured, parseable) containing:

- `selected: [<eidolon>, …]` — ordered list of Eidolons to invoke.
- `tier: standard | trance` — capability tier.
- `chain: [<step>, …]` — each step is `{eidolon, role, hand_off_artifact_path}`.
- `model_tier_per_step: [<capability_class>, …]` — speed-class /
  reasoning-class only; never vendor names (P8, D9).
- `confidence: 0..1` — cortex's own self-reported confidence.
- `assumptions: [...]` — `[GAP]` / `[DISPUTED]` / explicit assumption markers
  (D7) when routing is ambiguous.
- `clarification_request: <string?>` — populated only when confidence < τ
  AND the prompt is recoverable via 1-3 questions (`[D §3.5]`).
- `refusal_rerouting: <bool>` — true when the cortex re-routed to avoid a
  declared refusal (P6).

### 4.3 Internal stages

| # | Stage | Input | Output | Signal source | Failure mode |
|---|---|---|---|---|---|
| S1 | **Classify** | prompt + context | feature vector: verbs, surface size hints, prior-attempt flag, refusal trigger flags | `[F §3]` verb taxonomy; descriptor `triggers` / `refuses`; conversation history | All-zero feature vector → S5 emits CLARIFY |
| S2 | **Score** | feature vector + descriptors | `score[eidolon] ∈ [0,1]` for each of 6 members | LLM soft-match against descriptor name+description+triggers (P3); structural overlap of trigger keywords | All scores < τ → S5 CLARIFY or fallback to FORGE for routing-decision (`[D §3.1]`) |
| S3 | **Tier-Select** | top-K scores, complexity heuristics, user hint | `tier ∈ {standard, trance}` | Complexity rubric (§6.2); explicit user `TRANCE` token; surface-size hint; prior-attempt failure (→ VIGIL) | Insufficient signal → default `standard`; never default `trance` (P5) |
| S4 | **Plan (Compose Chain)** | top-K + tier | ordered chain with hand-off contracts | Hand-off graph (§7.1); chain templates (§7.3); refusal table (§5.4) | Cycle detected → break with `[BLOCKED]` and emit `clarification_request` |
| S5 | **Emit** | full decision | routing artifact (§4.2) | Output schema; D7 markers | Schema-invalid → re-emit once; second failure → `[BLOCKED]` |

### 4.4 Architecture pattern chosen

**Hierarchical supervisor with two-stage hybrid dispatch** (`[D §4]`).

- **Stage 1**: Descriptor-based supervisor. The host LLM reads
  `EIDOLONS.md` (always loaded), soft-matches the prompt against the
  six descriptors, and produces a top-K with confidence per Eidolon.
  Backed by Anthropic Skills (`[D §3.1]`) and the LangGraph supervisor
  consensus pattern (`[D §2 #20]`).
- **Stage 2**: Confidence gate + TRANCE escalation. If
  `top_score ≥ τ_trance` AND complexity flags fire AND budget is
  available, escalate to TRANCE (§6). Otherwise dispatch standard or
  trigger CLARIFY (`[D §3.5]`).

**Patterns rejected (with reason):**

- **Single-router (one-shot classifier):** insufficient — `[D §4]` notes
  "no correction once dispatched." We need the relay capability.
- **Cascade/escalation by strength:** wrong shape — Eidolons differ in
  *role*, not *strength* (`[D §4]`); a "weaker" ATLAS is not a
  smaller-budget APIVR-Δ.
- **Mixture-of-Agents aggregation as default:** ~N× cost; reserved for
  TRANCE on hard queries only (`[D §3.4]`).
- **Multi-agent debate:** `[D §2 #6]` shows it underperforms
  self-consistency at equal cost without heterogeneity. Available only
  as an opt-in FORGE-TRANCE add-on.

---

## 5. Trigger Taxonomy & Routing Rules

### 5.1 Per-Eidolon descriptor schema

The eventual `EIDOLONS.md` must publish a descriptor row for each
Eidolon with these fields (`[D §2 #22]` SkillRouter / Skill survey
schema; foundation `[F §1]` field set):

```
name | capability_class | trigger_verbs | anti_triggers (refuses) |
confidence_boost_signals | confidence_penalty_signals |
hands_off_to | refused_capabilities | working_set_token_budget
```

`capability_class` and `model_tier` use **capability class names only**
(reasoning-class, speed-class) per D9 (`prime-directives.md:152-162`).

### 5.2 Trigger / anti-trigger table (binding source)

Pulled from `[F §3]` verb taxonomy. Eventual `EIDOLONS.md` may rephrase
but **must not introduce verbs absent from a skill card or roster
summary** (per `[F §3]` note that IDG/FORGE/VIGIL skill cards are not in
the local checkout — verbs come from `methodology/composition.md` and
roster summaries; this is acceptable until those skill cards land —
tracked in OQ-12).

| Eidolon | Trigger verbs (boost) | Anti-triggers (penalty / refuse) |
|---|---|---|
| ATLAS | "map", "trace", "find where", "who calls/writes", "build call graph", "list entrypoints", "audit (read-only)" `[F §3 row 1]` | "implement", "fix", "deploy", "edit" — refuses to write `prime-directives.md:43` |
| SPECTRA | "spec", "plan", "decompose", "clarify", "GIVEN/WHEN/THEN", "decision-ready" `[F §3 row 2]` | "implement now", "modify file" — refuses to code `prime-directives.md:42` |
| APIVR-Δ | "implement", "build", "fix", "extend", "wire up", "make tests pass" `[F §3 row 3]` | "design from scratch", "novel architecture" — refuses greenfield `prime-directives.md:41` |
| IDG | "document", "ADR", "runbook", "chronicle", "synthesize", "record decisions" `[F §3 row 4]` | "explore the repo", "find calls" — refuses retrieval `prime-directives.md:43`, `roster/index.yaml:204-208` |
| FORGE | "trade-off", "which approach", "ambiguous", "counterfactual", "deliberate" `[F §3 row 5]` | "implement", "retrieve", "synthesize prose" — refuses tools `prime-directives.md:44` |
| VIGIL | "root cause", "flaky", "heisenbug", "regression after X", "post-mortem", "why does this fail" `[F §3 row 6]` | "build new feature", "plan from scratch" — refuses non-forensic work `[F §1 row 6]` |

### 5.3 Confidence-boost / penalty signals

| Signal | Direction | Target Eidolon |
|---|---|---|
| Stack trace, panic, traceback, "still failing after retry" in prompt | +0.3 | VIGIL |
| Surface size > N files (heuristic; user-mentioned or implied) | +0.2 | ATLAS-TRANCE |
| "Greenfield", "from scratch", "novel" | -0.3 | APIVR-Δ (it refuses) |
| "Just write it", complexity score < 4/12 | -0.2 | SPECTRA |
| "I don't have a spec yet" | +0.2 | SPECTRA |
| Conversation contains a prior failed APIVR-Δ attempt | +0.4 | VIGIL |
| Prompt names an Eidolon explicitly | +0.5 | that Eidolon (cortex must still check refusal table §5.4) |
| Prompt references multiple SDLC phases ("scout and spec and build") | trigger-chain | (see §7.3 chain templates) |

### 5.4 Disambiguation table (known-ambiguous cases)

| Prompt class | Default route | Override condition |
|---|---|---|
| "Fix the bug" | APIVR-Δ standard | Prior attempt failed in this conversation OR stack trace + "flaky" → VIGIL |
| "Design X" | SPECTRA standard | Prompt also asks to write code → SPECTRA → APIVR-Δ chain |
| "Find and fix" | ATLAS → APIVR-Δ direct (`roster/index.yaml:60` allows this skip) | Surface > complexity threshold OR "unclear requirements" → ATLAS → SPECTRA → APIVR-Δ |
| "Document this" | IDG | Prior artifact missing on disk → re-route to ATLAS first (IDG refuses retrieval `prime-directives.md:43`) |
| "Should we use X or Y?" | FORGE | Decision is also implementable → FORGE → SPECTRA chain |
| "Audit the auth flow" | ATLAS standard | Auditor wants written narrative → ATLAS → IDG (`MANIFESTO.md:79`) |
| "Write a runbook" with no source artifacts | CLARIFY (IDG cannot retrieve) | User provides artifacts → IDG |

---

## 6. TRANCE Tier Specification

### 6.1 What TRANCE means (capabilities granted)

| Capability | Mechanism | Source |
|---|---|---|
| Parallel fan-out to N sub-invocations | Tool-call concurrency (Claude Code; AutoGen; LangGraph) | `[D §3.4]`; `[F §7]` |
| Worktree / context isolation per parallel branch | `isolation: "worktree"` per agent | `[D §5 row 2]`; `[F §7]`; user memory `feedback_parallel_agents_same_repo` |
| Verifier-cascade wrapping | Generator → step-level verifier → emit (PRM / Math-Shepherd) | `[D §2 #14]` |
| Evaluator-optimizer loop, capped at 3 iterations | Generator + evaluator + termination gate | `[D §3.7]` |
| Model-tier upgrade per step | Capability-class override (lead = reasoning-class, workers = speed-class) | `[D §3.4]`; D9 |
| Self-consistency on reasoning chains (FORGE only) | N=3 standard TRANCE, N=5 high-stakes; majority-vote / judge-merge | `[D §3.6]` |
| Reflexion-style routing-decision artifacts | Structured emit per turn | `[D §3.8]` (memory propagation is opt-in v2) |

TRANCE is **not**: longer single-thread thinking, unbounded loops, or
arbitrary new tool surfaces. `[D §2 #18]` (Revisiting o1) explicitly
warns against this.

### 6.2 Activation gates (GIVEN / WHEN / THEN)

Each gate must hold **all** GIVEN clauses for the WHEN to apply.

- **G1 — Discovery scatter (ATLAS-TRANCE).**
  GIVEN a discovery prompt over a repo where the prompt or detected
  surface implies > N files (cortex heuristic; see §6.4 C5)
  WHEN the cortex selects ATLAS at standard tier
  THEN escalate to TRANCE: scatter parallel sub-agents per module/path,
  isolation `worktree`, then aggregate via ATLAS Abstract phase
  (`atlas-abstract/SKILL.md:34-138`).

- **G2 — Hard-decision self-consistency (FORGE-TRANCE).**
  GIVEN a FORGE invocation flagged "high-stakes" by upstream Eidolon OR
  an explicit user `TRANCE` token
  WHEN the decision space has ≥3 plausible alternatives
  THEN sample N=3 reasoning traces (N=5 if user marks high-stakes),
  majority-vote or judge-merge; if consensus < 60% emit `no decision`
  with sampled disagreements (`[D §3.6]`).

- **G3 — Spec evaluator-optimizer (SPECTRA-TRANCE).**
  GIVEN SPECTRA at complexity ≥7/12 (`spectra-planning/SKILL.md:14`)
  WHEN the user has signaled high-stakes OR the upstream Eidolon flagged
  ambiguous requirements
  THEN run generator + evaluator loop, max 3 iterations
  (`[D §3.7]`); on 3rd failure escalate to FORGE.

- **G4 — Parallel implementation (APIVR-Δ-TRANCE).**
  GIVEN a multi-track feature where SPECTRA emitted >1 independent story
  WHEN total verifier cost is bounded
  THEN spawn one APIVR-Δ per track with `isolation: "worktree"`; merge
  via the verifier cascade; preserve APIVR's existing 3-attempt budget
  per track (`apivr-failure-recovery/SKILL.md:154-210`).

- **G5 — Doc parallel synthesis (IDG-TRANCE).**
  GIVEN an IDG synthesis where the source artifact set is large
  (multiple inputs / multiple sections)
  WHEN the topological order from `idg-composition/SKILL.md:7-22` allows
  parallelization (sections without inter-section dependency)
  THEN synthesize per-section in parallel; combine via the standard CHT
  verification (`idg-verification/SKILL.md:69-86`); the **one-revision
  cap** (`idg-verification/SKILL.md:85`) is preserved per section.

- **G6 — Forensic counterfactuals (VIGIL-TRANCE).**
  GIVEN a VIGIL invocation with ≥2 plausible root-cause hypotheses
  WHEN bisect surface allows independent testing
  THEN spawn parallel hypothesis tests on isolated bisects (worktree
  isolation); merge into a single `root-cause-report.md` (`roster/index.yaml:298`).

### 6.3 Refusal gates (when TRANCE MUST NOT activate)

- **R1 — Refusal-bound capabilities.** A refused capability does not
  become available at TRANCE. ATLAS still does not write at TRANCE.
  SPECTRA still does not implement. IDG still does not retrieve. FORGE
  still does not tool-call. VIGIL still does not auto-apply patches
  (`[F §9 invariant 5]`; `prime-directives.md:38-46`; `roster/index.yaml:298`).
- **R2 — FORGE parallel fan-out is reasoning-only.** FORGE's TRANCE is
  self-consistency on reasoning chains; it does not gain tool access.
  Direct corollary of `prime-directives.md:44`.
- **R3 — Bounded budgets are inviolable.** Per-Eidolon retry budgets
  remain enforced inside TRANCE (`[F §9 invariant 11]`). TRANCE adds
  parallelism, not a fresh budget.
- **R4 — D5 unbounded reflection.** TRANCE may not extend reflection
  loops past published caps (SPECTRA 3 cycles, IDG 1 revision, APIVR
  ≤3 same-category attempts). `[D §2 #18]` evidence + D5
  (`prime-directives.md:82-91`).
- **R5 — Partial-team deployment.** If a needed Eidolon is not
  installed (`eidolons.lock` check), TRANCE is degraded: cortex emits a
  `[GAP]` and a fallback chain rather than spawning fan-out into a
  member that doesn't exist (`composition.md:86-107`).

### 6.4 Cost ceiling rules

The dossier flags TRANCE-always vs TRANCE-on-demand as unresolved
(`[D §6 row 1]`). v1 chooses **TRANCE-on-demand** with explicit caps:

- **C1 — Max parallel branches per TRANCE invocation: 5** (Anthropic
  empirical sweet spot for orchestrator-workers `[D §3.4]`; "complex =
  10+ agents" reserved for nested supervisors, not v1 cortex).
- **C2 — Max model-tier upgrade: lead = reasoning-class, workers =
  speed-class.** Mirrors Anthropic research-system topology
  (`[D §3.4]`). Vendor names never appear in cortex output (D9).
- **C3 — Max wall-clock: bounded by host harness.** Cortex emits a
  `wall_clock_budget_seconds` hint; if absent, the host enforces its
  default. Cortex never spins indefinite background jobs without
  user opt-in.
- **C4 — Token budget warning at 5× standard.** If projected cost ≥5×
  the standard-tier budget, cortex emits a `[DECISION]` marker
  surfacing the tradeoff so the user (or a calling agent) can consent.
  Anthropic's 15× lift number is the upper bound, not the default.
- **C5 — Surface-size thresholds.** "Large surface" in §6.2 G1 is
  defined as `> 25 files` OR `> 5 modules` (heuristic; configurable).
  Below threshold, ATLAS standard tier suffices.
- **C6 — Auto-trigger requires both a complexity flag AND a stakes
  flag.** Either alone keeps the cortex at standard tier (P5).

### 6.5 Per-Eidolon TRANCE matrix

| Eidolon | TRANCE form | Granted | Forbidden at TRANCE |
|---|---|---|---|
| ATLAS | Scatter sub-agents per module | Parallel fan-out (G1); worktree isolation; Abstract-phase aggregation | Writing, editing — D2 refusal stands (R1) |
| SPECTRA | Evaluator-optimizer loop on draft spec | Generator + evaluator + termination gate (G3); cap 3 iterations | Implementing code (R1); >3 cycles (R4) |
| APIVR-Δ | Parallel feature branches in worktrees + verifier cascade | Multi-track implementation (G4); per-track verifier; reflection memory still bounded ≤3 retries | Re-attempting beyond category budget (R3); writing in shared tree without `isolation: worktree` |
| IDG | Parallel doc-section synthesis | Per-section parallelism with topological respect (G5); CHT verification per section | Retrieval (R1); >1 revision per section (R4) |
| FORGE | Self-consistency on reasoning chains | N=3 (or N=5) sampled traces with majority-vote / judge-merge (G2) | Tool calls, retrieval, code emission (R2); debate without heterogeneity (`[D §2 #6]`) |
| VIGIL | Parallel hypothesis testing on isolated bisects | Counterfactual fan-out on worktrees (G6); 5-intervention budget preserved | Auto-apply patches (R1, `roster/index.yaml:298`); writing outside `verified-patch.diff` |

---

## 7. Hand-off & Composition Protocol

### 7.1 Canonical hand-off graph (cortex's authoritative view)

The foundation flagged a disagreement between `roster/index.yaml`
declared edges and `methodology/composition.md` prose-described edges
(`[F §4]` "Gaps in the declared graph"). The cortex resolves this by
adopting **the union as the routable set, with origin labels**:

```
ATLAS  ──(roster:downstream)──▶  SPECTRA
ATLAS  ──(roster:downstream)──▶  APIVR-Δ        # documented bypass
SPECTRA ──(roster:downstream)──▶ APIVR-Δ
APIVR-Δ ──(roster:downstream)──▶ IDG
SPECTRA ──(composition.md)────▶  IDG            # plan-only docs
ATLAS  ──(composition.md)────▶  IDG            # read-only audits
VIGIL  ──(composition.md:49-51)▶ SPECTRA / IDG / FORGE  # not in roster yet
FORGE  ──(composition.md:67-68) ▶ <any caller>  # consultation return
ANY    ──(any)──▶  human                        # implicit terminal
```

The resolution is **explicit in the cortex output**: every chain step
records `edge_origin: "roster" | "composition" | "implicit"`. This
preserves D7 `[DISPUTED]` discipline (`prime-directives.md:117-118`).

It also **schedules a follow-up roster work-item** (§10 OQ-3) to
reconcile `roster/index.yaml` with `composition.md` so the two sources
agree.

### 7.2 Detecting when a chain is needed

Trigger a chain (multi-Eidolon dispatch) when **any** holds:

- The prompt's verb set spans ≥2 capability classes (`[F §3]`).
- A target Eidolon would refuse the prompt's later sub-task (P6, R1).
- Confidence top-1 < 0.8 AND top-2 ≥ 0.6 (genuine ambiguity → consult
  + relay rather than guess; `[D §3.5]`).
- An explicit chain template matches (§7.3).

### 7.3 Chain templates (canonical)

These are first-class patterns the cortex emits when matched. Each is
justified by `MANIFESTO.md:78-82` and `methodology/composition.md`.

| Template | Steps | When to use |
|---|---|---|
| **Plan-before-build** | ATLAS → SPECTRA → APIVR-Δ → IDG | Unfamiliar code + multi-component change. Manifesto §"What you can do" row 1. |
| **Audit-without-touching** | ATLAS → IDG | "Audit", "explain", "review" with no write intent. Preset `research`. |
| **Ship-fast** | SPECTRA → APIVR-Δ | Known terrain, scoped feature. Preset `plan-and-build`. |
| **Direct-implementation-bypass** | ATLAS → APIVR-Δ (skip SPECTRA) | `roster/index.yaml:60` permits when complexity < 7/12 AND surface is small AND requirements are unambiguous. Cortex must record bypass justification (D7 `[DECISION]`). |
| **Decide-then-implement** | FORGE → SPECTRA → APIVR-Δ | "Should we use X or Y, then build it." |
| **Forensic-then-fix** | VIGIL → APIVR-Δ | Bug with reproduction + verified patch suggestion (`roster/index.yaml:298` — VIGIL emits `verified-patch.diff` but never auto-applies). |
| **Failed-attempt-recovery** | (prior APIVR-Δ failure) → VIGIL → APIVR-Δ | `apivr-failure-recovery/SKILL.md:14-27` Evidence Gate; conversation history shows the prior attempt. |
| **Decision-only** | FORGE | No code touching; deliberation that emits a verdict + assumptions + confidence (`composition.md:60-69`). |

### 7.4 Hand-off contract enforcement

Each chain step writes to a **structured artifact on disk** under the
producer's own scope (`.atlas/`, `.spectra/`, `.apivr/`, `.idg/`, etc.,
per `[F §9 invariant 4]`; `composition.md:54-58`). The cortex emits the
expected artifact path; the consuming Eidolon parses structured data,
not chat prose.

---

## 8. Validation Gates (SPECTRA-native GIVEN/WHEN/THEN)

The eventual `EIDOLONS.md` MUST satisfy all 14 scenarios. Each is the
acceptance criterion for one routing class.

### V1 — Pure-discovery prompt
GIVEN the prompt "map the auth flow"
WHEN no prior Eidolon has acted in this conversation AND surface size is unknown / small
THEN the cortex routes to ATLAS standard tier; no chain; emit confidence ≥ 0.8.

### V2 — Discovery over large surface (TRANCE scatter)
GIVEN the prompt "map the entire monorepo's data layer"
WHEN cortex heuristic estimates surface > 25 files OR > 5 modules
THEN escalate to ATLAS-TRANCE; scatter sub-agents per module with `isolation: worktree`; aggregate via Abstract phase (G1). Emit `[DECISION]` recording the threshold trip.

### V3 — Spec-needs-research chain
GIVEN the prompt "I need a spec for refactoring the dispatcher; I don't know the call graph yet"
WHEN both discovery verbs and spec verbs co-occur
THEN emit chain ATLAS → SPECTRA; standard tier per step; record `edge_origin: roster`; hand-off artifact = `scout-report.md`.

### V4 — Brownfield bug fix (standard)
GIVEN the prompt "Fix the off-by-one in `flowmap_resolve`"
WHEN no prior failed attempt in conversation AND no stack-trace markers
THEN APIVR-Δ standard; chain length 1; bounded retry budget per `apivr-failure-recovery/SKILL.md:154-210`.

### V5 — Brownfield bug fix, second attempt → VIGIL
GIVEN the conversation contains a prior APIVR-Δ Reflect-exhaustion in this turn
WHEN the user re-prompts the same fix
THEN re-route to VIGIL (`[F §3 row 6]`; `composition.md:46-48`); emit `[DECISION]` citing the failure-recovery skill.

### V6 — Hard architectural decision, no code (FORGE)
GIVEN the prompt "Should we route via the hierarchical supervisor or a single-router for our 6-Eidolon roster?"
WHEN the prompt has decision verbs and no implementation verbs
THEN FORGE standard; chain length 1; output is verdict + assumptions + alternatives (`composition.md:60-69`); no downstream chain.

### V7 — Documentation synthesis from multiple sources (IDG-TRANCE)
GIVEN the prompt "Write the ADR set covering all six methodology docs"
WHEN source artifact set ≥ N sections AND IDG topological order permits parallelism
THEN IDG-TRANCE (G5); per-section parallel synthesis; CHT verification per section; one-revision cap preserved.

### V8 — Ambiguous "design and implement X" (chain)
GIVEN the prompt "Design and implement the `--json` flag for `eidolons doctor`"
WHEN both design and implement verbs co-occur
THEN chain SPECTRA → APIVR-Δ; complexity scored against `spectra-planning/SKILL.md:14-19` (≤7/12 may bypass to direct APIVR-Δ — see V14).

### V9 — Stack trace + repeat failure → VIGIL fast-path
GIVEN a prompt containing a stack trace or "still failing after retry"
WHEN no prior VIGIL invocation
THEN VIGIL standard; bypass APIVR-Δ first-attempt path; record reason `confidence_boost: stack_trace_signal` (§5.3).

### V10 — Free-form natural-language prompt with no Eidolon name (the headline case)
GIVEN the prompt "make sense of this codebase and propose a refactor plan"
WHEN no Eidolon name is in the prompt AND no host environment hint
THEN cortex routes via descriptor soft-match: ATLAS → SPECTRA chain; emit confidence and surface assumptions; this is the `[F §5]` gap explicitly closed.

### V11 — Refused capability re-routes
GIVEN the prompt "ATLAS, please patch this file"
WHEN the named Eidolon would refuse (P6; ATLAS write refusal)
THEN cortex sets `refusal_rerouting: true`; selects APIVR-Δ instead; emits `[DECISION]` explaining the override; never asks ATLAS to write.

### V12 — Abstain / clarify rather than guess
GIVEN the prompt "do the thing"
WHEN no eidolon scores ≥ τ AND no chain template matches
THEN emit `clarification_request` with 1-3 questions (`[D §3.5]`); do not dispatch; cap clarifications at 1 turn (Claude Code pattern).

### V13 — TRANCE cost ceiling enforcement
GIVEN a prompt that would otherwise spawn 8 parallel branches
WHEN C1 (`max_parallel = 5`) would be exceeded
THEN cortex declines unbounded fan-out; emits `[DECISION]` citing C1 with the proposed alternative (sequenced batches of 5); awaits user consent OR proceeds at the cap with an `[ACTION]` flag.

### V14 — Direct-implementation bypass with justification
GIVEN the prompt "add a `--json` flag to `eidolons doctor`" (V8 contrasted)
WHEN complexity < 7/12 AND surface is small AND ATLAS handoff allowed (`roster/index.yaml:60`)
THEN ATLAS → APIVR-Δ direct; skip SPECTRA; cortex emits `[DECISION]` with the bypass justification (this closes the `[F §6]` gap).

---

## 9. Invariants & Non-Negotiables

The cortex preserves all of `[F §9]` invariants 1-15 verbatim, plus the
following cortex-specific additions:

- **I-C1 — Marker-bounded `EIDOLONS.md` sections.** When the artifact is
  installed into shared host files (`AGENTS.md`, `CLAUDE.md`, copilot
  instructions), use `<!-- eidolon:cortex start --> … <!-- eidolon:cortex end -->`
  per `[F §9 invariant 1]`. `eidolons remove` depends on these.
- **I-C2 — No `eval` of routing rules.** The descriptor table is data;
  the dispatch is interpretive (LLM reads it). The cortex never executes
  arbitrary strings from the prompt as routing rules. `[F §9 invariant 2]`
  generalized.
- **I-C3 — D9 capability classes only.** The cortex emits
  `model_tier ∈ {speed-class, reasoning-class}`; never
  `claude-3-5-sonnet`, never `gpt-4o`. (`prime-directives.md:152-162`.)
  Vendor translation is the host's responsibility.
- **I-C4 — Always-loaded section ≤ 900 tokens.** The body of
  `EIDOLONS.md` may be larger but only the descriptor index plus the
  dispatch protocol must always-load. Deep tables, chain templates, and
  TRANCE matrices live in collapsible / anchored sections subject to
  progressive disclosure (P3, D1).
- **I-C5 — Refusals are immutable.** The cortex's emitted decision must
  never request a refused capability of a target Eidolon.
  (`[F §9 invariant 5]`.)
- **I-C6 — Idempotent emission.** Same prompt + same context + same
  roster ⇒ same routing decision (within the deterministic descriptor
  match). `[F §9 invariant 6]`.
- **I-C7 — Roster is the source of truth.** The cortex reads
  `roster/index.yaml`. New Eidolons added to the roster auto-appear in
  the dispatcher's universe; removed Eidolons disappear. `[F §9 invariant 14]`.
- **I-C8 — `[GAP]` and `[DISPUTED]` over silent merge** in routing
  decisions where the right Eidolon is genuinely ambiguous.
  `[F §9 invariant 15]`; `prime-directives.md:117-118`.
- **I-C9 — Bash 3.2 compatibility** for any `cli/src/*.sh` helper that
  consumes a cortex artifact (`[F §9 invariant 7]`; `CLAUDE.md` "Bash 3.2
  compatibility").
- **I-C10 — Stderr discipline** for any logging the cortex tooling
  emits; stdout reserved for captured values. `[F §9 invariant 8]`.

---

## 10. Open Questions / Assumptions

The eventual implementer carries these forward as labeled assumptions.

| ID | Assumption | What would invalidate it | Mitigation |
|---|---|---|---|
| OQ-1 | LLM-self-routing against descriptors is good enough for v1 (no trained classifier). | Production telemetry shows mis-routing > 10% on a held-out set. | Migrate to a small calibrated classifier (RouteLLM `[D §2 #1]`); descriptors stay authoritative. |
| OQ-2 | Confidence τ thresholds (τ_standard = 0.6, τ_trance = 0.8) are reasonable defaults from `[D §3.2]`. | Calibration experiment shows the optimal point is far off. | Tune τ from routing-decision logs; cite published Hybrid-LLM dial behavior. |
| OQ-3 | The hand-off graph union (§7.1) is acceptable until `roster/index.yaml` and `composition.md` are reconciled. | A consumer Eidolon refuses an edge the cortex relies on. | File a roster issue; cortex emits `[DISPUTED]` until resolved. |
| OQ-4 | TRANCE-on-demand (gated, not always-on) is the right v1 stance. | Cost-quality data on code-spec workloads contradicts the recommendation. | Add an TRANCE-default flag in `eidolons.yaml`; cortex still emits `[DECISION]` at C4 ceilings. |
| OQ-5 | Verbal confidence is reliable enough to set τ. | "Know Your Limits" TACL 2024 / `[D §6 row 3]` evidence accumulates against verbal confidence. | Pair LLM-confidence with structural signals (descriptor keyword overlap, prior-turn context, explicit hints) per `[D §6 row 3]`. |
| OQ-6 | Max 2 reroutes per turn is sufficient to prevent ping-pong. | Production logs show ≥3-step rerouting needed for legitimate cases. | Raise the cap with an explicit `[BLOCKED]` exit; never remove the cap. (`[D §6 row 4]`.) |
| OQ-7 | Self-consistency at N=3 / N=5 is the right FORGE-TRANCE shape. | Empirical study on FORGE-style decisions disagrees. | Drop N back to 3 or to FORGE-standard; tune from logs. (`[D §3.6]`.) |
| OQ-8 | Refusal-as-routing (re-route, never override) is the right policy. | A new Eidolon with mechanically-enforceable selective refusal lands. | Update I-C5; the policy is per-Eidolon, not global. (`[D §6 row 5]`.) |
| OQ-9 | Stateless cortex (no routing memory) is the v1 default. | Routing accuracy improves >5% with cross-session memory in pilot. | Add a Reflexion-style routing-decision store (`[D §3.8]`); initially read-only, opt-in write. |
| OQ-10 | Multi-turn cortex cycle (think → score → route) is unnecessary at v1. | Single-shot dispatch yields high mis-routing. | Add an internal Plan-and-Act sub-cycle; cite `[D §2 #13]`. |
| OQ-11 | Debate is not the TRANCE primitive. | A heterogeneous-model debate study shows a clear lift on coding tasks. | Add as a FORGE-TRANCE opt-in mode; never the default. (`[D §6 row 5]`.) |
| OQ-12 | Skill cards for IDG, FORGE, VIGIL not yet in the local nexus checkout (`[F §3]` note) is acceptable for v1 descriptors. | A new skill card lands with verbs that contradict the cortex descriptor. | Cortex re-aggregates skill cards on every roster change (`I-C7`). |

---

## 11. Implementation Hand-off

### 11.1 File location

- **Primary artifact:** `EIDOLONS.md` at the **root of the nexus repo**
  (`/Users/henrique/workspace/oss/agents/eidolons/EIDOLONS.md`).
  Rationale: parallels `MANIFESTO.md` and `CLAUDE.md` at the same level,
  reads naturally as a top-level project document, picked up by any host
  that scans the repo root.
- **Mirrored into the consumer project's `.eidolons/` install target** by
  the nexus-level installer when a consumer runs `eidolons init` or
  `eidolons sync`. The mirror lands at `./.eidolons/cortex/EIDOLONS.md`
  (matching the dot-prefixed install convention `[F §9 invariant 10]`).
  Per-Eidolon installers do **not** write the cortex file (they only
  write to cwd; nexus-level concerns are nexus-only,
  `docs/architecture.md:148-156`).
- **Marker-bounded inclusion** into `AGENTS.md`, `CLAUDE.md`, copilot
  instructions per I-C1 / `[F §9 invariant 1]`.

### 11.2 Files the cortex MUST NOT step on

- `roster/index.yaml` — read-only consumer (I-C7).
- `methodology/prime-directives.md`, `MANIFESTO.md` — voice docs;
  cortex is downstream.
- `cli/eidolons` and `cli/src/dispatch_eidolon.sh` — deterministic
  string-match path is unchanged (§2 non-scope).
- Per-Eidolon `./.eidolons/<name>/` directories — those belong to each
  member's own installer (`docs/architecture.md` security model).
- `eidolons.yaml` / `eidolons.lock` — these declare the consumer
  project's installed roster; cortex reads but never rewrites.

### 11.3 Suggested next Eidolon for implementation

**APIVR-Δ.** `EIDOLONS.md` is a brownfield artifact in the nexus
repo with a clear spec, established conventions, and bounded budget —
the canonical APIVR-Δ shape (`apivr-methodology/SKILL.md:3`). The
cortex spec contains the GIVEN/WHEN/THEN gates APIVR-Δ uses as its
Verify rubric.

**Hand-off label:** `spectra:plan → apivr:implement` with hand-off
artifact at this file path. Edge origin: `roster:downstream`
(`roster/index.yaml:106-108`).

**Suggested chain for the implementation itself:** APIVR-Δ standard
tier (single eidolon, single track) → IDG (chronicle the cortex
introduction in a CHANGELOG entry and a brief ADR). No ATLAS step
needed — the surface is this file plus the listed read-only references;
no SPECTRA second pass needed — the spec is this document.

---

*End of cortex spec. Author next: APIVR-Δ. Confidence: high (spec is
fully grounded in `[D]` + `[F]` + repo invariants; open questions
explicitly carried forward as named assumptions).*
