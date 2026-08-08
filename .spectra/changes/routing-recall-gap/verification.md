# Verification — `routing-recall-gap`

> ESL change `routing-recall-gap` · tier **full**
> Maker: `vivi` · Checker: `kupo` (maker ≠ checker, C4)

## Evidence

| AC | Criterion | Result | Evidence |
|---|---|---|---|
| **AC-1** | Recall ≥ 80 % on the adversarial suite | **PASS — 100 %** | `eidolons eval routing --suite recall` → 49/49 |
| **AC-2** | MISS rate ≤ 10 % | **PASS — 0 %** | 0 tasks with `selected == []` |
| **AC-3** | No precision regression on `public` | **PASS — 15/15** | `eidolons eval routing` unchanged at 100 % |
| **AC-4** | Read-only never routes to a writer; refusal reroute survives | **PASS — 5/5 guards** | `N-G01`…`N-G05` |
| **AC-5** | **The gate can fail** | **PASS — 16.3 %** | mutation check below |
| **AC-6** | `clarify` is observable, not silent | **PASS** | 3 new tests in `cli/tests/harness.bats` |
| **AC-7** | lint / schema / bash 3.2 | **PASS** | `make lint` exit 0; `make schema` exit 0; harness AC-7 bash4-construct test green |
| **AC-8** | Full bats suite green | **PASS — 1703/1703** (after fixing 4 self-inflicted regressions, below) | `bats cli/tests/` (sequential; `parallel(1)` absent on this box) |

### AC-8 — the first full run was RED, and the tail looked green

The first sequential run ended on a screenful of `ok` lines and was briefly
recorded here as passing. It was not: `grep -c '^ok'` gave 1699 against a
`1..1703` plan. Four failures sat earlier in the stream, all caused by this
change:

| Test | Cause | Resolution |
|---|---|---|
| `dispatch-predicate AC-C01` (C6) | `"replace the"` added to the coder lexicon poached fixture **C6** from Gilgamesh | phrase **removed** — no recall task depended on it |
| `dispatch-predicate AC-C02` (P9) | bare `"refactor"` routed **P9** (`across the entire codebase`) to Vivi instead of clarifying | new `unbounded_scope` negative signal |
| `eval routing --suite all` | hardcoded `total == 19` | derived from the suite file, so it tracks additions |
| `eval routing --validate-suite` | `N-G03` duplicated `R-013`'s prompt | reworded the guard |

Both routing failures were real design faults, not test friction: a widened
coder lexicon was reaching past its own boundary. The frozen `generalist-eidolon`
S1..S5 vectors were **not** touched — only Step-1 scoring, which is what
supplies their S6 precondition. All 11 frozen predicate fixtures (C3, C5, C6,
P1–P3, P5, P8–P11) now resolve to their contracted routes again.

## AC-5 — mutation check (the load-bearing one)

A recall suite shipped alongside the lexicon it measures passes trivially. So
the suite was run **unchanged** against the **pre-change** `roster/routing.yaml`
(reverted from `HEAD`, everything else current):

```
eidolons eval routing  suite=recall
  debug           0/8      0%
  decision        0/5      0%
  discovery       0/10     0%
  docs            1/4     25%
  implement       1/8   12.5%
  micro           0/4      0%
  planning        1/5     20%
  guard-clarify   2/2    100%     ← guards SHOULD pass in both worlds
  guard-readonly  1/1    100%
  guard-refusal   1/1    100%
  guard-trance    1/1    100%
  ──────────────
  OVERALL         8/49  16.3%
```

Below the 20 % ceiling. The eight survivors are the five precision guards
(which test unchanged behaviour and are *expected* to pass either way) plus
three recall tasks whose wording happened to overlap the old lexicon
(`capture this as an ADR`, `clean up`, `requirements`). The recall arm proper
moves 3/44 → 44/44.

Reproduce: `bash scripts/verify-recall-mutation.sh` (vendored from the
job-local `mutation-check.sh` used during authoring).

### The mutation gate's own first run passed for the wrong reason

Worth recording, because it is the same defect class this change exists to
remove. The first version of `verify-recall-mutation.sh` parsed the score with
a positional `awk` field:

```
OVERALL   8/49   16.3%   cost=0 tokens (no model)
              ^$3    ^$4
```

`$4` is `cost=0`, which `awk` evaluates as `0` — so the comparison `0 < 20`
held and the gate printed **PASS** … on every possible input, including a
router with perfect recall. It was caught by reading the message
(`collapses to cost=0%`), not the exit status.

Fixed to select the field ending in `%`, then checked in **both** directions —
a gate is only a gate if it goes red:

| Invocation | Expected | Actual |
|---|---|---|
| `verify-recall-mutation.sh HEAD~1` (old lexicons) | PASS, exit 0 | 16.3 %, exit 0 |
| `verify-recall-mutation.sh HEAD` (current lexicons) | FAIL, exit 1 | 100 %, exit 1 |
| `verify-recall-mutation.sh nonexistent-ref` | error, exit 2 | exit 2 |

## What was actually wrong

Three layers, only the first of which was visible as a complaint:

1. **Symptom.** Gilgamesh at 51/21 975 recorded dispatches (0.23 %); 2 in
   August 2026.
2. **Mechanism.** Trigger lexicons covered the cortex's own vocabulary, not
   engineers'. `diagnose`, `debug`, `investigate`, `analyze`, `review`,
   `refactor`, `optimize`, `compare`, `evaluate`, `summarize` — none matched
   anything. Score 0 → below `tau_standard` → `decision: clarify` → the hook
   returned early and injected **nothing**. The host then worked the prompt
   inline with no routing context, so *no Eidolon was invoked at all* and
   nothing recorded a miss. Gilgamesh could not backstop this: Step-2(a) is a
   five-way AND needing both a path token and an acceptance marker.
3. **Why it survived.** `evals/routing-suite.yaml` was authored *from* the
   lexicons, so it could only confirm them — 15/15, 100 %, permanently green
   over a router that was blind to 91 % of ordinary prompts.

Gilgamesh's rarity was a *symptom of the roster's silence*, not a Gilgamesh
defect. With honest specialist recall, a rarely-used fallthrough generalist is
the correct steady state — so its Step-2(a) predicate is deliberately untouched
(amending it would need a new SHA-256 freeze on `generalist-eidolon`).

## Residual risk

- The recall suite is Eidolons-authored, like `public`. Its protection comes
  from being written **intent-first** and from the AC-5 mutation check, not
  from independence of authorship.
- Lexicon matching remains presence-based over closed phrase lists; it will
  always have a tail. The change makes that tail **observable** (AC-6) instead
  of silent, which is the durable half of the fix.
- The AC-6 work-intent discriminator is a heuristic. It is fail-open in both
  directions: no match → historical silent path; false match → one extra
  clarification line. It never selects an Eidolon.

### Known residual — no three-class chain template

Found while re-routing the prompt that opened this change ("… Diagnose,
Digest, Plan and Fix it"). Post-change it now scores **three** classes —
`vigil` 0.8 (debugger, via the new `diagnose`), `ramza` 0.8 (planner),
`vivi` 0.8 (coder) — where pre-change VIGIL scored 0 and the debugger
intent was invisible. That is the intended recall gain.

But `roster/routing.yaml`'s `chains:` has no template whose
`requires_classes` covers *debugger + planner + coder*, so template selection
falls back to the most specific 2-class match. `ship-fast`
(`planner, coder`) and `forensic-then-fix` (`debugger, coder`) both have
specificity 2, and `sort_by(-spec)` is a stable sort — so **declaration order
in the file silently decides the winner**. `ship-fast` is declared first and
takes it; the diagnosis step is dropped from the chain.

Deliberately **not** fixed here. Adding a template changes routing for prompts
this change has not measured, and the recall suite's guard set does not cover
multi-class chain selection. Two separable follow-ups:

1. Add a `diagnose-then-plan-then-fix` template (`vigil, ramza, vivi`) with
   recall-suite coverage for 3-class prompts.
2. Make the specificity tie-break explicit rather than order-dependent —
   an equal-specificity tie between two templates is currently resolved by
   nothing more principled than which line comes first.
