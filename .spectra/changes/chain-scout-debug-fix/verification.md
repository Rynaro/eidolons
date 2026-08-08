# Verification — `chain-scout-debug-fix`

> ESL change `chain-scout-debug-fix` · tier **full**
> Maker: `vivi` · Checker: `kupo` (maker ≠ checker, C4 — mechanically enforced)

## Evidence

| AC | Result | Evidence |
|---|---|---|
| **AC-1** | **PASS** | 3/3 scout+debugger+coder phrasings → `scout-diagnose-fix` → `[atlas, vigil, vivi, idg]` (`N-C07`, `N-C09`) |
| **AC-2** | **PASS** | `"audit the module, diagnose the failure, fix it and document it"` → `[atlas, vigil, vivi, idg]`, was `[atlas, idg]` (`N-C08`) |
| **AC-3** | **PASS** | `public` 15/15; `N-015` still `[vigil, vivi]`; `N-C04` still `scout-diagnose-plan-fix`; `plan-before-build` / `decide-then-implement` / `ship-fast` / `scout-then-spec` / `audit-without-touching` unchanged |
| **AC-4** | **PASS** | corrected subset audit: **5 → 4**, set difference is exactly `audit-without-touching\|forensic-then-fix\|coder+debugger+scout+scriber`; no new pair |
| **AC-5** | **PASS — 4/4 mutations red** | table below |
| **AC-6** | **PASS** | `make lint` 0 · `make schema` 0 · token budget 836/850 · self-test **99 tasks** |
| **AC-7** | **PASS** | `bats cli/tests/` → **1714/1714**, 0 failures, 7 skipped (counted against the plan, not read off the tail) |

Suites: recall **80/80**, public **15/15**, `routing_chains.bats` **10/10**.

## AC-5 — falsifying the new assertions

Baseline unmutated green; every mutation **red**:

| # | Mutation | Test that must go red | Result |
|---|---|---|---|
| M1 | delete `scout-diagnose-fix` | scout-step route | **RED** ✓ |
| M2 | delete `scout-diagnose-fix` | read-only-pair route | **RED** ✓ |
| M3 | delete `scout-diagnose-fix` | ambiguity pin (set returns to 5) | **RED** ✓ |
| M4 | drop **only** the trailing `idg` | read-only-pair route | **RED** ✓ |

M4 is the load-bearing one. It is the mutation that would reintroduce a silent
scriber step-drop — the defect two earlier checkers found in this family — and
it is caught rather than assumed.

## What the baseline measurement turned up that was not on the record

`chain-three-class` recorded the scout drop. It did **not** record that adding
a scriber made the same combination resolve, by declaration order, to
`audit-without-touching` → `[atlas, idg]` — a prompt explicitly asking for a
fix answered with a read-only scout and a scribe, with both the diagnosis and
the repair dropped. That is strictly worse than the residual as written, and it
was found by measuring the baseline before touching anything rather than by
trusting the prior record's description of the gap.

## Residual — disclosed

- **`[scout, coder]` has no template.** `"explore the module and implement the
  change"` → `vivi` alone, scout dropped. A distinct combination this change
  does not measure; recorded rather than fixed, because closing one gap by
  opening an unmeasured one is the pattern four checker rounds removed.
- **Four order-dependent ties remain**, unchanged, still decided by declaration
  order, still pinned and not endorsed.
- A three-class scout+debugger+coder prompt now receives an `idg` step it did
  not explicitly ask for — the same trade `plan-before-build` has always made,
  stated rather than hidden.

## Note on the strength of this record's drift check

**Same weakness as the two records archived on 2026-08-08.** The ESL change was
opened at `proposed` before any edit, but `spec.yaml` and `spec.md` were
written **after** `roster/routing.yaml` was edited and the routes measured —
the order was: propose → implement → verify → *then* write the declaration.

So the declaration still cannot disagree with the work. The drift check at
close answers "did anything land outside the stated scope?" and **not** "did
the design move away from what was planned?". A frozen plan-time
`declared_scope` is what would answer the second question, and this change does
not have one.

Recorded plainly because an earlier draft of this very section claimed the
opposite — that the spec preceded the implementation — which was false and
would have overstated the check. That is the same species of overclaim three
checker rounds removed from the sibling records.
