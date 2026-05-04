# EIDOLONS.md Cortex — Foundation Inventory

> Local-knowledge half of the foundation pair. Pairs with a separate
> frontier-research dossier. **Inventory, not design.**
> Generated 2026-05-03 against `roster/index.yaml` registry_version 1.0,
> updated_at 2026-05-03T15:58Z.

---

## 1. Roster Snapshot

| # | Eidolon | Version | Cycle | Capability class | Model tier¹ | Trigger verbs (skill cards) | Refuses | Hands off → |
|---|---------|---------|-------|------------------|-------------|---|---|---|
| 1 | **ATLAS** | 1.3.0 | A→T→L→A→S | scout | unspecified² | "map the repo", "what are the entrypoints", "build the call graph", "find where X happens", "trace Y", "who writes to Z", "who calls this", "what implements this" (`.claude/skills/atlas-traverse/SKILL.md:4`, `.claude/skills/atlas-locate/SKILL.md:4`) | writes, edits, commits, deploys (`methodology/prime-directives.md:43`) | spectra, apivr (lateral: forge, vigil) (`roster/index.yaml:60-61`) |
| 2 | **SPECTRA** | 4.2.10 | S→P→E→C→T→R→A | planner | unspecified² | "complex features", "multi-component change", "ambiguous requirements", "spec before implementation" (`.claude/skills/spectra-planning/SKILL.md:3`) | implementing code, modifying files (`methodology/prime-directives.md:42`, skill `:42`) | apivr (upstream: atlas; lateral: forge, vigil) (`roster/index.yaml:106-108`) |
| 3 | **APIVR-Δ** | 3.0.5 | A→P→I→V→Δ/R | coder | "sonnet" required (memory feedback `feedback_apivr_model`) | "implement", "build", "feature", "fix", "extend"; loads on non-trivial brownfield work (`.claude/skills/apivr-methodology/SKILL.md:3`) | planning from scratch, designing architecture (`methodology/prime-directives.md:41`) | idg (upstream: atlas, spectra; lateral: forge, vigil) (`roster/index.yaml:151-153`) |
| 4 | **IDG** | 1.1.5 | I→D→G | scriber | unspecified² | "document", "ADR", "runbook", "chronicle", "change-narrative" (inferred from `methodology/composition.md:26`, `idg-composition/SKILL.md`) | retrieving, analyzing code, researching (`methodology/prime-directives.md:43`) | (terminal — upstream: apivr, spectra, atlas) (`roster/index.yaml:198-199`) |
| 5 | **FORGE** | 1.2.1 | F→O→R→G→E | reasoner | unspecified² | "trade-off", "ambiguity", "counterfactual", "novel problem", "deliberate" (`roster/index.yaml:222`, `methodology/composition.md:16`) | retrieving, implementing, synthesizing prose (`methodology/prime-directives.md:44`) | none — lateral consultant for all (`roster/index.yaml:245-247`) |
| 6 | **VIGIL** | 1.0.3 | V→I→G→I→L | debugger | unspecified² | "flaky test", "regression", "heisenbug", "post-mortem", "root cause", forensic attribution (`roster/index.yaml:266`, `methodology/composition.md:28`) | building, planning, documenting (inferred from `methodology/composition.md:81`) | none — lateral specialist; emits `verified-patch.diff`, never auto-applies (`roster/index.yaml:288-291,298`) |

¹ `model:` is **not** a roster field today. It surfaces only in user-memory feedback (APIVR-Δ → sonnet) and in the "Note on harness" of the activation context for this very task. The cortex would be the place to fix this.
² `roster/index.yaml` does not declare a model tier per Eidolon. `methodology/prime-directives.md:162` explicitly forbids hard-coded vendor names — the cortex must speak in capability classes.

**Presets** (`roster/index.yaml:308-332`): `minimal`=[atlas]; `pipeline`=[atlas,spectra,apivr,idg]; `plan-and-build`=[spectra,apivr]; `full`=[atlas,spectra,apivr,idg,forge,vigil]; `research`=[atlas,idg]; `diagnostics`=[apivr,vigil,forge].

---

## 2. Capability Surfaces (per Eidolon, grounded)

### ATLAS — read-only codebase intelligence
- Phase T (Traverse) is **deterministic-only**: zero LLM during retrieval; symbol index, AST, ripgrep, `git log` (`atlas-traverse/SKILL.md:24`).
- Phase L (Locate) descends a five-tier probe ladder (symbol → graph → lexical → windowed read → dry run) with three-strike halt and `FINDING-XXX`/`GAP-XXX` records (`atlas-locate/SKILL.md:30-218`).
- Phase A (Abstract) does AgentFold compression to ≤2000-token summary in a clean-context subagent; mechanically validates that every `FINDING-XXX`, `GAP-XXX`, and `ESCALATION_TRIGGER` survives (`atlas-abstract/SKILL.md:34-138`).
- Phase S (Synthesize) emits ≤3000-token `scout-report.md` with handoff block to SPECTRA / APIVR-Δ / human / ATLAS (`atlas-synthesize/SKILL.md:46-167`).
- Persists to `.atlas/memex/` only; `writes_repo: false` (`roster/index.yaml:67-69`).

### SPECTRA — decision-ready specifications
- Triggers on complexity ≥7/12, multi-component, or ambiguous-requirement signals (`spectra-planning/SKILL.md:14-19`).
- Cycle: CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble (`spectra-planning/SKILL.md:23`).
- Output: dual-format spec (Markdown + YAML/JSON) — never code; rubric-scored, validation-gated, GIVEN/WHEN/THEN stories (`roster/index.yaml:83`, skill `:38`).
- Confidence <85% at Assemble forces return to Refine, **max 3 cycles** — bounded revision (skill `:42`).
- All output strictly under `.spectra/`; reads optional conventions file (`spectra-planning/SKILL.md:43,47`).

### APIVR-Δ — brownfield feature implementation
- Five phases: Analyze (memory recall + repo map + Discovery Report), Plan (Tree-of-Thoughts × 3-5 strategies, four-axis scoring), Implement (USE→EXTEND→WRAP→CREATE priority), Verify (lint+tests+coverage+build+types), then **Δ** (delta suggestions, output-only) or **R** (Reflect with bounded retry) (`apivr-methodology/SKILL.md`).
- Evidence Gate at Reflect: no concrete artifact → escalate (`apivr-failure-recovery/SKILL.md:14-27`).
- Retry budget: ≤3 same-category attempts; explicit loop-detection protocol (`apivr-failure-recovery/SKILL.md:154-210`).
- Persistent memory: `task-log`, `pattern-registry`, `failure-catalog`, `delta-history`, `session-handoff` with 30-entry caps (`apivr-memory-management/SKILL.md:16-23,141`).
- Only Eidolon with `writes_repo: true` (`roster/index.yaml:160`).

### IDG — documentation synthesis
- Section-level composition in topological order; per-section context budget cap ~2000 tokens (`idg-composition/SKILL.md:7-22`).
- Structural markers `[DECISION]/[ACTION]/[DISPUTED]/[GAP]` are mechanical, not paraphrased (`idg-composition/SKILL.md:36-76`).
- CHT verification (Completeness / Helpfulness / Truthfulness, 1-5 each); deliver if all ≥4, revise once if any 2-3, escalate if any =1 (`idg-verification/SKILL.md:69-86`).
- **Hard cap: one revision pass** (`idg-verification/SKILL.md:85`).
- `reads_repo: false` — pure synthesis from provided context, no retrieval (`roster/index.yaml:204-208`).

### FORGE — deep reasoning
- Stateless lateral consultant; called by any member or user; emits reasoning report with verdict + assumptions + confidence + alternatives (`methodology/composition.md:60-69,131`).
- No retrieval, no implementation, no synthesis (`methodology/prime-directives.md:44`).
- `reads_repo: false`, `persists: []` (`roster/index.yaml:251-255`).

### VIGIL — forensic root-cause attribution
- Reproduction-gated, counterfactual-verified, dependency-graph-ranked (`roster/index.yaml:266`).
- Five-intervention budget; emits `root-cause-report.md` + `verified-patch.diff` (sandbox authority — never auto-applies) (`methodology/composition.md:46-48,73-79`, `roster/index.yaml:298`).
- Failure-signature ledger soft-capped at 50 with recency-weighted consolidation (`methodology/composition.md:128`).
- Only invoked by APIVR-Δ escalation, user, or orchestrator — has no roster-declared upstream (`roster/index.yaml:288-291`).

---

## 3. Trigger Verb Taxonomy (grouped, sourced)

**Discovery / scouting verbs → ATLAS**
`map`, `traverse`, `find where`, `trace`, `who calls`, `who writes`, `what implements`, `list routes/workers/CLIs`, `audit (read-only)`, `build call graph`, `entrypoints` (`atlas-traverse/SKILL.md:4`, `atlas-locate/SKILL.md:4`).

**Spec / planning verbs → SPECTRA**
`spec`, `plan`, `decompose`, `clarify requirements`, `score strategies`, `decision-ready`, `GIVEN/WHEN/THEN`, "I need a spec before coding" (`spectra-planning/SKILL.md:3,14-19`).

**Implement verbs → APIVR-Δ**
`implement`, `build`, `add feature`, `fix`, `extend`, `wire up`, `refactor (in-scope)`, `make tests pass`, brownfield change requests (`apivr-methodology/SKILL.md:3`).

**Document verbs → IDG**
`document`, `write ADR`, `runbook`, `chronicle`, `change narrative`, `synthesize from artifacts`, `record decisions` (inferred from `methodology/composition.md:26`, `idg-composition/SKILL.md:38-76`).

**Decision / reasoning verbs → FORGE**
`trade-off`, `which approach`, `ambiguous`, `counterfactual`, `novel problem`, `deliberate`, `pros/cons with verdict` (`roster/index.yaml:222`, `methodology/composition.md:16`).

**Forensic / debug verbs → VIGIL**
`root cause`, `flaky`, `heisenbug`, `regression after X`, `post-mortem`, `why does this fail`, `attribute the fault`, "APIVR-Δ exhausted Reflect" (`roster/index.yaml:266`, `methodology/composition.md:28`).

**Note:** trigger phrases live in skill-card frontmatter (`when_to_use:`, `description:`), not in the roster. The cortex would either re-aggregate them or push them up into roster fields. `[GAP]` IDG/FORGE/VIGIL skill cards are not under `.claude/skills/` in this nexus checkout — only ATLAS, SPECTRA, and APIVR-Δ have local skill manifests; verbs above for IDG/FORGE/VIGIL come from methodology docs and roster summaries, not from a `when_to_use:` field.

---

## 4. Hand-off Graph (verbatim from `roster/index.yaml`)

Edges are **declared**, not inferred:

```
                 ┌────────────────────────────────────────────┐
                 │           lateral pool (called by any)     │
                 │   FORGE  ◀────────────────▶  VIGIL         │
                 └────────────────────────────────────────────┘
                       ▲                          ▲
                       │ lateral                  │ lateral
   ┌─────────┐    ┌─────────┐    ┌─────────┐   ┌─────────┐
   │  ATLAS  │ ─▶ │ SPECTRA │ ─▶ │ APIVR-Δ │ ─▶│   IDG   │
   └─────────┘    └─────────┘    └─────────┘   └─────────┘
        │              ▲              ▲             ▲
        └──────────────┘              │             │
        downstream: also direct       │             │
        ATLAS → APIVR-Δ               │             │
                                      └─upstream────┘
                                      idg.upstream: [apivr,spectra,atlas]
```

**Cycles:** None among the four-stage pipeline (ATLAS→SPECTRA→APIVR-Δ→IDG is acyclic). FORGE and VIGIL are lateral-only — their `upstream` and `downstream` arrays are empty (`roster/index.yaml:244-245,288-289`); the only "back-edges" are the consultation pattern, which composition.md describes as `→ FORGE → return to caller` (`methodology/composition.md:60-79`) — informationally a cycle, structurally a fan-out + fold.

**Gaps in the declared graph:**
- VIGIL → SPECTRA, VIGIL → IDG, VIGIL → FORGE edges exist in `composition.md:49-51` but are **not** declared in VIGIL's `roster/index.yaml` `downstream/lateral` (it lists laterals only).
- FORGE has no roster-declared destination; composition.md treats every member as a possible recipient (`composition.md:67-68`).
- ATLAS skips SPECTRA when emitting `→ APIVR-Δ` directly (`atlas-synthesize/SKILL.md:111`) — declared in `roster/index.yaml:60` (`downstream: [spectra, apivr]`), but the *handoff contract* and the conditions that justify the bypass are only in prose (`composition.md:42`).
- The "→ human" handoff label exists (`atlas-synthesize/SKILL.md:113`) but no Eidolon names humans as a roster downstream — humans are an implicit terminal.

---

## 5. Routing Mechanism Today (1 paragraph)

`cli/eidolons` is a string dispatcher (`cli/eidolons:84-133`). It pattern-matches the first argv against built-in verbs (`init|add|remove|sync|list|roster|doctor|verify|upgrade|mcp|version|help`); on miss, it shells out to `roster_list_names` and, if the token equals an Eidolon name, delegates to `cli/src/dispatch_eidolon.sh`, which looks for `./.eidolons/<eidolon>/commands/<sub>.sh` (or the `~/.eidolons/cache/<name>@<ver>/commands/` fallback). **That is the entirety of routing today.** It assumes the user already knows which Eidolon to invoke and which subcommand to call. There is no semantic router, no capability-class lookup, no confidence threshold, no fallback to "ask the team", no parallel fan-out, no model-tier negotiation. **What has no routing path today:** free-form natural-language prompts ("explore this repo and tell me what's risky"), prompts that span two capability classes ("scout *and* spec the auth refactor"), prompts whose right tier is unclear ("is this an ATLAS L-probe or an APIVR-Δ analyze?"), and any prompt arriving through a host (Claude Code, Cursor) without going through `cli/eidolons` at all — which is most of them. The CLI is roster-aware; the host conversation is not.

---

## 6. Capability Gaps (concrete examples of mis-routing today)

| Incoming prompt | Today's likely fate | Why the gap |
|---|---|---|
| "Explore the auth flow and propose a fix" | Either ATLAS alone (no plan emitted) or APIVR-Δ alone (skips Discovery → re-explores) | Spans scout + plan + build; no router escalates to chained pipeline |
| "Add a `--json` flag to `eidolons doctor`" | Could land on SPECTRA (over-spec) or APIVR-Δ (skip plan) | Complexity is borderline (≤7/12 per `spectra-planning/SKILL.md:14`) — no rubric is run |
| "Why is this test flaky?" | APIVR-Δ if invoked first, then 3-attempt loop, then escalate to VIGIL | VIGIL invocation is described as escalation-only (`methodology/composition.md:28`) — there is no fast-path for a user who already knows it's a heisenbug |
| "Document what we just built" | IDG, but only if the user names IDG explicitly | Free-form "document this" has no dispatch entry |
| "Two patterns apply here — which?" mid-task | Currently in-Eidolon FORGE consult (`composition.md:64`) — but the user prompt arriving cold has no FORGE entrypoint | FORGE is consultation-only in roster (`upstream: []` `roster/index.yaml:244`) |
| "Refactor the cortex of the eidolons codebase" (this task) | Falls through to whichever skill the host happens to load — there is no orchestrator | The exact prompt class EIDOLONS.md is being written to handle |
| Prompts in non-installed-Eidolon territory ("trace this in a project where only `minimal` preset is installed") | Silent capability cliff | Partial-team deployment is first-class (`methodology/composition.md:86-107`) but the cortex must reason about availability |
| Cross-Eidolon ambiguity: "find and fix" | Hard to split: ATLAS→APIVR-Δ direct edge exists (`roster/index.yaml:60`) but the chunking is human work | No cortex policy on when ATLAS hands directly to APIVR-Δ vs through SPECTRA |

---

## 7. Harness Affordances Inventory

What the Claude Code harness exposes that an TRANCE tier *could* leverage. Most are **not** in current roster declarations:

| Affordance | Mechanism | Current usage in roster | Plausible TRANCE consumer |
|---|---|---|---|
| **Parallel agent fanout** (single message, multiple Agent calls) | Tool-call concurrency | ATLAS Locate "scatter subagents" (`atlas-locate/SKILL.md:94-141`) — only documented case | SPECTRA generating 3-5 strategies in parallel; FORGE running adversarial-pair deliberation; VIGIL fanning out counterfactuals |
| **`isolation: "worktree"`** | Per-agent git worktree | Memory feedback flags collision risk (`feedback_parallel_agents_same_repo`) | APIVR-Δ when implementing; VIGIL when patching — both write `.diff`s |
| **Model overrides** (sonnet/opus/haiku) | Per-agent `model:` field | Only APIVR-Δ has a memory-recorded constraint (`feedback_apivr_model` → sonnet); roster has no `model:` field | FORGE → opus (deep reasoning); SPECTRA → opus on complexity ≥7; ATLAS T → haiku/speed-class (deterministic); VIGIL → opus on counterfactual gen |
| **Background agents** (`run_in_background`) | Long-running with poll | Not used | ATLAS large-repo Memex builds; APIVR-Δ test suites; VIGIL bisects |
| **Hooks** (pre/post-tool, pre/post-prompt) | Harness lifecycle | Not used in nexus | Marker-bounded section guards; idempotency pre-flight; refusal-boundary checks |
| **MCP servers** | Tool surface | `eidolons mcp atlas-aci` scaffolds Atlas-ACI sqlite codegraph (`docs/architecture.md:161-163`) | Other Eidolons gaining MCP tools — IDG markdown linter, VIGIL trace-ingest |
| **Slash-skills / progressive disclosure** | `.claude/skills/<name>/SKILL.md` with frontmatter `when_to_use:` | ATLAS (4 phase skills), SPECTRA (1), APIVR-Δ (4) — IDG/FORGE/VIGIL absent locally | Cortex itself as a skill; per-Eidolon trigger-card harvest |
| **Memory across conversations** | `~/.claude/projects/.../MEMORY.md` etc. | User-level memory exists (`feedback_*`); APIVR-Δ has its own `.eidolons/apivr/memories/` | Cortex routing-decision history; TRANCE escalation log |
| **Subagent spawn with clean context** | Documented in `atlas-abstract/SKILL.md:46-58` | ATLAS Abstract phase | SPECTRA Refine; FORGE adversarial-pair; VIGIL Locate-style probes |
| **Structured outputs / JSON Schema** | Schemas at `schemas/*.json`, validated in CI | Roster + manifests | Routing decisions emitted as structured artifacts (auditable) |

---

## 8. Open Questions for the Research Agent

Specific, scoped, answerable from peer-reviewed / frontier-lab literature:

1. **Single-router vs hierarchical-router** for fixed rosters of ≤10 specialists with declared capability classes — which has lower routing error and what's the crossover roster size?
2. **Confidence thresholds for TRANCE escalation** — what published values for cascade systems (e.g., SCoRe, Routing Bandits, FrugalGPT-style) trigger escalation from base to high-capability tier? Numeric ranges, not directional.
3. **Ensemble / parallel deliberation** — is N=2 adversarial pair, N=3 majority, or N=5 best-of-N the empirically dominant pattern for plan-class tasks? At what task complexity does the gain plateau?
4. **Verbal-confidence calibration of LLMs** — how reliable is a model's self-reported confidence as the routing signal vs an external scorer? (Anthropic, OpenAI, DeepMind reports as of 2025-2026.)
5. **Refusal-as-routing** — do production systems treat an Eidolon's hard refusal as a router signal (re-route to capable peer), or as a stop? Evidence either direction.
6. **Hand-off contract formalisms** — are there published schemas for inter-agent artifact validation (LangGraph, AutoGen, CrewAI, Microsoft Agents) whose properties the Eidolons handoff contracts should align with?
7. **Routing under partial-team deployment** — how do published systems degrade gracefully when a target specialist is unavailable? (Fallback chains, capability subsetting, refuse-with-explanation.)
8. **Cost-aware routing** — is there a settled cost model that justifies opus-for-FORGE vs sonnet-for-APIVR-Δ vs haiku-for-ATLAS-Traverse, or is this still folkloric?
9. **Memory across routers** — research on whether the *router* should accumulate routing-decision memory (improves with use) or remain stateless (reproducible). Trade-offs.
10. **Multi-turn vs single-shot routing** — does literature support the cortex itself running an internal cycle (think → score → route) vs emitting a single-shot dispatch? Cite empirical comparisons.
11. **Self-reflection bound** — given prime directive D5 ("bounded self-correction"), what's the published optimum for the cortex's own re-routing budget? CorrectBench (`MANIFESTO.md:41`) is one anchor; what others?
12. **TRANCE-tier definition prior art** — are there published "tier-2 / escalation" agent designs (e.g., Anthropic's harness work, GPT-4o orchestration patterns) the cortex should mirror or deliberately diverge from?

---

## 9. Invariants the Cortex MUST Preserve

Non-negotiable. Pulled directly from the source documents.

1. **Marker-bounded sections** when writing into shared host files (`AGENTS.md`, `CLAUDE.md`, copilot instructions). Markers `<!-- eidolon:<name> start --> … <!-- eidolon:<name> end -->`. `eidolons remove` depends on these. (`CLAUDE.md` "Key invariants", `docs/architecture.md:119`, `spectra-conventions.md:11`.)
2. **No code execution from `eidolons.yaml`.** `yaml → jq query → bash exec` only. No `eval`. (`CLAUDE.md` "Key invariants", `docs/architecture.md:159`.)
3. **EIIS conformance** for any new Eidolon admitted to the cortex's routable set. The cortex routes only to roster members (`roster/index.yaml`); new members go through EIIS first. (`docs/architecture.md:11-22`, `methodology/prime-directives.md:5`.)
4. **Hand-off contracts are structured artifacts on disk.** Working-set tokens stay bounded across the pipeline; downstream parses structured data, not prose; provenance travels. (`methodology/composition.md:54-58`.)
5. **Hard refusals are P0.** ATLAS won't write (`methodology/prime-directives.md:43`), SPECTRA won't implement (`:42`), IDG won't research (`:43`), FORGE won't tool-call/synthesize prose (`:44`), VIGIL won't auto-apply patches (`roster/index.yaml:298`). The cortex must **never** override a refusal — it must re-route.
6. **Idempotency of CLI surface.** `eidolons sync` and `install.sh` produce identical output on repeat runs unless roster/manifest changed. The cortex, if it persists routing decisions, must do so idempotently. (`CLAUDE.md` "Key invariants", `docs/architecture.md:117`, `spectra-conventions.md:93`.)
7. **Bash 3.2 compatibility** for any `cli/src/*.sh` or `cli/install.sh` the cortex touches. No bash-4 features. (`CLAUDE.md` "Bash 3.2 compatibility", `spectra-conventions.md:91`.)
8. **All log output via `say/ok/info/warn/die` goes to stderr.** Stdout is reserved for captured values (e.g., `fetch_eidolon` returns the cache path). The cortex's logs must follow. (`CLAUDE.md` "CLI architecture", `spectra-conventions.md:92`.)
9. **No vendor-name hardcoding** in methodology. Capability classes only — reasoning-class, speed-class — never "claude-3-5-sonnet". (`methodology/prime-directives.md:162`.)
10. **Install target is `./.eidolons/<member>/`** (dot-prefixed, hidden). Cortex artifacts that mirror per-Eidolon state must respect this. (`CLAUDE.md` "Key invariants", `spectra-conventions.md:96`.)
11. **Bounded revision** — every Eidolon has a fixed verification gate and bounded budget (D5, `methodology/prime-directives.md:82-91`). The cortex must not re-route around a bounded budget by spawning fresh siblings indefinitely.
12. **Working-set tokens** — entry points cap ≤900 tokens, target ≤3500 (`methodology/prime-directives.md:27`, roster `working_set_tokens` per member). The cortex itself, if always-loaded, lives under the same budget; it cannot become the next monolithic system prompt the manifesto explicitly refuses (`MANIFESTO.md:39`).
13. **Per-Eidolon `install.sh` writes only to cwd**, never to `$EIDOLONS_HOME`. The cortex, as a nexus-level concept, may write to `$EIDOLONS_HOME`; downstream Eidolon installers never get that authority. (`docs/architecture.md:148-156`, `spectra-conventions.md:99`.)
14. **Roster is the source of truth** for who exists, where, and at what version. The cortex reads `roster/index.yaml` — it does not re-implement membership. (`docs/architecture.md:39-49`, `spectra-conventions.md:12`.)
15. **`[GAP]` and `[DISPUTED]` over silent merge** when sources conflict — including in routing decisions where the right Eidolon is genuinely ambiguous. (`methodology/prime-directives.md:117-118`, `MANIFESTO.md:57`.)

---

*End of foundation. Pairs with the frontier-research dossier produced by the parallel research agent. Final EIDOLONS.md is downstream of both.*
