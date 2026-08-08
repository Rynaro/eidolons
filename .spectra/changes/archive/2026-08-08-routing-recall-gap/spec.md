# routing-recall-gap — the roster was silent, not selective

**maker:** vivi · **checker:** kupo · **tier:** full · **repo:** Rynaro/eidolons
**released as:** v2.18.0 (`ec92dce`, PR #551)

## Problem

The reported symptom was "Gilgamesh is never invoked." That was true —
**51 of 21,975 recorded dispatches (0.23 %)**, 2 in August 2026 — and shallow.
Chasing the number found the actual defect two layers down.

### The measurement

A 44-prompt corpus was written **intent-first**: each prompt phrased the way an
engineer would type it, deliberately without consulting `roster/routing.yaml`.

| Metric | Result |
|---|---|
| Correct Eidolon selected | **6.8 %** (3/44) |
| **Selected nothing at all** | **90.9 %** (40/44) |
| Routed to the wrong Eidolon | 2.3 % |

`diagnose`, `debug`, `investigate`, `analyze`, `review`, `refactor`, `optimize`,
`compare`, `evaluate`, `summarize` matched **no Eidolon in the roster**.

### The silence

A prompt matching nothing scores 0 → below `tau_standard` → `decision: clarify`.
At that point `cli/src/harness_hook.sh` returned early and injected **nothing**.
The host therefore received no routing context, worked the prompt inline, and
**no Eidolon was invoked at all** — while the kernel's own
`clarification_request` was computed and thrown away.

A router with a lexicon hole was byte-indistinguishable from a healthy one.
This is the same shape as the ECM context-kernel failure recorded earlier in
this project: fail-open hides a dead kernel, and silence reads as health.

### Why no gate caught it

`evals/routing-suite.yaml` was authored **from** the trigger lexicons, so it
could only ever confirm them. Fifteen tasks, 100 % green, permanently, over a
router blind to nine prompts in ten. A benchmark written from the
implementation's own vocabulary is a tautology wearing a percentage.

## Decision

1. **Widen `trigger_verbs`** across all seven routed capability classes. DATA
   only — invariant I-C2 holds.
2. **Make the no-route path observable.** A below-τ prompt *carrying work
   intent* surfaces the `clarification_request`; conversational turns
   ("thanks, that looks good") stay silent, preserving R1-AC2. The
   discriminator is explicitly **not** a routing lexicon: it never selects an
   Eidolon and fails open in both directions.
3. **Replace the tautological benchmark.** `--suite recall` (49 tasks: 44
   natural-language + 5 precision guards), plus
   `scripts/verify-recall-mutation.sh`, which runs the suite against a prior
   `routing.yaml` and **fails if the score does not collapse**.

Plus an `unbounded_scope` signal: `"refactor across the entire codebase"` no
longer reaches a coder on a bare verb match, mirroring the Step-2 predicate's
existing S5 bounded-scope judgement into Step 1.

## Result

| | Before | After |
|---|---|---|
| Recall | 6.8 % | **100 %** |
| Routed nowhere | 90.9 % | **0 %** |
| `public` suite | 15/15 | 15/15 (**no regression**) |

## Gilgamesh is deliberately untouched

Its Step-2(a) predicate and the frozen `generalist-eidolon` S1..S5 vectors are
unchanged. Its rarity was a *symptom of the roster's silence*, not a defect —
with honest specialist recall, a rarely-used fallthrough generalist with zero
positive trigger verbs is the **correct steady state**. All 11 frozen predicate
fixtures resolve to their contracted routes.

## Two failures during the work, both self-inflicted

**The first "all green" was wrong.** The first full bats run ended on a
screenful of `ok` and was briefly recorded as passing. `grep -c '^ok'` gave
1699 against a `1..1703` plan — four failures sat earlier in the stream. Two
were real design faults: the widened coder lexicon reaching past its boundary
and poaching Gilgamesh's frozen fixtures C6 (`"replace the"`, removed) and P9
(bare `"refactor"`, fixed by the `unbounded_scope` signal rather than by
reverting the verb).

**The mutation gate's own first run passed for the wrong reason.** It parsed
the score with a positional `awk` field and picked up `cost=0` instead of
`16.3`, which awk evaluates as `0` — so it printed PASS on *every possible
input*, including a router with perfect recall. Found by reading the message,
not the exit status. It is now checked in both directions (16.3 % → exit 0,
100 % → exit 1, bad ref → exit 2).

## Anti-scope

- No change to the `raw → score` curve, `tau_standard`, or the chain templates.
- No change to the Gilgamesh Step-2(a) predicate or its frozen lexicons.
- The three-class chain-template gap was recorded as a residual here and closed
  separately by change `chain-three-class` (v2.19.0).
