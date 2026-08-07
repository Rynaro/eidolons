# #48 — mechanism note: the floor's derived-membership channel is STRUCTURALLY absent on the shipped fixture

Status: DRAFT evidence for the expected S-5 / FORGE-D9-class-(c) retirement of AC-138/AC-139.
Derived from source at `b7f1a47`, verified by execution (Kupo K-C3) and by reading.

## The finding

`evals/fusion_gate.py:175-177`, verbatim:

>     # All three competitors share the SAME edge target -- see module
>     # docstring: this is what makes decaying_walk's hash-order frontier pick

`N1`, `N2`, `N3` all point at the single phantom `Z`. Therefore the derived arm's
MEMBERSHIP is `{Z}` whenever **any** of the three is seeded, and `{}` only if **none** is.

`retrieve.py:562`: `fetch_width = max(k, FETCH_WIDTH_FLOOR)`, and `N1` is deterministically
`dense_ranking[0]` (`fusion_gate.py:64-66`). So every floor >= 1 seeds `N1`, and the derived
union is `{Z}` at **every** floor. Measured (Kupo, real GraphStore):

```
floor=2     n_seeds= 2 | neighbor_expand=['Z'] | decaying_walk={'Z':0.5} | DERIVED_UNION=['Z']
floor=10    n_seeds=10 | neighbor_expand=['Z'] | decaying_walk={'Z':0.5} | DERIVED_UNION=['Z']
floor=1000  n_seeds=15 | neighbor_expand=['Z'] | decaying_walk={'Z':0.5} | DERIVED_UNION=['Z']
```

**No floor pair can produce a derived-membership difference on this fixture.** This is a
property of the fixture's topology, not of any seed, and not of `PYTHONHASHSEED`.

## Why the pre-#41 "channel is LIVE and MEASURED" claim was true then and is false now

The pre-#41 channel was never a MEMBERSHIP channel. It was an ABORT channel.
`fusion_gate.py:75-81` describes it exactly: anomaly A's single-successful-seed cap meant
`decaying_walk` expanded only ONE seed, so the outcome depended on which element hash-order
picked first:

- pick lands on an edge-bearing competitor (`N1`/`N2`/`N3`) -> `{Z: 0.5}`
- pick lands on an edgeless filler (`F1..F12`)             -> `{}` (walk aborts there)

The floor changed the *slice contents* (10 vs 15 elements), which changed the odds of that
pick. That is the lottery, and it is why the divergence was a single seed out of 14 (seed 8)
rather than a systematic difference.

**#41 deleted that mechanism.** `graph.py:215-230` now loops EVERY seed; `graph.py:305` sorts
the frontier. With all seeds expanded, `N1` is always among them, so the union is always
`{Z}`. The abort channel is gone, and no membership channel ever existed to replace it.

Confirmed by git dating (K-B18): `evals/fusion_gate.py` last changed at `56c8510`
(2026-08-03); `storage/graph.py` last changed at `cab9b73`, the #41 sweep (2026-08-04). The
claim was written the day BEFORE #41 landed and has not been touched since.

## Consequence for #48

spec.md §4 (#48)'s prediction is **CONFIRMED, and by a stronger argument than the plan made.**
The plan predicted #41 "plausibly removed the floor's only channel" on the old topology. The
mechanism above shows it is removed *structurally and deterministically*, not probabilistically
— there is no seed, and no `PYTHONHASHSEED`, at which the shipped fixture can exhibit the
channel post-#41.

AC-138/AC-139, as literally worded against the shipped fixture, are therefore **unobtainable**.
This is S-5, routing to FORGE D9 class (c): **retire with a mechanism note; close #48 as
*retired*, not *discharged*.** verification-plan §6 requires the issue comment to say which.

## What is NOT concluded

This does **not** say a floor-sensitive fixture is impossible in general. A NEW fixture with
**distinct phantoms per competitor** (`N1->Z1`, `N2->Z2`, `N3->Z3`) would give each floor a
different derived union by construction — that is precisely what `evals/floor_sensitivity_gate.py`
is specified to build, and it is the reason Kupo routed AC-357's control there rather than
declaring it impossible.

So #48's disposition is decided by ONE remaining question, and it is a real measurement:
**does the new fixture's derived-membership difference propagate to a DETERMINISTICALLY
DISJOINT fused-rank distribution (AC-322)?** If yes, #48 closes discharged. If no, #48 closes
retired on this note. Both are legitimate; neither is a fabricated pass.
