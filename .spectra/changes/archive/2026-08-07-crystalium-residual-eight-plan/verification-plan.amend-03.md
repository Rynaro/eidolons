# verification-plan.amend-03 — `crystalium-residual-eight-plan`

**Amendment `amend-03`.** Supersedes named sections of `verification-plan.amend-01.md` and
`verification-plan.amend-02.md`. No earlier file is edited. Chain:
`verification-plan.md` -> `amend-01` -> `amend-02` -> **`amend-03`** (governs on conflict).

MAIN = `/home/rynaro/workspace/oss/agents/crystalium`
CHANGE = `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan`

---

## 0. Execution rules — adds rules 12, 13, 14

Rules 1-11 stand. Added:

**12. Artifact freshness (global rule (g)).** A nonce covers **one measurement, not one
command** — VP-M1 mints once at the head of the chain and every command in it carries that
value, because `.positive_control.run_nonce == $n` is otherwise unsatisfiable by construction.
Multi-file predicates **must slurp** (`jq -s -e 'all(.[]; …)'`): `jq -e 'pred' a.json b.json`
exits on the **last** input, so a failing first file is invisible — measured this pass. No step
reads a gate artifact it did not just cause to be written. Every producing block is **one `&&` chain**: `rm -f` the artifact, mint a
nonce and read the tree sha **on the host**, run the emit with both passed in as environment,
then `jq` the file with `.run_nonce` and `.tree_sha` asserted against the invoking run. Seeded
loops share one nonce across the family and the aggregate asserts it **per row**.
*This rule exists because the K-B15 remedy traded a loud false red for a silent false green: a
gate that crashes before `emit` left the previous run's artifact, `evals/results/*.json` is
gitignored so `git status` stayed clean, and `amend-01` §A.4 item 3 recorded that as a feature
and added "no host-side `rm` is ever needed". That sentence is **STRUCK**.*

**13. Detached-checkout hygiene (global rule (h)).** Any step that moves the tree refuses to run
dirty, records the original ref, restores it **unconditionally including on failure** (`;` not
`&&` before the restore), and asserts the restore before reporting PASS.

**14. Producer-named artifact contracts (global rule (i)).** Every step that reads a file names
its **producing step**, its **exact filename** and the **exact keys** asserted. Where the file
already exists, the step is written against the **shipped** keys and is **run before freeze**.
*This rule exists because K-B8's species — a criterion naming an artifact or field no step
produces — recurred four times (AC-306, AC-322's aggregate, AC-345's `.txt`, AC-332's
`red-evidence` shape).*

**New exit class (extends rule 5's three).** A `jq` exit 1 failing **only** on `.run_nonce` or
`.tree_sha` is a **STALE READ (S-15)** — not a red, not a green. Re-run the chain.

---

## 1. Why VP-M1 is being rewritten a THIRD time

`amend-01` demoted VP-M1's preliminary result as a one-sided proxy. `amend-02` found the deeper
defect — the protocol had no failure mode — and built a positive control. **That control could
not be built.** Kupo measured it: `_build_fixture:172-177` points `N1`, `N2` and `N3` at the
**same** phantom `Z`, and `fetch_width = max(k, FETCH_WIDTH_FLOOR)` always admits `N1`, so the
derived union is `['Z']` at floors 2, 10 **and** 1000. `amend-02`'s control asserted
`channel_live == true` on that fixture: **permanently red, at every floor pair**.

Worse than a dead control: `amend-02` routed its red to *"the probe is not instrumented … a
probe defect … fix the probe and re-run"*, and S-14 then forbade recording any `channel_live`
value. **The implementer would have debugged a correctly-instrumented probe, spent the one-cycle
redesign budget on a misdiagnosis, and still had no evidence.**

The finding underneath is **stronger** than `amend-02` assumed, and it is what makes the fix
clean: the pre-#41 channel was an **ABORT** channel (anomaly A's single-successful-seed cap made
the outcome depend on which element hash-order picked first), not a **membership** channel. #41
deleted that mechanism — `graph.py:215-230` loops every seed, `:305` sorts the frontier — so on
the shipped fixture the derived union is floor-invariant **by topology**, for every seed and
every `PYTHONHASHSEED`. See `CHANGE/issue-48-mechanism-note.md`; **AC-374 asserts it
mechanically.**

---

## 2. VP-M1 — REPLACED (supersedes `amend-02` §2.1-2.4)

D5's probe construction (the recording proxy at the `graph_store` seam, the `run_floor_probe`
self-check, the `try/finally` monkeypatch, `fusion_gate.py` byte-untouched) **stands unchanged**.
What changes: **where the control lives**, **what symbol is called**, and **how the artifacts are
bound to the run**.

### 2.0 One probe symbol, one caller (K-C-N5)

**Deleted from the plan:** `vp_m1_seed`, `vp_m1_control`. Normative surface:

- **`vp_m1_probe(*, floor: int, fixture: str = "shipped") -> dict`** — FORGE D5's ruled symbol,
  extended by **one keyword with a default** so every D5-era call is unchanged. Returns
  `{floor, floor_applied_readback, derived, retrieved, target_rank, self_check_ok, fixture,
  fixture_phantom_targets}`.
- **`vp_m1_pair(*, seed_label, floor_low, floor_high, fixture) -> dict`** — the **only** caller.
  Calls `vp_m1_probe` **twice in one process**; returns `{seed, floor_low, floor_high, fixture,
  fixture_phantom_targets, low, high, channel_live, probe_symbol: "vp_m1_probe", probe_calls: 2}`.

**Why a pair-caller is unavoidable (maker's call, flagged).** The two floors of a seed row must
be compared **within one process**: with `PYTHONHASHSEED` *unset* — mandatory under rule (d) —
hash randomisation differs per process, so a cross-process pair for the `unset` row compares two
different randomisations and is not a measurement. Two spawns per seed is **unsound**, not merely
expensive. Bounded extension of D5, recorded rather than absorbed.

### 2.1 Step 1 — the positive control, on W-G-FLOOR's OWN fixture (AC-357; rule (f))

```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/m1-positive-control.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_pair(seed_label='0', floor_low=2, floor_high=1000, fixture='distinct_phantom'), '/app/evals/results/m1-positive-control.json')" && jq -e --arg n "$NONCE" '(.run_nonce == $n) and (.fixture == "distinct_phantom") and ((.fixture_phantom_targets | unique | length) == (.fixture_phantom_targets | length)) and ((.fixture_phantom_targets | length) >= 3) and ((.low.derived | length) > 0) and ((.high.derived | length) > (.low.derived | length)) and (((.low.derived - .high.derived) | length) == 0) and (.channel_live == true) and (.low.self_check_ok == true) and (.high.self_check_ok == true)' evals/results/m1-positive-control.json
```
**PASS = exit 0.** The control fixture assigns **one phantom per competitor** (`c1 -> z1`,
`c2 -> z2`, `c3 -> z3`) with `c1` inside the low floor's slice and `c2`, `c3` outside it, so
`[:2]` reaches only `z1` and `[:1000]` reaches all three — the derived union differs **by
construction**, independent of hash order. One seed suffices. `fixture_phantom_targets` is read
**off the graph at runtime**, so the control cannot be pointed at a same-phantom fixture and
silently mean nothing.

**Routing on red — three branches, not two (this is the correction that matters):** see
`spec.criteria.amend-03.md` AC-357. Red **here** is a probe-or-fixture defect (S-13 step 1) and
**stops** step 2. Green here plus no difference on the shipped fixture is **EVIDENCE**, not a
defect.

### 2.2 Step 1b — the shipped fixture's topology, captured (AC-374)

```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/m1-shipped-fixture-topology.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.shipped_fixture_topology(floors=[2,10,1000]), '/app/evals/results/m1-shipped-fixture-topology.json')" && jq -e --arg n "$NONCE" '(.run_nonce == $n) and (.distinct_phantom_count == 1) and ((.derived_union_by_floor | to_entries | map(.value) | unique | length) == 1) and ((.derived_union_by_floor | to_entries | map(.value)[0] | length) > 0)' evals/results/m1-shipped-fixture-topology.json
```
**PASS = exit 0.** This is the mechanism note **as an assertion**. It runs **before** step 2 so
that step 2's result is interpreted against a measured topology rather than a remembered one.

### 2.3 Step 2 — 14 spawned processes, one shared nonce

```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/m1-seed-*.json && ( for s in 0 1 2 3 4 5 6 7 8 9 10 11 12; do docker compose run --rm -e PYTHONHASHSEED=$s -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_pair(seed_label='$s', floor_low=10, floor_high=1000, fixture='shipped'), '/app/evals/results/m1-seed-$s.json')" || exit 1; done ) && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_pair(seed_label='unset', floor_low=10, floor_high=1000, fixture='shipped'), '/app/evals/results/m1-seed-unset.json')"
```
The 14th run **omits `-e PYTHONHASHSEED` entirely** (rule (d) / K-N17). `PYTHONHASHSEED` 0-12 +
unset is the tree's own evidence set (`fusion_gate.py:85-86`), chosen because it is the only set
**provably containing the divergent point (seed 8)**. **C-2 (`0-5` + unset) remains correct
everywhere else** — AC-344, AC-317, AC-322.

**The shared nonce is load-bearing.** A mid-loop abort leaves seeds written by **this** run and
the rest from a previous one; without the nonce, `jq -s` slurps them into a well-formed 14-row
artifact that satisfies every length guard. With it, the stale rows fail
`all(.seeds[]; .run_nonce == $n)`.

### 2.4 Step 3 — aggregate, in the same chain

```
cd /home/rynaro/workspace/oss/agents/crystalium && jq -s --slurpfile ctl evals/results/m1-positive-control.json '{run_nonce: .[0].run_nonce, tree_sha: .[0].tree_sha, seeds: ., channel_live: (any(.[]; .low.derived != .high.derived)), seed_set: [.[].seed], seed_set_covers_divergent_point: (([.[].seed] | index("8")) != null), divergent_point_known: "8", positive_control: $ctl[0]}' evals/results/m1-seed-0.json evals/results/m1-seed-1.json evals/results/m1-seed-2.json evals/results/m1-seed-3.json evals/results/m1-seed-4.json evals/results/m1-seed-5.json evals/results/m1-seed-6.json evals/results/m1-seed-7.json evals/results/m1-seed-8.json evals/results/m1-seed-9.json evals/results/m1-seed-10.json evals/results/m1-seed-11.json evals/results/m1-seed-12.json evals/results/m1-seed-unset.json > /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```
Then **AC-321** is the gate on that file, run with `CRYSTALIUM_GATE_NONCE` still exported from
step 2's chain. **The control's nonce must match**: step 1 and step 2 are run in the **same
shell session**, or the aggregate is regenerated after re-running step 1 — a control from an
older run fails `.positive_control.run_nonce == $n`.

### 2.5 Aggregate schema (supersedes `amend-02` §2.2)

```json
{
  "run_nonce": "<uuid4 minted by the invoking chain>",
  "tree_sha": "<git rev-parse HEAD at invocation>",
  "seeds": [
    { "seed": "0", "run_nonce": "<same>", "floor_low": 10, "floor_high": 1000,
      "fixture": "shipped", "probe_symbol": "vp_m1_probe", "probe_calls": 2,
      "low":  {"floor": 10,   "derived": ["..."], "retrieved": ["..."], "target_rank": 0, "self_check_ok": true, "floor_applied_readback": 10},
      "high": {"floor": 1000, "derived": ["..."], "retrieved": ["..."], "target_rank": 0, "self_check_ok": true, "floor_applied_readback": 1000},
      "channel_live": false }
  ],
  "seed_set": ["0","1","2","3","4","5","6","7","8","9","10","11","12","unset"],
  "seed_set_covers_divergent_point": true,
  "divergent_point_known": "8",
  "positive_control": {
    "run_nonce": "<same>", "fixture": "distinct_phantom",
    "fixture_phantom_targets": ["z1","z2","z3"],
    "floor_low": 2, "floor_high": 1000,
    "low":  {"derived": ["z1"], "self_check_ok": true},
    "high": {"derived": ["z1","z2","z3"], "self_check_ok": true},
    "channel_live": true, "probe_symbol": "vp_m1_probe", "probe_calls": 2
  },
  "channel_live": false
}
```

### 2.6 What VP-M1 may and may not license (supersedes `amend-02` §2.3)

| observation | licensed conclusion |
|---|---|
| AC-357 green, AC-374 green, `channel_live == false` over 14 points | **On the shipped fixture the derived-membership channel is absent — structurally, not merely unobserved.** All three competitors share one phantom and every floor >= 1 seeds `N1`, so no seed and no `PYTHONHASHSEED` can produce a difference. `spec.md` §4 #48's prediction is **confirmed by a stronger argument than the plan made**. Route to **S-5 ⇒ S-13 class (c)**: retire AC-138/AC-139 with the mechanism note; close #48 **retired**, not discharged. |
| AC-357 green, `channel_live == true` | **REFUTATION.** The prediction and `issue-48-mechanism-note.md` are both wrong. Correct the note (do not quietly drop it) and carry the tie-break explanation. |
| AC-357 **red on its own fixture** | **NOTHING about the floor.** Probe or fixture defect (S-13 step 1). Not recordable (**S-14**). |
| AC-374 red (the shipped fixture has distinct phantoms) | The structural argument is void; #48's framing is **redone**, not inherited. |
| any run on `< 14` points | smoke test only; `seed_set_covers_divergent_point: false` must be in the artifact. |

**The routing rule is unchanged: the new between-floors fixture gets built either way.**

### 2.7 The preliminary capture — status unchanged

`CHANGE/vp-m1-floor-channel.preliminary.json` remains demoted and must not be cited. Its cause is
now fully stated: a **C-2 protocol provably blind to the only divergent point**, on the **wrong
quantity** (`retrieved`, which the fixture pins), against a fixture whose derived channel is
**structurally absent**. Three independent reasons it could not have settled `channel_live`.

---

## 3. VP-M6 — floor-sensitivity aggregate (NEW; K-C4/K-C5)

The gate's own measurement, distinct from VP-M1. Four commands, one chain — see
`spec.criteria.amend-03.md` AC-322 for the full text. Structure:

1. six seeded spawns (`0-5`) plus one with `-e` omitted, all sharing one nonce, each emitting
   `evals/results/floor-seed-<s>.json` via `run_seed(seed_label=…)`;
2. **`aggregate_seeds(['0','1','2','3','4','5','unset'])`** — the **producing step** for
   `evals/results/floor-seed-aggregate.json` (renamed from `floor-7seed-aggregate.json`, whose
   name hard-coded a seed count a 14-seed run would falsify, and which **no step produced**);
3. the gate `jq`, asserting the classifier's verdict **and** an independent recomputation **and**
   their agreement.

**Mandatory triage before any red is routed** (AC-322's triage block): `classifier != recomputed`
is an **instrument defect** (S-13 step 1); `classifier == recomputed == false` is the **finding**
(S-5 ⇒ class (c)). One exit code, two very different dispositions — the triage is what keeps them
apart.

---

## 4. VP-M7 — censoring delta, now with a criterion that can fail (K-C-N13)

VP-M7 continues to record the pre/post `explain.fusion.{n_sparse_cap, selectivity, w_sparse}`
delta per path. **AC-377 is added because recording is not gating.**

Measured this pass: `explain.fusion` exposes `n_sparse_cap`, `selectivity`, `w_sparse` and a
**resolved** `n_sparse` — and **no raw count** (`retrieve.py:1085-1105`). The censoring signal is
therefore **unobservable from outside today**. W-45 adds, as additive fields:
`explain.fusion.raw_n_sparse` (the value actually passed to `resolve_sparse_weight`),
`explain.fusion.sparse_fetch_shape` and `explain.fusion.fetches[]` carrying
`{fetch, k_requested, n_returned}` **per fetch** — required by FORGE's fence ruling, since the
top-up's trigger is per-fetch and `len(sparse_ranking)` is **not** the head's raw count on the
subset path.

---

## 5. Release-checklist deltas

### 5.1 v2.0.2 — add

- [ ] **AC-357** — VP-M1's positive control green **on W-G-FLOOR's own distinct-phantom fixture**
      before any VP-M1 measurement is recorded (rule (f) / S-14)
- [ ] **AC-374** — the shipped fixture's topology captured: one distinct phantom, one derived
      union across floors {2, 10, 1000}, union non-empty
- [ ] **AC-321** — `vp-m1-floor-channel.json` carries 14 rows, the literal seed `"8"`, the
      control's **substance** (derived arrays present, `low != high`, `low ⊂ high`), and the
      invoking run's nonce on **every** row
- [ ] **AC-322** — the aggregate exists, is produced by `aggregate_seeds`, and the classifier's
      verdict **agrees with** the independent recomputation
- [ ] **AC-358** — both classifier nodes green, including `test_aggregate_uses_classifier`
- [ ] **AC-359** — **both** stale-claim sites dated: the module docstring **and**
      `run_floor_probe`'s
- [ ] **AC-313** — part 1 in the container (two full hashes, one **docstring-stripped** body
      hash, two constants); part 2 on the **host** (whole-file canonical identity)
- [ ] **AC-305** — three rig nodes green, including
      `test_liveness_measured_on_populated_edgeless_graph`
- [ ] **AC-306** — the fence record validates against the **shipped** keys
      (`ruling_text_quoted` / `ruled_at` / `ruled_by`) with non-empty `authorised_changes` and
      `breach_conditions`
- [ ] **AC-375** — the wide-band control green **before** AC-317's negative is allowed to route
- [ ] **AC-376** — `test_weight_injection_reaches_instance` green
- [ ] **AC-380** — the ESL record: `status` advanced, `acceptance_checks` populated (>= 63),
      `spec.yaml` present, `esl-cross-repo-skip.json` declaring the C3 code-state skip **with its
      compensating control**
- [ ] **AC-332 part 0** — every `red-evidence-w*.json` shard validates, and the consolidated
      `red-evidence.json` row count equals the sum of shard lengths
- [ ] **Rule-(g) audit:** every gate artifact read in this batch was produced by the chain that
      read it (nonce + tree sha matched)
- [ ] **Rule-(i) audit:** every artifact a criterion reads has a **named producing step**
      (`spec.amend-03.md` §16.3's table, all rows green)
- [ ] **No `git` inside any container** (K-C2) — grep the executed criteria for
      `docker …python -c` blocks containing `'git'`

### 5.2 v2.1.0 — add

- [ ] **AC-377** — both cases: censored ⇒ `selectivity == 0.0`; uncensored ⇒ `> 0.0`
- [ ] **AC-378** — the dense mirror node green, **or** the ungated fallback recorded in #45's
      closing comment quoting **D3's reversal condition verbatim**
- [ ] **AC-379** — the FORGE-mandated `test_subset_status_topup_recovers_active_hits` green,
      **plus** `test_topup_counter_matches_observed_calls`
- [ ] **AC-348** — the **per-path** budgets, three parametrised cases (default `<= 2`,
      single-layer `<= 2`, strict subset `<= 2 + 2L`)
- [ ] **AC-381** — the fence-breach guard green (breaches 2-6); AC-349, AC-356, AC-377 and
      AC-379 cover 1, 8, 9 and 7
- [ ] **AC-345** — part (i) under rule (h) with the tree provably restored; part (ii)'s XFAIL
      asserted on the **summary line**, not by eye
- [ ] **AC-361** — under rule (h), tree provably restored
- [ ] **Fence reversal check:** if the only green path for W-44 required a `bm25_search`
      parameter, a SQL change, a new storage method or an unbounded refetch loop, **the ALLOW is
      void, S-10 fires, #44 is re-filed**
- [ ] **D6 reversal check:** `Config.recall_active_only` still defaults `True`
      (`config.py:333`, env default `config.py:437`)

---

## 6. STOP table — deltas

| id | delta |
|---|---|
| **S-5** | **Amended.** Its evidence may now include the **structural** finding (AC-374): on the shipped fixture the derived union is floor-invariant **by topology**. A `channel_live == false` whose **instrument** control (AC-357) is green **is** admissible, provided AC-374's artifact accompanies it. `amend-02`'s *"most likely outcome"* is superseded by *"the only possible outcome on this fixture"*. |
| **S-13** | Unchanged. §2.6's three-branch routing decides **whether step 1 is entered at all** — the misrouting spent the budget before the ladder was reached. |
| **S-14** | **Amended.** A routing negative is unvalidated when its **instrument** is uncontrolled; it is **validated** when the instrument is controlled and the fixture is provably incapable of the positive, **provided that impossibility is an emitted artifact**. |
| **NEW S-15 — STALE ARTIFACT** | **Trigger:** any `jq` failing only on `.run_nonce`/`.tree_sha`, or any artifact read that the invoking chain did not write. **Action:** not a gate result — not a red, not a green. Re-run the rule-(g) chain. **Recording a stale read as a red is itself a finding.** Not an S-13 event: the gate is not unfailable, it was **not run**. |
| **S-10** | **Does not fire.** FORGE's fence verdict is **ALLOW** (`CHANGE/fence-amend.json`). W-44's entry precondition is satisfied on that gate; the reversal condition in §5.2 remains live. |

---

## 7. What this plan does NOT license — additions

`verification-plan.md` §6, `amend-01` §6 and `amend-02` §6 stand. Added:

- Any use of a gate artifact whose `run_nonce` does not match the run that read it (**S-15**).
- Any claim that AC-357's red is a finding about the **floor**. On W-G-FLOOR's own fixture it is
  a finding about the **probe**.
- Any claim that the shipped fixture's floor-invariance is a **probe defect**. It is a
  **topology** result, measured, and AC-374 asserts it.
- Any citation of the seed-8 evidence, or of *"the channel is LIVE and MEASURED"*, as applying to
  the shipped fixture: both come from the **reverted** variant (3), **pre-#41**, and rest on a
  mechanism #41 deleted.
- Any criterion that runs `git` inside a container (K-C2 — it does not exist there).
- Any relaxation of **AC-348** or **AC-355** to fit an implementation. The ruled fallback for a
  non-discriminating subset fixture is **explicit suppression plus a follow-up filing**, never a
  loosened budget.
- Any shipping of D3's **dense** half without either **AC-378** green or the ungated fallback
  recorded **with D3's reversal condition quoted**.
- Any treatment of `has_code: false` as meaning "this change has no code". It means the code is
  in **another repository**, where ESL's code-state gates cannot see it — declared, with its
  compensating control, in `esl-cross-repo-skip.json`.
