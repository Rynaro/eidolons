# Research Library

> The evidence base for the Eidolons team. Papers, production patterns, citations.

Every design decision in every Eidolon traces back to something in this library. This is the nexus's aggregation of what was previously scattered across five separate `DESIGN-RATIONALE.md` files.

---

## Structure

| File | Contents |
|------|----------|
| [`references.bib`](references.bib) | BibTeX file — every paper we cite, properly formatted |
| [`production-patterns.md`](production-patterns.md) | Non-paper evidence — documented patterns from Claude Code, Cursor, Aider, DocAgent, SWE-Agent, etc. |
| [`papers/`](papers/) | One Markdown summary per paper — what it says, what we took from it, which Eidolon uses it |

---

## Research → Eidolon mapping

This is the inverse index. Given an Eidolon, which research backs it?

### ATLAS (Scout)

- **AgentFold** — phase-boundary context compaction → ATLAS's AgentFold at phase boundaries
- **Scatter-gather subagents** — operator pattern → ATLAS's subagent fan-out for independent sub-questions
- **Bounded ACI** — Aider, Claude Code read primitives → ATLAS's 7-tool read-only surface
- **Evidence anchoring** — SWE-Agent, DocAgent → ATLAS's `path:line` + confidence tier

### SPECTRA (Planner)

- **Plan-mode agents** — Claude Code Plan Mode, Cursor Plan → SPECTRA's Explore phase
- **Decision theory** — classical MAUT scoring → SPECTRA's scoring rubrics
- **Information theory** — entropy-based validation → SPECTRA's 6-layer validation

### APIVR-Δ (Coder)

- **CorrectBench 2025** — evidence for bounded self-correction → APIVR-Δ's 3-attempt cap on Reflect
- **Reflexion** — verbal reinforcement learning → the Reflect phase itself (but bounded)
- **SWE-Agent** — tool design for software engineering → APIVR-Δ's tool surface
- **Context engineering** (Anthropic, Sept 2025) → layered loading

### IDG (Scriber)

- **DocAgent (Meta/FAIR, arXiv 2504.08725)** — CHT verification framework → IDG's Gate phase
- **Topological ordering of documentation dependencies** → IDG's skeleton-first drafting

### FORGE (Reasoner — in construction)

- TBD — candidates: **Chain-of-Thought**, **Tree-of-Thoughts**, **Self-Consistency**, **Debate**, **Counterfactual reasoning** literature

---

## Cross-cutting themes

Patterns that appear in multiple Eidolons:

### Layered loading

Research: Anthropic Context Engineering (Sept 2025) + APIVR-Δ's production evidence.
Applied to: **all Eidolons**. Entry point ~900 tokens, skills load on-demand per phase.

### Bounded self-correction

Research: CorrectBench (2025) + Reflexion critique literature.
Applied to: **IDG** (1 pass), **APIVR-Δ** (up to 3), **ATLAS** (three-strike halt).

### Structural markers as intelligence

Research: Harness AI incident conventions + DocAgent's CHT framework.
Applied to: **IDG** (four markers), **ATLAS** (`[FINDING-NNN]`), all Eidolons via Prime Directive D7.

### Evidence anchoring

Research: SWE-Agent tool design + DocAgent citation enforcement.
Applied to: **ATLAS** (`path:line`), **IDG** (source artifact refs), **SPECTRA** (pattern + rejected alternatives).

---

## Production patterns

Non-paper evidence. See [`production-patterns.md`](production-patterns.md) for full details.

- **Claude Code** — Plan Mode, skill activation, subagents
- **Cursor** — MDC rules, agent-requested skills, `AGENTS.md` support
- **Aider** — file-aware editing, test-driven repair loops
- **Copilot Workspace** — multi-step agent coding
- **SWE-Agent** — bounded ACI for software engineering
- **DocAgent** — multi-role documentation pipeline
- **OpenCode** — permission-scoped agents

Each pattern lists: source, what it does, how the Eidolons borrow from it, how the Eidolons *differ* (important — we don't just copy).

---

## Contributing to the library

If an Eidolon's design evolves and the rationale shifts:

1. Update the paper summary in `papers/<slug>.md` if the finding is new
2. Update the production-patterns entry if the pattern is new
3. Update `references.bib` if adding a citation
4. Update this INDEX's "Research → Eidolon mapping" section
5. Commit with message: `research: add/update <slug>`

Do **not** duplicate rationale that already lives in an individual Eidolon's `DESIGN-RATIONALE.md`. The nexus library is for *cross-cutting* evidence. Eidolon-specific rationale stays in the Eidolon's repo.

---

## Status

This library is in an early state. Priority extraction order:

1. Consolidate citations from existing `DESIGN-RATIONALE.md` files in each Eidolon repo
2. Build BibTeX from those citations
3. Write one paper summary per major citation
4. Cross-link back into each Eidolon's rationale

This is tracked as **Open Thread §8 — Research aggregation** in the project instructions.
