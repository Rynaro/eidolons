# Cortex Deep — Hand-off Graph

> Load this file when composing a multi-Eidolon chain or auditing
> which edges are declared vs inferred. See `EIDOLONS.md` for the
> always-loaded routing cortex.

---

## Canonical Hand-off Graph

The cortex adopts the **union** of roster-declared edges and
`methodology/composition.md` prose-described edges, with origin labels.
Every chain step records `edge_origin: "roster" | "composition" | "implicit"`.

```
ATLAS  ──(roster:downstream)──▶  SPECTRA
ATLAS  ──(roster:downstream)──▶  APIVR-Δ        # documented bypass
SPECTRA ──(roster:downstream)──▶ APIVR-Δ
APIVR-Δ ──(roster:downstream)──▶ IDG
SPECTRA ──(composition.md)────▶  IDG            # plan-only docs
ATLAS  ──(composition.md)────▶  IDG            # read-only audits
VIGIL  ──(composition.md:49-51)▶ SPECTRA / IDG / FORGE  # not yet in roster
FORGE  ──(composition.md:67-68)▶ <any caller>  # consultation return
ANY    ──(any)──▶  human                        # implicit terminal
```

`[DISPUTED]` edges (roster vs composition.md disagree): VIGIL downstream edges
are declared only in composition.md, not in `roster/index.yaml`. Until
`roster/index.yaml` is reconciled (OQ-3), the cortex emits `[DISPUTED]` on
any chain step using a VIGIL downstream edge.

---

## Disambiguation Table

| Prompt class | Default route | Override condition |
|---|---|---|
| "Fix the bug" | APIVR-Δ standard | Prior attempt failed in this conversation OR stack trace + "flaky" → VIGIL |
| "Design X" | SPECTRA standard | Prompt also asks to write code → SPECTRA → APIVR-Δ chain |
| "Find and fix" | ATLAS → APIVR-Δ direct | Surface > complexity threshold OR "unclear requirements" → ATLAS → SPECTRA → APIVR-Δ |
| "Document this" | IDG | Prior artifact missing on disk → re-route ATLAS first (IDG refuses retrieval) |
| "Should we use X or Y?" | FORGE | Decision is also implementable → FORGE → SPECTRA chain |
| "Audit the auth flow" | ATLAS standard | Auditor wants written narrative → ATLAS → IDG |
| "Write a runbook" with no source artifacts | CLARIFY (IDG cannot retrieve) | User provides artifacts → IDG |

---

## Chain Template Justifications

| Template | Edge origins | Spec source |
|---|---|---|
| plan-before-build | roster (ATLAS→SPECTRA), roster (SPECTRA→APIVR-Δ), roster (APIVR-Δ→IDG) | MANIFESTO.md §"What you can do" row 1; composition.md |
| audit-without-touching | composition.md (ATLAS→IDG) | Preset `research`; MANIFESTO.md:79 |
| ship-fast | roster (SPECTRA→APIVR-Δ) | Preset `plan-and-build` |
| direct-implementation-bypass | roster (ATLAS→APIVR-Δ) | roster/index.yaml:60; spec §7.3 |
| decide-then-implement | composition.md (FORGE→caller), roster (SPECTRA→APIVR-Δ) | composition.md:60-69 |
| forensic-then-fix | composition.md (VIGIL→APIVR-Δ) | roster/index.yaml:298; composition.md:46-48 |
| failed-attempt-recovery | composition.md (APIVR-Δ failure → VIGIL) | apivr-failure-recovery/SKILL.md:14-27 |
| decision-only | (terminal FORGE) | composition.md:60-69 |

---

## Open Questions Carried Forward

| ID | Assumption | Mitigation |
|---|---|---|
| OQ-3 | Hand-off graph union (roster + composition.md) is acceptable until roster/index.yaml and composition.md are reconciled. | File a roster issue; cortex emits `[DISPUTED]` until resolved. |
| OQ-6 | Max 2 reroutes per turn is sufficient to prevent ping-pong. | Raise cap with explicit `[BLOCKED]` exit; never remove the cap. |
