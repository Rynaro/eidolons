# Production Patterns

> Evidence from shipped AI coding tools. How the Eidolons borrow, where they diverge.

Not every design decision traces to a paper. Some of the strongest evidence comes from observing what works — and what doesn't — in production systems. This document captures that evidence.

---

## Claude Code

**Source:** Anthropic's IDE-embedded coding agent. Native skills + subagents + MCP.

**Patterns adopted:**
- **Plan Mode** — a read-only mode that produces a plan before any mutation. SPECTRA is a more opinionated, portable version of this.
- **Skills** — filesystem-based, activated by description-matching. Every Eidolon's `skills/<phase>/SKILL.md` follows this convention.
- **Subagents** — ephemeral child contexts that return one structured finding. ATLAS uses this for scatter-gather on independent sub-questions.
- **MCP** (Model Context Protocol) — standardized tool interface. `atlas-aci` is an MCP server.

**Where we diverge:** Claude Code's Plan Mode lives inside the host. SPECTRA is portable — runs in any host, produces an artifact that any implementer can consume. Skills in Claude Code are activated by the model; in EIIS they're triggered by declared phase transitions, removing ambiguity.

---

## Cursor

**Source:** Cursor's coding agent with `.cursor/rules/*.mdc` MDC rules and `AGENTS.md` support.

**Patterns adopted:**
- **MDC format** — Markdown with YAML frontmatter, `description:` + `globs:` + `alwaysApply:` fields. Each Eidolon ships `.cursor/rules/<n>.mdc` wrappers.
- **`AGENTS.md` open standard** — a vendor-neutral rules file at repo root. EIIS mandates this.
- **Agent-requested skills** — Cursor decides which rule to apply based on description. Eidolons rely on this for phase-specific skill activation.

**Where we diverge:** Cursor's rules are flat files; Eidolons layer them — entry point → skill → template. The MDC wrapper is a thin adapter pointing at the canonical `skills/<phase>/SKILL.md`.

---

## GitHub Copilot

**Source:** GitHub's AI pair programmer with Agent Mode, `.github/copilot-instructions.md`, and custom agents.

**Patterns adopted:**
- **`.github/copilot-instructions.md`** — repo-level instructions that Copilot auto-discovers.
- **Custom agents** — `.github/agents/*.agent.md` with frontmatter declaring tools and methodology.
- **`AGENTS.md` recognition** — modern Copilot hosts honor the open standard.

**Where we diverge:** Copilot's context window is typically smaller than Claude Code's. Eidolons' ≤3,500-token working-set target is driven partly by this constraint. Copilot also lacks Anthropic's skill-loading mechanism in some hosts — our skills are loaded by explicit instruction in the chat rather than by the model choosing autonomously.

---

## Aider

**Source:** Terminal-based pair programming tool. Paul Gauthier.

**Patterns adopted:**
- **File-aware editing** — the agent maintains an explicit mental model of which files are in context.
- **Test-driven repair** — when a change breaks tests, the agent iterates with the test output as ground truth. APIVR-Δ's Verify phase mirrors this.
- **Git integration** — every change is a commit; history is the state. Eidolons embrace this.

**Where we diverge:** Aider is a single-agent tool. Eidolons split planning, implementing, and chronicling across separate members — Aider's loop would be APIVR-Δ's Implement/Verify/Reflect only.

---

## OpenCode

**Source:** Open-source coding agent with permission-scoped subagents.

**Patterns adopted:**
- **Permission system** — per-subagent `permission:` block in YAML frontmatter (`edit: deny`, `write: deny`, `bash: "pattern": allow|ask|deny`).
- **Custom agents** in `.opencode/agents/*.md` — EIIS includes OpenCode wiring docs.

**Where we diverge:** OpenCode's permissions are per-subagent; Eidolons' mechanical invariants are per-Eidolon. The unified pattern: refuse at the tool-surface layer, not at the prompt layer.

---

## DocAgent

**Source:** Meta/FAIR research (arXiv 2504.08725). Multi-role documentation generation system.

**Patterns adopted:**
- **CHT verification** — Completeness, Helpfulness, Truthfulness. IDG's Gate phase implements exactly this triple.
- **Topological ordering** — write dependencies before dependents. IDG's skeleton phase respects this.
- **Multi-role pipeline** — Reader, Searcher, Writer, Verifier, Orchestrator.

**Where we diverge:** DocAgent's pipeline is internal to one agent. IDG is *just* the Writer+Verifier. Reading and searching belong to ATLAS; orchestration belongs to the consumer of the pipeline, not the agent.

---

## SWE-Agent

**Source:** Yang et al., NeurIPS 2024. Agent-Computer Interface design for software engineering.

**Patterns adopted:**
- **Bounded ACI** — narrow tool surface, mechanical bounds (line caps, match caps). ATLAS's 7-tool surface is direct descendant.
- **Evidence anchoring** — outputs cite line ranges. ATLAS and APIVR-Δ require this.
- **Tool-design over prompt-design** — invariants enforced by the tool, not the prompt.

**Where we diverge:** SWE-Agent is one monolithic agent with mixed read/write capability. Eidolons split this: ATLAS is read-only, APIVR-Δ has write capability, and the separation is mechanical (different tool surfaces).

---

## Cross-cutting observations

Patterns that appear in *many* production systems, therefore high-confidence:

### Narrow tool surface > wide tool surface
Aider, SWE-Agent, Claude Code, ATLAS all converge on <10 core tools. Wide surfaces produce unreliable tool selection.

### Read/write split
Claude Code Plan Mode (read), OpenCode permissions (per-subagent), ATLAS (all-read) — the industry is moving toward explicit read/write boundaries.

### Progressive disclosure of instructions
Claude Code skills, Cursor MDC rules, EIIS layered loading — none of the successful systems load everything upfront. The monolithic-prompt approach is mostly extinct in production tooling.

### Handoff artifacts over handoff messages
DocAgent, SWE-Agent, APIVR-Δ all produce structured artifacts at phase boundaries rather than passing free-form messages. Machine-parseable beats prose.

### Bounded loops
Every shipped system with reflection has a stop condition. Unbounded loops are a research-paper artifact, not a production pattern.

---

## Anti-patterns observed

What we see and consciously avoid:

- **"Helpful assistant" generalists** — one system prompt trying to do everything. Degrades with context size.
- **Hidden state across sessions** — agents that can't explain where their decisions come from.
- **Tool explosion** — "let's add another tool for this edge case" until the model can't reliably pick the right one.
- **Prompt-level invariants** — "please don't edit files without permission" without any tool-surface enforcement. These leak under pressure.
- **Implicit handoffs** — the agent deciding when to escalate without structured criteria. Becomes unpredictable.

---

## Status

This document starts from observation. As the Eidolons evolve and we ship more canary evaluations, we'll add:

- Quantitative comparisons (pass rates, token efficiency) between Eidolons and their nearest production analog
- A "what changed our mind" section when a pattern we adopted turns out to have weaknesses
- Links to blog posts, conference talks, and production post-mortems that shaped specific decisions

Contributions welcome — patterns must come with a source (link, repo, paper) and a concrete observation of what works or fails.
