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
| **AC-5** | **Every assertion this change adds can fail**, under a mutation that breaks what it guards — including one removing only the trailing `idg`, and one reintroducing the FORGE drop | every row of the mutation table in `verification.md` goes RED; the replayed gaming attack. The count lives in that table only — restating it here is what let it diverge 4 / 8 / 10 across four files |
| **AC-6** | lint / schema / cortex token budget / suite self-test clean | CI parity |
| **AC-7** | Full bats suite green, counted against the plan | `bats cli/tests/` |
| **AC-9** | This record's own `spec.yaml` parses, and the gate that now checks it goes RED on the defect it names | `make schema` **and CI**; **no root cause is claimed** — two earlier wordings named one and a checker falsified both. Falsified across the modes measured: an embedded `": "` on an entry's first line and on a continuation, **and a bare trailing `:` with no `": "` present** (what breaks the archived `routing-recall-gap`), with a block-scalar control. That list is not asserted exhaustive |
| **AC-10** | Every `roster/routing.yaml` template is documented in the cortex deep table, and the gate asserting it goes RED on the pre-fix table | `routing_chains.bats`; falsified five ways incl. a doc-only-row control proving containment ≠ equality. Scope limits (name presence not steps; vacuous pass on an empty enumeration) disclosed in the bats comment and AC-10's evidence |
| **AC-11** | The recall eval arm scores 100%, so the cases cited as AC-1/AC-2 evidence can fail | `eval.bats` "the recall arm scores 100%"; falsifiable — the `idg`-drop takes recall to 80/83 while public stays 15/15. Three assertions of **different natures**: `total == declared` (derived), `total >= 83` (a **hardcoded ratchet**, sole guard in the recall band 49–82, which does **not** self-raise — bump it in the commit that grows the arm), `passed == total` (accuracy, self-raising). Floor coverage measured: 77 RED · 82 RED · 83/84/90 green, so grow-to-90-then-shrink-to-84 is **undetected** |

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
