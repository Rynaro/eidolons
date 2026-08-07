# spec.criteria.amend-04 — node-selector resolution + the sweep gate

amendment: 04 | date: 2026-08-06 | applied_by: **orchestrator (mechanical)** | checker: kupo (pending)
supersedes: the VERIFY selectors of AC-305, AC-311, AC-315, AC-358 in amend-01..03
chains from criteria hash `50803a00`

**Authorship note (read this):** amend-01..03 were authored by RAMZA. This amendment is applied
by the orchestrator because it is a MECHANICAL correction backed entirely by executed
measurement — it changes no criterion's semantics, weakens no threshold, and relaxes no
assertion. It replaces selectors that CANNOT RESOLVE with selectors that resolve to the same
tests. It is nonetheless subject to checker review like any other amendment, and the checker
should treat orchestrator-authored criteria with MORE suspicion, not less.

## The defect (measured on `release/v2.0.2` @ ff4fb5d)

Criteria address nodes as `<file>.py::<function>`. Every implementer grouped tests into
classes, so real ids are `<file>.py::<Class>::<function>`. pytest cannot resolve the
module-level form and exits non-zero:

```
ERROR: not found: /app/mcp-server/tests/test_floor_sensitivity_gate.py::test_aggregate_uses_classifier
(no match in any of [<Module test_floor_sensitivity_gate.py>])
```

All 7 are FALSE REDS — the tests exist and pass. Full evidence: `release-blocker-node-selectors.md`.

**Bare `-k` is rejected as the fix.** Measured: `-k test_aggregate_uses_classifier` collects **2**
nodes (substring match also catches `test_aggregate_uses_classifier_on_non_disjoint_rows`), so
`-k` does not pin identity — delete one node and the criterion still passes. Form (a),
exact class-qualified ids, is adopted, paired with the AC-382 sweep which catches the coupling
risk (a class rename breaks the id, and the sweep reports it as a BLOCKER rather than a red test).

## REPLACED selectors — semantics unchanged, resolution fixed

All verified to collect exactly 1 node and exit 0 on `ff4fb5d`.

### AC-305 (rig liveness / R-CONF) — 3 selectors
- `mcp-server/tests/test_corpus_rig.py::TestVerdictClassifier::test_confounded_axis_returns_no_numbers`
- `mcp-server/tests/test_corpus_rig.py::TestLiveness::test_liveness_confounded_on_empty_graph`
- `mcp-server/tests/test_corpus_rig.py::TestLiveness::test_liveness_measured_on_populated_edgeless_graph`

### AC-311 (G-XL single-layer control, STOP S-4)
- `mcp-server/tests/test_cross_layer_gate.py::TestSingleLayerControl::test_single_layer_control_is_rank_zero`

### AC-315 (G-CORPUS small-corpus control, STOP S-7)
- `mcp-server/tests/test_corpus_scaling_gate.py::TestCorpusScalingGate::test_small_corpus_control_recovers_planted`

### AC-358 (disjointness classifier is the consumed instrument) — 2 selectors
- `mcp-server/tests/test_floor_sensitivity_gate.py::TestDisjointnessClassifier::test_disjointness_classifier_both_branches`
- `mcp-server/tests/test_floor_sensitivity_gate.py::TestAggregateSeeds::test_aggregate_uses_classifier`

Unchanged (already resolve): `test_server_entrypoint.py::test_serve_stdio_handshake`,
`test_weight_discrimination.py::test_weight_injection_reaches_instance`.

## ADDED — AC-382 (ubiquitous): the node-collection sweep gate

GIVEN the criteria set for a release batch
WHEN the release checklist is run
THEN the system shall, BEFORE any other criterion executes, assert that every pytest node id
named by an EFFECTIVE criterion resolves on the release tree, classifying each as COLLECTS,
PENDING (declared to a wave that has not started), or BLOCKER — and shall fail on any BLOCKER.

VERIFY (host; `git` is unavailable in-container):
```
CH=/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan
MAIN=/home/rynaro/workspace/oss/agents/crystalium
# 1. EFFECTIVE node set: dedupe by (file, terminal function), preferring the class-qualified
#    form, so selectors superseded by a later amendment do not resurrect as phantom BLOCKERs.
grep -rhoE 'mcp-server/tests/[a-z_]+\.py::[A-Za-z_:]+' $CH/spec.criteria*.md $CH/verification-plan*.md \
 | sort -u | awk -F'::' '{k=$1"::"$NF; if(!(k in b)||NF>d[k]){b[k]=$0;d[k]=NF}} END{for(i in b)print b[i]}' \
 | sort > /tmp/nodes_eff.txt
# 2. ONE collection run (never one container per node — see red-check RC-2 below)
cd $MAIN && docker compose run --rm crystalium pytest mcp-server/tests/ --collect-only -q < /dev/null 2>/dev/null \
 | grep '::' | sed 's|^tests/|mcp-server/tests/|' | sort -u > /tmp/all_nodes.txt
test -s /tmp/all_nodes.txt || { echo "BLOCKER: collection produced nothing"; exit 1; }
# 3. Set-difference, then classify against the declared wave manifest below
comm -23 /tmp/nodes_eff.txt /tmp/all_nodes.txt > /tmp/missing.txt
comm -23 /tmp/missing.txt $CH/wave-manifest-pending.txt > /tmp/blockers.txt
wc -l < /tmp/blockers.txt; cat /tmp/blockers.txt; test ! -s /tmp/blockers.txt
```
**PASS = exit 0 with `/tmp/blockers.txt` empty.** Non-empty = a criterion naming a node that
neither exists nor is declared to a future wave.

### Declared PENDING manifest (`wave-manifest-pending.txt`)
Nodes a not-yet-started wave will create. Anything missing and NOT on this list is a BLOCKER.
A node must be REMOVED from this list when its wave lands, so the sweep starts enforcing it.

| node | owning unit |
|---|---|
| `test_cross_layer_gate.py::test_relocated_target_control` | W-45 (AC-343) |
| `test_retrieve_layer_merge.py::test_subset_layer_recall_no_regression` | W-45 (AC-355) |
| `test_retrieve_layer_merge.py::test_subset_layer_dense_mirror_no_regression` | W-45 (AC-378) |
| `test_retrieve_layer_merge.py::test_subset_censoring_signal_is_the_global_fetch` | W-45 |
| `test_sparse_status_topup.py::test_prefix_baseline_starves_active_hits` | W-44 (AC-345) |
| `test_sparse_status_topup.py::test_topup_recovers_active_hits` | W-44 (AC-346) |
| `test_sparse_status_topup.py::test_at_most_one_extra_query` | W-44 (AC-348) |
| `test_sparse_status_topup.py::test_topup_inert_when_active_only_off` | W-44 (AC-356) |
| `test_sparse_status_topup.py::test_subset_status_topup_recovers_active_hits` | W-44 (AC-379) |
| `test_sparse_status_topup.py::test_topup_counter_matches_observed_calls` | W-44 |
| `test_storage_graph.py::test_exclude_seeds_default_is_byte_identical` | W-42 (AC-350) |

### RED-CHECK OF THIS GATE — it failed three ways before it worked

AC-382 is itself a gate, so it was red-checked like any other. **All three defects below were
found by RUNNING it, not by reading it**, and each is the very species the gate exists to catch:

- **RC-1 — phantom BLOCKERs.** The first form grepped every criteria file including superseded
  ones, so it found 27 node ids (7 broken + 7 corrected duplicates) and reported 7 BLOCKERs for
  selectors no effective criterion uses. Fixed by the dedupe-by-terminal-function rule in step 1.
- **RC-2 — the gate PASSED having checked 1 of 20 nodes.** The first loop was
  `while read -r n; do docker compose run ... ; done < nodes.txt`. `docker compose run` consumes
  stdin, so it ate the loop's own input: one iteration ran, the loop ended, and the gate printed
  `SWEEP EXIT=0`. **A gate reporting success at 5% coverage is precisely the defect class this
  campaign exists to prevent, written into the gate meant to prevent it.** Fixed by collecting
  once and doing a set-difference — which also cut runtime from >10 min (timed out) to 1m43s.
- **RC-3 — Wave-2 nodes in existing files misclassified as BLOCKERs.** Classification keyed on
  FILE existence, but `test_relocated_target_control` (W-45) and
  `test_exclude_seeds_default_is_byte_identical` (W-42) live in files that already exist. Fixed
  by the explicit declared manifest above — file existence cannot infer wave ownership.

Measured on `release/v2.0.2` @ `ff4fb5d` after all three fixes: 1076 nodes collected,
20 effective criteria nodes, 9 COLLECTS, 11 PENDING (all manifest-declared), **0 BLOCKERs**.

### Why this is a gate and not a rule
This species — a criterion naming a node/key/artifact no step produces — has recurred **11 times
across 3 amendments**, each time despite an explicit global rule against it. A rule violated 11
times is not a control. **AC-382 runs as step 0 of BOTH release checklists.**

## Wave-3 disposition table — #48 (folding in FORGE's SPLIT ruling)

Per `issue-48-closure-ruling.md`, #48 closes as a **SPLIT**, and the closing comment must name
both halves:
- **RETIRED** (D9 class (c)): AC-138/AC-139 *as worded against the shipped fusion-gate fixture*,
  plus the "channel is LIVE and MEASURED" prose. The mechanism they measured (the pre-#41
  single-seed abort lottery) was deleted by #41; the shipped topology (one shared phantom,
  `N1` always admitted) makes the demanded disjointness structurally unobtainable there —
  proven at 14/14 seeds including seed 8, mechanised as AC-374.
- **DISCHARGED**: AC-322 on the purpose-built distinct-phantom fixture, via AC-139's own
  "moved, not weakened" hatch (ranks 0 vs 1 at all 7 C-2 seeds; classifier and independent
  recomputation agree; two axis-distinct red-checks fire).

**Binding constraint on the closing comment:** the new gate is a **regression guard and
existence proof, NOT evidence that `FETCH_WIDTH_FLOOR` matters in practice.** Citing it as
practice-relevance evidence is forbidden — that is the moment it becomes the same stipulated-
ground-truth species already ruled unobtainable for #47 and #55.

---

## ADDENDUM (post-checker) — two defects found by the v2.0.2 checker hop

### AC-332 REPLACED — `length == 5` fails for having MORE evidence

Measured on the real `checker-redcheck.json` (6 verified entries: the 5 mandated + the
optional G-FLOOR the checker was invited to add):
```
jq -e '[.gates[] | select(.independently_reproduced==true)] | length == 5'  -> false, exit 1
```
A criterion that goes RED because the checker produced MORE independently-verified evidence
than the minimum is a criterion that can fail for a reason unrelated to the defect it names.
It also actively discourages the thoroughness the campaign depends on.

**REPLACED VERIFY:**
```
jq -e '[.gates[] | select(.independently_reproduced==true
        and (.perturbation_patch|type=="string") and ((.perturbation_patch|length) > 0)
        and .exit_code != 0 and .restore.exit_code == 0)] | length >= 5' \
  CHANGE/checker-redcheck.json
```
**PASS = exit 0.** Verified: `true`, exit 0 on the real artifact. The bound becomes a FLOOR,
and the per-entry schema conjuncts (non-empty patch, non-zero exit, restore-to-zero) do the
work the count was standing in for — a boolean-only file still cannot satisfy it.

### D8's checker table contains 3 REPLAY rows — fix before reusing it for v2.1.0

The checker cross-checked FORGE's D8 replacement table against the makers' own
`red-evidence-*.json` and found that **3 of its 5 rows (G-XL, G-WD, G-FLOOR) are verbatim or
same-mechanism replays of red-checks the makers had ALREADY executed.** Used literally they
would fail D8's own anti-replay patch-diff step.

This is notable in kind: D8 was itself the FIX for a defective perturbation table (K-B9 found
5 of 7 rows unusable). The replacement table reproduced the defect it was written to remove.
The checker avoided it only because it verified each axis empirically before committing, and
used independent axes instead.

**Required before the v2.1.0 checker hop:** re-derive the D8 table's three replay rows against
the actual maker evidence, and make the anti-replay patch-diff step run BEFORE the checker
starts work, not after — a checker who discovers the replay at reporting time has already
spent the effort. Wave-2's makers have not yet written their red-evidence, so the v2.1.0 rows
must be derived AFTER those files exist, never pre-committed.

### AC-381 REPLACED — its fence anchor can never match (found by the W-44 maker)

AC-381 (amend-03) detects fence breaches 2-6 by asserting anchor substrings are present in
`retrieve.py`. One anchor is `'never a status predicate on the shared'`. **That substring does
not exist and never did.** The fence comment wraps across two `#`-prefixed lines
(`retrieve.py:611-612` at `b7f1a47`):

```
611:                # (`bm25_search` returns full rows) — never a status predicate
612:                # on the shared `bm25_search`, and no extra I/O beyond the one
```

Measured at `b7f1a47` — the fence's OWN origin commit:
`git show b7f1a47:...retrieve.py | grep -c "never a status predicate on the shared"` -> **0**.

So the detector is broken independently of any campaign change: it either always red-flags a
breach that has not happened, or (depending on how the assertion is phrased) can never fire on
the breach it names. Either way it does not detect what it claims. This is the **12th**
recurrence of the naming/anchor species, and this time inside a detector added specifically to
catch fence breaches — the guard needed a guard.

**REPLACED VERIFY:** normalise comment wrapping before matching, so the anchor is insensitive
to line breaks and `#` continuation:
```
docker compose run --rm crystalium /app/.venv/bin/python -c "
import re, pathlib
src = pathlib.Path('mcp-server/src/crystalium/aetheryte/retrieve.py').read_text()
# collapse '#'-continued comment lines into single logical lines
flat = re.sub(r'\s*\n\s*#\s*', ' ', src)
flat = re.sub(r'\s+', ' ', flat)
for anchor in ['never a status predicate on the shared',
               'no new public storage method']:
    assert anchor in flat, 'FENCE ANCHOR MISSING: ' + anchor
print('ok')
"
```
**PASS = prints `ok`.** Verified against the real source: the flattened form contains both
anchors. Red-check: delete either anchor phrase from the comment and the command must fail.

**General rule promoted from this:** any criterion that greps SOURCE PROSE (comments,
docstrings) must normalise line-wrapping first. A wrapped comment is the normal case in this
codebase, not the exception — every fence and disposition comment in `retrieve.py` and
`config.py` wraps.


### AC-382 RC-4 — a FOURTH defect in this gate, found by the v2.1.0 checker

The sweep produced **2 spurious BLOCKERs** on the v2.1.0 tree. Cause: two Wave-2 tests became
**parametrized**, so pytest collects `test_exclude_seeds_default_is_byte_identical[T1]`,
`[T2]`, `[T3]`, `[T3-variant]` and `test_subset_censoring_signal_is_the_global_fetch[censored]`,
`[uncensored]` — while the criteria reference the bare function name. An exact-line `comm`
can never match a bracketed collection ID against a bare reference. A third instance was
accidentally MASKED by a stale manifest entry, which is worse: the manifest was hiding a live
defect rather than declaring a pending one.

**Fix — normalise BOTH sides before the set-difference** (added to step 3 of AC-382's VERIFY):
```
sed -E 's/\[[^]]*\]$//' /tmp/all_nodes.txt | sort -u > /tmp/all_nodes_norm.txt
comm -23 /tmp/nodes_eff.txt /tmp/all_nodes_norm.txt > /tmp/missing.txt
```
Also: **the manifest must be emptied as each wave lands.** A stale entry silently suppresses a
real BLOCKER — exactly the failure mode the gate exists to prevent.

Measured after the fix on `release/v2.1.0` (`d243789`): 20 effective nodes, 1102 collected
(989 normalised), manifest empty, **0 BLOCKERs**. Red-checked: injecting a fabricated node id
yields 1 BLOCKER and a non-zero exit.

**Running tally for this one gate: 4 defects, every one found by RUNNING it** — phantom
BLOCKERs from superseded files (RC-1), passing at 5% coverage because `docker compose run` ate
the loop's stdin (RC-2), wave ownership inferred from file existence (RC-3), and parametrize
brackets (RC-4). The gate is sound now, but the lesson is the gate itself: a criterion is not
trustworthy because it was carefully written, only because it was executed against both a
passing and a failing input.
