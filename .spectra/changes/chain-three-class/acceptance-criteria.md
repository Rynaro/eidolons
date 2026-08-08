# Acceptance Criteria — `chain-three-class`

> ESL change `chain-three-class` · tier **full** · maker `vivi` · checker `kupo`
> Spec ref: `roster/routing.yaml` · follows `routing-recall-gap` (nexus v2.18.0)

## Problem

`routing-recall-gap` closed the recall hole but recorded a residual: no chain
template covers three capability classes including `debugger`. Measured on
`main` @ `13013ae`:

| Prompt shape | Selected template | Result |
|---|---|---|
| debugger+planner+coder (×4 probes) | `ship-fast` | **diagnosis step dropped** |
| scout+debugger+planner+coder | `plan-before-build` | **diagnosis step dropped** |
| scout+debugger+coder | `forensic-then-fix` | scout step dropped |

The kernel selects `sort_by(-spec) | .[0]` over templates whose
`requires_classes` ⊆ the prompt's triggered classes. With no 3-class debugger
template, a "diagnose it, spec it, fix it" prompt falls back to the 2-class
`ship-fast` — handing a **planner a failure nobody had root-caused**.

Second-order: jq's `sort_by` is **stable**, so two equal-specificity templates
that both match are resolved by *declaration order in the file*. Adding a
3-class debugger template collides with `plan-before-build` on a
scout+debugger+planner+coder prompt, so the fix must not introduce a new
order-dependent tie.

## Criteria

| ID | Criterion | Method |
|---|---|---|
| **AC-1** | debugger+planner+coder selects `diagnose-then-plan-then-fix` → `[vigil, ramza, vivi]` | recall suite `N-C01..N-C03` |
| **AC-2** | scout+debugger+planner+coder resolves by **specificity**, not file order → `[atlas, vigil, ramza, vivi]` | `N-C04` |
| **AC-3** | No existing chain route changes (2-class and the pre-existing 3-class) | `public` 15/15 + `N-015`, `N-C06` |
| **AC-4** | **No NEW order-dependent tie.** The set of unresolved equal-specificity pairs stays exactly the 7 pre-existing ones | `cli/tests/routing_chains.bats` |
| **AC-5** | **The new tests can fail.** Each is falsified by mutating what it guards | mutation run, recorded in `verification.md` |
| **AC-6** | Every template step names a real roster member | `routing_chains.bats` |
| **AC-7** | lint / schema / token budget / suite self-test clean | CI parity |
| **AC-8** | Full bats suite green | `bats cli/tests/` |

**AC-5 is load-bearing**, for the same reason it was in `routing-recall-gap`:
a test written alongside the data it checks passes trivially. Each new
assertion must be shown red under a mutation that breaks the property it
claims to protect.

## Anti-scope

- **The 7 pre-existing equal-specificity ties are NOT resolved here.** They
  predate this change; fixing them means choosing semantics for each pair, not
  adding a mechanism. They are *pinned* by test so no eighth can appear
  silently — recorded, not endorsed.
- **No `priority` field / no change to the selection algorithm.** The fix is
  DATA: two template entries. Invariant I-C2 holds.
- The `scout+debugger+coder` gap (scout step dropped) is **left open** and
  reported — it is a distinct combination this change does not measure.
