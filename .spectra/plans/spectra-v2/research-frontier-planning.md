# Research — Frontier Planning Science, 2025-2026

> SPECTRA v2 campaign · gathered 2026-07-04 by an Opus survey agent, curated by Fable 5.
> Instruction to the agent was to surface contradictions of our own premise, not confirmation. It found two.
> Confidence: [HIGH] = numbers read from the paper; [MED] = via search snippet; [LOW] = aggregator claim.

## T1 — Do explicit plan scaffolds still help reasoning-era models?

- Plans still lift resolve rate, **but the benefit is model-dependent** — removing the plan cost DeepSeek-V3 23 SWE-agent instances, GPT-5-mini/Devstral barely moved (Plan Compliance in Autonomous Programming Agents, arXiv 2604.12147) [HIGH].
- **CONTRADICTION #1 — rigid/misaligned scaffolds actively hurt**: an incomplete plan (one phase removed) is worse than *no* plan; augmentation works "only when aligned with a model's internal strategy"; strong models override prescribed phase order; some SWE-bench issues resolved *only* in the no-plan setting (forced Reproduction phase caused failure loops); compliance drops 13% on harder tasks (same paper) [HIGH].
- Scaffold value scales inversely with model strength; heavy structure pays for weak/executor-tier models (Feedback-to-Plan 2605.26720; DIRECT 2606.12402; Agent-S3-style ablations ≈2× success for weak models) [MED].
- **Design implication**: phases must be mechanically right-sized and skippable-with-reason; scaffold *density* becomes a function of executing model tier. A mandatory fixed pipeline is now an evidenced failure mode.

## T2 — Plan verification & critics

- Generative "thinking" verifiers beat discriminative PRMs and LLM-as-judge on ~1% of the training labels (ThinkPRM, arXiv 2504.16828) [HIGH].
- Plan steps need **progress rewards**, not binary correctness (PRMs Meet Planning 2604.17957; AgentPRM, WebConf 2026) [MED].
- Judge debiasing is mandatory: position bias 10-15 pts, self-preference 10-25%; mitigations RBD, CalibraEval, IRT-on-judges (Judging the Judges, 2604.23178) [MED].
- **Spec-faithfulness degrades when the spec emerges incrementally**; external plan/spec state ("ProjectGuard") recovered 90% of the gap (SLUMP, arXiv 2603.17104) [HIGH].
- Design implication: ship a generative plan-critic gate with mechanical debiasing (position-swap, identity-strip — SPECTRA DR-11 anticipated this) + externally-tracked plan state + plan-vs-diff drift as a first-class metric.

## T3 — Multi-agent planning failures

- MAST (arXiv 2503.13657): Specification & System-Design failures 41.8%, Inter-Agent Misalignment 37%, Verification 21% over 1,600+ traces [HIGH].
- Role-spec fixes +9.4%, verification step +15.6% — necessary but insufficient; the decomposition itself must be right [MED].
- Hidden-profile/distributed-information: agents exchange but fail to integrate (pre-discussion accuracy 0.08-0.22); latent knowledge is nearly impossible to elicit passively (Elicitation Game 2502.02180) [MED].
- Design implication: the planner centralizes latent constraints; elicitation must be explicit and structured (validates DISCOVER, demands it be checklist/ontology-driven).

## T4 — Requirements elicitation + spec quality

- LLM interviewers under-elicit implicit requirements (ReqElicitGym 2602.18306; LLMREI 2507.02564) [MED].
- Ontology/checklist-guided interviewing is the emerging fix (2605.05828; follow-up question generation 2507.02858) [MED].
- EARS normalization + auto-inferred NFRs work as machine gates (ISO 25010-aligned NFR inference: median validity 5.0/5, 80.4% expert agreement; requirements-defect prediction 2601.01952) [MED].
- Design implication: DISCOVER/CLARIFY get a fixed probe ontology; requirements normalize to EARS and pass a mechanical defect/atomicity lint before planning.

## T5 — Measuring plans (not just Pass@1)

- Plan-adherence is now its own metric, decomposed Plan-Phase / Plan-Order / Plan-Fidelity (2604.12147); "generates a reasonable plan then deviates" is a named industry failure [MED].
- **Rubrics must be validated against outcomes before trust**: AdaRubric protocol requires AUC ≥ 0.8, Cohen's κ ≥ 0.75 vs manual outcomes (2603.21362) [MED].
- **Planning tokens have sharply diminishing returns past ~100 tokens**; early-stopping failed trajectories saves 28-64% tokens at 1.6-4.2pp cost (BAGEN 2606.00198); harness loop budgets dominate cost (Token Economics 2605.09104) [MED].
- Long-horizon benchmarks arriving (SWE Atlas 2605.08366, RoadmapBench 2605.15846) [LOW].
- Design implication: instrument adherence separately from quality; treat the 7-dim rubric as a *calibratable instrument* (log scores vs outcomes), cap default plan verbosity aggressively, budget the planning phase.

## T6 — Model-tier economics of planning

- **CONTRADICTION #2 — frontier-plans+cheap-executes is not a free lunch**: forced Opus-planner+Haiku-executor scored 90 vs solo Opus 97 at ~3× cost on a coupled task (AkitaOnRails benchmark, 2026-04) — coordination overhead + "planner must read every executor output" erased savings and cost quality [HIGH].
- Tiering pays **when executor subtasks are decoupled and quality-gated**: planner-Opus/executor-Haiku −57% execution spend at equal plan quality; cascade routing −13% cost and −5% error (Augment Code routing guide) [MED].
- **Sparse advisor beats mandatory delegation**: small agent calls the expert on ~11.9% of turns and unlocks strong performance (SWE-Protégé, arXiv 2602.22124) [MED].
- Cognition doctrine: weak models cannot self-detect their limits → escalation must be deterministic rules, never self-assessment [MED, prior v2.0 research, consistent].
- Design implication: the frontier model (Fable-class) holds plan/replan/verify **boundaries**; executors get heavy scaffold + low-ambiguity contracts (Aider's lesson); escalation encoded as data (routing.yaml), triggered by observable signals.

## Net verdict for the successor

The structured-planning premise **survives with corrections**: (a) right-size mechanically, phases skippable-with-reason, scaffold density ∝ 1/model-tier; (b) plan state lives externally with a drift metric; (c) plan quality is verified by a debiased generative critic that is not the plan's author; (d) elicitation is ontology-driven, not free-form; (e) rubrics are instruments to calibrate, not truths to assert; (f) tiering is applied at decoupled boundaries with deterministic escalation, not as a blanket planner/executor split.
