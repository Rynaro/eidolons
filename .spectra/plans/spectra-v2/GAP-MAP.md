# GAP-MAP — SPECTRA 4.11 vs the Curated Evidence

> SPECTRA v2 campaign · 2026-07-04 · Fable 5.
> Inputs: 4 digest reports (mechanization inventory, research base, Vivi playbook, v2.0 context) + 3 research dossiers + `CURATION.md` verdicts.
> Format: campaign house style — hypothesis grading, then gap classes with MUST/SHOULD.

## Hypothesis grading

| Hypothesis (going in) | Verdict | Evidence |
|---|---|---|
| H1: SPECTRA's methodology is strong but under-enforced | **CONFIRMED** | Mechanization inventory: installer/schemas mechanical, every cognitive gate LLM-trusted prose; DR-11/DR-12 scope notes admit it |
| H2: Market plan modes are blackboxes users distrust | **CONFIRMED** | Cursor staff-admitted unenforced boundary; ExitPlanMode #9701; no vendor rubric/provenance; leak-only internals |
| H3: The mechanization white space is unclaimed | **CONFIRMED** | MCP scan: no rubric gate, EARS linter, criteria freeze, drift checker, evidence gates, maker≠checker — anywhere |
| H4: More planning structure is always better | **REFUTED** | arXiv 2604.12147 (forced phases hurt), Scott Logic 10×, ~100-token diminishing returns, GSD anti-ceremony growth |
| H5: Frontier-plans+cheap-executes is straightforwardly correct | **PARTLY WRONG** | AkitaOnRails −7 quality at 3× cost (coupled); works only decoupled + gated + sparse-advisor (SWE-Protégé) |
| H6: SPECTRA's evidence base is current | **REFUTED** | Citations stop ≈2024; zero benchmark data; thresholds are dressed heuristics (own SYNTHESIS.md gap table) |

## Gap classes

### G-A — Enforcement gap (the existential one)
Every quality gate in SPECTRA 4.11 is a promise the model makes to itself. The market's own failures (Cursor, ExitPlanMode) prove promises don't hold; ICLR 2026 goal-drift proves they erode under pressure.
- **MUST**: rubric/complexity/confidence arithmetic computed by script from per-dimension inputs (JSON in → gate decision out), never by the model.
- **MUST**: phase state machine on disk (`.state.json` already exists as an artifact — make it *authoritative*: a `gate` script validates transitions, records skips-with-reason).
- **MUST**: maker≠checker asserted mechanically on the plan-critique step (checker identity ≠ author identity, recorded in the envelope).
- **MUST**: emitted spec + envelope validated against schemas at emission time (schemas exist today; nothing runs them — close the loop).
- **SHOULD**: host enforcement recipes (Claude Code PreToolUse hook shim; opencode permission ruleset; Roo fileRegex) shipping as install-time wiring, so the read-only planning boundary is the host's mechanism, not prose.

### G-B — Right-sizing gap
"Never skip" is now evidence-contradicted (H4). ESL already ratified the pattern: mechanical right-sizing (observable signals only).
- **MUST**: a right-sizing gate script (inputs: files-touched estimate, blast radius, novelty, stakes signals) → trivial / lite / full tier; tier determines mandatory phases and verification layers; overrides recorded.
- **MUST**: trivial tier stays under a hard verbosity budget (~1 screen; the ~100-token finding scaled to spec form).
- **SHOULD**: delta-spec amendment path (OpenSpec lesson) so re-planning cost is proportional to the change.

### G-C — Drift & adherence gap (the flagship)
Nothing anywhere binds an approved plan to the executed diff. ESL names `drift_check`; SLUMP shows external state recovers 90% of spec-emergence degradation.
- **MUST**: `drift-check`: declared scope (files/interfaces in the frozen plan) vs actual `git diff` — uncovered changes flagged, report on disk.
- **MUST**: acceptance-criteria SHA-256 freeze at Assemble exit (DR-12) **plus** first-class `ac-amend` (hash-chained, re-approval) — freeze = tamper-evidence, never immutability (Brooker variable).
- **SHOULD**: plan-adherence report (Plan-Phase / Plan-Order / Plan-Fidelity) as a post-execution artifact + canary metric.

### G-D — Tier-routing gap
The roster routes Eidolons, not model tiers at plan boundaries. opusplan/Windsurf/Aider validate the boundary; AkitaOnRails bounds it.
- **MUST**: tier annotations in the handoff artifacts: stories/tasks carry executor-tier hints + low-ambiguity output contracts (schema-validated where possible, goose-style).
- **MUST**: scaffold density ∝ 1/tier — the spec emitted for a Haiku-class executor is *denser* (explicit steps, contracts) than for an Opus-class one (goals + constraints).
- **SHOULD**: sparse-advisor escalation encoded as data (extends routing.yaml escalation from v2.0 Wave 2): deterministic triggers for consulting the frontier tier at replan/verify boundaries.

### G-E — Calibration & honesty gap
Zero collected benchmark data; thresholds asserted as science. The transparency brand requires honesty about instruments.
- **MUST**: successor docs present rubric weights/thresholds as *calibratable instruments*; no outcome claims until measured (inherits nexus H-WIN discipline).
- **MUST**: `score` script logs (dimensions, total, gate, timestamp) to `.spectra/logs/` so calibration data accrues from day one; runnable `calibrate` verb (the parked v2.0 Wave 3 item) lands in the successor, not in SPECTRA 4.x.
- **SHOULD**: plan-adherence + drift metrics become the successor's canary DSL entries (measurable, not string-match-only).

### G-F — Elicitation gap
DISCOVER is right (MAST 41.8%) but free-form (ReqElicitGym: under-elicits).
- **MUST**: DISCOVER's five axes become a checklist with a mechanical coverage counter (≥2 unresolved `[GAP]` axes → escalate is today prose; make the counter a script over the elicitation summary).
- **SHOULD**: EARS normalization + `ears-lint` (grammar, atomicity, verify_method presence) before planning begins.

### G-G — Composition gap
Junction's `harness_plan_from_prompt` is a stub reserving the planner seat; `harness_verify` already checks envelopes L1-L4.
- **MUST**: successor emits Junction §7.5-compatible `plan.json` alongside the human plan — the portable, executable plan schema no vendor ships.
- **SHOULD**: MCP surface wrapping the bin/ scripts (score/lint/freeze/drift/gate) as a Junction-catalogue candidate — scripts-first so MCP-less hosts lose nothing.

## Non-goals (scoped out, with reasons)
- Execution loops (Vivi's seat; handoffs stay ECL).
- Web dashboards/UI (hosts own UX).
- Role-agent theater (BMAD evidence).
- Package-manager distribution (nexus doctrine).
- Re-declaring ESL/ECL/EIIS schemas (anti-scope P0s hold; reference by version).
