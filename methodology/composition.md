# Composition

> How the Eidolons work together. Handoff contracts, the canonical pipeline, and partial-team deployment.

The power of Eidolons is not in any single member — it is in their **composition.** This document defines how.

> **This file is auto-generated** from `eidolons-ecl/contracts/*.yaml` by
> `eidolons-ecl compose-gen`. Edits to this file are clobbered on
> regeneration — change the contracts (or the template) instead.

---

## The canonical pipeline

```
ATLAS ───▶ SPECTRA ───▶ APIVR-Δ ───▶ IDG
  scout      plan         build        chronicle
             ▲              │ ▲
             │              │ │
           FORGE ◀─── (ambiguity, trade-offs, novel problems)
                            │ │
                          VIGIL ◀─── (failure resisted repair; forensic attribution)
```

**Reading left to right:**

1. **ATLAS** maps an unfamiliar codebase or problem area and emits a `scout-report.md` with evidence-anchored findings.
2. **SPECTRA** consumes the scout report, produces a spec (Markdown + YAML + state JSON) with stories, validation gates, and agent hints.
3. **APIVR-Δ** consumes the spec, implements the feature, emits a completion artifact (session log, delta history, completion report).
4. **IDG** consumes the session artifacts, produces documentation (chronicle, ADR, runbook, change-narrative) with structural markers.
5. **FORGE** is called at any point where ambiguity, trade-offs, or novel reasoning is needed — a consultable specialist, not always in-line.
6. **VIGIL** is called when a failure resists normal repair — APIVR-Δ's Reflect loop exhausted, a heisenbug surfaces, or a compound failure needs root-cause attribution. A consultable forensic specialist, not always in-line.

**This pipeline is the default shape, not the only shape.** Partial configurations are first-class (see §3).

---

## Hand-off edges

Reading left to right: a row says "an envelope on this edge is allowed
to carry one of these performatives wrapping one of these artifact
kinds, with this context-budget ceiling, at this trust level".

| From | To | Performatives | Artifact kinds | Context budget | Trust | Origin |
| --- | --- | --- | --- | --- | --- | --- |
| `apivr` | `forge` | REQUEST, CRITIQUE | reasoning-request | 3000 | `standard` | `roster` |
| `apivr` | `idg` | PROPOSE, INFORM | apivr-completion-report | 5000 | `standard` | `roster` |
| `apivr` | `kupo` | DELEGATE, INFORM, ACKNOWLEDGE | apivr-completion-report | 4000 | `standard` | `roster` |
| `apivr` | `vigil` | ESCALATE, REQUEST, ACKNOWLEDGE | repair-failed-report | 4000 | `high` | `roster` |
| `atlas` | `apivr` | PROPOSE, INFORM, REFUSE | scout-report | 4000 | `standard` | `roster` |
| `atlas` | `forge` | REQUEST, CRITIQUE | reasoning-request | 3000 | `standard` | `roster` |
| `atlas` | `kupo` | DELEGATE, INFORM, ACKNOWLEDGE | scout-report | 4000 | `standard` | `roster` |
| `atlas` | `spectra` | PROPOSE, INFORM, REFUSE | scout-report | 4000 | `standard` | `roster` |
| `forge` | `apivr` | PROPOSE, INFORM, CRITIQUE | reasoning-report | 3000 | `standard` | `roster` |
| `forge` | `atlas` | PROPOSE, INFORM, CRITIQUE | reasoning-report | 3000 | `standard` | `roster` |
| `forge` | `idg` | PROPOSE, INFORM, CRITIQUE | reasoning-report | 3000 | `standard` | `roster` |
| `forge` | `kupo` | DELEGATE, INFORM, ACKNOWLEDGE | reasoning-report | 4000 | `standard` | `roster` |
| `forge` | `spectra` | PROPOSE, INFORM, CRITIQUE | reasoning-report | 3000 | `standard` | `roster` |
| `forge` | `vigil` | PROPOSE, INFORM, CRITIQUE | reasoning-report | 3000 | `standard` | `roster` |
| `human` | `apivr` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `roster` |
| `human` | `atlas` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `roster` |
| `human` | `forge` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `roster` |
| `human` | `idg` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `roster` |
| `human` | `kupo` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `implicit` |
| `human` | `spectra` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `roster` |
| `human` | `vigil` | REQUEST, INFORM, CRITIQUE, REFUSE, ACKNOWLEDGE, ESCALATE | prompt | 4000 | `standard` | `roster` |
| `idg` | `forge` | REQUEST, CRITIQUE | reasoning-request | 3000 | `standard` | `roster` |
| `kupo` | `apivr` | PROPOSE, INFORM, ESCALATE, REFUSE, ACKNOWLEDGE, RESUME | edit-proposal | 4000 | `standard` | `roster` |
| `kupo` | `atlas` | INFORM, ESCALATE, REFUSE, ACKNOWLEDGE | edit-proposal | 4000 | `standard` | `roster` |
| `kupo` | `forge` | PROPOSE, INFORM, ESCALATE, REFUSE, ACKNOWLEDGE, RESUME | edit-proposal | 4000 | `standard` | `roster` |
| `kupo` | `spectra` | PROPOSE, INFORM, ESCALATE, REFUSE, ACKNOWLEDGE, RESUME | edit-proposal | 4000 | `standard` | `roster` |
| `kupo` | `vigil` | PROPOSE, INFORM, ESCALATE, REFUSE, ACKNOWLEDGE, RESUME | edit-proposal | 4000 | `standard` | `roster` |
| `spectra` | `apivr` | PROPOSE, INFORM, REFUSE | spec | 6000 | `standard` | `roster` |
| `spectra` | `forge` | REQUEST, CRITIQUE | reasoning-request | 3000 | `standard` | `roster` |
| `spectra` | `kupo` | DELEGATE, INFORM, ACKNOWLEDGE | spec | 4000 | `standard` | `roster` |
| `vigil` | `apivr` | PROPOSE, CRITIQUE, INFORM | root-cause-report | 4000 | `high` | `roster` |
| `vigil` | `forge` | REQUEST, CRITIQUE | reasoning-request | 3000 | `standard` | `roster` |
| `vigil` | `idg` | PROPOSE, INFORM | root-cause-report | 4000 | `standard` | `roster` |
| `vigil` | `kupo` | DELEGATE, INFORM, ACKNOWLEDGE | root-cause-report | 4000 | `standard` | `roster` |
| `vigil` | `spectra` | PROPOSE, INFORM, ESCALATE | root-cause-report | 4000 | `high` | `roster` |

### Hand-off invariants

1. **Artifacts are written to disk, not passed in-context.** This keeps working-set tokens bounded across the pipeline.
2. **Each artifact has a schema.** Structured outputs validated by JSON Schema 2020-12. Downstream Eidolons parse structured data, not prose.
3. **Provenance travels.** Every claim in a downstream artifact traces back to a specific line in the upstream artifact.
4. **Handoffs are labeled explicitly.** `→ SPECTRA (needs spec)`, `→ APIVR-Δ (ready to implement)`, `→ FORGE (trade-off deliberation)`, `→ human (out of scope)` — no implicit transitions.

### The consultation pattern (FORGE, VIGIL)

FORGE and VIGIL are not in the linear pipeline. Any other Eidolon — or the user — can consult them at any point:

```
APIVR-Δ during Plan phase
  → "Two patterns apply here; trade-off unclear"
  → emits reasoning-request.md to FORGE
  → FORGE emits reasoning-report.md with verdict + confidence
  → APIVR-Δ resumes Plan phase
```

```
APIVR-Δ during Reflect phase
  → 3 repair attempts exhausted; flaky test still failing
  → emits repair-failed-report.md to VIGIL (sandbox authority)
  → VIGIL runs V→I→G→I→L: reproduction, IDG, ≤5 counterfactuals
  → VIGIL emits root-cause-report.md + verified-patch.diff
  → APIVR-Δ applies patch, verifies, resumes
```

FORGE reasons; it does not implement, retrieve, or synthesize. VIGIL attributes; it does not build, plan, or document. Both emit structured deliberation artifacts, not specs or code.

---

## Edge notes

### `apivr → forge`

APIVR-Δ consults FORGE during Plan phase when ambiguity or trade-offs surface. Listed in roster: apivr.handoffs.lateral contains forge. The reasoning-request profile is intentionally lightweight (base profile only); FORGE methodology owns the body shape. This contract is the representative shape for all consultation requests to FORGE; per-edge contracts for atlas→forge, spectra→forge, idg→forge, vigil→forge follow the same template and are added per-PR as those edges are exercised.

### `apivr → idg`

APIVR-Δ hands off the completion artefact (session log + delta history + completion report) for IDG to chronicle. Listed in roster: apivr.handoffs.downstream contains idg.

### `apivr → kupo`

APIVR DELEGATEs a localized, verifier-backed micro-task to Kupo (the low-effort executor) — e.g. a rename, import fix, lockfile/dep-pin bump, config-key edit, or one-line fix identified within its own apivr-completion-report. Kupo KEEPs only localized (<= 2 files), named-verifier-backed work (else REFUSE/ESCALATE cheaply), patches an ephemeral sandbox, proves it with an external verifier, and returns a verified edit-proposal via kupo-to-apivr. Declared in roster: kupo.handoffs.upstream contains apivr.

### `apivr → vigil`

APIVR-Δ escalates to VIGIL when the Reflect phase exhausts its 3-failure threshold on the same category. Performative MUST be ESCALATE for the threshold path; REQUEST is reserved for ad-hoc forensic asks that do not cross the threshold. Listed in roster: apivr.handoffs.lateral contains vigil.

### `atlas → apivr`

ATLAS hands off directly to APIVR-Δ when SPECTRA is not deployed (partial team) or when the work is small enough to skip spec authoring. Same artefact kind as the ATLAS→SPECTRA edge but with the additional required_section reuse_first_assets, which APIVR-Δ uses to satisfy its Internal-First P0.

### `atlas → forge`

ATLAS consults FORGE during the Locate or Synthesize phase when a forensic finding or hand-off-target decision has more than one defensible framing — e.g. competing call-graph entry points, ambiguous owner attribution, or a structural choice that downstream consumers (APIVR-Δ or SPECTRA) will see different consequences from. Listed in roster: atlas.handoffs.lateral contains forge. Mirrors apivr-to-forge body shape; FORGE methodology owns the response.

### `atlas → kupo`

ATLAS DELEGATEs a localized, verifier-backed micro-task to Kupo (the low-effort executor) — e.g. a rename, import fix, lockfile/dep-pin bump, config-key edit, or one-line fix identified within its own scout-report. Kupo KEEPs only localized (<= 2 files), named-verifier-backed work (else REFUSE/ESCALATE cheaply), patches an ephemeral sandbox, proves it with an external verifier, and returns a verified edit-proposal via kupo-to-atlas. Declared in roster: kupo.handoffs.upstream contains atlas.

### `atlas → spectra`

ATLAS hands off a finalised scout report for SPECTRA to consume during the SCOPE phase. Listed in roster: atlas.handoffs.downstream contains spectra. Source-of-truth row in methodology/composition.md ("ATLAS | SPECTRA | scout-report.md + findings.json").

### `forge → apivr`

FORGE returns the reasoning report to the requesting Eidolon. Listed in roster: forge.handoffs.lateral contains apivr. CRITIQUE is reserved for the case where FORGE deliberately reframes the question rather than answering it (REFORGE pass). This contract is the representative shape for all FORGE consultation reports; per-edge contracts forge→atlas, forge→spectra, forge→idg, forge→vigil follow the same template and are added per-PR as those edges are exercised.

### `forge → atlas`

FORGE returns a reasoning report to ATLAS in response to atlas→forge consultation. Listed in roster: forge.handoffs.lateral contains atlas. CRITIQUE is reserved for the REFORGE case where FORGE reframes the question rather than answering it (e.g. when the structural choice ATLAS surfaced cannot be decided without a missing hand-off target).

### `forge → idg`

FORGE returns a reasoning report to IDG in response to idg→forge consultation. Listed in roster: forge.handoffs.lateral contains idg. CRITIQUE is reserved for the REFORGE case where FORGE declines to adjudicate (e.g. because the conflicting sources require a fresh observation rather than reasoning) and returns the question reframed.

### `forge → kupo`

FORGE DELEGATEs a localized, verifier-backed micro-task to Kupo (the low-effort executor) — e.g. a rename, import fix, lockfile/dep-pin bump, config-key edit, or one-line fix identified within its own reasoning-report. Kupo KEEPs only localized (<= 2 files), named-verifier-backed work (else REFUSE/ESCALATE cheaply), patches an ephemeral sandbox, proves it with an external verifier, and returns a verified edit-proposal via kupo-to-forge. Declared in roster: kupo.handoffs.upstream contains forge.

### `forge → spectra`

FORGE returns a reasoning report to SPECTRA in response to spectra→forge consultation. Listed in roster: forge.handoffs.lateral contains spectra. CRITIQUE is reserved for the REFORGE case where FORGE refuses the scoring frame (e.g. because the rubric dimensions themselves are mis-calibrated for the change in scope) rather than picking a winner.

### `forge → vigil`

FORGE returns a reasoning report to VIGIL in response to vigil→forge consultation. Listed in roster: forge.handoffs.lateral contains vigil. CRITIQUE is reserved for the REFORGE case where FORGE refuses the blame-target frame — typically when reproduction evidence is too thin for any of VIGIL's hypotheses to be reasoned about, and an extra observation pass is the right next step.

### `human → apivr`

Human-origin edge into APIVR-Δ. The originator may REQUEST APIVR-Δ to implement a feature or run the A→P→I→V→Δ cycle on a spec, INFORM it with additional context (a test case to anchor against, a constraint surfaced after planning), CRITIQUE a prior implementation report or a proposed plan during the Plan phase, REFUSE a proposed artefact, ACKNOWLEDGE a completion report to close a pause-on gate, or ESCALATE a blocker (e.g. "this should route to VIGIL"). Human originators MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME — see human-to-atlas.yaml for per-performative rationale (Junction spec §5.7). Authored to support Junction's F-HUMAN-EDGE; additive to ECL v1.0 with no spec-version bump.

### `human → atlas`

Human-origin edge into ATLAS. The originator may REQUEST ATLAS to map a surface or produce a scout-report, INFORM it with additional context (e.g. "the dispatch lives in cli/src/"), CRITIQUE a prior scout-report for revision, REFUSE a proposed scout target or framing, ACKNOWLEDGE a scout-report to close a pause-on gate, or ESCALATE a blocker outside the current chain. Human originators MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME (rationale per performative: PROPOSE collapses to REQUEST; DECIDE is reserved for an evaluator Eidolon — FORGE — so the audit trail names the deciding role; DELEGATE is reserved for Eidolon-origin task binding; RESUME is emitted by the harness itself when re-entering a trace, not by the human). Authored to support Junction's F-HUMAN-EDGE per Junction spec §5.7; additive to ECL v1.0 with no spec-version bump.

### `human → forge`

Human-origin edge into FORGE. The originator may REQUEST FORGE to perform a quality gate, RFC review, or arbitrate a trade-off, INFORM it with additional context (a counterfactual, an external constraint not surfaced in the originating chain), CRITIQUE a prior reasoning report, REFUSE a proposed decision (FORGE re-runs with the human's REFUSE recorded in the trace), ACKNOWLEDGE a reasoning report, or ESCALATE a blocker. Note that FORGE is itself the evaluator role emitting DECIDE — the human's role here is to feed inputs and accept or reject outputs, never to short-circuit FORGE's own DECIDE. Human originators MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME — see human-to-atlas.yaml for per-performative rationale (Junction spec §5.7). Authored to support Junction's F-HUMAN-EDGE; additive to ECL v1.0 with no spec-version bump.

### `human → idg`

Human-origin edge into IDG. The originator may REQUEST IDG to chronicle a session's artefacts and decisions, INFORM it with additional context (a missing rationale, a corrected attribution), CRITIQUE a prior chronicle for revision, REFUSE a proposed chronicle, ACKNOWLEDGE a finalised chronicle, or ESCALATE a blocker outside the current chain. Human originators MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME — see human-to-atlas.yaml for per-performative rationale (Junction spec §5.7). Authored to support Junction's F-HUMAN-EDGE; additive to ECL v1.0 with no spec-version bump.

### `human → kupo`

Human-origin edge into Kupo. The originator may REQUEST a quick localized, verifier-backed micro-task (rename, import fix, lockfile bump, lint autofix), INFORM additional context, CRITIQUE a prior edit-proposal for revision, REFUSE a target/framing, ACKNOWLEDGE to close a gate, or ESCALATE a blocker. Humans MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME (PROPOSE collapses to REQUEST; DECIDE is reserved for an evaluator Eidolon; DELEGATE is reserved for Eidolon-origin task binding; RESUME is harness-emitted). edge_origin: implicit — a human may invoke the executor directly, outside a roster chain.

### `human → spectra`

Human-origin edge into SPECTRA. The originator may REQUEST SPECTRA to author a decision-ready specification, INFORM it with additional context (a reference doc, an updated requirement, a fact discovered mid-cycle), CRITIQUE a prior spec for revision (tightening a gate, reframing a story), REFUSE a proposed spec, ACKNOWLEDGE a spec to close a pause-on gate before APIVR-Δ proceeds, or ESCALATE a blocker outside the current chain (e.g. "this needs ATLAS first"). Human originators MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME — see human-to-atlas.yaml for per-performative rationale (Junction spec §5.7). Authored to support Junction's F-HUMAN-EDGE; additive to ECL v1.0 with no spec-version bump.

### `human → vigil`

Human-origin edge into VIGIL. The originator may REQUEST VIGIL to investigate or patch a defect, INFORM it with additional context (a reproducer, a suspect commit, a log excerpt), CRITIQUE a prior root-cause report for revision, REFUSE a proposed patch, ACKNOWLEDGE a patch or root-cause report to close a pause-on gate, or ESCALATE a blocker outside the current chain. Human originators MUST NOT emit PROPOSE, DECIDE, DELEGATE, or RESUME — see human-to-atlas.yaml for per-performative rationale (Junction spec §5.7). Authored to support Junction's F-HUMAN-EDGE; additive to ECL v1.0 with no spec-version bump.

### `idg → forge`

IDG consults FORGE when a chronicle must adjudicate between conflicting source artefacts — e.g. two upstream Eidolons recorded contradictory decisions for the same change, or a `[DISPUTED]` marker requires reasoned resolution before it can be retired. Listed in roster: idg.handoffs.lateral contains forge. Mirrors apivr-to-forge; FORGE owns the response body.

### `kupo → apivr`

Kupo returns a verified edit-proposal to apivr (the parent that DELEGATEd): search/replace or whole-file edits proven GREEN by a NAMED external verifier in an ephemeral sandbox. The PARENT applies the patch to the real tree and commits — Kupo never writes the real tree (PROPOSE-only) and never routes work onward (worker, never router). On out-of-scope or budget exhaustion, Kupo ESCALATEs or REFUSEs. Reverse of apivr-to-kupo (roster handoff).

### `kupo → atlas`

Kupo replies to ATLAS with INFORM/ESCALATE/REFUSE/ACKNOWLEDGE only — never PROPOSE, because a read-only scout cannot apply a patch. If ATLAS delegates a quick lookup, Kupo INFORMs the result; if the task requires an applied edit, Kupo ESCALATEs to a write-capable parent. Reverse of atlas-to-kupo (roster).

### `kupo → forge`

Kupo returns a verified edit-proposal to forge (the parent that DELEGATEd): search/replace or whole-file edits proven GREEN by a NAMED external verifier in an ephemeral sandbox. The PARENT applies the patch to the real tree and commits — Kupo never writes the real tree (PROPOSE-only) and never routes work onward (worker, never router). On out-of-scope or budget exhaustion, Kupo ESCALATEs or REFUSEs. Reverse of forge-to-kupo (roster handoff).

### `kupo → spectra`

Kupo returns a verified edit-proposal to spectra (the parent that DELEGATEd): search/replace or whole-file edits proven GREEN by a NAMED external verifier in an ephemeral sandbox. The PARENT applies the patch to the real tree and commits — Kupo never writes the real tree (PROPOSE-only) and never routes work onward (worker, never router). On out-of-scope or budget exhaustion, Kupo ESCALATEs or REFUSEs. Reverse of spectra-to-kupo (roster handoff).

### `kupo → vigil`

Kupo returns a verified edit-proposal to vigil (the parent that DELEGATEd): search/replace or whole-file edits proven GREEN by a NAMED external verifier in an ephemeral sandbox. The PARENT applies the patch to the real tree and commits — Kupo never writes the real tree (PROPOSE-only) and never routes work onward (worker, never router). On out-of-scope or budget exhaustion, Kupo ESCALATEs or REFUSEs. Reverse of vigil-to-kupo (roster handoff).

### `spectra → apivr`

SPECTRA hands off a decision-ready specification for APIVR-Δ to implement. Listed in roster: spectra.handoffs.downstream contains apivr. SPECTRA emits the spec in dual format (Markdown + YAML/JSON state) per its methodology; the envelope.artifact.path points at the Markdown file and the YAML state lives alongside it.

### `spectra → forge`

SPECTRA consults FORGE during the Explore or Construct phase when the scoring rubric for two candidate strategies converges within the decision-band noise floor, or when a stakeholder constraint forces a trade-off that the rubric cannot disambiguate. Listed in roster: spectra.handoffs.lateral contains forge. Same lightweight body shape as apivr-to-forge; FORGE owns the response.

### `spectra → kupo`

SPECTRA DELEGATEs a localized, verifier-backed micro-task to Kupo (the low-effort executor) — e.g. a rename, import fix, lockfile/dep-pin bump, config-key edit, or one-line fix identified within its own spec. Kupo KEEPs only localized (<= 2 files), named-verifier-backed work (else REFUSE/ESCALATE cheaply), patches an ephemeral sandbox, proves it with an external verifier, and returns a verified edit-proposal via kupo-to-spectra. Declared in roster: kupo.handoffs.upstream contains spectra.

### `vigil → apivr`

VIGIL returns a root-cause attribution (and, when authority allows, a verified patch) to the APIVR-Δ that escalated. Listed in roster: vigil.handoffs.lateral contains apivr. CRITIQUE is reserved for the case where VIGIL disputes APIVR-Δ's repair hypothesis without yet supplying a verified alternative.

### `vigil → forge`

VIGIL consults FORGE during the Graph or Intervene phase when the dependency-graph ranking surfaces ≥2 hypotheses with comparable counterfactual support, or when the ≤5-intervention budget approaches exhaustion without a single blame-target emerging. Listed in roster: vigil.handoffs.lateral contains forge. Same body shape as apivr-to-forge; FORGE owns the response.

### `vigil → idg`

VIGIL routes a finalised attribution to IDG when the incident merits chronicling (post-mortem, ADR, runbook update). Listed in roster: vigil.handoffs.lateral contains idg. chronicle_hooks names the documentation surfaces IDG should target.

### `vigil → kupo`

VIGIL DELEGATEs a localized, verifier-backed micro-task to Kupo (the low-effort executor) — e.g. a rename, import fix, lockfile/dep-pin bump, config-key edit, or one-line fix identified within its own root-cause-report. Kupo KEEPs only localized (<= 2 files), named-verifier-backed work (else REFUSE/ESCALATE cheaply), patches an ephemeral sandbox, proves it with an external verifier, and returns a verified edit-proposal via kupo-to-vigil. Declared in roster: kupo.handoffs.upstream contains vigil.

### `vigil → spectra`

VIGIL routes a root cause to SPECTRA when the systemic finding indicates the spec itself is defective and re-planning is required (SPEC_DEFECT routing per VIGIL methodology). Listed in roster: vigil.handoffs.lateral contains spectra. The added structural_fix_notes section flags the re-plan target.


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
| **With debugger** | add `vigil` to any | Flaky tests, regressions, or post-mortems likely |
| **Diagnostics** | `apivr, vigil, forge` | Brownfield debugging; APIVR-Δ builds/fixes, VIGIL attributes, FORGE deliberates on ambiguous cases |

These map to presets in [`../roster/index.yaml`](../roster/index.yaml) — `eidolons init --preset solo-scout`, etc.

### Host mismatches

A team may span hosts — e.g., the user runs ATLAS in Claude Code for exploration, then switches to Cursor to run APIVR-Δ for implementation. Supported:

- Each Eidolon's files live in `.eidolons/<n>/` — host-independent
- Host dispatch (`CLAUDE.md`, `.cursor/rules/`, etc.) is auto-wired per the consumer's tooling
- Handoff artifacts live in the repo (`scout-reports/`, `specs/`, `sessions/`) — travel with the code, not with the host

---

## Anti-patterns

**Internal sub-agent pipelines.** An Eidolon that grows a pipeline inside itself (planner → builder → verifier all in one prompt) violates D2. That's what the team is for.

**Implicit handoffs.** An Eidolon that tries to "do a bit of everything" because it sees an adjacent need. Explicit handoff or refusal; no implicit expansion.

**Shared mutable state.** Eidolons do not mutate each other's memory. Handoffs are immutable artifacts written to disk and consumed read-only.

**Version drift.** Installing ATLAS v1.0 but SPECTRA v4.2 when SPECTRA v4.2 was built against ATLAS v1.1 scout-report schema. Compatibility matrix in `../roster/index.yaml` captures supported version ranges; `eidolons doctor` warns on mismatches.

---

## Generation

This file is regenerated by:

```
python3 eidolons-ecl-sdk.bundle.pyz compose-gen \
  --contracts ./contracts \
  --template ./reference-sdk/py/src/eidolons_ecl/compose_gen/templates/composition.md.j2 \
  --out methodology/composition.md
```

Run from the eidolons-ecl repo root. Output is deterministic; the
nexus repo's `composition-drift.yml` CI gate fails if regenerated
output drifts from HEAD.

---

## Related

- [`prime-directives.md`](prime-directives.md) — the ten non-negotiables
- [`vocabulary.md`](vocabulary.md) — shared terminology
- [`../roster/index.yaml`](../roster/index.yaml) — machine-readable handoff contracts per Eidolon
- [`../docs/architecture.md`](../docs/architecture.md) — install-time architecture