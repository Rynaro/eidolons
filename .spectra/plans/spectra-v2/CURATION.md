# Curation — Verdicts on the Evidence (Fable pass)

> SPECTRA v2 campaign · 2026-07-04 · Author: Fable 5 (curation is deliberately NOT delegated).
> Method: every load-bearing claim from the three research dossiers + the four digest reports was graded.
> KEEP = build on it. CONDITIONAL = build on it within stated bounds. KILL = do not build on it; remove from successor claims.

## Verdict table

| # | Claim | Verdict | Basis | Design consequence |
|---|-------|---------|-------|--------------------|
| C1 | Plan/execute separation improves outcomes | **KEEP** | Universal convergence + RigorBench plan-then-build +0.37 [MED] + Aider measured splits | Successor keeps read-only planning core (D-inherit) |
| C2 | The plan/execute boundary must be enforced by *mechanism*, not prompt | **KEEP** | Cursor staff-admitted violation; ExitPlanMode #9701; ICLR 2026 goal-drift; Cline/Roo/opencode all gate in code | Ship tool/write gating recipes per host + state-machine gate script |
| C3 | Plans must persist as versioned, portable files | **KEEP** | All vendors converged on plan-as-file; Augment critique; SDD growth; SLUMP external-state +90% | Keep `.spectra/` artifacts; add plan.json (Junction §7.5-compatible) as the portable schema |
| C4 | Plan-vs-diff drift detection is valuable and absent everywhere | **KEEP** | MCP white-space scan (searched, none); vendor complaints; ESL drift_check named-not-implemented | **Flagship mechanization**: drift-check script/MCP verb |
| C5 | Mandatory full-cycle planning for every task | **KILL** | arXiv 2604.12147 (incomplete/forced plans hurt; strong models override); Scott Logic 10× ceremony; GSD anti-ceremony growth; ~100-token diminishing returns | Replace "Never skip" with a **mechanical right-sizing gate** (ESL-style, observable signals) producing trivial/lite/full tiers; skips recorded with reason |
| C6 | 7-dim weighted rubric as *evidence-based truth* | **KILL (as truth) / KEEP (as instrument)** | Weights are designer heuristics (SYNTHESIS.md's own gap table); AdaRubric: rubrics need AUC≥0.8/κ≥0.75 validation | Rubric arithmetic moves to a script (no silent math errors); scores+outcomes logged for calibration; claims soften to "instrument under calibration" |
| C7 | 6-layer verification always | **CONDITIONAL** | SPECTRA already allows adaptive budget; forced phases measurably hurt (C5 evidence) | Layers become tier-indexed: trivial=structural only; full=all 6 + critic |
| C8 | Confidence gate ≥85% AUTO_PROCEED | **CONDITIONAL** | Threshold is a heuristic; but graduated gates match Jules/spec-workflow direction | Keep gates, compute mechanically from factor inputs, log for calibration; thresholds are config, not doctrine |
| C9 | Frontier-plans + cheap-executes as blanket doctrine | **KILL** | AkitaOnRails: −7 quality at 3× cost on coupled tasks | Replace with **boundary tiering**: frontier holds plan/replan/verify gates; executors get decoupled, low-ambiguity contracts; sparse-advisor escalation (SWE-Protégé 11.9%) encoded as routing data |
| C10 | Two-model split gains are real | **KEEP (bounded)** | Aider +3-5pt same-model, SOTA pairs [HIGH] — contingent on low-ambiguity executor contract | Story/task handoffs carry executor-tier hints + output contracts (goose-style schema validation) |
| C11 | Maker≠checker on plan quality | **KEEP** | Jules Planning Critic −9.5% failures; ThinkPRM; ESL maker≠checker precedent (mechanical) | Plan-critic gate: critic identity ≠ author identity, asserted mechanically; debias (position-swap/identity-strip) per DR-11, now enforced not prose |
| C12 | EARS acceptance criteria | **KEEP + mechanize** | Kiro mainstreamed EARS; auto-linting nonexistent (white space); SPECTRA owns acceptance_checks[] per ESL §2.4 | `ears-lint` script: grammar + atomicity (no compound AND) + verify_method presence |
| C13 | SHA-256 freeze of acceptance criteria | **KEEP + add amend path** | DR-12 sound; but Brooker: mutability is THE variable; Kiro anti-freeze doctrine | `ac-freeze` + `ac-amend`: freezing with a cheap, first-class, hash-chained amendment protocol — freeze≠immutability, freeze=tamper-evidence |
| C14 | DISCOVER open-ended elicitation | **KEEP + structure it** | MAST 41.8% spec/design failures; HiddenBench; ReqElicitGym: free-form under-elicits | DISCOVER gets a fixed probe ontology (stakeholders/goal/metrics/constraints/non-goals already there) + coverage counter enforced by script, not prose |
| C15 | TRANCE parallel spec generation (G3) | **CONDITIONAL** | R3-06 quality>diversity holds; bias mitigations validated by 2025-26 judge literature | Keep TRANCE-gated; mitigations move from prose to the critic tooling |
| C16 | SPECTRA's benchmark/effectiveness claims | **KILL (until measured)** | Zero data collected; canaries are string-matchers | Successor makes NO outcome claims; inherits nexus H-WIN instrument; plan-adherence (Plan-Phase/Order/Fidelity) becomes a measured canary |
| C17 | THEORY.md formal derivations (EVPI, plan entropy) | **KILL (as derivations) / KEEP (as heuristics)** | Digest: "asserted, not derived or fit to data" | Successor docs present these as named heuristics with calibration hooks; honesty is part of the transparency brand |
| C18 | Vendor-agnostic portability as differentiator | **KEEP (strengthened)** | Windsurf/Cascade died by acquisition mid-campaign; Copilot Workspace sunset; plans locked in transcripts | Lead the positioning with continuity + portable plan schema |
| C19 | Ephemeral plan modes vs persisted specs | **KEEP the hybrid** | Market bifurcation; practitioner "spike → distill → spec-drive" | Right-sizing gate IS the hybrid: trivial tier ≈ plan-mode-weight; full tier ≈ spec-anchored |
| C20 | MCP as mechanization vehicle | **KEEP** | White space confirmed; Junction planner seat is an explicit stub; spec-workflow-mcp proves phase-gating demand (4.3k★) | Scripts first (bash 3.2, host-agnostic), MCP surface wrapping them (Junction-catalogue candidate); never MCP-only (hosts without MCP still get gates via scripts+hooks) |

## The three design theses that survive curation

**T-A. Transparency becomes *mechanical* transparency.** The market's plan modes are blackboxes twice over: hidden criteria AND unenforced promises. The successor's counter is not more prose — it is gates that run: scored rubrics computed by code, criteria linted by grammar, drift measured against the diff, approvals that cannot be authored by the model being gated (maker≠checker), all auditable on disk.

**T-B. Right-size or die.** The 2026 evidence is unambiguous: forced ceremony hurts outcomes and adoption (strongest competitor growth is anti-ceremony). The successor's default posture is the *lightest* tier that the observable signals allow, with mechanical escalation — planning weight proportional to stakes, never to habit.

**T-C. Tier the models at boundaries, not phases.** Frontier intelligence (Fable-class) owns the moments where plans are born, judged, and amended. Execution scaffolding is dense for cheap models, light for strong ones. Escalation is deterministic data, not self-assessment. This is how "Fable is the differentiator; the others compensate" becomes architecture instead of slogan.

## What was deliberately NOT adopted

- BMAD-style role theater (12 agents) — cost/ceremony evidence against.
- Spec-as-source (Tessl thesis) — "mostly a thesis" as of mid-2026; SPECTRA stays methodology + artifacts, not a compiler.
- Naive N-branch plan sampling — R3-06 (quality dominates diversity) still holds.
- Building our own execution loop — Vivi owns execution; the successor plans and verifies. Handoffs stay ECL.
- A dashboard/web UI (spec-workflow-mcp's moat) — out of scope for an Eidolon; hosts own UX. We own artifacts + gates.
