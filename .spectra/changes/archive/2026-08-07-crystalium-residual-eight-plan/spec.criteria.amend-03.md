# spec.criteria.amend-03 — `crystalium-residual-eight-plan`

**Amendment `amend-03`.** Supersedes named criteria of `spec.criteria.amend-01.md` and
`spec.criteria.amend-02.md` (hash `f385f39bbabb6ee7371afd8815ef2de0e18905a0048d2f4000813edf219b0d9f`).
No earlier file is edited. Chain: `spec.criteria.md` -> `amend-01` -> `amend-02` ->
**`amend-03`** (governs on conflict).

Conventions and global rules **(a)-(f)** carry forward unchanged. **Rules (g), (h) and (i) are
added below and have equal standing.**

| shorthand | absolute path |
|---|---|
| MAIN | `/home/rynaro/workspace/oss/agents/crystalium` |
| CHANGE | `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan` |
| NEXUS | `/home/rynaro/workspace/oss/agents/eidolons` |

---

## 0.1 NEW GLOBAL RULE (g) — ARTIFACT FRESHNESS (K-C6)

> **(g)** No criterion may read a gate artifact it did not just cause to be written. Every
> artifact-producing block is **one `&&` chain** that (1) `rm -f`s the artifact, (2) mints a run
> nonce and reads the tree sha **on the host**, (3) runs the emit with both passed in as
> environment, (4) `jq`s the file with **`.run_nonce` and `.tree_sha` asserted against the
> invoking run**.

`emit(result, out)` stamps `run_nonce = os.environ["CRYSTALIUM_GATE_NONCE"]` and
`tree_sha = os.environ["CRYSTALIUM_TREE_SHA"]` by **direct subscript** — a missing variable
raises `KeyError` and the emit fails loudly. **No default, no `.get`, no fallback.**

Canonical form (every gate criterion below is an instance of it):
```
cd MAIN && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/<name>.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "…m.emit(m.run(), '/app/evals/results/<name>.json')" && jq -e --arg n "$NONCE" --arg t "$TREE" '(type == "object") and (.run_nonce == $n) and (.tree_sha == $t) and <pred>' evals/results/<name>.json
```
Seeded loops use **one** nonce for the whole family, `rm -f` the whole glob first, and the
aggregate asserts `all(.seeds[]; .run_nonce == $n)`.

**A nonce covers one MEASUREMENT, not one command.** Where a measurement spans several commands
whose artifacts are compared with each other — VP-M1 is control + topology capture + 14 seeds +
aggregate — the nonce is minted **once**, at the head of the chain, and every command in it
carries the same value. Minting per command would make a cross-artifact assertion such as
`.positive_control.run_nonce == $n` **unsatisfiable by construction**, which is a false red of
the same family as the one rule (g) exists to prevent.

**Multi-file reads must slurp.** `jq -e 'pred' a.json b.json` evaluates per input and exits on
the **last** output — a failing first file is invisible. Every multi-file predicate in this
campaign uses `jq -s -e 'all(.[]; …)'`.

**Fourth exit class, added to rule (a)'s three:** a `jq` exit 1 whose only failing conjunct is
`.run_nonce` or `.tree_sha` is a **STALE READ (S-15)** — not a red, not a green. Re-run the
chain. Recording it as a red is itself a finding.

## 0.2 NEW GLOBAL RULE (h) — DETACHED-CHECKOUT HYGIENE (K-C-N8)

> **(h)** Any criterion that checks out a ref other than the tree it was invoked on MUST
> (i) refuse to run on a dirty tree, (ii) record the original ref, (iii) restore it
> **unconditionally, including on failure**, (iv) assert the restore before reporting PASS.

```
cd MAIN && test -z "$(git status --porcelain)" && ORIG="$(git rev-parse HEAD)" && git checkout --detach <ref> && <command> ; RC=$? ; git checkout --detach "$ORIG" && test "$(git rev-parse HEAD)" = "$ORIG" && test "$RC" = "0"
```

## 0.3 NEW GLOBAL RULE (i) — PRODUCER-NAMED ARTIFACT CONTRACTS (K-B8's species, 4th recurrence)

> **(i)** Every criterion that reads a file it did not just produce MUST name **(1) the
> producing step, (2) the exact filename, (3) the exact key names it asserts.** "The maker" or
> "W-<unit>" is not a producing step. Where the artifact already exists, the criterion is
> written **against the shipped keys**, and discharged **before** freeze, not after.

Producer audit table: `spec.amend-03.md` §16.3.

---

## 1. Wave 0

### AC-305 (event-driven) — REPLACED (K-C-N12)
*(was: one pytest node plus the correct liveness form stated **in prose only** — so the shared
rig, which is exactly where `all_edges() == 0` would live, was checked by an unchanged node that
cannot fail on it)*

GIVEN the shared corpus rig's liveness self-check
WHEN it is exercised on a populated edgeless graph, on an empty graph, and on a binding pinned axis
THEN the rig shall report `measured` only when the store is proven live and genuinely edgeless
VERIFY: three normative nodes, all required — run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_corpus_rig.py::test_confounded_axis_returns_no_numbers mcp-server/tests/test_corpus_rig.py::test_liveness_measured_on_populated_edgeless_graph mcp-server/tests/test_corpus_rig.py::test_liveness_confounded_on_empty_graph -v
```
**PASS = exit 0 with three nodes collected.** All three names are **normative**.

`test_liveness_measured_on_populated_edgeless_graph` is the discriminating one: it builds a
graph with `node_count() > 0` and no edges and requires `verdict == "measured"` with
`liveness.edge_count == 0` and `liveness.node_count == <corpus size>`. **A rig written
`all_edges() == 0` is `[] == 0` in Python — always `False` — so it can never conclude "edgeless"
and therefore can never report `measured` here** (K-B16). `test_liveness_confounded_on_empty_graph`
covers the other direction (`node_count == 0` ⇒ `confounded`, no numeric axes), so a rig that
reports `measured` on a dead store also fails. The §A.3 form is now the rig's **asserted
contract**, not a paragraph.

### AC-306 (ubiquitous) — REPLACED (F-1: the criterion did not discharge against the artifact FORGE wrote)
*(was: `.ruling_quote` / `.decided_at` / `.decided_by` — **measured exit 1** against the shipped
`fence-amend.json`, which carries `ruling_text_quoted` / `ruled_at` / `ruled_by`. Rule (i): the
criterion is aligned to the shipped keys, and strengthened while aligned.)*

GIVEN the `bm25_search` status-predicate fence ruling recorded by FORGE at `CHANGE/fence-amend.json`
WHEN the fence-amend record is inspected
THEN the record shall carry a machine-readable verdict together with the authorisations, breach conditions, composition ruling and reversal condition W-44 depends on
VERIFY: run the command block below; PASS exactly as stated.
```
jq -e '(type == "object") and (.verdict == "ALLOW" or .verdict == "DENY") and (.ruling_text_quoted | type == "string") and ((.ruling_text_quoted | length) > 0) and (.ruled_at | type == "string") and (.ruled_by | type == "string") and (.authorised_changes | type == "array") and ((.authorised_changes | length) > 0) and (.breach_conditions | type == "array") and ((.breach_conditions | length) > 0) and (.composition_ruling | type == "string") and ((.composition_ruling | length) > 0) and (.reversal_condition | type == "string") and ((.reversal_condition | length) > 0)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/fence-amend.json
```
**PASS = exit 0.** **Producer (rule (i)): FORGE's W-HOP ruling step; file `CHANGE/fence-amend.json`;
keys as listed.** *Verified this pass: the amended predicate exits **0** on the shipped artifact
and the superseded one exits **1**.*

**It still fails on the failures it exists to catch:** a missing verdict, an empty quotation, an
absent decider or timestamp, and — new — **an `ALLOW` carrying no breach conditions, which is a
fence with no teeth**. `DENY` still triggers **S-10**. The narrative sibling `fence-amend.md`
remains the record; the `.json` is normative.

---

## 2. Wave 1 — the four gates

### AC-310 (event-driven) — AMENDED (rule (g))
The GIVEN/WHEN/THEN of `spec.criteria.amend-01.md`'s AC-310 stand **unchanged**. Its two command
blocks are replaced by **one** rule-(g) chain, so the emit's exit is load-bearing and the read is
provably fresh.

GIVEN the rebuilt cross-layer fixture of `spec.amend-01.md` §B.2.1
WHEN `Aetheryte.recall` runs on `b7f1a47` under a freshly minted run nonce
THEN the gate shall report the semantic target at the exact fused rank the per-layer append order predicts
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/cross-layer-gate.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.cross_layer_gate as m; m.emit(m.run(), '/app/evals/results/cross-layer-gate.json')" && jq -e --arg n "$NONCE" --arg t "$TREE" '(type == "object") and (.run_nonce == $n) and (.tree_sha == $t) and (.target_rank | type == "number") and (.expected_blocked_rank | type == "number") and (.liveness.corpus_per_layer | type == "number") and (.expected_blocked_rank == .liveness.corpus_per_layer) and (.expected_blocked_rank == 3) and (.target_rank == .expected_blocked_rank)' evals/results/cross-layer-gate.json
```
**PASS = exit 0.** Routing unchanged (`target_rank == 0` with AC-312 fully green ⇒ **S-3** ⇒
**S-13**; any AC-312 conjunct red ⇒ fixture bug, S-13 step 1). **New:** a failure on
`.run_nonce`/`.tree_sha` alone is **S-15**, not a red.

### AC-312 (ubiquitous) — AMENDED (K-C-N10; rule (g))
`spec.criteria.amend-01.md`'s six liveness conjuncts stand. **Two additions**, and the read moves
onto AC-310's chain (same nonce, same invocation).

GIVEN the cross-layer gate's emitted result
WHEN its liveness block is inspected
THEN the sparse arm's recorded membership shall be bound to the arm size `explain` reports
VERIFY: append the conjuncts below to AC-310's `jq` predicate in the same chain; PASS exactly as stated.
```
and (.sparse_ranking | type == "array") and (.sparse_ranking_provenance == "bm25_search_spy") and ((.sparse_ranking | length) == .liveness.sparse_arm_size) and (.liveness.sparse_arm_size == (.liveness.corpus_per_layer + 1)) and (.liveness.global_bm25_rank0 == "sem-target") and (.liveness.node_count == 4) and (.liveness.edge_count == 0) and (.liveness.dense_arm_size == 0) and (.verdict == "measured")
```
**PASS = exit 0.** **`sparse_ranking` provenance is NORMATIVE (K-C-N10):** it is captured by a
**recording spy on `relational.bm25_search`** — FORGE D5's recording-proxy pattern, reused —
de-duplicated in first-seen order exactly as `retrieve.py:527-530` does. **Re-issuing
`bm25_search` after the run to reconstruct it is FORBIDDEN**: that is a re-implementation which
can diverge from what `recall` actually did, the precise risk D5's self-check exists to close.
`explain` carries `arm_sizes` (**sizes, not membership**, `retrieve.py:1098-1104`), so
`len(sparse_ranking) == liveness.sparse_arm_size` is the binding self-check that makes the spy
answerable to `explain`.

### AC-313 (event-driven) — REPLACED AGAIN (K-C1, K-C2, K-C-N9)
*(amend-02's version pinned `inspect.getsource(run_floor_probe)` — **which includes the
docstring** — while AC-359 mandated correcting that same docstring, so the amendment both
required and forbade one edit; part 2 ran `git` **inside the container**, where it does not
exist; and its residual filter exempted any diff line containing the literal `cross_layer`,
including a trailing comment on an otherwise illicit edit.)*

GIVEN the `cross_layer` axis rename and the #48 docstring correction in `evals/fusion_gate.py`
WHEN the module is inspected at runtime and its source compared against `b7f1a47`
THEN the AC-125 fixture's code shall be byte-frozen while exactly two docstrings and one key rename remain free to change
VERIFY: two parts, both required — run the command blocks below; PASS exactly as stated.

(i) runtime pins, **in the container** (proves importability; no `git`):
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import ast, hashlib, inspect, textwrap, evals.fusion_gate as m
def body(fn):
    src = textwrap.dedent(inspect.getsource(fn)); node = ast.parse(src).body[0]; st = list(node.body)
    if st and isinstance(st[0], ast.Expr) and isinstance(getattr(st[0],'value',None), ast.Constant) and isinstance(st[0].value.value, str): st = st[1:]
    lines = src.splitlines(True); return ''.join(lines[st[0].lineno-1:st[-1].end_lineno])
FULL = {'_crystal':'6fa658f431c97b759824408cb5af0f3a98f851dd46c089607c649a39f1930ded','_build_fixture':'66d3e9a7ea3bb8b1830c5d5ea3de7c8f70afef7a098b4a38069677ef6d6b62d4'}
for fn, want in FULL.items():
    got = hashlib.sha256(inspect.getsource(getattr(m, fn)).encode()).hexdigest(); assert got == want, (fn, got, want)
got = hashlib.sha256(body(m.run_floor_probe).encode()).hexdigest()
assert got == '9b371898fdfc1a46966234589fa5d6a9c41248a4496f36f6abbcaa96f4bb1519', ('run_floor_probe body', got)
assert m._FILLER_COUNT == 12, m._FILLER_COUNT
assert m._QUERY == 'plarnix threxil vandomere signature', m._QUERY
print('ok')
"
```
(ii) whole-file canonical identity, **on the host** (`git` is absent from the container — K-C2):
```
cd /home/rynaro/workspace/oss/agents/crystalium && git rev-parse --verify b7f1a47^{commit} && python3 -c "
import ast, subprocess
def canon(src):
    tree = ast.parse(src); lines = src.splitlines(True); cuts = []
    d = tree.body[0]
    assert isinstance(d, ast.Expr) and isinstance(d.value, ast.Constant) and isinstance(d.value.value, str), 'module docstring missing'
    cuts.append((d.lineno, d.end_lineno, '<<MODULE_DOCSTRING>>' + chr(10)))
    for n in tree.body:
        if isinstance(n, ast.FunctionDef) and n.name == 'run_floor_probe':
            s = n.body[0]
            assert isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant) and isinstance(s.value.value, str), 'run_floor_probe docstring missing'
            cuts.append((s.lineno, s.end_lineno, '<<RUN_FLOOR_PROBE_DOCSTRING>>' + chr(10)))
    out, prev = [], 0
    for a, b, tag in sorted(cuts):
        out += lines[prev:a-1] + [tag]; prev = b
    out += lines[prev:]
    return ''.join(out).replace('sparse_arm_per_layer_probe', 'cross_layer')
old = subprocess.run(['git','show','b7f1a47:evals/fusion_gate.py'], capture_output=True, text=True, check=True).stdout
new = open('evals/fusion_gate.py').read()
assert canon(old) == canon(new), 'fusion_gate.py changed outside the two licensed docstrings and the cross_layer rename'
print('ok')
"
```
**PASS = exit 0 and the literal output `ok` on both.**

Part (i) byte-freezes `_crystal` and `_build_fixture` in **full**, `run_floor_probe`'s **body**
(docstring stripped by AST — AC-359 mandates that docstring's correction), and two constants.
*The body hash was computed this pass and cross-checked on **host py 3.14.6** and **container py
3.12.13** — byte identical, so the pin carries no interpreter dependence.* `_FILLER_COUNT == 12`
is vigil's F-V4 cardinality fix; moving it silently removes the floor's tail.

Part (ii) replaces amend-02's line filter: after redacting the **two licensed docstrings** and
inverting the **one licensed rename**, the whole file must be **byte-identical** to `b7f1a47`.
There is no exemption to abuse. *Verified this pass: identical today; **passes** a simulated
rename-plus-docstring edit; **rejects** a one-line `_build_fixture` edit hidden behind a trailing
`# cross_layer` comment — K-C-N9's hole.*

### AC-314 (event-driven) — AMENDED (rule (g))
GIVEN a single-layer corpus of `M` crystals with `M > candidate_k`
WHEN the corpus-scaling gate runs under a freshly minted run nonce
THEN the planted ground-truth record shall be absent from the recalled ids
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/corpus-scaling-gate.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.corpus_scaling_gate as m; m.emit(m.run(), '/app/evals/results/corpus-scaling-gate.json')" && jq -e --arg n "$NONCE" --arg t "$TREE" '(type == "object") and (.run_nonce == $n) and (.tree_sha == $t) and (.planted_recovered == false) and (.liveness.corpus_size > .liveness.candidate_k) and (.liveness.sparse_arm_size == .liveness.candidate_k) and (.liveness.layers == ["episodic"]) and (.liveness.edge_count == 0) and (.liveness.node_count > 0)' evals/results/corpus-scaling-gate.json
```
**PASS = exit 0.** Substance unchanged from `amend-01`; only the freshness plumbing is new.
Rule-(f) control unchanged and correctly directed: **AC-315** demonstrates the instrument can
emit `planted_recovered == true` on a small corpus.

### AC-316 (ubiquitous) — REPLACED (K-C-N11)
*(was: pointed at `evals.corpus_scaling_gate`, which **varies `M` and never patches
`FETCH_WIDTH_FLOOR`** — so the leak guard guarded a patch that does not happen and was
permanently green)*

GIVEN the floor-sensitivity probe, which monkeypatches `FETCH_WIDTH_FLOOR` in `try/finally`
WHEN the probe has run in the same process
THEN the patched value shall be observable during the run while the module constant reads 10 afterwards
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import crystalium.aetheryte.retrieve as r
before = r.FETCH_WIDTH_FLOOR; assert before == 10, before
import evals.floor_sensitivity_gate as m
res = m.vp_m1_probe(floor=1000, fixture='shipped')
assert res['floor_applied_readback'] == 1000, ('patch never applied', res.get('floor_applied_readback'))
after = r.FETCH_WIDTH_FLOOR; assert after == 10, ('leaked monkeypatch', before, after)
print('ok')
"
```
**PASS = exit 0 and the literal output `ok`.** Two halves, both load-bearing:
`floor_applied_readback` is `retrieve.FETCH_WIDTH_FLOOR` read **inside** the patched region and
is the **anti-vacuity** guard (a probe that never patches now FAILS rather than passing
silently); the same-process post-run read is what makes an unrestored patch detectable
(`fusion_gate.py:227-229, 264`'s pattern). **Recorded normatively:** the corpus-scaling gate does
**not** patch this constant, so no leak guard is written for it — that absence is a stated
decision, not an omission.

### AC-317 (event-driven) — AMENDED (rule (g); control re-designated per K-C-N2)
The three-command shape and the 21-cell predicate of `spec.criteria.amend-01.md`'s AC-317 stand.
Two changes.

GIVEN the weight-discriminating fixture across the 7-seed C-2 protocol
WHEN each seed's cells are emitted under one shared run nonce
THEN every seed shall show at least two distinct outcomes across the three weights
VERIFY: run `amend-01`'s AC-317 chain with the rule-(g) wrapper below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/wd-seed-*.json && ( for s in 0 1 2 3 4 5; do docker compose run --rm -e PYTHONHASHSEED=$s -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run(seed_label='$s'), '/app/evals/results/wd-seed-$s.json')" || exit 1; done ) && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run(seed_label='unset'), '/app/evals/results/wd-seed-unset.json')" && jq -s -e --arg n "$NONCE" '(length == 7) and (all(.[]; (.run_nonce == $n) and (.cells | length) == 3 and (all(.cells[]; (.weight_readback | type == "number") and (.weight_readback == .weight) and (.outcome | type == "string"))))) and (all(.[]; ([.cells[].outcome] | unique | length) >= 2))' evals/results/wd-seed-0.json evals/results/wd-seed-1.json evals/results/wd-seed-2.json evals/results/wd-seed-3.json evals/results/wd-seed-4.json evals/results/wd-seed-5.json evals/results/wd-seed-unset.json
```
**PASS = exit 0.** The 7th run omits `-e PYTHONHASHSEED` entirely (rule (d)); every run carries
the **same** nonce, so a seed file left by an earlier run fails the `all(.[]; .run_nonce == $n)`
conjunct rather than being slurped into a well-formed 7-row set.

**Rule-(f) control re-designated (K-C-N2).** `amend-02`'s audit cited D8's edge-severing
perturbation, which demonstrates the **negative** (one outcome) — the wrong direction. The
positive-capability control is now **AC-375** (wide-band responsiveness). `weight_readback`'s
tautology hole is closed by **AC-376**, not by this predicate.

### AC-321 (event-driven) — REPLACED AGAIN (K-C-N1; rule (g); K-C-N5)
*(amend-02's version accepted a `positive_control` that was a **bare boolean** — verified by
Kupo: an artifact whose control is `{floor_low, floor_high, channel_live:true}` with no derived
arrays exits **0** — and named a probe symbol (`vp_m1_seed`) that no ruling defines.)*

GIVEN the post-#41 tree and the D5 derived-membership probe
WHEN the probe runs over the 14-point historical seed set with its positive control
THEN the recorded `channel_live` shall be derivable from per-seed evidence gathered under one run nonce on a seed set provably containing the only known divergent point
VERIFY: run the command block below against the artifact VP-M1 step 3 emits; PASS exactly as stated.
```
jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.seeds | type == "array") and ((.seeds | length) == 14) and (all(.seeds[]; .run_nonce == $n)) and (([.seeds[].seed] | index("8")) != null) and (([.seeds[].seed] | index("unset")) != null) and (([.seeds[].seed] | unique | length) == 14) and (.seed_set_covers_divergent_point == true) and (all(.seeds[]; (.low.derived | type == "array") and (.high.derived | type == "array") and (.low.self_check_ok == true) and (.high.self_check_ok == true) and (.probe_symbol == "vp_m1_probe") and (.probe_calls == 2))) and (.positive_control | type == "object") and (.positive_control.run_nonce == $n) and (.positive_control.fixture == "distinct_phantom") and (.positive_control.channel_live == true) and (.positive_control.low.derived | type == "array") and (.positive_control.high.derived | type == "array") and ((.positive_control.low.derived | length) > 0) and (.positive_control.low.derived != .positive_control.high.derived) and (((.positive_control.low.derived - .positive_control.high.derived) | length) == 0) and (.positive_control.low.self_check_ok == true) and (.positive_control.high.self_check_ok == true) and (.channel_live | type == "boolean") and (.channel_live == ([.seeds[] | .low.derived != .high.derived] | any))' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```
**PASS = exit 0.** `$NONCE` is the nonce minted at the head of **VP-M1's chain**
(`verification-plan.amend-03.md` §2), and this `jq` is that chain's **final command** — never a
bare read of the file. **One nonce covers the whole measurement** (control, topology capture, 14
seeds, aggregate), which is why `.positive_control.run_nonce == $n` is satisfiable: a control
left over from an earlier invocation fails it.

Six independent ways to fail, each closing a measured hole: a seed set excluding **8**
(`index("8")`); a fabricated verdict (`channel_live` must equal the disjunction over its own
rows); a **missing** control; a control that is a **bare boolean** (K-C-N1 — the derived arrays
must be present, non-empty, **different**, and `low ⊆ high`); a row produced by some other symbol
(`probe_symbol`/`probe_calls`); and a **stale** row from an earlier run (`run_nonce`).

`channel_live == false` here licenses only: *"no derived-membership difference observable at
14/14 sampled points on the shipped fixture (variant 2), post-#41"* — and, **with AC-374 green**,
the stronger structural statement that none is **possible** on that fixture
(`CHANGE/issue-48-mechanism-note.md`). It never licenses *"the channel is dead"* in general.

### AC-322 (event-driven) — REPLACED (K-C4, K-C5; rule (g))
*(amend-02's version read `floor-7seed-aggregate.json`, which **no step produced** — grepped:
one hit, the criterion itself — and computed disjointness **in jq** while AC-358 controlled a
classifier nothing consumed.)*

GIVEN the new tie-break-neutral floor-sensitivity fixture measured over the 7-seed C-2 protocol
WHEN the aggregate is produced by `aggregate_seeds` and inspected
THEN the two floors' target-rank distributions shall be disjoint under both the shipped classifier and an independent recomputation
VERIFY: run the four-command chain below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/floor-seed-*.json && ( for s in 0 1 2 3 4 5; do docker compose run --rm -e PYTHONHASHSEED=$s -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.run_seed(seed_label='$s'), '/app/evals/results/floor-seed-$s.json')" || exit 1; done ) && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.run_seed(seed_label='unset'), '/app/evals/results/floor-seed-unset.json')" && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.aggregate_seeds(['0','1','2','3','4','5','unset']), '/app/evals/results/floor-seed-aggregate.json')" && jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.seed_set | type == "array") and ((.seed_set | length) == 7) and (.seed_set_covers_divergent_point == false) and (.divergent_point_known == "8") and (.seeds | type == "array") and ((.seeds | length) == 7) and (all(.seeds[]; (.run_nonce == $n) and (.floor10_target_rank | type == "number") and (.floor1000_target_rank | type == "number") and (.floor10_target_rank >= 0) and (.floor1000_target_rank >= 0))) and (.classifier.symbol == "classify_disjoint") and (.classifier.disjoint | type == "boolean") and (([.seeds[].floor10_target_rank] | unique) as $a | ([.seeds[].floor1000_target_rank] | unique) as $b | (($a | length) > 0) and (($b | length) > 0) and (.classifier.disjoint == ((($a - $b) | length) == ($a | length))) and (.classifier.disjoint == true))' evals/results/floor-seed-aggregate.json
```
**PASS = exit 0.** **Producer (rule (i)): `aggregate_seeds(seed_labels)` in
`evals/floor_sensitivity_gate.py`, third command of this chain; file
`evals/results/floor-seed-aggregate.json`** — renamed from `floor-7seed-aggregate.json`, whose
name hard-coded a seed count a 14-seed run would falsify.

**Two independent computations must agree (K-C5).** `aggregate_seeds` calls the pure
`classify_disjoint(low_ranks, high_ranks)` — the symbol **AC-358 tests** — and the `jq` above
recomputes disjointness from the rows. `.classifier.disjoint == <recomputation>` is the
cross-check; `== true` is the gate. The classifier is no longer decoration.

**Triage is MANDATORY before any red is routed**, because two very different findings share one
exit code:
```
cd /home/rynaro/workspace/oss/agents/crystalium && jq -r '{classifier: .classifier.disjoint, recomputed: (([.seeds[].floor10_target_rank] | unique) as $a | ([.seeds[].floor1000_target_rank] | unique) as $b | ((($a - $b) | length) == ($a | length))), low: ([.seeds[].floor10_target_rank] | unique), high: ([.seeds[].floor1000_target_rank] | unique)}' evals/results/floor-seed-aggregate.json
```
- `classifier != recomputed` ⇒ **INSTRUMENT DEFECT** (S-13 step 1). **Not** an S-5 event. Fix the
  disagreement and re-run; no disposition is routed off a disagreeing pair.
- `classifier == recomputed == false` ⇒ the real finding ⇒ **S-5** ⇒ **S-13 class (c)**: retire
  AC-138/AC-139 with the mechanism note, close #48 **retired**, not discharged.

### AC-357 (event-driven) — REPLACED AGAIN (K-C3 — the control was unbuildable on the shipped fixture)
*(amend-02's control ran `floor=2` vs `floor=1000` on the **shipped** fixture and asserted
`channel_live == true`. Kupo measured `DERIVED_UNION=['Z']` at floors 2, 10 **and** 1000:
`_build_fixture:172-177` points `N1`, `N2` and `N3` at the **same** phantom, and
`fetch_width = max(k, FETCH_WIDTH_FLOOR)` always admits `N1`. **The control could not emit
`true` at any floor pair**, its red was routed to "probe defect", and S-14 then forbade recording
any `channel_live` — W-G-FLOOR could not start.)*

GIVEN W-G-FLOOR's own floor-sensitivity fixture, built with a DISTINCT phantom per edge-bearing competitor
WHEN the probe is run at `floor = 2` against `floor = 1000` on that fixture
THEN the probe shall emit `channel_live == true` with the high floor's derived union a proper superset of the low floor's
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/m1-positive-control.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_pair(seed_label='0', floor_low=2, floor_high=1000, fixture='distinct_phantom'), '/app/evals/results/m1-positive-control.json')" && jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.fixture == "distinct_phantom") and (.probe_symbol == "vp_m1_probe") and (.probe_calls == 2) and (.fixture_phantom_targets | type == "array") and ((.fixture_phantom_targets | length) >= 3) and ((.fixture_phantom_targets | unique | length) == (.fixture_phantom_targets | length)) and (.floor_low == 2) and (.floor_high == 1000) and (.low.derived | type == "array") and (.high.derived | type == "array") and ((.low.derived | length) > 0) and ((.high.derived | length) > (.low.derived | length)) and (((.low.derived - .high.derived) | length) == 0) and (.low.derived != .high.derived) and (.channel_live == true) and (.low.self_check_ok == true) and (.high.self_check_ok == true)' evals/results/m1-positive-control.json
```
**PASS = exit 0.** **Producer (rule (i)): `vp_m1_pair(fixture='distinct_phantom')` in
`evals/floor_sensitivity_gate.py`, the command above; file
`evals/results/m1-positive-control.json`.**

**Why this fixture and not the shipped one.** The control fixture assigns `c1 -> z1`,
`c2 -> z2`, `c3 -> z3` with `c1` inside the low floor's slice and `c2`, `c3` outside it, so
`[:2]` reaches only `z1` while `[:1000]` reaches all three: **the derived union differs across
the floor boundary by construction**, independent of hash order. `fixture_phantom_targets` is
read **off the graph at runtime**, never hard-coded, so this control cannot be pointed at a
same-phantom fixture and silently mean nothing — the exact defect it exists to prevent.

**Routing — three branches, not two. This is the correction that matters:**
1. **RED here, on W-G-FLOOR's own distinct-phantom fixture** ⇒ **PROBE OR FIXTURE DEFECT**
   (S-13 step 1). The instrument cannot see a difference that exists by construction. Fix and
   re-run; **no `channel_live` recordable** (S-14).
2. **GREEN here, while the shipped fixture shows no floor difference** (AC-374 green, AC-321
   `channel_live == false`) ⇒ **EVIDENCE, not a probe defect.** That is the structural finding of
   `CHANGE/issue-48-mechanism-note.md`; record it and route to **S-5 ⇒ S-13 class (c)**.
3. **GREEN here, and the shipped fixture DOES differ** ⇒ the prediction and the mechanism note
   are both **refuted**; correct the note, carry the tie-break explanation.

*`amend-02` collapsed 1 and 2 into "probe defect", which spent the one-cycle redesign budget on a
misdiagnosis of a correctly-instrumented probe.*

### AC-358 (event-driven) — REPLACED (K-C5 — the control now tests the instrument AC-322 consumes)
GIVEN the pure disjointness classifier `classify_disjoint` that `aggregate_seeds` calls
WHEN it is exercised on synthetic rank lists with no I/O
THEN it shall reach both branches while rejecting the empty-input case
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_floor_sensitivity_gate.py::test_disjointness_classifier_both_branches mcp-server/tests/test_floor_sensitivity_gate.py::test_aggregate_uses_classifier -v
```
**PASS = exit 0 with two nodes collected.** Both node names and the symbol name
`evals.floor_sensitivity_gate.classify_disjoint` are **normative**.

`test_disjointness_classifier_both_branches` asserts at minimum `([0,0],[2,2]) ⇒ disjoint true`;
`([0,1],[1,2]) ⇒ false`; `([],[]) ⇒ false` (the K-B3 vacuity case, where `|[] − []| == |[]|` is
`0 == 0`). `test_aggregate_uses_classifier` is the K-C5 binding: it feeds synthetic per-seed rows
to `aggregate_seeds` and asserts the emitted `classifier.disjoint` **equals**
`classify_disjoint` called directly on the same inputs, and that `classifier.symbol` is
`"classify_disjoint"`. Without it, the classifier could be perfect and the aggregate wrong.

**Honest limit, unchanged from `amend-02` §3.6:** this discharges rule (f) for the
**instrument**, not for the **fixture**. A fixture-level positive control would be circular (it
*is* the gate passing); its absence is exactly **S-5's** trigger.

### AC-359 (ubiquitous) — REPLACED (K-C1 — BOTH stale-claim sites, not one)
*(amend-02's version read only `m.__doc__`. `run_floor_probe`'s docstring (`:293-311`) carries
the same claim in stronger form — *"the floor DOES have a live, measured channel on this
fixture"*, *"anomaly A's single-successful-seed cap"* — and amend-02 simultaneously **froze** it
via `inspect.getsource`. As specified, the campaign would have shipped a file whose module
docstring says "pre-#41, untested" and whose function docstring 200 lines later says the
opposite, with the criteria mandating exactly that.)*

GIVEN the two floor-channel liveness claims in `evals/fusion_gate.py` — the module docstring and `run_floor_probe`'s
WHEN the shipped source is read on the post-#41 tree
THEN each claim shall be dated as pre-#41 and identified as untested since
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import evals.fusion_gate as m
sites = {'module': (m.__doc__ or ''), 'run_floor_probe': (m.run_floor_probe.__doc__ or '')}
for name, d in sites.items():
    low = d.lower()
    assert ('live and measured' in low) or ('does have a live' in low), (name, 'the superseded claim was DELETED; it must be dated, not erased')
    assert ('single-seed cap' in low) or ('single-successful-seed cap' in low), (name, 'the mechanism name #41 removed was deleted')
    assert '#41' in d, (name, 'no reference to crystalium#41')
    assert ('56c8510' in d) or ('pre-#41' in low), (name, 'not dated as pre-#41 (config.py:304-308 pattern)')
    assert ('not been re-tested' in low) or ('untested' in low), (name, 'does not state it is untested post-#41')
    assert ('cab9b73' in d) or ('graph.py:215-230' in d), (name, 'does not cite what removed the mechanism')
print('ok')
"
```
**PASS = exit 0 and the literal output `ok`.**

*Verified at `b7f1a47` this pass, per site:* `live and measured` PRESENT (module),
`does have a live` PRESENT (`run_floor_probe`), `single-seed cap` / `single-successful-seed cap`
PRESENT respectively — while `#41`, `56c8510`, `pre-#41`, `untested`, `not been re-tested`,
`cab9b73` and `graph.py:215-230` are **ABSENT at both**. **AC-359 therefore fails today at both
sites and greens only on real work.**

The first two assertions are deliberate **anti-deletion** guards: the superseded claim and the
mechanism it named must be **dated, not erased** — *"the failures are kept in this docstring on
purpose"* (`fusion_gate.py:14-16`), and erasing a superseded claim destroys the record §3.1
exists to protect. The `config.py:304-308` precedent (*"HISTORICAL (pre-#41 tree, 56c8510)"*) is
the required form.

**Ownership:** the bytes of **both** docstrings belong to **W-G-XL** (its grant is extended from
`:72-92` + `:104-106` to *"the module docstring and `run_floor_probe`'s docstring"*);
**W-G-FLOOR touches `evals/fusion_gate.py` not at all** (FORGE D5 holds); the **claim** is #48's
and is cited in its closing comment. AC-313's restructured freeze permits exactly these two
edits — no more.

### AC-374 (ubiquitous) — ADDED (K-C3's structural finding, MECHANISED)

GIVEN the shipped AC-125 fixture, whose three edge-bearing competitors share one phantom
WHEN its topology and its derived-arm membership are captured across three floors in one process
THEN the derived union shall be identical at every floor with exactly one distinct phantom target
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/m1-shipped-fixture-topology.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.shipped_fixture_topology(floors=[2,10,1000]), '/app/evals/results/m1-shipped-fixture-topology.json')" && jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.fixture == "shipped") and (.topology_source == "graph.all_edges") and ((.edge_sources | sort) == ["N1","N2","N3"]) and ((.phantom_targets | length) == 3) and ((.phantom_targets | unique | length) == 1) and (.distinct_phantom_count == 1) and (.derived_union_by_floor | type == "object") and ((.derived_union_by_floor | keys | length) == 3) and ((.derived_union_by_floor | to_entries | map(.value) | unique | length) == 1) and ((.derived_union_by_floor | to_entries | map(.value)[0] | length) > 0)' evals/results/m1-shipped-fixture-topology.json
```
**PASS = exit 0.** **Producer (rule (i)): `shipped_fixture_topology(floors)` in
`evals/floor_sensitivity_gate.py`; file `evals/results/m1-shipped-fixture-topology.json`.** It
imports `_build_fixture` (a read — `fusion_gate.py` stays byte-untouched), reads the edge set
**off the graph** (`topology_source == "graph.all_edges"`, never a literal), and captures the
derived union at each floor through the same `graph_store` spy the probe uses.

**This is #48's evidence, machine-checked.** A mechanism note only a human reads is the same
species of artifact as the pre-#41 claim this campaign exists to correct. Green means: the
derived-membership channel is **structurally absent** on the shipped fixture — `{Z}` at every
floor, for every seed, because all three competitors share one phantom and
`fetch_width = max(k, FETCH_WIDTH_FLOOR)` always admits `N1`. The last conjunct
(`union length > 0`) prevents a **dead walk** from masquerading as floor-invariance.

**It can fail:** if the shipped fixture ever gains distinct phantoms, AC-374 reddens and #48's
framing must be **redone** rather than inherited. `CHANGE/issue-48-mechanism-note.md` is the
narrative sibling; **this criterion is the assertion.**

### AC-375 (event-driven) — ADDED (K-C-N2 — AC-317's positive-capability control, correctly directed)

GIVEN the same weight-discriminating fixture AC-317 uses
WHEN it is evaluated across a wide weight band spanning two orders of magnitude
THEN the gate shall produce at least two distinct outcomes across that band
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/wd-wideband-control.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run(seed_label='0', weights=[0.5, 1.0, 100.0]), '/app/evals/results/wd-wideband-control.json')" && jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.cells | type == "array") and ((.cells | length) == 3) and (([.cells[].weight] | sort) == [0.5, 1.0, 100.0]) and (all(.cells[]; (.weight_readback == .weight) and (.outcome | type == "string"))) and (([.cells[].outcome] | unique | length) >= 2)' evals/results/wd-wideband-control.json
```
**PASS = exit 0.** This is rule (f) **Form 2 (responsiveness)**, and it is the correct direction:
AC-317's routing outcome is *"fewer than 2 distinct outcomes across `{0.90, 0.95, 1.00}`"*, which
is reported as the **#55 degeneracy finding**. Without this control, that report cannot be
distinguished from *"my fixture is degenerate"*. `config.py:296-298` states that values above
1.0 re-create P1, so a **200x** swing that still produces one outcome **indicts the fixture, not
the weights** — and AC-317's negative may not be routed until this is green.

*`amend-02`'s audit cited D8's edge-severing perturbation here. That perturbation collapses the
outcome set to one — it demonstrates the **negative**. Rule (f) requires the **positive**. The
row was inverted and is corrected.*

### AC-376 (event-driven) — ADDED (K-C-N6 — the weight readback becomes a real pin)

GIVEN the weight-discrimination module's `build_aetheryte` factory
WHEN a test independently constructs an instance at each measured weight
THEN the instance's own `fusion_weight_derived` shall equal the injected weight
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_weight_discrimination.py::test_weight_injection_reaches_instance -v
```
**PASS = exit 0.** Node name and the factory symbol `evals.weight_discrimination.build_aetheryte`
are **normative**. The node body asserts, for each of `{0.5, 0.90, 0.95, 1.00, 100.0}`,
`build_aetheryte(w_derived=w).fusion_weight_derived == w` — **read off the instance the test
built itself**.

AC-317's `weight_readback == .weight` conjunct compares two fields the same module emits, so a
module that assigns `weight_readback = weight` passes it; the rule *"read it off the `Aetheryte`
instance"* was prose. This is the **AC-346 pattern** (`assert aetheryte.recall_active_only is
True` **inside the test body**), which Kupo correctly identified as the one that is real. It
fails on the defect it names: a factory that builds the instance without threading the weight.

---

## 3. Wave 1 exit — release v2.0.2

### AC-332 (event-driven) — REPLACED (K-C-N3 missing `cd`; F-2 red-evidence shape)
*(amend-01's part 3 opened `checker-redcheck.json` and `red-evidence.json` by **bare relative
name** under a file-wide MAIN convention, and did `json.load(...)['gates']` — which raises
`TypeError: list indices must be integers or slices, not str` on the artifact the W-ENTRY
implementer actually wrote, a **top-level array** named `red-evidence-wentry.json`. Measured this
pass.)*

GIVEN the v2.0.2 release candidate and the per-unit maker red-evidence shards
WHEN the checker independently re-breaks each of the five artifacts on an axis differing from the maker's
THEN each shall go red under the checker's own perturbation with the patch, command, tree SHA, non-zero exit, output tail and restore proof recorded
VERIFY: four parts, all required — run the command blocks below; PASS exactly as stated.

(0) shard schema plus consolidation, and no shard silently dropped:
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && jq -s -e 'all(.[]; type == "array" and (length > 0) and (all(.[]; (.gate | type == "string") and (.axis | type == "string") and (.perturbation_patch | type == "string") and ((.perturbation_patch | length) > 0) and (.command | type == "string") and (.tree_sha | type == "string") and (.exit_code | type == "number") and (.exit_code != 0) and (.output_tail | type == "string") and (.restore.exit_code == 0))))' red-evidence-w*.json && jq -s '{batch: "v2.0.2", gates: add}' red-evidence-w*.json > red-evidence.json && test "$(jq '.gates | length' red-evidence.json)" = "$(jq -s 'map(length) | add' red-evidence-w*.json)"
```
(1) the checker's own five rows:
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && jq -e '(type == "object") and (.gates | type == "array") and ((.gates | length) == 5) and (([.gates[].gate] | unique | length) == 5) and (([.gates[] | select((.perturbation_patch | type == "string") and ((.perturbation_patch | length) > 0) and (.command | type == "string") and (.tree_sha | type == "string") and (.axis | type == "string") and (.exit_code | type == "number") and (.exit_code != 0) and (.output_tail | type == "string") and (.restore.exit_code == 0))] | length) == 5)' checker-redcheck.json
```
(2) the five gates are the right five:
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && jq -e '(type == "object") and (([.gates[].gate] | sort) == ["corpus-scaling","cross-layer","entrypoint","floor-sensitivity","weight-discrimination"])' checker-redcheck.json
```
(3) anti-replay, **with the `cd` K-C-N3 found missing**:
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && python3 -c "
import json
c = json.load(open('checker-redcheck.json'))['gates']
m = json.load(open('red-evidence.json'))['gates']
mp = {g['perturbation_patch'] for g in m}
dup = [g['gate'] for g in c if g['perturbation_patch'] in mp]
assert not dup, ('replayed maker patch', dup)
assert len(c) == 5, ('expected 5 checker rows', len(c))
print('ok', len(c))
"
```
**PASS = exit 0 on all four.**

**Producer (rule (i)).** Maker side: each unit writes
`CHANGE/red-evidence-<unitslug>.json`, a **top-level array** of eight-key entries —
`red-evidence-wentry.json` is conformant as written and needs **no change**. Consolidated side:
part 0's `jq -s` is the **producing step** for `red-evidence.json`; the glob `red-evidence-w*.json`
matches every shard and **cannot match its own output**. *Verified this pass: the shipped shard
exits 0 against part 0's schema, and the consolidation yields `{gates: [...]}` with 2 rows.*

**`jq -s -e` is load-bearing in part 0, not stylistic.** `jq -e 'pred' a.json b.json`
evaluates the filter **per input** and exits on the **last** output's truth value — measured this
pass: a **bad** shard followed by a good one exits **0**. Slurping and asserting
`all(.[]; …)` is the only form that fails on any shard. *(Found by executing my own criterion;
it is the same species of defect this amendment exists to remove, and it was in the new surface.)*

Part 0's final `test` is the anti-drop guard: consolidated row count **must equal** the sum of
shard lengths, so a shard omitted from the glob cannot silently shrink the anti-replay corpus —
which would make part 3 pass by having nothing to compare against. Maker row counts are
deliberately **unconstrained** (more axes are better); only the **shape** is fixed. The `== 5`
constraints apply to `checker-redcheck.json` only.

**Reversal (D8)** unchanged: on an independent collision of minimal patches, the checker
documents it and substitutes a second axis-distinct perturbation. The requirement is **axis
independence**, not patch-text novelty.

---

## 4. Wave 2 — behaviour

### AC-345 (event-driven) — REPLACED (K-C-N4 filename, K-C-N7 non-mechanical XFAIL, K-C-N8 checkout hygiene)

GIVEN a corpus whose top-`candidate_k` BM25 hits are all deprecated, with `recall_active_only=True`
WHEN recall runs on the recorded pre-fix commit and again on the released tree
THEN the node shall be green at the recorded SHA and reported XFAIL on the released tree
VERIFY: two parts, both required, both under global rule (h) — run the command blocks below; PASS exactly as stated.

(i) the commit-1 characterisation, re-run by the checker at the recorded SHA:
```
cd /home/rynaro/workspace/oss/agents/crystalium && test -z "$(git status --porcelain)" && ORIG="$(git rev-parse HEAD)" && SHA="$(jq -r '.commit1_sha' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/ac345-prefix-evidence.json)" && test -n "$SHA" && test "$SHA" != "null" && git rev-parse --verify "$SHA^{commit}" && git checkout --detach "$SHA" && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_prefix_baseline_starves_active_hits -v ; RC=$? ; cd /home/rynaro/workspace/oss/agents/crystalium && git checkout --detach "$ORIG" && test "$(git rev-parse HEAD)" = "$ORIG" && test "$RC" = "0"
```
(ii) the sentinel on the release tree, asserted on the **summary line**:
```
cd /home/rynaro/workspace/oss/agents/crystalium && test -z "$(git status --porcelain)" && OUT="$(docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_prefix_baseline_starves_active_hits -q --tb=no -rX)" && echo "$OUT" | grep -qE '[0-9]+ xfailed' && test "$(echo "$OUT" | grep -cE '[0-9]+ passed' || true)" = "0"
```
**PASS = exit 0 on both.**

**Producer (rule (i)): W-44's commit-1 characterisation step writes
`CHANGE/ac345-prefix-evidence.json` with keys `commit1_sha`, `commit2_sha`, `node`,
`recorded_at`, `recorded_by`, `prefix_summary`.** `spec.amend-01.md` §B.4.4's `.txt` spelling is
**STRUCK** — the criterion `jq`s the file, so `.json` is normative. The `test -n "$SHA"` guard
stops an empty value being handed to `git checkout` (K-C-N4's downstream failure).

Part (i) obeys **rule (h)** in full: dirty-tree refusal, recorded original, unconditional restore
via `;` **even when pytest fails**, and an asserted restore before PASS. Part (ii) then runs on
the tree part (i) restored — under `amend-01`'s ordering it ran at the **commit-1 SHA**, where
the node is unmarked and green, and would have reported PASS for the wrong reason.

Part (ii) is now **mechanical** (K-C-N7): `pytest -q` returns **0 for a PASS and for an XFAIL
alike**, so *"Not PASS, not FAIL: XFAIL"* was an eyeball on the summary. It is now a positive
`grep -qE '[0-9]+ xfailed'` plus a rule-(e)-shaped zero-count guard on `passed`. The marker is
`@pytest.mark.xfail(strict=True, reason="pre-#44 starvation characterisation; XPASS = starvation regression (#44)")`,
landed in the **same commit** as the `retrieve.py` fix; **XPASS ⇒ strict ⇒ suite RED**.

### AC-348 (ubiquitous) — REPLACED (FORGE fence-amend `composition_ruling`; openly amends D3)
*(was: one `<= 1` top-up budget for all paths. FORGE's fence ruling replaces the head-only
composition on the strict-subset path with a **per-fetch** widen rule, which `<= 1` cannot
express.)*

GIVEN the Option A fetch shape with the per-fetch status-aware top-up
WHEN the `bm25_search` call-count spy is read for the fixture's path
THEN the observed call count shall equal that path's exact stated budget
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_retrieve_layer_merge.py -v -k "call_budget_per_path"
```
**PASS = exit 0** with **three** parametrised cases collected. Budgets, stated per path in D1's
terminal-branch restatement shape — **each an exact bound, never one number with a caveat:**

| path | fetch-shape baseline | top-up budget | total `bm25_search` calls |
|---|---|---|---|
| default (`layers=None`, `_ALL_LAYERS`) | 1 global | **<= 1** | **<= 2** |
| single-layer | 1 filtered | **<= 1** | **<= 2** |
| strict subset, `L = len(target_layers)` | `1 + backstop_count`, `backstop_count <= L` | **<= 1 + L** | **<= 2 + L + backstop_count**, hence **<= 2 + 2L** |

**The `<= 1` clause is NOT relaxed.** It is retained unchanged on the two paths D3 wrote it for,
and replaced by an exact per-path bound on the path it cannot express — because the top-up now
widens **each fetch that is individually censored-and-dirty, at most once per fetch, never a
widen decided by another fetch's signal** (K-B13(c) applied per fetch). **Relaxing this budget or
AC-355 to fit an implementation is forbidden** (fence-amend `reversal_condition`); the ruled
fallback is explicit subset-path suppression.

### AC-350 (event-driven) — REPLACED (K-C-N14 — the T3-variant's True branch was in no criterion)
*(was: three parametrised cases; §B.5.2 states four expected True-branch values and AC-354
collects four on the False branch, so the T3-variant's `exclude_seeds=True` value was asserted
nowhere)*

GIVEN `exclude_seeds=True`, the default
WHEN `neighbor_expand` and `decaying_walk` run on T1, T2, T3 and the T3-variant
THEN the returned sets and weights shall be byte-identical to `b7f1a47` on all four topologies
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py -v -k "exclude_seeds_default_is_byte_identical"
```
**PASS = exit 0**, with **four** parametrised cases collected.

| topology | graph | call | expected |
|---|---|---|---|
| **T1** | seeds `{S1,S2}`; `S1->S2`, `S1->N1` | `neighbor_expand(["S1","S2"], depth=1)` | `{"N1"}` |
| **T2** | seeds `{S1,S2}`; `S1->M`, `M->S2`, `M->N2` | `neighbor_expand(["S1","S2"], depth=2)` | `{"M","N2"}` |
| **T3** | same as T2 | `decaying_walk(["S1","S2"], max_hops=2, decay=0.5)` | `{"M":0.5,"N2":0.25}` |
| **T3-variant** *(new)* | seeds `{S1,S2}`; single edge `S1->S2` | `decaying_walk(["S1","S2"], max_hops=2, decay=0.5)` | `{}` |

**The T3-variant case carries a mandatory liveness guard**, because its expected value is
**empty** and an empty result is exactly what a dead store returns: the node additionally asserts
`graph.node_count() == 2` and `len(graph.all_edges()) == 1` (the §A.3 form). Without it the case
would pass on a kuzu error — K-B16's failure mode, in the one place an empty expectation invites
it. AC-354 asserts the same topology's False branch (`{"S2":0.5}`), so both branches of all four
topologies are now covered.

### AC-352 (event-driven) — AMENDED (rule (g))
Both parts of `spec.criteria.amend-01.md`'s AC-352 stand **unchanged in substance**; each is
re-plumbed onto rule (g)'s chain.

GIVEN seed exclusion relaxed on the retrieval path
WHEN the DP-1(b) re-check and its `w_derived = 100.0` control run under freshly minted nonces
THEN no derived-only record shall outrank a record backed by two base arms
VERIFY: two parts, both required — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/wd-dp1-recheck.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run_dp1_recheck(), '/app/evals/results/wd-dp1-recheck.json')" && jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.p1_recreated == false) and (.w_derived == 1.0) and (.derived_only_rank | type == "number") and (.two_base_arm_rank | type == "number") and (.derived_only_rank > .two_base_arm_rank)' evals/results/wd-dp1-recheck.json
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/wd-dp1-control.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run_dp1_recheck(w_derived=100.0), '/app/evals/results/wd-dp1-control.json')" && jq -e --arg n "$NONCE" '(type == "object") and (.run_nonce == $n) and (.p1_recreated == true) and (.w_derived == 100.0) and (.derived_only_rank < .two_base_arm_rank)' evals/results/wd-dp1-control.json
```
**PASS = exit 0 on both.** Part (ii) remains the plan's cleanest rule-(f) Form-1 instance
(`config.py:296-298`'s stated ceiling used as a mechanical positive control): **a fixture that
cannot re-create P1 on demand cannot falsify its absence**, so without it part (i)'s `false` is
not evidence and **S-1 cannot be cleared**.

### AC-356 (event-driven) — AMENDED (fence breach condition 8)
Command and node name unchanged from `spec.criteria.amend-01.md`. One addition to its meaning.

GIVEN the #44 corpus with `recall_active_only=False`
WHEN recall runs
THEN the top-up shall issue zero additional `bm25_search` calls
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_topup_inert_when_active_only_off -v` — PASS = exit 0.

`_is_active` returns unconditionally `True` when the flag is off (`retrieve.py:573-574`), so
`n_inactive_observed == 0` and **no fetch is ever dirty** — inertness is structural, not
conditional. **This node is now also the mechanical detector for fence breach condition 8**
(*"The top-up issuing any additional `bm25_search` call when `recall_active_only` is False"*):
its spy asserts **zero** additional calls, so a breach reddens it. **Reversal (D6)** unchanged.

### AC-377 (event-driven) — ADDED (K-C-N13 — the censoring signal is the fetch actually performed)

GIVEN Option A's strict-subset path, where `sparse_ranking` holds a post-filtered head plus a backstop tail
WHEN recall runs once with the global fetch censored and once with it uncensored
THEN the selectivity boost shall be suppressed exactly when the global fetch that produced the head was censored
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_retrieve_layer_merge.py::test_subset_censoring_signal_is_the_global_fetch -v
```
**PASS = exit 0** with **two** parametrised cases collected. Node name is **normative**.

- **(i) censored.** `E = 4 * candidate_k` episodic rows plus `S = candidate_k` semantic rows, all
  matching; `layers=["semantic","procedural"]`. The global call requests
  `candidate_k * len(_ALL_LAYERS)` and receives that many rows. Assert
  `explain.fusion.selectivity == 0.0`, `explain.fusion.w_sparse == 1.0`,
  `explain.fusion.n_sparse_cap == candidate_k * 4`,
  `explain.fusion.raw_n_sparse == candidate_k * 4`, and
  `explain.fusion.sparse_fetch_shape == "global+backstop"`.
- **(ii) uncensored** — the rule-(f) Form-1 positive. A corpus smaller than the global request on
  the same 2-layer subset. Assert `explain.fusion.selectivity > 0.0` and
  `explain.fusion.w_sparse > 1.0`.

**Why it can fail.** `retrieve.py:597-598` computes `cap = candidate_k * len(target_layers)` and
`raw_n_sparse = len(sparse_ranking)` — coherent only under today's per-layer loop. Under Option A
`sparse_ranking` is *post-filtered head + backstop tail*, i.e. **not the fetch that produced the
signal**. Leaving `:598` alone while `cap` becomes the global request makes the censoring test
**unreachable**, so `:256`'s guard never fires and the ratio branch stays permanently live — the
#38 boost applied to a fetch that **was** globally censored, which is exactly what C-7/DP-9
forbid (`retrieve.py:230-237`). Case (i) reddens on that implementation.

*(Direction note, recorded for the audit: the checker's summary of this defect said the boost
would be "silently disabled". `retrieve.py:256-259` sets `selectivity = 0.0` **when censored**,
so an inert guard leaves the boost **always on**. The finding is real and blocking; its stated
direction was inverted, and it matters because the two failure modes have opposite `explain`
symptoms.)*

**W-45 owns the enabling change** (`spec.amend-03.md` §10, §15.4): capture the **per-fetch** raw
counts at the call sites, pass the head's to `resolve_sparse_weight`, and add the additive
`explain.fusion` fields `raw_n_sparse`, `sparse_fetch_shape` and `fetches[]`. Measured this pass:
`explain.fusion` currently exposes `n_sparse_cap`, `selectivity`, `w_sparse` and a **resolved**
`n_sparse` — **no raw count**, so this signal is unobservable from outside today. **Reversal
(D3)** carried unchanged: pathological behaviour reopens **cap semantics**, never the score-space
merge.

### AC-378 (event-driven) — ADDED (FORGE D3 fidelity — the dense half was ungated)

GIVEN a dense stub that honours `layer_filter` exactly as `dense_search` does
WHEN recall runs with `layers=["semantic","procedural"]` on a corpus whose global dense top is dominated by excluded layers
THEN the planted semantic target shall be present in `dense_ranking`
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_retrieve_layer_merge.py::test_subset_layer_dense_mirror_no_regression -v
```
**PASS = exit 0.** Node name is **normative**.

D3 mandates the three-case fetch shape for **both arms** — *"sparse shown; dense mirrors it"* —
and AC-355 pins the dense arm **empty**, so as the plan stood the dense half shipped with **no
gate at all**. The maker's single-axis rationale for AC-355's pin is sound; the correct response
is a **second node**, not dropped coverage. The stub is a `side_effect` callable returning only
rows of the requested layer, and the global ordering when `layer_filter is None`
(`vector.py:174-199` supports `layer_filter=None`), so it mirrors the real contract rather than
inventing one. **RED on a naive global+post-filter dense implementation; GREEN only when the
dense backstop exists.** AC-355 keeps its empty-dense pin: **two nodes, one axis each.**

**Fallback, recorded rather than discovered later.** If the stub cannot express the contract
without a real vector store, W-45 records the dense half as **ungated** in the #45 closing
comment, quoting **D3's reversal condition** — *"If `test_subset_layer_recall_no_regression`
cannot be made green without violating the `bm25_search` fence, W-45 stops and returns to FORGE
with the failing construction"* — and returns to FORGE. **S-13 step 5 governs either way: a dense
node that cannot fail is deleted, not merged.**

### AC-379 (event-driven) — ADDED (FORGE fence-amend: the MANDATED subset-composition node)

GIVEN the K-N12 regime — an excluded-layer-dominated censored head with a deprecated-censored target-layer backstop call above a planted active target, `recall_active_only=True`
WHEN recall runs with a 2-layer strict subset
THEN the planted active target shall be recovered into `result.records`
VERIFY: two parts, both required — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_subset_status_topup_recovers_active_hits -v
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_topup_counter_matches_observed_calls -v
```
**PASS = exit 0 on both.** Both node names are **normative**;
`test_subset_status_topup_recovers_active_hits` is mandated verbatim by FORGE's fence-amend
`composition_ruling`, which assigns its AC id to this amendment.

**Part 1 is the discriminating gate: RED under head-only, GREEN only with the backstop-locus
widen.** The starvation locus on a strict subset is a deprecated-censored **per-layer backstop**
call; a wider global head returns mostly excluded-layer rows the post-filter discards. Before
this node existed the strict-subset composition had **no criterion that could fail on it** —
AC-346/AC-347 are default-path, AC-355 measures layer coverage, AC-348 counts calls.

**Part 2 is F-V3 counter honesty**, using only the fields the ruling authorises:
`explain.fusion.sparse_topup = {fired, widened_fetches: [{fetch, k_initial, k_final,
n_inactive_observed}]}` must match the **spy's observed `bm25_search` call sequence** exactly —
one entry per observed widened call, same locus, same `k_final`, with
`k_final == min(k_initial + n_inactive_observed, HARD_TOPUP_CEILING)` and
`fired == ((widened_fetches | length) > 0)`. A counter that stays truthful about work that
produced nothing is the **#36 F-V3 defect**, and head-only would have shipped exactly that
(`fired: true`, recovery structurally absent) **as designed behaviour**. Part 2 also detects
fence breach condition 7 (a second widen of one fetch, or a loop) as an extra or unmatched entry.

**Ruled fallback, not softened:** if the fixture cannot discriminate, route to **S-13 with
explicit subset-path SUPPRESSION** — document the top-up as inert on strict subsets and file a
follow-up. **Never ship the subset-path behaviour unmeasured; never relax AC-348 or AC-355 to
fit.**

---

## 5. Wave 2 exit — release v2.1.0

### AC-361 (ubiquitous) — REPLACED (K-C-N8 — checkout hygiene)
`spec.criteria.amend-01.md`'s AC-361 substance (the `compare_wire.py` wire-compatibility
comparison) is unchanged. Its `git checkout` is brought under **global rule (h)**.

GIVEN the v2.1.0 release tree and the previous release ref
WHEN the wire comparison runs across the two trees
THEN the tool shall report no incompatible wire change with the original ref restored afterwards
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && test -z "$(git status --porcelain)" && ORIG="$(git rev-parse HEAD)" && git checkout --detach "$PREV_RELEASE_REF" && docker compose run --rm crystalium /app/.venv/bin/python scripts/compare_wire.py --baseline ; RC=$? ; cd /home/rynaro/workspace/oss/agents/crystalium && git checkout --detach "$ORIG" && test "$(git rev-parse HEAD)" = "$ORIG" && test "$RC" = "0" && docker compose run --rm crystalium /app/.venv/bin/python scripts/compare_wire.py --compare
```
**PASS = exit 0**, with the tree provably back at `$ORIG`. `compare_wire.py` remains the named
tool and its clean report remains the pass condition (K-N16). The dirty-tree refusal and the
unconditional restore are new: a criterion that leaves the tree at a foreign ref poisons every
criterion after it.

---

## 6. Wave 3 — disposition

### AC-372 (unwanted-behavior) — REPLACED (K-C2 — `git` does not exist in the container)
*(amend-01's part 2 ran `subprocess.run(['git','diff',...], check=True)` **inside** the
container. `shutil.which('git')` is `None` there — `Dockerfile:7` is `FROM python:3.12-slim` and
the only package install is `curl ca-certificates` — so `check=True` raises `FileNotFoundError`
and #47's disposition guard was a guaranteed false red.)*

**IF** `candidate_k` is changed without a recorded response curve
THEN the change shall carry an explicit unsupported-claim fence in its comment
VERIFY: two parts, both on the host — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && git rev-parse --verify b7f1a47^{commit}
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && python3 -c "
import subprocess, sys
d = subprocess.run(['git','diff','b7f1a47..HEAD','--','mcp-server/src/crystalium/aetheryte/retrieve.py'], capture_output=True, text=True, check=True).stdout
lines = [l for l in d.splitlines() if l[:1] in '+-' and not l.startswith(('+++','---'))]
touched = [l for l in lines if 'candidate_k' in l and l.startswith('+')]
if not touched:
    print('ok: candidate_k untouched'); sys.exit(0)
assert 'no shipped measurement validates' in d.lower(), 'candidate_k changed without the unsupported-claim fence'
print('ok: candidate_k changed WITH fence')
"
```
**PASS = exit 0 on both, with one of the two literal `ok:` outputs.** Part 1 is the anti-vacuity
guard (a bad ref fails here, not silently in part 2). Both parts run on the **host**: the check
is pure text over a git blob and imports nothing from the package, so container-only execution —
which exists to pin the *package's* runtime — is not weakened. Disposition unchanged:
**WONTFIX-with-rationale**, S-13 class (b), with a named reopen signal.

### AC-380 (ubiquitous) — ADDED (K-N14 / K-C-N15 — the ESL record itself)

GIVEN the ESL change record for this campaign, which lives in the nexus while its code lands in crystalium
WHEN the record and its cross-repo skip declaration are inspected
THEN the record shall carry a lifecycle state, a populated acceptance-check list and an explicit declaration of the code-state checks that cannot run
VERIFY: three parts, all required — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && jq -e '(type == "object") and (.esl_version == "1.1") and (.tier == "full") and ((.status == "in_progress") or (.status == "verified") or (.status == "archived")) and (.acceptance_checks | type == "array") and ((.acceptance_checks | length) >= 63) and (all(.acceptance_checks[]; (.id | type == "string") and (.verify_method | type == "string") and ((.verify_method | length) > 0))) and (.maker == "ramza") and (.checker == "kupo") and (.maker != .checker)' change.json
```
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && test -f spec.yaml && python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit('PyYAML absent on host; run this part where make schema runs')
d = yaml.safe_load(open('spec.yaml'))
for k in ('change_id','esl_version','tier','maker','checker','criteria_sha256','acceptance_checks','amendment_chain'):
    assert k in d, ('spec.yaml missing key', k)
assert d['tier'] == 'full', d['tier']
assert isinstance(d['acceptance_checks'], list) and len(d['acceptance_checks']) >= 63, len(d.get('acceptance_checks', []))
assert isinstance(d['amendment_chain'], list) and len(d['amendment_chain']) >= 3, d.get('amendment_chain')
print('ok')
"
```
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && jq -e '(type == "object") and (.record_repo | test("eidolons")) and (.code_repo | test("crystalium")) and (.code_base_ref | type == "string") and ((.code_base_ref | length) == 40) and (.has_code_in_record_repo == false) and (.skipped_checks | type == "array") and ((.skipped_checks | length) >= 2) and (([.skipped_checks[].check] | index("C3.code_state")) != null) and (all(.skipped_checks[]; (.reason | type == "string") and ((.reason | length) > 0) and (.compensating_control | type == "string") and ((.compensating_control | length) > 0)))' esl-cross-repo-skip.json
```
**PASS = exit 0 on all three.** **Producers (rule (i)): `change.json` — the release unit at each
lifecycle transition; `spec.yaml` — the maker, before the first tag; `esl-cross-repo-skip.json` —
W-HOP, Wave 0.**

**All three fail today**, measured by the checker via `mcp__tonberry__status`: `status:
proposed`, `acceptance_checks: []`, `drift_checked: false`, **C3 fail `full: missing spec.yaml`**.

**The cross-repo question, answered rather than absorbed.** The record lives in the **nexus**;
every line of code it plans lands in **crystalium**. ESL's code-state gates evaluate the repo the
record is in, so they **cannot observe this change's code at all**. `has_code: false` is
literally accurate for the nexus and materially misleading if left bare — **a false value that
happens to be true for the wrong reason is precisely the shape this campaign exists to remove**.
Part 3 therefore requires the skip to be **declared with its compensating control**
(AC-353/AC-363/AC-324 run `git` against the crystalium tree directly on explicit branch refs;
S-12's per-unit `comm -23` runs there too), so a reader can distinguish a check that was **not
applicable** from one that was **not run**. The ECM precedent in this repo — a record that sat
`in_progress` for five releases behind 164 green tests, whose never-run drift check found real
drift — is why this is a criterion and not a checklist line.

### AC-381 (unwanted-behavior) — ADDED (FORGE fence-amend: the nine breach conditions, made detectable)

**IF** any change breaches the `bm25_search` status-predicate fence
THEN the breach shall be detected mechanically before the release tag
VERIFY: five parts, all required, all on the host — run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && python3 -c "
import ast, subprocess, sys
def blob(ref, path):
    return subprocess.run(['git','show', ref + ':' + path], capture_output=True, text=True, check=True).stdout
STORE = ['mcp-server/src/crystalium/storage/relational.py','mcp-server/src/crystalium/storage/graph.py','mcp-server/src/crystalium/storage/vector.py']
# (2) no new public method on any storage class
for p in STORE:
    old = {n.name for n in ast.walk(ast.parse(blob('b7f1a47', p))) if isinstance(n, ast.FunctionDef) and not n.name.startswith('_')}
    new = {n.name for n in ast.walk(ast.parse(open(p).read())) if isinstance(n, ast.FunctionDef) and not n.name.startswith('_')}
    assert new <= old, ('breach 2: new public storage method', p, sorted(new - old))
# (3) no status/temporal predicate entering SQL on the read path
d = subprocess.run(['git','diff','b7f1a47..HEAD','--'] + STORE, capture_output=True, text=True, check=True).stdout
added = [l for l in d.splitlines() if l.startswith('+') and not l.startswith('+++')]
bad = [l for l in added if ('status' in l.lower() or 't_valid_to' in l.lower()) and ('where' in l.lower() or 'select' in l.lower())]
assert not bad, ('breach 3: status/temporal predicate in SQL', bad)
# (4) exactly one _is_active definition in the package
r = subprocess.run(['git','grep','-c','def _is_active','HEAD','--','mcp-server/src/crystalium/'], capture_output=True, text=True)
n = sum(int(l.rsplit(':',1)[1]) for l in r.stdout.splitlines() if l.strip())
assert n == 1, ('breach 4: _is_active defined ' + str(n) + ' times')
# (5) layers/episodic.py byte-identical
assert blob('b7f1a47','mcp-server/src/crystalium/layers/episodic.py') == open('mcp-server/src/crystalium/layers/episodic.py').read(), 'breach 5: layers/episodic.py edited'
# (6) both fence comments survive verbatim
cur = open('mcp-server/src/crystalium/aetheryte/retrieve.py').read()
for anchor in ('never a status predicate on the shared', 'applies no status predicate'):
    assert anchor in cur, ('breach 6: fence comment weakened or deleted', anchor)
print('ok')
"
```
**PASS = exit 0 and the literal output `ok`.**

FORGE's fence ALLOW carries **nine** breach conditions, each requiring a **fresh W-HOP before any
code**. Six of them had **no mechanical detector at all** — they were prose inside an artifact
the plan `jq`s for a *verdict word*. **A fence whose breaches are undetectable is the "gates are
where defects hide" pattern applied to a ruling.** Coverage map:

| breach | detector |
|---|---|
| 1 — `bm25_search` parameter, SQL or signature change | **AC-349** (its red-check must stay live) |
| 2 — new public storage method | **this criterion**, part 2 (AST, public names may only shrink or hold) |
| 3 — status/temporal predicate in SQL | **this criterion**, part 3 |
| 4 — a second `_is_active` definition | **this criterion**, part 4 (`git grep -c`, exactly one) |
| 5 — `layers/episodic.py:319` edited | **this criterion**, part 5 (byte-identity) |
| 6 — fence comment edited, weakened or deleted | **this criterion**, part 6 (both anchors survive) |
| 7 — multi-widen, loop refetch, or a cross-fetch widen decision | **AC-379 part 2** + **AC-348**'s exact per-path bound |
| 8 — top-up firing when the flag is off | **AC-356** (spy asserts zero additional calls) |
| 9 — censoring recompute reading anything but the fetch performed | **AC-377** (both directions) |

Runs on the **host** (`git` is absent from the container — K-C2) and imports nothing from the
package. **Any red here is a fence breach: STOP, re-hop to W-HOP, before any further code.**

---

## 7. Status index — `amend-03`

| status | criteria |
|---|---|
| **REPLACED AGAIN** (3) | AC-313, AC-321, AC-357 |
| **REPLACED** (12) | AC-305, AC-306, AC-316, AC-322, AC-332, AC-345, AC-348, AC-350, AC-358, AC-359, AC-361, AC-372 |
| **AMENDED** (6) | AC-310, AC-312, AC-314, AC-317, AC-352, AC-356 |
| **ADDED** (8) | AC-374, AC-375, AC-376, AC-377, AC-378, AC-379, AC-380, AC-381 |

`amend-02` left **55** criteria in force. `amend-03` replaces 15, amends 6, adds 8 ⇒ **63
criteria** in force after `amend-03`.
