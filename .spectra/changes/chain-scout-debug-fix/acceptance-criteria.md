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
| **AC-3** | **RESTATED** (the original — *"no existing chain route changes"* — was falsified by a checker). Exactly **6 of 57** class subsets change, and every one **gains** coverage of a class that triggered it; **no subset loses coverage of a class that triggered it**. Templates untouched on every subset are byte-identical. `decide-then-implement`, `audit-without-touching`, `forensic-then-fix` and `scout-diagnose-plan-fix` **do** change on scout-bearing subsets | all-subsets route differential vs `db82fb2` (enumerated in `verification.md`); the pinned coverage-violation **set**; `public` 15/15; `N-015`. **The original evidence trio (`public`/`N-015`/`N-C04`) is all true and none of it can fail on the property AC-3 states — that is why the defect got through** |
| **AC-4** | Unresolved tie set moves **5 → 4** with NO new ambiguity | corrected subset audit; ambiguity pin |
| **AC-8** | The coverage guard **cannot be paid off**. Pinning a count let a checker trade a fixed violation against a smuggled one at constant total; the guard pins the **set** | replayed gaming attack goes RED |
| **AC-5** | **Every assertion this change adds can fail**, under a mutation that breaks what it guards — including one removing only the trailing `idg`, and one reintroducing the FORGE drop | 8 mutations in `verification.md`; the replayed gaming attack |
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
