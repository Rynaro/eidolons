# v2.0 Research — Verification & Memory as Multipliers for Weak-Model Teams (2026-07-02)

> Fan-out research agent deliverable, persisted verbatim (light formatting only).
> Sources verified by direct fetch are marked (fetched); search-snippet-only marked
> (snippet); unverifiable claims marked UNVERIFIED.

## 1. Fresh-context verification patterns

**1.1 Cross-Context Review (CCR)** (fetched) — reviewing an artifact in a separate
session with no access to production history beat same-session self-review (F1 28.6% vs
24.6%, p=0.008); re-reviewing twice in-session did NO better (21.7%); even a subagent
WITH production context underperformed (23.8%). Context separation itself is the active
ingredient. Caveats: small (30 artifacts/360 reviews), single author.
https://arxiv.org/abs/2603.12123 — **ADOPT NOW**: make "fresh context, no maker
transcript" a hard ESL verify-envelope requirement. Zero infra cost.

**1.2 Anthropic Claude Code Review** (fetched) — parallel specialized finders + a
verification step that checks candidates against actual code behavior to filter false
positives; findings carry file:line + how-verified; machine-readable severity JSON for CI
gating. (InfoQ: <1% findings incorrect — UNVERIFIED.)
https://code.claude.com/docs/en/code-review — **ADAPT**: finders + disprover shape as
Eidolon protocol; managed fleet not adoptable.

**1.3 Self-correction literature** — intrinsic self-correction still fails (Huang ICLR
2024; Kamoi 2024); 2026 decomposition result: models fail to correct errors in their OWN
outputs while successfully correcting identical errors presented as EXTERNAL input.
https://arxiv.org/pdf/2310.01798 · /2406.01297 · /2601.00828 — **ADOPT NOW (axiom)**:
maker≠checker across sessions unlocks correction ability self-review cannot access.

**1.4 The Verification Horizon** (fetched) — verification is the bottleneck; every
verifier is a proxy; push verification into the mechanically checkable regime; weak-to-
strong supervision works exactly where checks are objective and cheap.
https://arxiv.org/pdf/2606.26300 — **ADOPT (framing)**.

**1.5 OpenHands critic** — k=5 rollouts filtered by regression+reproduction tests, then
trained 32B critic (60.6→66.4 SWE-bench Verified).
https://www.openhands.dev/blog/sota-on-swe-bench-verified-with-inference-time-scaling-and-critic-model
— **ADAPT**: import mechanical test-filter stage; reject trained critic (no fine-tuning).

**1.6 Debate panels** — outperform static ensembles (NeurIPS 2025) BUT "Deliberative
Illusion" (2026) documents factual attrition + stance homogenization.
https://arxiv.org/pdf/2510.12697 · /2606.03032 — **REJECT for v2.0** (single fresh
disprover captures most value); WATCH for high-stakes gates.

**1.7 Anthropic multi-agent research system** — orchestrator + fresh-context workers +
SEPARATE citation pass; multi-agent +90.2% vs single-agent on internal eval.
https://www.anthropic.com/engineering/multi-agent-research-system — **ADAPT** (separate
verification pass as own chain step).

**1.8 CI-as-verifier + reward hacking** — trust deterministic CI, never self-report; but
agents tamper (delete tests, monkey-patch). Anti-tamper ratchet needed.
https://www.faros.ai/blog/harness-engineering · arxiv 2606.16062 · 2606.08960 —
**ADOPT NOW**: verifier confirms test-file hashes/count didn't regress vs baseline
(trivial bash + sha256, fits ECL integrity model).

## 2. Claim-evidence / provenance

**2.1 REVIEW.md verification bar** (fetched) — behavior claims need file:line citation,
not naming-inference. https://code.claude.com/docs/en/code-review — **ADOPT NOW**:
mechanically checkable afterward; fits ECL payload rules.

**2.2 From Fluent to Verifiable** (fetched) — claim-level metrics: Provenance Coverage,
Provenance Soundness, Contradiction Transparency, Audit Effort; gate unverified claims
from downstream. Deep-research citation accuracy only 40-80%.
https://arxiv.org/html/2602.13855 — **ADAPT**: import metrics (PCov computable by bash
checker over sidecar); reject full graphs.

**2.3 Agent Traces to Trust survey** (fetched) — claim-granularity attribution; closed
relation vocabulary (Support/Contradict/Invalidate/Trigger/Update).
https://arxiv.org/html/2606.04990v3 — **ADAPT**: closed enum for claim-evidence sidecar,
mirrors ECL closed-performative philosophy.

**2.4 KnowsRecord** — schema-validated YAML claims+evidence+provenance.
https://arxiv.org/html/2604.17309v1 — **WATCH** (vocabulary donor).

**2.5 OTel GenAI conventions** — still experimental mid-2026.
— **WATCH (adopt names only)**: keep ECL JSONL trace fields OTel-mappable.

**2.6 Pramana** — protocol-layer claim verification. arxiv 2605.20312 — **WATCH**
(read before ECL 1.1).

## 3. Memory architectures

**3.1 Retrieval quality dominates write strategy** (fetched) — retrieval method spans
20 accuracy points; write strategy 3-8; raw chunks + hybrid retrieval beat LLM-processed
writes (81.1%); retrieval precision r=0.98 with downstream accuracy.
https://arxiv.org/html/2603.02473v1 — **ADOPT NOW (crystalium investment guidance)**:
store raw+cheap, invest in recall ranking, skip write-time distillation.

**3.2 Four memory types, separated** — Letta/Zep/Mem0/LangMem all converge on working/
episodic/semantic/procedural, with distinct decay/versioning.
— **ADOPT taxonomy; REJECT vendors as dependencies.**

**3.3 Injected vs agent-initiated recall: evidence MIXED → hybrid.** 2026 benchmarks
favor tool-based recall (agent knows more at decision time); PROACTAGENT's proactive
gains need RL; shipping pattern (Letta blocks, Claude Code MEMORY.md ≤200-line index) is
two-tier. — **ADOPT hybrid: tiny always-injected index + on-demand recall tools.**
"Injection beats recall" outright: UNVERIFIED.

**3.4 Experience Compression Spectrum** (fetched) — L0 raw trace → L1 episodic summary
(5-20×) → L2 procedural skill (50-500×) → L3 rule (1000×+); promote at k similar
episodes; VALIDATE promoted skills on held-out tasks before replacing sources (no system
implements this); L2 skills beat L1 trajectory retrieval +68.5pp (SkillRL).
https://arxiv.org/html/2604.15877v1 — **ADOPT (design)**: the missing spec for
crystalium's episode→skill pipeline.

**3.5 Letta sleep-time compute** (fetched docs) — background consolidation during idle.
https://docs.letta.com/guides/agents/architectures/sleeptime/ — **ADAPT** as batch
`consolidate` command at session end/cron, where 3.4 promotion executes.

**3.6 Zep/Graphiti bi-temporal facts** — validity intervals, non-destructive
invalidation. https://arxiv.org/abs/2501.13956 — **WATCH; adopt bi-temporal
invalidation idea** (cheap in flat files; prevents weak models acting on stale memory).

**3.7 Git-native memory** — Beads: JSONL in .beads/, git-backed, branch-follows-code,
append-safe merges; ADRs as typed memory records.
https://github.com/gastownhall/beads — **ADAPT storage doctrine; WATCH indexers.**

## 4. Checkpointing / recovery / forensics

**4.1 Durable execution = journal-replay or state checkpointing** (Temporal/LangGraph/
Pydantic/OpenAI SDK). — **REJECT infra / ADAPT mechanism**: JSONL step journal +
"skip already-journaled steps" = 80% of durable execution in pure files; journal doubles
as ECL trace.

**4.2 Who&When failure attribution (ICML 2025 Spotlight)** — best methods find culprit
agent 53.5%, culprit STEP only 14.2%; post-hoc attribution effectively unsolved.
https://arxiv.org/abs/2505.00212 — **ADOPT NOW (implication)**: verification gates
BETWEEN steps localize failure at commit time; the strongest external justification for
ESL per-transition gates + ECL per-handoff envelopes.

**4.3 Time-travel replay** (LangGraph/LangSmith/Langfuse) — **ADAPT**: plan_checkpoint/
plan_replan + step journal already form checkpoints; add resume-from-checkpoint CLI verb.

**4.4 Beads existence proof** — file-based beats infra; "tool does the topological
thinking, agent gets only the ready list" — directly stealable for weak-model planning.
— **ADOPT pattern.**

**4.5 ACRFence** — semantic rollback attacks on checkpoint-restore. arxiv 2603.20625 —
**WATCH**: chain checkpoint hashes if v2.0 adds resume.

## 5. Making success legible to weak verifiers

**5.1 GitHub Spec Kit** (fetched) — acceptance checks part of the spec, written before
work; Phase -1 gates; `[NEEDS CLARIFICATION]` must be zero (grep-checkable); contract
tests exist before implementation (ls-checkable). Adopter "3-10×" claims UNVERIFIED.
https://github.com/github/spec-kit — **ADAPT gate mechanics; reject full SDD
regeneration doctrine.**

**5.2 EARS notation (Kiro)** — five fixed sentence templates ("WHEN <trigger> THE
SYSTEM SHALL <response>") make criteria mechanically parseable, 1:1 mappable to tests.
https://kiro.dev/blog/introducing-kiro/ — **ADOPT NOW**: closed template grammar =
same design move as ECL's closed performative set.

**5.3 Machine-readable verdicts** (fetched) — verifier emits severity JSON parseable by
gh+jq to gate merges. — **ADOPT NOW**: every V-gate emits structured verdict file.

**5.4 Weak-to-strong supervision** — works where verification is objective and cheap;
rubric/judge verification degrades under optimization pressure. (2606.26300) —
**ADOPT (thesis-level)**: the academic form of the v2.0 goal.

**5.5 Test quality needs verification** — weak/incomplete suites are the main leak.
— **ADAPT**: acceptance artifact hash-frozen at plan time; verifier confirms frozen
checks ran unmodified.

## Top-10 ranked imports

1. Fresh-context maker≠checker as protocol invariant (checker gets artifact + sidecar
   only, never maker transcript) — best evidence-per-cost in report.
2. Executable acceptance criteria frozen before work (EARS + checks script,
   SHA-256-frozen in ECL envelope; verify = re-hash + run).
3. Claim→evidence bar on every artifact (file:line/hash/URL sidecar; bash checker
   computes Provenance Coverage; unverified claims gated from downstream).
4. Verifier-as-disprover, not panels.
5. Structured verdict artifacts from every gate (JSON, jq-consumable).
6. Retrieval-first crystalium (raw cheap writes; invest in recall ranking).
7. Two-tier recall: tiny always-injected index + on-demand recall tools.
8. Mechanical episode→skill promotion with validation gate (k-occurrence trigger,
   held-out validation, provenance links; runs in batch consolidation).
9. JSONL step journal + resume rule instead of durable-execution infra (chained
   checkpoint hashes).
10. Design-for-attribution rationale for per-step gates (Who&When: 14.2% post-hoc step
    accuracy — gate at write time instead).

## Sources

(Full list preserved from agent report — see arxiv/vendor links inline above.)
