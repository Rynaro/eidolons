# Verification — `chain-three-class`

> ESL change `chain-three-class` · tier **full**
> Maker: `vivi` · Checker: `kupo` (maker ≠ checker, C4)

## Evidence

| AC | Criterion | Result | Evidence |
|---|---|---|---|
| **AC-1** | 3-class debugger chain | **PASS** | `N-C01..N-C03` → `[vigil, ramza, vivi]` |
| **AC-2** | 4-class resolves by specificity | **PASS** | `N-C04` → `[atlas, vigil, ramza, vivi]`, template `scout-diagnose-plan-fix` |
| **AC-3** | No existing route changed | **PASS** | `public` 15/15; `N-015` still `[vigil, vivi]`; `N-C06` still `[ramza, vivi]`; `plan-before-build` / `decide-then-implement` unchanged |
| **AC-4** | No new order-dependent tie | **PASS** | unresolved set = exactly the 7 pre-existing pairs |
| **AC-5** | **The new tests can fail** | **PASS — 4/4 mutations red** | table below |
| **AC-6** | Steps name real members | **PASS** | `routing_chains.bats` |
| **AC-7** | lint / schema / token budget / self-test | **PASS** | all exit 0; suite self-test 73 tasks; recall-mutation gate PASS at 16.6 % vs `v2.17.0` |
| **AC-8** | Full bats suite | **PASS — 1709/1709** | `bats cli/tests/`, counted against the plan (not read off the tail) |

Suites: recall **54/54**, public **15/15**.

## AC-5 — falsifying the new tests

Four mutations, each breaking exactly what one assertion claims to protect.
Baseline (unmutated) green; every mutation **red**:

| # | Mutation | Test that must go red | Result |
|---|---|---|---|
| M1 | delete `diagnose-then-plan-then-fix` | 3-class route | **RED** ✓ |
| M2 | add a template creating a new equal-specificity collision | ambiguity pin | **RED** ✓ |
| M3 | point a template step at `nosuchmember` | member existence | **RED** ✓ |
| M4 | delete `scout-diagnose-plan-fix` (the tie cover) | tie-cover assertion | **RED** ✓ |

M2 and M4 are the ones that matter: they prove the ambiguity pin is a real
gate and not a restatement of the file it reads.

## The claim I had to retract mid-change

The first version of the `chains:` header comment asserted the template list
was "CLOSED UNDER INTERSECTION — whenever two entries could both match, a
strictly more specific entry exists". Auditing it before shipping showed that
is **false**: 7 equal-specificity pairs among the pre-existing 2-class
templates have no covering entry and are still decided by declaration order:

```
decide-then-implement  vs  audit-without-touching   coder+reasoner+scout+scriber
decide-then-implement  vs  ship-fast                coder+planner+reasoner
decide-then-implement  vs  forensic-then-fix        coder+debugger+reasoner
decide-then-implement  vs  scout-then-spec          coder+planner+reasoner+scout
audit-without-touching vs  ship-fast                coder+planner+scout+scriber
audit-without-touching vs  forensic-then-fix        coder+debugger+scout+scriber
audit-without-touching vs  scout-then-spec          planner+scout+scriber
```

The comment now states the true, narrower guarantee: this change does not add
an eighth. Had the audit not been run, a false invariant would have shipped in
a comment that future readers would have trusted.

## Residual

- **`scout+debugger+coder`** (e.g. "map the auth flow, diagnose why login
  fails, and fix it") still selects the 2-class `forensic-then-fix` and drops
  the scout step. A distinct combination, unmeasured by this change; adding
  `[scout, debugger, coder]` would be safe w.r.t. the ambiguity pin (its
  unions are already covered) but is deliberately out of scope here.
- The 7 ties above remain order-dependent. Pinned, not fixed.
