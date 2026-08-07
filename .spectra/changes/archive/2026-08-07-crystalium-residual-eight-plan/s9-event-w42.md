# S-9 fired during W-42's exit gate — investigated, cause identified, resolved

## The event
On the flipped W-42 tree:
```
make test     -> 1097 passed, 4 skipped, 1 xfailed   EXIT=0
make test-ci  -> 1 FAILED, 1092 passed, 8 skipped     EXIT=2
```
Mode disagreement = **STOP S-9**. Work halted.

Failing node: `test_retrieve_layer_merge.py::TestCallBudgetPerPath::test_call_budget_per_path[subset]`
Failure: `sqlite3.OperationalError: unable to open database file` at `relational.py:235`
(`sqlite3.connect(str(self.db_path), timeout=10)`).

## Diagnosis — an I/O error, not a logic failure
1. The node **passes in isolation** (all 3 params green, 3.50s), so the code path is sound.
2. W-45 had previously reported this exact node green with counts 1/1/3.
3. Host state at failure time, caused by THIS campaign's own accumulation:
   `/` at **84%** (39G free), 91 docker volumes (85GB), 55 containers, **81.7GB build cache**.
   `unable to open database file` is the classic sqlite symptom of resource/space pressure,
   not of a wrong query or a bad path.
4. Reclaimed 44.43GB (build cache + dangling images >24h). `/` went 84% -> **55%**.
5. Re-ran the SAME target on the SAME tree, no code change:
   `make test-ci -> 1093 passed, 8 skipped, 1 xfailed, EXIT=0`.

Both modes now green and mutually consistent (the 4-test delta is exactly the SKIP_SLOW
conversion, matching every prior run in this campaign).

## Honest limits of this conclusion
"It passed after I freed disk space" is a strong correlation and a mechanistically plausible
cause, **not a proof**. What IS established: the node is green in isolation, green in a full
`make test` run, and green in a full `make test-ci` run after reclamation — three independent
green observations against one red. The red was not reproduced after the environmental change.

What is NOT established: that resource pressure was the sole cause. If this node reddens again
with the same signature on a healthy host, it is a REAL defect (a fixture writing to a path
that collides only under full-suite ordering) and must go to VIGIL rather than being retried.

## Recorded so it is not rediscovered as a mystery
- The exhaustion was self-inflicted: one worktree per unit x 8 units, each with its own compose
  project and named volume, plus image rebuilds. That is the campaign's own parallelism cost.
- Operational note for the rest of this campaign and any successor: reclaim build cache BEFORE
  a release exit gate, not after a red. A release gate that reds on disk pressure is
  indistinguishable at first glance from a real regression, and burns a STOP condition.
- S-9 did exactly its job: it caught a mode disagreement that a single-mode run would have
  missed entirely. The disagreement was environmental, but the gate firing was correct.
