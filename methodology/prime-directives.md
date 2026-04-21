# Prime Directives

> Ten non-negotiables that apply to every Eidolon — current or future, new or iterating.

These directives are the kernel of the Eidolons program. They are enforced by roster admission: a candidate Eidolon that violates any of them is not added to the team. Existing Eidolons that drift out of conformance are flagged by `eidolons doctor` and the cross-member canary suite.

---

## D1 — Layered Loading Is The Architecture

Every Eidolon follows the proven loading pattern:

```
entry-point (agent.md, ≤ ~1,000 tokens — always loaded)
    ↓
SKILL.md (routing card for the host / skill system, minimal)
    ↓ on-demand
skills/<phase>/SKILL.md (phase-specific methodology)
    ↓ on-demand
templates/<artifact>.md (output skeletons)
```

**Rules:**

- Entry point contains only identity + cycle + P0 rules + skill-loading triggers.
- Skills load **per phase**, never upfront. Phase-irrelevant instructions degrade performance (Anthropic Context Engineering, Sept 2025).
- Target working set: **≤ 3,500 tokens** for specialists, ≤ 5,000 for generalists.
- Budget is explicit — list token count per file in the design doc.

**Exemplar:** APIVR-Δ v3.0 measures `entry + one skill + one template ≈ 4,350 tokens`. Every new Eidolon mirrors this pattern.

---

## D2 — Single Responsibility, Hard Boundaries

Each Eidolon has exactly one capability class. Boundaries are **enforced in the system prompt**, not hoped for.

| Eidolon | Does | Refuses |
|---------|------|---------|
| APIVR-Δ | Implement features | Plan from scratch, design architecture |
| SPECTRA | Plan and specify | Implement code, modify files |
| IDG | Synthesize docs from provided context | Retrieve, analyze code, research |
| ATLAS | Read-only exploration | Write, edit, commit, deploy |
| FORGE | Deep reasoning | Retrieve, implement, synthesize prose |

If an Eidolon starts absorbing adjacent concerns: **split it or hand off**. Roster bloat dilutes the team.

---

## D3 — Mechanical Invariants Over Prompt Reminders

Where possible, invariants are **enforced by the harness**, not by asking the model politely.

**Exemplar:** ATLAS's read-only guarantee. The MCP server (`atlas-aci`) exposes exactly seven read-only tools — no `edit_file`, no `write_file`, no `shell_exec`. A prompt-level instruction asking the model "please don't write" is advisory. A tool surface that doesn't expose write primitives is mechanical.

Every Eidolon must name its mechanical invariants explicitly:

- **Tool allowlists** — what's exposed, what's forbidden
- **Argument bounds** — line caps, match caps, pagination cursors
- **Path scoping** — repo-root guards, traversal protection
- **Rate limiting** — calls per minute, budget exhaustion
- **Telemetry sinks** — observability from day one

Where a host supports these (MCP permissions, tool allowlists, directory scoping), enforce them at the harness layer.

---

## D4 — Evidence Over Assertion

Every design decision in every deliverable must be traceable to:

- A cited research paper (with year, venue, key finding), **OR**
- A documented production pattern (APIVR-Δ, Claude Code, Cursor, Aider, DocAgent, SWE-Agent, etc.), **OR**
- A principled trade-off with rejected alternatives named

**No "because it feels right."** Every Eidolon ships a `DESIGN-RATIONALE.md` (or equivalent) mapping research findings to design decisions.

The nexus aggregates this evidence base in [`../research/`](../research/) — papers, production patterns, BibTeX, cross-references.

---

## D5 — Bounded Self-Correction

Unbounded Reflexion loops degrade output quality on open-ended tasks (CorrectBench 2025). Every Eidolon has:

- **A fixed verification gate.** CHT for IDG (Completeness, Helpfulness, Truthfulness). 6-layer for SPECTRA. Structured checklists, not freeform reflection.
- **A bounded revision budget.** 1 pass for prose (IDG), up to 3 for code (APIVR-Δ).
- **An explicit escalation path.** When the gate fails after the budget is exhausted, the Eidolon *surfaces the failure* — it does not loop forever.

No unbounded reflection. No "try again until it works." Fixed gate, bounded budget, explicit escalation.

---

## D6 — Evidence-Anchored Claims

For research-grade outputs, claims are **citations, not assertions**.

| Eidolon | Anchor format |
|---------|---------------|
| **IDG** | Cites source artifacts for every factual statement; `[GAP]`, `[DISPUTED]` surface problems |
| **ATLAS** | `path:line_start-line_end` + confidence tier (`H \| M \| L`) |
| **SPECTRA** | Pattern matches, rejected alternatives, validation gates |
| **APIVR-Δ** | Test anchors, lint output, trace evidence — no speculation |
| **FORGE** (planned) | Reasoning chains, assumptions, decision factors |

An unanchored claim is an invalid claim.

---

## D7 — Structural Markers

The Eidolons use markers to elevate output from record to intelligence. Borrow liberally, use consistently.

| Marker | Meaning |
|--------|---------|
| `[DECISION]` | A choice was made. Record what, why, alternatives rejected. |
| `[ACTION]` | Something needs to happen next. Record owner, trigger, deadline. |
| `[DISPUTED]` | Sources conflict. Present both sides; do not silently merge. |
| `[GAP]` | Information was expected but not provided. Surface explicitly. |
| `[FINDING-NNN]` | ATLAS-style evidence-anchored claim with confidence tier. |
| `[ROOT-CAUSE]` | Debugger marker: the actual fault, not the symptom. |
| `[SYMPTOM]` | Debugger marker: visible manifestation, not the root. |
| `[BLOCKED]` | Work could not proceed, with reason. |

Markers are **mechanical**. Downstream tools parse them. Don't paraphrase markers — emit them exactly.

---

## D8 — Deliverables Are Multi-File Packages

When we design a new Eidolon, the output is (at minimum):

1. `agent.md` — always-loaded entry point (~900 tokens)
2. `<EIDOLON>.md` — full specification / methodology (authoritative)
3. `AGENTS.md` — open-standard rules file (Copilot/Cursor/OpenCode)
4. `CLAUDE.md` — Claude Code pointer
5. `skills/<phase>/SKILL.md` — one per phase, on-demand
6. `templates/<artifact>.md` — one per output type
7. `schemas/<artifact>.schema.json` — validators for structured outputs
8. `DESIGN-RATIONALE.md` — research → decision mapping
9. `install.sh` — EIIS-conformant installer
10. `install.manifest.json` schema (referenced from `schemas/`)
11. `hosts/<host>.md` — one per supported host (claude-code, copilot, cursor, opencode)
12. `evals/canary-missions.md` — at least one mission
13. `README.md` — architecture, quick start, design principles, research foundation
14. `CHANGELOG.md` — Keep-a-Changelog format

**Not drafts. Not outlines. Ready-to-integrate, host-agnostic, EIIS-conformant packages.**

---

## D9 — Host-Agnosticism Is Explicit

Every Eidolon ships host-specific wiring docs. Current targets:

- **Claude Code** — `CLAUDE.md` + `.claude/agents/<n>.md` subagent
- **GitHub Copilot** — `.github/copilot-instructions.md` + root `AGENTS.md`
- **Cursor** — `.cursor/rules/<n>.mdc`
- **OpenCode** — `.opencode/agents/<n>.md`
- **Raw API / MCP** — direct system prompt load

No Eidolon may hard-code vendor names in its core methodology. We speak in **capability classes** — reasoning-class, speed-class — not model names. When a host supports MCP, the Eidolon's tools are exposed via MCP; when it doesn't, the Eidolon falls back to the host's native read tools.

---

## D10 — Security & Privacy As First-Class Concerns

Every Eidolon design surfaces:

- **What context it consumes** and where that context came from
- **What it persists**, where, and for how long
- **What external tools/APIs it invokes** and whether those leak data
- **Failure modes** where sensitive data could leak into logs, memory, or outputs
- **Recommended mitigations** — scoped memory, redaction, local-only persistence, path-traversal guards, rate limiting

**Not a checkbox at the end — a design input from the start.**

The roster entry captures the declaration:

```yaml
security:
  reads_repo: true
  reads_network: false
  writes_repo: false
  persists: [".atlas/memex/"]
```

`eidolons doctor` verifies these claims match the installed reality.

---

## How to use these

- **Designing a new Eidolon?** Every D1–D10 must be satisfied or explicitly deferred-with-reason.
- **Reviewing an existing Eidolon?** Walk D1–D10 as a checklist.
- **Proposing a new directive (D11+)?** Must be evidence-grounded and orthogonal to the existing ten. No duplication, no aspirational rules that can't be verified.

---

## Related

- [`composition.md`](composition.md) — handoff contracts, pipeline, partial-team deployment
- [`vocabulary.md`](vocabulary.md) — shared terminology
- [`../research/INDEX.md`](../research/INDEX.md) — the evidence base
- `Rynaro/eidolons-eiis` — the install standard that mechanically enforces D1, D8, D9
