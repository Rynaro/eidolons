# Acceptance Criteria — `routing-recall-gap`

> ESL change `routing-recall-gap` · tier **full** · maker `vivi` · checker `kupo`
> Spec ref: `roster/routing.yaml`

## Problem (measured, not asserted)

The mechanical routing kernel (`eidolons run`) has high precision and
catastrophically low **recall**. Measured over a 44-prompt natural-language
corpus authored independently of the trigger lexicons:

| Metric | Baseline (pre-change) |
|---|---|
| recall (correct Eidolon in `selected`) | **6.8 %** (3/44) |
| MISS (`selected == []`, `decision=clarify`) | **90.9 %** (40/44) |
| WRONG (routed, wrong Eidolon) | 2.3 % (1/44) |

### Causal chain

1. **L1 — symptom.** Gilgamesh received 51 of 21 975 recorded dispatches
   (0.23 %); 2 in August 2026. Perceived as "never invoked".
2. **L2 — mechanism.** `trigger_verbs` in `roster/routing.yaml` cover a narrow
   vocabulary. A prompt matching no phrase scores 0 → below `tau_standard`
   (0.6) → `decision: clarify`. `cli/src/harness_hook.sh` then returns early
   (`return 0`) and injects **nothing**: the host receives no routing context,
   works the prompt inline, and **no Eidolon is invoked at all**. The kernel's
   own `clarification_request` string is computed and then discarded.
   Gilgamesh cannot rescue these: Step-2(a)'s predicate is a five-way AND
   (`S1∧S2∧S3∧S4∧S5`) requiring both an explicit path/ID token and an
   acceptance marker.
3. **L3 — why it went undetected.** `evals/routing-suite.yaml` (15 tasks,
   100 % pass) was authored *from* the trigger lexicons, so it can only ever
   confirm them. It is a gate that cannot fail on the defect it names.

## Criteria

| ID | Criterion | Method |
|---|---|---|
| **AC-1** | Recall on the adversarial recall suite ≥ **80 %** | `eidolons eval routing --suite recall` |
| **AC-2** | MISS rate (`selected == []`) on the recall suite ≤ **10 %** | same |
| **AC-3** | No precision regression: all 15 existing `public` routing-suite tasks still pass | `eidolons eval routing` = 15/15 |
| **AC-4** | Read-only intent never routes to a write-capable Eidolon; the named-refusal reroute still fires | guard tasks in the recall suite |
| **AC-5** | **The gate can fail.** The recall suite scored against the *pre-change* `roster/routing.yaml` MUST report < 20 % recall | mutation check, recorded in `verification.md` |
| **AC-6** | `decision == "clarify"` injects the `clarification_request` into the host instead of returning silently | `cli/tests/harness_hook.bats` |
| **AC-7** | `make lint` clean, `make schema` green, bash 3.2 compatible (no bash-4 constructs) | CI parity |
| **AC-8** | Full bats suite green | `make test` |

**AC-5 is load-bearing.** A recall suite added at the same time as the lexicon
it measures would pass trivially. The suite must be shown red against the old
data file before it is accepted as green against the new one.

## Anti-scope

- No change to the scorer's `raw → score` curve, `tau_standard`, or the chain
  templates. This change is **DATA + one hook branch**, preserving invariant
  I-C2 (routing.yaml is data; the kernel interprets it, there is no eval).
- No change to the Gilgamesh Step-2(a) predicate or its frozen ESL lexicons —
  amending those requires a new SHA-256 freeze on the `generalist-eidolon`
  change and is explicitly out of scope here. Gilgamesh remaining rare is a
  *correct* outcome once specialists have honest recall; the defect was the
  silent dead-end, not Gilgamesh's selectivity.
