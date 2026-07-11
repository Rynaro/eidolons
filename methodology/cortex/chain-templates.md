# Cortex Deep — Chain Templates

> Load this file when composing a multi-Eidolon chain (Dispatch Protocol
> Step 2, ≥2 co-triggering capability classes). See `EIDOLONS.md` for the
> always-loaded routing cortex and `roster/routing.yaml` for the
> machine-readable `chains:` block the kernel actually matches against
> (`eidolons run`; `requires_classes` selects the most-specific template).

Relocated out of the EIDOLONS.md always-loaded region per R-021/R-022
(generalist-eidolon P2 cortex re-fit) — this table was mislabeled
"(always-loaded)" while not actually needed for single-Eidolon dispatch.

---

## Chain Templates

| Template | Steps | When |
|----------|-------|------|
| **plan-before-build** | ATLAS → RAMZA → Vivi → IDG | Unfamiliar code + multi-component change |
| **audit-without-touching** | ATLAS → IDG | "Audit", "explain", "review" with no write intent |
| **ship-fast** | RAMZA → Vivi | Known terrain, scoped feature |
| **direct-implementation-bypass** | ATLAS → Vivi (skip RAMZA) | Complexity < 7/12 AND small surface AND unambiguous reqs; emit `[DECISION]` |
| **decide-then-implement** | FORGE → RAMZA → Vivi | "Should we use X or Y, then build it" |
| **forensic-then-fix** | VIGIL → Vivi | Bug with reproduction + verified patch suggestion |
| **failed-attempt-recovery** | (prior coder failure) → VIGIL → Vivi | Conversation shows prior coder Reflect-exhaustion |
| **decision-only** | FORGE | No code touching; deliberation emitting verdict + assumptions |

Gilgamesh (generalist, fallback-only) never appears in a chain template —
it lives solely in Dispatch Protocol Step-2(a) (no specialist scores ≥ τ,
predicate resolves actionable). A chain always wins over the Step-2(a)/(b)
split when ≥2 capability classes co-trigger (Step 2's chain branch is
evaluated first).

See `methodology/cortex/handoff-graph.md` §"Chain Template Justifications"
for the edge-origin provenance of each template.
