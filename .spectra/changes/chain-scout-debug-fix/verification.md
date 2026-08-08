# Verification — `chain-scout-debug-fix`

> ESL change `chain-scout-debug-fix` · tier **full**
> Maker: `vivi` · Checker: `kupo` (maker ≠ checker, C4 — mechanically enforced)

## Checker round 1 — **REJECT**

| # | Severity | Finding | Status |
|---|---|---|---|
| H1 | **HIGH** | `scout-diagnose-fix` took `{scout,debugger,reasoner,coder}` (± scriber) over from `decide-then-implement` and **dropped the FORGE step**. Reproduced on four natural prompts. `forge` scored **0.8**; the hardcoded `idg` scored **0.0** — the template hardcoded the class that scored zero and excluded the one that scored 0.8. A user asking to *decide between rollback or patch* got no deliberation step. | **FIXED** |
| H2 | **HIGH** | The test cited as AC-3's evidence pins a **scout-free** prompt, so it cannot go red on a scout-bearing route flip. And the ambiguity pin counts **pairs** — the pair survived at its smaller witness while the route changed, so it stayed green. Pair-counting structurally cannot see a route flip. | **FIXED** |
| M1 | medium | `EIDOLONS.md:77` still said "Eight templates" (now 11) — the always-loaded cortex, mirrored to consumers by `eidolons sync`. Two other docs were re-synced; this one was missed. | **FIXED** |
| L1–L4 | low | CHANGELOG said "four new assertions" (that is the mutation count); `verification.md` listed `audit-without-touching` as unchanged while AC-2 says it changed; two measured phrasings unpinned; `change.json` carries `acceptance_checks: []`. | **FIXED / noted** |

AC-1, AC-2, AC-4, AC-5, AC-6, AC-7 all verified independently and held. Over-reach probes found none.

## Remediation

- **`scout-diagnose-decide-fix`** (`atlas → vigil → forge → vivi → idg`) for
  `[scout, debugger, reasoner, coder]`, plus
  **`scout-diagnose-decide-plan-fix`** for all five routed classes, covering the
  union so the two spec-4 entries cannot tie.
- **A route-level ratchet** (`routing_chains.bats`). H2 is the durable finding:
  the ambiguity pin measures pairs and a route can flip beneath it. The new
  check enumerates **all 57 class subsets** and counts those whose selected
  chain omits a triggered class.
- AC-3 and `safety_invariant` **retracted and restated** as what was measured.
- `EIDOLONS.md` template-count sentence de-numbered so it cannot go stale again.

## The systemic finding this exposed

Running the coverage check against **shipped v2.19.1** gives **30 violations
out of 57 subsets**. Step-drops are not an edge case in this design — they are
the majority behaviour. Chain selection matches one template per class
combination; with 57 subsets and 11 templates, most subsets fall back to a
lower-specificity entry that omits a triggered class.

This change takes it **30 → 24**. It does not solve the shape, and the record
does not claim to. The ratchet bounds it; a durable fix would mean synthesizing
the chain from the triggered classes in a canonical order rather than matching
a template — a kernel redesign, out of scope here and recorded as a
recommendation.

## Evidence

| AC | Result | Evidence |
|---|---|---|
| **AC-1** | **PASS** | 3/3 scout+debugger+coder phrasings → `scout-diagnose-fix` → `[atlas, vigil, vivi, idg]` (`N-C07`, `N-C09`) |
| **AC-2** | **PASS** | `"audit the module, diagnose the failure, fix it and document it"` → `[atlas, vigil, vivi, idg]`, was `[atlas, idg]` (`N-C08`) |
| **AC-3** | **PASS (restated)** | All-subsets route differential vs `db82fb2`: **6 of 57 change, 51 identical**, and every changed subset **gains** triggered-class coverage — none loses a class it carried. `plan-before-build` / `ship-fast` / `scout-then-spec` / `forensic-then-fix` / `diagnose-then-plan-then-fix` / `scout-diagnose-plan-fix` unchanged; `public` 15/15; `N-015` still `[vigil, vivi]`. **`decide-then-implement` and `audit-without-touching` DO change on scout-bearing subsets** — the original wording claimed otherwise and was falsified |
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
| M5 | delete `scout-diagnose-decide-fix` | **route-level ratchet** | **RED** ✓ |
| M6 | delete `scout-diagnose-decide-fix` | targeted-combination test | **RED** ✓ |

M4 and M5 are the load-bearing ones. M4 is the mutation that would reintroduce
a silent scriber step-drop. M5 reintroduces the exact FORGE drop the checker
found — and it is caught by the route-level ratchet, which is the instrument
that did not exist when the defect got through.

Six mutations, twelve assertions. AC-5 says *"every new assertion goes red
under a mutation that breaks what it guards"* — that is true of the assertions
this change adds; it is **not** a claim that every assertion in the file has a
dedicated mutation (the "pre-existing routes unchanged" test still has none,
as recorded in the sibling `chain-three-class`).

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
