# RELEASE BLOCKER — 7 v2.0.2 criteria cannot collect their own test nodes

Found by mechanical sweep of every pytest node id referenced in the criteria, run against the
integrated `release/v2.0.2` tree (`ff4fb5d`). FORGE found 1 instance while ruling #48; the sweep
found **7**. This is the K-B8 species ("a criterion naming something no step produces") — now its
5th through 11th recurrence, which means the GLOBAL RULE against it is not working and a
MECHANICAL check is required instead.

## The defect

Criteria address nodes as `mcp-server/tests/<file>.py::<function>`. Every implementer grouped
their tests into classes (idiomatic pytest), so the real ids are
`<file>.py::<Class>::<function>`. pytest cannot resolve the module-level form:

```
ERROR: not found: /app/mcp-server/tests/test_floor_sensitivity_gate.py::test_aggregate_uses_classifier
(no match in any of [<Module test_floor_sensitivity_gate.py>])
```

**Every one of these is a FALSE RED.** The functions exist and pass; only the selector is wrong.
Verified by running each with `-k`: all 7 exit 0.

| criterion's id | actual id | `-k` result |
|---|---|---|
| `test_corpus_rig.py::test_confounded_axis_returns_no_numbers` | `TestVerdictClassifier::…` | 1 passed |
| `test_corpus_rig.py::test_liveness_confounded_on_empty_graph` | `TestLiveness::…` | 1 passed |
| `test_corpus_rig.py::test_liveness_measured_on_populated_edgeless_graph` | `TestLiveness::…` | 1 passed |
| `test_corpus_scaling_gate.py::test_small_corpus_control_recovers_planted` | `TestCorpusScalingGate::…` | 1 passed |
| `test_cross_layer_gate.py::test_single_layer_control_is_rank_zero` | `TestSingleLayerControl::…` | 1 passed |
| `test_floor_sensitivity_gate.py::test_disjointness_classifier_both_branches` | `TestDisjointnessClassifier::…` | 1 passed |
| `test_floor_sensitivity_gate.py::test_aggregate_uses_classifier` | `TestAggregateSeeds::…` | **2 passed** |

Correctly PENDING (Wave-2 files/nodes not yet written — not defects):
`test_retrieve_layer_merge.py` (3 nodes), `test_sparse_status_topup.py` (6 nodes),
`test_cross_layer_gate.py::test_relocated_target_control` (AC-343, written by W-45),
`test_storage_graph.py::test_exclude_seeds_default_is_byte_identical` (AC-350, written by W-42).
Collecting correctly today: `test_server_entrypoint.py::test_serve_stdio_handshake`,
`test_weight_discrimination.py::test_weight_injection_reaches_instance` (both module-level).

## Consequence

**The v2.0.2 release checklist cannot pass as written.** Seven criteria exit 4 (usage error),
indistinguishable from a genuine red to anyone reading exit codes. A checker running the
checklist verbatim would conclude the batch is broken; a checker who "fixed" the commands
ad hoc would be silently rewriting the criteria at release time.

## The fix is NOT simply "switch to -k"

The criteria's own convention text says *"so the checker's `-k` selector is deterministic"* — but
`-k` does SUBSTRING matching. Measured: `-k test_aggregate_uses_classifier` matches **2** nodes,
because `test_aggregate_uses_classifier_on_non_disjoint_rows` also contains that substring. So
`-k` does not pin identity: delete one of the two and the criterion still passes with 1.

Required form is either:
- **(a)** the exact class-qualified node id (deterministic, but couples criteria to class layout), or
- **(b)** `-k <name>` PLUS an assertion on the collected count (`--collect-only -q` returning exactly N).

(b) is preferred: it survives class reorganisation AND fails if the node set changes underneath it.

## The systemic fix — a rule is not enough

This species has now recurred 11 times across 3 amendments despite an explicit global rule.
Add a MECHANICAL gate to both release checklists, before any other criterion runs:

> **Node-collection sweep.** Extract every `<file>.py::<node>` and every `-k <name>` referenced in
> the criteria; for each, assert it collects the expected number of nodes on the release tree.
> Any criterion that cannot collect is a criterion that cannot fail on its defect, and blocks
> the release until fixed. Files belonging to unstarted waves are reported as PENDING, not as
> failures — the sweep must distinguish those two.

The sweep that found this took one command. It should have been a gate, not an ad-hoc check.
