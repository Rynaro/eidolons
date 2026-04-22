# Composition

> How the Eidolons work together. Handoff contracts, the canonical pipeline, and partial-team deployment.

The power of Eidolons is not in any single member — it is in their **composition.** This document defines how.

---

## The canonical pipeline

```
ATLAS ───▶ SPECTRA ───▶ APIVR-Δ ───▶ IDG
  scout      plan         build        chronicle
             ▲              │
             │              ▼
           FORGE ◀─── (ambiguity, trade-offs, novel problems)
```

**Reading left to right:**

1. **ATLAS** maps an unfamiliar codebase or problem area and emits a `scout-report.md` with evidence-anchored findings.
2. **SPECTRA** consumes the scout report, produces a spec (Markdown + YAML + state JSON) with stories, validation gates, and agent hints.
3. **APIVR-Δ** consumes the spec, implements the feature, emits a completion artifact (session log, delta history, completion report).
4. **IDG** consumes the session artifacts, produces documentation (chronicle, ADR, runbook, change-narrative) with structural markers.
5. **FORGE** is called at any point where ambiguity, trade-offs, or novel reasoning is needed — a consultable specialist, not always in-line.

**This pipeline is the default shape, not the only shape.** Partial configurations are first-class (see §3).

---

## Handoff contracts

Every Eidolon-to-Eidolon handoff is a **structured artifact**, not a free-form message. Artifacts are machine-parseable, validated against schemas, and persisted to disk for provenance.

| From | To | Artifact | Contains |
|------|----|----|----------|
| ATLAS | SPECTRA | `scout-report.md` + `findings.json` | Evidence-anchored findings, decision target, open gaps, recommended scope |
| ATLAS | APIVR-Δ | `scout-report.md` + `findings.json` | Same as above, plus explicit "reuse-first" asset list |
| SPECTRA | APIVR-Δ | Spec Markdown + YAML + state JSON | Stories with timeboxes, GIVEN/WHEN/THEN, agent hints, validation gates |
| APIVR-Δ | IDG | Session log + delta history + completion report | What was built, what changed, what failed and why |
| Any | FORGE | Reasoning request | Question, context, constraints, candidate answers (if any) |
| FORGE | Any | Reasoning report | Answer, assumptions, confidence tier, alternatives considered |

### Handoff invariants

1. **Artifacts are written to disk, not passed in-context.** This keeps working-set tokens bounded across the pipeline.
2. **Each artifact has a schema.** Structured outputs validated by JSON Schema 2020-12. Downstream Eidolons parse structured data, not prose.
3. **Provenance travels.** Every claim in a downstream artifact traces back to a specific line in the upstream artifact.
4. **Handoffs are labeled explicitly.** `→ SPECTRA (needs spec)`, `→ APIVR-Δ (ready to implement)`, `→ FORGE (trade-off deliberation)`, `→ human (out of scope)` — no implicit transitions.

### The consultation pattern (FORGE)

FORGE is not in the linear pipeline. Any other Eidolon can consult FORGE at any point:

```
APIVR-Δ during Plan phase
  → "Two patterns apply here; trade-off unclear"
  → emits reasoning-request.md to FORGE
  → FORGE emits reasoning-report.md with verdict + confidence
  → APIVR-Δ resumes Plan phase
```

FORGE does not implement, retrieve, or synthesize. It reasons. Its output is a structured deliberation, not a spec or code.

---

## Partial-team deployment

**Not every project uses every Eidolon.** Design implications:

1. **Every Eidolon is independently installable.** No hidden dependencies on teammates. ATLAS works solo; IDG works solo.
2. **Handoff contracts are optional inputs.** An Eidolon must function even when its upstream partner isn't deployed. If ATLAS isn't installed, SPECTRA accepts a human-authored scout-like brief instead.
3. **The installer exposes granular flags** — `eidolons init --members atlas,idg` picks just those two.
4. **Documentation for each member lists** "works standalone: yes/no" (always yes), "benefits from upstream": [list], "benefits from downstream": [list].

### Common partial configurations

| Configuration | Members | Use case |
|---------------|---------|----------|
| **Solo scout** | `atlas` | Audit an unfamiliar codebase without changing anything |
| **Solo chronicle** | `idg` | Document an existing session or decision |
| **Explore + document** | `atlas, idg` | Understand and document, read-only |
| **Plan + build** | `spectra, apivr` | Feature work where the team already knows the codebase |
| **Full pipeline** | `atlas, spectra, apivr, idg` | New feature in unfamiliar code |
| **With reasoner** | add `forge` to any | Ambiguous trade-offs expected |

These map to presets in [`../roster/index.yaml`](../roster/index.yaml) — `eidolons init --preset solo-scout`, etc.

### Host mismatches

A team may span hosts — e.g., the user runs ATLAS in Claude Code for exploration, then switches to Cursor to run APIVR-Δ for implementation. Supported:

- Each Eidolon's files live in `.eidolons/<n>/` — host-independent
- Host dispatch (`CLAUDE.md`, `.cursor/rules/`, etc.) is auto-wired per the consumer's tooling
- Handoff artifacts live in the repo (`scout-reports/`, `specs/`, `sessions/`) — travel with the code, not with the host

---

## Shared memory model

**Open thread.** Each Eidolon has its own memory schema today:

- ATLAS — Memex (hashed-directory KV for excerpts)
- APIVR-Δ — episodic (`task-log`, `pattern-registry`, `failure-catalog`, `delta-history`)
- SPECTRA — spec state JSON per session
- IDG — stateless (synthesis from provided context)
- FORGE — TBD

Harmonizing these into a coherent cross-agent memory story is an active design thread. The four candidate memory classes are:

- **Episodic** — past missions, specs, sessions, documents
- **Semantic** — templates, architectural patterns, conventions per project
- **Procedural** — learned strategies, domain-specific heuristics
- **Execution** — in-flight plans, state files, replanning history

When the design lands, it will live in [`./shared-memory.md`](shared-memory.md) (TBD) and the canonical storage location will be `.eidolons/memory/` in the consumer project.

---

## Anti-patterns

**Internal sub-agent pipelines.** An Eidolon that grows a pipeline inside itself (planner → builder → verifier all in one prompt) violates D2. That's what the team is for.

**Implicit handoffs.** An Eidolon that tries to "do a bit of everything" because it sees an adjacent need. Explicit handoff or refusal; no implicit expansion.

**Shared mutable state.** Eidolons do not mutate each other's memory. Handoffs are immutable artifacts written to disk and consumed read-only.

**Version drift.** Installing ATLAS v1.0 but SPECTRA v4.2 when SPECTRA v4.2 was built against ATLAS v1.1 scout-report schema. Compatibility matrix in `../roster/index.yaml` captures supported version ranges; `eidolons doctor` warns on mismatches.

---

## Related

- [`prime-directives.md`](prime-directives.md) — the ten non-negotiables
- [`vocabulary.md`](vocabulary.md) — shared terminology
- [`../roster/index.yaml`](../roster/index.yaml) — machine-readable handoff contracts per Eidolon
- [`../docs/architecture.md`](../docs/architecture.md) — install-time architecture
