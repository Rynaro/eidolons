# The Eidolons Manifesto

> A personal, portable team of AI agents. Each is a named specialist with its own methodology, identity, and boundaries. They work alone when the task is sharp; they work in harmony when the task is big; they travel together, from project to project, codebase to codebase, host to host.

---

## Why Eidolons

The first wave of AI coding tools produced **generalist agents** — one big system prompt that tries to be planner, scout, builder, and chronicler at once. This approach hits a ceiling fast: monolithic prompts at 5–15k tokens suffer from context rot, phase-irrelevant instructions dilute the active task, and there's no clean boundary between what the agent *is* and what it *does*.

The second wave tried **sub-agent pipelines inside a single system** — one harness spawning specialized children. Better, but still coupled: the pipeline is bolted together by the host, version drift between members is hidden, and portability across projects is near zero.

**Eidolons is a third approach.** Each agent is a first-class citizen — its own repo, its own methodology, its own release cadence, its own voice. They cooperate through explicit handoff contracts, not through shared state. They travel with the person who uses them, not with the tool they happen to run inside.

---

## The four commitments

### 1. Each member is an individual

The Eidolons are not interchangeable cogs. Each has a name, a capability class, a named methodology with a phase cycle, and a refusal boundary. ATLAS refuses to write; SPECTRA refuses to implement; IDG refuses to research. This isn't a limitation — it's the point. Sharp boundaries let each member go deeper in its domain than a generalist ever could.

### 2. The team is portable

The Eidolons belong to the person, not the project. They install into any codebase — Rails, Python, Rust, frontend monorepo, greenfield, brownfield, monorepo, microservices. They wire themselves into whichever host is in use: Claude Code, Copilot, Cursor, OpenCode, raw API. A person can arrive at a new project and bring their team with them.

### 3. Every decision is traceable

No "because it feels right." Every design decision in every Eidolon maps to a research paper, a production pattern, or a principled trade-off with named alternatives. Evidence is checked into the repo — `DESIGN-RATIONALE.md` in each Eidolon, aggregated research library in the nexus. If the reasoning changes, the documentation changes.

### 4. Composition is first-class

The team is more than the sum of its members. The canonical pipeline — ATLAS → SPECTRA → APIVR-Δ → IDG, with FORGE (reasoning) and VIGIL (forensic debugging) as lateral specialists — is a real compositional asset. Handoff contracts are structured artifacts, not free-form messages. Partial-team deployment is supported by design: bring just ATLAS to an audit-heavy project, bring the whole pipeline to a greenfield, bring ATLAS + IDG when you want to understand and document without changing anything.

---

## What we refuse

**Monolithic system prompts.** A 5,000-token prompt that tries to be everything to every task. Replaced by layered loading: ~900-token entry + on-demand skills.

**Unbounded reflection loops.** Research (CorrectBench 2025) shows they degrade prose quality. Every Eidolon has a fixed verification gate and a bounded revision budget.

**Internal sub-agent pipelines inside one member.** If ATLAS needs planning, it hands off to SPECTRA; it does not grow an internal SPECTRA. Roster bloat dilutes the team.

**Hard-coded vendor names.** We speak in capability classes — reasoning-class, speed-class — not model names. An Eidolon must work on Claude, GPT, Gemini, a local Llama.

**Draft-quality deliverables.** We ship complete packages: entry point, skills, templates, rationale, installer, host wirings, CHANGELOG, canary missions. Not outlines, not TODOs.

**Roster bloat.** Not every capability needs a new Eidolon. If a gap can be filled by extending an existing member's skills, we extend. New members must earn their place — distinct boundary, named methodology, evidence base.

---

## Origin

Designed and battle-tested by a senior engineering leader (≈20 years) who ships production AI systems, cares deeply about security and data leakage, and insists on Linux-heavy, Git-driven, container-native workflows. Written because the existing options were either too rigid (vendor plan modes, closed loops) or too loose (roll-your-own prompts that drift between projects).

The Eidolons are opinionated. They are also humble about where the evidence is thin — `[DISPUTED]` and `[GAP]` markers surface disagreement and missing information rather than papering over them.

---

## The current team

| Eidolon | Role | Status |
|---------|------|--------|
| **ATLAS** | Scout — read-only codebase intelligence | shipped |
| **SPECTRA** | Planner — decision-ready specifications | shipped |
| **APIVR-Δ** | Coder — brownfield feature implementation | shipped |
| **IDG** | Scriber — documentation synthesis | shipped |
| **FORGE** | Reasoner — deep reasoning, trade-offs, counterfactuals | shipped |
| **VIGIL** | Debugger — forensic root-cause attribution | shipped |

See [`roster/index.yaml`](roster/index.yaml) for the machine-readable registry and [`methodology/composition.md`](methodology/composition.md) for how they work together.

---

## What you can do with them

- **Plan-before-build.** ATLAS maps the unfamiliar codebase, SPECTRA turns the scout report into a decision-ready spec, APIVR-Δ implements against that spec, IDG chronicles what happened.
- **Audit without touching.** ATLAS + IDG. Explore a codebase, produce a read-only findings report and a change-narrative — no code modified.
- **Ship a feature fast.** SPECTRA + APIVR-Δ. Skip the scout if you know the terrain; plan, then build.
- **Bring rigor to ambiguous decisions.** FORGE. Deliberate on trade-offs, name counterfactuals, produce a verdict with confidence tier.

---

## Final word

The Eidolons are a **personal team** that travels with the user. Each member is sharp, portable, evidence-grounded, versioned. They work alone when the task is small and in harmony when the task is big. They are not bolted-together tools; they are individuals with their own voice, their own methodology, and their own place in the roster.

When the question is hard and the context is big, you don't want one confused assistant. You want a team.
