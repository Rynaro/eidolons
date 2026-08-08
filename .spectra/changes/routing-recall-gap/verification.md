# Verification — `routing-recall-gap`

> ESL change `routing-recall-gap` · tier **full**
> Maker: `vivi` · Checker: `kupo` (maker ≠ checker, C4 — mechanically enforced)

## Checker round 1 — **REJECT**

An independent checker (distinct actor, clean context) was dispatched against
the shipped code at `ec92dce` and told explicitly what the maker was least sure
of. It rejected. Every finding below came from *running* the kernel and the
hook, not from reading this record.

| # | Severity | Finding | Status |
|---|---|---|---|
| F1 | **BLOCKER** | Read-only interrogatives routed to write-capable Eidolons: **3/24 → 15/24** over the checker's own corpus. `"which port does the server listen on?"` → `vivi`, and the hook then instructed the host to delegate to a coder. Culprits: bare `port`, `modify`, `update the`, `migrate`. | **FIXED** |
| F2 | **MAJOR** | `unbounded_scope` was an **unconditional veto**, not the "bare verb match" its note claimed (−0.4 killed even raw=3: 0.97 → 0.57). It suppressed bounded one-file work while bare `everywhere` routed through. Its "mirrors predicate S5" claim was false — S5 has a LIMITER rescue that Step 1 never implemented. | **FIXED / claim corrected** |
| F3 | **MAJOR** | The work-intent discriminator used **unanchored substring globs**: `*test*`→"la**test**", `*spec*`→"e**spec**ially", `*plan*`→"ex**plan**ation". Fired on 12/20 conversational prompts including `"how are you today?"`, and stayed **silent on 12/12** genuine work requests. The AC-6 negative test pinned the single string that happened to work. | **FIXED** |
| — | minor | `verify-recall-mutation.sh` default `HEAD~1` false-alarms from a later checkout; `spec.md`/`spec.yaml` were untracked; AC-6 cited the wrong test file. | **FIXED** |
| — | none | AC-1/2/3/5/7, `files_touched`, and the frozen Gilgamesh fixtures all verified green independently. | confirmed |

The checker's through-line: **the change asserted precision over a 5-task guard
set and never measured it** — the same tautology on the precision axis that the
change was written to remove on the recall axis. AC-5 proved the suite was
sensitive to lexicon *removal*; nothing in it was sensitive to lexicon
*addition*.

## Remediation (shipped as v2.19.1)

- **New `read_only_question` signal** (−0.5 to coder/executor/scriber only, so
  ATLAS/FORGE/VIGIL/RAMZA still receive questions). `port` → `port the`.
  Result on the checker's counterexamples: **0/12** reach a writer.
- **`unbounded_scope` penalty −0.4 → −0.25**, which actually implements the
  "lone verb match" the note claimed: 0.8 → 0.55 (clarify), 0.9 → 0.65
  (routes), 0.97 → 0.72 (routes). `everywhere` added to the match list.
- **The false S5 claim is replaced with an honest limit.** The signal table is
  presence-matched and cannot express S5's limiter∧path conjunction, so Step 1
  implements only the punitive half. A bounded ask carrying a generic-scope
  phrase may still clarify — a conservative failure, and now a visible one.
- **Discriminator rewritten to whole-word matching** over a
  punctuation-normalised prompt, with an explicit conversational deny-list
  checked first.
- **Guards now measure the precision axis**: `N-G06`–`N-G10` (read-only
  interrogatives; bounded vs unbounded scope). **`N-042` reworded** — it had
  *expected* a repo-wide rename to reach Kupo, i.e. the suite was blessing the
  exact case `unbounded_scope` exists to catch, cancelling the signal.
- **AC-6 tests are corpora now**, both directions: 10 conversational prompts
  must stay silent, 8 real work requests must surface.
- **`verify-recall-mutation.sh` scores the recall arm only.** Guards pass in
  both worlds by design, so they put a rising floor under the mutated score;
  growing the guard set 5 → 10 pushed it 16.6 % → 22 % and tripped the gate.
  Raising the ceiling would have been the gate-that-cannot-fail defect
  committed by the script that exists to prevent it. Default ref pinned to
  `v2.17.0`.

## Evidence after remediation

| AC | Result | Evidence |
|---|---|---|
| AC-1 | **PASS** | recall arm 100 % |
| AC-2 | **PASS** | 0 MISS |
| AC-3 | **PASS** | `public` 15/15 |
| AC-4 | **PASS (now measured)** | 0/12 read-only interrogatives reach a writer, was 12/12; guards `N-G01`, `N-G06`, `N-G07`, `N-G10` |
| AC-5 | **PASS** | recall arm collapses to **8.2 %** against `v2.17.0` (ceiling 20 %); exit 0 / 1 / 2 verified in all three directions |
| AC-6 | **PASS (corpus)** | 10 conversational silent, 8 work requests surfaced, `cli/tests/harness.bats` 170/170 |
| AC-7 | **PASS** | `make lint` 0 · `make schema` 0 · budget 836/850 · bash 3.2 construct test green |
| AC-8 | **PASS** | `bats cli/tests/` → **1712/1712**, 0 failures |

Suites: recall **59/59**, public **15/15**, self-test **78 tasks**.
Frozen `generalist-eidolon` fixtures: all 11 resolve to contracted routes.

## Residual — disclosed

- **No LIMITER rescue.** A bounded ask containing a generic-scope phrase
  ("update the helper at all call sites in `cli/src/lib.sh` only") still
  clarifies. Implementing the rescue needs conditional signals — a kernel
  change, not a data change.
- **`"should we refactor this or leave it?"`** forms a `decide-then-implement`
  chain rather than a lone FORGE dispatch. `should we` is deliberately excluded
  from `read_only_question`, because penalising the coder there would make that
  chain unreachable. FORGE runs first and may conclude "leave it".
- The discriminator remains a heuristic; it never selects an Eidolon and fails
  open in both directions.

## The lesson this round actually taught

Both of this change's headline gates were real — and both were sensitive to
exactly one direction of failure. `AC-5` could detect a lexicon getting
*narrower* and was structurally blind to one getting *wider*. Writing a gate is
not the same as knowing which way it can fail.
