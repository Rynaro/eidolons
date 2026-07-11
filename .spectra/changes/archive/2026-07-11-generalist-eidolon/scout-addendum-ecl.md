# Scout addendum — GAP-001 closed (eidolons-ecl inspection)

**Producer:** orchestrator (Fable), 2026-07-10 — shallow clone of `Rynaro/eidolons-ecl` @ HEAD.

- **FINDING-020** (H): `eidolons-ecl/contracts/` holds **54 directed-edge YAML contracts** (one per edge, incl. `human-to-<member>` edges). Contract shape: `contract_version, from, to, edge_origin, performatives_allowed (subset of the closed 10), artifacts[{kind, schema_ref, required_sections, evidence_anchor_required}], context_delta{token_budget_max, required_handles}, trust_level, notes`.
- **FINDING-021** (H): `methodology/composition.md` **is** auto-generated — regen command documented at `composition.md:402-412`:
  `python3 eidolons-ecl-sdk.bundle.pyz compose-gen --contracts ./contracts --template .../composition.md.j2 --out methodology/composition.md` (run from eidolons-ecl root; deterministic output; nexus CI gate `composition-drift.yml` fails on drift).
- **Consequence for the campaign:** any new member (or any rewiring of Kupo's edges) requires an upstream `eidolons-ecl` PR adding/editing edge contracts + per-artifact JSON schema under `schemas/per-eidolon/`, then a nexus-side regen of composition.md. Edge count for a new generalist ≈ 1 human-to-X + upstream edges (atlas→X, forge→X?) + downstream edges (X→vivi, X→idg, X→vigil, X→kupo?, X→forge?) — final set determined by the spec's `handoffs` block.
