# chain-scout-debug-fix — the scout step, and a fix request answered read-only

**maker:** vivi · **checker:** kupo · **tier:** full · **repo:** Rynaro/eidolons
**closes the residual of:** `chain-three-class` (archived 2026-08-08, v2.19.0)

## Problem

Measured on `main` @ `db82fb2` (v2.19.1). Three phrasings of
scout + debugger + coder all selected the two-class `forensic-then-fix`:

| prompt | selected | dropped |
|---|---|---|
| `map the auth flow, diagnose why login fails, and fix it` | `[vigil, vivi]` | **scout** |
| `explore the worker, debug the broken install path and fix it` | `[vigil, vivi]` | **scout** |
| `trace the request path, diagnose the timeout, then patch it` | `[vigil, vivi]` | **scout** |

That much was already on the record. What was **not** recorded, and turned up
while measuring the baseline, is worse:

```
audit the module, diagnose the failure, fix it and document it
  -> chain: audit-without-touching  ->  [atlas, idg]
```

Adding a scriber makes this combination one of the order-dependent ties, and
`audit-without-touching` is declared before `forensic-then-fix`, so it wins on
file order. **Both the diagnosis and the fix are dropped**, and a prompt that
explicitly asked for a repair comes back with a read-only scout and a scribe.
Nobody chose that; a line number did.

## Decision

**Three templates.** DATA only — the selection algorithm is untouched, so I-C2
holds.

```yaml
- name: scout-diagnose-fix                    # the gap this change targeted
  steps: ["atlas", "vigil", "vivi", "idg"]
  requires_classes: ["scout", "debugger", "coder"]

- name: scout-diagnose-decide-fix             # added after checker finding H1
  steps: ["atlas", "vigil", "forge", "vivi", "idg"]
  requires_classes: ["scout", "debugger", "reasoner", "coder"]

- name: scout-diagnose-decide-plan-fix        # covers the union of the two spec-4 entries
  steps: ["atlas", "vigil", "forge", "ramza", "vivi", "idg"]
  requires_classes: ["scout", "debugger", "reasoner", "planner", "coder"]
```

The first alone was rejected: it took `{scout,debugger,reasoner,coder}` over
from `decide-then-implement` and **dropped FORGE**, which scored 0.8 while the
hardcoded `idg` scored 0.0. Diagnosis precedes deliberation (`vigil` → `forge`)
for the same reason `diagnose-then-plan-then-fix` orders it that way: the
options FORGE weighs are *produced by* the diagnosis, so deliberating first
means deliberating on speculation.

### Why it ends in `idg`

For the same reason `plan-before-build` and `scout-diagnose-plan-fix` do: it
supersedes entries that carried a trailing scriber step. Without it, the
scriber case above would trade one silent step-drop for another — losing `idg`
while gaining the diagnosis — which is precisely the defect this family of
changes exists to remove. The cost is a docs step on a three-class prompt that
did not explicitly ask for one; that is the same trade `plan-before-build` has
always made, and it is visible in the artifact rather than silent.

### Why it adds no ambiguity

Its unions with the other two spec-3 templates (`plan-before-build`,
`diagnose-then-plan-then-fix`) are both `{scout, debugger, planner, coder}`,
already covered by `scout-diagnose-plan-fix` at spec 4. And because
`{scout, debugger, coder} ⊆ {coder, debugger, scout, scriber}` with strictly
greater specificity, it **resolves** the `audit-without-touching` vs
`forensic-then-fix` tie outright. The unresolved set moves **5 → 4**.

Verified with the corrected subset audit, not asserted.

## Verification approach

Both new assertions were **falsified by mutation** before being trusted:

| Mutation | Test that must go red | Result |
|---|---|---|
| delete `scout-diagnose-fix` | scout-step route | **RED** ✓ |
| delete `scout-diagnose-fix` | read-only-pair route | **RED** ✓ |
| delete `scout-diagnose-fix` | ambiguity pin (set returns to 5) | **RED** ✓ |
| drop **only** the trailing `idg` | read-only-pair route | **RED** ✓ |

The last one matters most: it is the mutation that would reintroduce a silent
step-drop, and it is caught.

## Residual — disclosed

- **`[scout, coder]` has no template.** `"explore the module and implement the
  change"` dispatches to `vivi` alone, dropping the scout step. A different
  combination, unmeasured by this change, recorded rather than fixed.
- **Four order-dependent ties remain** among the two-class templates,
  unchanged. They are still resolved by declaration order and are still pinned,
  not endorsed.
- A three-class scout+debugger+coder prompt now receives a docs step it did not
  ask for. Stated above as a deliberate trade, not hidden.
