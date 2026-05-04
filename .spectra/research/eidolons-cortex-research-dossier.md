# EIDOLONS Cortex — Research Dossier

**Author:** Research subagent (Opus 4.7, 1M ctx)
**Date:** 2026-05-03
**Scope:** Frontier techniques for an EIDOLONS.md "central cortex" that routes prompts to a fixed roster of 5 specialized agents (ATLAS, SPECTRA, APIVR-Δ, IDG, FORGE) and defines an TRANCE tier of harness capabilities.
**Method:** Two rounds of literature search (40+ queries), 4 deep fetches of primary sources. Bias toward arXiv preprints, ICLR/NeurIPS/ICML proceedings, and Anthropic engineering documentation. Blog posts marked as such.

---

## 1. Executive Summary

Five findings carry the most weight for a fixed-roster routing cortex:

1. **Routing is a calibrated classifier problem, not an LLM-judgement problem.** Hybrid LLM (Ding et al., ICLR 2024) and RouteLLM (Ong et al., ICLR 2025) both show that a small calibrated router predicting query difficulty/win-probability outperforms ad-hoc LLM-as-router by 30-85% in cost at matched quality. The signal that matters is a continuous score plus a tunable threshold, not a discrete decision. RouterArena (Oct 2025) confirms this generalizes across 12 routers.

2. **Heterogeneous specialists beat homogeneous swarms.** "Stop Overvaluing Multi-Agent Debate" (Zhang et al., NeurIPS 2025 position) and X-MAS (May 2025) jointly establish that diversity-of-capability is what makes multi-agent systems beat single-agent baselines — not the debate protocol itself. The Eidolons roster (5 distinct methodologies) is already a diversity asset; the cortex must preserve it, not collapse it.

3. **Progressive disclosure is the production-proven discovery mechanism.** Anthropic Agent Skills (Oct 2025) routes via lightweight YAML metadata (~100 tokens per skill) preloaded in system prompt, with full instructions loaded only on trigger. This is the canonical pattern for a fixed-roster cortex — name+description as router signal, body as deferred payload.

4. **Pre-plan confidence-raising is well-supported.** Self-Consistency (Wang et al., ICLR 2023), Self-Refine (Madaan et al., NeurIPS 2023), Reflexion (Shinn et al., NeurIPS 2023), and "Ask or Assume?" (2026) converge on a recipe: sample multiple paths, verify with a separate evaluator, abstain or ask clarification when uncertainty is high. This maps cleanly to an "elevate confidence before composing the plan" stage.

5. **TRANCE-tier capability is parallel-fanout + verifier-cascade + heterogeneity, not "longer thinking alone."** Anthropic's multi-agent research system (90.2% lift over single-agent at ~15× tokens), o1 test-time scaling results, and Du & Mordatch's debate work jointly support: parallel breadth > sequential depth for hard tasks, but only when paired with a verifier or aggregator. Pure self-revision (longer CoT) often degrades correctness (Revisiting o1 test-time scaling, ACL 2025).

---

## 2. Ranked Technique Catalog

| # | Technique | Citation | Summary | Applicability |
|---|-----------|----------|---------|---------------|
| 1 | **Calibrated router with preference data** | RouteLLM, Ong et al., arXiv:2406.18665 (ICLR 2025) | Train a small classifier on Chatbot-Arena preference data to predict P(strong-model-wins) per query; threshold at runtime. 85% cost cut on MT-Bench at matched quality. | **HIGH** — exactly the shape of a 5-Eidolon dispatcher. Replace "strong/weak" with "ATLAS/SPECTRA/APIVR-Δ/IDG/FORGE." |
| 2 | **Hybrid LLM (difficulty-aware routing)** | Ding et al., arXiv:2404.14618 (ICLR 2024) | Router predicts query difficulty + tunable quality dial. 22% queries to small model with <1% quality drop. Threshold dial is the user-facing knob. | **HIGH** — gives the cortex a continuous "complexity" signal aligned with the existing complexity-routing in `apivr-methodology`. |
| 3 | **Progressive disclosure (Skills metadata)** | Anthropic Agent Skills docs, Oct 2025 (vendor doc) | YAML name+description always loaded (~100 tok); body loaded on match; resources loaded by reference. Three-level lazy hierarchy. | **HIGH** — already the runtime model the consumer projects use; the cortex should mirror this exactly. |
| 4 | **Mixture-of-Agents (layered aggregation)** | Wang et al., arXiv:2406.04692 (ICLR 2025 Spotlight) | N proposer agents → aggregator(s) → final. Open-source MoA beats GPT-4o on AlpacaEval. Quality from aggregation, not from any single agent. | **MED** — only relevant if cortex spawns >1 Eidolon for the same step. Useful for TRANCE tier when SPECTRA + FORGE both tackle a hard decision. |
| 5 | **Multi-agent debate** | Du, Li, Torralba, Tenenbaum, Mordatch, arXiv:2305.14325 (ICML 2024) | Multi-round debate between LLM instances raises factuality/reasoning. **But:** subsequent work (#6) shows the lift comes from heterogeneity, not the debate protocol. | **MED** — cite as inspiration; do not adopt naive debate. |
| 6 | **Heterogeneity > debate (critique)** | Zhang et al., arXiv:2502.08788 (NeurIPS 2025 position); X-MAS arXiv:2505.16997 | MAD often fails to beat single-agent CoT+self-consistency at matched compute. Model heterogeneity is the universal lift (8-47%). | **HIGH** — directly justifies the "5 distinct methodologies" architecture; warns against collapsing roles. |
| 7 | **Orchestrator-workers** | Anthropic Engineering, "How we built our multi-agent research system" (2025, vendor blog) | Lead Opus + 3-5 Sonnet subagents in parallel; 90.2% lift vs single-agent at ~15× tokens. Failure modes: over-spawning, duplicate work, poor task descriptions. | **HIGH** — this is the production reference architecture for TRANCE-tier fan-out. |
| 8 | **Self-Consistency** | Wang et al., arXiv:2203.11171 (ICLR 2023) | Sample N CoT paths, majority-vote answer. +17.9% GSM8K. Cheap, drop-in. | **HIGH** — easiest TRANCE-tier upgrade for FORGE-style decisions. |
| 9 | **Self-Refine** | Madaan et al., arXiv:2303.17651 (NeurIPS 2023) | Same LLM acts as generator + critic + refiner in a loop. ~20% absolute gain across 7 tasks. | **MED** — natural fit for IDG (doc synthesis) and SPECTRA (spec composition); risky for ATLAS (read-only). |
| 10 | **Reflexion** | Shinn et al., arXiv:2303.11366 (NeurIPS 2023) | Verbal RL: convert task feedback into textual reflections stored in episodic memory; reuse next trial. | **HIGH** — APIVR's `apivr-memory-management` skill is already a Reflexion implementation. Cortex should reuse this protocol across roster. |
| 11 | **Tree of Thoughts** | Yao et al., arXiv:2305.10601 (NeurIPS 2023) | Explicit tree search over thought-states with self-eval at each node. 74% Game-of-24 vs 4% CoT. | **MED** — overkill for routing; relevant as an TRANCE-tier mode for FORGE. |
| 12 | **ReAct** | Yao et al., arXiv:2210.03629 (ICLR 2023) | Interleaved Thought–Action–Observation. Foundation for nearly all tool-using agents incl. Deep Research. | **HIGH (foundational)** — already the implicit baseline; cite as the floor. |
| 13 | **Plan-and-Solve / Plan-and-Act** | Wang et al., ACL 2023 (PS); Erdogan et al., arXiv:2503.09572 (ICML 2025, Plan-and-Act) | Explicit Planner + Executor split. Plan-and-Act 2025 specifically targets long-horizon agents. | **HIGH** — maps to the SPECTRA(plan)→APIVR(execute) handoff already in the roster. |
| 14 | **Process Reward Models (verifier)** | "Let's Verify Step by Step" Lightman et al., arXiv:2305.20050 (ICLR 2024); Math-Shepherd ACL 2024 | Step-level verifier outperforms outcome-level supervision; powers best-of-N selection. | **MED** — useful as APIVR Verify-phase reward signal; secondary for routing. |
| 15 | **Cascade with confidence threshold** | FrugalGPT Chen et al., arXiv:2305.05176 (TMLR 2024); Gatekeeper arXiv:2502.19335 | Sequential model calls; escalate only if cheap model's confidence < threshold. Up to 98% cost cut at matched quality. | **MED** — cascade fits cost-sensitive ops (e.g., IDG simple doc patches), less natural for capability-routing. |
| 16 | **Unified routing + cascading** | de Koninck et al., arXiv:2410.10347 | Optimal strategy combines one-shot routing AND sequential escalation under a single decision-theoretic framework. | **MED** — relevant if cortex needs both modes (predict-route + escalate-on-failure). |
| 17 | **Test-time compute scaling** | OpenAI o1 (Sep 2024 vendor); s1, Muennighoff et al., arXiv:2501.19393 | Sequential CoT-extension and parallel best-of-N both scale; **parallel scales better than sequential** for o1-class. | **HIGH** — key evidence that TRANCE = parallel fanout, not just longer thinking. |
| 18 | **Critical caveat on long CoT** | "Revisiting Test-Time Scaling of o1-like Models" arXiv:2502.12215 (ACL 2025) | Longer CoTs do **not** consistently improve accuracy; correct solutions are often shorter. Self-revision can degrade. | **HIGH** — bounds the TRANCE design: don't blindly stretch thinking budget. |
| 19 | **Abstention / clarification under uncertainty** | "Know Your Limits" survey, Wen et al., TACL 2024; "Ask or Assume?" arXiv:2603.26233 | Calibrated abstention + clarification-seeking raises coding-agent resolve rate from 61.2% → 69.4%. | **HIGH** — load-bearing for "elevate confidence BEFORE plan" requirement. |
| 20 | **Supervisor / hierarchical multi-agent** | LangGraph Supervisor docs (vendor); HiPlan arXiv:2508.19076 | Central supervisor decides which specialist runs; supports nesting (supervisor-of-supervisors). | **HIGH** — the natural architecture for a cortex over a fixed roster. |
| 21 | **Semantic / embedding routing** | Aurelio Semantic Router (OSS); vLLM Semantic Router | Pre-encode "route utterances" as embeddings; cosine-match incoming query. ~50× latency cut vs LLM-as-router. | **MED** — viable cheap first stage before learned router; complements RouteLLM. |
| 22 | **Skill discovery via descriptors** | "Agent Skills for Large Language Models" survey arXiv:2602.12430; SkillRouter arXiv:2603.22455 | Description (≤500 char) + body (≤2000 char) is the standard skill descriptor; routing is retrieval over descriptions. | **HIGH** — direct prescription for the EIDOLONS.md descriptor schema. |
| 23 | **Budget-aware reasoning** | BudgetThinker arXiv:2508.17196; Certainty-Guided Reasoning arXiv:2509.07820 | Dynamically extend or terminate thinking based on confidence/budget. CGR achieves higher accuracy at lower token cost than fixed-budget. | **MED** — applicable to FORGE and SPECTRA at TRANCE tier. |
| 24 | **MetaGPT (SOPs as prompts)** | Hong et al., arXiv:2308.00352 (ICLR 2024) | Encode standardized operating procedures into role prompts; assembly-line decomposition. SOTA pass@1 on coding. | **MED** — validates that strong methodology priors (which Eidolons already have) outperform generic prompting. |
| 25 | **Deep Research (multi-step planner)** | OpenAI Deep Research (Feb 2025 vendor blog) | Triage → clarification → instruction → research agents; 5–30 min autonomous loops. | **MED** — reference for the cortex's clarification + scoping front-stage. |

---

## 3. Frontier Techniques for EIDOLONS.md (Curated 8)

These are the techniques that should anchor the cortex spec. For each: how it maps to the roster, what TRANCE capability it unlocks, and a concrete implementation hint.

### 3.1 Progressive-disclosure descriptor routing (Anthropic Skills pattern)
- **Maps to:** All 5 Eidolons. EIDOLONS.md becomes the always-loaded metadata layer (≤100 tok per Eidolon × 5 = ~500 tok overhead).
- **Signal:** YAML `name + description` per Eidolon, augmented with `triggers` (verbs: "scout", "plan", "implement", "document", "decide") and `refuses` (negative keywords).
- **Threshold:** None at metadata stage — Claude does soft matching against descriptions in system prompt.
- **Fallback:** If no Eidolon's description matches with confidence, escalate to FORGE (pure reasoner) for a routing decision.
- **TRANCE unlock:** Multiple Eidolons can be triggered in parallel for the same query (orchestrator-workers).
- **Source:** [Anthropic Agent Skills docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview); [Equipping agents with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills).

### 3.2 Calibrated routing signal (RouteLLM/Hybrid-LLM pattern)
- **Maps to:** Cortex dispatcher itself. Even without a trained classifier, the cortex can elicit a self-reported confidence-per-eidolon from the LLM and threshold against it.
- **Signal:** For each Eidolon, score(query) ∈ [0,1]. Pick argmax above τ; otherwise clarify or escalate.
- **Threshold:** τ tunable per TRANCE tier (e.g., 0.6 standard, 0.8 TRANCE — higher bar to act).
- **Fallback:** Below τ → trigger clarification (technique 3.5) before composing plan.
- **Source:** [RouteLLM arXiv:2406.18665](https://arxiv.org/abs/2406.18665); [Hybrid LLM arXiv:2404.14618](https://arxiv.org/abs/2404.14618).

### 3.3 Heterogeneity-preserving orchestration
- **Maps to:** Multi-Eidolon invocations. Never collapse two Eidolons into one role; never replace ATLAS's read-only stance with APIVR's write-capable stance.
- **Signal:** Roster diversity index — how many distinct methodologies are represented in the active set.
- **TRANCE unlock:** When a query touches 2+ phases of the SDLC (e.g., "scout + spec + implement"), spawn ATLAS → SPECTRA → APIVR-Δ as a relay, not as a single mega-agent.
- **Source:** [X-MAS arXiv:2505.16997](https://arxiv.org/abs/2505.16997); [Stop Overvaluing MAD arXiv:2502.08788](https://arxiv.org/abs/2502.08788).

### 3.4 Orchestrator-worker fan-out (TRANCE only)
- **Maps to:** TRANCE tier exclusively. Lead cortex spawns N parallel Eidolon invocations; collects results; synthesizes.
- **Signal/threshold:** Anthropic's empirical scaling rule — simple = 1 agent / 3-10 calls; comparison = 2-4 agents / 10-15 calls each; complex = 10+ agents. Use complexity score (3.2) to pick tier.
- **Fallback:** On any subagent failure, do not retry the whole fan-out; continue with N-1 results and flag the gap (Reflexion-style).
- **Caveat:** ~15× token cost vs single-agent. Justified only when expected quality lift > cost.
- **Source:** [Anthropic multi-agent research blog](https://www.anthropic.com/engineering/multi-agent-research-system); [Anthropic Building Effective Agents](https://www.anthropic.com/research/building-effective-agents).

### 3.5 Pre-plan clarification + abstention
- **Maps to:** The cortex's "raise confidence before composing the plan" requirement. Sits between routing and dispatch.
- **Signal:** Underspecification flags — missing scope, ambiguous referents, unstated constraints.
- **Threshold:** If clarifying-question gain (model-estimated) > some bar, ask before dispatch. Cap at 1-3 questions per turn (per Claude Code pattern).
- **Fallback:** If user can't disambiguate, dispatch to FORGE for a Frame phase to record assumptions explicitly.
- **Source:** [Ask or Assume? arXiv:2603.26233](https://arxiv.org/abs/2603.26233); [Know Your Limits TACL 2024](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00754/131566/Know-Your-Limits-A-Survey-of-Abstention-in-Large).

### 3.6 Self-Consistency for hard decisions (FORGE TRANCE)
- **Maps to:** FORGE specifically — the pure reasoner. Sample N (3-5) reasoning traces, majority-vote or judge-merge.
- **Signal:** Decision is "hard" — flagged by FORGE's own Frame phase or by upstream Eidolon escalation.
- **Threshold:** N=3 standard TRANCE, N=5 high-stakes (matches o1's 64-sample sweet spot scaled to budget).
- **Fallback:** If consensus < 60%, return "no decision" + sampled disagreements (Gate phase failure).
- **Source:** [Self-Consistency arXiv:2203.11171](https://arxiv.org/abs/2203.11171); [s1 simple test-time scaling arXiv:2501.19393](https://arxiv.org/abs/2501.19393).

### 3.7 Evaluator-Optimizer loop (SPECTRA / IDG TRANCE)
- **Maps to:** SPECTRA's spec composition; IDG's doc synthesis. Generator + Evaluator + termination gate.
- **Signal:** Structured evaluation criteria (SPECTRA already defines validation gates; IDG already has CHT verification).
- **Threshold:** PASS = all gates green. Cap iterations at 3 (Anthropic's empirical sweet spot).
- **Fallback:** If 3 iterations fail, hand off to FORGE for a deliberate decision on whether to scope-down or escalate to user.
- **Source:** [Anthropic evaluator-optimizer cookbook](https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/evaluator_optimizer.ipynb); [Self-Refine arXiv:2303.17651](https://arxiv.org/abs/2303.17651).

### 3.8 Reflexion memory across cortex turns
- **Maps to:** Cross-Eidolon learning. APIVR already has `apivr-memory-management`; the cortex should propagate failure classifications and successful patterns across the roster, not just within APIVR.
- **Signal:** Verbal reflection at end of each Eidolon invocation; structured into FINDING / GAP / PATTERN records.
- **Threshold:** Always-on for write-capable Eidolons (APIVR, IDG, SPECTRA); read-only memory for ATLAS and FORGE.
- **Fallback:** Memory corruption → fall back to no-memory baseline; never let stale memory cause regression.
- **Source:** [Reflexion arXiv:2303.11366](https://arxiv.org/abs/2303.11366).

---

## 4. Routing Architecture Patterns — Survey & Recommendation

### Patterns considered

| Pattern | Pros | Cons | Fit for 5-Eidolon roster |
|---------|------|------|-------------------------|
| **Single-router (one-shot classifier)** | Cheap; deterministic; calibratable. | No correction once dispatched; misroutes hurt. | Good baseline. |
| **Cascade (escalation)** | Cost-optimal under Frugal-GPT assumptions; explicit fallback. | Sequential latency; capability mismatch (cheap≠wrong-tool) for fixed roster. | Poor — Eidolons differ in *role*, not *strength*. |
| **Hierarchical supervisor** | Clean composition; supports nesting; Claude Agent SDK & LangGraph both support natively. | Supervisor itself becomes a single point of failure; needs its own evaluation. | **Best fit.** |
| **Mixture-of-Agents aggregation** | Highest quality at the top end; well-evidenced lift on hard tasks. | ~N× cost; aggregator quality is the new bottleneck; overkill for routing. | Reserve for TRANCE tier on hard queries. |
| **Multi-agent debate** | Strong on factuality. | Often no lift over self-consistency at equal cost; sycophancy risks. | Avoid as primary; use only with model heterogeneity. |
| **Tournament / voting** | Robust under noise; calibratable. | Needs a verifier; expensive. | TRANCE tier only. |

### Recommended composition for EIDOLONS.md

**Two-stage hybrid:**

1. **Stage 1 — Descriptor-based supervisor** (always-on, ~500 tok). The cortex publishes Eidolon descriptors (name + description + triggers + refuses) in the system prompt. The host LLM (Claude as supervisor) does a soft match. Backed by the vendor-proven Skills mechanism.

2. **Stage 2 — Confidence gate + TRANCE escalation.** If supervisor's top match is high-confidence and a single Eidolon suffices → dispatch (standard tier). If query spans multiple phases → relay (orchestrator-worker pattern, Eidolon → Eidolon handoff). If decision is high-stakes or low-confidence → TRANCE tier (parallel fanout to ≥2 Eidolons, optional FORGE arbitration, evaluator-optimizer wrapping).

This composition is justified by: (a) progressive-disclosure works in production at Anthropic and millions of Skills users; (b) supervisor pattern is the consensus architecture in LangGraph and the Claude Agent SDK; (c) the heterogeneity literature says the 5 distinct Eidolons are themselves the diversity asset — keep them visible to the supervisor rather than collapsing them.

---

## 5. TRANCE Tier Definition — Candidates Ranked by Evidence Strength

| Rank | TRANCE capability | Evidence strength | Mechanism |
|------|------------------|-------------------|-----------|
| 1 | **Parallel fan-out to multiple Eidolons (orchestrator-workers)** | **Strong** — Anthropic 90.2% lift; o1 parallel > sequential; MoA Spotlight | Lead cortex spawns 2-N Eidolon invocations concurrently; collects; synthesizes. Gate on complexity score and budget. |
| 2 | **Worktree / context isolation per parallel Eidolon** | **Strong (production)** — Anthropic Agent SDK; Claude Code worktrees; incident.io case study | Each parallel Eidolon gets isolated working directory + isolated context window. Prevents cross-contamination of file edits. |
| 3 | **Self-consistency / best-of-N for FORGE decisions** | **Strong** — Wang ICLR 2023; o1 AIME 74→83% with N=64 | N=3-5 parallel reasoning traces with majority-vote or judge selection. |
| 4 | **Evaluator-optimizer iteration capped at 3** | **Strong** — Anthropic cookbook + Self-Refine; APIVR already does this | Generator (Eidolon) + evaluator (FORGE or domain rubric) loop until PASS or 3 iterations. |
| 5 | **Heterogeneous model selection per Eidolon** | **Strong** — X-MAS 8-47% lift; Stop-Overvaluing-MAD position | TRANCE allows lead = Opus, workers = Sonnet (mirrors Anthropic research-system); could allow per-Eidolon model pinning. |
| 6 | **Verifier-cascade (PRM / step-level reward)** | **Medium-strong** — Lightman ICLR 2024; Math-Shepherd | Adds a verifier between generation and emission; especially useful for APIVR-Δ Verify and SPECTRA validation gates. |
| 7 | **Extended thinking / dynamic budget** | **Medium with caveats** — BudgetThinker, CGR; **but** "Revisiting o1" warns longer ≠ better | Allow Eidolons to request extended-thinking for complex steps. Couple with confidence-gated termination, not blind extension. |
| 8 | **Reflexion-style memory propagation across roster** | **Medium-strong** — Reflexion NeurIPS 2023; APIVR memory skill is empirical evidence | Cross-Eidolon learning store; TRANCE tier writes back; standard tier reads only. |
| 9 | **Tournament selection of plans** | **Medium** — generative verifier work, GenSelect | When multiple SPECTRA plans or APIVR diffs are produced, run pairwise comparison. Expensive — TRANCE only. |
| 10 | **Multi-agent debate** | **Weak as primary, strong as add-on** — Du ICML 2024 lift, but Stop-Overvaluing-MAD shows it underperforms simpler baselines without heterogeneity | Use only when (a) heterogeneous models available, (b) factuality is the dominant axis. |

**Recommended TRANCE definition (composite):** parallel fan-out + worktree isolation + evaluator-optimizer wrapping + confidence-gated termination + Reflexion memory. Optional add-ons: self-consistency for FORGE, verifier-cascade for APIVR/SPECTRA.

---

## 6. Open Gaps

1. **Quantitative tradeoff: "TRANCE always" vs "TRANCE on demand."** Anthropic's 15× token cost number applies to research workloads. We don't have data for code-spec workloads with the Eidolons roster. Spec author should set TRANCE as opt-in (user flag or auto-trigger on complexity ≥ threshold), not always-on.

2. **No published study of fixed-roster routing at N=5.** The literature is dominated by 2-tier (small/large) routers and large-pool MoA. The closest analogues are LangGraph supervisor demos and Anthropic's research subagents (3-5 specialists). The cortex spec is doing applied work the literature hasn't directly benchmarked — assume the supervisor pattern generalizes but plan to measure.

3. **Confidence-elicitation reliability for self-routing.** "Know Your Limits" survey shows verbalized confidence is improving but still imperfect. For the cortex's own self-reported routing confidence, the spec author should pair LLM-confidence with structural signals (descriptor keyword overlap, prior-turn context, explicit user hints) rather than trust softmax alone.

4. **When to abandon a route mid-execution.** The cascade-routing literature handles this for static models, but for an ATLAS-mid-mission situation where the answer turns out to need APIVR-Δ instead, no clean published protocol. Recommend the spec define an explicit "handoff" verb that any Eidolon can invoke and a guard against infinite ping-pong (max 2 reroutes per turn).

5. **MAD / debate efficacy on coding-agent tasks.** The strongest debate evidence is on factuality and math; coding-agent results are mixed. The Eidolons stack is mostly software-engineering — assume debate is **not** TRANCE-default; surface as an optional mode for FORGE only.

---

## 7. Bibliography

**Routing & Cascading**
- Ong et al. (2024). *RouteLLM: Learning to Route LLMs with Preference Data.* arXiv:2406.18665. ICLR 2025. https://arxiv.org/abs/2406.18665
- Ding et al. (2024). *Hybrid LLM: Cost-Efficient and Quality-Aware Query Routing.* arXiv:2404.14618. ICLR 2024. https://arxiv.org/abs/2404.14618
- Chen, Zaharia, Zou (2023). *FrugalGPT.* arXiv:2305.05176. TMLR 2024. https://arxiv.org/abs/2305.05176
- de Koninck et al. (2024). *A Unified Approach to Routing and Cascading for LLMs.* arXiv:2410.10347. https://arxiv.org/abs/2410.10347
- *RouterArena* (2025). arXiv:2510.00202. https://arxiv.org/abs/2510.00202
- Hu et al. (2024). *RouterBench.* arXiv:2403.12031. https://arxiv.org/abs/2403.12031
- *Gatekeeper: Improving Model Cascades Through Confidence Tuning.* arXiv:2502.19335. https://arxiv.org/pdf/2502.19335

**Multi-Agent & Mixture-of-Agents**
- Wang et al. (2024). *Mixture-of-Agents Enhances LLM Capabilities.* arXiv:2406.04692. ICLR 2025 Spotlight. https://arxiv.org/abs/2406.04692
- Du, Li, Torralba, Tenenbaum, Mordatch (2023). *Improving Factuality and Reasoning through Multiagent Debate.* arXiv:2305.14325. ICML 2024. https://arxiv.org/abs/2305.14325
- Zhang et al. (2025). *Stop Overvaluing Multi-Agent Debate.* arXiv:2502.08788. NeurIPS 2025 position. https://arxiv.org/abs/2502.08788
- *X-MAS: Towards Building Multi-Agent Systems with Heterogeneous LLMs.* arXiv:2505.16997. https://arxiv.org/abs/2505.16997
- Wu et al. (2023). *AutoGen.* arXiv:2308.08155. https://arxiv.org/abs/2308.08155
- Hong et al. (2023). *MetaGPT: Meta Programming for a Multi-Agent Collaborative Framework.* arXiv:2308.00352. ICLR 2024. https://arxiv.org/abs/2308.00352

**Self-improvement, Verification, Memory**
- Wang et al. (2022). *Self-Consistency Improves CoT Reasoning.* arXiv:2203.11171. ICLR 2023. https://arxiv.org/abs/2203.11171
- Madaan et al. (2023). *Self-Refine.* arXiv:2303.17651. NeurIPS 2023. https://arxiv.org/abs/2303.17651
- Shinn et al. (2023). *Reflexion.* arXiv:2303.11366. NeurIPS 2023. https://arxiv.org/abs/2303.11366
- Yao et al. (2023). *Tree of Thoughts.* arXiv:2305.10601. NeurIPS 2023. https://arxiv.org/abs/2305.10601
- Lightman et al. (2023). *Let's Verify Step by Step.* arXiv:2305.20050. ICLR 2024. https://arxiv.org/abs/2305.20050
- *Math-Shepherd.* ACL 2024. https://aclanthology.org/2024.acl-long.510.pdf

**Agent Foundations**
- Yao et al. (2022). *ReAct.* arXiv:2210.03629. ICLR 2023. https://arxiv.org/abs/2210.03629
- Wang et al. (2023). *Plan-and-Solve Prompting.* ACL 2023. https://aclanthology.org/2023.acl-long.147/
- Erdogan et al. (2025). *Plan-and-Act.* arXiv:2503.09572. ICML 2025. https://arxiv.org/abs/2503.09572
- *HiPlan: Hierarchical Planning for LLM-Based Agents.* arXiv:2508.19076. https://arxiv.org/abs/2508.19076
- Wang et al. (2023). *Voyager.* arXiv:2305.16291. https://arxiv.org/abs/2305.16291

**Test-Time Compute**
- OpenAI (Sep 2024). *Learning to Reason with LLMs (o1).* https://openai.com/index/learning-to-reason-with-llms/ *(vendor blog)*
- Muennighoff et al. (2025). *s1: Simple test-time scaling.* arXiv:2501.19393. https://arxiv.org/abs/2501.19393
- *Revisiting Test-Time Scaling of o1-like Models.* arXiv:2502.12215. ACL 2025. https://arxiv.org/abs/2502.12215
- *BudgetThinker.* arXiv:2508.17196. https://arxiv.org/abs/2508.17196
- *Certainty-Guided Reasoning.* arXiv:2509.07820. https://arxiv.org/abs/2509.07820

**Uncertainty, Abstention, Clarification**
- Wen et al. (2024). *Know Your Limits: A Survey of Abstention in LLMs.* TACL. https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00754/131566/Know-Your-Limits-A-Survey-of-Abstention-in-Large
- *Ask or Assume? Uncertainty-Aware Clarification-Seeking in Coding Agents.* arXiv:2603.26233. https://arxiv.org/abs/2603.26233
- *Curiosity by Design.* arXiv:2507.21285. https://arxiv.org/abs/2507.21285

**Skills & Capability Descriptors**
- Anthropic (2025). *Agent Skills Overview.* https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview *(vendor doc)*
- Anthropic (2025). *Equipping Agents for the Real World with Agent Skills.* https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills *(vendor blog)*
- *Agent Skills for LLMs: Architecture, Acquisition, Security.* arXiv:2602.12430. https://arxiv.org/html/2602.12430v3
- *SkillRouter.* arXiv:2603.22455. https://arxiv.org/html/2603.22455v4
- Patil et al. (2023). *Gorilla.* arXiv:2305.15334. https://arxiv.org/abs/2305.15334

**Production Multi-Agent Architectures (vendor / blog)**
- Anthropic. *How we built our multi-agent research system.* https://www.anthropic.com/engineering/multi-agent-research-system *(vendor blog)*
- Anthropic. *Building Effective Agents.* https://www.anthropic.com/research/building-effective-agents *(vendor blog)*
- Anthropic. *Evaluator-Optimizer cookbook.* https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/evaluator_optimizer.ipynb *(vendor)*
- Anthropic. *Building agents with the Claude Agent SDK.* https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk *(vendor blog)*
- LangChain. *LangGraph Multi-Agent Supervisor.* https://reference.langchain.com/python/langgraph-supervisor *(vendor doc)*
- OpenAI. *Introducing Deep Research.* https://openai.com/index/introducing-deep-research/ *(vendor blog)*

**Routing Implementations (OSS)**
- Aurelio Labs. *Semantic Router.* https://github.com/aurelio-labs/semantic-router *(OSS)*
- vLLM. *Semantic Router.* https://vllm-semantic-router.com/ *(OSS)*
- Together. *Mixture-of-Agents (MoA).* https://github.com/togethercomputer/moa *(OSS)*
