# v2.0 Research — Orchestration, Distillation, Tier Routing, Decomposition (2026-07-02)

> Fan-out research agent deliverable (~55 primary sources; claims 2+-source verified or
> marked UNVERIFIED). Persisted condensed; classifications relative to Eidolons
> constraints (no fine-tuning, bash 3.2 core, host-agnostic, deterministic kernel).

## Headline verdict

"Strong system + weak model beats bare frontier model" is **conditionally true, and the
condition is precise: a deterministic verifier must exist.** Where outputs are
mechanically checkable the evidence is strong and replicated across four years
(AlphaCode → CodeT → Large Language Monkeys → CodeMonkeys → Devin Fusion). Where
verification is judgment-based, gains plateau and scaffold value depreciates each model
generation (METR: scaffolding ~8pp n.s. vs ~26pp from post-training; mini-swe-agent's
authors deleted their own 2024 scaffold). **The durable moat is the verifier and
maker≠checker separation — not orchestration cleverness.**

## Section highlights

**1 Orchestrator/worker (production 2026)**
- Anthropic multi-agent: Opus lead + Sonnet workers +90.2%, but ~15× tokens — ADAPT.
- Claude Code: Haiku-pinned read-only Explore agent; per-subagent `model:` frontmatter —
  ADOPT (roster-expressible today).
- `opusplan`: opus during plan mode → sonnet for execution; the plan boundary is a
  mechanical tier-switch trigger — ADOPT.
- **Advisor strategy (verified):** Sonnet+Opus-advisor +2.7pp at −11.9% cost; Haiku+
  Opus-advisor 41.2% BrowseComp vs 19.7% Haiku solo at −85% cost vs Sonnet — ADAPT
  (encode "consult upstream tier" as ECL performative).
- Cognition 2026: "map-reduce-and-manage" — **writes stay single-threaded, most
  subagents read-only**; "Smart Friend" failed: weak models can't self-detect limits →
  deterministic escalation rules, never self-assessment — ADOPT.
- **Devin Fusion (verified):** frontier agent holds plan/ambiguity/final-review only,
  cheap sidekick executes; FrontierCode 57.6 vs 57.0 solo at −35-41% cost — ADAPT.
- Cursor: plan-as-reviewable-artifact + worktree isolation — ADAPT.
- PEAR "weak planner hurts more than weak executor": withdrawn by arXiv — WATCH only.

**2 Distillation without fine-tuning**
- SkillWeaver: strong-agent-authored skills lift weak agents up to +54.3% (WebArena) — ADAPT.
- Agent Workflow Memory: traces → named textual workflows, +24.6/+51.1% relative — ADOPT
  (cleanest template for crystalium skill lifecycle).
- AutoManual: teacher writes Markdown runbook; GPT-3.5 hits 86.2% ALFWorld with it —
  ADOPT (literal validation of methodology-package format).
- Memp: procedural memory built by GPT-4o transplanted to Qwen-14B (+~5%) — ADAPT.
- **ACE (ICLR 2026): playbooks need structured delta updates, never wholesale
  regeneration** (brevity bias, context collapse) — ADOPT (maps to ESL drift contract).
- Letta skill learning: reflect→Markdown skills, +21-37% on Terminal-Bench at −15.7%
  cost — ADOPT (recipe for a nexus command over crystalium).
- **2026 caution study: naive skill extraction causes negative transfer; an authoring
  meta-skill + validation gate substantially reduces it** — ADOPT as guardrail.
- GEPA: reflective prompt evolution beats RL (+6-20%, 35× fewer rollouts), output is
  text — ADAPT (offline tooling).
- AFlow: optimized workflows let small models beat GPT-4o at 4.55% of cost — ADAPT.
- KAIST Agent Distillation, Sub-goal Distillation: REJECT (need weight updates); salvage:
  behavioral/tool traces transfer better than reasoning transcripts.

**3 Tier routing / cascades**
- **Structural finding: every pre-generation difficulty router is ML-shaped (FrugalGPT
  scorer, RouteLLM, Arch-Router, GPT-5 router). The post-generation class — run cheap →
  mechanical check → escalate — is deterministic-capable. This settles the kernel
  design.** — ADOPT.
- RouteLLM: REJECT for kernel (trained weights); keep as benchmark baseline.
- RouterBench: 405k precomputed outcomes → score any router offline free — ADOPT.
- Arch-Router/NVIDIA: adopt the declarative category→tier YAML policy, replace ML
  matcher with mechanical signals — ADAPT.
- GPT-5 router opacity = the anti-pattern; Eidolons routing is grep-able — positioning.
- Mixture-of-Thought cascade: sample cheap in 2 formats, escalate only on disagreement —
  40% of strong-model cost, mechanical accept check — ADOPT.
- C3PO: conformal thresholds precomputed offline, shipped as constants — ADAPT.
- **Large Language Monkeys: DeepSeek-V2 15.9%→56% SWE-bench Lite at 250 samples; 5 weak
  samples beat 1 strong sample at 3× cheaper — only where automatically verifiable.**
  Verification Horizon: strong policies exploit weak verifiers by tampering with tests →
  test files read-only to executor, verifier outside executor write scope — ADOPT.
- Hosted routers (OpenRouter/NotDiamond/Martian): REJECT (hosted ML black boxes).

**4 Decomposition granularity for small models**
- Tier ladder: sub-14B ≈15-22% SWE-bench even with RL; 24-72B 40-60% via fixed
  pipelines; haiku/mini-class 55-73% with two bounded tools — ADOPT as cortex table.
- **Agentless: fixed localize→repair→validate pipeline, no LLM control flow — 50.8%
  Verified at ~$0.34/issue.** "The model never decides what to do next" — ADOPT.
- **Kimi-Dev-72B: 60.4% in fixed workflow vs 48.6% as free agent — SAME WEIGHTS,
  ~12-point structure dividend** — ADAPT.
- Scaffold gap ≈22 points for o3-mini (39% open scaffold vs 61% internal) but ~0 for
  frontier (mini-swe-agent >74% with 100 lines) → **scaffold depth is a per-tier dial,
  not a global choice** — ADOPT.
- Haiku 4.5 (verified): 73.3% Verified with bash + string-replace editing only —
  at this tier the leverage is output contract + validation gating, not task graphs.
- **Aider: per-tier edit-format contracts (whole-file → search/replace → diff) with
  mechanical retry; architect/editor split lifts o1-preview 79.7→85.0** — ADOPT.
- Agentless Lite: mechanical retrieval + format-validated retry = floor recipe — ADAPT.
- CodePlan: static analysis plans, LLM edits one location per call — 5/6 vs 0/6
  baselines on repo-wide migrations — ADAPT (per-host adapter tools).
- R2E-Gym: execution-based + execution-free verifiers saturate ~42% alone, 51%
  combined — pair execution evidence with static patch review — ADAPT.
- SWE-agent ACI: narrow per-step action vocabulary + per-step validation is what made
  2024-class models usable — ADOPT for weak tiers.
- METR/bitter-lesson counterweight: concentrate the moat in verification, maker≠checker,
  inspectable routing, cost arbitrage below frontier — NOT orchestration complexity — WATCH.

## Top-10 ranked imports

1. **Post-generation cascade as the routing kernel's algorithm** (cheap tier →
   deterministic verifier → escalate on fail).
2. **Tier-indexed decomposition dial** in the cortex (fixed pipeline sub-frontier,
   thin loop at frontier).
3. **Plan-boundary tiering + advisor escalation** (strong model holds plan/ambiguity/
   review; escalation by deterministic rule, never weak-model self-assessment).
4. **Declarative tier-policy artifact** (checked-in role/phase→tier YAML, CI-validated).
5. **Trace→skill distillation pipeline with authoring meta-skill guardrail**.
6. **ACE delta-update algebra for living playbooks** (into ESL drift).
7. **Single-writer invariant + read-only cheap scouts**.
8. **Per-tier edit-format contracts + architect/editor split**.
9. **Hardened dual verification gates** (execution + static review; verifiers outside
   executor write scope; maker≠checker at every cascade gate).
10. **Offline router evaluation + eval-gated downgrade procedure**.

(Íntegra of sources in agent transcript; key: cognition.com/blog/devin-fusion,
claude.com/blog/the-advisor-strategy, arXiv 2407.21787, 2407.01489, 2509.23045,
2510.04618, 2409.07429, 2504.07079, 2605.23899, 2502.00409, 2310.03094, 2403.12031.)
