# Context Lifecycle Survey — Ingest (2026-07)

> Ingested from a three-cycle multi-stream survey (Streams A–E, evidence tiers S–D,
> coverage 2024-01 → 2026-07) on LLM session caching, KV cache compression, context
> compaction, session lifecycle management, and autonomous decision policies.
> This file is the nexus's *extraction*: the findings we act on, the layers we
> explicitly do not act on, and the survey's gap register mapped to ECM mechanisms.
> Companion spec: `docs/specs/ecm/spec.md`.

---

## Layer map — what the nexus can and cannot touch

The survey covers a seven-layer dependency stack. Eidolons is **host-mediated**
(Claude Code, Codex CLI, Copilot, Cursor, OpenCode): the bottom four layers belong
to providers and serving stacks and are *out of scope* for nexus tooling. They are
retained here because they explain **why** the top-layer contracts must look the
way they do.

| Layer | Examples | Nexus posture |
|---|---|---|
| Architectural | MLA (~75% KV reduction, DeepSeek V2+) | Observe only |
| Serving system | PagedAttention (SOSP'23), RadixAttention (SGLang) | Observe only; deployment note for junction sandbox loops |
| Cross-engine tier | LMCache (arXiv:2510.09665, 15× throughput), NVIDIA Dynamo | Observe only |
| KV compression | KVzip (NeurIPS'25 Oral), MiniKV (86% @ >98.5% acc), ChunkKV | Observe only — but its *failure modes* inform the pin-set contract |
| Provider API caching | Anthropic `cache_control` (0.10× reads), OpenAI auto, Gemini implicit, DeepSeek disk | **Act:** prefix-stability contract (ECM §cache-discipline) |
| Session management | Server-side compaction (Anthropic `compact-2026-01-12`, OpenAI `/responses/compact`), context editing, memory tool | **Act:** compaction triggers, externalize-before-compact, handoff (ECM core) |
| Agent policy | Utilization thresholds, cost heuristics — *no formal model exists* (Gap G1) | **Act:** mechanical decision table (ECM §policy) |

---

## Findings we act on

### F1 — Context rot is real, threshold-governed, and starts early [S/A-tier]

- Wang et al. (arXiv:2601.15300, 2026): open-model F1 collapses **45.5%** at
  **40–50% of max context** (Qwen2.5-7B, 0.55 → 0.30); five-method cross-validated.
- EMNLP Findings 2025: input length **alone** degrades performance **13.9–85%**
  across 5 models *even with perfect retrieval* and whitespace-only distractors.
- Chroma (18 frontier models, B/C-tier): every model degrades with context growth;
  past ~50% of window, degradation correlates with distance-from-end (recency bias).
- Claude Code's own auto-compact default is 95% of window, with 60–75% the
  recommended aggressive override range (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`).

**Taken:** ECM's zone ladder — GREEN < 50% / AMBER 50–75% / RED 75–90% /
CRITICAL ≥ 90%. Compact at RED, never wait for the host's 95% emergency floor.
The 50%-vs-77% source tension is resolved by scope: the 40–50% collapse is
open-model evidence; frontier hosts degrade more gracefully — so 50% opens the
*advisory* zone, 75% is the *mechanical* trigger.

### F2 — Lossy compression/compaction silently drops instructions [S-tier]

- Chen et al., ACL 2026 (arXiv:2510.00231): under multi-instruction prompting,
  KV eviction bias causes **certain instructions to be completely ignored**, and
  demonstrably leaks system-prompt content. Negligible-loss claims from
  single-instruction benchmarks do not transfer.
- Compaction is the application-layer analog of eviction: server-side compaction
  is lossy by design; exact tool arguments, file contents, identifiers are not
  guaranteed to survive.

**Taken:** ECM's **pin set** — a declared set of context elements (cortex digest,
refusal tables, ESL enforcement mode, tier map, active criteria SHAs) that must
survive every lossy operation verbatim, with post-op verification and repair by
re-injection. This is the same failure class ACL 2026 documents, addressed at the
layer we control.

### F3 — Identifiers must be externalized before compaction [B-tier, convergent]

- Anthropic + OpenAI docs and practitioner evidence converge: anything that must
  survive compaction exactly (paths, symbols, decision IDs, plan state) goes to
  persistent storage *before* the trigger — never trust the summary for exact recall.
- Anthropic's memory tool + context editing integration formalizes the pattern:
  warn-before-clear, write-to-memory, then clear.

**Taken:** ECM's **externalize-before-compact** contract, implemented on
CRYSTALIUM's existing surface (`plan_checkpoint` for execution state, `commit`
for episodic notes, `ingest` for ECL envelopes). Mandatory when crystalium is
installed; warn-and-degrade when absent.

### F4 — Prefix stability is the caching contract [S/A-tier]

- All four provider caches key on **exact prefix match** (Anthropic breakpoints,
  OpenAI/Gemini automatic, DeepSeek disk). Cache reads cost 0.10–0.50× base input;
  a stable 100k-token prefix is the single highest-ROI optimization (up to 90%
  input-cost and 85% latency reduction).
- LMCache production finding: **context truncation halves prefix-cache hit ratio**
  — the standard cost-control move (truncate from the front) directly defeats the
  standard efficiency move (prefix caching).

**Taken:** ECM's **cache-discipline** contract: stable-prefix ordering (cortex →
agent files → tool defs first; volatile injections appended last), never
truncate-from-front, byte-stable generated sections (the existing idempotency +
marker invariants already deliver this — ECM names *why* they are load-bearing),
short per-prompt injections to bound cache-miss cost.

### F5 — Server-side compaction has converged; triggers are configurable [B-tier]

- Anthropic beta `compact-2026-01-12`: configurable trigger (min 50k, default 150k),
  human-readable summary block, `pause_after_compaction` for inject-resume,
  custom instructions replace the default summary prompt. Known limitation: with
  tools defined, the model may tool-call during summarization — instructions must
  prohibit it.
- OpenAI `/responses/compact` + `context_management.compact_threshold`: opaque
  encrypted compaction item (not inspectable — a real operational difference).
- Claude Code: PreCompact hook fires before auto/manual compaction; auto-compact
  threshold overridable.

**Taken:** ECM triggers compaction *through the host's surface* (hooks, `/compact`,
API compaction where the harness is API-driven) and never re-implements it. The
PreCompact-class hook is where externalize-before-compact and pin re-injection
mechanize.

### F6 — Memory must be harness-injected, never model-requested [A/B-tier]

- Mem0 (platform-side automatic retrieval/injection) succeeds where
  Letta/MemGPT-class "agent remembers to call memory tools" fails — the same
  measured failure as our documentary cortex (DOSSIER-HARNESS-2026-06 §2).

**Taken:** the meter, the policy verdict, and the handoff recall are all
**hook-injected artifacts** computed by the deterministic kernel — never
capabilities the model must remember to request. This is why ECM's implementation
is kernel verbs + hook recipes first, MCP tools a distant optional second.

### F7 — Session lifecycle is a small closed operation set [B-tier, convergent]

Continue / prune tool results / compact / handoff-fresh / subagent-isolate /
graceful wrap-up. The survey's five-operation taxonomy plus budget ceiling
(`pause_after_compaction` + token counter) covers every observed production
pattern.

**Taken:** ECM's operation set is exactly this closed set — no open-ended
"context strategies."

### F8 — Repeated compaction fidelity is unstudied [Gap]

No S/A-tier study of 10+ compaction events exists; summary-of-summary loss is
hypothesized (survey §5.4 H2) but unmeasured.

**Taken:** ECM takes the conservative position: **compaction depth cap = 2**.
Beyond two compactions in one session, the only permitted lossy operation is
handoff-fresh (externalize → brief → new session), which resets summary depth
to zero with crystalium as the fidelity floor.

---

## Findings we observe but do not act on

- **KV compression families** (eviction / quantization / merge / sharing /
  head-pruning; MiniKV, KVzip, ChunkKV, ClusterAttn, DMS, AsymKV, FlowMM):
  provider/serving-layer concerns. Only their *pitfall literature* (F2) crosses
  into ECM.
- **MLA and serving-stack economics** (PagedAttention, RadixAttention, LMCache,
  CacheBlend, Dynamo): relevant only as a deployment note — self-hosted junction
  sandbox loops with repeated large prompts benefit from SGLang+LMCache-class
  serving; not spec surface.
- **Multi-tenant KV-sharing leakage** (NDSS 2025) and **DroidSpeak cross-model
  KV reuse**: serving-layer; noted in ECM's security considerations only as the
  adjacent failure class.

---

## Gap register → ECM mechanism map

| Survey gap | Survey status | ECM response |
|---|---|---|
| G1 — formal cache/compact/reset cost model | No S/A-tier work | **Mechanical decision table** over observable signals (ESL right-sizing doctrine: never LLM-discretionary). Not an optimization model — a deterministic policy with recorded provenance, auditable and revisable. |
| G2 — cross-session persistence quality | No S/A-tier work | **Handoff brief** (structured, ECL-enveloped, crystalium-ingested) + **round-trip canary** (successor session must recall the brief; measurable, CI-checkable). |
| G3 — compaction-boundary information leakage | No S/A-tier work | **Trust-tier preservation**: handoff briefs and compaction-survivor notes carry `contains_tool_origin` provenance when T3 content was in session scope; Dream's corroboration gate guards promotion; pins never include T3 content. |
| G4 — repeated-compaction fidelity | No S/A-tier work | **Depth cap = 2**, then handoff-fresh (F8). |
| G5 — leaked-material stream | Empty by absence | n/a |

---

## Key citations (carried into `references.bib` on promotion)

- Kwon et al., PagedAttention, SOSP 2023, arXiv:2309.06180 — [S]
- Chen et al., Pitfalls of KV Cache Compression, ACL 2026, arXiv:2510.00231 — [S]
- Wang et al., Intelligence Degradation in Long-Context LLMs, arXiv:2601.15300 — [A]
- Du et al., Context Length Alone Hurts LLM Performance, EMNLP Findings 2025 — [S]
- Kim et al., KVzip, NeurIPS 2025 Oral, arXiv:2505.23416 — [S]
- Liu et al., LMCache, arXiv:2510.09665 — [A]
- Yao et al., CacheBlend, EuroSys 2025 Best Paper, arXiv:2405.16444 — [S]
- Anthropic Platform Docs — compaction (`compact-2026-01-12`), context editing
  (`context-management-2025-06-27`), memory tool (`memory_20250818`), prompt
  caching — [B, first-party]
- OpenAI API Docs — `/responses/compact`, `context_management.compact_threshold` — [B, first-party]
- DOSSIER-HARNESS-2026-06 (internal) — hook-surface matrix, inject-by-default
  verdict, Mem0-vs-Letta memory-injection evidence — [internal, verified]

Full survey (all tiers, all six subdomains, methodology, banned-source register)
retained in the campaign records; this file is the actionable extraction.
