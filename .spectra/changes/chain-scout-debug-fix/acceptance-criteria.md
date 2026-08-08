# Acceptance Criteria — `chain-scout-debug-fix`

> ESL change `chain-scout-debug-fix` · tier **full** · maker `vivi` · checker `kupo`
> Closes the residual recorded by `chain-three-class` (archived 2026-08-08).

## Problem (measured on `main` @ `db82fb2`)

| Prompt shape | Selected | Consequence |
|---|---|---|
| scout+debugger+coder (3/3 phrasings) | `forensic-then-fix` → `[vigil, vivi]` | **scout dropped** |
| scout+debugger+coder+**scriber** | `audit-without-touching` → `[atlas, idg]` | **diagnosis AND fix dropped** — a repair request answered read-only, decided by declaration order |

## Criteria

| ID | Criterion | Method |
|---|---|---|
| **AC-1** | scout+debugger+coder selects `scout-diagnose-fix` → `[atlas, vigil, vivi, idg]` | `N-C07`, `N-C09`; `routing_chains.bats` |
| **AC-2** | scout+debugger+coder+scriber no longer returns the read-only `[atlas, idg]` | `N-C08`; `routing_chains.bats` |
| **AC-3** | No existing chain route changes — incl. debugger+coder **without** a scout staying on `forensic-then-fix` | `public` 15/15 + `N-015`, `N-C04` |
| **AC-4** | Unresolved tie set moves **5 → 4** with NO new ambiguity | corrected subset audit; ambiguity pin |
| **AC-5** | **Both new assertions can fail**, including under a mutation that removes only the trailing `idg` | mutation run in `verification.md` |
| **AC-6** | lint / schema / cortex token budget / suite self-test clean | CI parity |
| **AC-7** | Full bats suite green, counted against the plan | `bats cli/tests/` |

**AC-5 is load-bearing**, as in every change in this family: a test written
alongside the data it checks passes trivially. The `idg`-removal mutation is
the specific one that matters — it is what would reintroduce a silent
step-drop.

## Anti-scope

- The **four** remaining order-dependent ties are not resolved. Each needs a
  semantic decision per pair, not a mechanism.
- No change to the selection algorithm, the kernel form predicates, or any
  signal.
- **`[scout, coder]`** (`"explore the module and implement the change"` →
  `vivi` alone, scout dropped) is a distinct combination this change does not
  measure. Recorded as a residual, deliberately not fixed here — closing a gap
  by opening an unmeasured one is the pattern this campaign spent four checker
  rounds removing.
