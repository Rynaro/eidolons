# chain-three-class — the chain that dropped the diagnosis

**maker:** vivi · **checker:** kupo · **tier:** full · **repo:** Rynaro/eidolons
**released as:** v2.19.0 (`f152c4c`, PR #553)

## Problem

The routing kernel picks the matching chain template with the most
`requires_classes` — `sort_by(-spec) | .[0]` in `cli/src/run.sh`. No template
covered `debugger + planner + coder`.

Measured on `main` @ `13013ae`, over a 13-prompt probe:

| Prompt shape | Selected template | Result |
|---|---|---|
| debugger+planner+coder (4/4 probes) | `ship-fast` → `[ramza, vivi]` | **diagnosis dropped** |
| scout+debugger+planner+coder | `plan-before-build` | **diagnosis dropped** |
| scout+debugger+coder | `forensic-then-fix` | scout dropped |

The consequence is not cosmetic. A prompt like *"diagnose the flaky test, plan
the fix and implement it"* handed **a planner a failure nobody had root-caused**
— and because the fallback is a legitimate template, the dropped step left no
trace in the routing artifact. Nothing reported a miss.

This was recorded as a known residual when `routing-recall-gap` shipped in
v2.18.0, rather than fixed there, because the chain-selection surface was not
covered by that change's guard set.

## Decision

Two template entries in `roster/routing.yaml`. **DATA only** — the selection
algorithm is untouched, so invariant I-C2 (the kernel interprets; there is no
eval) holds.

```yaml
- name: scout-diagnose-plan-fix
  steps: ["atlas", "vigil", "ramza", "vivi", "idg"]
  requires_classes: ["scout", "debugger", "planner", "coder"]

- name: diagnose-then-plan-then-fix
  steps: ["vigil", "ramza", "vivi"]
  requires_classes: ["debugger", "planner", "coder"]
```

`scout-diagnose-plan-fix` ends with `idg` because the entry it supersedes
(`plan-before-build`) did. The first revision omitted it, and a checker found
that a prompt explicitly asking for documentation therefore **lost the docs
step** — the same silent step-drop this change exists to remove, transplanted
onto the scriber class.

### Why the four-class entry is not optional

jq's `sort_by` is **stable**. Two templates of equal specificity that both match
are therefore resolved by *which one is declared first in the file* — an
artifact, not a decision anyone made.

Adding `diagnose-then-plan-then-fix` alone would collide with
`plan-before-build` (both specificity 3) on a scout+debugger+planner+coder
prompt. `scout-diagnose-plan-fix` covers the union of that pair's classes at
specificity 4, so specificity stays decisive and the stable-sort fallback is
never reached for that shape.

## The invariant that turned out to be false

The first draft of the `chains:` header comment asserted the template list was
*"closed under intersection — whenever two entries could both match, a strictly
more specific entry exists."*

It was audited before shipping. **It is false** — and the audit itself was then
wrong about *how* false. The corrected count is **five**:

```
audit-without-touching vs  forensic-then-fix        coder+debugger+scout+scriber
audit-without-touching vs  scout-then-spec          planner+scout+scriber
decide-then-implement  vs  audit-without-touching   coder+reasoner+scout+scriber
decide-then-implement  vs  forensic-then-fix        coder+debugger+reasoner
decide-then-implement  vs  ship-fast                coder+planner+reasoner
```

### The audit was itself computed with the wrong operator

The first revision claimed **seven**. That number came from a jq expression
testing set **equality** with the union:

```jq
(($t[$i].req + $t[$j].req) | unique) as $u | select([ $all[] | select(. == $u) ] | length == 0)
```

The kernel selects `select(requires_classes ⊆ classes) | sort_by(-spec) | .[0]`
— **subset**, not equality. A pair is resolved whenever *any* template `C` has
`C.req ⊆ (A ∪ B)` and `|C| > |A|`. Testing equality over-reports, and it is
blind to a template that merely duplicates an existing class set (such a pair
always ties, since no strict superset can exist inside their own union).

Two of the seven were provably not ties — `decide-then-implement vs
scout-then-spec` and `audit-without-touching vs ship-fast` are both resolved by
`plan-before-build`. Confirmed twice: by exhaustive enumeration over all 57
class subsets, and by reordering the pair in a live roster and observing the
route not change.

**And the expected list had been generated with that same expression**, so both
sides of the pin agreed and the gate passed while proving nothing — the exact
tautology this project keeps rediscovering, one refinement deeper.

The parent `13013ae` had **six**, not the nine the wrong instrument reported.
So this change did not merely avoid adding a tie: it **resolved** one
(`ship-fast` vs `forensic-then-fix` at coder+debugger+planner), moving the set
6 → 5. The first revision never claimed that, because it could not see it.

These five are **recorded, not endorsed**. Resolving them means choosing
semantics for each pair, which is a different change.

## Verification approach

`cli/tests/routing_chains.bats` pins the multi-class routes and the ambiguity
set. Because a test authored alongside the data it checks passes trivially,
assertions are **falsified by mutation** before being trusted:

| Mutation | Test that must go red | Result |
|---|---|---|
| delete `diagnose-then-plan-then-fix` | 3-class route | **RED** ✓ |
| add a template creating a new collision | ambiguity pin | **RED** ✓ |
| step → `nosuchmember` | member existence | **RED** ✓ |
| delete `scout-diagnose-plan-fix` | tie cover | **RED** ✓ |
| add a template DUPLICATING an existing class set | ambiguity pin | **RED** ✓ (new) |

The duplicate-class-set case is the one the equality-based helper could not
detect: a checker demonstrated all six original assertions staying green while
the live route flipped to `idg>kupo`. The subset form catches it automatically.

Known gap, stated rather than implied: the "pre-existing routes unchanged" test
has no falsifying mutation on record. The four mutations above leave it green.

## Anti-scope

- The five remaining ties are **not** resolved.
- No `priority` field; no change to the selection algorithm.
- `scout+debugger+coder` still drops the scout step to `forensic-then-fix`.
  Adding `[scout, debugger, coder]` would be safe against the ambiguity pin
  (its unions are already covered) but is a distinct, unmeasured combination.
