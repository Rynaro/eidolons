# V4-18 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority or publication authority.

## V4-18 — Adopt need-based specialist execution across the roster

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-13`, `V4-16`, `V4-17`.

**Scope and decisions.** Adopt approved method/worker contracts in explicit profile slices. Preserve named expertise, aliases, purpose, charters, and ceilings for ATLAS, FORGE, VIGIL, IDG, Kupo, Gilgamesh, SPECTRA, and APIVR-Delta. This is not an unrelated global rename. Classify enforceable rules, heuristics, and rationale. Embedded methods cannot substitute silently for a specifically requested independent invocation. Adoption can use external packages without depending on consolidation. Unproven benefits labeled experimental/maintenance — never measured wins without V4-21 evidence. No V4-22/V4-23.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-18-R01 | WHEN a task requires expertise but no separate execution boundary, routing SHALL permit an embedded method instead of a mandatory specialist worker. | **V4-18-T01** |
| V4-18-R02 | WHEN the user explicitly requests a separate specialist or independent review, routing SHALL preserve that execution requirement. | **V4-18-T02** |
| V4-18-R03 | IF a specialist contribution requires a distinct context, permission boundary, or independent track, THEN routing SHALL record that reason on its assignment. | **V4-18-T03** |
| V4-18-R04 | WHEN a methodology control is revised, the profile registry SHALL retain its rule, heuristic, or rationale classification and replacement reference. | **V4-18-T04** |
| V4-18-R05 | WHEN a profile version is adopted, compatibility validation SHALL check the exact producer and consumer versions. | **V4-18-T05** |
| V4-18-R06 | WHEN a method advertises isolated execution, its package SHALL declare a bounded input/output contract compatible with that execution form. | **V4-18-T06** |
| V4-18-R07 | IF a specialist strategy lacks qualifying comparative evidence, THEN the registry SHALL label its performance benefit unproven. | **V4-18-T07** |

## Required slices

ATLAS, FORGE, VIGIL, IDG, Kupo, Gilgamesh, SPECTRA, APIVR-Delta, nexus-adoption — each as a fixture profile registry entry with activation + I/O/execution-form contract + producer/consumer version checks.

## Bounded decision

See [decision.md](decision.md). Schema-2 additive roster_* namespaces. Reuse V4-13 compiler, V4-16 RAMZA, V4-17 Vivi contracts where applicable. No V4-22/V4-23.
